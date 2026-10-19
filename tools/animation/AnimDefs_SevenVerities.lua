--!nonstrict
-- AnimDefs_SevenVerities
-- Location: ServerStorage.WeaponAnimTools.Defs_SevenVerities (ModuleScript)
-- The Blade of Seven Verities' animations as AnimTools tables (angles: { rx, ry, rz } degrees,
-- fromEulerAnglesYXZ; for the arms rx = raise forward, rz = raise sideways, ry = swing
-- left(+)/right(-) after raising). Built into ReplicatedStorage.WeaponKits.AnimSources.SevenVerities.
-- Every action starts and ends in HOLD so it blends into the idle carry without a pop.

local HOLD = {
	RightUpperArm = { 30, 0, 24 },
	RightLowerArm = { 122, 0, 0 },
	RightHand = { 0, -55, 0 },
}

local function with(base, extra)
	local t = {}
	for k, v in base do t[k] = v end
	for k, v in extra do t[k] = v end
	return t
end

local REST_UPPER = { UpperTorso = { 0, 0, 0 }, Head = { 0, 0, 0 }, LeftUpperArm = { 0, 0, 0 } }
local START = with(HOLD, REST_UPPER)

local Defs = {}

-- moving carry (walk / run): one hand, the blade trailing low behind at the side, edge down
-- (right arm only, so the run keeps its own legs / left arm). Pose found by a search for
-- "grip at the right hip, blade pointing back-down-out" (UpperTorso space).
local MOVE_HOLD = { RightUpperArm = { -16, -103, -20 }, RightLowerArm = { 39, 0, 0 }, RightHand = { -14, -61, 28 } }
Defs.Hold = {
	looped = true, priority = "Movement", length = 1.6,
	keys = {
		{ t = 0, ease = "Cubic", dir = "InOut", pose = MOVE_HOLD },
		{ t = 0.8, ease = "Cubic", dir = "InOut", pose = { RightUpperArm = { -18, -103, -20 }, RightLowerArm = { 41, 0, 0 }, RightHand = { -14, -61, 28 } } },
		{ t = 1.6, pose = MOVE_HOLD },
	},
}

-- basic attack 1: forehand, right -> left, slightly diagonal
Defs.Swing1 = {
	priority = "Action", length = 0.42,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = START },
		{ t = 0.08, ease = "Cubic", dir = "In", pose = {
			UpperTorso = { 0, -30, 0 }, Head = { 0, 20, 0 }, LeftUpperArm = { 40, 0, -15 },
			RightUpperArm = { 115, -105, 0 }, RightLowerArm = { 25, 0, 0 }, RightHand = { -90, 0, 0 } } },
		{ t = 0.17, ease = "Linear", pose = {
			UpperTorso = { 0, 15, 0 }, Head = { 0, -10, 0 }, LeftUpperArm = { 0, 0, -20 },
			RightUpperArm = { 85, 0, 0 }, RightLowerArm = { 5, 0, 0 }, RightHand = { -90, 0, 0 } } },
		{ t = 0.25, ease = "Cubic", dir = "InOut", pose = {
			UpperTorso = { 0, 35, 0 }, Head = { 0, -25, 0 }, LeftUpperArm = { -25, 0, -25 },
			RightUpperArm = { 60, 65, 0 }, RightLowerArm = { 30, 0, 0 }, RightHand = { -80, 20, 0 } } },
		{ t = 0.42, pose = START },
	},
}

-- basic attack 2: backhand, left -> right
Defs.Swing2 = {
	priority = "Action", length = 0.42,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = START },
		{ t = 0.08, ease = "Cubic", dir = "In", pose = {
			UpperTorso = { 0, 30, 0 }, Head = { 0, -20, 0 }, LeftUpperArm = { -20, 0, -20 },
			RightUpperArm = { 100, 80, 0 }, RightLowerArm = { 60, 0, 0 }, RightHand = { -70, 0, 0 } } },
		{ t = 0.17, ease = "Linear", pose = {
			UpperTorso = { 0, -10, 0 }, Head = { 0, 8, 0 }, LeftUpperArm = { 10, 0, -15 },
			RightUpperArm = { 85, 0, 0 }, RightLowerArm = { 5, 0, 0 }, RightHand = { -90, 0, 0 } } },
		{ t = 0.25, ease = "Cubic", dir = "InOut", pose = {
			UpperTorso = { 0, -35, 0 }, Head = { 0, 25, 0 }, LeftUpperArm = { 35, 0, -15 },
			RightUpperArm = { 70, -95, 0 }, RightLowerArm = { 15, 0, 0 }, RightHand = { -90, -10, 0 } } },
		{ t = 0.42, pose = START },
	},
}

-- Lucky Coin: the free (left) hand flicks the coin up, the head follows it
Defs.CoinToss = {
	priority = "Action", length = 0.95,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = { LeftUpperArm = { 0, 0, 0 }, LeftLowerArm = { 0, 0, 0 }, LeftHand = { 0, 0, 0 }, Head = { 0, 0, 0 } } },
		{ t = 0.12, ease = "Cubic", dir = "In", pose = { LeftUpperArm = { 55, 20, -8 }, LeftLowerArm = { 75, 0, 0 }, LeftHand = { 15, 0, 0 }, Head = { -5, 0, 0 } } },
		{ t = 0.2, ease = "Cubic", dir = "Out", pose = { LeftUpperArm = { 125, 10, -10 }, LeftLowerArm = { 20, 0, 0 }, LeftHand = { -35, 0, 0 }, Head = { 20, 0, 0 } } },
		{ t = 0.5, ease = "Cubic", dir = "InOut", pose = { LeftUpperArm = { 95, 10, -12 }, LeftLowerArm = { 35, 0, 0 }, LeftHand = { -10, 0, 0 }, Head = { 32, 0, 0 } } },
		{ t = 0.95, pose = { LeftUpperArm = { 0, 0, 0 }, LeftLowerArm = { 0, 0, 0 }, LeftHand = { 0, 0, 0 }, Head = { 0, 0, 0 } } },
	},
}

-- Mastered Magic: the sword raised high toward the gates, the free hand pushed forward
local RAISED = {
	UpperTorso = { 8, 0, 0 }, Head = { 8, 0, 0 },
	RightUpperArm = { 160, -15, 15 }, RightLowerArm = { 10, 0, 0 }, RightHand = { -50, 0, 0 },
	LeftUpperArm = { 85, 15, -5 }, LeftLowerArm = { 10, 0, 0 },
}
Defs.MagicRaise = {
	priority = "Action", length = 5.6,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = with(START, { LeftLowerArm = { 0, 0, 0 } }) },
		{ t = 0.25, ease = "Cubic", dir = "InOut", pose = RAISED },
		{ t = 2.8, ease = "Cubic", dir = "InOut", pose = with(RAISED, { RightUpperArm = { 157, -12, 16 }, UpperTorso = { 10, 0, 0 } }) },
		{ t = 5.35, ease = "Cubic", dir = "InOut", pose = RAISED },
		{ t = 5.6, pose = with(START, { LeftLowerArm = { 0, 0, 0 } }) },
	},
}

-- Nightmare Form (2.4 s cutscene, full body): the sword before the face while it turns
-- black, crouch as the body darkens, the transformation roar, then a combat stance
local LEGS_REST = {
	LowerTorso = { 0, 0, 0 }, RightUpperLeg = { 0, 0, 0 }, RightLowerLeg = { 0, 0, 0 }, RightFoot = { 0, 0, 0 },
	LeftUpperLeg = { 0, 0, 0 }, LeftLowerLeg = { 0, 0, 0 }, LeftFoot = { 0, 0, 0 },
	LeftLowerArm = { 0, 0, 0 }, LeftHand = { 0, 0, 0 },
}
local NM_START = with(START, LEGS_REST)
Defs.Nightmare = {
	priority = "Action4", length = 2.4,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = NM_START },
		-- the blade held upright before the face
		{ t = 0.3, ease = "Cubic", dir = "InOut", pose = with(LEGS_REST, {
			UpperTorso = { 0, 10, 0 }, Head = { -8, -8, 0 },
			RightUpperArm = { 70, 35, 0 }, RightLowerArm = { 75, 0, 0 }, RightHand = { 0, 0, 0 },
			LeftUpperArm = { 10, 0, -10 } }) },
		{ t = 0.75, ease = "Cubic", dir = "InOut", pose = with(LEGS_REST, {
			UpperTorso = { -5, 12, 0 }, Head = { -12, -8, 0 },
			RightUpperArm = { 72, 38, 0 }, RightLowerArm = { 80, 0, 0 }, RightHand = { 0, 0, 0 },
			LeftUpperArm = { 10, 0, -12 } }) },
		-- the body darkens: hunched, gathering power
		{ t = 1.15, ease = "Cubic", dir = "In", pose = {
			LowerTorso = { 0, 0, 0, 0, -0.55, 0 }, UpperTorso = { -25, 0, 0 }, Head = { -20, 0, 0 },
			RightUpperArm = { 20, 0, 30 }, RightLowerArm = { 70, 0, 0 }, RightHand = { -40, -30, 0 },
			LeftUpperArm = { 20, 0, -30 }, LeftLowerArm = { 70, 0, 0 }, LeftHand = { 0, 0, 0 },
			RightUpperLeg = { 30, 0, 8 }, RightLowerLeg = { -45, 0, 0 }, RightFoot = { 15, 0, 0 },
			LeftUpperLeg = { 30, 0, -8 }, LeftLowerLeg = { -45, 0, 0 }, LeftFoot = { 15, 0, 0 } } },
		-- the roar: chest up, arms thrown out, head back
		{ t = 1.45, ease = "Cubic", dir = "Out", pose = {
			LowerTorso = { 0, 0, 0, 0, -0.15, 0 }, UpperTorso = { 18, 0, 0 }, Head = { 28, 0, 0 },
			RightUpperArm = { 10, 0, 75 }, RightLowerArm = { 15, 0, 0 }, RightHand = { -80, -20, 0 },
			LeftUpperArm = { 10, 0, -75 }, LeftLowerArm = { 15, 0, 0 }, LeftHand = { 0, 0, 0 },
			RightUpperLeg = { 5, 0, 14 }, RightLowerLeg = { -8, 0, 0 }, RightFoot = { 3, 0, -10 },
			LeftUpperLeg = { 5, 0, -14 }, LeftLowerLeg = { -8, 0, 0 }, LeftFoot = { 3, 0, 10 } } },
		{ t = 1.95, ease = "Cubic", dir = "InOut", pose = {
			LowerTorso = { 0, 0, 0, 0, -0.15, 0 }, UpperTorso = { 22, 0, 0 }, Head = { 32, 0, 0 },
			RightUpperArm = { 12, 0, 80 }, RightLowerArm = { 12, 0, 0 }, RightHand = { -80, -20, 0 },
			LeftUpperArm = { 12, 0, -80 }, LeftLowerArm = { 12, 0, 0 }, LeftHand = { 0, 0, 0 },
			RightUpperLeg = { 5, 0, 14 }, RightLowerLeg = { -8, 0, 0 }, RightFoot = { 3, 0, -10 },
			LeftUpperLeg = { 5, 0, -14 }, LeftLowerLeg = { -8, 0, 0 }, LeftFoot = { 3, 0, 10 } } },
		-- ready: low combat stance, blade forward-low
		{ t = 2.25, ease = "Cubic", dir = "Out", pose = {
			LowerTorso = { 0, -15, 0, 0, -0.35, 0 }, UpperTorso = { -10, 10, 0 }, Head = { 0, 5, 0 },
			RightUpperArm = { 45, -10, 20 }, RightLowerArm = { 25, 0, 0 }, RightHand = { -70, -15, 0 },
			LeftUpperArm = { 20, 0, -25 }, LeftLowerArm = { 30, 0, 0 }, LeftHand = { 0, 0, 0 },
			RightUpperLeg = { 25, 0, 6 }, RightLowerLeg = { -30, 0, 0 }, RightFoot = { 5, 0, 0 },
			LeftUpperLeg = { -10, 0, -8 }, LeftLowerLeg = { -25, 0, 0 }, LeftFoot = { 20, 0, 0 } } },
		{ t = 2.4, pose = {
			LowerTorso = { 0, -15, 0, 0, -0.35, 0 }, UpperTorso = { -10, 10, 0 }, Head = { 0, 5, 0 },
			RightUpperArm = { 45, -10, 20 }, RightLowerArm = { 25, 0, 0 }, RightHand = { -70, -15, 0 },
			LeftUpperArm = { 20, 0, -25 }, LeftLowerArm = { 30, 0, 0 }, LeftHand = { 0, 0, 0 },
			RightUpperLeg = { 25, 0, 6 }, RightLowerLeg = { -30, 0, 0 }, RightFoot = { 5, 0, 0 },
			LeftUpperLeg = { -10, 0, -8 }, LeftLowerLeg = { -25, 0, 0 }, LeftFoot = { 20, 0, 0 } } },
	},
}

-- Moonlight Slash: appear mid-swing, one big diagonal cut down through the enemy
local ML_UP = {
	LowerTorso = { 0, 0, 0, 0, -0.2, 0 }, UpperTorso = { 10, -25, 0 }, Head = { 0, 15, 0 },
	RightUpperArm = { 160, -40, 20 }, RightLowerArm = { 30, 0, 0 }, RightHand = { -30, 0, 0 },
	LeftUpperArm = { 30, 0, -20 }, LeftLowerArm = { 20, 0, 0 },
	RightUpperLeg = { 10, 0, 0 }, RightLowerLeg = { -10, 0, 0 }, LeftUpperLeg = { -5, 0, 0 }, LeftLowerLeg = { -10, 0, 0 },
}
local ML_CUT = {
	LowerTorso = { 0, 0, 0, 0, -0.6, 0 }, UpperTorso = { -20, 30, 0 }, Head = { -5, -15, 0 },
	RightUpperArm = { 40, 50, 0 }, RightLowerArm = { 10, 0, 0 }, RightHand = { -90, 0, 0 },
	LeftUpperArm = { -30, 0, -35 }, LeftLowerArm = { 20, 0, 0 },
	RightUpperLeg = { 45, 0, 0 }, RightLowerLeg = { -40, 0, 0 }, LeftUpperLeg = { -25, 0, 0 }, LeftLowerLeg = { -30, 0, 0 },
}
local ML_END = with(START, {
	LowerTorso = { 0, 0, 0 }, LeftLowerArm = { 0, 0, 0 },
	RightUpperLeg = { 0, 0, 0 }, RightLowerLeg = { 0, 0, 0 }, LeftUpperLeg = { 0, 0, 0 }, LeftLowerLeg = { 0, 0, 0 },
})
Defs.Moonlight = {
	priority = "Action2", length = 0.5,
	keys = {
		{ t = 0, ease = "Cubic", dir = "In", pose = ML_UP },
		{ t = 0.1, ease = "Cubic", dir = "Out", pose = ML_CUT },
		{ t = 0.28, ease = "Cubic", dir = "InOut", pose = ML_CUT },
		{ t = 0.5, pose = ML_END },
	},
}

-- ===================================================================== Superior upgrade (2026-10-07)
-- basic attack 3: overhead diagonal, right shoulder high -> down to the left
Defs.Swing3 = {
	priority = "Action", length = 0.45,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = START },
		{ t = 0.09, ease = "Cubic", dir = "In", pose = {
			UpperTorso = { 6, -22, 0 }, Head = { 5, 15, 0 }, LeftUpperArm = { 60, 0, -10 },
			RightUpperArm = { 165, -30, 10 }, RightLowerArm = { 30, 0, 0 }, RightHand = { -60, 0, 0 } } },
		{ t = 0.19, ease = "Linear", pose = {
			UpperTorso = { -14, 12, 0 }, Head = { -5, -5, 0 }, LeftUpperArm = { 20, 0, -20 },
			RightUpperArm = { 85, 15, 0 }, RightLowerArm = { 5, 0, 0 }, RightHand = { -100, 0, 0 } } },
		{ t = 0.27, ease = "Cubic", dir = "InOut", pose = {
			UpperTorso = { -22, 30, 0 }, Head = { -10, -15, 0 }, LeftUpperArm = { -20, 0, -25 },
			RightUpperArm = { 30, 60, 0 }, RightLowerArm = { 20, 0, 0 }, RightHand = { -90, 25, 0 } } },
		{ t = 0.45, pose = START },
	},
}

-- finisher: a full 360 spin (the whole body turns on the root, counter-clockwise), blade out
local SPIN_ARM = { RightUpperArm = { 90, -35, 0 }, RightLowerArm = { 5, 0, 0 }, RightHand = { -90, 0, 0 },
	UpperTorso = { -6, 0, 0 }, Head = { 0, 0, 0 }, LeftUpperArm = { 20, 0, -50 }, LeftLowerArm = { 10, 0, 0 } }
local function spinAt(deg, drop)
	return with(SPIN_ARM, { LowerTorso = { 0, deg, 0, 0, -(drop or 0.3), 0 },
		RightUpperLeg = { 20, 0, 8 }, RightLowerLeg = { -25, 0, 0 }, LeftUpperLeg = { 20, 0, -8 }, LeftLowerLeg = { -25, 0, 0 } })
end
local SPIN_REST = with(START, { LowerTorso = { 0, 0, 0 }, LeftLowerArm = { 0, 0, 0 },
	RightUpperLeg = { 0, 0, 0 }, RightLowerLeg = { 0, 0, 0 }, LeftUpperLeg = { 0, 0, 0 }, LeftLowerLeg = { 0, 0, 0 } })
Defs.Spin = {
	priority = "Action", length = 0.62,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = SPIN_REST },
		{ t = 0.08, ease = "Cubic", dir = "In", pose = with(spinAt(-45, 0.25), { RightUpperArm = { 90, -100, 0 }, UpperTorso = { -8, -15, 0 } }) },
		{ t = 0.15, ease = "Linear", pose = spinAt(45) },
		{ t = 0.22, ease = "Linear", pose = spinAt(135) },
		{ t = 0.29, ease = "Linear", pose = spinAt(225) },
		{ t = 0.36, ease = "Linear", pose = spinAt(315) },
		{ t = 0.43, ease = "Cubic", dir = "Out", pose = spinAt(370, 0.35) },
		{ t = 0.62, pose = SPIN_REST },
	},
}

-- idle (standing still): relaxed swordsman -- the blade rests flat on the right shoulder, the
-- grip in front of the right chest (searched: grip (0.45, 0.47, -0.77), blade (0.2, 0.51, 0.83),
-- flat, clearing the shoulder top), weight on the right leg, free arm loose, a slow breath
local IDLE_A = {
	LowerTorso = { 0, -10, 3, 0, -0.05, 0 }, UpperTorso = { -3, 8, -2 }, Head = { -2, -6, 3 },
	RightUpperArm = { 22, 51, 5 }, RightLowerArm = { 100, 0, 0 }, RightHand = { 18, 29, -56 },
	LeftUpperArm = { 4, 0, -10 }, LeftLowerArm = { 14, 0, 0 }, LeftHand = { 0, 0, 0 },
	RightUpperLeg = { 2, 0, 4 }, RightLowerLeg = { -3, 0, 0 }, RightFoot = { 1, 0, 0 },
	LeftUpperLeg = { 8, 0, -9 }, LeftLowerLeg = { -10, 0, 0 }, LeftFoot = { 4, 0, 6 },
}
local IDLE_B = with(IDLE_A, {
	LowerTorso = { 0, -10, 3, 0, -0.08, 0 }, UpperTorso = { -1.5, 8, -2 }, Head = { -1, -6, 3 },
	RightUpperArm = { 23, 51, 5 }, LeftUpperArm = { 5, 0, -11 },
})
Defs.Idle = {
	looped = true, priority = "Movement", length = 3.6,
	keys = {
		{ t = 0, ease = "Cubic", dir = "InOut", pose = IDLE_A },
		{ t = 1.8, ease = "Cubic", dir = "InOut", pose = IDLE_B },
		{ t = 3.6, pose = IDLE_A },
	},
}

-- equip flourish: the sword thrust up to the sky, held a beat, cut down to the side, then the carry
local EQ_UP = {
	UpperTorso = { 12, 0, 0 }, Head = { 18, 0, 0 },
	RightUpperArm = { 170, -5, 8 }, RightLowerArm = { 5, 0, 0 }, RightHand = { -30, 0, 0 },
	LeftUpperArm = { 10, 0, -35 }, LeftLowerArm = { 10, 0, 0 },
}
Defs.Equip = {
	priority = "Action", length = 1.1,
	keys = {
		{ t = 0, ease = "Cubic", dir = "Out", pose = with(START, { LeftLowerArm = { 0, 0, 0 } }) },
		{ t = 0.22, ease = "Cubic", dir = "InOut", pose = EQ_UP },
		{ t = 0.55, ease = "Cubic", dir = "In", pose = with(EQ_UP, { UpperTorso = { 14, 0, 0 }, RightUpperArm = { 172, -5, 9 } }) },
		{ t = 0.72, ease = "Cubic", dir = "Out", pose = {
			UpperTorso = { -6, -15, 0 }, Head = { -4, 8, 0 },
			RightUpperArm = { 60, -60, 20 }, RightLowerArm = { 10, 0, 0 }, RightHand = { -90, 0, 0 },
			LeftUpperArm = { 5, 0, -25 }, LeftLowerArm = { 10, 0, 0 } } },
		{ t = 1.1, pose = with(START, { LeftLowerArm = { 0, 0, 0 } }) },
	},
}

return Defs
