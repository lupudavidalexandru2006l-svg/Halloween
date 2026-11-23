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
	emberpup = { part = "Head", lid = Color3.fromRGB(200, 88, 8), eyes = {
		eye(0.1271, 0.1186, -0.3088, 0.029, 0.066, -0.997, 0.0561),
		eye(-0.1279, 0.1191, -0.3088, -0.107, 0.118, -0.987, 0.0558) } },
	-- black eyes on a black face: picked by hand (find_pet_eyes px=211,206,22;382,206,22); lids a shade lighter
	obby = { part = "Head", lid = Color3.fromRGB(46, 42, 56), eyes = {
		eye(0.1622, 0.1714, -0.3617, 0.305, 0.119, -0.945, 0.0444),
		eye(-0.1513, 0.1714, -0.3673, -0.240, 0.096, -0.966, 0.0444) } },
	flarechick = { part = "Head", lid = Color3.fromRGB(190, 31, 110), eyes = {
		eye(0.1421, 0.0261, -0.2697, -0.140, 0.183, -0.973, 0.0587),
		eye(-0.1335, 0.0243, -0.2691, 0.075, -0.010, -0.997, 0.0581) } },
	geodillo = { part = "Head", lid = Color3.fromRGB(112, 74, 139), eyes = {
		eye(0.1625, 0.0715, -0.3258, 0.330, -0.095, -0.939, 0.0545),
		eye(-0.1612, 0.0720, -0.3256, -0.206, -0.056, -0.977, 0.0550) } },
	pyrokoi = { part = "Head", lid = Color3.fromRGB(208, 178, 145), eyes = {
		eye(0.1350, 0.1408, -0.2810, 0.497, 0.122, -0.859, 0.0496),
		eye(-0.1346, 0.1378, -0.2815, -0.441, -0.040, -0.897, 0.0473) } },
	magmallow = { part = "Head", lid = Color3.fromRGB(195, 169, 117), eyes = {
		eye(0.1659, 0.1459, -0.3464, 0.100, 0.090, -0.991, 0.0580),
		eye(-0.1552, 0.1513, -0.3503, -0.168, 0.209, -0.963, 0.0526) } },
	sizzlemander = { part = "Head", lid = Color3.fromRGB(77, 168, 34), eyes = {
		eye(0.1939, 0.1436, -0.3717, 0.618, 0.056, -0.784, 0.0585),
		eye(-0.1944, 0.1434, -0.3734, -0.617, 0.104, -0.780, 0.0563) } },
	lavalamp_jelly = { part = "Head", lid = Color3.fromRGB(8, 56, 140), eyes = {
		eye(0.0964, 0.0525, -0.4342, 0.191, 0.178, -0.965, 0.0560),
		eye(-0.0981, 0.0549, -0.4314, -0.297, 0.107, -0.949, 0.0587) } },
	thunderchick = { part = "Head", lid = Color3.fromRGB(208, 188, 6), eyes = {
		eye(0.1242, 0.1075, -0.2601, 0.389, 0.137, -0.911, 0.0507),
		eye(-0.1232, 0.1078, -0.2596, -0.173, 0.147, -0.974, 0.0513) } },
	jade_qilin = { part = "Head", lid = Color3.fromRGB(56, 132, 92), eyes = {
		eye(0.1109, 0.0987, -0.2893, 0.306, -0.014, -0.952, 0.0440),
		eye(-0.1115, 0.0975, -0.2889, -0.379, 0.011, -0.925, 0.0452) } },
	starwing_griffin = { part = "Head", lid = Color3.fromRGB(12, 88, 151), eyes = {
		eye(0.1236, 0.1161, -0.3069, 0.235, 0.158, -0.959, 0.0529),
		eye(-0.1221, 0.1163, -0.3070, -0.308, -0.025, -0.951, 0.0527) } },
	hoodoo_golem = { part = "Head", lid = Color3.fromRGB(80, 137, 139), eyes = {
		eye(0.1215, -0.0079, -0.1657, 0.366, 0.132, -0.921, 0.0421),
		eye(-0.1215, -0.0078, -0.1655, -0.363, 0.150, -0.920, 0.0407) } },
	hoodoo_hare = { part = "Head", lid = Color3.fromRGB(179, 96, 34), eyes = {
		eye(0.1241, 0.0483, -0.2248, 0.501, 0.130, -0.856, 0.0448),
		eye(-0.1254, 0.0475, -0.2237, -0.486, 0.136, -0.863, 0.0433) } },
	ringo = { part = "Head", lid = Color3.fromRGB(193, 55, 101), eyes = {
		eye(0.1236, 0.1260, -0.3762, -0.360, -0.007, -0.933, 0.0542),
		eye(-0.1215, 0.1281, -0.3759, 0.243, 0.367, -0.898, 0.0534) } },
	cliffkid = { part = "Head", lid = Color3.fromRGB(193, 184, 165), eyes = {
		eye(0.1459, 0.1546, -0.3292, 0.536, 0.138, -0.833, 0.0339),
		eye(-0.1336, 0.1493, -0.3373, -0.434, 0.097, -0.895, 0.0345) } },
	glowbat = { part = "Head", lid = Color3.fromRGB(72, 63, 121), eyes = {
		eye(0.1174, 0.1150, -0.2226, 0.466, -0.002, -0.885, 0.0457),
		eye(-0.1199, 0.1149, -0.2237, -0.510, -0.070, -0.857, 0.0453) } },
	-- Lava Lake (island 9), 2026-11-20: found in Blender (pet_rig.py eyes: dark, low-saturation faces facing
	-- front), from the bounding-box centre. Bubblava's left eye mirrored from its right; Paddleduck read off the grid.
	bubblava = { part = "Head", lid = Color3.fromRGB(230, 100, 20), eyes = {
		eye(-0.1876, 0.1374, -0.2686, -0.470, 0.092, -0.878, 0.0401),
		eye(0.1876, 0.1374, -0.2686, 0.470, 0.092, -0.878, 0.0401) } },
	crustacrab = { part = "Head", lid = Color3.fromRGB(90, 42, 154), eyes = {
		eye(-0.1172, 0.3966, 0.0238, 0.073, 0.178, -0.981, 0.0481),
		eye(0.1444, 0.3976, 0.0112, 0.052, 0.408, -0.911, 0.0474) } },
	paddleduck = { part = "Head", lid = Color3.fromRGB(240, 196, 26), eyes = {
		eye(0.1500, 0.1950, -0.1900, 0.600, 0.100, -0.790, 0.0280),
		eye(-0.1200, 0.1950, -0.1900, -0.600, 0.100, -0.790, 0.0280) } },
	basalt_beaver = { part = "Head", lid = Color3.fromRGB(107, 62, 31), eyes = {
		eye(-0.1341, 0.1229, -0.4201, -0.297, 0.088, -0.951, 0.0452),
		eye(0.1742, 0.1363, -0.3859, 0.578, 0.334, -0.744, 0.0391) } },
	ember_eel = { part = "Head", lid = Color3.fromRGB(196, 26, 122), eyes = {
		eye(-0.0454, 0.3085, -0.2073, -0.580, 0.097, -0.808, 0.0300),
		eye(0.1637, 0.3050, -0.2642, 0.265, 0.411, -0.872, 0.0300) } },
	caldera_hippo = { part = "Head", lid = Color3.fromRGB(22, 122, 122), eyes = {
		eye(-0.1892, 0.1690, -0.3576, -0.398, 0.269, -0.877, 0.0419),
		eye(0.1856, 0.1695, -0.3581, 0.334, 0.251, -0.909, 0.0407) } },
	obsidian_swan = { part = "Head", lid = Color3.fromRGB(90, 31, 160), eyes = {
		eye(-0.1108, 0.2690, -0.0930, -0.498, 0.082, -0.863, 0.0284),
		eye(0.0445, 0.2161, -0.2323, 0.301, 0.126, -0.945, 0.0364) } },
	lakeheart_serpent = { part = "Head", lid = Color3.fromRGB(176, 19, 42), eyes = {
		eye(-0.1596, 0.2886, -0.2039, -0.255, 0.260, -0.932, 0.0521),
		eye(0.1674, 0.2148, -0.2070, 0.126, 0.147, -0.981, 0.0547) } },
	-- Magma Core (island 10), 2026-11-20: find_pet_eyes.py on each <key>_rig.glb
	coreling = { part = "Head", lid = Color3.fromRGB(181, 67, 0), eyes = {
		eye(0.2035, 0.0879, -0.4357, 0.192, -0.046, -0.980, 0.0798),
		eye(-0.2022, 0.0931, -0.4307, -0.264, 0.153, -0.952, 0.0765) } },
	sparkmole = { part = "Head", lid = Color3.fromRGB(22, 28, 61), eyes = {
		eye(0.1644, 0.1402, -0.3396, 0.494, -0.093, -0.865, 0.0593),
		eye(-0.1640, 0.1400, -0.3400, -0.471, -0.054, -0.880, 0.0585) } },
	ironhorn_beetle = { part = "Head", lid = Color3.fromRGB(83, 65, 46), eyes = {
		eye(0.1744, -0.1082, -0.3785, 0.292, 0.179, -0.939, 0.0625),
		eye(-0.1730, -0.1085, -0.3736, -0.530, -0.106, -0.841, 0.0626) } },
	-- Pyrolamb 2026-11-21 (this PC): eyes measured on the rig grid (the eye finder caught a cheek)
	pyrolamb = { part = "Head", lid = Color3.fromRGB(40, 36, 38), eyes = {
		eye(0.146, 0.150, -0.470, 0.25, 0.05, -0.97, 0.042),
		eye(-0.146, 0.150, -0.470, -0.25, 0.05, -0.97, 0.042) } },
	thermowl = { part = "Head", lid = Color3.fromRGB(123, 183, 205), eyes = {
		eye(0.1305, 0.1298, -0.2707, 0.107, 0.101, -0.989, 0.0608),
		eye(-0.1358, 0.1262, -0.2748, -0.044, 0.116, -0.992, 0.0606) } },
	forge_bear = { part = "Head", lid = Color3.fromRGB(176, 6, 3), eyes = {
		eye(0.1334, 0.1231, -0.3736, 0.176, 0.010, -0.984, 0.0553),
		eye(-0.1328, 0.1228, -0.3754, -0.362, -0.060, -0.930, 0.0536) } },
	coreflare_drake = { part = "Head", lid = Color3.fromRGB(204, 173, 15), eyes = {
		eye(0.1262, 0.1305, -0.3470, 0.272, -0.184, -0.944, 0.0576),
		eye(-0.1270, 0.1324, -0.3476, -0.264, -0.221, -0.939, 0.0573) } },
	planetcore_turtle = { part = "Head", lid = Color3.fromRGB(113, 18, 169), eyes = {
		eye(0.1630, 0.2315, -0.4716, 0.277, 0.083, -0.957, 0.0685),
		eye(-0.1642, 0.2333, -0.4710, -0.198, 0.181, -0.963, 0.0687) } },
}

return PetEyes
