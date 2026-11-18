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
        if P.get('slots_prices'): return P['slots_prices'][S['slots'] - 1]  # Config.upgrades.pen.prices
        return nice(P['slots_base'] * P['slots_growth'] ** (S['slots'] - 1) * P['slots_rgrowth'] ** S['reb'])
    def shop():
        it = []
        if S['gun'] < 10: it.append((P['guns'][S['gun']], 'gun'))
        if S['trainer'] < 10: it.append((P['trainer'][S['trainer']], 'trainer'))
        if S['thaw'] < 10: it.append((P['thaw'][S['thaw']], 'thaw'))
        if S['slots'] < 7: it.append((slots_cost(), 'slots'))
        if S['look'] < 5 and not P.get('free_looks'): it.append((P['looks'][S['look']], 'look'))
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
                S['coins'] = 0; S['power'] = 0; S['reb'] += 1; S['slots'] = S['slots'] if P.get('slots_keep') else 1; ev(f"rebirth{S['reb']}"); continue
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
            g = P.get('base', 1) * P.get('level_value', 4) ** plevel() * P.get('tmult', TRAINER_MULT)[S['trainer'] - 1] * GUN_TRAIN[S['gun'] - 1] * (1 + 0.5 * S['reb'])
            S['power'] += g * (kid['clicks'] + 1 / 1.2) * (1 + 5 / 12) * kid['train_eff'] * dt
        else:
            trip_left -= dt
            if trip_left <= 0:
                z = farm
                cap = GUN_BEAMS[S['gun'] - 1]
                d = 80 + ZMIN[z - 1] + 0.55 * LENGTHS[z - 1]
                walk = 2 * d / kid['walk'] * kid['slow'] / (1.08 if S['gear'] >= 2 else 1) / (1.05 if S['gear'] >= 3 else 1)
                need = max(P['needs'][z - 1], P.get('floor', 50))
                speed = min(5, max(1, math.sqrt(max(S['power'], 1) / need))) * (1 + 0.12 * (S['gun'] - 1))
                odds = P.get('odds') or [t[1] for t in TIERS]
                w = [o * (EARLY.get(i, 1) if z <= 4 else 1) for i, o in enumerate(odds)]
                for _ in range(cap):
                    incs = P.get('income') or [t[2] for t in TIERS]
                    def size_roll():
                        # Config.sizes: (chance, income x, thaw x), rarest first; none = Normal
                        for ch, im, tm in P.get('sizes', []):
                            if rnd.random() < ch: return im, tm
                        return 1, 1
                    seen = []
                    for _k in range(kid['pick_k']):
                        ti = rnd.choices(range(7), weights=w)[0]
                        seen.append((ti, size_roll()))
                    best, (smult, sthaw) = max(seen, key=lambda x: incs[x[0]] * x[1][0])
                    name, _, inc, ths, fz = TIERS[best]
                    ths = (P.get('thaw_s') or [t[3] for t in TIERS])[best]
                    inc = incs[best] * smult
                    ths *= sthaw
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
        nm = sum(1 for a in P.get('machines_at', [1, 3]) if S['slots'] >= a)  # Config.thaw.machinesAt
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
        # the server Secret every 30 min (Config.secretSpawn): on a random island of 10; this kid gets it
        # if it can freeze there and wins the race against the other players (about half the time)
        if S['t'] > 0 and S['t'] % 1800 < dt and kid.get('secrets', True):
            zr = rnd.randint(1, 10)
            if zr <= farm and rnd.random() < 0.5:
                sinc = (P.get('income') or [t[2] for t in TIERS])[6] * 4 ** (zr - 1)
                queue.append((sinc, max(1, 1200 * 1.3 ** (zr - 1) * 0.9 ** (S['thaw'] - 1) / 1.33 ** (S['slots'] - 1))))
                ev('secret')
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
            if k not in ('newpet', 'secret') and k not in keys: keys.append(k)
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
    done = st.median([max(t for t, k in ev if k not in ('newpet', 'secret')) / 3600 for ev in allev])
    key = {k: m for m, k, n in rows}
    print(f"first buy {key.get('slots2',0)*60:.0f}s, longest wait in first 10 min {gaps10:.0f}s, island2 {key.get('island2',0):.1f}m, R1 {key.get('rebirth1',0):.1f}m, R2 {key.get('rebirth2',0):.1f}m, island10 {key.get('island10',0)/60:.1f}h, last buy {done:.1f}h")
    print("new things per hour (incl. new pets):", [int(x) for x in per_hour])

# the prices in roblox/src/shared/Config.luau after the rarity pass of 2026-11-17 (Steal an Egg's steps, tamed)
FINAL = dict(
    odds=[59.995, 25, 10, 4, 0.9, 0.1, 0.005], income=[1, 4, 20, 100, 500, 2500, 25000],
    # shot-gain pass 2026-11-17: no x4 per island (level_value 1), needs fitted to keep the same timings
    # Steal an Egg pass 2026-11-17: its biome speed gates as needs, bolts worth 5, trainers 6-10 x20-2000
    level_value=1, needs=[0, 900, 10e3, 40e3, 170e3, 700e3, 2.5e6, 18e6, 700e6, 2.5e9],
    base=5, floor=450, tmult=[1, 2, 3, 4, 6, 20, 75, 200, 600, 2000],
    # owner 2026-11-17: Common / Uncommon thaw in 2 / 4 s; Looks come with Slots level 7 (not bought)
    thaw_s=[2.6, 5.2, 26, 78, 195, 624, 1560], free_looks=True,  # every thaw x1.3 (owner 2026-11-17 night)
    # coin pass 2026-11-17 (keep the 10.4 h runway), then the late-game pass (each stage harder than the last)
    guns=[0, 40e3, 2e6, 25e6, 250e6, 5e9, 25e9, 750e9, 2.5e12, 40e12],
    trainer=[0, 15e3, 2e6, 1.2e9, 15e9, 400e9, 1.2e12, 4e12, 7.5e12, 50e12],
    thaw=[0, 250, 1e3, 4e3, 200e3, 2e6, 7.5e6, 300e6, 20e9, 1e12],
    looks=[0, 500e3, 30e6, 7.5e9, 6e12],
    gear=[250e3, 1.5e6, 30e6, 2e9, 2e12],
    gel=1e6, slots_base=50, slots_growth=2.5, slots_rgrowth=15,
    # Slots pass 2026-11-18: Config.upgrades.pen.prices, kept through rebirth; Thaw Machines at Slots 1 / 2 / 5
    slots_prices=[100, 2.5e3, 200e3, 4e6, 150e6, 7.5e9], slots_keep=True, machines_at=[1, 2, 5],
    rebirth=[5e6, 250e6, 5e9, 15e9, 250e9, 500e9, 25e12],
    # Config.sizes (2026-11-17 size chart), rarest first: (chance, income x, thaw x), Cosmic down to Big
    sizes=[(0.000081, 343.33, 6), (0.0002, 165.48, 5), (0.0005, 79.76, 4), (0.0013, 38.44, 3), (0.0032, 18.53, 2.5),
           (0.0098, 8.93, 2), (0.035, 4.3, 1.6), (0.15, 2.07, 1.25)])

if __name__ == '__main__':
    # Keep FINAL in step with Config.luau, then: python pacing_sim.py
    print('=== typical kid'); report(FINAL, detail=True)
    for name, k in [('fast kid', dict(KID, slow=1.25, overhead=4, clicks=4, train_eff=0.85)),
                    ('slow kid', dict(KID, slow=2.0, overhead=9, clicks=1.8, pick_k=2, sell=0.3, train_eff=0.6))]:
        print('---', name); report(FINAL, kid=k)
    print('--- before the pacing pass (old rarities)'); report(CURRENT)
