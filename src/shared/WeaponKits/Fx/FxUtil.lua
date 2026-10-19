--!strict
-- FxUtil
-- Location: ReplicatedStorage.WeaponKits.FxUtil (ModuleScript, client only)
-- Building blocks for the signature weapons' client effects
-- (ReplicatedStorage.WeaponKits.Fx.<Kit>, run by StarterPlayerScripts.WeaponFxClient).
-- Everything made here exists only on this client, in workspace.WeaponFx.
--   Part / Sprite / Billboard        glowing images (unlit, so they read in the dark tower
--                                    and catch the bloom)
--   Label                            floating text over a part or a point
--   Burst / Ring / Light / Pixels    one-shot particles, expanding rings, light flashes,
--                                    little "digital" cubes
--   Every(seconds, fn)               per-frame updater: fn(t, alpha, dt), false stops it
--   Weapon / Pose                    the held weapon model and coded poses on its
--                                    WeaponGrip weld (stand-ins until a kit's animations
--                                    are published; a weaker pose never breaks a stronger one)
--   Animation / PlayAnim             ReplicatedStorage.WeaponKits.Anims.<Kit>.<name>
--   Ghost                            afterimage of a character
--   Enemies                          living enemies near a point (tag "DungeonEnemy")
--   Sound                            one-shot / looped sounds in the SFX group
--   Shake / Quake / Grade            SummonPlaza ScreenFx (Screen Shake setting respected)

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ScreenFx = require(ReplicatedStorage:WaitForChild("SummonPlaza"):WaitForChild("Fx"):WaitForChild("Shared"):WaitForChild("ScreenFx"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local FxUtil = {}
local player = Players.LocalPlayer

FxUtil.Shake = ScreenFx.Shake
FxUtil.Quake = ScreenFx.Quake
FxUtil.Grade = ScreenFx.Grade
FxUtil.Font = UITheme.FontFaces.Heading
FxUtil.SPARK = "rbxasset://textures/particles/sparkles_main.dds"
FxUtil.SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local ENEMY_TAG = "DungeonEnemy"

-- ===== containers =====
local holder: Folder? = nil
function FxUtil.Folder(): Folder
	local f = holder
	if f and f.Parent then return f end
	local nf = Instance.new("Folder")
	nf.Name = "WeaponFx"
	nf.Parent = workspace
	holder = nf
	return nf
end

local labels: Folder? = nil
local function labelFolder(): Folder
	local f = labels
	if f and f.Parent then return f end
	local nf = Instance.new("Folder")
	nf.Name = "WeaponFxLabels"
	nf.Parent = player:WaitForChild("PlayerGui")
	labels = nf
	return nf
end

-- Anchored, invisible, non-colliding part; `props` are applied before parenting.
function FxUtil.Part(props: {[string]: any}?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	local parent: Instance = FxUtil.Folder()
	if props then
		for k, v in props do
			if k == "Parent" then parent = v else (p :: any)[k] = v end
		end
	end
	p.Parent = parent
	return p
end

function FxUtil.Tween(inst: Instance, seconds: number, goal: {[string]: any}, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

function FxUtil.Later(inst: Instance, seconds: number)
	Debris:AddItem(inst, seconds)
end

function FxUtil.EaseOut(a: number): number
	return 1 - (1 - a) * (1 - a)
end

function FxUtil.Smooth(a: number): number
	return a * a * (3 - 2 * a)
end

function FxUtil.Flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- ===== images =====
export type ImageOpts = { color: Color3?, transparency: number?, brightness: number?, canvas: Vector2?, onTop: boolean?, rotation: number?, offset: Vector3? }

local function image(parent: Instance, img: string, o: ImageOpts): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = "Image"
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.Size = UDim2.fromScale(1, 1)
	l.Image = img
	l.ImageColor3 = o.color or Color3.new(1, 1, 1)
	l.ImageTransparency = o.transparency or 0
	l.Rotation = o.rotation or 0
	l.Parent = parent
	return l
end

-- Unlit image filling one face of `part` (it scales with the part).
-- Top face: the image's top points along the part's -X, its right along -Z.
function FxUtil.Sprite(part: BasePart, face: Enum.NormalId, img: string, o: ImageOpts?): ImageLabel
	local opts: ImageOpts = o or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sprite" .. face.Name
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = opts.brightness or 1.6
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = opts.canvas or Vector2.new(256, 256)
	gui.AlwaysOnTop = opts.onTop == true
	gui.Parent = part
	return image(gui, img, opts)
end

-- Unlit camera-facing image, `size` studs wide, on a part or an attachment.
function FxUtil.Billboard(adornee: Instance, size: number, img: string, o: ImageOpts?): (BillboardGui, ImageLabel)
	local opts: ImageOpts = o or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = UDim2.fromScale(size, size)
	gui.LightInfluence = 0
	gui.Brightness = opts.brightness or 1.6
	gui.AlwaysOnTop = opts.onTop == true
	gui.StudsOffsetWorldSpace = opts.offset or Vector3.zero
	gui.MaxDistance = 800
	gui.ResetOnSpawn = false
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui, image(gui, img, opts)
end

-- Floating text over a part (follows it) or a point: pops in, rises, fades.
export type LabelOpts = { sub: string?, size: number?, rise: number?, seconds: number?, offset: Vector3?, delay: number? }
function FxUtil.Label(at: BasePart | Vector3, text: string, color: Color3, o: LabelOpts?)
	local opts: LabelOpts = o or {}
	local anchor: BasePart
	local own = false
	if typeof(at) == "Vector3" then
		anchor = FxUtil.Part({ CFrame = CFrame.new(at) })
		own = true
	else
		anchor = at
	end
	local size = opts.size or 30
	local gui = Instance.new("BillboardGui")
	gui.Name = "FxLabel"
	gui.Size = UDim2.fromOffset(420, size * 2.2)
	gui.StudsOffsetWorldSpace = opts.offset or Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = gui
	local main = Instance.new("TextLabel")
	main.Name = "Main"
	main.BackgroundTransparency = 1
	main.Size = UDim2.new(1, 0, 0, size)
	main.FontFace = FxUtil.Font
	main.TextSize = size
	main.Text = text
	main.TextColor3 = color
	main.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 10, 25)
	stroke.Parent = main
	local sub: TextLabel? = nil
	local subStroke: UIStroke? = nil
	if opts.sub then
		local s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.BackgroundTransparency = 1
		s.Position = UDim2.new(0, 0, 0, size * 0.95)
		s.Size = UDim2.new(1, 0, 0, size * 0.6)
		s.FontFace = FxUtil.Font
		s.TextSize = math.floor(size * 0.6)
		s.Text = opts.sub
		s.TextColor3 = Color3.new(1, 1, 1)
		s.Parent = gui
		local ss = Instance.new("UIStroke")
		ss.Thickness = 2
		ss.Color = Color3.fromRGB(20, 10, 25)
		ss.Parent = s
		sub, subStroke = s, ss
	end
	local seconds = opts.seconds or 1.4
	local rise = opts.rise or 2.2
	task.delay(opts.delay or 0, function()
		if not anchor.Parent then return end
		gui.Parent = labelFolder()
		FxUtil.Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		FxUtil.Tween(gui, seconds, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, rise, 0) }, Enum.EasingStyle.Sine)
		task.delay(seconds * 0.6, function()
			local fade = TweenInfo.new(seconds * 0.4)
			TweenService:Create(main, fade, { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			if sub and subStroke then
				TweenService:Create(sub, fade, { TextTransparency = 1 }):Play()
				TweenService:Create(subStroke, fade, { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(gui, seconds + 0.1)
		if own then Debris:AddItem(anchor, seconds + 0.2) end
	end)
end

-- ===== particles, rings, lights =====
export type BurstOpts = {
	texture: string?, color: (Color3 | ColorSequence)?, count: number?, speed: NumberRange?, life: NumberRange?,
	size: (number | NumberSequence)?, transparency: NumberSequence?, spread: number?, emission: number?,
	drag: number?, accel: Vector3?, rotation: NumberRange?, spin: NumberRange?, zOffset: number?,
	squash: NumberSequence?, box: Vector3?, dir: Vector3?, orient: Enum.ParticleOrientation?, brightness: number?,
}

-- One-shot particle burst at a point (`dir` aims the emitter, default straight up).
function FxUtil.Burst(at: Vector3, o: BurstOpts): ParticleEmitter
	local cf = CFrame.new(at)
	if o.dir and o.dir.Magnitude > 1e-3 then
		-- emitters shoot along the part's Top (+Y)
		cf = CFrame.lookAt(at, at + o.dir) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
	local p = FxUtil.Part({ CFrame = cf, Size = o.box or Vector3.new(0.2, 0.2, 0.2) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.texture or FxUtil.SPARK
	local col = o.color or Color3.new(1, 1, 1)
	e.Color = if typeof(col) == "Color3" then ColorSequence.new(col) else col
	e.Speed = o.speed or NumberRange.new(4, 10)
	e.Lifetime = o.life or NumberRange.new(0.3, 0.6)
	local size = o.size or 0.5
	e.Size = if type(size) == "number" then NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) }) else size
	e.Transparency = o.transparency or NumberSequence.new(0)
	local spread = o.spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.LightEmission = o.emission or 1
	e.LightInfluence = 0
	e.Brightness = o.brightness or 1
	e.Drag = o.drag or 0
	e.Acceleration = o.accel or Vector3.zero
	e.Rotation = o.rotation or NumberRange.new(0, 360)
	e.RotSpeed = o.spin or NumberRange.new(0)
	e.Orientation = o.orient or Enum.ParticleOrientation.FacingCamera
	e.ZOffset = o.zOffset or 0
	if o.squash then e.Squash = o.squash end
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = p
	e:Emit(o.count or 12)
	Debris:AddItem(p, e.Lifetime.Max + 0.3)
	return e
end

-- Flat glowing ring (circle outline) lying in the part's top plane of `cf`,
-- growing from radius r0 to r1 while it fades.
function FxUtil.Ring(cf: CFrame, r0: number, r1: number, color: Color3, seconds: number, thickness: number?, transparency: number?)
	local p = FxUtil.Part({ CFrame = cf, Size = Vector3.new(r0 * 2, 0.05, r0 * 2) })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(256, 256)
	gui.Parent = p
	local th = thickness or 6
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, -th * 2, 1, -th * 2)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = th
	stroke.Transparency = transparency or 0
	stroke.Parent = frame
	FxUtil.Tween(p, seconds, { Size = Vector3.new(r1 * 2, 0.05, r1 * 2) })
	FxUtil.Tween(stroke, seconds, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(p, seconds + 0.1)
end

-- ===== combo slashes / impacts (Superior basic attacks) =====
-- Sweeping fibrous crescent (textures: a 280-degree ring whose bright head points at the image's
-- right, tail fading clockwise; the "M" variant runs the tail the other way). The ring lies in a
-- plane through `origin`: forward = `dir`, then rolled `roll` degrees about forward and tilted
-- `tilt` degrees (front edge up). The head sweeps from yaw `from` to `to` (degrees, + = towards
-- the left) in `seconds`, then everything fades in `fade`. `edge` draws a thin coloured rim layer.
export type SlashOpts = {
	ring: string, edge: string?, radius: number?, roll: number?, tilt: number?, yaw: number?,
	from: number, to: number, seconds: number?, fade: number?,
	color: Color3?, edgeColor: Color3?, brightness: number?, lift: number?, grow: number?,
}
function FxUtil.Slash(origin: Vector3, dir: Vector3, o: SlashOpts): () -> ()
	local flat = FxUtil.Flat(dir)
	local base = CFrame.lookAt(origin, origin + flat) * CFrame.Angles(0, math.rad(o.yaw or 0), 0)
		* CFrame.Angles(0, 0, math.rad(o.roll or 0)) * CFrame.Angles(math.rad(o.tilt or 0), 0, 0)
	local radius = o.radius or 8
	local full = radius * 2 / 0.78 -- the strands sit around 0.78 of the texture's half-width
	local seconds = o.seconds or 0.16
	local fade = o.fade or 0.18
	local grow = o.grow or 0.82
	local parts: {BasePart} = {}
	local imgs: {ImageLabel} = {}
	local function layer(tex: string, color: Color3, bright: number, lift: number)
		local p = FxUtil.Part({ CFrame = base, Size = Vector3.new(full, 0.05, full) })
		p:SetAttribute("Lift", lift)
		table.insert(parts, p)
		-- both faces, so the crescent reads from above and below
		table.insert(imgs, FxUtil.Sprite(p, Enum.NormalId.Top, tex, { canvas = Vector2.new(512, 512), brightness = bright, color = color }))
		local under = FxUtil.Sprite(p, Enum.NormalId.Bottom, tex, { canvas = Vector2.new(512, 512), brightness = bright * 0.8, color = color })
		under.Rotation = 180
		table.insert(imgs, under)
	end
	layer(o.ring, o.color or Color3.new(1, 1, 1), o.brightness or 2.2, 0)
	if o.edge then layer(o.edge, o.edgeColor or Color3.fromRGB(255, 200, 80), (o.brightness or 2.2) * 1.3, 0.03) end
	local from, to = math.rad(o.from), math.rad(o.to)
	local total = seconds + fade
	local stop = FxUtil.Every(total, function(t)
		local k = FxUtil.EaseOut(math.clamp(t / seconds, 0, 1))
		local yaw = from + (to - from) * k
		local s = full * (grow + (1 - grow) * k)
		for _, p in parts do
			p.Size = Vector3.new(s, 0.05, s)
			p.CFrame = base * CFrame.new(0, p:GetAttribute("Lift") or 0, 0) * CFrame.Angles(0, yaw, 0)
		end
		local f = math.clamp((t - seconds) / fade, 0, 1)
		for _, im in imgs do im.ImageTransparency = f ^ 1.2 end
		if t >= total then
			for _, p in parts do p:Destroy() end
		end
		return nil
	end)
	for _, p in parts do Debris:AddItem(p, total + 5) end -- fallback only: the updater removes them
	return stop
end

-- Hit flash on an enemy: a sharp 4-point star and a spiky white splash, plus sparks.
export type ImpactOpts = { star: string, burst: string?, color: Color3?, scale: number?, sparks: number? }
function FxUtil.Impact(at: Vector3, o: ImpactOpts)
	local scale = o.scale or 1
	local color = o.color or Color3.new(1, 1, 1)
	local p = FxUtil.Part({ CFrame = CFrame.new(at) })
	local gui, star = FxUtil.Billboard(p, 0.1, o.star, { color = Color3.new(1, 1, 1), brightness = 3 })
	star.Rotation = math.random(0, 90)
	gui.AlwaysOnTop = false
	local life = 0.2 * math.sqrt(scale)
	FxUtil.Every(life, function(_, a)
		local s = (if a < 0.3 then FxUtil.EaseOut(a / 0.3) else 1) * 3.2 * scale
		gui.Size = UDim2.fromScale(s, s)
		star.ImageTransparency = math.clamp((a - 0.35) / 0.65, 0, 1)
		return nil
	end)
	if o.burst then
		local g2, splash = FxUtil.Billboard(p, 0.1, o.burst, { color = color, brightness = 2.5 })
		splash.Rotation = math.random(0, 360)
		FxUtil.Every(life * 1.2, function(_, a)
			local s = (0.8 + 3.4 * FxUtil.EaseOut(a)) * scale
			g2.Size = UDim2.fromScale(s, s)
			splash.ImageTransparency = a ^ 1.5
			return nil
		end)
	end
	if (o.sparks or 8) > 0 then
		FxUtil.Burst(at, {
			color = ColorSequence.new(Color3.new(1, 1, 1), color), count = o.sparks or 8, speed = NumberRange.new(10, 22) ,
			life = NumberRange.new(0.12, 0.28), size = 0.28 * scale, drag = 6, spread = 180,
		})
	end
	FxUtil.Every(life * 1.2, function(t)
		if t >= life * 1.2 then p:Destroy() end
		return nil
	end)
	Debris:AddItem(p, life * 1.2 + 5) -- fallback only
end

-- Short light flash at a point (or on a part).
function FxUtil.Light(at: Vector3 | BasePart, color: Color3, range: number, brightness: number, seconds: number)
	local p: BasePart = if typeof(at) == "Vector3" then FxUtil.Part({ CFrame = CFrame.new(at) }) else at
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	FxUtil.Tween(l, seconds, { Brightness = 0 })
	Debris:AddItem(if typeof(at) == "Vector3" then p else l, seconds + 0.1)
end

-- Little glowing cubes that pop out of a point and fade ("digital" bits).
function FxUtil.Pixels(at: Vector3, color: Color3, count: number, reach: number, seconds: number)
	for _ = 1, count do
		local s = 0.1 + math.random() * 0.14
		local p = FxUtil.Part({
			CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0),
			Size = Vector3.new(s, s, s), Material = Enum.Material.Neon, Color = color, Transparency = 0.05,
		})
		local dirv = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		if dirv.Magnitude < 1e-3 then dirv = Vector3.yAxis end
		local goal = at + dirv.Unit * reach * (0.5 + math.random() * 0.5)
		FxUtil.Tween(p, seconds, { CFrame = CFrame.new(goal), Transparency = 1, Size = Vector3.new(s, s, s) * 0.4 })
		Debris:AddItem(p, seconds + 0.1)
	end
end

-- ===== sounds =====
local sfxGroup: SoundGroup? = nil
local function sfx(): SoundGroup?
	local g = sfxGroup
	if g and g.Parent then return g end
	local found = SoundService:FindFirstChild("SFX")
	sfxGroup = if found and found:IsA("SoundGroup") then found else nil
	return sfxGroup
end

export type SoundOpts = { volume: number?, pitch: number?, from: number?, looped: boolean?, fadeIn: number?, duration: number?, fadeOut: number?, reach: number? }
-- Plays a sound on a part (it follows the part), at a point, or flat (no `at`), in the
-- game's SFX group. `from` starts part-way in, `duration` stops it (fading out) after that
-- long. Returns the Sound and a stop(fadeSeconds?) function.
function FxUtil.Sound(id: string, at: (BasePart | Vector3)?, o: SoundOpts?): (Sound, (number?) -> ())
	local opts: SoundOpts = o or {}
	local s = Instance.new("Sound")
	s.Name = "WeaponSfx"
	s.SoundId = id
	local volume = opts.volume or 0.5
	s.Volume = if opts.fadeIn then 0 else volume
	s.PlaybackSpeed = opts.pitch or 1
	s.Looped = opts.looped == true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = opts.reach or 160
	s.SoundGroup = sfx()
	local holder: Instance? = nil
	if typeof(at) == "Vector3" then
		holder = FxUtil.Part({ CFrame = CFrame.new(at) })
		s.Parent = holder
	elseif at then
		s.Parent = at
	else
		s.Parent = SoundService
	end
	if opts.from then s.TimePosition = opts.from end
	s:Play()
	if opts.fadeIn then FxUtil.Tween(s, opts.fadeIn, { Volume = volume }) end
	local done = false
	local function finish()
		s:Destroy()
		if holder then holder:Destroy() end
	end
	local function stop(fade: number?)
		if done then return end
		done = true
		local f = fade or 0.25
		FxUtil.Tween(s, f, { Volume = 0 })
		task.delay(f + 0.05, finish)
	end
	if opts.duration then
		task.delay(opts.duration, function() stop(opts.fadeOut) end)
	elseif not s.Looped then
		s.Ended:Once(function()
			if not done then
				done = true
				finish()
			end
		end)
		task.delay(15, function() stop(0.1) end) -- never left behind
	end
	return s, stop
end

-- ===== per-frame updates =====
-- Calls fn(t, alpha, dt) every frame for `seconds` (the last call has alpha = 1).
-- fn returning false stops it early. Returns a stop function.
function FxUtil.Every(seconds: number, fn: (number, number, number) -> boolean?): () -> ()
	local start = os.clock()
	local conn: RBXScriptConnection? = nil
	local function stop()
		local c = conn
		conn = nil
		if c then c:Disconnect() end
	end
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = math.min(os.clock() - start, seconds)
		local ok, keep = pcall(fn, t, if seconds > 0 then t / seconds else 1, dt)
		if not ok then
			warn("[WeaponFx] " .. tostring(keep))
			stop()
		elseif keep == false or t >= seconds then
			stop()
		end
	end)
	return stop
end

-- ===== the held weapon =====
function FxUtil.Weapon(character: Model?): Model?
	local gv = character and character:FindFirstChild("GearVisuals")
	local slot = gv and gv:FindFirstChild("Weapon")
	local m = slot and slot:FindFirstChildWhichIsA("Model")
	return m
end

type GripState = { weld: Weld, rest: CFrame, owner: any, priority: number }
local grips: {[Weld]: GripState} = setmetatable({}, { __mode = "k" }) :: any

local function gripOf(character: Model?): GripState?
	local model = FxUtil.Weapon(character)
	local grip = model and model:FindFirstChild("Grip")
	local weld = grip and grip:FindFirstChild("WeaponGrip")
	if not weld or not weld:IsA("Weld") then return nil end
	local g = grips[weld]
	if not g then
		g = { weld = weld, rest = weld.C0, owner = nil, priority = 0 }
		grips[weld] = g
	end
	return g
end

-- Coded pose on the held weapon: fn(t, alpha) returns an offset from the rest grip
-- every frame for `seconds`, then it eases back in `back` seconds. Every client runs
-- it for the caster (weld changes don't replicate). A pose with a lower priority than
-- the one playing is skipped. Returns a stop function (nil when skipped).
function FxUtil.Pose(character: Model?, seconds: number, priority: number, fn: (number, number) -> CFrame, back: number?): (() -> ())?
	local g = gripOf(character)
	if not g then return nil end
	if g.owner ~= nil and g.priority > priority then return nil end
	local token = {}
	g.owner = token
	g.priority = priority
	local weld, rest = g.weld, g.rest
	local last = CFrame.identity
	local easing = false
	local function easeBack()
		if easing or g.owner ~= token then return end
		easing = true
		local from = last
		FxUtil.Every(back or 0.15, function(_, a)
			if g.owner ~= token then return false end
			if weld.Parent then weld.C0 = rest * from:Lerp(CFrame.identity, FxUtil.EaseOut(a)) end
			if a >= 1 then
				g.owner = nil
				g.priority = 0
			end
			return nil
		end)
	end
	local stopFrames = FxUtil.Every(seconds, function(t, a)
		if g.owner ~= token then return false end
		last = fn(t, a)
		if weld.Parent then weld.C0 = rest * last end
		if a >= 1 then easeBack() end
		return nil
	end)
	return function()
		stopFrames()
		easeBack()
	end
end

-- ===== animations =====
function FxUtil.Animation(kitName: string, name: string): Animation?
	local root = ReplicatedStorage:FindFirstChild("WeaponKits")
	local anims = root and root:FindFirstChild("Anims")
	local kit = anims and anims:FindFirstChild(kitName)
	local a = kit and kit:FindFirstChild(name)
	if a and a:IsA("Animation") and a.AnimationId ~= "" then return a end
	return nil
end

local tracks: {[Animator]: {[Animation]: AnimationTrack}} = setmetatable({}, { __mode = "k" }) :: any

-- Plays a published kit animation on the LOCAL player's character (it replicates).
export type AnimOpts = { fade: number?, speed: number?, weight: number?, priority: Enum.AnimationPriority? }
function FxUtil.PlayAnim(kitName: string, name: string, o: AnimOpts?): AnimationTrack?
	local anim = FxUtil.Animation(kitName, name)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not anim or not animator then return nil end
	local list = tracks[animator]
	if not list then
		list = {}
		tracks[animator] = list
	end
	local track = list[anim]
	if not track then
		local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
		if not ok then return nil end
		track = tr
		list[anim] = tr
	end
	local opts: AnimOpts = o or {}
	local t = track :: AnimationTrack
	t.Priority = opts.priority or Enum.AnimationPriority.Action
	t:Play(opts.fade or 0.08, opts.weight or 1, opts.speed or 1)
	return t
end

-- ===== characters / enemies =====
-- Afterimage: the character's visible parts in one glowing colour, fading out.
-- `move` shifts it (e.g. back to where a teleport started).
function FxUtil.Ghost(character: Model, color: Color3, seconds: number, start: number?, move: Vector3?): Model
	local m = Instance.new("Model")
	m.Name = "Ghost"
	local shift = move or Vector3.zero
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and d.Name ~= "HumanoidRootPart" then
			local was = d.Archivable
			d.Archivable = true
			local ok, c = pcall(function() return d:Clone() end)
			d.Archivable = was
			if ok and c then
				for _, ch in c:GetChildren() do
					if not ch:IsA("DataModelMesh") then ch:Destroy() end
				end
				local mesh = c:FindFirstChildWhichIsA("SpecialMesh")
				if mesh then mesh.TextureId = "" end
				if c:IsA("MeshPart") then pcall(function() (c :: any).TextureID = "" end) end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.Material = Enum.Material.Neon
				c.Color = color
				c.Transparency = start or 0.3
				c.CFrame = d.CFrame + shift
				c.Parent = m
				FxUtil.Tween(c, seconds, { Transparency = 1 })
			end
		end
	end
	m.Parent = FxUtil.Folder()
	Debris:AddItem(m, seconds + 0.1)
	return m
end

export type EnemyInfo = { model: Model, root: BasePart, dist: number }
-- Living enemies within `range` of `from` (counted to their edge), nearest first.
function FxUtil.Enemies(from: Vector3, range: number): {EnemyInfo}
	local out: {EnemyInfo} = {}
	for _, m in CollectionService:GetTagged(ENEMY_TAG) do
		if m:IsA("Model") and m:IsDescendantOf(workspace) then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local root = m.PrimaryPart
			if hum and root and hum.Health > 0 then
				local d = (root.Position - from).Magnitude
				if d - math.max(root.Size.X, root.Size.Z) / 2 <= range then
					table.insert(out, { model = m, root = root, dist = d })
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	return out
end

-- Distance from `origin` along `dir` to the first solid wall (enemies, characters,
-- effects and see-through or non-colliding parts don't stop it), at most `maxLen`.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
function FxUtil.WallDistance(origin: Vector3, dir: Vector3, maxLen: number): number
	local ignore: {Instance} = { FxUtil.Folder() }
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(ignore, p.Character) end
	end
	wallParams.FilterDescendantsInstances = ignore
	local pos, left = origin, maxLen
	for _ = 1, 8 do
		local hit = workspace:Raycast(pos, dir * left, wallParams)
		if not hit then return maxLen end
		local inst = hit.Instance
		local model = inst:FindFirstAncestorWhichIsA("Model")
		local isCreature = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
		if not isCreature and inst.CanCollide and inst.Transparency < 0.9 then
			return (hit.Position - origin).Magnitude
		end
		table.insert(ignore, if isCreature and model then model else inst)
		wallParams.FilterDescendantsInstances = ignore
		left -= (hit.Position - pos).Magnitude
		pos = hit.Position
		if left <= 0.05 then return maxLen end
	end
	return (pos - origin).Magnitude
end

function FxUtil.FeetY(character: Model?, root: BasePart): number
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local hip = if hum then hum.HipHeight else 2
	return root.Position.Y - root.Size.Y / 2 - hip
end

return FxUtil
