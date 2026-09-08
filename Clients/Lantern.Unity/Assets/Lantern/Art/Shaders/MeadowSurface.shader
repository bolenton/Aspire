Shader "Lantern/Meadow Surface"
{
    Properties
    {
        [MainColor] _BaseColor("Color", Color) = (0.3,0.5,0.2,1)
        _Detail("Surface detail", Range(0,1)) = 0.2
        _Wind("Breeze", Range(0,1)) = 0
        _Water("Water", Range(0,1)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Cull Off
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            float _Detail, _Wind, _Water;
        CBUFFER_END
        struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
        struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half3 normalWS : TEXCOORD1; half fog : TEXCOORD2; };
        float3 Breeze(float3 p)
        {
            float weight = saturate(p.y * .7) * _Wind;
            p.x += sin(p.x*.55+p.z*.34+_Time.y*.9)*.065*weight;
            p.z += cos(p.x*.38+p.z*.51+_Time.y*.7)*.04*weight;
            return p;
        }
        float Hash(float2 p) { return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
        float Noise(float2 p)
        {
            float2 i=floor(p),f=frac(p); f=f*f*(3-2*f);
            return lerp(lerp(Hash(i),Hash(i+float2(1,0)),f.x),lerp(Hash(i+float2(0,1)),Hash(i+1),f.x),f.y);
        }
        Varyings Vertex(Attributes input)
        {
            Varyings output;
            output.positionWS=Breeze(TransformObjectToWorld(input.positionOS.xyz));
            output.positionCS=TransformWorldToHClip(output.positionWS);
            output.normalWS=TransformObjectToWorldNormal(input.normalOS);
            output.fog=ComputeFogFactor(output.positionCS.z);
            return output;
        }
        ENDHLSL
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            half4 Fragment(Varyings input, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                half3 normal=normalize(input.normalWS)*IS_FRONT_VFACE(face,1,-1);
                Light sun=GetMainLight(TransformWorldToShadowCoord(input.positionWS));
                half diffuse=saturate(dot(normal,sun.direction)*.65+.35);
                half shadow=lerp(.45,1,sun.shadowAttenuation);
                half3 fill=lerp(half3(.26,.29,.24),half3(.42,.49,.46),normal.y*.5+.5);
                float variation=(Noise(input.positionWS.xz*.65)-.5)*.32+(Noise(input.positionWS.xz*17)-.5)*.10;
                half3 base=_BaseColor.rgb*(1+variation*_Detail);
                half3 color=base*(fill+sun.color*diffuse*shadow*.73);
                color+=base*_Wind*saturate(dot(-normal,sun.direction))*.24;
                if (_Water>.5)
                {
                    float ripple=sin(input.positionWS.x*4+input.positionWS.z*2-_Time.y*.65)*sin(input.positionWS.z*6+_Time.y*.4);
                    float glint=smoothstep(.84,.96,ripple);
                    color=lerp(color,half3(.55,.81,.72),glint*.35);
                    half fresnel=pow(1-saturate(dot(normal,GetWorldSpaceNormalizeViewDir(input.positionWS))),3);
                    color=lerp(color,half3(.49,.70,.74),fresnel*.45);
                }
                return half4(MixFog(color,input.fog),1);
            }
            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex ShadowVertex
            #pragma fragment ShadowFragment
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            float3 _LightDirection, _LightPosition;
            float4 ShadowVertex(Attributes input) : SV_POSITION
            {
                float3 world=Breeze(TransformObjectToWorld(input.positionOS.xyz));
                float3 normal=TransformObjectToWorldNormal(input.normalOS);
                float3 direction=_LightDirection;
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                direction=normalize(_LightPosition-world);
                #endif
                float4 clip=TransformWorldToHClip(ApplyShadowBias(world,normal,direction));
                #if UNITY_REVERSED_Z
                clip.z=min(clip.z,UNITY_NEAR_CLIP_VALUE);
                #else
                clip.z=max(clip.z,UNITY_NEAR_CLIP_VALUE);
                #endif
                return clip;
            }
            half4 ShadowFragment() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
