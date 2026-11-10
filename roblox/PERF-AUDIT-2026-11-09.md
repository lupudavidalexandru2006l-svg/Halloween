# Performance audit 2026-11-09: the 10 heaviest models (Studio "Ray a pet")

Audit only. Nothing in the place or the repo's game code was changed. Read against the vault's
World Rules › 7 and 9 (phones first, far scenery cheap, meshes under 20k triangles, Low graphics
setting) and Code Rules.

## How this was measured

- Read live from the running playtest in Studio (placeId 140233011383258) through `tools/studio_bridge.ps1`,
  on both the server and the client, plus a read of the map builder (`MapArt.luau`) and every client loop
  that runs per frame.
- **Render cost per model:** on the playtest client only, each group was hidden for a moment
  (`LocalTransparencyModifier = 1`) or had `CastShadow` turned off, the engine counters
  (`Stats.SceneTriangleCount`, `SceneDrawcallCount`, `ShadowsTriangleCount`, `ShadowsDrawcallCount`,
  `RenderCPUFrameTime`) were averaged over 20 frames, and every value was put back. Play-mode changes never
  save to the place.
- Two camera spots: **Hub** (the player's spot by the pans, ~(-58, 3, -20)) and **Tunnel** (road at
  z = 330, looking up the tunnel). A third spot at z = 1050 gave 0 shadows (lighting there), so its
  shadow numbers are not used.
- **Limits, stated plainly:**
  - Counters move by about ±10k triangles and ±5 draw calls between reads; smaller differences are noise.
  - FPS, frame time and memory in Studio cover Studio itself plus server and client in one process
    (4.4 GB total), so they say nothing about the game and are not used.
  - One player, PC, no phone test. Script CPU per function was not measured (needs the Script Profiler).

## Baseline (before any change)

| Spot | Scene draw calls | Scene triangles | Shadow draw calls | Shadow triangles | Render CPU |
|---|---|---|---|---|---|
| Hub | 245 | 290,000 | 214 | 797,000 | ~10.5 ms |
| Tunnel z=330 | 356 | 613,000 | 134 | 447,000 | ~11.2 ms |

Other facts from the live game:

| What | Value | Meaning |
|---|---|---|
| Instances in Workspace (server) | 14,173, of which `Map` 13,770 | almost everything is the generated map |
| Client Map instances loaded | 13,178 of 13,770 (96%) | streaming keeps nearly everything (see below) |
| `StreamingEnabled` / target radius | on / 1,024 studs | map spans x ±260, z -366 to 1,492 (~1,860 studs) |
| Physics step | client 0.16 ms, server 0.04 ms, 4 contacts | physics is not a problem |
| Moving parts | client 1,005, server 30 | the client moves ~1,000 anchored parts by script each frame |
| Server data send (idle) | ~5 kbps | no replication problem from the map |
| Point lights in Map | ~134 (none cast shadows) | |
| Particle emitters in Map | ~95 | |
| Scenery meshes | 6 meshes (Rock 20 tris, Octa 8, Cone 24, Dome 208, Ring 512, Arch 512), cloned 4,252 times | all `CollisionFidelity = Default`, `RenderFidelity = Automatic` |
| Gun meshes | 18,600 triangles each, 10 guns | under the 20k cap, but heavy for a hand-held item |
| Pet meshes | ~7,700 triangles per pet, split into 3-9 parts | fine |

**Biggest single fact: the shadow pass draws ~2.7x the triangles of the visible scene in the hub
(797k vs 290k).** Low graphics already turns shadows off for players who pick it.

## Ranked: the 10 models with the best optimization priority

Priority = measured cost × how much of it can go without any visible change. The cliffs have the most
parts in the game but measure cheap, so they rank last.

| # | Model | Main performance problem | Proposed optimization | Expected impact | Visual risk |
|---|---|---|---|---|---|
| 1 | Wild pet visuals (`Workspace.PetVisuals`) | 59% of hub shadow triangles (469k), 62 shadow draw calls; ~1,000 parts moved one by one each frame | Batch the moves with `BulkMoveTo` (A). Optional: no real shadow beyond a distance, the blob shadow stays (B) | A: CPU, to be measured. B: up to a large share of the shadow pass | A: none. B: low, needs your OK |
| 2 | Thaw Machines (`Hub.Pan1-6.ThawMachine1/2`) | 6 of 12 machines are invisible but fully built: 720 parts, 6 lights, beams and emitters; visible ones rewrite ~60 properties per frame | Keep the 2nd machine out of the world until a pan owns it; write a property only when its value changes | -720 parts (~5% of the map), less per-frame CPU | none |
| 3 | Sell booth (`Hub.Booth_sell`) | Most shadow-heavy building (56k shadow triangles); 12 of its parts can never be seen (inside the hub wall or its own base) | Remove parts that can never be seen (same for 32 in the Equipment booth) | -138 parts, less shadow work | none (checked by screenshots) |
| 4 | Shade / sun / lava areas (`Workspace.Map.Areas`) | 194 see-through discs = 78 draw calls in the tunnel for ~11k triangles; all 219 have unused `CanTouch` | `CanTouch` off (A). Optional: one merged disc mesh per island (B) | A: small CPU. B: up to ~70 draw calls | A: none. B: low, overlaps to check |
| 5 | Hazards (`Tunnel.Section8-10.Hazards`) | 57 particle emitters + 23 lights still drawn from far away: 61 draw calls from the island-3 view | Emitters and lights sleep when the camera is far away | up to ~60 draw calls when far | very low, needs your OK |
| 6 | Gates (`Tunnel.Section2-10.Gate*`, `EndCapArt.Gate99`) | 32-36 draw calls (216 see-through ice bars, 80 neon crystals), 16 lights; glow and booth motion rewritten every frame at any distance | Cache the tagged motion list; only breathe glows and turn motion parts that are near | small CPU | none / very low |
| 7 | Tunnel props (`Tunnel.Section*.Props`) | Most scene triangles in the tunnel: 144k, 35 draw calls, 76k shadow triangles (284 balls, 811 tiny parts) | Remove 14 buried parts; nothing else is safe | small | none |
| 8 | Tunnel trees (`Tunnel.Section*.Trees`) | 115k scene + 135k shadow triangles in the tunnel (biggest shadow source there) | No safe change beyond Low graphics; documented so nobody "fixes" the look | none planned | n/a |
| 9 | Gun models (`ReplicatedStorage.GunModels`) | 18.6k triangles per gun, all 10 guns (~3 MB each as source) sent to every client | Box collision on the templates (A). Optional: lighter meshes (B) | A: small memory. B: fewer triangles per player | A: none. B: low-medium, needs your OK |
| 10 | Cliffs (`Tunnel.Section1-9.Cliffs`) | Most instances in the game (2,637), but only ~5 draw calls (instancing works) | Box collision on the scenery mesh templates; leave the rest | small memory | none |

---

## 1. Wild pet visuals

- **Where:** `Workspace.PetVisuals` (client only), built by `StarterPlayerScripts.Client.Controllers.PetVisuals`
  from `ReplicatedStorage.PetModels` on the server's invisible `Workspace.WildPets` roots.
- **Contents:** 27 pets, 1,924 instances, 788 parts. Each pet is 17-21 parts: 3-9 `MeshPart`s (about
  7,700 triangles per pet), plus eyes, lids, a blob shadow, ring and sparkle parts. All anchored.
- **Why heavy (measured):**
  - Hub: hiding them removed 42 scene draw calls, 104k scene triangles, **62 shadow draw calls and 469k
    shadow triangles**, and ~3 ms render CPU, the biggest single result.
  - Tunnel: 33 draw calls, 77k scene triangles, 148k shadow triangles.
  - CPU: `step()` writes `part.CFrame` (and `Size` for squash) on every part of every pet in range,
    one property at a time: the ~1,000 moving primitives on the client.
- **Category:** GPU (shadow pass), CPU (per-frame writes).
- **Potential:** high.

**A. Batch the part moves (no visual change).** In `PetVisuals.step` (around line 694), collect each part
and its CFrame instead of setting it, then move them all in one call at the end of `step`:

```lua
local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}
-- inside the per-part loop, instead of `part.part.CFrame = cf * place`:
table.insert(moveParts, part.part)
table.insert(moveCFs, cf * place)
-- (the Size write stays where it is)
-- after every pet is done:
if #moveParts > 0 then
	workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	table.clear(moveParts)
	table.clear(moveCFs)
end
```

- Why: one engine call instead of hundreds of single property writes. Same CFrames, same frame, so the
  pets look identical.
- Gameplay risk: none (the parts are anchored visuals; the server's PetRoots are untouched). Check that
  nothing listens to `Position`/`Orientation` changed on pet parts (the grep found nothing).

**B. Optional: real shadows only for pets near the camera.** Pets already have their own blob shadow
part (`fx.shadow`). Turning `CastShadow` off on pet parts beyond, say, 80 studs (`Config.pets.shadowDistance`)
would cut most of the 469k shadow triangles in the hub. **This is a visible change** (a far pet loses its
sharp shadow and keeps the soft blob). I'd only do it with your OK after a side-by-side screenshot.

Not recommended: lighter pet meshes. Pets are the stars of the game.

## 2. Thaw Machines

- **Where:** `Workspace.Map.Art.Hub.Pan1` to `Pan6`, each with `ThawMachine1` and `ThawMachine2`
  (built by `MapArt.thawMachine`, animated by `Client.Controllers.ThawMachines`, shown/hidden by `PanLooks.machines`).
- **Contents:** 12 models × 124 instances = 1,488 (120 parts each: 28 plain blocks, 12 neon chase lights,
  metal cylinders, LEDs, coils, a halo, a holo screen), 12 PointLights. The client adds `Workspace.ThawMachineFx`:
  168 instances (108 beams, 24 emitters) for all 12 machines.
- **Why heavy:**
  - No pan owns a second machine right now (`Plot.Machines` is 1 or nil everywhere), yet all six
    `ThawMachine2`s are fully built, replicated to every client, then hidden with
    `LocalTransparencyModifier = 1`. That's **720 parts, 6 lights, and 8 solid server-side colliders per
    machine** that nobody can see (clients turn the collision off locally, so players don't bump into them).
  - Measured at the hub: pans 52k shadow triangles, of which the machines 28k.
  - Every frame, each machine within 120 studs rewrites Color and Transparency on its chase lights, coils,
    glows, strips, LEDs and beacon, the CFrame of 7-8 halo parts, 9 beams and 3 emitters, even while idle
    when most values don't change. `hidden()` also does two `FindFirstChild` lookups per machine per frame.
- **Category:** memory, CPU, a little GPU.
- **Potential:** high, all of it with no visual change.

**A. The second machine exists only on pans that own it.** After `MapArt.build` (and in `findExisting` for
a saved map), the server moves each `ThawMachine2` into `ServerStorage.SpareThawMachines`; when a plot's
`Machines` attribute becomes 2 (`PenService` sets it), it parents that pan's machine back.

```lua
-- WorldService, after the map is built or found
local spare = Instance.new("Folder")
spare.Name = "SpareThawMachines"
spare.Parent = ServerStorage
local function placeMachine(i: number)
	local plot = map:FindFirstChild("Plot" .. i)
	local pan = map:FindFirstChild("Pan" .. i, true)
	local m2 = (pan and pan:FindFirstChild("ThawMachine2")) or spare:FindFirstChild("ThawMachine2_" .. i)
	if not (plot and pan and m2) then return end
	local own = plot:GetAttribute("Machines") == 2
	m2.Name = if own then "ThawMachine2" else "ThawMachine2_" .. i
	m2.Parent = if own then pan else spare
end
-- call placeMachine(i) for every plot, and on plot:GetAttributeChangedSignal("Machines")
```

- Visual: identical (those machines are invisible today).
- Gameplay risk: low. `ThawMachines.scanModels` already picks up a machine that appears later (every 2 s),
  and `PanLooks.machines` already unhides it. To avoid a 2 s delay on purchase, also run `scanModels` on the
  pan's `ChildAdded`. Check `PenService` for any code that reads `ThawMachine2` positions while unowned.

**B. Write only what changed.** Keep the last value written per part in a Lua table and skip equal writes:

```lua
local last: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local function put(inst: Instance, key: string, value: any)
	local seen = last[inst]
	if not seen then seen = {}; last[inst] = seen end
	if seen[key] ~= value then
		seen[key] = value;
		(inst :: any)[key] = value
	end
end
-- e.g. put(c, "Color", lit); put(c, "Transparency", 0.78 - 0.78 * on)
```

Also cache each machine's `Plot` instance once in `setup()` instead of looking it up in `hidden()` every frame.
- Visual: identical (same values, fewer redundant writes).

## 3. Sell booth (and the Equipment booth)

- **Where:** `Workspace.Map.Art.Hub.Booth_sell` (`MapArt.sellBooth`, `coinHeap`); same issue in `Hub.Booth_equipment`.
- **Contents:** 453 instances, 427 parts: 190 cylinders (coins), 97 balls (heap, gems), 50 blocks, 44 plank
  blocks, 37 neon bulbs; 2 lights, 1 emitter.
- **Why heavy (measured):** turning its shadows off removed **55k shadow triangles** at the hub, the most of
  any building. **12 of its parts sit with all 8 corners inside a bigger, opaque block** of the map (see the correction below), so the
  camera can never see them (planks in the hub wall, coins sunk in its stone base, tiny balls inside its wood blocks). The Equipment booth
  has 32 such parts and costs 25 scene draw calls / 23k triangles at the hub.
- **Category:** GPU (shadows, draw calls), memory.
- **Potential:** medium-high.

**Fix: drop buried parts when the booth is built.** At the end of `sellBooth` and `equipmentBooth`, remove
any part whose 8 corners are inside an opaque (`Transparency == 0`) block of the same booth that isn't
animated. Bump `Config.world.mapVersion` to 15 so the saved map is rebuilt.

```lua
local function buried(p: BasePart, box: BasePart): boolean
	if box == p or box.ClassName ~= "Part" or (box :: Part).Shape ~= Enum.PartType.Block or box.Transparency > 0 then
		return false
	end
	local h = p.Size / 2
	for _, c in { Vector3.new(1,1,1), Vector3.new(1,1,-1), Vector3.new(1,-1,1), Vector3.new(1,-1,-1),
		Vector3.new(-1,1,1), Vector3.new(-1,1,-1), Vector3.new(-1,-1,1), Vector3.new(-1,-1,-1) } do
		local l = box.CFrame:PointToObjectSpace(p.CFrame:PointToWorldSpace(h * c))
		local b = box.Size / 2
		if math.abs(l.X) > b.X or math.abs(l.Y) > b.Y or math.abs(l.Z) > b.Z then
			return false
		end
	end
	return true
end
```

- Visual: unchanged by definition. Checked with before/after screenshots from fixed camera points around
  each booth, including from inside the shop window.
- Not applied to the Thaw Machines: two chase lights per machine are buried too, but removing them would
  change the running light's timing.
- Gameplay risk: none (only decoration; prompts and sign parts are excluded by name).

## 4. Shade, sun and lava areas

- **Where:** `Workspace.Map.Areas` (built by `WorldService`, read by `Shared.WorldRules` through the
  `ShadeZone` / `SunZone` / `LavaZone` tags).
- **Contents:** 219 cylinder parts: 154 `Shade` (Transparency 0.82), 42 `SunPatch` (0.45), 23 `LavaPool` (invisible).
- **Why heavy (measured):** see-through parts can't be drawn in batches, so each visible disc is its own draw
  call: **78 scene draw calls in the tunnel view, 34 at the hub, for only ~3-11k triangles.** All 219 have
  `CanTouch = true`, but nothing listens to their touches (zones are found by position in `WorldRules`).
- **Category:** CPU/GPU (draw calls), physics (touch checks).
- **Potential:** medium.

**A. `CanTouch = false`** in the three `part(...)` calls in `WorldService` (around line 280). No visual
change, no gameplay change (verified: the only `.Touched` in the game is the fall catcher).

**B. Optional: one disc mesh per island.** Merging an island's shade discs into one mesh would turn ~70
draw calls into ~10. Where two discs overlap, the overlap is darker today and a merged mesh may draw it
once, so this needs an overlap check first. The tagged zone parts would stay (invisible) for `WorldRules`.
Low visual risk; I'd show you screenshots before keeping it.

## 5. Hazards

- **Where:** `Workspace.Map.Art.Tunnel.Section8`, `Section9`, `Section10` `.Hazards` (`MapArt.hazards`).
- **Contents:** 454 instances, 139 parts (88 rocks, 34 neon `SunRim` rings, 9 `LavaGlow`), 57 particle
  emitters (~244 particles/s), 23 PointLights.
- **Why heavy (measured):** hiding them removed **61 draw calls from the island-3 view** (hundreds of studs
  away) and 25 from z = 1050. Emitters and lights keep running however far the camera is.
- **Category:** GPU (draw calls, particles), CPU (particle simulation).
- **Potential:** medium.

**Fix: hazard sparkles and lights sleep when far.** Tag the emitters and lights in `MapArt.hazards`
(`HazardFx`); a client loop every 0.5 s sets `Enabled = distance < Config.mapFx.hazardFxDistance` (start at
300 studs). Particles of this size are below a pixel at that distance.
- Visual risk: very low, but it is a change at the cutoff, so I'd check it in a screenshot first.
- Gameplay: none (lava and sun zones are position checks).

## 6. Gates

- **Where:** `Workspace.Map.Art.Tunnel.Section2` to `Section10` `.Gate2`-`Gate10` and `EndCapArt.Gate99`
  (`MapArt.gatehouse` / `GATE_TOWERS`), animated by `Client.Controllers.MapController`.
- **Contents:** 923 instances, 698 parts: 216 see-through `Ice` bars, 80 neon see-through crystals, 20
  `GateGlow` slabs, 16 lights, 2 emitters.
- **Why heavy (measured):** 32-36 scene draw calls (the see-through bars and crystals), 28-40k shadow
  triangles. Each frame `MapController` rewrites `Transparency` on every `GateGlow` and runs
  `moveMapParts`, which calls `CollectionService:GetTagged`, reads 3-5 attributes per tagged folder and
  builds new tables for all 18 motion folders (booth gears, portal swirl, crystals), at any distance.
- **Category:** CPU (per-frame loop), GPU (draw calls).
- **Potential:** low-medium.

**Fix:** keep the tagged motion folders in a list (filled once, updated with `GetInstanceAddedSignal` /
`GetInstanceRemovedSignal`), with their attributes read once; skip folders and glows farther than
`Config.mapFx.motionDistance` from the camera. The booths' moving parts are in the hub and can't be seen
from the tunnel. Visual: none in practice; at the cutoff a far gate holds a steady glow instead of a slow
breath. The see-through bars stay (they are the gate's look).

## 7. Tunnel props

- **Where:** `Workspace.Map.Art.Tunnel.Section1`-`10` `.Props` (`meadowProps`, `forestProps`, `hotProps`...:
  snowmen, giant mushrooms, crates, presents, bushes, flowers, small rocks).
- **Contents:** 1,637 instances, 1,282 parts: 284 balls, 368 + 211 blocks, 75 cylinders, 45 neon crystals,
  27 emitters; 811 parts smaller than 1.5 studs.
- **Why heavy (measured):** the most scene triangles in the tunnel view (**144k**, 35 draw calls) plus 76k
  shadow triangles. Ball parts are the triangle-heavy shape.
- **Potential:** low without changing the look. Safe: remove the 1 buried part (Section 4; see the correction below) with the same
  build-time pass as #3. Swapping balls for low-poly sphere meshes would change their silhouette, so I don't
  recommend it.

## 8. Tunnel trees

- **Where:** `Workspace.Map.Art.Tunnel.Section1`-`10` `.Trees` (`MapArt.tree`), 154 tree Models.
- **Contents:** 1,277 instances, 891 parts: 248 cone meshes, 199 cylinders (121 solid trunks), 64 balls,
  84 leafy blocks, 12 Glass crystal meshes; 846 cast shadows.
- **Why heavy (measured):** in the tunnel, **115k scene triangles, 18 draw calls and 135k shadow
  triangles**, the biggest shadow source there.
- **Potential:** none without a visible change. Trees are supposed to cast shadows, and the trunks are solid
  on purpose. Players on Low graphics already lose all shadows. Listed so the cost is known.
- Rule note, not a performance fix: 45 tree crystals use `Glass`, which World Rules › 6 says not to use
  (Roblox draws nothing see-through behind Glass). Changing it would change the look, so it's your call.

## 9. Gun models

- **Where:** `ReplicatedStorage.GunModels` (10 Models, each one `Body` MeshPart), cloned onto the player
  when held.
- **Contents:** 18,600-triangle mesh + 1 texture per gun (source GLBs 3.1-3.3 MB each). Already well set
  up: no shadow, no collision, no query, no touch, massless.
- **Why heavy:** every client receives all 10 guns on join, owned or not, and each held gun costs 18.6k
  triangles per player in view (12 players ≈ 220k).
- **Category:** memory, loading, GPU.
- **Potential:** medium.

**A. `CollisionFidelity = Box` on the 10 templates** (set in Studio edit mode; it can't be set from a running
script). The guns never collide, so no visual or gameplay change; the engine skips building detailed
collision data.

**B. Optional: lighter gun meshes** (~8k triangles, same UVs and texture) through `tools/prep_trellis_gun.py`.
At hand size the difference should be hard to see, but it is a geometry change: low-medium risk, side-by-side
renders first, your OK needed.

## 10. Cliffs

- **Where:** `Workspace.Map.Art.Tunnel.Section1`-`9` `.Cliffs` (`MapArt.cliffs`).
- **Contents:** 2,637 instances, the most of any model: 2,390 MeshParts using only 4 meshes (Rock 20 tris,
  Dome 208, Cone 24, Octa 8) + 182 parts. None collide; 1,179 answer raycasts; 698 cast shadows.
- **Why it ranks last (measured):** in the tunnel view they add 110k scene triangles but **only ~5 draw calls**
  (the same few meshes are drawn in batches) and ~11k shadow triangles. Cheap to draw; the cost is
  instance count and memory.
- **Fix:** `CollisionFidelity = Box` on the 6 templates in `ReplicatedStorage.SceneryMeshes` (Studio edit
  mode). All 4,252 clones inherit it. Small memory gain. Not recommended: turning raycasts off on cliffs,
  because the camera (Invisicam) uses them to fade a cliff that blocks your view.

## Not in the top 10, and why

- **Hub Village** (1,072 instances): measured cheap (~5k scene, ~9k shadow triangles at the hub).
- **Far scenery** (232 instances): already no collision, no shadows; measured near zero.
- **Path lanterns** (30 PointLights, 30 Glass lanterns): ~12 draw calls in the tunnel. Could join #5's
  sleep-when-far if you like.
- **Rebirth booth** (312 instances): ~2k triangles; its 159 see-through parts are the portal's look.

## Whole-game notes

- **Streaming barely trims anything.** The target radius is 1,024 studs and the map is ~1,860 long, so a
  client in the hub keeps 96% of the map. The map is all Folders, so nothing streams as a unit. Lowering the
  radius would save memory on phones but makes far scenery pop in, which works against World Rules' far
  silhouettes. I'd leave it and rely on Roblox streaming out under memory pressure (`Opportunistic` is on).
- **Physics and network are fine.** 0.16 ms physics on the client, 4 contacts, ~5 kbps from the server.
  Collision-fidelity changes save memory, not FPS.
- **Shadows are the biggest render cost.** Low graphics turns them off. `Lighting.Technology` can't be read
  from a script; the cascaded shadow pass means it's ShadowMap or Future. Worth a look in Studio.
- **ServerStorage holds 9 backup folders (~11,600 instances**: Phase6 6,267, Lobby 4,264, BoothEmblem 804...).
  Players never receive them, but they grow the place file and server memory. Deleting them is your call.

## Implementation plan (waits for your approval)

**Phase A, no visual change:**
1. Thaw Machines: second machine only when owned (#2A), write-only-on-change (#2B).
2. Pets: batched moves (#1A).
3. Booths and props: build-time removal of buried parts (#3, #7), `mapVersion` 15.
4. Areas: `CanTouch = false` (#4A).
5. MapController: cached motion list and distance skip (#6).
6. Studio edit mode: Box collision on the 6 scenery mesh templates and 10 gun templates (#9A, #10).

**Phase B, low visual risk, each one only with your OK after screenshots:**
pet shadow distance (#1B), hazard sleep-when-far (#5), merged shade discs (#4B), lighter guns (#9B).

All distances go in `Config` (Code Rules › 4). Every change is made in the repo first, then synced with
`tools/studio_sync.ps1`.

## Validation plan

1. Re-run the same measurement (same two camera spots, same 20-frame averages) after each phase and
   compare with the baseline table above. The measurement script goes into `tools/` so anyone can repeat it.
2. MicroProfiler and Script Profiler in a playtest for the CPU items (`ThawMachines`, `PetVisuals`,
   `MapController`), before and after.
3. Instance counts (Workspace, Map, client) before and after.
4. Fixed-camera screenshots before and after at the hub, each booth, the pans and 3 tunnel spots,
   compared side by side for any visual difference.
5. A playtest of the touched systems: buying the 2nd Thaw Machine, thawing, pet wander and actions, gates
   opening, shade/sun/lava melt rates.
6. **Phone check (needs you):** Studio's emulator isn't a real phone (World Rules › 7). Before/after FPS
   in the busiest spot on a real phone.

No improvement is claimed until it is measured this way.

## Phase A results (done 2026-11-10)

All Phase A items are in the repo and synced into "Ray a pet"; map version 15.

**Correction to the audit:** the first buried-part check counted a part as hidden if it sat inside a block's
box. `ellipsoid()` builds a Block with a sphere mesh, so its box is not its shape: the first build removed
the loose coins lying on the Sell booth's gold heap (caught in the before/after screenshots). Parts with a
mesh inside no longer count as hiding blocks. The real list is **44 parts**: 32 Equipment booth back
pieces inside the hub wall, 3 Sell booth planks inside the hub wall, 3 coins sunk in the Sell booth's stone
base, 6 tiny balls inside its wood blocks, and 1 plate under the sand in Section 4.

| Measure | Before | After |
|---|---|---|
| Map instances every client receives (server count) | 13,770 | 12,976 |
| Second Thaw Machines in the world (no pan owns one) | 6 (744 instances) | 0 (parked in ServerStorage) |
| Thaw Machine effects the client builds | 168 | 84 |
| Map build time (edit-mode test build) | n/a | 0.22 s, including the buried-part pass |
| Moving 600 pet-sized parts (Studio, throttled) | 1.85 ms one by one | 0.83 ms with one BulkMoveTo |
| 540 parts × 2 unchanged values (idle Thaw Machines) | 0.17 ms written | 0.044 ms skipped |

- **Render counters showed no measurable change.** Wild pets wander and respawn at random and make up most
  of the shadow work, so their positions swamp these changes; this run even read a little higher.
  Streaming also differed between sessions until the test character visited the tunnel.
- **Visual check:** fixed-camera screenshots at 9 spots (booths, pans, hub, tunnel) match; the only
  differences are the day/night lighting and the gears' angle.
- **Behaviour check:** no script errors; pets, chase lights and booth gears animate. Setting Plot 3's
  `Machines` to 2 brought its second machine in (visible, prompt, lights, effects) and setting it back
  parked it again.
- **Box collision:** `CollisionFidelity` can't be set from a script, so the 16 templates got Box collision
  through `AssetService:CreateMeshPartAsync` + `ApplyMesh`. `ApplyMesh` cleared the guns' textures; all 10
  were put back right away and checked. These templates live only in the place, not the repo.
- **Saved map:** the edit place still holds an old v12 map, so every server rebuilds the map at start (0.22 s).
- **Still open:** a real phone check, and Phase B (each item only with the owner's OK after screenshots).
