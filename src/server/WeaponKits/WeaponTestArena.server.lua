--!strict
-- WeaponTestArena
-- Location: ServerScriptService.WeaponKits.WeaponTestArena (Script) -- STUDIO ONLY (does nothing live)
-- A training ground for the signature weapons, built at runtime high above the map:
--   * a dark floor with a 10-stud grid and distance marks (range checks),
--   * 12 training dummies at 12 / 25 / 40 / 55 studs: they never die (heal back at 50%), never
--     move or attack, count as enemies for every kit (tag DungeonEnemy, in the run's arena
--     folder) and show their DPS / last hit / total over their heads,
--   * real tower enemies on demand (AI, aggro, attacks -- for summons, i-frames, decoys),
--   * control pillars (ProximityPrompts): spawn attackers, clear, next signature weapon,
--     reset cooldowns, heal, day/night, leave.
-- Entering starts a RunRegistry run of mode "test" (player attribute InRun = "test"), so gates,
-- auto-attacks, skills and ultimates all work exactly like in a gamemode.
-- Entry: the "Weapon Test Arena" portal next to the lobby spawn, or from the Studio command bar /
-- MCP: workspace:SetAttribute("WeaponTestCommand", "<cmd>#<anything unique>") on the server,
--   cmd = enter | leave | attackers:<n>[:<floor>[:<hpMult>]] | clear | equip:<gearId> | next | reset | heal | night | reloadkits
--         | strip (unequip every slot except the weapon)

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local RunRegistry = require(ServerScriptService.DungeonSystem:WaitForChild("RunRegistry"))
local EnemyController = require(ServerScriptService.DungeonSystem:WaitForChild("EnemyController"))
local InventoryManager = require(ServerScriptService.GearSystem:WaitForChild("InventoryManager"))
local GearRegistry = require(ReplicatedStorage.GearSystem.GearRegistry)
local TowerRegistry = require(ReplicatedStorage.DungeonSystem.TowerRegistry)
local TowerConfig = require(ReplicatedStorage:FindFirstChild("TowerConfig", true) :: ModuleScript)
local ServiceRegistry = require(ServerScriptService.ServiceRegistry)

local ORIGIN = Vector3.new(0, 1800, 6000) -- floor top centre
local SIZE = 170
local WALL_H = 36 -- corner pillars: the "roof" height for field-wide effects (Red Rain)
local SPAWN = ORIGIN + Vector3.new(0, 3.5, 55)
local DUMMY_HP = 1e9
local TAG = EnemyController.GetTag()

local arena: Model? = nil
local enemiesFolder: Folder? = nil
local runs: {[Player]: any} = {}
local returnTo: {[Player]: CFrame} = {}

-- ===================================================================== building
local function part(props: {[string]: any}, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function label(adornee: Instance, text: string, size: number, color: Color3, offset: Vector3?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, size * 4)
	gui.StudsOffsetWorldSpace = offset or Vector3.new(0, 3, 0)
	gui.MaxDistance = if size <= 13 then 45 else 220
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = adornee
	gui.Parent = adornee
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.TextWrapped = true
	t.Parent = gui
	return t
end

-- ----- training dummy -----
local function makeDummy(at: Vector3, index: number, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "TrainingDummy_" .. index
	local root = part({ Name = "HumanoidRootPart", Size = Vector3.new(2.4, 5, 2.4), Transparency = 1, CanCollide = false,
		CFrame = CFrame.lookAt(at + Vector3.new(0, 2.5, 0), SPAWN * Vector3.new(1, 0, 1) + Vector3.new(0, at.Y + 2.5, 0)) }, m)
	local base = root.CFrame
	part({ Name = "Stand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3, 3), Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 60, 66), CFrame = base * CFrame.new(0, -2.3, 0) * CFrame.Angles(0, 0, math.rad(90)) }, m)
	part({ Name = "Post", Size = Vector3.new(0.4, 1.4, 0.4), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 50),
		CFrame = base * CFrame.new(0, -1.5, 0) }, m)
	part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 2.2, 2.2), Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(196, 160, 104), CFrame = base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)) }, m)
	part({ Name = "Arms", Size = Vector3.new(4.4, 0.5, 0.5), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 50),
		CFrame = base * CFrame.new(0, 1.4, 0) }, m)
	local head = part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.7, 1.7), Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(205, 170, 115), CFrame = base * CFrame.new(0, 2.9, 0) }, m)
	part({ Name = "Target", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 1.3, 1.3), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(230, 60, 60), CFrame = base * CFrame.new(0, 0.7, -1.12) * CFrame.Angles(0, math.rad(90), 0) }, m)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			p.CanCollide = p.Name == "Stand"
			p.CanQuery = p.Name == "HumanoidRootPart" or p.Name == "Body"
		end
	end
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = DUMMY_HP
	hum.Health = DUMMY_HP
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = m
	m.PrimaryPart = root
	m:SetAttribute("BaseWalkSpeed", 0)
	m:SetAttribute("TrainingDummy", true)
	local dist = (Vector3.new(at.X, 0, at.Z) - Vector3.new(SPAWN.X, 0, SPAWN.Z)).Magnitude
	local text = label(head, "DUMMY " .. index .. "  (" .. math.floor(dist + 0.5) .. " st)\nDPS 0", 13, Color3.fromRGB(255, 240, 210), Vector3.new(0, 2.4, 0))
	m.Parent = parent
	CollectionService:AddTag(m, TAG)

	-- DPS meter + heal-back
	local hits: {{t: number, d: number}} = {}
	local total, lastHit, last = 0, 0, hum.Health
	hum.HealthChanged:Connect(function(h)
		if h < last then
			local d = last - h
			total += d
			lastHit = d
			table.insert(hits, { t = os.clock(), d = d })
		end
		last = h
	end)
	task.spawn(function()
		while m.Parent do
			task.wait(0.25)
			local now = os.clock()
			while hits[1] and now - hits[1].t > 4 do table.remove(hits, 1) end
			local sum = 0
			for _, h in hits do sum += h.d end
			local span = if hits[1] then math.max(1, math.min(4, now - hits[1].t + 0.25)) else 4
			local dps = if #hits > 0 then sum / span else 0
			text.Text = ("DUMMY %d  (%d st)\nDPS %s  |  hit %s\ntotal %s"):format(index, math.floor(dist + 0.5),
				string.format("%.0f", dps), string.format("%.0f", lastHit), string.format("%.0f", total))
			if hum.Health < DUMMY_HP * 0.5 or hum.Health <= 0 then
				hum.Health = DUMMY_HP
				last = DUMMY_HP
			end
			if not root.Anchored then root.Anchored = true end
		end
	end)
	return m
end

-- ----- control pillars -----
local controls: {[string]: ProximityPrompt} = {}
local handlers: {[string]: (Player) -> ()} = {}

local function pillar(name: string, action: string, at: Vector3, color: Color3, parent: Instance)
	local p = part({ Name = "Control_" .. name, Size = Vector3.new(2.4, 4, 2.4), Material = Enum.Material.Neon, Color = color,
		Transparency = 0.15, CFrame = CFrame.new(at + Vector3.new(0, 2, 0)), CanCollide = true }, parent)
	label(p, action, 16, Color3.new(1, 1, 1), Vector3.new(0, 3.6, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = "Weapon Test"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	controls[name] = prompt
	prompt.Triggered:Connect(function(player)
		local fn = handlers[name]
		if fn then
			local ok, err = pcall(fn, player)
			if not ok then warn("[WeaponTest] " .. name .. ": " .. tostring(err)) end
		end
	end)
end

local function build()
	if arena and arena.Parent then return end
	local m = Instance.new("Model")
	m.Name = "WeaponTestArena"
	local floor = part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), Material = Enum.Material.Slate,
		Color = Color3.fromRGB(34, 33, 40), CFrame = CFrame.new(ORIGIN - Vector3.new(0, 1, 0)) }, m)
	-- 10-stud grid, brighter every 50
	for i = -SIZE / 2 + 10, SIZE / 2 - 10, 10 do
		local major = i % 50 == 0
		local c = if major then Color3.fromRGB(110, 95, 150) else Color3.fromRGB(62, 56, 82)
		part({ Name = "GridX", Size = Vector3.new(SIZE, 0.05, if major then 0.25 else 0.12), Material = Enum.Material.Neon, Color = c,
			Transparency = 0.35, CanCollide = false, CanQuery = false, CFrame = CFrame.new(ORIGIN + Vector3.new(0, 0.03, i)) }, m)
		part({ Name = "GridZ", Size = Vector3.new(if major then 0.25 else 0.12, 0.05, SIZE), Material = Enum.Material.Neon, Color = c,
			Transparency = 0.35, CanCollide = false, CanQuery = false, CFrame = CFrame.new(ORIGIN + Vector3.new(i, 0.03, 0)) }, m)
	end
	-- distance marks from the spawn (north = -Z)
	for _, d in { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 } do
		local at = Vector3.new(SPAWN.X - 12, ORIGIN.Y, SPAWN.Z - d)
		if at.Z > ORIGIN.Z - SIZE / 2 then
			local mark = part({ Name = "Mark" .. d, Size = Vector3.new(3, 0.1, 0.4), Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 200, 80), CanCollide = false, CanQuery = false, CFrame = CFrame.new(at + Vector3.new(0, 0.06, 0)) }, m)
			label(mark, d .. " st", 14, Color3.fromRGB(255, 220, 140), Vector3.new(0, 1.2, 0))
		end
	end
	-- low rim + four tall corner pillars
	for _, s in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local along = if s[1] == 0 then Vector3.new(SIZE, 2, 1) else Vector3.new(1, 2, SIZE)
		part({ Name = "Rim", Size = along, Material = Enum.Material.Slate, Color = Color3.fromRGB(55, 50, 66),
			CFrame = CFrame.new(ORIGIN + Vector3.new(s[1] * SIZE / 2, 1, s[2] * SIZE / 2)) }, m)
	end
	for _, s in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		part({ Name = "Pillar", Size = Vector3.new(4, WALL_H, 4), Material = Enum.Material.Slate, Color = Color3.fromRGB(55, 50, 66),
			CFrame = CFrame.new(ORIGIN + Vector3.new(s[1] * (SIZE / 2 - 2), WALL_H / 2, s[2] * (SIZE / 2 - 2))) }, m)
	end
	part({ Name = "SpawnPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 8, 8), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(90, 200, 255), Transparency = 0.4, CanCollide = false,
		CFrame = CFrame.new(SPAWN.X, ORIGIN.Y + 0.1, SPAWN.Z) * CFrame.Angles(0, 0, math.rad(90)) }, m)

	local enemies = Instance.new("Folder")
	enemies.Name = "Enemies"
	enemies.Parent = m
	-- dummies: 12 in arcs at 12 / 25 / 40 / 55 studs (north of the spawn)
	local layout = { { 12, { -12, 12 } }, { 25, { -30, -10, 10, 30 } }, { 40, { -24, 0, 24 } }, { 55, { -18, 0, 18 } } }
	local n = 0
	for _, row in layout do
		for _, ang in row[2] do
			n += 1
			local a = math.rad(ang)
			local at = Vector3.new(SPAWN.X + math.sin(a) * row[1], ORIGIN.Y, SPAWN.Z - math.cos(a) * row[1])
			makeDummy(at, n, enemies)
		end
	end
	-- control pillars on the west side of the spawn
	local cx, cz = SPAWN.X - 22, SPAWN.Z + 6
	pillar("Attackers", "Spawn 6 attackers", Vector3.new(cx, ORIGIN.Y, cz - 15), Color3.fromRGB(230, 70, 60), m)
	pillar("Clear", "Clear attackers", Vector3.new(cx, ORIGIN.Y, cz - 10), Color3.fromRGB(150, 150, 160), m)
	pillar("Next", "Next signature weapon", Vector3.new(cx, ORIGIN.Y, cz - 5), Color3.fromRGB(255, 190, 60), m)
	pillar("Reset", "Reset cooldowns", Vector3.new(cx, ORIGIN.Y, cz), Color3.fromRGB(80, 200, 255), m)
	pillar("Heal", "Heal me", Vector3.new(cx, ORIGIN.Y, cz + 5), Color3.fromRGB(90, 230, 120), m)
	pillar("Night", "Day / night", Vector3.new(cx, ORIGIN.Y, cz + 10), Color3.fromRGB(140, 110, 255), m)
	pillar("Leave", "Leave arena", Vector3.new(cx, ORIGIN.Y, cz + 15), Color3.fromRGB(255, 255, 255), m)
	m.PrimaryPart = floor
	m.Parent = Workspace
	arena = m
	enemiesFolder = enemies
end

-- ===================================================================== the run
local function inArena(p: Player): boolean
	local run = RunRegistry.GetRun(p)
	return run ~= nil and run == runs[p]
end

local function attackers(): {Model}
	local out = {}
	local f = enemiesFolder
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") and not m:GetAttribute("TrainingDummy") then table.insert(out, m) end
		end
	end
	return out
end

local function clearAttackers()
	for _, m in attackers() do m:Destroy() end
end

local function teleport(p: Player, cf: CFrame)
	pcall(function() p:RequestStreamAroundAsync(cf.Position, 5) end)
	local c = p.Character
	if c then c:PivotTo(cf) end
end

local function enter(p: Player)
	build()
	if inArena(p) then return end
	if RunRegistry.GetRun(p) then
		warn("[WeaponTest] " .. p.Name .. " is in another run -- leave it first")
		return
	end
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then returnTo[p] = root.CFrame end
	local run = RunRegistry.CreateRun({ p }, "test" :: any, enemiesFolder :: Folder, ORIGIN, SIZE / 2)
	runs[p] = run
	teleport(p, CFrame.lookAt(SPAWN, SPAWN + Vector3.new(0, 0, -1)))
	print("[WeaponTest] " .. p.Name .. " entered the arena (InRun = test)")
end

local function leave(p: Player)
	if inArena(p) then RunRegistry.RemovePlayer(p) end
	runs[p] = nil
	local anyone = false
	for _, r in runs do if r then anyone = true end end
	if not anyone then clearAttackers() end
	local back = returnTo[p]
	returnTo[p] = nil
	if back and p.Character then teleport(p, back) end
end

-- hpMult: test attackers are tougher than real ones (default x25) so they live long enough to watch
local function spawnAttackers(p: Player, count: number, floor: number?, hpMult: number?)
	if not inArena(p) then enter(p) end
	local run = runs[p]
	if not run then return end
	local towerId = TowerConfig.TowerId
	local tower = TowerRegistry.Get(towerId)
	local config = TowerRegistry.GetRoomAsDungeonConfig(towerId, floor or 1, 1)
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if root then root.Position else SPAWN
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local pos = Vector3.new(center.X + math.cos(a) * 30, ORIGIN.Y + 3, center.Z + math.sin(a) * 30)
		local id = TowerRegistry.PickNormal(tower)
		local ok, err = pcall(EnemyController.SpawnEnemy, id, 1, config, run, pos, hpMult or 25, 1)
		if not ok then warn("[WeaponTest] spawn " .. tostring(id) .. ": " .. tostring(err)) end
	end
end

-- signature weapons = every kit module's gearId
local function signatureGearIds(): {string}
	local list = {}
	local kits = ServerScriptService:FindFirstChild("WeaponKits")
	local folder = kits and kits:FindFirstChild("Kits")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("ModuleScript") then
				local ok, kit = pcall(require, m)
				if ok and type(kit) == "table" and type(kit.gearId) == "string" then table.insert(list, kit.gearId) end
			end
		end
	end
	table.sort(list)
	return list
end

local function equip(p: Player, gearId: string)
	if not GearRegistry.Get(gearId) then warn("[WeaponTest] unknown gear " .. gearId) return end
	local have = nil
	for _, inst in InventoryManager.GetInventory(p) do
		if inst.gearId == gearId then have = inst break end
	end
	if not have then have = InventoryManager.AddItem(p, gearId, true) end
	if have then InventoryManager.EquipItem(p, have.instanceId) end
	local t = GearRegistry.Get(gearId)
	print("[WeaponTest] equipped " .. gearId .. " (" .. tostring(t and t.name) .. ")")
	local prompt = controls.Next
	if prompt then prompt.ObjectText = "now: " .. tostring(t and t.name or gearId) end
end

-- everything but the weapon off (the gear sets will be remade; test the weapon alone)
local function strip(p: Player)
	for slot, item in InventoryManager.GetEquipped(p) do
		if item and slot ~= "Weapon" then InventoryManager.UnequipItem(p, slot) end
	end
	print("[WeaponTest] unequipped everything but the weapon")
end

local function nextWeapon(p: Player)
	local list = signatureGearIds()
	if #list == 0 then return end
	local cur = InventoryManager.GetEquippedItem(p, "Weapon")
	local i = table.find(list, cur and cur.gearId or "") or 0
	equip(p, list[(i % #list) + 1])
end

local function resetCooldowns(p: Player)
	local combat = ServiceRegistry.Get("Combat")
	if combat and combat.ResetCooldowns then pcall(combat.ResetCooldowns, p) end
	local ok, wks = pcall(require, ServerScriptService.WeaponKits.WeaponKitService)
	if ok and wks.ResetCooldowns then wks.ResetCooldowns(p) end
	-- clear the HUD timers
	local okR, router = pcall(require, ServerScriptService.Progression.RemoteRouter)
	if okR then
		for _, slot in { 1, 2, 3, "U" } do router.Push(p, "Cooldown", { slot = slot, duration = 0 }) end
	end
end

local function heal(p: Player)
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = hum.MaxHealth end
end

-- Dev hot reload of the server kits during a play test: push new Source into the Kits modules
-- (execute_luau on the Server DM), then send "reloadkits". Each module is re-instanced + required
-- here (this script's threads live on), and WeaponKitService.KitFor serves the fresh tables.
-- Client effects reload by themselves: replace ReplicatedStorage.WeaponKits.Fx.<Kit> with a
-- clone carrying the new Source (WeaponFxClient registers modules on ChildAdded).
local function reloadKits()
	local WKS = require(ServerScriptService.WeaponKits.WeaponKitService)
	local fresh = {}
	local n = 0
	for _, m in ServerScriptService.WeaponKits.Kits:GetChildren() do
		if m:IsA("ModuleScript") then
			local c = m:Clone()
			c.Parent = m.Parent
			m:Destroy()
			local ok, kit = pcall(require, c)
			if ok and type(kit) == "table" and kit.gearId then
				fresh[kit.gearId] = kit
				n += 1
			else
				warn("[WeaponTest] reload " .. c.Name .. ": " .. tostring(kit))
			end
		end
	end
	local orig = (WKS :: any)._origKitFor or WKS.KitFor
	;(WKS :: any)._origKitFor = orig
	WKS.KitFor = function(player)
		local kit, template = orig(player)
		if template and fresh[template.id] then return fresh[template.id], template end
		return kit, template
	end
	print("[WeaponTest] reloaded " .. n .. " kits")
end

local savedClock: number? = nil
local function night()
	if savedClock then
		Lighting.ClockTime = savedClock
		savedClock = nil
	else
		savedClock = Lighting.ClockTime
		Lighting.ClockTime = 0
	end
end

handlers.Attackers = function(p) spawnAttackers(p, 6) end
handlers.Clear = function(_) clearAttackers() end
handlers.Next = nextWeapon
handlers.Reset = resetCooldowns
handlers.Heal = heal
handlers.Night = function(_) night() end
handlers.Leave = leave

-- ===================================================================== entry portal (lobby)
local function buildPortal()
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local at = if spawn then spawn.Position + Vector3.new(10, 0, 0) else Vector3.new(0, 10, 0)
	local p = part({ Name = "WeaponTestPortal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 6, 6),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(90, 200, 255), Transparency = 0.3, CanCollide = false,
		CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Workspace)
	label(p, "WEAPON TEST ARENA\n(Studio only)", 16, Color3.fromRGB(150, 230, 255), Vector3.new(0, 4, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter Weapon Test Arena"
	prompt.ObjectText = "Studio"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(enter, player)
		if not ok then warn("[WeaponTest] enter: " .. tostring(err)) end
	end)
end

-- ===================================================================== commands (MCP / command bar)
Workspace:GetAttributeChangedSignal("WeaponTestCommand"):Connect(function()
	local raw = Workspace:GetAttribute("WeaponTestCommand")
	if type(raw) ~= "string" then return end
	local cmd = raw:match("^([^#]+)") or raw
	local p = Players:GetPlayers()[1]
	if not p then return end
	local parts = string.split(cmd, ":")
	local ok, err = pcall(function()
		if parts[1] == "enter" then enter(p)
		elseif parts[1] == "leave" then leave(p)
		elseif parts[1] == "attackers" then spawnAttackers(p, tonumber(parts[2]) or 6, tonumber(parts[3]), tonumber(parts[4]))
		elseif parts[1] == "clear" then clearAttackers()
		elseif parts[1] == "equip" and parts[2] then equip(p, parts[2])
		elseif parts[1] == "strip" then strip(p)
		elseif parts[1] == "next" then nextWeapon(p)
		elseif parts[1] == "reset" then resetCooldowns(p)
		elseif parts[1] == "heal" then heal(p)
		elseif parts[1] == "night" then night()
		elseif parts[1] == "reloadkits" then reloadKits()
		else warn("[WeaponTest] unknown command " .. cmd) end
	end)
	Workspace:SetAttribute("WeaponTestResult", (if ok then "ok " else "ERR " .. tostring(err) .. " ") .. raw)
end)

-- falling off / dying in the arena
RunService.Heartbeat:Connect(function()
	for p, run in runs do
		if run then
			local c = p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < ORIGIN.Y - 60 then
				root.AssemblyLinearVelocity = Vector3.zero
				c:PivotTo(CFrame.lookAt(SPAWN, SPAWN + Vector3.new(0, 0, -1)))
			end
		end
	end
end)
local function watch(p: Player)
	p.CharacterAdded:Connect(function(c)
		local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				if inArena(p) then
					RunRegistry.RemovePlayer(p)
					runs[p] = nil
					returnTo[p] = nil
				end
			end)
		end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do watch(p) end
Players.PlayerRemoving:Connect(function(p)
	if inArena(p) then RunRegistry.RemovePlayer(p) end
	runs[p] = nil
	returnTo[p] = nil
end)

buildPortal()
print("[WeaponTest] ready -- portal next to the lobby spawn, or workspace:SetAttribute(\"WeaponTestCommand\", \"enter#1\")")
