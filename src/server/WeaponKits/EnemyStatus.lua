--!strict
-- EnemyStatus
-- Location: ServerScriptService.WeaponKits.EnemyStatus (ModuleScript)
-- Status effects weapon kits put on enemies. EnemyController's AI loop asks
-- IsFrozen() every tick and walk speed goes through Apply(), so slows land at
-- once instead of on the next AI tick:
--   Freeze(model, seconds)         can't move or attack, still takes damage
--   Slow(model, id, pct, seconds)  -pct% movement speed; the strongest active slow
--                                  wins and the same id refreshes (no stacking)
--   FreezeRun(run, seconds)        every enemy of a run, including ones that spawn
--                                  while it lasts (ultimate cutscenes)
--   SlowRun(run, id, pct, seconds) the same for a field-wide slow
-- A frozen enemy's animations are paused here on the server (the tracks are
-- played by the server, so the pause replicates to everyone). Model attributes
-- mirror the state for the clients: Frozen, Slowed. The walk speed an enemy has
-- without any status is its "BaseWalkSpeed" attribute (set by EnemyController).

local EnemyStatus = {}

type SlowEntry = { pct: number, untilT: number }
type State = { frozenUntil: number, slows: {[string]: SlowEntry} }
local states: {[Model]: State} = setmetatable({}, { __mode = "k" }) :: any

local function state(model: Model): State
	local s = states[model]
	if not s then
		s = { frozenUntil = 0, slows = {} }
		states[model] = s
	end
	return s
end

-- speed each paused track had, to resume it when the freeze ends
local pausedSpeed: {[AnimationTrack]: number} = setmetatable({}, { __mode = "k" }) :: any

local function animatorOf(model: Model): Animator?
	local visual = model:FindFirstChild("Visual")
	local controller = visual and visual:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if animator then return animator end
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

local function pauseAnimations(model: Model, paused: boolean)
	local animator = animatorOf(model)
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do
		if paused then
			if pausedSpeed[track] == nil then
				pausedSpeed[track] = track.Speed
				track:AdjustSpeed(0)
			end
		elseif pausedSpeed[track] ~= nil then
			track:AdjustSpeed(pausedSpeed[track])
			pausedSpeed[track] = nil
		end
	end
end

local function living(model: Model): (Humanoid?, BasePart?)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if hum and root and hum.Health > 0 then return hum, root end
	return nil, nil
end

function EnemyStatus.IsFrozen(model: Model): boolean
	local s = states[model]
	return s ~= nil and s.frozenUntil > os.clock()
end

-- 0 while frozen, else 1 minus the strongest active slow.
function EnemyStatus.SpeedMultiplier(model: Model): number
	local s = states[model]
	if not s then return 1 end
	local now = os.clock()
	if s.frozenUntil > now then return 0 end
	local worst = 0
	for id, sl in s.slows do
		if sl.untilT > now then worst = math.max(worst, sl.pct) else s.slows[id] = nil end
	end
	return math.max(0, 1 - worst / 100)
end

-- Re-applies walk speed + anchoring from the current state.
function EnemyStatus.Apply(model: Model)
	local hum, root = living(model)
	if not hum or not root then return end
	local frozen = EnemyStatus.IsFrozen(model)
	local wasFrozen = model:GetAttribute("Frozen") == true
	local mult = EnemyStatus.SpeedMultiplier(model)
	local base = model:GetAttribute("BaseWalkSpeed")
	if type(base) == "number" then hum.WalkSpeed = base * mult end
	if frozen then
		if not root.Anchored then
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			model:SetAttribute("StatusAnchored", true)
		end
		hum:MoveTo(root.Position)
	elseif model:GetAttribute("StatusAnchored") then
		model:SetAttribute("StatusAnchored", nil)
		root.Anchored = false
	end
	if frozen then
		pauseAnimations(model, true)
	elseif wasFrozen then
		pauseAnimations(model, false)
	end
	model:SetAttribute("Frozen", if frozen then true else nil)
	model:SetAttribute("Slowed", if (not frozen and mult < 1) then true else nil)
end

function EnemyStatus.Freeze(model: Model, seconds: number)
	if not living(model) or seconds <= 0 then return end
	local s = state(model)
	s.frozenUntil = math.max(s.frozenUntil, os.clock() + seconds)
	EnemyStatus.Apply(model)
	task.delay(seconds + 0.03, function() EnemyStatus.Apply(model) end)
end

function EnemyStatus.Unfreeze(model: Model)
	local s = states[model]
	if s then s.frozenUntil = 0 end
	EnemyStatus.Apply(model)
end

function EnemyStatus.Slow(model: Model, id: string, pct: number, seconds: number)
	if not living(model) or seconds <= 0 then return end
	state(model).slows[id] = { pct = math.clamp(pct, 0, 100), untilT = os.clock() + seconds }
	EnemyStatus.Apply(model)
	task.delay(seconds + 0.03, function() EnemyStatus.Apply(model) end)
end

-- Runs `fn(model, secondsLeft)` on every enemy of the run now and on every one
-- that spawns before `seconds` are up.
local function forRun(run: any, seconds: number, fn: (Model, number) -> ())
	local untilT = os.clock() + seconds
	for _, m in run.arenaFolder:GetChildren() do
		if m:IsA("Model") then fn(m, seconds) end
	end
	local conn: RBXScriptConnection
	conn = run.arenaFolder.ChildAdded:Connect(function(m)
		local left = untilT - os.clock()
		if left <= 0 then conn:Disconnect() return end
		if m:IsA("Model") then task.defer(function() fn(m, untilT - os.clock()) end) end
	end)
	task.delay(seconds + 0.05, function() if conn.Connected then conn:Disconnect() end end)
end

function EnemyStatus.FreezeRun(run: any, seconds: number)
	forRun(run, seconds, EnemyStatus.Freeze)
end

function EnemyStatus.SlowRun(run: any, id: string, pct: number, seconds: number)
	forRun(run, seconds, function(m, left) EnemyStatus.Slow(m, id, pct, left) end)
end

return EnemyStatus
