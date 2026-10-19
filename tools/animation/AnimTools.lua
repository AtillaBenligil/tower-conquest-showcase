--!nonstrict
-- AnimTools (Studio-only authoring helpers)
-- Location: ServerStorage.WeaponAnimTools.AnimTools (ModuleScript)
-- Author R15 animations as small tables, preview them on a posed rig in Edit mode (forward
-- kinematics with the same maths the Animator uses: Part1 = Part0 * Att0 * Transform * Att1^-1,
-- so it works for Motor6D and AnimationConstraint rigs alike), and build KeyframeSequences.
-- Animation table:
--   { length = s, looped = bool, priority = "Action", keys = {
--       { t = s, ease = "Cubic", dir = "Out", pose = { RightUpperArm = { rx, ry, rz, [x, y, z] }, ... } }, ... } }
--   angles in degrees (CFrame.fromEulerAnglesYXZ: Ry*Rx*Rz), offsets in studs.
--   Pose names are the moving part (the joint's Part1): LowerTorso (Root), UpperTorso (Waist),
--   Head (Neck), Right/LeftUpperArm (Shoulder), ...LowerArm (Elbow), ...Hand (Wrist),
--   ...UpperLeg (Hip), ...LowerLeg (Knee), ...Foot (Ankle).
--   A joint keyed in any key is keyed in every key (missing = rest), others stay free so the
--   default walk/idle keeps playing on them.

local AnimTools = {}

AnimTools.JOINTS = {
	LowerTorso = { "HumanoidRootPart", "RootRigAttachment" },
	UpperTorso = { "LowerTorso", "WaistRigAttachment" },
	Head = { "UpperTorso", "NeckRigAttachment" },
	RightUpperArm = { "UpperTorso", "RightShoulderRigAttachment" },
	RightLowerArm = { "RightUpperArm", "RightElbowRigAttachment" },
	RightHand = { "RightLowerArm", "RightWristRigAttachment" },
	LeftUpperArm = { "UpperTorso", "LeftShoulderRigAttachment" },
	LeftLowerArm = { "LeftUpperArm", "LeftElbowRigAttachment" },
	LeftHand = { "LeftLowerArm", "LeftWristRigAttachment" },
	RightUpperLeg = { "LowerTorso", "RightHipRigAttachment" },
	RightLowerLeg = { "RightUpperLeg", "RightKneeRigAttachment" },
	RightFoot = { "RightLowerLeg", "RightAnkleRigAttachment" },
	LeftUpperLeg = { "LowerTorso", "LeftHipRigAttachment" },
	LeftLowerLeg = { "LeftUpperLeg", "LeftKneeRigAttachment" },
	LeftFoot = { "LeftLowerLeg", "LeftAnkleRigAttachment" },
}
AnimTools.ORDER = {
	"LowerTorso", "UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperLeg", "RightLowerLeg", "RightFoot",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
}

-- { rx, ry, rz, [x, y, z] } -> CFrame: yaw (ry) is applied last, about the parent's up axis,
-- so { 90, -40, 0 } = "arm raised forward, then swung 40 deg to the right". A CFrame passes through.
function AnimTools.CF(v: any): CFrame
	if not v then return CFrame.identity end
	if typeof(v) == "CFrame" then return v end
	local rot = CFrame.fromEulerAnglesYXZ(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
	return CFrame.new(v[4] or 0, v[5] or 0, v[6] or 0) * rot
end

-- ===== preview =====
function AnimTools.Pose(rig: Model, transforms: {[string]: CFrame})
	for _, name in AnimTools.ORDER do
		local j = AnimTools.JOINTS[name]
		local p0, p1 = rig:FindFirstChild(j[1]), rig:FindFirstChild(name)
		if p0 and p1 then
			local a0, a1 = p0:FindFirstChild(j[2]), p1:FindFirstChild(j[2])
			if a0 and a1 then
				p1.CFrame = p0.CFrame * a0.CFrame * (transforms[name] or CFrame.identity) * a1.CFrame:Inverse()
			end
		end
	end
	-- the held weapon (any child model with a GearId), exactly like GearVisuals' WeaponGrip weld
	local hand = rig:FindFirstChild("RightHand")
	if hand then
		local hs = hand.Size
		for _, m in rig:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("GearId") then
				m:PivotTo(hand.CFrame * CFrame.new(0, -hs.Y * 0.15, -hs.Z / 2 + 0.25))
			end
		end
	end
end

local EASE = {
	Linear = function(a) return a end,
	Constant = function(_) return 0 end,
	Cubic = function(a, dir)
		if dir == "In" then return a ^ 3 end
		if dir == "Out" then return 1 - (1 - a) ^ 3 end
		return if a < 0.5 then 4 * a ^ 3 else 1 - (-2 * a + 2) ^ 3 / 2
	end,
	Quad = function(a, dir)
		if dir == "In" then return a * a end
		if dir == "Out" then return 1 - (1 - a) ^ 2 end
		return if a < 0.5 then 2 * a * a else 1 - (-2 * a + 2) ^ 2 / 2
	end,
}

local function jointsOf(def): {string}
	local set, list = {}, {}
	for _, k in def.keys do
		for name in k.pose do
			if not set[name] then
				set[name] = true
				table.insert(list, name)
			end
		end
	end
	return list
end

-- The transforms of `def` at time t (easing of the key we leave, like the Animator).
function AnimTools.Sample(def, t: number): {[string]: CFrame}
	local keys = def.keys
	local out = {}
	local joints = jointsOf(def)
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then a, b = keys[i], keys[i + 1] break end
	end
	if t <= keys[1].t then a, b = keys[1], keys[1] end
	if t >= keys[#keys].t then a, b = keys[#keys], keys[#keys] end
	local span = b.t - a.t
	local alpha = if span > 0 then (t - a.t) / span else 0
	local f = EASE[a.ease or "Linear"] or EASE.Linear
	alpha = f(alpha, a.dir or "InOut")
	for _, name in joints do
		out[name] = AnimTools.CF(a.pose[name]):Lerp(AnimTools.CF(b.pose[name]), alpha)
	end
	return out
end

function AnimTools.PoseAt(rig: Model, def, t: number)
	AnimTools.Pose(rig, AnimTools.Sample(def, t))
end

-- ===== KeyframeSequence =====
local PARENT_OF = {}
for name, j in AnimTools.JOINTS do PARENT_OF[name] = j[1] end

function AnimTools.Build(name: string, def): KeyframeSequence
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = def.looped == true
	kfs.Priority = Enum.AnimationPriority[def.priority or "Action"]
	local keyed = {}
	for _, j in jointsOf(def) do keyed[j] = true end
	-- every pose a keyed joint needs on its way down from the root
	local needed = { HumanoidRootPart = true }
	for j in keyed do
		local n = j
		while n and n ~= "HumanoidRootPart" do
			needed[n] = true
			n = PARENT_OF[n]
		end
	end
	for _, k in def.keys do
		local kf = Instance.new("Keyframe")
		kf.Time = k.t
		local poses = {}
		local function poseFor(n: string): Pose
			if poses[n] then return poses[n] end
			local p = Instance.new("Pose")
			p.Name = n
			if keyed[n] then
				p.CFrame = AnimTools.CF(k.pose[n])
				p.Weight = 1
				-- CubicV2 = the standard cubic curve the preview uses (legacy Cubic has In/Out swapped)
				local style = if k.ease == "Cubic" or k.ease == "Quad" then "CubicV2" else (k.ease or "Linear")
				local ok = pcall(function() p.EasingStyle = (Enum.PoseEasingStyle :: any)[style] end)
				if not ok then p.EasingStyle = Enum.PoseEasingStyle.Cubic end
				p.EasingDirection = Enum.PoseEasingDirection[k.dir or "InOut"]
			else
				p.Weight = 0 -- container only: leaves the joint to other animations
			end
			poses[n] = p
			if n == "HumanoidRootPart" then
				p.Parent = kf
			else
				p.Parent = poseFor(PARENT_OF[n])
			end
			return p
		end
		for n in needed do poseFor(n) end
		if k.marker then
			local m = Instance.new("KeyframeMarker")
			m.Name = k.marker
			m.Parent = kf
		end
		kf.Parent = kfs
	end
	-- make the clip exactly `length` long
	if def.length and def.length > def.keys[#def.keys].t + 1e-3 then
		local last = def.keys[#def.keys]
		local kf = Instance.new("Keyframe")
		kf.Time = def.length
		local poses = {}
		local function poseFor(n: string): Pose
			if poses[n] then return poses[n] end
			local p = Instance.new("Pose")
			p.Name = n
			if keyed[n] then
				p.CFrame = AnimTools.CF(last.pose[n])
				p.Weight = 1
			else
				p.Weight = 0
			end
			poses[n] = p
			p.Parent = if n == "HumanoidRootPart" then kf else poseFor(PARENT_OF[n])
			return p
		end
		for n in needed do poseFor(n) end
		kf.Parent = kfs
	end
	return kfs
end

return AnimTools
