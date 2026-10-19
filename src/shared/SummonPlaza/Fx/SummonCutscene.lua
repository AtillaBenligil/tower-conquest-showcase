--!strict
-- SummonCutscene
-- Location: ReplicatedStorage.SummonPlaza.Fx.SummonCutscene (ModuleScript, client only)
--
-- The star-fall cutscene for YOUR OWN Legendary+ pulls (rebuilt 2026-10-08;
-- the old chest-burst version is in ServerStorage.Backup_SummonRework_2026-10-08).
-- SummonWindow calls Play(results) when a summon has a Legendary or better:
--   1. strain   the floating chest spins, pulses and rattles, trying to
--               open but it can't (1.5 s)
--   2. open     it bursts open, a light shoots up, the camera whips up into
--               the night sky
--   3. stars    one shooting star per pull (x1 = 1, x10 = 10 side by side),
--               seen from below. Each Legendary+ pull's star turns its
--               tier's colour; the rarest one decides the ending:
--      Legendary  the yellow star swerves and dives straight into the
--                 camera, its light covers the screen (white)
--      Mythic     the red star stops, flares and pulses with shockwaves,
--                 then spirals into the camera (red, then white) -- longer,
--                 more effects, camera shake
--      Superior   a black hole opens in front of the stars, they orbit it
--                 faster and faster, merge into one big Superior star that
--                 pulses 5 times and then fills the screen with light
--   4. reveal   every Legendary+ item on its own screen, rarest first;
--               click / tap for the next one
-- Then it returns and SummonWindow shows the normal results screen.
-- The SKIP button (bottom right) jumps straight to the reveals (and during
-- the reveals, skips them all). Settings -> "Summon cutscene" off: no
-- cutscene and no reveals, straight to the results.
-- While it plays: every other ScreenGui is hidden, the character is held
-- still, and the player attribute "SummonCutscene" holds the current part
-- ("strain", "stars", "reveal") -- EffectRunner then leaves out this
-- player's own lobby event, NightSkyClient pauses its shooting stars.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local RarityConfig = require(ReplicatedStorage.GearSystem.RarityConfig)
local LobbyLighting = require(ReplicatedStorage.LobbyLighting)
local SettingsConfig = require(ReplicatedStorage.SettingsConfig)
local ChestController = require(script.Parent.Shared.ChestController)
local StarFx = require(script.Parent.Shared.StarFx)

local SummonCutscene = {}

export type Result = {
	rarity: string,
	name: string?,
	category: string?,
	set: string?,           -- the item's set name
	serialNumber: number?,
	dupe: boolean?, refund: number?,
	autoSold: boolean?, tokensAwarded: number?,
	unlockedSet: string?,   -- pulling it unlocked this set (Selection Banner)
	selected: boolean?,     -- the Selection Banner's grand prize
	preview: boolean?,      -- /summonfx: nothing was given
}

type State = { gui: ScreenGui?, cleanups: {() -> ()} }

local HEADING = Font.fromEnum(Enum.Font.FredokaOne)
local BODY = Font.fromEnum(Enum.Font.GothamBold)
pcall(function() -- the HUD's fonts when UITheme is around
	local UITheme = require(ReplicatedStorage:WaitForChild("UITheme", 5) :: ModuleScript) :: any
	HEADING = UITheme.FontFaces.Heading or HEADING
	BODY = UITheme.FontFaces.Body or BODY
end)

-- licensed library sounds (ProSoundEffects / APMOfficial)
local SFX = {
	Rattle = { 9119128546, 0.7 },  -- wood knocks (the chest lid)
	Boom = { 9125484367, 0.6 },    -- deep reverberant hit
	Whip = { 9120715547, 0.55 },   -- fast whoosh by
	Shoot = { 9118849619, 0.35 },  -- airy shimmering whoosh
	Chime = { 9114369623, 0.6 },   -- fairy-dust chimes
	Rush = { 9039693350, 0.7 },    -- APM swell to a sudden stop
	Suck = { 9039693523, 0.7 },    -- APM swell to a suck-out
	Rumble = { 1843027142, 0.7 },  -- APM low rumble
	Pulse = { 9126084278, 0.5 },   -- low pulsing synth
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CAMERA_STEP = "SummonCutsceneCamera"

-- timeline (seconds from the start)
local T_STRAIN = 1.5   -- the chest tries to open
local T_OPEN = 0.35    -- the burst before the camera whips up
local T_WHIP = 0.6
local T_SHOOT = T_STRAIN + 0.55 -- the stars start (while the camera is still turning)
local DEPTH = 900      -- how far up the stars fly (studs from the camera)

local player = Players.LocalPlayer
local playing = false

local function rank(r: string?): number
	return if r then (table.find(RarityConfig.Order, r) or 0) else 0
end

local function make(className: string, props: {[string]: any}, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do (inst :: any)[key] = value end
	if parent then inst.Parent = parent end
	return inst
end

local function tween(inst: Instance, seconds: number, props: {[string]: any}, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function inOut(a: number): number
	a = math.clamp(a, 0, 1)
	return if a < 0.5 then 4 * a * a * a else 1 - (-2 * a + 2) ^ 3 / 2
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: number): Vector3
	local a = 1 - u
	return p0 * (a * a * a) + p1 * (3 * a * a * u) + p2 * (3 * a * u * u) + p3 * (u * u * u)
end

local function sound(key: string, volume: number?, pitch: number?): Sound?
	local def = (SFX :: any)[key]
	if not def then return nil end
	local s = make("Sound", {
		Name = "SummonCutscene_" .. key, SoundId = "rbxassetid://" .. tostring(def[1]),
		Volume = def[2] * (volume or 1), PlaybackSpeed = pitch or 1,
	})
	local group = SoundService:FindFirstChild("SFX")
	if group and group:IsA("SoundGroup") then s.SoundGroup = group end
	s.Parent = SoundService
	s:Play()
	task.delay(12, function() s:Destroy() end)
	return s
end

-- Is this rarity one that gets the cutscene + its own reveal screen?
function SummonCutscene.For(rarity: string?): boolean
	return rank(rarity) >= rank("Legendary") and rarity ~= "Admin" and rarity ~= nil
end

function SummonCutscene.IsPlaying(): boolean
	return playing
end

-- Settings -> "Summon cutscene" (on by default).
function SummonCutscene.Enabled(): boolean
	return SettingsConfig.Get(player, "SummonCutscene") ~= false
end

-- ===================================================================
-- the reveal screens: one per Legendary+ item, rarest first
-- ===================================================================
local function revealText(r: Result): (string, string, string, Color3)
	local over = if r.preview then "EFFECTS PREVIEW" elseif r.selected then "GRAND PRIZE" else "YOU SUMMONED"
	local sub = tostring(r.category or "")
	if r.set and r.set ~= "" then sub = (if sub ~= "" then sub .. "  ·  " else "") .. r.set end
	local note, noteColor = "NEW!", Color3.fromRGB(120, 255, 150)
	if r.preview then
		note, noteColor = "Preview -- nothing was given", Color3.fromRGB(205, 200, 220)
	elseif r.autoSold then
		note, noteColor = ("Auto-sold for %d Tokens"):format(r.tokensAwarded or 0), Color3.fromRGB(255, 214, 110)
	elseif r.dupe then
		note, noteColor = ("Duplicate  ·  +%d Tokens"):format(r.refund or 0), Color3.fromRGB(255, 214, 110)
	end
	if r.unlockedSet then
		note ..= "\nSET UNLOCKED: " .. r.unlockedSet .. " -- choose it on the Selection Banner"
	end
	return over, sub, note, noteColor
end

local function runReveals(gui: ScreenGui, rares: {Result}, skipButton: TextButton, skipLabel: TextLabel, isSkipped: () -> boolean)
	local root = make("Frame", {
		Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 10, 28),
		BorderSizePixel = 0, ZIndex = 20,
	}, gui)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(10, 18, 48), Color3.fromRGB(4, 6, 18)),
	}, root)
	local rays = make("ImageLabel", {
		Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(1.3, 1.3),
		SizeConstraint = Enum.SizeConstraint.RelativeXX, BackgroundTransparency = 1, Image = StarFx.Textures.Rays,
		ImageTransparency = 0.25, ZIndex = 21,
	}, root)
	local glow = make("ImageLabel", {
		Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.75, 0.75),
		SizeConstraint = Enum.SizeConstraint.RelativeXX, BackgroundTransparency = 1, Image = StarFx.Textures.Glow,
		ImageTransparency = 0.2, ZIndex = 22,
	}, root)
	local flare = make("ImageLabel", {
		Name = "Flare", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.5, 0.5),
		SizeConstraint = Enum.SizeConstraint.RelativeXX, BackgroundTransparency = 1, Image = StarFx.Textures.Flare,
		ImageTransparency = 0.1, ZIndex = 23,
	}, root)
	local card = make("CanvasGroup", {
		Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.92, 0.8),
		BackgroundTransparency = 1, ZIndex = 25,
	}, root)
	make("UISizeConstraint", { MaxSize = Vector2.new(1300, 700) }, card)
	local scale = make("UIScale", { Scale = 1 }, card)
	local over = make("TextLabel", {
		Name = "Over", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.12), Size = UDim2.fromScale(1, 0.06),
		BackgroundTransparency = 1, FontFace = BODY, TextScaled = true, TextColor3 = WHITE, ZIndex = 26,
	}, card)
	make("UIStroke", { Color = BLACK, Thickness = 1.5, Transparency = 0.3 }, over)
	local tierLabel = make("TextLabel", {
		Name = "Tier", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.19), Size = UDim2.fromScale(1, 0.17),
		BackgroundTransparency = 1, FontFace = HEADING, TextScaled = true, TextColor3 = WHITE, ZIndex = 26,
	}, card)
	local tierStroke = make("UIStroke", { Thickness = 4 }, tierLabel)
	local shine = make("UIGradient", { Offset = Vector2.new(-0.6, 0) }, tierLabel)
	local shineTween = TweenService:Create(shine, TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(0.6, 0) })
	shineTween:Play()
	local itemLabel = make("TextLabel", {
		Name = "Item", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromScale(1, 0.13),
		BackgroundTransparency = 1, FontFace = HEADING, TextScaled = true, TextColor3 = WHITE, ZIndex = 26,
	}, card)
	local itemStroke = make("UIStroke", { Thickness = 3 }, itemLabel)
	local subLabel = make("TextLabel", {
		Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromScale(1, 0.05),
		BackgroundTransparency = 1, FontFace = BODY, TextScaled = true, TextColor3 = Color3.fromRGB(215, 222, 245), ZIndex = 26,
	}, card)
	make("UIStroke", { Color = BLACK, Thickness = 1.2, Transparency = 0.4 }, subLabel)
	local noteLabel = make("TextLabel", {
		Name = "Note", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.81), Size = UDim2.fromScale(1, 0.1),
		BackgroundTransparency = 1, FontFace = BODY, TextScaled = true, TextWrapped = true, ZIndex = 26,
	}, card)
	make("UITextSizeConstraint", { MaxTextSize = 26 }, noteLabel)
	make("UIStroke", { Color = BLACK, Thickness = 1.2, Transparency = 0.4 }, noteLabel)
	local counter = make("TextLabel", {
		Name = "Counter", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 22), Size = UDim2.fromOffset(160, 34),
		BackgroundTransparency = 1, FontFace = HEADING, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = WHITE, ZIndex = 27,
	}, root)
	make("UIStroke", { Color = BLACK, Thickness = 1.5, Transparency = 0.3 }, counter)
	local hint = make("TextLabel", {
		Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.fromOffset(420, 26),
		BackgroundTransparency = 1, FontFace = BODY, TextScaled = true, TextColor3 = Color3.fromRGB(200, 205, 230), ZIndex = 27,
		Text = if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then "Tap to continue" else "Click to continue",
	}, root)
	local flash = make("Frame", {
		Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 39,
	}, root)

	local spin = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation = (rays.Rotation + dt * 9) % 360
		flare.Rotation = (flare.Rotation - dt * 4) % 360
	end)

	local advance = false
	local clickConn = UserInputService.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
			advance = true
		end
	end)
	skipLabel.Text = if #rares > 1 then "SKIP ALL" else "SKIP"

	for i, r in rares do
		if isSkipped() then break end
		player:SetAttribute("SummonCutscene", "reveal")
		local color = RarityConfig.GetColor(r.rarity)
		local superior = r.rarity == "Superior"
		local o, sub, note, noteColor = revealText(r)
		over.Text = o
		tierLabel.Text = string.upper(r.rarity)
		tierStroke.Color = color:Lerp(BLACK, 0.6)
		shine.Color = if superior
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 160, 220)),
				ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(140, 220, 255)),
				ColorSequenceKeypoint.new(1, color),
			})
			else ColorSequence.new({
				ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.42, color:Lerp(WHITE, 0.3)),
				ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(0.58, color:Lerp(WHITE, 0.3)),
				ColorSequenceKeypoint.new(1, color),
			})
		local name = tostring(r.name or "?")
		if r.serialNumber then name ..= "  #" .. tostring(r.serialNumber) end
		itemLabel.Text = name
		itemStroke.Color = color:Lerp(BLACK, 0.55)
		subLabel.Text = sub
		noteLabel.Text = note
		noteLabel.TextColor3 = noteColor
		counter.Text = if #rares > 1 then ("%d / %d"):format(i, #rares) else ""
		rays.ImageColor3 = color
		glow.ImageColor3 = color:Lerp(WHITE, 0.15)
		flare.ImageColor3 = color:Lerp(WHITE, 0.5)
		root.BackgroundColor3 = color:Lerp(Color3.fromRGB(6, 10, 28), 0.85)
		-- entrance: a white flash, the card lands from big to normal
		flash.BackgroundTransparency = if i == 1 then 0 else 0.25
		tween(flash, if i == 1 then 0.7 else 0.4, { BackgroundTransparency = 1 })
		card.GroupTransparency = 1
		scale.Scale = 1.35
		tween(card, 0.3, { GroupTransparency = 0 })
		tween(scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
		glow.Size = UDim2.fromScale(0.2, 0.2)
		tween(glow, 0.6, { Size = UDim2.fromScale(0.75, 0.75) }, Enum.EasingStyle.Quart)
		sound("Chime", if superior then 1.2 else 1)
		if rank(r.rarity) >= rank("Mythic") then sound("Boom", 0.7) end
		-- clicks before 0.45 s don't count (the click that ended the last screen)
		local shownAt = os.clock()
		advance = false
		while not isSkipped() do
			if advance and os.clock() - shownAt > 0.45 then break end
			advance = false
			task.wait()
		end
	end
	clickConn:Disconnect()
	spin:Disconnect()
	shineTween:Cancel()
	local _ = skipButton
end

-- ===================================================================
-- the star scene
-- ===================================================================
type StarRow = {
	star: StarFx.Star,
	lane: number,
	start: number,
	rarity: string?,  -- set when this star belongs to a Legendary+ pull
	main: boolean,
	colored: boolean,
	mode: string,     -- "line" | "rush" | "hover" | "orbit" | "gone"
	breakAt: Vector3?,
	breakDir: Vector3?,
	theta: number, r0: number,
	sparks: ParticleEmitter?,
}

local function run(results: {Result}, preview: boolean, state: State, undo: () -> ())
	local function onUndo(fn: () -> ())
		table.insert(state.cleanups, fn)
	end
	local function phase(name: string?)
		player:SetAttribute("SummonCutscene", name)
	end
	phase("strain")
	onUndo(function() phase(nil) end)

	-- the rare pulls, rarest first (same rarity: the order pulled)
	local order: {[Result]: number} = {}
	local rares: {Result} = {}
	for i, r in results do
		order[r] = i
		if SummonCutscene.For(r.rarity) then table.insert(rares, r) end
	end
	table.sort(rares, function(a, b)
		local ra, rb = rank(a.rarity), rank(b.rarity)
		if ra ~= rb then return ra > rb end
		return order[a] < order[b]
	end)
	local best = rares[1]
	local tier = best.rarity
	local tierColor = RarityConfig.GetColor(tier)
	local superior = tier == "Superior"
	local mythic = tier == "Mythic"

	-- ---------- the screen ----------
	local gui = make("ScreenGui", {
		Name = "SummonCutscene", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui
	state.gui = gui
	make("TextButton", { -- takes every click: nothing underneath reacts while it plays
		Name = "Catcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
		AutoButtonColor = false, Selectable = false, ZIndex = 1,
	}, gui)
	local tint = make("ImageLabel", { -- glowing screen edges in the tier's colour (Mythic)
		Name = "Tint", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = StarFx.Textures.Vignette,
		ImageColor3 = tierColor, ImageTransparency = 1, ScaleType = Enum.ScaleType.Stretch, ZIndex = 35,
	}, gui)
	local white = make("Frame", {
		Name = "White", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 40,
	}, gui)
	local fade = make("Frame", {
		Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0,
		BorderSizePixel = 0, ZIndex = 50,
	}, gui)
	local skip = make("TextButton", {
		Name = "Skip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(150, 48),
		BackgroundColor3 = Color3.fromRGB(14, 18, 40), BackgroundTransparency = 0.25, AutoButtonColor = true, Text = "",
		Visible = false, ZIndex = 45,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, skip)
	make("UIStroke", { Color = Color3.fromRGB(190, 205, 255), Thickness = 2, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, skip)
	local skipLabel = make("TextLabel", {
		Name = "Label", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, FontFace = HEADING, TextScaled = true,
		Text = "SKIP  ▶▶", TextColor3 = WHITE, ZIndex = 46,
	}, skip)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, skipLabel)
	local skipped = false
	skip.MouseButton1Click:Connect(function() skipped = true end)

	-- ---------- hide the HUD, the windows and the menu blur ----------
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hidden: {ScreenGui} = {}
	if playerGui then
		for _, other in playerGui:GetChildren() do
			if other:IsA("ScreenGui") and other.Enabled then
				other.Enabled = false
				table.insert(hidden, other)
			end
		end
	end
	onUndo(function()
		for _, other in hidden do
			if other.Parent then other.Enabled = true end
		end
	end)
	local blurInst = Lighting:FindFirstChild("UIBlur")
	if blurInst and blurInst:IsA("BlurEffect") and blurInst.Enabled then
		local blur = blurInst :: BlurEffect
		blur.Enabled = false
		onUndo(function() blur.Enabled = true end)
	end
	gui.Parent = playerGui or player:WaitForChild("PlayerGui")
	task.delay(0.4, function() if gui.Parent then skip.Visible = true end end)

	-- ---------- hold the character still ----------
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local restoreBody: () -> () = function() end
	if character and root then
		local wasAnchored = root.Anchored
		local walk = if humanoid then humanoid.WalkSpeed else nil
		local canJump = if humanoid then humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) else nil
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
		root.Anchored = true
		local done = false
		restoreBody = function()
			if done then return end
			done = true
			if root.Parent then root.Anchored = wasAnchored end
			if humanoid and humanoid.Parent then
				if humanoid.WalkSpeed == 0 and walk then humanoid.WalkSpeed = walk end
				if canJump ~= nil then humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, canJump) end
			end
		end
		onUndo(restoreBody)
	end

	-- ---------- where everything happens ----------
	local chestAt = ChestController.GetPosition()
	local p0 = if root then root.Position else camera.CFrame.Position
	local haveChest = chestAt ~= nil and (p0 - (chestAt :: Vector3)).Magnitude < 300 and LobbyLighting.IsInLobby(p0)
	local anchor: Vector3 = if haveChest then chestAt :: Vector3 else p0 + Vector3.new(0, 4, 0)
	local flat = Vector3.new(p0.X - anchor.X, 0, p0.Z - anchor.Z) -- from the chest toward you
	if flat.Magnitude < 3 then
		local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
		flat = if look.Magnitude > 0.05 then -look.Unit else Vector3.new(0, 0, 1)
	end
	flat = flat.Unit
	local side = flat:Cross(Vector3.yAxis)
	-- the chest is ~26 studs wide (46 with its rays): frame it from 58 studs out, a little below
	local chestCF = CFrame.lookAt(anchor + flat * 58 + side * 8 + Vector3.new(0, -9, 0), anchor + Vector3.new(0, 1, 0))
	local pitch = math.rad(58)
	local skyPos = anchor + flat * 30 + Vector3.new(0, 14, 0) -- above the chest's lid, looking up past it
	local stageCF = CFrame.lookAt(skyPos, skyPos + (-flat) * math.cos(pitch) + Vector3.yAxis * math.sin(pitch))
	local function W(x: number, y: number, depth: number?): Vector3
		return stageCF * Vector3.new(x, y, -(depth or DEPTH))
	end

	-- ---------- the camera ----------
	local savedType, savedCFrame, savedFov = camera.CameraType, camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	local cameraRestored = false
	local function restoreCamera()
		if cameraRestored then return end
		cameraRestored = true
		RunService:UnbindFromRenderStep(CAMERA_STEP)
		camera.CameraType = savedType
		camera.CFrame = savedCFrame
		camera.FieldOfView = savedFov
	end
	onUndo(restoreCamera)

	-- ---------- scene objects ----------
	local fxFolder = make("Folder", { Name = "SummonCutsceneFx" }, workspace)
	onUndo(function() fxFolder:Destroy() end)
	onUndo(function() ChestController.Strain(0) end)

	local function ring(at: Vector3, color: Color3, from: number, to: number, seconds: number, transparency: number?)
		local g, img, part = StarFx.Billboard(StarFx.Textures.Ring, at, from, color, fxFolder)
		img.ImageTransparency = transparency or 0
		tween(g, seconds, { Size = UDim2.fromScale(to, to) }, Enum.EasingStyle.Quart)
		tween(img, seconds, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(seconds + 0.05, function() part:Destroy() end)
	end

	-- one star per pull (at most 10 on screen: Legendary+ pulls first)
	local shown: {Result} = {}
	if #results <= 10 then
		shown = table.clone(results)
	else
		for _, r in rares do if #shown < 10 then table.insert(shown, r) end end
		for _, r in results do
			if #shown >= 10 then break end
			if not table.find(shown, r) then table.insert(shown, r) end
		end
		table.sort(shown, function(a, b) return order[a] < order[b] end)
	end
	local n = #shown
	local spacing = if n > 6 then 108 else 130 -- side by side across the sky
	local stars: {StarRow} = {}
	local mainRow: StarRow? = nil
	for i, r in shown do
		local lane = (i - (n + 1) / 2) * spacing
		local row: StarRow = {
			star = nil :: any, lane = lane, start = T_SHOOT + ((i * 7) % math.max(n, 1)) * 0.01,
			rarity = if SummonCutscene.For(r.rarity) then r.rarity else nil,
			main = r == best, colored = false, mode = "line",
			theta = 0, r0 = 0,
		}
		table.insert(stars, row)
		if row.main then mainRow = row end
	end

	local DIR = Vector2.new(1, -0.42).Unit
	local PERP = Vector2.new(0.42, 1).Unit
	local C0 = Vector2.new(-40, 150)
	local SPEED = 1150
	local function linePos(row: StarRow, s: number): Vector2
		return C0 + DIR * (SPEED * s - 1250) + PERP * row.lane
	end
	local worldDir = (W(DIR.X, DIR.Y) - W(0, 0)).Unit

	-- ---------- tier timings ----------
	local tColor = T_SHOOT + 0.95       -- the rare stars change colour
	local tBreak = T_SHOOT + (if mythic then 1.1 else 1.25) -- the main star leaves its lane
	local T_RUSH = if mythic then 0.95 else 1.05
	local tHover, T_HOVER_IN, T_HOVER = tBreak, 0.55, 1.0 -- Mythic: stop and flare
	local tRush = if mythic then tHover + T_HOVER_IN + T_HOVER else tBreak
	local tBH, tCapture, T_ORBIT = T_SHOOT + 0.65, T_SHOOT + 0.8, 3.2 -- Superior
	local tMerge = tCapture + T_ORBIT
	local T_PULSE = 0.55
	local tFinal = tMerge + 0.25 + 5 * T_PULSE
	local tEnd = if superior then tFinal + 0.55 elseif mythic then tRush + T_RUSH else tRush + T_RUSH

	-- Superior pieces
	local holeAt = W(0, 70, 820)
	local hole: { gui: BillboardGui, discImg: ImageLabel }? = nil
	local big: { gui: BillboardGui, flareImg: ImageLabel, raysImg: ImageLabel }? = nil
	-- one billboard with stacked images (a fixed draw order); sizes are fractions of the billboard
	local function layer(gui: BillboardGui, id: string, frac: number, color: Color3, z: number, transparency: number?): ImageLabel
		return make("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(frac, frac),
			BackgroundTransparency = 1, Image = id, ImageColor3 = color, ImageTransparency = transparency or 0, ZIndex = z,
		}, gui)
	end
	local pulsesDone = 0

	local shake = 0
	local t0 = os.clock()
	-- testing: workspace attribute SummonCutsceneFreezeAt (set on the client) holds
	-- the scene at that second, for screenshots
	local function now(): number
		local freeze = workspace:GetAttribute("SummonCutsceneFreezeAt")
		local t = os.clock() - t0
		return if type(freeze) == "number" then math.min(t, freeze) else t
	end
	local played: {[string]: boolean} = {}
	local function once(key: string, fn: () -> ())
		if not played[key] then
			played[key] = true
			fn()
		end
	end
	local lastT = 0

	-- the main star's flight into the camera (Legendary / Mythic)
	local function rushPos(from: Vector3, dir: Vector3, u: number, spiral: boolean): Vector3
		local cam = camera.CFrame
		local p1 = from + dir * 220
		local p2 = cam.Position + cam.LookVector * 120 + cam.RightVector * 30 + cam.UpVector * 10
		local p3 = cam.Position + cam.LookVector * 3.5
		local p = bezier(from, p1, p2, p3, u)
		if spiral then
			local a = (1 - u) * 46
			p += cam.RightVector * math.cos(u * math.pi * 6) * a + cam.UpVector * math.sin(u * math.pi * 6) * a
		end
		return p
	end

	local function frame()
		local t = now()
		local dt = math.max(0, t - lastT)
		lastT = t

		-- ===== camera =====
		local cf: CFrame
		local fov: number
		local tWhip = T_STRAIN + T_OPEN - 0.05
		if t < tWhip then
			local a = smooth(t / T_STRAIN)
			cf = chestCF * CFrame.new(0, 0, -5 * a)
			fov = 48 - 3 * a
		elseif t < tWhip + T_WHIP then
			local a = inOut((t - tWhip) / T_WHIP)
			cf = chestCF:Lerp(stageCF, a)
			fov = 45 + 25 * a
		else
			local s = t - (tWhip + T_WHIP)
			cf = stageCF * CFrame.Angles(math.rad(0.5) * s, math.rad(0.35) * s, 0)
			if superior and t > tCapture then
				cf += cf.LookVector * (math.min(t - tCapture, T_ORBIT + 3) * 14)
			end
			fov = 70
		end
		if shake > 0 then
			cf *= CFrame.Angles((math.random() - 0.5) * shake * 0.03, (math.random() - 0.5) * shake * 0.03, (math.random() - 0.5) * shake * 0.02)
		end
		camera.CFrame = cf
		camera.FieldOfView = fov

		-- ===== chest =====
		if haveChest and t < T_STRAIN then
			local a = t / T_STRAIN
			ChestController.Strain(0.35 + 0.65 * a)
		end

		-- ===== stars =====
		for _, row in stars do
			local s = t - row.start
			if s < 0 or row.mode == "gone" then continue end
			if not row.star then
				row.star = StarFx.New(nil, 60, 13)
				row.star.part.Parent = fxFolder
				row.star:SetWidth(13, 1.5)
			end
			local star = row.star
			-- colour change
			if row.rarity and not row.colored and t >= tColor + (if row.main then 0 else 0.12) then
				row.colored = true
				local c = RarityConfig.GetColor(row.rarity)
				star:SetColor(c)
				ring(star.part.Position, c, 30, if row.main then 260 else 140, 0.7)
				if row.main then
					sound("Chime", 1.1)
					if row.rarity == "Mythic" or row.rarity == "Superior" then
						local e = make("ParticleEmitter", {
							Texture = StarFx.Textures.Sparkle, Color = ColorSequence.new(c:Lerp(WHITE, 0.4), c),
							LightEmission = 1, LightInfluence = 0, Rate = 90, Lifetime = NumberRange.new(0.4, 0.8),
							Speed = NumberRange.new(150, 420), SpreadAngle = Vector2.new(180, 180),
							Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 42), NumberSequenceKeypoint.new(1, 0) }),
							Transparency = NumberSequence.new(0.1), ZOffset = 1,
						}, star.part)
						row.sparks = e
					end
				end
			end
			local headSize = if row.colored then (if row.main then 95 else 78) else 60

			if row.mode == "line" then
				-- Legendary / Mythic: the main star leaves its lane
				if row.main and not superior and t >= tBreak then
					row.mode = if mythic then "hover" else "rush"
					row.breakAt = star.part.Position
					row.breakDir = worldDir
				elseif superior and t >= tCapture then
					-- Superior: every star is caught by the black hole
					-- each star gets its own slot around the hole (they fly into it while the orbit starts)
					local p = linePos(row, s)
					local rel = p - Vector2.new(0, 70)
					local slot = (table.find(stars, row) or 1) - 1
					row.theta = math.atan2(rel.Y / 0.55, rel.X) + slot * (2 * math.pi / math.max(n, 1))
					row.r0 = 520 + (slot % 3) * 70
					row.mode = "orbit"
				else
					local p = linePos(row, s)
					local grow = math.min(1, s / 0.2)
					star:Place(W(p.X, p.Y), W(p.X - DIR.X * 560 * grow, p.Y - DIR.Y * 560 * grow))
					star:SetHeadSize(headSize)
					star:SetFade(if s > 2.6 then math.min(1, (s - 2.6) / 0.4) else 0)
					if s > 3.1 then row.mode = "gone"; star.part.Parent = nil end
				end
			end

			if row.mode == "hover" then
				-- Mythic: brakes to the middle of the sky and flares
				local from = row.breakAt :: Vector3
				local target = W(0, 40, 650)
				local u = (t - tHover) / T_HOVER_IN
				local pos: Vector3
				if u < 1 then
					local e = 1 - (1 - u) ^ 3
					pos = bezier(from, from + worldDir * 200, target + worldDir * -60, target, e)
					star:Place(pos, bezier(from, from + worldDir * 200, target + worldDir * -60, target, math.max(0, e - 0.12)))
					star:SetHeadSize(headSize)
				else
					local h = t - (tHover + T_HOVER_IN)
					local beat = math.abs(math.sin(h * math.pi * 3))
					star:Place(target, target + worldDir * -1)
					star:SetWidth(0.1, 0.1)
					star:SetHeadSize(170 + 110 * beat + 90 * h)
					star.flare.Rotation = (star.flare.Rotation + dt * 260) % 360
					shake = 0.6 + 1.4 * h
					tint.ImageTransparency = 0.7 - 0.35 * beat - 0.2 * h
					for k, at in { 0.05, 0.4, 0.75 } do
						if h >= at then
							once("mring" .. k, function()
								ring(target, tierColor, 80, 900 + 250 * k, 0.9)
								ring(target, WHITE, 60, 520 + 160 * k, 0.65, 0.2)
								if row.sparks then row.sparks:Emit(40) end
								sound("Boom", 0.45 + 0.15 * k, 1.1 - 0.05 * k)
							end)
						end
					end
					once("mrushsfx", function() sound("Rush", 1) end)
					if t >= tRush then
						row.mode = "rush"
						row.breakAt = target
						row.breakDir = (camera.CFrame.Position - target).Unit * -1
						star:SetWidth(18, 2)
					end
				end
			end

			if row.mode == "rush" then
				local from = row.breakAt :: Vector3
				local u = math.clamp((t - tRush) / T_RUSH, 0, 1)
				local e = u ^ 2.2
				local spiral = mythic
				local dir = if mythic then worldDir * 0.4 else row.breakDir :: Vector3
				star:Place(rushPos(from, dir, e, spiral), rushPos(from, dir, math.max(0, e - 0.16), spiral))
				star:SetHeadSize(if mythic then 260 + 200 * e else 150 + 120 * e)
				star:SetWidth(if mythic then 34 else 26, 3)
				if mythic then
					star.flare.Rotation = (star.flare.Rotation + dt * 400) % 360
					shake = 2 + 4 * e
					tint.ImageTransparency = math.max(0, 0.4 - 0.6 * e)
				end
				once("rushsfx", function() if not mythic then sound("Rush", 0.9) end end)
				-- the light covers the screen
				local w = math.clamp((u - 0.62) / 0.38, 0, 1)
				white.BackgroundTransparency = 1 - w
				white.BackgroundColor3 = WHITE:Lerp(tierColor, 0.18 * (1 - w))
			end

			if row.mode == "orbit" then
				-- Superior: around the black hole, faster and faster, spiralling in
				local tau = t - tCapture
				local a = math.clamp(tau / T_ORBIT, 0, 1)
				local omega = 1.1 + 9.5 * a * a
				row.theta += omega * dt
				local r = row.r0 * (1 - smooth(a)) ^ 0.9
				local function orbitAt(theta: number, rr: number): Vector3
					local x, y = rr * math.cos(theta), rr * 0.55 * math.sin(theta)
					local c, sn = math.cos(math.rad(14)), math.sin(math.rad(14))
					return W(x * c - y * sn, 70 + x * sn + y * c, 820)
				end
				local head = orbitAt(row.theta, r)
				local blend = smooth(tau / 0.7)
				if blend < 1 then
					local p = linePos(row, s)
					head = W(p.X, p.Y):Lerp(head, blend)
				end
				local lag = math.min(1.4, omega * 0.09)
				star:Place(head, orbitAt(row.theta - lag, r * 1.05))
				star:SetHeadSize(headSize * (0.7 + 0.3 * (1 - a)))
				star:SetWidth(13 * (0.6 + 0.4 * (1 - a)), 1.5)
				if tau >= T_ORBIT then
					row.mode = "gone"
					star.part.Parent = nil
				end
			end
		end

		-- ===== Superior: the black hole and the big star =====
		if superior then
			if t >= tBH and not hole then
				-- the black hole: purple haze, the swirling disc, the black core on top
				local g, hazeImg = StarFx.Billboard(StarFx.Textures.Glow, holeAt, 1, Color3.fromRGB(120, 70, 255), fxFolder)
				hazeImg.ImageTransparency = 0.55
				-- sizes so the black core fills the disc's photon ring (core black r = 0.4, ring r = 0.4 of each image)
				local discImg = layer(g, StarFx.Textures.BlackHoleDisc, 0.62, tierColor:Lerp(Color3.fromRGB(170, 110, 255), 0.45), 2)
				layer(g, StarFx.Textures.BlackHoleCore, 0.6, BLACK, 3)
				hole = { gui = g, discImg = discImg }
				tween(g, 0.8, { Size = UDim2.fromScale(1500, 1500) }, Enum.EasingStyle.Back)
				sound("Rumble", 1)
				sound("Pulse", 0.8, 0.8)
				ring(holeAt, Color3.fromRGB(170, 110, 255), 100, 900, 1.0, 0.2)
			end
			local h = hole
			if h then
				local a = math.clamp((t - tCapture) / T_ORBIT, 0, 1)
				h.discImg.Rotation = (h.discImg.Rotation + dt * (60 + 600 * a * a)) % 360
				if t < tMerge then shake = 0.3 + 1.6 * a end
			end
			if t >= tMerge - 0.35 then
				once("suck", function() sound("Suck", 1) end)
			end
			if t >= tMerge and not big then
				-- the stars merge: the black hole collapses, the big star is born
				if h then
					tween(h.gui, 0.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				end
				-- rays behind, glow, the flare on top
				local g, raysImg = StarFx.Billboard(StarFx.Textures.Rays, holeAt, 1, tierColor, fxFolder)
				raysImg.ImageTransparency = 0.3
				layer(g, StarFx.Textures.Glow, 0.43, tierColor:Lerp(WHITE, 0.2), 2)
				local flareImg = layer(g, StarFx.Textures.Flare, 0.7, tierColor:Lerp(WHITE, 0.55), 3)
				big = { gui = g, flareImg = flareImg, raysImg = raysImg }
				white.BackgroundTransparency = 0.15
				tween(white, 0.5, { BackgroundTransparency = 1 })
				ring(holeAt, WHITE, 50, 700, 0.7)
				sound("Boom", 1)
				shake = 1.2
			end
			local b = big
			if b then
				local s = t - (tMerge + 0.25)
				local size = 260
				if s >= 0 then
					local k = math.floor(s / T_PULSE) + 1
					local ph = (s % T_PULSE) / T_PULSE
					if k <= 5 then
						size = 260 * (1 + (0.28 + 0.07 * k) * math.sin(math.pi * ph) ^ 2)
						if ph >= 0.45 and pulsesDone < k then
							pulsesDone = k
							local prism = { tierColor, Color3.fromRGB(255, 150, 220), Color3.fromRGB(140, 220, 255), tierColor, WHITE }
							ring(holeAt, prism[k], 80, 600 + 110 * k, 0.75)
							white.BackgroundTransparency = 0.8 - 0.09 * k
							tween(white, 0.35, { BackgroundTransparency = 1 })
							sound("Boom", 0.5 + 0.1 * k, 1.15 - 0.04 * k)
							shake = 1 + 0.5 * k
						end
					else
						-- the final light: fills the screen
						local u = math.clamp((t - tFinal) / 0.55, 0, 1)
						size = 260 * (1 + 9 * u * u)
						white.BackgroundTransparency = 1 - u
						shake = 3
					end
				else
					size = 260 * smooth((t - tMerge) / 0.25)
				end
				b.gui.Size = UDim2.fromScale(size * 3, size * 3)
				b.flareImg.Rotation = (b.flareImg.Rotation + dt * 25) % 360
				b.raysImg.Rotation = (b.raysImg.Rotation - dt * 12) % 360
			end
		end
		shake = math.max(0, shake - dt * 1.5)
	end

	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 2, function()
		local ok, err = pcall(frame)
		if not ok then
			warn("[SummonCutscene] " .. tostring(err))
			skipped = true
		end
	end)

	-- ---------- 1./2. the chest strains, then bursts open ----------
	tween(fade, 0.3, { BackgroundTransparency = 1 })
	local function waitUntil(at: number)
		while now() < at and not skipped do task.wait() end
	end
	if haveChest then
		task.spawn(function()
			for i = 1, 4 do
				if skipped or now() > T_STRAIN then break end
				sound("Rattle", 0.6 + 0.12 * i, 0.95 + 0.05 * i)
				ChestController.React("Pulse", tierColor:Lerp(WHITE, 0.6), 0.4 + 0.2 * i)
				task.wait(0.36)
			end
		end)
	end
	waitUntil(T_STRAIN)
	if not skipped then
		ChestController.Strain(0)
		if haveChest then ChestController.Open(Color3.fromRGB(200, 222, 255), 4, 1.4, 1, nil) end
		white.BackgroundTransparency = 0.35
		tween(white, 0.45, { BackgroundTransparency = 1 })
		sound("Boom", 0.8)
		-- a light shooting up out of the chest
		local _, _, beamPart = StarFx.Billboard(StarFx.Textures.Glow, anchor, 20, Color3.fromRGB(200, 225, 255), fxFolder)
		local up = make("Beam", {
			FaceCamera = true, LightEmission = 1, LightInfluence = 0, Brightness = 4, Width0 = 6, Width1 = 2,
			Color = ColorSequence.new(Color3.fromRGB(220, 235, 255)), Texture = StarFx.Textures.Streak,
			TextureMode = Enum.TextureMode.Stretch, Transparency = NumberSequence.new(0.1),
		}, beamPart)
		local a0 = make("Attachment", {}, beamPart)
		local a1 = make("Attachment", { Position = Vector3.new(0, 900, 0) }, beamPart)
		up.Attachment0 = a0
		up.Attachment1 = a1
		-- gone before the stars come
		task.spawn(function()
			for k = 1, 12 do
				task.wait(0.07)
				up.Transparency = NumberSequence.new(0.1 + 0.075 * k)
			end
			beamPart:Destroy()
		end)
		task.delay(0.15, function() sound("Whip", 1) end)
	end
	phase("stars")
	waitUntil(T_SHOOT)
	if not skipped then sound("Shoot", if n > 1 then 1.2 else 0.9) end

	-- ---------- 3. the stars play until the light covers the screen ----------
	waitUntil(tEnd)
	if not skipped then
		white.BackgroundTransparency = 0
		white.BackgroundColor3 = WHITE
		task.wait(0.12)
	else
		-- skip: a quick white cut into the reveals
		white.BackgroundTransparency = 0
		white.BackgroundColor3 = WHITE
	end
	skipped = false -- the skip button now skips the reveals

	-- behind the white: put the world back
	RunService:UnbindFromRenderStep(CAMERA_STEP)
	fxFolder:ClearAllChildren()
	ChestController.Strain(0)
	restoreCamera()
	restoreBody()

	-- ---------- 4. the reveals ----------
	white.BackgroundTransparency = 1
	tint.ImageTransparency = 1
	runReveals(gui, rares, skip, skipLabel, function() return skipped end)

	-- ---------- back to the game ----------
	phase(nil)
	skip.Visible = false
	tween(fade, 0.25, { BackgroundTransparency = 0 }).Completed:Wait()
	undo()
	-- the results come up under the black, which then fades away
	for _, c in gui:GetChildren() do
		if c ~= fade then c:Destroy() end
	end
	task.spawn(function()
		tween(fade, 0.35, { BackgroundTransparency = 1 }).Completed:Wait()
		gui:Destroy()
	end)
	local _ = preview
end

-- Plays the cutscene + the reveals for a summon's results and returns when
-- they're over (the moment the results screen should come up). Does nothing
-- if one is already playing, nothing is Legendary+, or the player turned
-- the cutscene off in Settings.
function SummonCutscene.Play(results: {Result}, preview: boolean?)
	if playing or not SummonCutscene.Enabled() then return end
	local any = false
	for _, r in results do
		if SummonCutscene.For(r.rarity) then any = true break end
	end
	if not any then return end
	playing = true
	local state: State = { gui = nil, cleanups = {} }
	local function undo()
		local list = state.cleanups
		state.cleanups = {}
		for i = #list, 1, -1 do
			local ok, err = pcall(list[i])
			if not ok then warn("[SummonCutscene] restore failed: " .. tostring(err)) end
		end
	end
	local ok, err = pcall(run, results, preview == true, state, undo)
	if not ok then
		warn("[SummonCutscene] " .. tostring(err))
		RunService:UnbindFromRenderStep(CAMERA_STEP)
		undo()
		if state.gui then state.gui:Destroy() end
	end
	playing = false
end

return SummonCutscene
