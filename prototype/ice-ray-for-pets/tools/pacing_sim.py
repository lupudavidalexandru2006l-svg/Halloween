"""Ice Ray for Pets pacing sim (pacing pass 2026-11-16, PACING-2026-11-16.md): one typical kid, cheapest-first buyer, on the Config numbers.
Events are (seconds, key) with keys like 'gun3', 'island4', 'rebirth2', 'slots5', 'newpet'."""
import math, random, statistics as st

TIERS = [  # name, odds, income, thaw s, freeze s
    ("Common", 59.995, 1, 4, 0.9), ("Uncommon", 25, 3, 8, 1.0), ("Rare", 10, 10, 20, 1.3),
    ("Epic", 4, 30, 60, 1.6), ("Legendary", 0.9, 100, 150, 2.1), ("Mythic", 0.1, 400, 480, 2.7),
    ("Secret", 0.005, 1500, 1200, 3.4)]
MINFREEZE = [0.5, 1, 1.5, 2.5, 3.5, 4.5, 6]
EARLY = {2: 1.5, 3: 2, 4: 2, 5: 1.5}
LENGTHS = [168, 176, 172, 172, 210, 230, 250, 270, 290, 320]
ZMIN = [sum(LENGTHS[:i]) for i in range(10)]
REBIRTH_GATES = {3: 1, 5: 2, 7: 4, 9: 6}
GUN_HEAT = [2, 2, 4, 4, 6, 6, 8, 8, 10, 10]
GUN_TRAIN = [1, 2, 3, 5, 8, 12, 20, 30, 50, 100]
GUN_BEAMS = [1, 1, 1, 2, 2, 2, 3, 3, 3, 4]
TRAINER_MULT = [1, 2, 3, 5, 8, 12, 20, 30, 50, 100]

CURRENT = dict(
    needs=[0, 150, 20e3, 300e3, 600e3, 40e6, 150e6, 7.5e9, 15e9, 2e12],
    guns=[0, 7.5e3, 200e3, 1e6, 10e6, 30e6, 500e6, 2e9, 15e9, 250e9],
    trainer=[0, 4e3, 120e3, 4e6, 75e6, 200e6, 3e9, 4e9, 7.5e9, 400e9],
    thaw=[0, 250, 1e3, 4e3, 15e3, 60e3, 400e3, 4e6, 40e6, 400e6],
    looks=[0, 50e3, 6e6, 250e6, 50e9],
    gear=[25e3, 150e3, 1.5e6, 60e6, 2e9],
    gel=75e3,
    slots_base=50, slots_growth=2.5, slots_rgrowth=15,
    rebirth=[300e3, 3e6, 200e6, 600e6, 7.5e9, 15e9, 150e9],
)

NICE = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 10]
def nice(n):
    if n < 1: return 0
    p = 10 ** math.floor(math.log10(n)); m = n / p
    return round(min(NICE, key=lambda s: abs(math.log(m / s))) * p)

# a typical kid: walks x1.6 the straight-line time, 6 s of fuss a trip, 2.5 clicks a second at the
# trainer at 70% focus, picks the best of the 3 pets in view, sells half the pets it doesn't keep
KID = dict(walk=32, slow=1.6, overhead=6, clicks=2.5, pick_k=3, sell=0.5, train_eff=0.7)

def sim(P, hours=12, seed=1, kid=KID, stop=None, dt=1.0):
    rnd = random.Random(seed)
    S = dict(t=0.0, coins=0.0, power=0.0, reach=1, reb=0, gun=1, trainer=1, thaw=1, slots=1, look=1, gel=0, gear=0)
    pan, queue, machines, species, events = [], [], [], set(), []
    incomes = []
    def ev(k):
        events.append((S['t'], k))
    def nslots(): return min(10 + S['slots'] - 1, 16)
    def mult(): return (1 + 0.5 * S['reb']) * (1.1 if S['gear'] >= 5 else 1)
    def income(): return sum(pan[:nslots()]) * mult()
    def plevel(): return sum(1 for n in P['needs'] if 0 < n <= S['power'])
    def slots_cost():
        return nice(P['slots_base'] * P['slots_growth'] ** (S['slots'] - 1) * P['slots_rgrowth'] ** S['reb'])
    def shop():
        it = []
        if S['gun'] < 10: it.append((P['guns'][S['gun']], 'gun'))
        if S['trainer'] < 10: it.append((P['trainer'][S['trainer']], 'trainer'))
        if S['thaw'] < 10: it.append((P['thaw'][S['thaw']], 'thaw'))
        if S['slots'] < 7: it.append((slots_cost(), 'slots'))
        if S['look'] < 5: it.append((P['looks'][S['look']], 'look'))
        if S['gear'] < 5: it.append((P['gear'][S['gear']], 'gear'))
        if not S['gel']: it.append((P['gel'], 'gel'))
        return sorted(it)
    def rebirth_cost():
        r = P['rebirth']; i = min(S['reb'], len(r) - 1)
        return r[i] * 3 ** max(0, S['reb'] + 1 - len(r))
    def want_rebirth():
        nz = S['reach'] + 1
        if nz <= 10: return REBIRTH_GATES.get(nz, 0) > S['reb']
        return S['reb'] < 7
    trip_left = 0.0
    nextlog = 0
    while S['t'] < hours * 3600:
        if stop and any(k == stop for _, k in events[-3:]):
            break
        while True:
            items = shop()
            rc = rebirth_cost()
            cheap = items[0] if items else (math.inf, None)
            if want_rebirth() and S['coins'] >= rc and (cheap[0] > rc * 0.4 or S['slots'] >= 7):
                S['coins'] = 0; S['power'] = 0; S['reb'] += 1; S['slots'] = 1; ev(f"rebirth{S['reb']}"); continue
            if want_rebirth() and cheap[0] > rc * 0.4 and cheap[0] <= S['coins']:
                break  # saving for the rebirth
            if cheap[1] and S['coins'] >= cheap[0]:
                S['coins'] -= cheap[0]; k = cheap[1]
                if k == 'gel': S['gel'] = 1; ev('gel')
                else:
                    S[k] += 1; ev(f"{k}{S[k]}")
                continue
            break
        while S['reach'] < 10:
            nz = S['reach'] + 1
            if S['power'] >= P['needs'][nz - 1] and REBIRTH_GATES.get(nz, 0) <= S['reb']:
                S['reach'] = nz; ev(f"island{nz}")
            else:
                break
        nz = S['reach'] + 1
        farm = min(S['reach'], GUN_HEAT[S['gun'] - 1])
        training = nz <= 10 and S['power'] < P['needs'][nz - 1] and REBIRTH_GATES.get(nz, 0) <= S['reb'] and len(pan) >= nslots()
        if training:
            g = 4 ** plevel() * TRAINER_MULT[S['trainer'] - 1] * GUN_TRAIN[S['gun'] - 1] * (1 + 0.5 * S['reb'])
            S['power'] += g * (kid['clicks'] + 1 / 1.2) * (1 + 5 / 12) * kid['train_eff'] * dt
        else:
            trip_left -= dt
            if trip_left <= 0:
                z = farm
                cap = GUN_BEAMS[S['gun'] - 1]
                d = 80 + ZMIN[z - 1] + 0.55 * LENGTHS[z - 1]
                walk = 2 * d / kid['walk'] * kid['slow'] / (1.08 if S['gear'] >= 2 else 1) / (1.05 if S['gear'] >= 3 else 1)
                need = max(P['needs'][z - 1], 50)
                speed = min(5, max(1, math.sqrt(max(S['power'], 1) / need))) * (1 + 0.12 * (S['gun'] - 1))
                w = [o * (EARLY.get(i, 1) if z <= 4 else 1) for i, (_, o, *_r) in enumerate(TIERS)]
                for _ in range(cap):
                    best = max(rnd.choices(range(7), weights=w)[0] for _k in range(kid['pick_k']))
                    name, _, inc, ths, fz = TIERS[best]
                    pinc = inc * 4 ** (z - 1) * rnd.choice([1, 1, 1, 1.2, 1.2, 1.5]) * (2 if rnd.random() < 1 / 40 else 1)
                    if (z, best) not in species:
                        species.add((z, best)); ev('newpet')
                    kept = pan[:nslots()]
                    if len(kept) < nslots() or pinc > kept[-1]:
                        th = ths * 1.3 ** (z - 1) * 0.9 ** (S['thaw'] - 1) / 1.33 ** (S['slots'] - 1)
                        queue.append((pinc, max(1, th)))
                    elif rnd.random() < kid['sell']:
                        S['coins'] += pinc * 300 * mult()
                    trip_left += max(MINFREEZE[best], fz * 2.2 / speed)
                trip_left += walk + kid['overhead'] + 3 * (cap - 1)
        nm = 2 if S['slots'] >= 3 else 1
        machines = [(m - dt, inc) for m, inc in machines]
        for m, inc in machines:
            if m <= 0: pan.append(inc)
        machines = [x for x in machines if x[0] > 0]
        while len(machines) < nm and queue:
            queue.sort(reverse=True)
            inc, th = queue.pop(0)
            machines.append((th, inc))
        pan.sort(reverse=True); del pan[16:]
        S['coins'] += income() * dt
        if S['t'] >= nextlog:
            incomes.append((S['t'], income())); nextlog += 60
        S['t'] += dt
    return events, incomes

def first(events, key):
    for t, k in events:
        if k == key: return t
    return None


def report(P, kid=KID, seeds=range(1, 9), hours=14, detail=False):
    allev = [sim(P, hours=hours, seed=s, kid=kid)[0] for s in seeds]
    keys = []
    for ev in allev:
        for t, k in ev:
            if k != 'newpet' and k not in keys: keys.append(k)
    rows = []
    for k in keys:
        ts = [first(ev, k) for ev in allev]
        ts = [t for t in ts if t is not None]
        rows.append((st.median(ts) / 60, k, len(ts)))
    rows.sort()
    if detail:
        prev = 0
        for m, k, n in rows:
            if k.startswith('slots') and m > 30: continue
            print(f"{m:7.1f} min  {k:10s} (+{m-prev:5.1f})  {n}/{len(allev)}"); prev = m
    per_hour = []
    for h in range(hours):
        per_hour.append(st.median([sum(1 for t, k in ev if h * 3600 <= t < (h + 1) * 3600) for ev in allev]))
    gaps10 = st.median([max(b - a for a, b in zip([0] + [t for t, _ in ev], [t for t, _ in ev]) if a < 600) for ev in allev])
    done = st.median([max(t for t, k in ev if k != 'newpet') / 3600 for ev in allev])
    key = {k: m for m, k, n in rows}
    print(f"first buy {key.get('slots2',0)*60:.0f}s, longest wait in first 10 min {gaps10:.0f}s, island2 {key.get('island2',0):.1f}m, R1 {key.get('rebirth1',0):.1f}m, R2 {key.get('rebirth2',0):.1f}m, island10 {key.get('island10',0)/60:.1f}h, last buy {done:.1f}h")
    print("new things per hour (incl. new pets):", [int(x) for x in per_hour])

# the prices in roblox/src/shared/Config.luau after the pacing pass of 2026-11-16
FINAL = dict(
    needs=[0, 150, 5e3, 300e3, 4e6, 75e6, 150e6, 15e9, 200e9, 4e12],
    guns=[0, 7.5e3, 500e3, 3e6, 15e6, 100e6, 2e9, 7.5e9, 75e9, 200e9],
    trainer=[0, 4e3, 300e3, 40e6, 750e6, 3e9, 25e9, 75e9, 600e9, 5e12],
    thaw=[0, 250, 1e3, 4e3, 30e3, 200e3, 1e6, 40e6, 1e9, 12e9],
    looks=[0, 150e3, 7.5e6, 1.5e9, 750e9],
    gear=[75e3, 400e3, 4e6, 200e6, 75e9],
    gel=250e3, slots_base=50, slots_growth=2.5, slots_rgrowth=15,
    rebirth=[1e6, 20e6, 600e6, 4e9, 40e9, 100e9, 2e12])

if __name__ == '__main__':
    # Keep FINAL in step with Config.luau, then: python pacing_sim.py
    print('=== typical kid'); report(FINAL, detail=True)
    for name, k in [('fast kid', dict(KID, slow=1.25, overhead=4, clicks=4, train_eff=0.85)),
                    ('slow kid', dict(KID, slow=2.0, overhead=9, clicks=1.8, pick_k=2, sell=0.3, train_eff=0.6))]:
        print('---', name); report(FINAL, kid=k)
    print('--- before the pass'); report(CURRENT)
