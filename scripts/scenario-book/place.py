#!/usr/bin/env python3
"""Merge hand-written scenario data into placements/gh.json, keeping the file's layout (one
scenario a block, one map tile a line), so a diff shows only what changed.

    scripts/scenario-book/place.py                      rewrite the file as it is (a format check: no diff)
    scripts/scenario-book/place.py 77                   print scenario 77's entry
    scripts/scenario-book/place.py 77 '<json object>'   merge the object into scenario 77

In the object, a key that is a map tile ("n1b", "l3a", "empty") replaces that tile's entry under
"tiles" (null removes it); any other key ("goal", "rules", "notes", "locks", …) replaces that key of
the scenario (null removes it). To add to a list — one more rule, one more note — pass the whole
list. Every key is documented in docs/scenario-book/README.md.

    place.py 77 '{"n1b": {"markers": {"a": [[3, 6], [4, 6]]}}, "plates": ["a"]}'

Afterwards: swift test --filter 'ScenarioPlacementTests|ScenarioSpecialRuleTests'
"""
import collections, json, os, re, sys

PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                    "GlavenGame", "Resources", "ScenarioMaps", "placements", "gh.json")
TILE = re.compile(r"^([a-z]\d+[a-z]|empty)$")

def dump(value):
    """Compact JSON with the text as it reads (×, −, ’), not as escapes."""
    return json.dumps(value, ensure_ascii=False)

def main():
    data = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    if len(sys.argv) > 2:
        number, new = sys.argv[1], json.loads(sys.argv[2], object_pairs_hook=collections.OrderedDict)
        entry = data.setdefault(number, collections.OrderedDict(tiles=collections.OrderedDict()))
        tiles = entry.setdefault("tiles", collections.OrderedDict())
        for key, value in new.items():
            target = tiles if TILE.match(key) else entry
            if value is None:
                target.pop(key, None)
            else:
                target[key] = value
        entry.move_to_end("tiles")   # the tiles close the block
    lines = ["{"]
    numbers = sorted(data, key=int)
    for i, number in enumerate(numbers):
        entry = data[number]
        head = "".join(f'"{key}": {dump(value)}, ' for key, value in entry.items() if key != "tiles")
        lines.append(f'  "{number}": {{{head}"tiles": {{')
        tiles = sorted(entry.get("tiles", {}))
        for j, tile in enumerate(tiles):
            lines.append(f'    "{tile}": {dump(entry["tiles"][tile])}' + ("," if j < len(tiles) - 1 else ""))
        lines.append("  }}" + ("," if i < len(numbers) - 1 else ""))
    lines.append("}")
    with open(PATH, "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")
    json.load(open(PATH, encoding="utf-8"))
    if len(sys.argv) > 1:
        print(json.dumps(data.get(sys.argv[1]), indent=1, ensure_ascii=False)[:4000])

if __name__ == "__main__":
    main()
