--!strict
-- WeaponFxClient
-- Location: StarterPlayer.StarterPlayerScripts.WeaponFxClient (LocalScript)
-- Draws the signature weapons' effects. The server kits (ServerScriptService.WeaponKits)
-- push "WFx" {kit, kind, caster, ...} to every player of the run; each push goes to the
-- module in ReplicatedStorage.WeaponKits.Fx whose `id` is `kit`, function `kind`(data, env)
--   env = { caster: Player?, character: Model?, root: BasePart?, mine: boolean }
-- Settings: Other Players' Effects off -> only your own; Ability Effects off -> only what
-- a module lists in `Always` (e.g. the stat you just got).
-- The caster's own client also plays the kit's animations (they replicate from there),
-- including the carry: Anims.<Kit>.Hold loops while you move holding a weapon whose model
-- names its animation set in the "AnimKit" attribute, and Anims.<Kit>.Idle (its own stance)
-- while you stand still.
-- Presence: for every character holding such a weapon, the Fx module with that AnimKit draws
-- its always-on look (Presence(character, model, env) -> cleanup; env.far when the camera is
-- far away) and, when the weapon is newly equipped, its equip flourish (Equip).
-- Studio only: animations not published yet (empty AnimationId) play straight from their
-- KeyframeSequences in ReplicatedStorage.WeaponKits.AnimSources.<Kit> (attribute "Anim" = the
-- Animation's name), so play tests show them.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PC = require(ReplicatedStorage:WaitForChild("Progression"):WaitForChild("ProgressionClient"))
local SettingsConfig = require(ReplicatedStorage:WaitForChild("SettingsConfig"))
local WeaponKits = ReplicatedStorage:WaitForChild("WeaponKits")
local FxUtil = require(WeaponKits:WaitForChild("FxUtil"))
local FxFolder = WeaponKits:WaitForChild("Fx")

local player = Players.LocalPlayer

if RunService:IsStudio() then
	local sources = WeaponKits:FindFirstChild("AnimSources")
	local anims = WeaponKits:FindFirstChild("Anims")
	if sources and anims then
		for _, kitFolder in sources:GetChildren() do
			local target = anims:FindFirstChild(kitFolder.Name)
			for _, kfs in kitFolder:GetChildren() do
				local name = kfs:GetAttribute("Anim")
				local a = target and target:FindFirstChild(if type(name) == "string" then name else kfs.Name)
				if a and a:IsA("Animation") and a.AnimationId == "" and kfs:IsA("KeyframeSequence") then
					local ok, id = pcall(function() return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs) end)
					if ok and type(id) == "string" then a.AnimationId = id end
				end
			end
		end
	end
end

-- ===== carry / idle stance =====
local current: {kit: string?, char: Model?, hold: AnimationTrack?, idle: AnimationTrack?} = {}
local function stopTrack(t: AnimationTrack?, fade: number)
	if t and t.IsPlaying then t:Stop(fade) end
end
local function refreshHold()
	local character = player.Character
	local model = FxUtil.Weapon(character)
	local attr = model and model:GetAttribute("AnimKit")
	local kit: string? = if type(attr) == "string" then attr else nil
	if kit ~= current.kit or character ~= current.char then
		stopTrack(current.hold, 0.25)
		stopTrack(current.idle, 0.25)
		current = { kit = kit, char = character }
	end
	if not kit or not character then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local moving = hum.MoveDirection.Magnitude > 0.1 or hum.FloorMaterial == Enum.Material.Air
	local hasIdle = FxUtil.Animation(kit, "Idle") ~= nil
	if moving or not hasIdle then
		stopTrack(current.idle, 0.2)
		if not (current.hold and current.hold.IsPlaying) then
			current.hold = FxUtil.PlayAnim(kit, "Hold", { fade = 0.25, priority = Enum.AnimationPriority.Movement })
		end
	else
		stopTrack(current.hold, 0.3)
		if not (current.idle and current.idle.IsPlaying) then
			current.idle = FxUtil.PlayAnim(kit, "Idle", { fade = 0.35, priority = Enum.AnimationPriority.Movement })
		end
	end
end
task.spawn(function()
	while true do
		pcall(refreshHold)
		task.wait(0.15)
	end
end)

-- ===== effects =====
local modules: {[string]: any} = {}
local byAnimKit: {[string]: any} = {}

local function register(m: Instance)
	if not m:IsA("ModuleScript") then return end
	local ok, mod = pcall(require, m)
	if not ok then
		warn("[WeaponFx] " .. m.Name .. ": " .. tostring(mod))
	elseif type(mod) == "table" and type(mod.id) == "string" then
		modules[mod.id] = mod
		if type(mod.AnimKit) == "string" then byAnimKit[mod.AnimKit] = mod end
	end
end
for _, m in FxFolder:GetChildren() do task.spawn(register, m) end
FxFolder.ChildAdded:Connect(register)

-- (PC.On can wait for the remotes: its own thread, so the presence loop below still starts)
task.spawn(PC.On, "WFx", function(data: any)
	if type(data) ~= "table" or type(data.kit) ~= "string" or type(data.kind) ~= "string" then return end
	local mod = modules[data.kit]
	local fn = mod and mod[data.kind]
	if type(fn) ~= "function" then return end
	local mine = data.caster == player.UserId
	if not mine and SettingsConfig.Get(player, "OthersFx") == false then return end
	local always = type(mod.Always) == "table" and mod.Always[data.kind] == true
	if not always and SettingsConfig.Get(player, "AbilityFx") == false then return end
	local caster = if type(data.caster) == "number" then Players:GetPlayerByUserId(data.caster) else nil
	local character = caster and caster.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local env = {
		caster = caster,
		character = character,
		root = if root and root:IsA("BasePart") then root else nil,
		mine = mine,
	}
	local ok, err = pcall(fn, data, env)
	if not ok then warn(("[WeaponFx] %s.%s: %s"):format(data.kit, data.kind, tostring(err))) end
end)

-- ===== presence + equip flourish =====
local FAR = 90 -- studs from the camera: beyond this the small particles are skipped
type Active = { model: Model, stop: () -> (), env: {[string]: any} }
local active: {[Model]: Active} = {}
local lastModel: {[Model]: Model} = setmetatable({}, { __mode = "k" }) :: any
local firstSeen: {[Model]: number} = setmetatable({}, { __mode = "k" }) :: any

local function stopActive(c: Model)
	local a = active[c]
	active[c] = nil
	if a then pcall(a.stop) end
end

local function refreshPresence()
	local seen: {[Model]: boolean} = {}
	local othersOn = SettingsConfig.Get(player, "OthersFx") ~= false
	local cam = workspace.CurrentCamera
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and c.Parent then
			seen[c] = true
			firstSeen[c] = firstSeen[c] or os.clock()
			local model = FxUtil.Weapon(c)
			local attr = model and model:GetAttribute("AnimKit")
			local mod = if type(attr) == "string" then byAnimKit[attr] else nil
			local mine = p == player
			local allowed = mine or othersOn
			local a = active[c]
			if a and (a.model ~= model or not mod or not allowed or not a.model.Parent) then
				stopActive(c)
				a = nil
			end
			if not a and model and mod and allowed and type(mod.Presence) == "function" then
				local env = { caster = p, character = c, mine = mine, far = false }
				local ok, stop = pcall(mod.Presence, c, model, env)
				if not ok then warn("[WeaponFx] presence: " .. tostring(stop)) end
				active[c] = { model = model, stop = if ok and type(stop) == "function" then stop else function() end, env = env }
				-- equip flourish: a new weapon on a character that was already there (not a respawn)
				if lastModel[c] ~= model and os.clock() - firstSeen[c] > 2 and type(mod.Equip) == "function" then
					local ok2, err = pcall(mod.Equip, c, model, env)
					if not ok2 then warn("[WeaponFx] equip: " .. tostring(err)) end
				end
				a = active[c]
			end
			if model then lastModel[c] = model end
			local root = c:FindFirstChild("HumanoidRootPart")
			if a and root and root:IsA("BasePart") and cam then
				a.env.far = (cam.CFrame.Position - root.Position).Magnitude > FAR
			end
		end
	end
	for c in active do
		if not seen[c] then stopActive(c) end
	end
end
task.spawn(function()
	while true do
		local ok, err = pcall(refreshPresence)
		if not ok then warn("[WeaponFx] " .. tostring(err)) end
		task.wait(0.3)
	end
end)
