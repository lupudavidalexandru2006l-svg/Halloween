--!strict
-- PetRig: plays Shared.PetClips on a skinned pet (one closed MeshPart + Bones, from anim/tools; Animation Rules 4).
-- The same clip data and maths as the Blender checker (anim/tools/bl_check.py), so a move that passed there looks
-- the same here: each slot's channels are rotations about the model's axes at rest, turned into the bone's own
-- frame (Transform = R^-1 * D * R); the root's channels move the whole model about the Root bone (feet, body
-- middle); when the body sinks the legs fold (two-bone) so the feet stay down.
-- A pose is a mix: { clip, t (0..1), w } entries, summed per channel, then crossfaded by the caller.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local PetClips = require(ReplicatedStorage.Shared.PetClips)

local PetRig = {}

export type BoneInfo = { bone: Bone, name: string, slot: string, right: boolean, rest: CFrame, restInv: CFrame,
	len: number, kind: string, seg: number, front: boolean }
export type Rig = { model: Model, plan: string, upright: boolean, parts: { { part: BasePart, rel: CFrame } },
	bones: { BoneInfo }, byName: { [string]: BoneInfo }, legs: { { up: BoneInfo, lo: BoneInfo, back: boolean } },
	rootAt: Vector3, hip: number, height: number, damp: { [string]: { [string]: number } },
	followers: { { part: BasePart, rel: CFrame } }, headChain: { Bone }, main: BasePart, scale: number }
export type Values = { [string]: { [string]: number } } -- bone name -> channel -> value ("Root" carries up/fwd/rt/sink)
export type Mix = { { clip: PetClips.Clip, t: number, w: number, name: string } }

-- a bone's world frame at rest, worked out down the chain from its part (Bone.WorldCFrame can be stale right
-- after a clone is scaled or moved)
local function restWorld(b: Bone): CFrame
	local p = b.Parent
	if p and p:IsA("Bone") then
		return restWorld(p) * b.CFrame
	elseif p and p:IsA("BasePart") then
		return p.CFrame * b.CFrame
	end
	return b.WorldCFrame
end

local function info(b: Bone, pivot: CFrame): BoneInfo
	local rest = pivot:ToObjectSpace(restWorld(b))
	local slot = b:GetAttribute("Slot")
	local side = b:GetAttribute("Side")
	local len = b:GetAttribute("Len")
	local kind = b:GetAttribute("Kind")
	local seg = b:GetAttribute("Seg")
	local r = rest.Rotation
	return { bone = b, name = b.Name, slot = if typeof(slot) == "string" then slot else "prop", right = side == "R",
		rest = r, restInv = r:Inverse(), len = if typeof(len) == "number" then len else 0,
		kind = if typeof(kind) == "string" then kind else "", seg = if typeof(seg) == "number" then seg else 0,
		front = b:GetAttribute("Front") == true }
end

-- builds the rig for a drawn (cloned, scaled) skinned model; nil when the model isn't skinned
function PetRig.new(model: Instance): Rig?
	if not model:IsA("Model") or model:GetAttribute("Skinned") ~= true then
		return nil
	end
	local pivot = model:GetPivot()
	local scale = model:GetScale()
	local parts, bones, byName = {}, {}, {}
	local main: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			d.Transform = CFrame.identity
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { part = d, rel = pivot:ToObjectSpace(d.CFrame) })
			if d:FindFirstChild("Root") and (d:FindFirstChild("Root") :: Instance):IsA("Bone") then
				main = d
			end
		elseif d:IsA("Bone") then
			local bi = info(d, pivot)
			bi.len *= scale
			table.insert(bones, bi)
			byName[d.Name] = bi
		end
	end
	if not main or not byName.Root then
		return nil
	end
	local legs = {}
	for _, b in bones do
		if b.kind == "leg" and b.seg == 0 then
			for _, c in bones do
				if c.kind == "leg" and c.seg == 1 and c.bone.Parent == b.bone then
					table.insert(legs, { up = b, lo = c, back = not b.front and model:GetAttribute("Upright") ~= true })
				end
			end
		end
	end
	local damp = {}
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode((model:GetAttribute("Damp") :: string?) or "{}")
	end)
	if ok and typeof(decoded) == "table" then
		damp = decoded
	end
	-- the head chain (main part -> ... -> Head): lids and statue eyes ride on the Head bone
	local chain: { Bone } = {}
	local head = byName.Head
	if head then
		local b: Instance? = head.bone
		while b and b:IsA("Bone") do
			table.insert(chain, 1, b)
			b = b.Parent
		end
	end
	local rig: Rig = { model = model, plan = (model:GetAttribute("Plan") :: string?) or "Quadruped",
		upright = model:GetAttribute("Upright") == true, parts = {}, bones = bones, byName = byName, legs = legs,
		rootAt = restWorld(byName.Root.bone).Position - pivot.Position, hip = ((model:GetAttribute("Hip") :: number?) or 0.3) * scale,
		height = ((model:GetAttribute("RigHeight") :: number?) or 1) * scale, damp = damp, followers = {}, headChain = chain,
		main = main, scale = scale }
	rig.rootAt = pivot:VectorToObjectSpace(rig.rootAt)
	-- skinned meshes move with the model; anything else in it (lids, statue eyes) follows the head
	local headRest = if head then restWorld(head.bone) else nil
	for _, p in parts do
		local isMesh = p.part:IsA("MeshPart") and (p.part == main or p.part:FindFirstChildWhichIsA("Bone", true) ~= nil
			or (p.part :: MeshPart).MeshId ~= "")
		-- the part holding the bones (an importer RootPart on glow pets) is body, never a head follower: as a
		-- follower it got turned with the head and spun the whole skin round (2026-11-21)
		if isMesh or not headRest or p.part == main then
			table.insert(rig.parts, p)
		else
			table.insert(rig.followers, { part = p.part, rel = (headRest :: CFrame):ToObjectSpace(p.part.CFrame) })
		end
	end
	return rig
end

-- sums the mix into per-bone channel values (with the pet's damping per clip), then folds the legs for the sink
function PetRig.sample(rig: Rig, mix: Mix, out: Values?): Values
	local vals: Values = out or {}
	for _, b in rig.bones do
		local v = vals[b.name]
		if v then
			table.clear(v)
		else
			vals[b.name] = {}
		end
	end
	local ikSink = 0
	for _, m in mix do
		if m.w <= 0 then
			continue
		end
		local damp = rig.damp[m.name]
		for _, b in rig.bones do
			local f = if damp then damp[b.slot] else nil
			PetClips.addSlot(vals[b.name], m.clip, b.slot, b.right, m.t, m.w, f)
		end
		if m.clip.autoLegs ~= false then
			local rv = {}
			PetClips.addSlot(rv, m.clip, "root", false, m.t, m.w, if damp then damp.root else nil)
			ikSink += rv.sink or 0
		end
	end
	if ikSink > 0 then
		for _, l in rig.legs do
			local a, b = PetClips.legFold(ikSink * rig.hip, l.up.len, l.lo.len)
			local sg = if l.back then -1 else 1
			local vu, vl = vals[l.up.name], vals[l.lo.name]
			vu.px = (vu.px or 0) + sg * a
			vl.px = (vl.px or 0) + sg * b
		end
	end
	return vals
end

-- mixes two value sets: a * (1 - f) + b * f
function PetRig.blend(a: Values, b: Values, f: number, out: Values): Values
	for name, vb in b do
		local va = a[name] or {}
		local o = out[name]
		if o then
			table.clear(o)
		else
			o = {}
			out[name] = o
		end
		for ch, x in vb do
			o[ch] = (va[ch] or 0) * (1 - f) + x * f
		end
		for ch, x in va do
			if vb[ch] == nil then
				o[ch] = x * (1 - f)
			end
		end
	end
	return out
end

local rad = math.rad
local function rot(v: { [string]: number }): CFrame
	return CFrame.fromEulerAnglesYXZ(rad(v.px or 0), rad(v.yw or 0), rad(v.rl or 0))
end

-- poses the bones and returns where the model's pivot goes (base = where the pet stands, like the old pose code)
-- plus the parts and CFrames to BulkMoveTo
function PetRig.apply(rig: Rig, vals: Values, base: CFrame, outParts: { BasePart }, outCFs: { CFrame }, holdBones: boolean?): CFrame
	local h = rig.height
	local rv = vals.Root or {}
	local ra = rig.rootAt
	-- the body's own motion (bob, lean, hop, sink) in the model's frame
	local M = CFrame.new(ra) * CFrame.new((rv.rt or 0) * h, (rv.up or 0) * h - (rv.sink or 0) * rig.hip, -(rv.fwd or 0) * h)
		* rot(rv) * CFrame.new(-ra)
	local cf = base * M
	-- it rides on the Root bone, so the mesh parts only move when the pet travels (moving skinned parts every
	-- frame was half the frame cost with many pets, 2026-11-21)
	local rootBone = rig.byName.Root.bone
	if not rig.rootRest then
		local mainRel = CFrame.identity
		for _, p in rig.parts do
			if p.part == rig.main then
				mainRel = p.rel
				break
			end
		end
		rig.mainRel = mainRel
		rig.rootRest = mainRel * rootBone.CFrame
		rig.rootRestInv = rig.rootRest:Inverse()
	end
	if not holdBones then
		rootBone.Transform = rig.rootRestInv * M * rig.rootRest
		for _, b in rig.bones do
			if b.name ~= "Root" then
				local v = vals[b.name]
				b.bone.Transform = if v and next(v) then b.restInv * rot(v) * b.rest else CFrame.identity
			end
		end
	end
	if base ~= rig.lastBase then
		rig.lastBase = base
		for _, p in rig.parts do
			table.insert(outParts, p.part)
			table.insert(outCFs, base * p.rel)
		end
	end
	if #rig.followers > 0 and #rig.headChain > 0 then
		-- the head's world frame this frame: the main part, then down the bone chain (Root carries the body motion)
		local w = base * rig.mainRel
		for _, bone in rig.headChain do
			w = w * bone.CFrame * bone.Transform
		end
		for _, f in rig.followers do
			table.insert(outParts, f.part)
			table.insert(outCFs, w * f.rel)
		end
	end
	return cf
end

-- the walk / run cycle length in studs: a stride that makes the feet not slide (4 x hip x sin(swing)),
-- or for legless pets the old gait stride
function PetRig.cycleLength(rig: Rig, clip: PetClips.Clip, fallback: number): number
	local sw = clip.swing or 0
	if sw > 0 and #rig.legs > 0 then
		local L = rig.legs[1].up.len + rig.legs[1].lo.len
		return math.max(0.05, 4 * L * math.sin(math.rad(sw)))
	end
	return fallback
end

return PetRig
