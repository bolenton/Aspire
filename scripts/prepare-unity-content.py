#!/usr/bin/env python3
"""Stage story contracts. The Unity meadow has its own newly authored art and sound set."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Clients/Lantern.Unity/Assets/StreamingAssets"


def stage(source: Path, target: Path) -> int:
    count = 0
    for file in source.rglob("*"):
        if not file.is_file() or file.name.startswith(".") or file.suffix == ".meta":
            continue
        destination = target / file.relative_to(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, destination)
        count += 1
    return count


if __name__ == "__main__":
    stories = stage(ROOT / "StoryPacks", DESTINATION / "StoryPacks")
    stories += stage(ROOT / "Clients/Lantern.Unity/Content", DESTINATION / "StoryPacks")
    print(f"Staged {stories} story files. Meadow artwork and audio are maintained separately.")
