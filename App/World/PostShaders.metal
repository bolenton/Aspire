#include <metal_stdlib>
using namespace metal;

// Final composite for the world post stack: rendered frame + two bloom taps
// + a depth-discontinuity outline. One kernel, one pass, writes the target
// exactly once — the "target written every frame" contract lives or dies on
// whoever dispatches this.
//
// Field order and packing must match `CompositeUniforms` in PostEffects.swift.
struct CompositeUniforms {
    float4 outlineColor;   // .a is outline opacity
    float  edgeThreshold;  // relative depth difference that counts as an edge
    float  outlineRadius;  // outline half-thickness in native pixels
    float  tightWeight;    // half-res bloom tap weight
    float  wideWeight;     // quarter-res bloom tap weight
    uint   outlineEnabled;
};

constexpr sampler bloomSampler(filter::linear, address::clamp_to_edge);

// RealityKit's nonAR depth is reverse-Z and non-linear; the reciprocal is
// proportional to view-space distance, which is what edge comparisons need.
static inline float viewDistance(float rawDepth) {
    return 1.0 / max(rawDepth, 1e-6);
}

kernel void postComposite(texture2d<float, access::read> source [[texture(0)]],
                          texture2d<float, access::sample> bloomTight [[texture(1)]],
                          texture2d<float, access::sample> bloomWide [[texture(2)]],
                          depth2d<float, access::read> depth [[texture(3)]],
                          texture2d<float, access::write> target [[texture(4)]],
                          constant CompositeUniforms &uniforms [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    const uint width = target.get_width();
    const uint height = target.get_height();
    if (gid.x >= width || gid.y >= height) { return; }

    float4 color = source.read(gid);
    float2 uv = (float2(gid) + 0.5) / float2(width, height);
    color.rgb += uniforms.tightWeight * bloomTight.sample(bloomSampler, uv).rgb;
    color.rgb += uniforms.wideWeight * bloomWide.sample(bloomSampler, uv).rgb;

    if (uniforms.outlineEnabled != 0) {
        // Cross-shaped depth comparison: an edge is a neighbor whose view
        // distance differs from ours by more than a distance-proportional
        // threshold, so near objects get contours while far terrain doesn't
        // dissolve into per-voxel scribbles. Sampling at `outlineRadius`
        // makes the line thicker without more taps.
        const int radius = max(1, int(uniforms.outlineRadius));
        const int2 bounds = int2(width - 1, height - 1);
        const float center = viewDistance(depth.read(gid));
        const int2 offsets[4] = { int2(radius, 0), int2(-radius, 0),
                                  int2(0, radius), int2(0, -radius) };
        float maxDifference = 0.0;
        for (int i = 0; i < 4; i++) {
            int2 tap = clamp(int2(gid) + offsets[i], int2(0, 0), bounds);
            float neighbor = viewDistance(depth.read(uint2(tap)));
            maxDifference = max(maxDifference, abs(neighbor - center));
        }
        const float threshold = uniforms.edgeThreshold * center;
        const float edge = smoothstep(threshold, threshold * 2.0, maxDifference);
        color.rgb = mix(color.rgb, uniforms.outlineColor.rgb,
                        edge * uniforms.outlineColor.a);
    }

    target.write(color, gid);
}
