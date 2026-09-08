#!/usr/bin/env python3
"""Rebuild the meadow's new sound set from documented, licensed source recordings."""
import argparse
import hashlib
import json
import shutil
import subprocess
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'Clients/Lantern.Unity/Assets/StreamingAssets/Meadow'
SOURCES = {
    'park-birds.wav': 'https://opengameart.org/sites/default/files/park_ambience_birds.wav',
    'park-river.wav': 'https://opengameart.org/sites/default/files/park_ambience_river.wav',
    'childhood.mp3': 'https://www.scottbuckley.com.au/library/wp-content/uploads/2019/01/sb_childhood.mp3?download=1',
    'kenney-impact.zip': 'https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip',
}


def acquire(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name, url in SOURCES.items():
        target = directory/name
        if target.exists():
            continue
        request = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0', 'Accept': '*/*',
            'Referer': 'https://www.scottbuckley.com.au/library/childhood/'})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        if len(data) < 10000:
            raise RuntimeError(f'Download was unexpectedly small: {name}')
        temporary = target.with_suffix(target.suffix+'.download')
        temporary.write_bytes(data)
        temporary.replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true', help='Acquire missing original recordings')
    parser.add_argument('--sources', type=Path, default=ROOT/'.artifacts/source-audio')
    args = parser.parse_args()
    ffmpeg = shutil.which('ffmpeg') or '/usr/local/bin/ffmpeg'
    if args.download:
        acquire(args.sources)
    for name in SOURCES:
        if not (args.sources/name).is_file():
            raise FileNotFoundError(f'{name} is missing. Use --download or provide --sources.')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Extract only the recordings that this game uses, never arbitrary archive paths.
    pack = args.sources/'kenney-impact/Audio'
    pack.mkdir(parents=True, exist_ok=True)
    names = [f'footstep_grass_00{i}.ogg' for i in range(4)] + ['impactBell_heavy_001.ogg','impactBell_heavy_003.ogg']
    with zipfile.ZipFile(args.sources/'kenney-impact.zip') as archive:
        for name in names:
            (pack/name).write_bytes(archive.read('Audio/'+name))
        credits = OUTPUT/'Credits'
        credits.mkdir(exist_ok=True)
        (credits/'Kenney.txt').write_bytes(archive.read('License.txt'))

    def convert(source, name, filters, stereo=False):
        subprocess.run([ffmpeg,'-v','error','-y','-i',str(source),'-af',filters,
                        '-ar','44100','-ac','2' if stereo else '1',str(OUTPUT/name)], check=True)

    def ambience(source, name, start, loudness, stereo):
        graph = (f'[0:a]atrim={start}:{start+34},asetpts=PTS-STARTPTS,asplit[a][b];'
                 '[a]atrim=0:2[head];[b]atrim=2:34,asetpts=PTS-STARTPTS[body];'
                 f'[body][head]acrossfade=d=2,loudnorm=I={loudness}:TP=-8:LRA=8[out]')
        subprocess.run([ffmpeg,'-v','error','-y','-i',str(source),'-filter_complex',graph,
                        '-map','[out]','-ar','44100','-ac','2' if stereo else '1',str(OUTPUT/name)],check=True)

    ambience(args.sources/'park-birds.wav','Birds.wav',10,-25,True)
    ambience(args.sources/'park-river.wav','River.wav',5,-28,False)
    for i in range(4):
        convert(pack/f'footstep_grass_00{i}.ogg',f'Footstep{i}.wav','lowpass=f=3200,volume=0.55,afade=t=in:d=0.012')
    convert(pack/'impactBell_heavy_001.ogg','Bell.wav','lowpass=f=3600,volume=0.3,afade=t=in:d=0.012,apad=pad_dur=1')
    convert(pack/'impactBell_heavy_003.ogg','Acorn.wav','lowpass=f=3200,volume=0.25,afade=t=in:d=0.015,apad=pad_dur=4')
    convert(pack/'impactBell_heavy_001.ogg','Oak.wav','asetrate=33075,aresample=44100,lowpass=f=2400,volume=0.15,afade=t=in:d=0.02,apad=pad_dur=5')
    subprocess.run([ffmpeg,'-v','error','-y','-i',str(args.sources/'childhood.mp3'),
                    '-af','loudnorm=I=-25:TP=-8:LRA=9,afade=t=in:d=3',
                    '-ar','44100','-ac','2','-b:a','160k',str(OUTPUT/'MeadowScore.mp3')],check=True)
    manifest = {name:{'source':url,'sha256':hashlib.sha256((args.sources/name).read_bytes()).hexdigest()} for name,url in SOURCES.items()}
    (OUTPUT/'Credits/SourceRecordings.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Prepared the new meadow score, ambience, foley and bell cues.')


if __name__ == '__main__':
    main()
