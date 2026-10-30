"""Summarise playtest-bot runs (play.mjs JSON output) against the grind budget. Kid time ~ bot time x 2.5."""
import json
import sys

KEYS = ['first_freeze', 'first_bank', 'first_coins_spent', 'first_rare_pet', 'forest_unlocked', 'first_new_zone']
for path in sys.argv[1:]:
    try:
        d = json.load(open(path))
    except Exception as e:  # still running
        print(path, 'not done', e)
        continue
    r = d['report']
    if not r:
        print(path, 'no report', d.get('errors'))
        continue
    m = r['marks']
    print(f'== {path.split("/")[-1]}  game {r["time"]:.0f}s  errors {len(d["errors"])}')
    for k in KEYS:
        print(f'  {k:18} ' + (f'{m[k]:6.0f}s bot  ~{m[k] * 2.5 / 60:5.1f} min kid' if k in m else '   -'))
    print('  end:', {k: r[k] for k in ['coins', 'pets', 'frozen', 'melts', 'upgrades', 'income', 'dropped']})
