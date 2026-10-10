#!/usr/bin/env python3
"""Prints a CHANGELOG.md section for a release from the archived OpenSpec changes.

    python3 scripts/changelog.py 0.2.0 [--since v0.1.0] [--date 2026-10-10]

Lists every change directory added under openspec/changes/archive/ since the given git tag (all of
them when no tag is given), each with the top-level bullets of its proposal's "What Changes".
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

ARCHIVE = "openspec/changes/archive"


def archived_since(tag):
    if tag is None:
        return sorted(d for d in os.listdir(ARCHIVE) if os.path.isdir(os.path.join(ARCHIVE, d)))
    out = subprocess.run(["git", "diff", "--name-only", "--diff-filter=A", f"{tag}..HEAD", "--", ARCHIVE],
                         check=True, capture_output=True, text=True).stdout
    names = {path.split("/")[3] for path in out.splitlines() if path.count("/") >= 4}
    return sorted(names)


def what_changes(change_dir):
    path = os.path.join(ARCHIVE, change_dir, "proposal.md")
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8").read()
    match = re.search(r"^## What Changes\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not match:
        return []
    bullets = []
    for line in match.group(1).splitlines():
        if line.startswith("- "):
            bullets.append(line)
        elif bullets and line.startswith("  ") and line.strip():
            bullets[-1] += "\n" + line  # keep nested lines with their bullet
    return bullets


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--since", help="previous release tag")
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    args = parser.parse_args()

    lines = [f"## {args.version} — {args.date}", ""]
    changes = archived_since(args.since)
    if not changes:
        lines += ["No archived changes since the previous release.", ""]
    for change in changes:
        name = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", change)
        lines += [f"### {name}", ""] + (what_changes(change) or ["- (no summary in the proposal)"]) + [""]
    sys.stdout.write("\n".join(lines))


if __name__ == "__main__":
    main()
