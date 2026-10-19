--!strict
-- HitComboClient
-- Location: StarterPlayer.StarterPlayerScripts.HitComboClient (LocalScript)
-- Hit-combo counter (every weapon): each hit you land (the server's damage-number batches,
-- DungeonSystem.Remotes.DamageNumbers, events with u = your UserId) adds to the count; it pops on
-- every hit, a bar under it drains while you're not hitting, and the chain ends when it runs out.
-- Rank words climb with the count: COMBO -> GREAT -> INSANE -> COMBO GOD. Total damage of the
-- chain underneath. Hidden while the count is 0.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remote = ReplicatedStorage:WaitForChild("DungeonSystem"):WaitForChild("Remotes"):WaitForChild("DamageNumbers") :: RemoteEvent
local okTheme, UITheme = pcall(require, ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer

local WINDOW = 5 -- seconds without a hit before the chain ends
local RANKS = {
	{ at = 1, word = "COMBO", color = Color3.fromRGB(150, 225, 255), glow = Color3.fromRGB(40, 120, 255) },
	{ at = 30, word = "GREAT", color = Color3.fromRGB(255, 215, 90), glow = Color3.fromRGB(255, 140, 0) },
	{ at = 80, word = "INSANE", color = Color3.fromRGB(255, 120, 70), glow = Color3.fromRGB(230, 20, 40) },
	{ at = 150, word = "COMBO GOD", color = Color3.fromRGB(255, 120, 245), glow = Color3.fromRGB(150, 40, 255) },
}
local HEADING = if okTheme and UITheme.FontFaces and UITheme.FontFaces.Heading then UITheme.FontFaces.Heading
	else Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Black)
local function italic(f: Font): Font
	return Font.new(f.Family, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
end

-- ===== ui =====
local gui = Instance.new("ScreenGui")
gui.Name = "HitCombo"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(1, 0.5)
holder.Position = UDim2.new(1, -120, 0.45, 0) -- left of the lobby's Store / Battlepass column
holder.Size = UDim2.fromOffset(300, 130)
holder.Rotation = -4
holder.Parent = gui
local holderScale = Instance.new("UIScale")
holderScale.Parent = holder

local function label(name: string, text: string, size: number, pos: UDim2, anchor: Vector2, align: Enum.TextXAlignment): (TextLabel, UIStroke)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = anchor
	l.Position = pos
	l.Size = UDim2.fromOffset(300, size)
	l.FontFace = italic(HEADING)
	l.TextSize = size
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = align
	l.Parent = holder
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = Color3.fromRGB(15, 8, 20)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l, s
end

-- "123" (big) + "HITS" (small, beside it)
local countLabel, countStroke = label("Count", "0", 64, UDim2.new(1, -78, 0, 0), Vector2.new(1, 0), Enum.TextXAlignment.Right)
local countScale = Instance.new("UIScale")
countScale.Parent = countLabel
local countGrad = Instance.new("UIGradient")
countGrad.Rotation = 90
countGrad.Parent = countLabel
local hitsLabel = label("Hits", "HITS", 26, UDim2.new(1, 0, 0, 30), Vector2.new(1, 0), Enum.TextXAlignment.Right)
hitsLabel.Size = UDim2.fromOffset(74, 26)
hitsLabel.TextColor3 = Color3.fromRGB(255, 60, 70)
local rankLabel, rankStroke = label("Rank", "COMBO", 30, UDim2.new(1, 0, 0, 62), Vector2.new(1, 0), Enum.TextXAlignment.Right)
local rankScale = Instance.new("UIScale")
rankScale.Parent = rankLabel
local damageLabel = label("Damage", "TOTAL DAMAGE: 0", 15, UDim2.new(1, 0, 0, 96), Vector2.new(1, 0), Enum.TextXAlignment.Right)
damageLabel.TextColor3 = Color3.fromRGB(220, 215, 230)

-- the draining bar
local barBack = Instance.new("Frame")
barBack.Name = "Bar"
barBack.AnchorPoint = Vector2.new(1, 0)
barBack.Position = UDim2.new(1, 0, 0, 116)
barBack.Size = UDim2.fromOffset(170, 5)
barBack.BackgroundColor3 = Color3.fromRGB(20, 12, 28)
barBack.BackgroundTransparency = 0.35
barBack.BorderSizePixel = 0
barBack.Parent = holder
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.AnchorPoint = Vector2.new(1, 0)
barFill.Position = UDim2.fromScale(1, 0)
barFill.Size = UDim2.fromScale(1, 1)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

-- ===== state =====
local count, damage, lastHit = 0, 0, 0
local rankIndex = 0

local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function rankFor(n: number): number
	local r = 1
	for i, rk in RANKS do
		if n >= rk.at then r = i end
	end
	return r
end

local function punch(scale: UIScale, peak: number, back: number)
	scale.Scale = peak
	TweenService:Create(scale, TweenInfo.new(back, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function applyRank(r: number, big: boolean)
	local rk = RANKS[r]
	rankLabel.Text = rk.word
	rankLabel.TextColor3 = rk.color
	rankStroke.Color = rk.glow:Lerp(Color3.new(0, 0, 0), 0.55)
	countGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), rk.color)
	countStroke.Color = rk.glow:Lerp(Color3.new(0, 0, 0), 0.6)
	barFill.BackgroundColor3 = rk.color
	if big then
		punch(rankScale, 1.9, 0.45)
		punch(holderScale, 1.12, 0.4)
	end
end

local function reset()
	count, damage, rankIndex = 0, 0, 0
	gui.Enabled = false
end

local function onHit(amount: number)
	local now = os.clock()
	if count > 0 and now - lastHit > WINDOW then reset() end
	count += 1
	damage += amount
	lastHit = now
	gui.Enabled = true
	countLabel.Text = tostring(count)
	damageLabel.Text = "TOTAL DAMAGE: " .. fmt(damage)
	local r = rankFor(count)
	if r ~= rankIndex then
		applyRank(r, rankIndex ~= 0)
		rankIndex = r
	end
	punch(countScale, 1.35, 0.22)
end

Remote.OnClientEvent:Connect(function(events: any)
	if type(events) ~= "table" then return end
	local me = player.UserId
	for _, ev in events do
		if type(ev) == "table" and (ev.u == nil or ev.u == me) and type(ev.a) == "number" and ev.a > 0 then
			onHit(ev.a)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if count == 0 then return end
	local left = 1 - (os.clock() - lastHit) / WINDOW
	if left <= 0 then
		reset()
		return
	end
	barFill.Size = UDim2.fromScale(left, 1)
	-- COMBO GOD shimmers
	if rankIndex == #RANKS then
		local t = os.clock() * 3
		rankLabel.TextColor3 = RANKS[#RANKS].color:Lerp(Color3.new(1, 1, 1), 0.35 + 0.35 * math.sin(t))
	end
	-- the last second: the whole counter fades
	local a = math.clamp((1 - left) * WINDOW - (WINDOW - 1), 0, 1)
	for _, l in { countLabel, hitsLabel, rankLabel, damageLabel } do l.TextTransparency = a end
	countStroke.Transparency = a
	rankStroke.Transparency = a
end)
