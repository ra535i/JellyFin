#!/usr/bin/env python3
"""
SABnzbd post-processing script for Attack on Titan (Shingeki no Kyojin)
Renames files with absolute episode numbering (S3-55) to proper SxxExx format
so Sonarr can import them.

S3 absolute episode mapping: 38-59 → S03E01-S03E22
The Final Season (S4) absolute episode mapping: 60-94 → varies

Install: Copy to SABnzbd's scripts folder and select as post-processing script
"""

import os
import re
import sys
import shutil

# Mapping for Attack on Titan season packs with absolute numbering
# Format: (season_num, absolute_start, episode_count)
AOT_MAPPINGS = [
    # Season 1: eps 1-25 (absolute 1-25)
    # Season 2: eps 26-37 (absolute 26-37)
    # Season 3 Part 1: eps 38-49 (absolute 38-49) → S03E01-S03E12
    # Season 3 Part 2: eps 50-59 (absolute 50-59) → S03E13-S03E22
    # The Final Season: eps 60-94 (varies by release)
]

# Season 3 specific: absolute 38-59 → S03E01-S03E22
# S3-38 → S03E01, S3-39 → S03E02, ..., S3-59 → S03E22
S3_ABSOLUTE_OFFSET = 37  # absolute - 37 = episode number


def fix_attack_on_titan_filename(filename):
    """Rename AoT files with absolute numbering to proper SxxExx format."""
    base, ext = os.path.splitext(filename)
    if ext.lower() not in ('.mkv', '.mp4', '.avi'):
        return filename  # Not a video file, skip

    # Pattern: S3-55 or S3-14 or S4-88 etc
    m = re.search(r'S(\d+)-(\d+)', base)
    if not m:
        return filename

    season = int(m.group(1))
    absolute_ep = int(m.group(2))

    # Season 3: absolute 38-59 → S03E01-S03E22
    if season == 3 and 38 <= absolute_ep <= 59:
        ep_num = absolute_ep - S3_ABSOLUTE_OFFSET
        new_base = re.sub(
            r'S3-\d+',
            f'S03E{ep_num:02d}',
            base
        )
        # Clean up the rest of the garbage naming
        # Remove [Moozzi2] / [neko-kBaraka] style prefixes
        new_base = re.sub(r'^\[.*?\]\s*', '', new_base)
        # Clean up extra spaces
        new_base = re.sub(r'\s+', ' ', new_base).strip()
        return f'{new_base}{ext}'

    # Season 4 / The Final Season: varies
    if season == 4 and 60 <= absolute_ep <= 94:
        # The Final Season episodes are split weirdly
        # This needs per-release mapping since releases bundle multiple episodes
        # For now, try the same approach
        # S4-60 → S04E01? No, S04E01 is absolute 60
        # Actually for The Final Season, absolute 60 = S04E01
        final_season_offset = 59
        ep_num = absolute_ep - final_season_offset
        if 1 <= ep_num <= 28:
            new_base = re.sub(
                r'S4-\d+',
                f'S04E{ep_num:02d}',
                base
            )
            new_base = re.sub(r'^\[.*?\]\s*', '', new_base)
            new_base = re.sub(r'\s+', ' ', new_base).strip()
            return f'{new_base}{ext}'

    return filename


def fix_any_absolute_numbering(filename):
    """
    Generic fix for any show using absolute numbering.
    Looks for patterns like S3-14 or S03-14 and tries to map them.
    Without a known mapping, it can't auto-fix, but this catches AoT.
    """
    base, ext = os.path.splitext(filename)
    if ext.lower() not in ('.mkv', '.mp4', '.avi'):
        return filename

    # Try specific show fixes
    if 'shingeki' in base.lower() or 'kyojin' in base.lower() or 'attack' in base.lower():
        return fix_attack_on_titan_filename(filename)

    return filename


def main():
    """
    SABnzbd calls this script with these positional arguments:
    1 - path to the completed job directory
    2 - the original name of the NZB file
    3 - the path to the post-processing scripts directory
    4 - the status of the job (0 = success)
    5 - the category
    """
    if len(sys.argv) < 2:
        # Running standalone - process all files in current dir
        directory = os.getcwd()
    else:
        directory = sys.argv[1]

    if not os.path.isdir(directory):
        return 1

    renamed = 0
    for item in os.listdir(directory):
        item_path = os.path.join(directory, item)
        if not os.path.isfile(item_path):
            continue

        new_name = fix_any_absolute_numbering(item)
        if new_name != item:
            new_path = os.path.join(directory, new_name)
            shutil.move(item_path, new_path)
            renamed += 1
            print(f'Renamed: {item} → {new_name}')

    print(f'Renamed {renamed} file(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main())