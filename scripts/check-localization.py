#!/usr/bin/env python3
"""Checks the string catalogs against the strings the compiler extracted from the sources.

Run after a build:  python3 scripts/check-localization.py [DerivedDataPath]

Fails when a string used in code is missing from Localizable.xcstrings, when a catalog entry has
no Russian translation, or (as a warning) when a catalog entry is no longer used.
"""
import glob
import json
import sys

derived = sys.argv[1] if len(sys.argv) > 1 else "build/DerivedData"
pattern = f"{derived}/Build/Intermediates.noindex/kRecord.build/Debug/kRecord.build/Objects-normal/arm64/*.stringsdata"

used = set()
for path in glob.glob(pattern):
    for table, entries in json.load(open(path)).get("tables", {}).items():
        if table == "Localizable":
            used.update(entry["key"] for entry in entries)
if not used:
    sys.exit("no .stringsdata files found: build the app first")

problems = 0
catalog = json.load(open("kRecord/Localizable.xcstrings"))["strings"]
for key in sorted(used - catalog.keys()):
    print(f"MISSING in catalog: {key!r}")
    problems += 1
for key in sorted(catalog.keys() - used):
    print(f"warning: unused catalog entry: {key!r}")


def check_russian(name, strings):
    global problems
    for key, entry in sorted(strings.items()):
        unit = entry.get("localizations", {}).get("ru", {}).get("stringUnit")
        if not unit or unit.get("state") != "translated" or not unit.get("value", "").strip():
            print(f"UNTRANSLATED in {name}: {key!r}")
            problems += 1


check_russian("Localizable.xcstrings", catalog)
check_russian("InfoPlist.xcstrings", json.load(open("kRecord/InfoPlist.xcstrings"))["strings"])

print(f"{len(used)} strings used, {len(catalog)} in catalog, {problems} problem(s)")
sys.exit(1 if problems else 0)
