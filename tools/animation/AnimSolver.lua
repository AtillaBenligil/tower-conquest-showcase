--!nonstrict
-- AnimSolver (Studio-only authoring helper)
-- Location: ServerStorage.WeaponAnimTools.AnimSolver (ModuleScript)
-- Finds arm angles (AnimTools pose format: { rx, ry, rz } degrees) for a held weapon:
--   Grip(rig, pose, target)  right arm: the weapon's grip (GearVisuals' WeaponGrip offset from
--                            the RightHand) at target.pos with its -Z along target.dir
--                            (both in UpperTorso space) and, optionally, target.up for the roll
--   Reach(rig, pose, side, point, palm?)  left/right arm: the hand at `point` (UpperTorso space)
-- target.root / opts.root = true: positions + directions in HumanoidRootPart space instead.
-- `pose` = the rest of the body (torso/head/legs angles) the arms hang from. Coordinate descent
-- with shrinking steps from a few starting guesses; returns the arm entries + the error.

local AnimTools = require(script.Parent.AnimTools)

local Solver = {}

local function grip(hand: BasePart): CFrame
	local hs = hand.Size
	return hand.CFrame * CFrame.new(0, -hs.Y * 0.15, -hs.Z / 2 + 0.25)
end
Solver.GripOffset = grip

local function transforms(pose: {[string]: any}): {[string]: CFrame}
	local out = {}
	for name, v in pose do out[name] = AnimTools.CF(v) end
	return out
end

-- generic coordinate descent over `vars` (list of { joint, axis(1..3), lo, hi })
local function descend(rig: Model, pose: {[string]: any}, vars, cost: () -> number, starts: {{number}})
	local best, bestCost = nil, math.huge
	for _, start in starts do
		local x = table.clone(start)
		local function apply()
			for i, v in vars do
				local j = pose[v[1]] or { 0, 0, 0 }
				j = table.clone(j)
				j[v[2]] = x[i]
				pose[v[1]] = j
			end
			AnimTools.Pose(rig, transforms(pose))
		end
		apply()
		local c = cost()
		local step = 24
		while step > 0.2 do
			local improved = false
			for i, v in vars do
				for _, sgn in { 1, -1 } do
					local old = x[i]
					x[i] = math.clamp(old + sgn * step, v[3], v[4])
					apply()
					local nc = cost()
					if nc < c - 1e-6 then
						c = nc
						improved = true
					else
						x[i] = old
					end
				end
			end
			if not improved then step *= 0.5 end
		end
		if c < bestCost then bestCost, best = c, table.clone(x) end
	end
	-- leave the rig in the best pose
	for i, v in vars do
		local j = table.clone(pose[v[1]] or { 0, 0, 0 })
		j[v[2]] = math.floor(best[i] * 10 + 0.5) / 10
		pose[v[1]] = j
	end
	AnimTools.Pose(rig, transforms(pose))
	return bestCost
end

local function torsoCF(rig: Model): CFrame
	return (rig:FindFirstChild("UpperTorso") :: BasePart).CFrame
end

-- the frame targets are given in: UpperTorso (default) or the HumanoidRootPart (opts.root)
local function spaceCF(rig: Model, root: boolean?): CFrame
	if root then return (rig:FindFirstChild("HumanoidRootPart") :: BasePart).CFrame end
	return torsoCF(rig)
end

-- right hand holds the weapon: grip at target.pos, weapon -Z along target.dir, target.up = roll
function Solver.Grip(rig: Model, pose: {[string]: any}, target)
	local hand = rig:FindFirstChild("RightHand") :: BasePart
	local vars = {
		{ "RightUpperArm", 1, -80, 190 }, { "RightUpperArm", 2, -120, 120 }, { "RightUpperArm", 3, -60, 170 },
		{ "RightLowerArm", 1, 0, 150 },
		{ "RightHand", 1, -70, 70 }, { "RightHand", 2, -60, 60 }, { "RightHand", 3, -50, 50 },
	}
	local function cost()
		local t = spaceCF(rig, target.root)
		local g = t:ToObjectSpace(grip(hand))
		local c = (g.Position - target.pos).Magnitude ^ 2 * 4
		c += (1 - g.LookVector:Dot(target.dir.Unit)) * 6
		if target.up then c += (1 - g.UpVector:Dot(target.up.Unit)) * 1.5 end
		-- prefer a relaxed wrist
		local w = pose.RightHand or { 0, 0, 0 }
		c += ((w[1] or 0) ^ 2 + (w[2] or 0) ^ 2 + (w[3] or 0) ^ 2) * 2e-5
		return c
	end
	local starts = target.starts or { { 40, 0, 20, 60, 0, 0, 0 }, { 120, -30, 40, 90, 0, 0, 0 }, { 0, 60, 90, 100, 0, 0, 0 }, { 160, 0, 10, 40, 0, 0, 0 } }
	return descend(rig, pose, vars, cost, starts)
end

-- a hand (palm centre) at `point`
function Solver.Reach(rig: Model, pose: {[string]: any}, side: string, point: Vector3, opts)
	local s = if side == "Left" then -1 else 1
	local hand = rig:FindFirstChild(side .. "Hand") :: BasePart
	local vars = {
		{ side .. "UpperArm", 1, -80, 190 }, { side .. "UpperArm", 2, -120, 120 }, { side .. "UpperArm", 3, if s > 0 then -60 else -170, if s > 0 then 170 else 60 },
		{ side .. "LowerArm", 1, 0, 150 },
		{ side .. "Hand", 1, -60, 60 }, { side .. "Hand", 3, -40, 40 },
	}
	local function cost()
		local t = spaceCF(rig, opts and opts.root)
		local h = t:ToObjectSpace(hand.CFrame)
		local c = (h.Position - point).Magnitude ^ 2 * 4
		if opts and opts.palm then c += (1 - (-h.RightVector * s):Dot(opts.palm.Unit)) * 0.8 end
		local w = pose[side .. "Hand"] or { 0, 0, 0 }
		c += ((w[1] or 0) ^ 2 + (w[3] or 0) ^ 2) * 2e-5
		return c
	end
	local starts = (opts and opts.starts) or { { 40, 0, 20 * s, 60, 0, 0 }, { 120, 30 * s, -40 * s, 90, 0, 0 }, { 160, 0, -10 * s, 40, 0, 0 } }
	return descend(rig, pose, vars, cost, starts)
end

return Solver
