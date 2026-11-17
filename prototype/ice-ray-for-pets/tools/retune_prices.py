"""Re-tune prices to a timeline: takes pacing_sim.FINAL's timeline, swaps in the odds and incomes set below,
then bisects each later price so a typical kid buys it at the same minute. Writes retuned.json; smooth it by
hand and check it with pacing_sim.py before copying it into Config.luau."""
import sys, copy, math, statistics as st, json, re
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import pacing_sim as M
# targets = the approved timeline (old tiers, no Secret spawns)
base = []
for s in range(1, 9):
    ev, _ = M.sim(M.FINAL, hours=13, seed=s, kid=dict(M.KID, secrets=False)); base.append(ev)
keys = []
for ev in base:
    for t, k in ev:
        if k not in ('newpet', 'secret') and k not in keys: keys.append(k)
FIXED = {'slots2','slots3','slots4','slots5','slots6','slots7','thaw2','thaw3','thaw4','trainer2','gun2','island2'}
T = []
for k in keys:
    if k in FIXED or k.startswith('slots'): continue
    T.append((st.median(M.first(ev, k) for ev in base) / 60, k))
T.sort()
def slot(key):
    name, n = re.match(r'([a-z]+)(\d*)', key).groups(); n = int(n) if n else 0
    if name == 'gel': return ('gel', None)
    return ({'island': 'needs', 'rebirth': 'rebirth', 'gear': 'gear', 'gun': 'guns', 'trainer': 'trainer', 'thaw': 'thaw', 'look': 'looks'}[name], n - 1)
def setp(P, key, v):
    f, i = slot(key)
    if i is None: P[f] = v
    else: P[f][i] = v
P = copy.deepcopy(M.FINAL)
P['odds'] = [59.995, 25, 10, 4, 0.9, 0.1, 0.005]; P['income'] = [1, 4, 20, 100, 500, 2500, 25000]
for _, k in T: setp(P, k, 1e30)
SEEDS = [1, 2, 3, 4, 5]
def when(key, tmax):
    ts = []
    for s in SEEDS:
        ev, _ = M.sim(P, hours=tmax / 60, seed=s, stop=key)
        x = M.first(ev, key); ts.append(x / 60 if x is not None else 1e9)
    return st.median(ts)
for tgt, key in T:
    lo, hi = 1.0, 1e17
    for _ in range(30):
        mid = math.sqrt(lo * hi); setp(P, key, mid)
        if when(key, tgt * 2.5) < tgt: lo = mid
        else: hi = mid
        if hi / lo < 1.05: break
    v = M.nice(math.sqrt(lo * hi)); setp(P, key, v)
    print(f"{key:10s} target {tgt:6.1f}  price {v:.3g}", flush=True)
json.dump(P, open('retuned.json', 'w'), indent=1)
