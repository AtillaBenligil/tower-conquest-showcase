--!strict
-- Fx.ThornOfTheAxis
-- Location: ReplicatedStorage.WeaponKits.Fx.ThornOfTheAxis (ModuleScript, client only)
-- Thorn of the Axis (server kit: ServerScriptService.WeaponKits.Kits.ThornOfTheAxis).
--   Presence   always: a crimson aura with a white inner side licking up from the whole body
--              (flames, rising filaments, wisps, light) -- stronger while the Thorn is up.
--              In a gamemode (player attribute InRun): 10 small spinning red gates in a
--              half-ring behind the back (same layout as the server: GateOffset).
--   Volley     basic attack: one thin wavering laser-arrow per enemy, each out of its own
--              gate; 4-step gesture chain (point / sweep = curving arrows / both arms = fast
--              arrows / finisher = gates flare + heavy spear-arrows).
--   Thorn      Creator of Thorn: the crimson flame-crystal thorn rises out of the top gates
--              and floats upright behind the back for 10 s, its two red rings orbiting.
--   Bleed      blood drops off a bleeding enemy.
--   Miracle    crimson glass creatures with red trails: dogs + birds follow the server's
--              decoys (workspace.WeaponSummons, smoothed), fish orbit the players they serve.
--   Bite/Peck  dog lunge + bite flash, bird laser-feather.
--   RedRain    levitation, the roof of the field fills with gates, red rain pours down.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WeaponKits = ReplicatedStorage:WaitForChild("WeaponKits")
local Fx = require(WeaponKits:WaitForChild("FxUtil"))
local Tex = require(WeaponKits:WaitForChild("TextureIds"))

local M = {}
M.id = "thorn_axis"
M.AnimKit = "ThornOfTheAxis"

local K = M.AnimKit
local CRIMSON = Color3.fromRGB(215, 18, 42)
local RED = Color3.fromRGB(255, 34, 56)
local DEEP = Color3.fromRGB(140, 4, 24)
local PALE = Color3.fromRGB(255, 222, 228)
local WHITE = Color3.new(1, 1, 1)

local SFX = {
	Swish = { 9126014082, 9126013811, 9126013382, 9119699577 },
	WhooshBy = 9120715547,
	Chime = 9114369623,
	DeepHit = 9125484367,
	EvilPulse = 9126084278,
	Dramatic = 9039693350,
	Suck = 9039693523,
}
local function sid(n: number): string
	return "rbxassetid://" .. tostring(n)
end
local function vol(env, v: number): number
	return if env.mine then v else v * 0.6
end

local function seq(points: {{number}}): NumberSequence
	local kps = {}
	for _, p in points do table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(kps)
end

local function emitter(parent: Instance, props: {[string]: any}): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in props do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- ===================================================================== gates
-- Same numbers as the server (Kits.ThornOfTheAxis): gate i on a half-ring in the back plane.
local GATE = { n = 10, radius = 5.4, back = 2.6, up = 1.0, from = -95, to = 95, size = 1.45 }
function M.GateOffset(i: number): Vector3
	local a = math.rad(GATE.from + (GATE.to - GATE.from) * (i - 1) / (GATE.n - 1))
	return Vector3.new(math.sin(a) * GATE.radius, GATE.up + math.cos(a) * GATE.radius * 0.8, GATE.back)
end

local function flatCF(root: BasePart): CFrame
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then CFrame.lookAt(root.Position, root.Position + flat) else CFrame.new(root.Position)
end

type GateSet = {
	parts: {BasePart}, glows: {BasePart}, imgs: {ImageLabel}, open: number, flareAt: number,
	pulse: {[number]: number}, root: BasePart,
}
local gateSets: {[Model]: GateSet} = setmetatable({}, { __mode = "k" }) :: any

-- World CFrame of gate i (facing forward, like the player) -- also used without a gate set.
local function gateCF(root: BasePart, i: number): CFrame
	return flatCF(root) * CFrame.new(M.GateOffset(i))
end

local function buildGates(character: Model, root: BasePart): GateSet
	local set: GateSet = { parts = {}, glows = {}, imgs = {}, open = 0, flareAt = -1e9, pulse = {}, root = root }
	for i = 1, GATE.n do
		local glow = Fx.Part({ Name = "TOA_GateGlow", Size = Vector3.new(0.1, 0.1, 0.05) })
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			Fx.Sprite(glow, face, Tex.GateSoft, { brightness = 1.4, transparency = 0.45 })
		end
		local p = Fx.Part({ Name = "TOA_Gate", Size = Vector3.new(0.1, 0.1, 0.05) })
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			table.insert(set.imgs, Fx.Sprite(p, face, Tex.GateVortex, { brightness = 2.2 }))
		end
		table.insert(set.parts, p)
		table.insert(set.glows, glow)
	end
	gateSets[character] = set
	return set
end

local function destroyGates(character: Model)
	local set = gateSets[character]
	gateSets[character] = nil
	if not set then return end
	for _, p in set.parts do p:Destroy() end
	for _, p in set.glows do p:Destroy() end
end

-- ===================================================================== presence (aura + gates)
local AURA_PARTS = { "UpperTorso", "LowerTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
	"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }

function M.Presence(character: Model, _model: Model, env)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if not root or not torso then return nil end
	local caster: Player? = env.caster
	local made: {Instance} = {}
	local function own<T>(inst: T): T
		table.insert(made, inst :: any)
		return inst
	end

	-- the aura: crimson flame tongues with a white inner side, licking up from every limb
	local flames: {ParticleEmitter} = {}
	local wisps: {ParticleEmitter} = {}
	for _, name in AURA_PARTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local big = name == "UpperTorso" or name == "LowerTorso"
			table.insert(flames, own(emitter(part, {
				Name = "TOA_AuraFlames", Texture = Tex.AuraFlame,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2, FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(9, 14),
				Color = ColorSequence.new(WHITE),
				Size = seq({ { 0, 0.5 }, { 0.3, if big then 1.5 else 1.1 }, { 1, 0.3 } }),
				Transparency = seq({ { 0, 0.7 }, { 0.15, 0.15 }, { 0.7, 0.4 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(0.3, 1.2), SpreadAngle = Vector2.new(25, 25),
				Acceleration = Vector3.new(0, 7, 0), Drag = 1.5, Rotation = NumberRange.new(-12, 12), RotSpeed = NumberRange.new(-25, 25),
				Rate = if big then 12 else 5, LightEmission = 0.35, Brightness = 1.6, ZOffset = 0.35,
				Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
				EmissionDirection = Enum.NormalId.Top, LockedToPart = false,
			})))
			-- the red outer layer around the white inner flames (reads red even in daylight)
			table.insert(flames, own(emitter(part, {
				Name = "TOA_AuraFlamesRed", Texture = Tex.AuraFlame,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2, FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(8, 12),
				Color = ColorSequence.new(Color3.fromRGB(255, 25, 45), Color3.fromRGB(190, 0, 25)),
				Size = seq({ { 0, 0.9 }, { 0.3, if big then 2.7 else 2.0 }, { 1, 0.6 } }),
				Transparency = seq({ { 0, 0.75 }, { 0.15, 0.1 }, { 0.7, 0.35 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.5, 0.85), Speed = NumberRange.new(0.4, 1.4), SpreadAngle = Vector2.new(30, 30),
				Acceleration = Vector3.new(0, 8, 0), Drag = 1.5, Rotation = NumberRange.new(-15, 15), RotSpeed = NumberRange.new(-25, 25),
				Rate = if big then 14 else 6, LightEmission = 0.1, Brightness = 1.3, ZOffset = -0.15,
				Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
				EmissionDirection = Enum.NormalId.Top, LockedToPart = false,
			})))
			if big then
				table.insert(wisps, own(emitter(part, {
					Name = "TOA_AuraWisps", Texture = Tex.AuraWisp,
					Color = ColorSequence.new(RED, CRIMSON),
					Size = seq({ { 0, 1.8 }, { 0.5, 3.4 }, { 1, 4.2 } }),
					Transparency = seq({ { 0, 1 }, { 0.25, 0.55 }, { 0.75, 0.75 }, { 1, 1 } }),
					Lifetime = NumberRange.new(0.9, 1.4), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
					Acceleration = Vector3.new(0, 3, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
					Rate = 5, LightEmission = 0.8, Brightness = 1.2, ZOffset = -0.5,
					Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				})))
			end
		end
	end
	-- rising white-red filaments (the "strings" of the aura in the refs)
	local filaments = own(emitter(torso, {
		Name = "TOA_AuraFilaments", Texture = Tex.AuraFilament,
		Color = ColorSequence.new(PALE, RED),
		Size = seq({ { 0, 1.4 }, { 1, 2.4 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.1 }, { 0.8, 0.4 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(5, 9), SpreadAngle = Vector2.new(30, 30),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Rate = 9, LightEmission = 1, Brightness = 2.5, ZOffset = 0.3,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
	}))
	local sparks = own(emitter(torso, {
		Name = "TOA_AuraSparks", Texture = Tex.Spark,
		Color = ColorSequence.new(PALE, RED),
		Size = seq({ { 0, 0.35 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 4, 0), Drag = 1, Rate = 10, LightEmission = 1, Brightness = 2.5,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	}))
	local light = own(Instance.new("PointLight"))
	light.Name = "TOA_AuraLight"
	light.Color = RED
	light.Range = 11
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = torso
	-- crimson outline around the whole body (the aura's red edge, visible from far)
	local outline = own(Instance.new("Highlight"))
	outline.Name = "TOA_AuraOutline"
	outline.Adornee = character
	outline.FillColor = CRIMSON
	outline.FillTransparency = 0.88
	outline.OutlineColor = RED
	outline.OutlineTransparency = 0.25
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = character

	local baseRates: {[ParticleEmitter]: number} = {}
	local baseBright: {[ParticleEmitter]: number} = {}
	for _, e in flames do
		baseRates[e] = e.Rate
		baseBright[e] = e.Brightness
	end
	for _, e in wisps do baseRates[e] = e.Rate end
	baseRates[filaments] = filaments.Rate
	baseRates[sparks] = sparks.Rate

	local alive = true
	local strong = false
	local wasFar = false
	local spin = 0
	local acc = 0
	local function setStrong(on: boolean, far: boolean)
		local k = if on then 2.2 else 1
		for e, r in baseRates do
			local farCut = if far and (e == sparks or e == filaments) then 0 else 1
			e.Rate = r * k * farCut
		end
		light.Range = if on then 16 else 11
		light.Brightness = if on then 2.6 else 1.4
		for _, e in flames do e.Brightness = baseBright[e] * (if on then 1.5 else 1) end
		outline.FillTransparency = if on then 0.8 else 0.88
		outline.OutlineTransparency = if on then 0 else 0.25
	end

	local conn = RunService.RenderStepped:Connect(function(dt)
		if not alive or not root.Parent then return end
		acc += dt
		if acc > 0.25 then
			acc = 0
			local until_ = if caster then caster:GetAttribute("ThornUntil") else nil
			local on = type(until_) == "number" and until_ > now()
			if on ~= strong or env.far ~= wasFar then
				strong = on
				wasFar = env.far == true
				setStrong(on, wasFar)
			end
		end
		-- the gates: only inside a gamemode
		local inRun = caster ~= nil and caster:GetAttribute("InRun") ~= nil
		local set = gateSets[character]
		if inRun and not set then
			set = buildGates(character, root)
			Fx.Sound(sid(SFX.Suck), root, { volume = vol(env, 0.25), pitch = 1.4 })
		end
		if not set then return end
		set.open = math.clamp(set.open + (if inRun then dt / 0.6 else -dt / 0.35), 0, 1)
		if set.open <= 0 and not inRun then
			destroyGates(character)
			return
		end
		spin += dt
		local base = flatCF(root)
		local tNow = os.clock()
		local flare = math.clamp(1 - (tNow - set.flareAt) / 0.45, 0, 1)
		local cfs: {CFrame} = {}
		local glowCfs: {CFrame} = {}
		for i, p in set.parts do
			-- staggered opening from the top gates outwards
			local order = math.abs(i - (GATE.n + 1) / 2) / (GATE.n / 2)
			local o = math.clamp(set.open * 1.6 - order * 0.6, 0, 1)
			local pulse = math.clamp(1 - (tNow - (set.pulse[i] or -1e9)) / 0.18, 0, 1)
			local s = GATE.size * Fx.EaseOut(o) * (1 + 0.25 * pulse + 0.7 * flare * flare)
			local bob = Vector3.new(0, math.sin(spin * 1.7 + i) * 0.08, 0)
			local cf = base * CFrame.new(M.GateOffset(i) + bob)
			p.Size = Vector3.new(math.max(s, 0.05), math.max(s, 0.05), 0.05)
			set.glows[i].Size = Vector3.new(math.max(s * 1.7, 0.05), math.max(s * 1.7, 0.05), 0.05)
			cfs[i] = cf
			glowCfs[i] = cf * CFrame.new(0, 0, 0.04)
		end
		Workspace:BulkMoveTo(set.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		Workspace:BulkMoveTo(set.glows, glowCfs, Enum.BulkMoveMode.FireCFrameChanged)
		for i, img in set.imgs do
			img.Rotation = (spin * (if i % 4 < 2 then 140 else -140)) % 360
		end
	end)

	return function()
		alive = false
		conn:Disconnect()
		destroyGates(character)
		for _, inst in made do
			if inst.Parent then inst:Destroy() end
		end
	end
end

-- equip: the aura bursts up around the body
function M.Equip(character: Model, _model: Model, env)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	if env.mine then Fx.PlayAnim(K, "Equip", { fade = 0.1, priority = Enum.AnimationPriority.Action2 }) end
	local feet = Fx.FeetY(character, root)
	local at = Vector3.new(root.Position.X, feet + 0.2, root.Position.Z)
	Fx.Burst(root.Position, {
		texture = Tex.AuraFlame, color = WHITE, count = 26, speed = NumberRange.new(6, 14),
		life = NumberRange.new(0.4, 0.7), size = seq({ { 0, 1.4 }, { 0.4, 2.6 }, { 1, 0.6 } }),
		transparency = seq({ { 0, 0.2 }, { 0.7, 0.4 }, { 1, 1 } }), spread = 35, drag = 3, accel = Vector3.new(0, 10, 0),
		box = Vector3.new(2, 4, 2), emission = 0.7, brightness = 2,
	})
	Fx.Burst(root.Position, {
		texture = Tex.AuraFilament, color = ColorSequence.new(PALE, RED), count = 18, speed = NumberRange.new(14, 26),
		life = NumberRange.new(0.3, 0.5), size = 2.6, spread = 25, orient = Enum.ParticleOrientation.VelocityParallel,
		box = Vector3.new(2, 3, 2), brightness = 3,
	})
	Fx.Ring(CFrame.new(at), 1, 9, RED, 0.5, 8)
	Fx.Light(root.Position, RED, 18, 4, 0.6)
	Fx.Sound(sid(SFX.Dramatic), root, { volume = vol(env, 0.35), pitch = 1.3, from = 0.4 })
end

-- ===================================================================== laser-arrows
-- A thin wavering laser with an arrowhead flying from `from` to a (moving) target part.
type ArrowOpts = { width: number, length: number, curve: Vector3?, arc: number?, wobble: number, glow: number, color: Color3? }
local function arrow(from: Vector3, target: BasePart, travel: number, o: ArrowOpts, onHit: ((Vector3) -> ())?)
	local holder = Fx.Part({ Name = "TOA_Arrow", CFrame = CFrame.new() })
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	local core = Instance.new("Beam")
	core.Attachment0, core.Attachment1 = a0, a1
	core.Texture = Tex.ArrowProj
	core.TextureMode = Enum.TextureMode.Stretch
	core.TextureLength = 1
	core.Width0, core.Width1 = o.width, o.width
	core.Color = ColorSequence.new(o.color or WHITE)
	core.LightEmission, core.LightInfluence, core.Brightness = 1, 0, 3
	core.FaceCamera = true
	core.Segments = 1
	core.Parent = holder
	local glow = Instance.new("Beam")
	glow.Attachment0, glow.Attachment1 = a0, a1
	glow.Texture = Tex.GlowStrip
	glow.TextureMode = Enum.TextureMode.Stretch
	glow.Width0, glow.Width1 = o.width * 0.25 * o.glow, o.width * 0.55 * o.glow
	glow.Color = ColorSequence.new(RED)
	glow.Transparency = seq({ { 0, 0.85 }, { 0.5, 0.35 }, { 1, 0.15 } })
	glow.LightEmission, glow.LightInfluence, glow.Brightness = 1, 0, 2
	glow.FaceCamera = true
	glow.Segments = 1
	glow.Parent = holder
	-- solid neon core: a thin red shaft + a bright diamond tip (reads in daylight and from far)
	local thick = 0.1 * o.width
	local shaft = Fx.Part({ Name = "TOA_ArrowShaft", Size = Vector3.new(thick, thick, 1), Material = Enum.Material.Neon,
		Color = o.color or RED, Transparency = 0.05 })
	local tipSize = 0.26 * o.width
	local tip = Fx.Part({ Name = "TOA_ArrowTip", Size = Vector3.new(tipSize * 0.7, tipSize * 0.7, tipSize * 1.6), Material = Enum.Material.Neon,
		Color = PALE, Transparency = 0 })
	local endPos = target.Position
	local seed = math.random() * 100
	local total = math.max(travel, 0.05)
	Fx.Every(total + 0.08, function(t)
		if target.Parent then endPos = target.Position end
		local a = math.clamp(t / total, 0, 1)
		local dir = endPos - from
		local dist = math.max(dir.Magnitude, 0.1)
		local function at(k: number): Vector3
			local p = from + dir * k
			local bend = math.sin(math.pi * k)
			if o.curve then p += o.curve * bend * dist * 0.22 end
			if o.arc then p += Vector3.new(0, o.arc * bend, 0) end
			local side = dir:Cross(Vector3.yAxis)
			if side.Magnitude > 1e-3 then
				p += side.Unit * math.sin(k * 26 + seed) * o.wobble * (1 - k)
			end
			return p
		end
		local head = at(a)
		local tail = at(math.max(0, a - o.length / dist))
		a0.WorldPosition = tail
		a1.WorldPosition = head
		local span = head - tail
		if span.Magnitude > 0.05 then
			local fwd = span.Unit
			shaft.Size = Vector3.new(thick, thick, span.Magnitude)
			shaft.CFrame = CFrame.lookAt((head + tail) / 2, head)
			tip.CFrame = CFrame.lookAt(head, head + fwd) * CFrame.Angles(0, 0, math.rad(45))
		end
		if t >= total then
			holder:Destroy()
			shaft:Destroy()
			tip:Destroy()
			if onHit then onHit(endPos) end
			return false
		end
		return nil
	end)
	Fx.Later(holder, total + 3)
	Fx.Later(shaft, total + 3)
	Fx.Later(tip, total + 3)
end

local GESTURE = { "Point", "Sweep", "Push", "Finish" }

function M.Volley(data, env)
	local character: Model?, root: BasePart? = env.character, env.root
	if not character or not root then return end
	local n = tonumber(data.n) or 1
	if env.mine then Fx.PlayAnim(K, GESTURE[n] or "Point", { fade = 0.06, priority = Enum.AnimationPriority.Action2 }) end
	local set = gateSets[character]
	local finisher = n == 4
	if finisher and set then set.flareAt = os.clock() end
	local base = flatCF(root)
	local right = base.RightVector
	local shots = if type(data.shots) == "table" then data.shots else {}
	for _, sh in shots do
		local model = sh.m
		local g = tonumber(sh.g) or 1
		local tgt = typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart
		if tgt then
			if set then set.pulse[g] = os.clock() end
			local from = gateCF(root, g).Position
			local side = if M.GateOffset(g).X >= 0 then 1 else -1
			local opts: ArrowOpts = if n == 2 then { width = 1.5, length = 10, curve = right * side, wobble = 0.12, glow = 1 }
				elseif n == 3 then { width = 1.3, length = 13, wobble = 0.05, glow = 0.85 }
				elseif finisher then { width = 2.6, length = 14, wobble = 0.08, glow = 1.5, arc = 1 }
				else { width = 1.5, length = 9, arc = 1.2, wobble = 0.15, glow = 1 }
			local thorn = data.thorn == true
			arrow(from, tgt, tonumber(sh.t) or 0.3, opts, function(hitAt)
				Fx.Impact(hitAt, { star = Tex.ImpactStar, burst = Tex.HitBurst, color = RED, scale = if finisher then 1.25 else 0.7, sparks = if finisher then 10 else 5 })
				if thorn then
					Fx.Burst(hitAt, { texture = Tex.BloodDrop, color = WHITE, count = 3, speed = NumberRange.new(4, 9), life = NumberRange.new(0.4, 0.6),
						size = 0.45, accel = Vector3.new(0, -40, 0), spread = 70, emission = 0, brightness = 1.4 })
				end
			end)
			-- launch flash at the gate
			if not env.far then
				Fx.Burst(from, { texture = Tex.Spark, color = ColorSequence.new(PALE, RED), count = if finisher then 8 else 3,
					speed = NumberRange.new(3, 8), life = NumberRange.new(0.15, 0.3), size = 0.35, drag = 4 })
			end
		end
	end
	if #shots > 0 then
		local swish = SFX.Swish[math.random(1, #SFX.Swish)]
		Fx.Sound(sid(swish), root, { volume = vol(env, if finisher then 0.4 else 0.22), pitch = if n == 3 then 1.6 else 1.35 })
		if finisher then
			Fx.Sound(sid(SFX.WhooshBy), root, { volume = vol(env, 0.3), pitch = 1.2 })
			Fx.Light(root.Position + Vector3.new(0, 3, 0), RED, 20, 3, 0.4)
		end
	end
end

function M.Bleed(data, _env)
	local at = data.at
	if typeof(at) ~= "Vector3" then return end
	Fx.Burst(at, { texture = Tex.BloodDrop, color = WHITE, count = 4, speed = NumberRange.new(3, 7), life = NumberRange.new(0.45, 0.7),
		size = 0.55, accel = Vector3.new(0, -35, 0), spread = 80, emission = 0, brightness = 1.4 })
end

-- ===================================================================== Creator of Thorn
local function summonTemplate(name: string): Model?
	local s = WeaponKits:FindFirstChild("Summons")
	local f = s and s:FindFirstChild("ThornOfTheAxis")
	local m = f and f:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

-- World-axis box around every part (Model:GetBoundingBox reports stale extents for imported meshes).
local function extents(m: Model): (CFrame, Vector3)
	local mn, mx = Vector3.one * 1e9, -Vector3.one * 1e9
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			local h = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local w = p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						mn = mn:Min(w)
						mx = mx:Max(w)
					end
				end
			end
		end
	end
	return CFrame.new((mn + mx) / 2), mx - mn
end

-- Stand-in until the Thorn mesh is in Summons.ThornOfTheAxis.Thorn: a neon shard.
local function fallbackThorn(): Model
	local m = Instance.new("Model")
	local shard = Instance.new("Part")
	shard.Name = "Thorn2_Shell"
	shard.Size = Vector3.new(0.9, 7.5, 0.4)
	shard.Material = Enum.Material.Neon
	shard.Color = CRIMSON
	shard.Parent = m
	m.PrimaryPart = shard
	return m
end

local THORN_REST = Vector3.new(0, 6.3, 3.6) -- floating spot behind the back (centre of the thorn)
local THORN_HEIGHT = 7.2                    -- studs, tip to top

function M.Thorn(data, env)
	local character: Model?, root: BasePart? = env.character, env.root
	if not character or not root then return end
	local duration = tonumber(data.duration) or 10
	if env.mine then Fx.PlayAnim(K, "Raise", { fade = 0.08, priority = Enum.AnimationPriority.Action2 }) end
	local tpl = summonTemplate("Thorn")
	local m = if tpl then tpl:Clone() else fallbackThorn()
	local parts: {BasePart} = {}
	local rel: {CFrame} = {}
	local _, size = extents(m)
	local scale = THORN_HEIGHT / math.max(size.Y, 0.1)
	if math.abs(scale - 1) > 0.02 then m:ScaleTo(m:GetScale() * scale) end
	local pivot = extents(m)
	local rings: {[BasePart]: number} = {}
	local shell: BasePart? = nil
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
			table.insert(parts, d)
			table.insert(rel, pivot:ToObjectSpace(d.CFrame))
			if d.Name:find("Ring") then rings[d] = if d.Name:find("2") then -1 else 1 end
			if d.Name:find("Shell") then shell = d end
		end
	end
	m.Parent = Fx.Folder()
	-- flames + sparks licking off the shard, light
	if shell then
		emitter(shell, {
			Name = "TOA_ThornFlames", Texture = Tex.AuraFlame,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2, FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			FlipbookFramerate = NumberRange.new(10, 15), Color = ColorSequence.new(Color3.fromRGB(255, 40, 40), Color3.fromRGB(255, 110, 40)),
			Size = seq({ { 0, 0.5 }, { 0.35, 1.5 }, { 1, 0.3 } }),
			Transparency = seq({ { 0, 0.75 }, { 0.15, 0.25 }, { 0.7, 0.5 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.3, 0.55), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(0, 9, 0), Drag = 1.5, Rotation = NumberRange.new(-10, 10),
			Rate = 18, LightEmission = 0.15, Brightness = 1.6, ZOffset = 0.3,
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		emitter(shell, {
			Name = "TOA_ThornSparks", Texture = Tex.Spark, Color = ColorSequence.new(PALE, Color3.fromRGB(255, 120, 40)),
			Size = seq({ { 0, 0.4 }, { 1, 0 } }), Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 5, 0), Drag = 1, Rate = 22,
			LightEmission = 1, Brightness = 3, Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		})
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 60, 50)
		l.Range = 16
		l.Brightness = 2.5
		l.Shadows = false
		l.Parent = shell
	end
	-- rises out of the top gates
	local topGate = (M.GateOffset(5) + M.GateOffset(6)) / 2
	local rise, fadeOut = 0.6, 0.45
	local spin = 0
	local tr: {[BasePart]: number} = {}
	for _, p in parts do tr[p] = p.Transparency end
	Fx.Burst(gateCF(root, 5).Position, { texture = Tex.AuraFilament, color = ColorSequence.new(PALE, RED), count = 16,
		speed = NumberRange.new(12, 22), life = NumberRange.new(0.3, 0.5), size = 2.6, spread = 20,
		orient = Enum.ParticleOrientation.VelocityParallel, brightness = 3 })
	Fx.Sound(sid(SFX.Dramatic), root, { volume = vol(env, 0.45), pitch = 1.1 })
	Fx.Sound(sid(SFX.Chime), root, { volume = vol(env, 0.3), pitch = 0.7 })
	Fx.Every(duration + fadeOut, function(t, _, dt)
		if not root.Parent then
			m:Destroy()
			return false
		end
		spin += dt
		local k = Fx.EaseOut(math.clamp(t / rise, 0, 1))
		local off = topGate:Lerp(THORN_REST, k) + Vector3.new(0, math.sin(t * 1.6) * 0.18, 0)
		local s = 0.25 + 0.75 * k
		local base = flatCF(root) * CFrame.new(off)
		local cfs = {}
		for i, p in parts do
			local r = rel[i]
			local scaled = CFrame.new(r.Position * s) * r.Rotation
			local dirn = rings[p]
			if dirn then scaled = CFrame.Angles(0, spin * 1.6 * dirn, 0) * scaled end
			cfs[i] = base * scaled
		end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		local f = math.clamp((t - duration) / fadeOut, 0, 1)
		if f > 0 then
			for _, p in parts do p.Transparency = tr[p] + (1 - tr[p]) * f end
		end
		if t >= duration + fadeOut then
			-- shatters into red shards
			local at = base.Position
			Fx.Burst(at, { texture = Tex.RainShard, color = WHITE, count = 16, speed = NumberRange.new(8, 18), life = NumberRange.new(0.3, 0.6),
				size = 1.4, spread = 180, drag = 3, orient = Enum.ParticleOrientation.VelocityParallel, brightness = 2.5 })
			Fx.Light(at, RED, 14, 3, 0.4)
			m:Destroy()
			return false
		end
		return nil
	end)
	Fx.Later(m, duration + fadeOut + 5)
end

-- ===================================================================== Miracle (summons)
-- The creature models face +X in their templates; decoys look along -Z.
local FACE = CFrame.Angles(0, math.pi / 2, 0)
local SUMMON_LIFT = { Dog = 0, Bird = 0, Fish = 0 }

type Creature = { model: Model, parts: {BasePart}, rel: {CFrame}, names: {string}, trans: {number}, cf: CFrame, lunge: number }

local function creature(kind: string, at: CFrame): Creature?
	local tpl = summonTemplate(kind)
	if not tpl then return nil end
	local m = tpl:Clone()
	local parts, rel, names, trans = {}, {}, {}, {}
	local ref = (tpl.PrimaryPart or tpl:FindFirstChildWhichIsA("BasePart") :: BasePart).CFrame
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
			table.insert(parts, d)
			table.insert(rel, CFrame.new(ref:PointToObjectSpace(d.Position)) * (ref.Rotation:Inverse() * d.CFrame.Rotation))
			table.insert(names, d.Name)
			table.insert(trans, d.Transparency)
			d.Transparency = 1
		end
	end
	local body = m:FindFirstChild("Body") :: BasePart?
	if body then
		-- red trail when it moves
		local t0 = Instance.new("Attachment")
		t0.Position = Vector3.new(0, body.Size.Y * 0.25, 0)
		t0.Parent = body
		local t1 = Instance.new("Attachment")
		t1.Position = Vector3.new(0, -body.Size.Y * 0.25, 0)
		t1.Parent = body
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = t0, t1
		trail.Color = ColorSequence.new(RED, DEEP)
		trail.Transparency = seq({ { 0, 0.35 }, { 1, 1 } })
		trail.Lifetime = 0.35
		trail.LightEmission, trail.LightInfluence, trail.Brightness = 1, 0, 2
		trail.FaceCamera = true
		trail.Parent = body
		local l = Instance.new("PointLight")
		l.Color = RED
		l.Range = 7
		l.Brightness = 1.5
		l.Shadows = false
		l.Parent = body
		emitter(body, {
			Name = "TOA_CreatureSparks", Texture = Tex.Spark, Color = ColorSequence.new(PALE, RED),
			Size = seq({ { 0, 0.25 }, { 1, 0 } }), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180), Rate = 8, LightEmission = 1, Brightness = 2,
		})
	end
	m.Parent = Fx.Folder()
	local c: Creature = { model = m, parts = parts, rel = rel, names = names, trans = trans, cf = at, lunge = -1e9 }
	return c
end

-- Places the creature at `cf` (its forward = cf.LookVector), with per-kind limb motion.
local function poseCreature(c: Creature, kind: string, cf: CFrame, t: number, moving: number, alpha: number)
	local cfs = {}
	local lunge = math.clamp(1 - (os.clock() - c.lunge) / 0.25, 0, 1)
	local base = cf * CFrame.new(0, SUMMON_LIFT[kind] or 0, -math.sin(lunge * math.pi) * 1.4) * FACE
	for i, p in c.parts do
		local r = c.rel[i]
		local name = c.names[i]
		if kind == "Dog" and name:find("Leg") then
			local phase = if name:find("FrontLeft") or name:find("BackRight") then 0 else math.pi
			r = CFrame.new(r.Position) * CFrame.Angles(0, 0, math.sin(t * 14 + phase) * 0.5 * moving) * r.Rotation
		elseif kind == "Dog" and name == "Tail" then
			r = CFrame.new(r.Position) * CFrame.Angles(math.sin(t * 9) * 0.35, 0, 0) * r.Rotation
		elseif kind == "Bird" and name:find("Wing") then
			local sgn = if name:find("Left") then -1 else 1
			local pivot = Vector3.new(r.Position.X, r.Position.Y - 0.6, 0)
			r = CFrame.new(pivot) * CFrame.Angles(sgn * math.sin(t * 9) * 0.6, 0, 0) * CFrame.new(r.Position - pivot) * r.Rotation
		elseif kind == "Fish" and name == "TailFin" then
			r = CFrame.new(r.Position) * CFrame.Angles(0, math.sin(t * 10) * 0.5, 0) * r.Rotation
		end
		cfs[i] = base * r
		p.Transparency = c.trans[i] + (1 - c.trans[i]) * (1 - alpha)
	end
	Workspace:BulkMoveTo(c.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function poof(at: Vector3, big: boolean)
	Fx.Burst(at, { texture = Tex.AuraFlame, color = WHITE, count = if big then 14 else 8, speed = NumberRange.new(3, 8),
		life = NumberRange.new(0.3, 0.55), size = seq({ { 0, 0.8 }, { 0.4, 2 }, { 1, 0.4 } }), spread = 180, drag = 3,
		accel = Vector3.new(0, 8, 0), emission = 0.7, brightness = 2 })
	Fx.Burst(at, { texture = Tex.Spark, color = ColorSequence.new(PALE, RED), count = 10, speed = NumberRange.new(6, 14),
		life = NumberRange.new(0.2, 0.45), size = 0.4, drag = 4 })
	Fx.Light(at, RED, 10, 2.5, 0.35)
end

local followers: {[string]: Creature} = {}

local function followDecoy(name: string, env, duration: number)
	local folder = Workspace:FindFirstChild("WeaponSummons") or Workspace:WaitForChild("WeaponSummons", 3)
	local decoy = folder and folder:WaitForChild(name, 3)
	if not decoy or not decoy:IsA("BasePart") then return end
	local kind = decoy:GetAttribute("Kind")
	if type(kind) ~= "string" then return end
	local c = creature(kind, decoy.CFrame)
	if not c then return end
	followers[name] = c
	local cf = decoy.CFrame
	local last = cf.Position
	local moving = 0
	local born = os.clock()
	local goneAt: number? = nil
	poof(cf.Position, true)
	Fx.Every(duration + 8, function(t, _, dt)
		if not goneAt and (not decoy.Parent or decoy:GetAttribute("Gone") ~= nil) then
			goneAt = os.clock()
			poof(c.cf.Position, decoy:GetAttribute("Gone") == "died")
		end
		if not goneAt then
			local k = 1 - math.exp(-12 * dt)
			cf = cf:Lerp(decoy.CFrame, k)
			local v = (cf.Position - last).Magnitude / math.max(dt, 1e-3)
			moving += ((math.clamp(v / 10, 0, 1)) - moving) * math.min(1, dt * 8)
			last = cf.Position
		end
		c.cf = cf
		local fadeIn = math.clamp((os.clock() - born) / 0.35, 0, 1)
		local fadeOut = if goneAt then 1 - math.clamp((os.clock() - goneAt) / 0.35, 0, 1) else 1
		poseCreature(c, kind, cf, t, if kind == "Bird" then 1 else moving, fadeIn * fadeOut)
		if goneAt and os.clock() - goneAt > 0.4 then
			c.model:Destroy()
			if followers[name] == c then followers[name] = nil end
			return false
		end
		return nil
	end)
	Fx.Later(c.model, duration + 10)
end

local function orbitFish(target: Player, index: number, duration: number)
	local c = creature("Fish", CFrame.new())
	if not c then return end
	local born = os.clock()
	local phase = index * 1.7
	Fx.Every(duration + 0.4, function(t)
		local character = target.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			c.model:Destroy()
			return false
		end
		local a = t * 2.2 + phase
		local r = 3.4
		local pos = hrp.Position + Vector3.new(math.cos(a) * r, 0.6 + math.sin(t * 2.5 + phase) * 0.5, math.sin(a) * r)
		-- swims along the circle (tangent)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local cf = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, math.sin(t * 6) * 0.15, 0)
		local fadeIn = math.clamp((os.clock() - born) / 0.35, 0, 1)
		local fadeOut = 1 - math.clamp((t - duration) / 0.4, 0, 1)
		poseCreature(c, "Fish", cf, t, 1, fadeIn * fadeOut)
		c.cf = cf
		-- a soft heal sparkle now and then
		if math.random() < 0.04 then
			Fx.Burst(hrp.Position, { texture = Tex.Spark, color = ColorSequence.new(PALE, RED), count = 3, speed = NumberRange.new(1, 3),
				life = NumberRange.new(0.4, 0.7), size = 0.35, accel = Vector3.new(0, 4, 0), box = Vector3.new(2, 3, 2) })
		end
		if t >= duration + 0.4 then
			poof(cf.Position, false)
			c.model:Destroy()
			return false
		end
		return nil
	end)
	Fx.Later(c.model, duration + 3)
end

function M.Miracle(data, env)
	local root: BasePart? = env.root
	local duration = tonumber(data.duration) or 15
	if env.mine then Fx.PlayAnim(K, "Miracle", { fade = 0.08, priority = Enum.AnimationPriority.Action2 }) end
	if root then
		local set = env.character and gateSets[env.character]
		if set then set.flareAt = os.clock() end
		Fx.Sound(sid(SFX.Chime), root, { volume = vol(env, 0.4), pitch = 0.9 })
		Fx.Sound(sid(SFX.Suck), root, { volume = vol(env, 0.3), pitch = 0.8 })
		Fx.Light(root.Position + Vector3.new(0, 3, 0), RED, 20, 3, 0.6)
	end
	for _, name in (if type(data.summons) == "table" then data.summons else {}) do
		if type(name) == "string" then task.spawn(followDecoy, name, env, duration) end
	end
	for i, uid in (if type(data.fish) == "table" then data.fish else {}) do
		local p = if type(uid) == "number" then Players:GetPlayerByUserId(uid) else nil
		if p then orbitFish(p, i, duration) end
	end
end

function M.Bite(data, _env)
	local c = if type(data.from) == "string" then followers[data.from] else nil
	if c then c.lunge = os.clock() end
	if typeof(data.at) == "Vector3" then
		task.delay(0.1, function()
			Fx.Impact(data.at, { star = Tex.ImpactStar, burst = Tex.HitBurst, color = RED, scale = 0.65, sparks = 4 })
		end)
	end
end

function M.Peck(data, _env)
	local c = if type(data.from) == "string" then followers[data.from] else nil
	local model = data.m
	local tgt = typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart
	if not c or not tgt then return end
	arrow(c.cf.Position, tgt, tonumber(data.t) or 0.3, { width = 1.1, length = 6, wobble = 0.05, glow = 0.8 }, function(hitAt)
		Fx.Impact(hitAt, { star = Tex.ImpactStar, color = RED, scale = 0.55, sparks = 3 })
	end)
end

-- ===================================================================== Red Rain (ultimate)
-- The ultimate animation (data.cutscene, ~3.4 s; enemies are frozen on the server):
--   0 .. liftFrom   he gathers: crouch, head bowed, crimson motes spiral in around him
--   liftFrom        lift-off: shockwave, a pillar of crimson light, he rises (server HipHeight)
--   ~1 .. ~3        the roof of the field fills with gates, rippling out from the centre
--   cutscene        the rain starts; he floats (arms crossed) and can move again
-- The caster's own screen gets letterbox bars, the title and three camera shots.
local rains: {[number]: () -> ()} = {}
local localPlayer = Players.LocalPlayer

local function letterbox(seconds: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "TOA_Cinematic"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	local bars = {}
	for _, top in { true, false } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		f.Position = UDim2.fromScale(0, if top then 0 else 1)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = gui
		table.insert(bars, f)
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	for _, bar in bars do Fx.Tween(bar, 0.25, { Size = UDim2.fromScale(1, 0.11) }) end
	task.delay(math.max(0, seconds - 0.25), function()
		for _, bar in bars do Fx.Tween(bar, 0.25, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
		Fx.Later(gui, 0.3)
	end)
	return gui
end

local function titleCard(gui: ScreenGui, at: number, hold: number)
	task.delay(at, function()
		if not gui.Parent then return end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.79)
		t.Size = UDim2.fromScale(0.7, 0.08)
		t.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
		t.Text = "RED RAIN"
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 235, 238)
		t.TextTransparency = 1
		t.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = RED
		stroke.Thickness = 2.5
		stroke.Transparency = 1
		stroke.Parent = t
		local scale = Instance.new("UIScale")
		scale.Scale = 1.25
		scale.Parent = t
		Fx.Tween(t, 0.18, { TextTransparency = 0 })
		Fx.Tween(stroke, 0.18, { Transparency = 0 })
		Fx.Tween(scale, 0.5, { Scale = 1 })
		task.delay(hold, function()
			Fx.Tween(t, 0.2, { TextTransparency = 1 })
			Fx.Tween(stroke, 0.2, { Transparency = 1 })
		end)
	end)
end

-- The caster's camera: low on the face while he gathers, wide as he rises under the opening
-- gates, then from below past him up into the roof as the rain begins.
local function cinematic(character: Model, root: BasePart, cut: number, roofY: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local savedType, savedFov, savedCF = cam.CameraType, cam.FieldOfView, cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	local hidden = {}
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "TOA_Cinematic" then
				g.Enabled = false
				table.insert(hidden, g)
			end
		end
	end
	local gui = letterbox(cut)
	titleCard(gui, cut * 0.38, cut * 0.42)
	local rcf = flatCF(root)
	local base = rcf.Position
	local head = character:FindFirstChild("Head") :: BasePart?
	local function rel(x: number, y: number, z: number): Vector3
		return rcf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local s1, s2 = cut * 0.34, cut * 0.72
	local stopShots = Fx.Every(cut, function(t)
		if not root.Parent or cam.CameraType ~= Enum.CameraType.Scriptable then return false end
		local live = root.Position
		local pos, focus, fov
		if t < s1 then
			local k = Fx.Smooth(t / s1)
			pos = rel(1.6, -1.1, -6.6):Lerp(rel(1.1, -0.7, -5.4), k)
			focus = if head and head.Parent then head.Position else live + Vector3.new(0, 1.5, 0)
			fov = 55
		elseif t < s2 then
			local k = Fx.Smooth((t - s1) / (s2 - s1))
			pos = rel(-9, 1.5, -25):Lerp(rel(-7, 5, -21), k)
			local up = live + Vector3.new(0, 2, 0)
			focus = up:Lerp(Vector3.new(live.X, (live.Y + roofY) / 2, live.Z), k * 0.6)
			fov = 62
		else
			local k = Fx.Smooth((t - s2) / (cut - s2))
			pos = rel(3, -1.2, 9):Lerp(Vector3.new(base.X, base.Y - 1, base.Z) + rcf:VectorToWorldSpace(Vector3.new(2.4, 0, 7.2)), k)
			focus = Vector3.new(live.X, live.Y, live.Z) + rcf:VectorToWorldSpace(Vector3.new(0, 0, -4)) + Vector3.new(0, (roofY - live.Y) * 0.55, 0)
			fov = 70 - 6 * k
		end
		cam.CFrame = CFrame.lookAt(pos, focus)
		cam.FieldOfView = fov
		return nil
	end)
	task.delay(cut, function()
		stopShots()
		cam.FieldOfView = savedFov
		cam.CFrame = savedCF
		cam.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
		for _, g in hidden do
			if g.Parent and not g.Enabled then g.Enabled = true end
		end
	end)
end

-- crimson motes spiralling around him, rising (gather) and streaming up (lift-off)
local function spiral(root: BasePart, seconds: number, far: boolean)
	local acc = 0
	Fx.Every(seconds, function(t, _, dt)
		acc += dt
		if acc < (if far then 0.12 else 0.04) or not root.Parent then return nil end
		acc = 0
		for arm = 0, 1 do
			local a = t * 7 + arm * math.pi
			local r = 3.2 - 1.2 * math.min(1, t / seconds)
			local h = -2.5 + (t * 3.5) % 6
			local at = root.Position + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
			Fx.Burst(at, { texture = Tex.Spark, color = ColorSequence.new(PALE, RED), count = 2, speed = NumberRange.new(2, 5),
				life = NumberRange.new(0.3, 0.6), size = 0.5, spread = 20, accel = Vector3.new(0, 14, 0), drag = 1 })
		end
		return nil
	end)
end

-- a pillar of crimson light from the ground to the roof, fading as it narrows
local function lightPillar(ground: Vector3, height: number)
	local p = Fx.Part({ Name = "TOA_Pillar", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = RED,
		Transparency = 0.15, Size = Vector3.new(height, 0.4, 0.4),
		CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	local core = Fx.Part({ Name = "TOA_PillarCore", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PALE,
		Transparency = 0.1, Size = Vector3.new(height, 0.2, 0.2),
		CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	Fx.Every(1.6, function(_, a)
		local w = if a < 0.15 then 0.4 + 5.6 * (a / 0.15) else 6 * (1 - (a - 0.15) / 0.85) + 0.2
		p.Size = Vector3.new(height, w, w)
		core.Size = Vector3.new(height, w * 0.35, w * 0.35)
		p.Transparency = 0.15 + 0.85 * a ^ 1.5
		core.Transparency = 0.1 + 0.9 * a ^ 1.3
		if a >= 1 then
			p:Destroy()
			core:Destroy()
		end
		return nil
	end)
	Fx.Later(p, 3)
	Fx.Later(core, 3)
end

function M.RedRain(data, env)
	local root: BasePart? = env.root
	local character: Model? = env.character
	if not root or not character then return end
	local caster = data.caster
	if rains[caster] then rains[caster]() end
	local cut = tonumber(data.cutscene) or tonumber(data.rise) or 3.4
	local liftFrom = tonumber(data.liftFrom) or cut * 0.22
	local liftTo = tonumber(data.liftTo) or cut * 0.85
	local duration = tonumber(data.duration) or 20
	local made: {Instance} = {}
	local stopped = false
	local floatTrack: AnimationTrack? = nil

	local feet = Fx.FeetY(character, root)
	local ground = Vector3.new(root.Position.X, feet + 0.1, root.Position.Z)

	-- the roof: a field of gates over the room
	local roomCf: CFrame? = if typeof(data.roomCf) == "CFrame" then data.roomCf else nil
	local roomSize: Vector3? = if typeof(data.roomSize) == "Vector3" then data.roomSize else nil
	local center = if roomCf then roomCf.Position else root.Position
	local sx = if roomSize then math.min(roomSize.X, 220) else 120
	local sz = if roomSize then math.min(roomSize.Z, 220) else 120
	local roofY = math.clamp((if roomCf and roomSize then roomCf.Position.Y + roomSize.Y / 2 - 3 else feet + 30), feet + 20, feet + 36)

	if env.mine then
		Fx.PlayAnim(K, "Levitate", { fade = 0.12, priority = Enum.AnimationPriority.Action3 })
		task.delay(cut - 0.25, function()
			if not stopped then floatTrack = Fx.PlayAnim(K, "Float", { fade = 0.35, priority = Enum.AnimationPriority.Action }) end
		end)
		cinematic(character, root, cut, roofY)
	end

	-- gather: a red swell, motes spiralling in
	Fx.Grade({ Saturation = 0.2, Contrast = 0.2, Brightness = -0.04, TintColor = Color3.fromRGB(255, 200, 205) }, 0.4, cut + duration - 0.4, 1.2)
	Fx.Sound(sid(SFX.Suck), root, { volume = vol(env, 0.45), pitch = 0.75 })
	Fx.Ring(CFrame.new(ground), 7, 1.5, RED, liftFrom, 8, 0.2)
	spiral(root, cut, env.far == true)

	-- lift-off: shockwave, pillar of light, aura burst
	task.delay(liftFrom, function()
		if stopped or not root.Parent then return end
		Fx.Ring(CFrame.new(ground), 1, 16, RED, 0.7, 10)
		Fx.Ring(CFrame.new(ground + Vector3.new(0, 0.05, 0)), 1, 10, PALE, 0.5, 6)
		lightPillar(ground, roofY - ground.Y)
		Fx.Burst(root.Position, { texture = Tex.AuraFilament, color = ColorSequence.new(PALE, RED), count = 36,
			speed = NumberRange.new(20, 38), life = NumberRange.new(0.4, 0.75), size = 3.2, spread = 18,
			orient = Enum.ParticleOrientation.VelocityParallel, box = Vector3.new(3, 2, 3), brightness = 3 })
		Fx.Burst(ground, { texture = Tex.AuraFlame, color = WHITE, count = 20, speed = NumberRange.new(10, 20),
			life = NumberRange.new(0.35, 0.6), size = seq({ { 0, 1.5 }, { 0.4, 3 }, { 1, 0.6 } }), spread = 80,
			drag = 3, accel = Vector3.new(0, 12, 0), emission = 0.3, brightness = 2, box = Vector3.new(4, 0.5, 4) })
		Fx.Light(root.Position, RED, 30, 5, 0.9)
		Fx.Sound(sid(SFX.Dramatic), root, { volume = vol(env, 0.6), pitch = 0.85 })
		if env.mine then pcall(Fx.Shake, 0.5, 0.45) end
	end)

	local spacing = math.max(11, math.sqrt(sx * sz / 64))
	local nx, nz = math.max(2, math.floor(sx / spacing)), math.max(2, math.floor(sz / spacing))
	local gates: {{part: BasePart, img: ImageLabel, glow: ImageLabel, delay: number, size: number, rain: {ParticleEmitter}}} = {}
	local fall = roofY - feet
	local openFrom, openSpan = liftFrom + 0.25, math.max(0.6, (liftTo - liftFrom) * 0.8)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = center.X - sx / 2 + (ix + 0.5) * sx / nx + (math.random() - 0.5) * spacing * 0.35
			local z = center.Z - sz / 2 + (iz + 0.5) * sz / nz + (math.random() - 0.5) * spacing * 0.35
			local y = roofY + (math.random() - 0.5) * 3
			local size = spacing * (0.55 + math.random() * 0.25)
			local p = Fx.Part({ Name = "TOA_RoofGate", CFrame = CFrame.new(x, y, z), Size = Vector3.new(0.1, 0.05, 0.1) })
			table.insert(made, p)
			local glow = Fx.Sprite(p, Enum.NormalId.Bottom, Tex.GateSoft, { brightness = 1.2, transparency = 1 })
			local img = Fx.Sprite(p, Enum.NormalId.Bottom, Tex.GateVortex, { brightness = 2, transparency = 1 })
			local rain = {
				emitter(p, {
					Name = "TOA_RainNeedles", Texture = Tex.RainNeedle, Color = ColorSequence.new(WHITE),
					Size = seq({ { 0, 3.6 }, { 1, 3.6 } }), Squash = seq({ { 0, 2.6 }, { 1, 2.6 } }),
					Transparency = seq({ { 0, 0.05 }, { 0.85, 0.15 }, { 1, 1 } }),
					Lifetime = NumberRange.new(fall / 95, fall / 80), Speed = NumberRange.new(80, 95),
					SpreadAngle = Vector2.new(6, 6), Orientation = Enum.ParticleOrientation.VelocityParallel, Rotation = NumberRange.new(90),
					EmissionDirection = Enum.NormalId.Bottom, Rate = 0, LightEmission = 0.3, Brightness = 2.2,
					Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				}),
				emitter(p, {
					Name = "TOA_RainShards", Texture = Tex.RainShard, Color = ColorSequence.new(WHITE),
					Size = seq({ { 0, 4.4 }, { 1, 4.4 } }), Squash = seq({ { 0, 2.2 }, { 1, 2.2 } }),
					Transparency = seq({ { 0, 0.1 }, { 0.85, 0.2 }, { 1, 1 } }),
					Lifetime = NumberRange.new(fall / 75, fall / 65), Speed = NumberRange.new(65, 75),
					SpreadAngle = Vector2.new(5, 5), Orientation = Enum.ParticleOrientation.VelocityParallel, Rotation = NumberRange.new(90),
					EmissionDirection = Enum.NormalId.Bottom, Rate = 0, LightEmission = 0.3, Brightness = 2.2,
					Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				}),
			}
			-- ripple: the gates right above him open first
			local d = Vector2.new(x - ground.X, z - ground.Z).Magnitude / math.max(sx, sz)
			table.insert(gates, { part = p, img = img, glow = glow, delay = openFrom + math.min(1, d * 1.4) * openSpan, size = size, rain = rain })
		end
	end
	-- the roof is complete: a flash up there and a jolt
	task.delay(openFrom + openSpan + 0.3, function()
		if stopped then return end
		Fx.Light(Vector3.new(ground.X, roofY - 4, ground.Z), RED, 60, 4, 0.8)
		if env.mine then pcall(Fx.Shake, 0.35, 0.3) end
	end)
	local loopSfx: ((number?) -> ())? = nil
	task.delay(cut, function()
		if stopped then return end
		local _, stop = Fx.Sound(sid(SFX.EvilPulse), root, { volume = vol(env, 0.3), looped = true, fadeIn = 0.6, pitch = 1.15 })
		loopSfx = stop
	end)

	local closing = false
	local closeAt = 0
	local spin = 0
	local splashAcc = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		spin += dt
		local t = os.clock() - (closeAt > 0 and closeAt or 0)
		local raining = not closing and spin > cut
		local farCut = if env.far then 0.4 else 1
		for i, g in gates do
			local open
			if closing then
				open = 1 - math.clamp(t / 0.8, 0, 1)
			else
				open = math.clamp((spin - g.delay) / 0.45, 0, 1)
			end
			local sz2 = g.size * Fx.EaseOut(open)
			g.part.Size = Vector3.new(math.max(sz2, 0.1), 0.05, math.max(sz2, 0.1))
			g.img.ImageTransparency = 1 - open
			g.glow.ImageTransparency = 1 - open * 0.6
			g.img.Rotation = (spin * (if i % 2 == 0 then 70 else -70)) % 360
			g.rain[1].Rate = if raining then 14 * farCut else 0
			g.rain[2].Rate = if raining then 4 * farCut else 0
		end
		-- splashes on the enemies the rain is hitting
		if raining then
			splashAcc += dt
			if splashAcc > 0.12 then
				splashAcc = 0
				local list = Fx.Enemies(center, 260)
				if #list > 0 then
					local e = list[math.random(1, #list)]
					local at = e.root.Position + Vector3.new((math.random() - 0.5) * 2, e.root.Size.Y * 0.3, (math.random() - 0.5) * 2)
					Fx.Impact(at, { star = Tex.ImpactStar, color = RED, scale = 0.5, sparks = 3 })
				end
			end
		end
	end)

	local function cleanup()
		if stopped then return end
		stopped = true
		rains[caster] = nil
		closing = true
		closeAt = os.clock()
		if floatTrack then floatTrack:Stop(0.6) end
		if loopSfx then loopSfx(0.8) end
		task.delay(1, function()
			conn:Disconnect()
			for _, inst in made do
				if inst.Parent then inst:Destroy() end
			end
		end)
	end
	rains[caster] = cleanup
	task.delay(cut + duration + 2, cleanup) -- in case the end push never comes
end

function M.RedRainEnd(data, _env)
	local stop = rains[data.caster]
	if stop then stop() end
end

local _ = Lighting
return M
