--!strict
-- PetEyes: where each 3D pet's painted eyes are, so PetVisuals can lay closed eyelids over them
-- while the pet sleeps. Keyed by the model's name in ReplicatedStorage.PetModels.
-- at: the eye's centre on the face, from the model's pivot, in pet heights (the model is 1 tall)
-- normal: which way the face points there; r: the eye's radius, in pet heights
-- part: which part the lids ride on (Head turns with the head; Body for pets with no head part)
-- lid: the fur or skin colour round the eye
-- Measured 2026-11-09 in Studio: each pet stood 6 studs tall in front of a camera, the eyes were picked
-- from the capture and a ray from the camera found the spot on the mesh. Re-measure if a model changes.

export type Eye = { at: Vector3, normal: Vector3, r: number }
export type Spec = { part: string, lid: Color3, eyes: { Eye } }

local function eye(x: number, y: number, z: number, nx: number, ny: number, nz: number, r: number): Eye
	return { at = Vector3.new(x, y, z), normal = Vector3.new(nx, ny, nz), r = r }
end

local PetEyes: { [string]: Spec } = {
	conehog = { part = "Head", lid = Color3.fromRGB(225, 222, 215), eyes = {
		eye(0.1280, 0.0264, -0.5181, 0.526, 0.217, -0.822, 0.0485),
		eye(-0.1254, 0.0291, -0.5180, -0.527, 0.189, -0.829, 0.0485) } },
	snowbun = { part = "Head", lid = Color3.fromRGB(210, 120, 175), eyes = {
		eye(0.1534, 0.1569, -0.3083, 0.486, 0.447, -0.751, 0.0512),
		eye(-0.1571, 0.1534, -0.3076, -0.472, 0.473, -0.745, 0.0476) } },
	mittenkit = { part = "Head", lid = Color3.fromRGB(205, 128, 40), eyes = {
		eye(0.1693, 0.0851, -0.3006, 0.443, 0.258, -0.858, 0.0461),
		eye(-0.0486, 0.0613, -0.2900, -0.473, -0.060, -0.879, 0.0459) } },
	toddle = { part = "Head", lid = Color3.fromRGB(215, 110, 30), eyes = {
		eye(0.2126, 0.0660, -0.3363, 0.565, 0.074, -0.822, 0.0681),
		eye(-0.1700, 0.0572, -0.3325, -0.306, 0.448, -0.840, 0.0676) } },
	aurora_owl = { part = "Body", lid = Color3.fromRGB(195, 200, 212), eyes = {
		eye(0.1248, 0.0996, -0.1956, 0.407, -0.034, -0.913, 0.0512),
		eye(-0.1026, 0.0488, -0.1951, -0.535, 0.002, -0.845, 0.0552) } },
	blizzard_yeti = { part = "Head", lid = Color3.fromRGB(180, 188, 225), eyes = {
		eye(0.0985, 0.1767, -0.1745, 0.344, 0.046, -0.938, 0.0377),
		eye(-0.0772, 0.1760, -0.1813, -0.346, 0.040, -0.937, 0.0374) } },
	pupcicle = { part = "Head", lid = Color3.fromRGB(228, 222, 110), eyes = {
		eye(0.1712, 0.1010, -0.3265, 0.124, -0.099, -0.987, 0.0538),
		eye(-0.1017, 0.1711, -0.2737, -0.294, 0.386, -0.874, 0.0415) } },
	waddles = { part = "Head", lid = Color3.fromRGB(215, 222, 232), eyes = {
		eye(0.1005, 0.2042, -0.3158, 0.437, 0.249, -0.864, 0.0416),
		eye(-0.1569, 0.1945, -0.3088, -0.268, 0.042, -0.963, 0.0331) } },
	puffball = { part = "Body", lid = Color3.fromRGB(170, 28, 88), eyes = {
		eye(0.2110, 0.0537, -0.4584, 0.157, 0.150, -0.976, 0.0625),
		eye(-0.1594, 0.0982, -0.4574, -0.158, 0.039, -0.987, 0.0790) } },
	hopsprout = { part = "Head", lid = Color3.fromRGB(218, 192, 25), eyes = {
		eye(0.1944, 0.1529, -0.2413, -0.115, 0.554, -0.825, 0.0800),
		eye(-0.1915, 0.1507, -0.2460, 0.171, 0.534, -0.828, 0.0815) } },
	snowglobe_drake = { part = "Head", lid = Color3.fromRGB(205, 40, 48), eyes = {
		eye(0.1302, 0.1065, -0.6124, 0.546, -0.109, -0.831, 0.0596),
		eye(-0.1496, 0.1370, -0.5959, -0.441, 0.073, -0.895, 0.0669) } },
	trufflet = { part = "Head", lid = Color3.fromRGB(105, 62, 48), eyes = {
		eye(0.1378, 0.1768, -0.3956, -0.060, 0.473, -0.879, 0.0412),
		eye(-0.1951, 0.1961, -0.3369, -0.426, 0.149, -0.893, 0.0431) } },
	-- measured 2026-11-09 (second batch): Mushroom Grove TRELLIS pets
	glimmermoth = { part = "Head", lid = Color3.fromRGB(35, 40, 115), eyes = {
		eye(0.1240, 0.0487, -0.2468, 0.231, 0.139, -0.963, 0.0610),
		eye(-0.1240, 0.0487, -0.2466, -0.263, -0.014, -0.965, 0.0610) } },
	shimmerfrog = { part = "Head", lid = Color3.fromRGB(20, 105, 125), eyes = { -- Head here is the eye ridge, no Role
		eye(0.2006, 0.2011, -0.3499, 0.020, 0.132, -0.991, 0.0765),
		eye(-0.1999, 0.1990, -0.3526, 0.003, 0.150, -0.989, 0.0728) } },
	capcrown_badger = { part = "Head", lid = Color3.fromRGB(90, 35, 100), eyes = {
		eye(0.1399, 0.1088, -0.4510, 0.648, 0.031, -0.761, 0.0432),
		eye(-0.1042, 0.1092, -0.5152, -0.367, -0.089, -0.926, 0.0403) } },
	sporewing_drake = { part = "Head", lid = Color3.fromRGB(160, 20, 30), eyes = {
		eye(0.1570, 0.1600, -0.4613, 0.236, 0.266, -0.935, 0.0608),
		eye(-0.0780, 0.1405, -0.4273, -0.759, 0.135, -0.637, 0.0548) } },
	-- measured 2026-11-10: Myco Golem and Sunny Beach TRELLIS pets (eyes found as the biggest dark spots
	-- on a 6-stud front capture; Flopseal's lid colour picked by hand, its eye ring reached the sky)
	myco_golem = { part = "Body", lid = Color3.fromRGB(45, 165, 170), eyes = {
		eye(0.1265, 0.1457, -0.2955, 0.278, 0.180, -0.944, 0.0427),
		eye(-0.1018, 0.1452, -0.3018, -0.250, -0.041, -0.967, 0.0422) } },
	puffsy = { part = "Body", lid = Color3.fromRGB(194, 132, 28), eyes = {
		eye(0.1786, 0.1026, -0.4341, 0.234, 0.093, -0.968, 0.0687),
		eye(-0.1756, 0.1027, -0.4342, -0.216, 0.202, -0.955, 0.0696) } },
	starbit = { part = "Body", lid = Color3.fromRGB(186, 27, 181), eyes = {
		eye(0.1248, 0.0058, -0.1864, 0.208, -0.062, -0.976, 0.0587),
		eye(-0.1184, -0.0253, -0.1844, -0.227, -0.120, -0.966, 0.0523) } },
	flopseal = { part = "Head", lid = Color3.fromRGB(28, 70, 185), eyes = {
		eye(0.1659, 0.2153, -0.4092, 0.400, 0.568, -0.719, 0.0569),
		eye(-0.1444, 0.2116, -0.4187, -0.643, 0.372, -0.670, 0.0528) } },
	-- 2026-11-11: Frostfox (redo) and four Pine Forest pets, eyes found the same way
	frostfox = { part = "Head", lid = Color3.fromRGB(20, 165, 195), eyes = {
		eye(-0.1065, -0.0487, -0.3716, -0.208, 0.326, -0.922, 0.0692),
		eye(0.1298, -0.0539, -0.3639, 0.467, 0.257, -0.846, 0.0699) } },
	capmouse = { part = "Head", lid = Color3.fromRGB(72, 30, 122), eyes = {
		eye(0.1167, 0.0908, -0.2928, 0.287, 0.483, -0.827, 0.0632),
		eye(-0.1209, 0.0879, -0.2493, -0.473, 0.138, -0.870, 0.0654) } },
	mossfawn = { part = "Head", lid = Color3.fromRGB(27, 64, 31), eyes = {
		eye(0.1488, 0.1470, -0.3280, 0.645, 0.063, -0.761, 0.0643),
		eye(-0.0898, 0.1779, -0.3696, -0.378, -0.023, -0.925, 0.0616) } },
	lanternbug = { part = "Body", lid = Color3.fromRGB(215, 215, 232), eyes = {
		eye(0.1281, 0.0401, -0.4690, 0.340, 0.177, -0.924, 0.0686),
		eye(-0.1313, 0.0399, -0.4707, -0.366, 0.144, -0.919, 0.0685) } },
	mapleguard_bear = { part = "Head", lid = Color3.fromRGB(200, 22, 32), eyes = {
		eye(0.1172, 0.1619, -0.2792, 0.269, -0.109, -0.957, 0.0637),
		eye(-0.1187, 0.1616, -0.2632, 0.220, 0.351, -0.910, 0.0646) } },
	-- 2026-11-13: the rest of Sunny Beach. Found in Blender from the cleaned GLB instead of a Studio capture:
	-- a flat-colour orthographic front render, the two biggest round near-black blobs, a ray onto the mesh
	-- (Roblox x = -Blender x, y = Blender z, z = Blender y). Glowfin's eyes are tall ovals: radius covers
	-- their height. The orca's eyes touch its black body, so their pixels were picked by eye.
	glowfin = { part = "Body", lid = Color3.fromRGB(5, 105, 88), eyes = {
		eye(0.1866, 0.2495, -0.2920, 0.763, 0.154, -0.628, 0.0580),
		eye(-0.1857, 0.2486, -0.2921, -0.729, 0.062, -0.681, 0.0580) } },
	pearlsnail = { part = "Head", lid = Color3.fromRGB(196, 172, 20), eyes = {
		eye(0.1682, 0.1288, -0.4764, 0.708, 0.353, -0.612, 0.0729),
		eye(-0.1669, 0.1293, -0.4802, -0.595, 0.417, -0.686, 0.0734) } },
	reefback_turtle = { part = "Head", lid = Color3.fromRGB(188, 80, 62), eyes = {
		eye(0.1455, 0.0194, -0.4606, 0.554, -0.066, -0.830, 0.0484),
		eye(-0.1552, 0.0293, -0.4672, -0.548, 0.124, -0.827, 0.0554) } },
	prismapus = { part = "Head", lid = Color3.fromRGB(118, 46, 156), eyes = {
		eye(0.1603, 0.0643, -0.2211, 0.241, -0.197, -0.950, 0.0542),
		eye(-0.1246, 0.1050, -0.2204, -0.181, 0.052, -0.982, 0.0543) } },
	beacon_orca = { part = "Body", lid = Color3.fromRGB(196, 188, 168), eyes = {
		eye(0.2448, 0.0101, -0.3391, 0.300, 0.148, -0.943, 0.0484),
		eye(-0.0449, 0.0101, -0.3111, -0.231, 0.241, -0.943, 0.0484) } },
	-- Desert Dunes (2026-11-13), same Blender method
	catcus = { part = "Head", lid = Color3.fromRGB(48, 98, 40), eyes = {
		eye(0.1486, 0.0984, -0.3164, 0.076, 0.126, -0.989, 0.0609),
		eye(-0.1531, 0.0953, -0.3174, -0.056, 0.115, -0.992, 0.0576) } },
	fenny = { part = "Head", lid = Color3.fromRGB(196, 100, 22), eyes = {
		eye(0.1186, -0.0042, -0.3416, 0.263, -0.050, -0.964, 0.0585),
		eye(-0.1167, -0.0052, -0.3408, -0.187, 0.031, -0.982, 0.0591) } },
	-- 2026-11-14, measured on the split rigs (find_pet_eyes.py joins the parts)
	lumpkin = { part = "Head", lid = Color3.fromRGB(80, 38, 13), eyes = {
		eye(0.1128, 0.2264, -0.2274, 0.212, 0.146, -0.966, 0.0504),
		eye(-0.1128, 0.2264, -0.2283, -0.093, 0.208, -0.974, 0.0504) } },
	sunfrill = { part = "Head", lid = Color3.fromRGB(168, 28, 20), eyes = {
		eye(0.1245, 0.0765, -0.2709, 0.359, -0.343, -0.868, 0.0436),
		eye(-0.1256, 0.0763, -0.2681, -0.168, -0.405, -0.899, 0.0449) } },
	dunehorn_ram = { part = "Head", lid = Color3.fromRGB(205, 188, 161), eyes = {
		eye(0.1379, 0.1423, -0.3368, 0.275, 0.139, -0.951, 0.0523),
		eye(-0.1373, 0.1422, -0.3379, -0.319, 0.564, -0.762, 0.0513) } },
	-- 2026-11-16
	solaris_sphinx = { part = "Head", lid = Color3.fromRGB(193, 136, 10), eyes = {
		eye(0.1576, 0.1237, -0.3172, 0.095, 0.159, -0.983, 0.0465),
		eye(-0.0880, 0.1253, -0.3092, -0.490, 0.288, -0.823, 0.0486) } },
	scarabit = { part = "Head", lid = Color3.fromRGB(80, 50, 134), eyes = {
		eye(0.1642, 0.1106, -0.3777, -0.377, 0.239, -0.895, 0.0536),
		eye(-0.1730, 0.1028, -0.3807, 0.210, 0.215, -0.954, 0.0645) } },
	-- the face is on the Body (its Head is only the antennae)
	mirage_manta = { part = "Body", lid = Color3.fromRGB(196, 196, 150), eyes = {
		eye(0.1118, 0.1142, -0.1474, 0.230, 0.178, -0.957, 0.0600),
		eye(-0.1138, 0.1146, -0.1473, -0.319, 0.118, -0.940, 0.0596) } },
}

return PetEyes
