#!/usr/bin/env python3
"""
SABnzbd post-processing script for Attack on Titan (Shingeki no Kyojin)
Renames files with absolute episode numbering (S3-55) to proper SxxExx format
so Sonarr can import them.

S3 absolute episode mapping: 38-59 → S03E01-S03E22
The Final Season (S4) absolute episode mapping: 60-94 → S04E01-S04E28

Install: Copy to SABnzbd's scripts folder and select as post-processing script
"""

import os
import re
import sys
import shutil

# Season 3: absolute 38-59 → S03E01-S03E22
S3_ABSOLUTE_OFFSET = 37  # absolute - 37 = episode number


def _resolve_absolute_ep(base):
    """Extract the true absolute episode number from various AoT naming formats.

    Moozzi2 standard:    S3-14 [ 51 ]           → absolute 51
    Moozzi2 multi-ep:    The Final Season-30 END [ 91-94 ] → first ep 91
    neko-kBaraka:        S3 - 55                → absolute 55
    """
    # Moozzi2 multi-episode pack: "The Final Season-30 END [ 91-94 ]"
    m_multi = re.search(r'\[\s*(\d+)\s*-\s*(\d+)\s*\]', base)
    if m_multi:
        return int(m_multi.group(1))  # Return first episode in the range
    # Moozzi2 single: S3-14 [ 51 ]
    m_mooz = re.search(r'S3-\d+\s*\[\s*(\d+)\s*\]', base)
    if m_mooz:
        return int(m_mooz.group(1))
    # Standard: S3-55 or S3 - 55
    m_std = re.search(r'S(\d+)\s*-\s*(\d+)', base)
    if m_std:
        return int(m_std.group(2))
    return None


def fix_attack_on_titan_filename(filename):
    """Rename AoT files with absolute numbering to proper SxxExx format."""
    base, ext = os.path.splitext(filename)
    if ext.lower() not in ('.mkv', '.mp4', '.avi'):
        return filename

    absolute_ep = _resolve_absolute_ep(base)
    if absolute_ep is None:
        return filename

    # Season 3: absolute 38-59 → S03E01-S03E22
    if 38 <= absolute_ep <= 59:
        ep_num = absolute_ep - 37
        new_base = re.sub(r'S3\s*-\s*\d+', f'S03E{ep_num:02d}', base)
        new_base = re.sub(r'^\[.*?\]\s*', '', new_base)
        new_base = re.sub(r'\s+', ' ', new_base).strip()
        return f'{new_base}{ext}'

    # The Final Season: absolute 60-94 → S04E01-S04E28
    if 60 <= absolute_ep <= 94:
        ep_num = absolute_ep - 59
        if 1 <= ep_num <= 28:
            new_base = re.sub(r'S4\s*-\s*\d+', f'S04E{ep_num:02d}', base)
            new_base = re.sub(r'^\[.*?\]\s*', '', new_base)
            new_base = re.sub(r'\s+', ' ', new_base).strip()
            return f'{new_base}{ext}'

    return filename


def fix_any_absolute_numbering(filename):
    """Route to show-specific fixers."""
    base, ext = os.path.splitext(filename)
    if ext.lower() not in ('.mkv', '.mp4', '.avi'):
        return filename

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