-- Egg Heist client: HUD, notifications, knockback, and per-player prompt visibility.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("EggHeistRemotes")
local player = Players.LocalPlayer

-- HUD -----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "EggHeistHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function text(name, size, pos, color, textSize)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.Text = ""
	l.Parent = gui
	return l
end

local cashLabel = text("Cash", UDim2.fromOffset(400, 50), UDim2.new(0.5, 0, 0, 8), Color3.fromRGB(110, 255, 120), 42)
local incomeLabel = text("Income", UDim2.fromOffset(400, 26), UDim2.new(0.5, 0, 0, 56), Color3.fromRGB(255, 255, 255), 22)
local carryLabel = text("Carry", UDim2.fromOffset(500, 30), UDim2.new(0.5, 0, 1, -120), Color3.fromRGB(255, 220, 80), 26)
local toast = text("Toast", UDim2.fromOffset(700, 40), UDim2.new(0.5, 0, 0, 100), Color3.fromRGB(255, 255, 255), 28)
toast.TextTransparency = 1
toast.TextStrokeTransparency = 1

local function refreshCash()
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	cashLabel.Text = cash and ("$" .. Config.Format(cash.Value)) or ""
end

local function refreshIncome()
	incomeLabel.Text = "+$" .. Config.Format(player:GetAttribute("Income") or 0) .. "/s"
end

local function refreshCarry()
	local carrying = player:GetAttribute("Carrying")
	carryLabel.Text = carrying and ("Carrying " .. carrying .. " - get back to your pen!") or ""
end

task.spawn(function()
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	cash.Changed:Connect(refreshCash)
	refreshCash()
end)
player:GetAttributeChangedSignal("Income"):Connect(refreshIncome)
player:GetAttributeChangedSignal("Carrying"):Connect(refreshCarry)
refreshIncome()
refreshCarry()

-- Day / night timer (top right) ---------------------------------------------

local phasePanel = Instance.new("Frame")
phasePanel.Name = "PhasePanel"
phasePanel.AnchorPoint = Vector2.new(1, 0)
phasePanel.Size = UDim2.fromOffset(220, 58)
phasePanel.Position = UDim2.new(1, -16, 0, 60)
phasePanel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
phasePanel.BackgroundTransparency = 0.2
phasePanel.Parent = gui
Instance.new("UICorner").Parent = phasePanel

local function phaseText(name, y, h, size, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = UDim2.new(1, -16, 0, h)
	l.Position = UDim2.fromOffset(8, y)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = phasePanel
	return l
end

local phaseTitle = phaseText("Title", 4, 28, 24, Color3.fromRGB(255, 220, 80))
local phaseHint = phaseText("Hint", 32, 20, 16, Color3.fromRGB(220, 230, 255))

task.spawn(function()
	while true do
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
		phasePanel.Visible = phase ~= nil and endsAt ~= nil
		if phasePanel.Visible then
			local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
			local clock = string.format("%d:%02d", left // 60, left % 60)
			if phase == "Night" then
				phaseTitle.Text = "🌙 NIGHT  " .. clock
				phaseTitle.TextColor3 = Color3.fromRGB(150, 180, 255)
				phaseHint.Text = "Heaps are restocking..."
				phasePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 40)
			else
				phaseTitle.Text = "☀️ DAY  " .. clock
				phaseTitle.TextColor3 = Color3.fromRGB(255, 220, 80)
				phaseHint.Text = "Steal eggs before nightfall!"
				phasePanel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
			end
		end
		task.wait(0.25)
	end
end)

-- Speed level + XP bar (XP comes from running on treadmills) ----------------

local speedPanel = Instance.new("Frame")
speedPanel.Name = "SpeedPanel"
speedPanel.AnchorPoint = Vector2.new(1, 1)
speedPanel.Size = UDim2.fromOffset(240, 58)
speedPanel.Position = UDim2.new(1, -16, 1, -90)
speedPanel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
speedPanel.BackgroundTransparency = 0.2
speedPanel.Parent = gui
Instance.new("UICorner").Parent = speedPanel

local speedTitle = Instance.new("TextLabel")
speedTitle.Size = UDim2.new(1, -16, 0, 26)
speedTitle.Position = UDim2.fromOffset(8, 4)
speedTitle.BackgroundTransparency = 1
speedTitle.Font = Enum.Font.FredokaOne
speedTitle.TextSize = 20
speedTitle.TextXAlignment = Enum.TextXAlignment.Left
speedTitle.TextColor3 = Color3.fromRGB(80, 220, 255)
speedTitle.Parent = speedPanel

local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(1, -16, 0, 16)
barBack.Position = UDim2.fromOffset(8, 34)
barBack.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
barBack.Parent = speedPanel
Instance.new("UICorner").Parent = barBack
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(80, 220, 255)
barFill.Parent = barBack
Instance.new("UICorner").Parent = barFill
local barText = Instance.new("TextLabel")
barText.Size = UDim2.fromScale(1, 1)
barText.BackgroundTransparency = 1
barText.Font = Enum.Font.FredokaOne
barText.TextSize = 13
barText.TextColor3 = Color3.new(1, 1, 1)
barText.TextStrokeTransparency = 0.3
barText.ZIndex = 2
barText.Parent = barBack

local function refreshSpeed()
	local level = player:GetAttribute("SpeedLevel") or 0
	local xp = player:GetAttribute("SpeedXP") or 0
	local mult = Config.TreadmillXPMultiplier(player:GetAttribute("TreadmillLevel") or 0)
	speedTitle.Text = "⚡ Speed Lv " .. level .. "  (" .. Config.WalkSpeed(level, false) .. ")"
		.. (mult > 1 and ("   XP x" .. mult) or "")
	local needed = Config.SpeedXPNeeded(level)
	TweenService:Create(barFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(math.clamp(xp / needed, 0, 1), 1) }):Play()
	barText.Text = math.floor(xp) .. " / " .. needed .. " XP - run on treadmills!"
end
player:GetAttributeChangedSignal("SpeedLevel"):Connect(refreshSpeed)
player:GetAttributeChangedSignal("SpeedXP"):Connect(refreshSpeed)
player:GetAttributeChangedSignal("TreadmillLevel"):Connect(refreshSpeed)
refreshSpeed()

-- Pen prompts: only a pen's owner sees its nest Unlock prompt and its
-- treadmill's Upgrade prompt (which shows your own next price).
local plotsFolder = workspace:WaitForChild("EggHeist"):WaitForChild("Plots")

local function plotOf(inst)
	while inst and inst.Parent ~= plotsFolder do
		inst = inst.Parent
	end
	return inst
end

local function refreshPenPrompt(prompt)
	local plot = plotOf(prompt)
	local mine = plot ~= nil and plot:GetAttribute("OwnerId") == player.UserId
	if prompt.Name == "Unlock" then
		prompt.Enabled = mine
	elseif prompt.Name == "UpgradeTreadmill" then
		prompt.Enabled = mine
		local level = player:GetAttribute("TreadmillLevel") or 0
		if level >= Config.MaxTreadmillLevel then
			prompt.ActionText = "Fully upgraded!"
			prompt.ObjectText = "Treadmill XP x" .. Config.TreadmillXPMultiplier(level)
		else
			prompt.ActionText = "Upgrade $" .. Config.Format(Config.TreadmillUpgradeCost(level))
			prompt.ObjectText = "Treadmill XP x" .. Config.TreadmillXPMultiplier(level) .. " \u{2192} x"
				.. Config.TreadmillXPMultiplier(level + 1)
		end
	end
end

local function refreshAllPenPrompts()
	for _, d in plotsFolder:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			refreshPenPrompt(d)
		end
	end
end

plotsFolder.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then
		refreshPenPrompt(d)
	end
end)
for _, plot in plotsFolder:GetChildren() do
	plot:GetAttributeChangedSignal("OwnerId"):Connect(refreshAllPenPrompts)
end
player:GetAttributeChangedSignal("TreadmillLevel"):Connect(refreshAllPenPrompts)
refreshAllPenPrompts()

-- Treadmill: run in place while locked on, jump to hop off ------------------

local UserInputService = game:GetService("UserInputService")
local RUN_ANIM = "rbxassetid://507767714"
local runTrack

local treadmillHint = text("TreadmillHint", UDim2.fromOffset(600, 30), UDim2.new(0.5, 0, 1, -160),
	Color3.fromRGB(80, 220, 255), 24)

local function refreshTreadmill()
	local on = player:GetAttribute("OnTreadmill") == true
	treadmillHint.Text = on and "\u{1F3C3} Training... press JUMP to get off" or ""
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if on and animator then
		if not runTrack or runTrack.Parent == nil then
			local anim = Instance.new("Animation")
			anim.AnimationId = RUN_ANIM
			runTrack = animator:LoadAnimation(anim)
			runTrack.Priority = Enum.AnimationPriority.Action
			runTrack.Looped = true
		end
		local level = player:GetAttribute("SpeedLevel") or 0
		runTrack:Play(0.2)
		runTrack:AdjustSpeed(Config.WalkSpeed(level, false) / 16)
	elseif runTrack then
		runTrack:Stop(0.2)
	end
end
player:GetAttributeChangedSignal("OnTreadmill"):Connect(refreshTreadmill)
player:GetAttributeChangedSignal("SpeedLevel"):Connect(function()
	if player:GetAttribute("OnTreadmill") then
		refreshTreadmill()
	end
end)
player.CharacterAdded:Connect(function()
	runTrack = nil
	refreshTreadmill()
end)

UserInputService.JumpRequest:Connect(function()
	if player:GetAttribute("OnTreadmill") then
		Remotes.LeaveTreadmill:FireServer()
	end
end)

-- Scroll the slats on any belt someone is running on.
RunService.RenderStepped:Connect(function(dt)
	for _, plot in plotsFolder:GetChildren() do
		local mill = plot:FindFirstChild("Treadmill")
		local belt = mill and mill:FindFirstChild("Belt")
		if belt and belt:GetAttribute("Running") then
			local len = belt.Size.Z
			local speed = belt:GetAttribute("Speed") or 16
			for _, slat in mill.Slats:GetChildren() do
				local off = ((slat:GetAttribute("Offset") or 0) + dt * speed) % len
				slat:SetAttribute("Offset", off)
				slat.CFrame = belt.CFrame * CFrame.new(0, belt.Size.Y / 2 + 0.03, -len / 2 + off)
			end
		end
	end
end)

local toastId = 0
Remotes.Notify.OnClientEvent:Connect(function(message)
	toastId += 1
	local id = toastId
	toast.Text = message
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.2
	task.delay(3, function()
		if id == toastId then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end)

-- Knockback when a guard catches you ---------------------------------------

Remotes.Knockback.OnClientEvent:Connect(function(direction)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	hum.PlatformStand = true
	root.AssemblyLinearVelocity = direction * 60 + Vector3.new(0, 35, 0)
	task.delay(1, function()
		hum.PlatformStand = false
	end)
end)

-- Prompts: you see "Sell" on your own items and "Steal" on everyone else's.

local function refreshPrompt(prompt)
	local item = prompt.Parent and prompt.Parent.Parent
	if not item then
		return
	end
	local mine = item:GetAttribute("OwnerId") == player.UserId
	if prompt.Name == "Steal" then
		prompt.Enabled = not mine
	elseif prompt.Name == "Sell" then
		prompt.Enabled = mine
	end
end

local itemsFolder = workspace:WaitForChild("EggHeist"):WaitForChild("Items")
itemsFolder.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then
		refreshPrompt(d)
	end
end)
itemsFolder.ChildAdded:Connect(function(item)
	item:GetAttributeChangedSignal("OwnerId"):Connect(function()
		for _, d in item:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				refreshPrompt(d)
			end
		end
	end)
end)
for _, d in itemsFolder:GetDescendants() do
	if d:IsA("ProximityPrompt") then
		refreshPrompt(d)
	end
end

-- Unicorn manes cycle through the rainbow.
RunService.RenderStepped:Connect(function()
	local hue = (os.clock() * 0.25) % 1
	for _, part in CollectionService:GetTagged("RainbowPart") do
		part.Color = Color3.fromHSV(hue, 0.8, 1)
	end
end)

-- Shop & admin panels ---------------------------------------------------------

local MarketplaceService = game:GetService("MarketplaceService")

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

local function makeButton(parent, textValue, color, size, pos)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.5
	b.Text = textValue
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	return b
end

local function makePanel(name, title, accent)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(440, 420)
	frame.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
	frame.Visible = false
	frame.Parent = gui
	corner(frame, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 3
	stroke.Parent = frame
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -60, 0, 44)
	t.Position = UDim2.fromOffset(16, 6)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = accent
	t.Text = title
	t.Parent = frame
	local close = makeButton(frame, "X", Color3.fromRGB(200, 60, 60), UDim2.fromOffset(36, 36), UDim2.new(1, -46, 0, 10))
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	return frame
end

-- Side buttons
local sideButtons = Instance.new("Frame")
sideButtons.Name = "SideButtons"
sideButtons.BackgroundTransparency = 1
sideButtons.AnchorPoint = Vector2.new(0, 0.5)
sideButtons.Position = UDim2.new(0, 12, 0.5, 0)
sideButtons.Size = UDim2.fromOffset(150, 120)
sideButtons.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.Parent = sideButtons
local shopButton = makeButton(sideButtons, "\u{1F6D2} Shop", Color3.fromRGB(60, 190, 90), UDim2.fromOffset(150, 52))
local adminButton = makeButton(sideButtons, "\u{1F6E0} Admin", Color3.fromRGB(200, 120, 40), UDim2.fromOffset(150, 52))
adminButton.Visible = false

-- Follow reward panel
local follow = makePanel("FollowReward", "\u{2B50} Follow Reward", Color3.fromRGB(255, 200, 60))
follow.Size = UDim2.fromOffset(440, 250)
local followInfo = Instance.new("TextLabel")
followInfo.Size = UDim2.new(1, -32, 0, 90)
followInfo.Position = UDim2.fromOffset(16, 54)
followInfo.BackgroundTransparency = 1
followInfo.Font = Enum.Font.FredokaOne
followInfo.TextScaled = true
followInfo.TextWrapped = true
followInfo.TextColor3 = Color3.new(1, 1, 1)
followInfo.Parent = follow
local followResult = Instance.new("TextLabel")
followResult.Size = UDim2.new(1, -32, 0, 26)
followResult.Position = UDim2.new(0, 16, 1, -36)
followResult.BackgroundTransparency = 1
followResult.Font = Enum.Font.FredokaOne
followResult.TextScaled = true
followResult.TextColor3 = Color3.fromRGB(255, 220, 120)
followResult.Text = ""
followResult.Parent = follow
local claimButton = makeButton(follow, "Claim $" .. Config.Format(Config.FollowRewardCash), Color3.fromRGB(60, 190, 90),
	UDim2.fromOffset(220, 48), UDim2.new(0.5, -110, 0, 152))

-- The panel opens from the Free Cash stand in the lobby.
local followStand = workspace:WaitForChild("EggHeist"):WaitForChild("FollowStand", 10)
local function waitPath(root, ...)
	for _, name in { ... } do
		root = root and root:WaitForChild(name, 10)
	end
	return root
end
local standPrompt = waitPath(followStand, "Counter", "PromptSpot", "OpenFollowReward")
local standSub = waitPath(followStand, "Board", "SignGui", "Sub")

local function refreshFollow()
	local name = ReplicatedStorage:GetAttribute("CreatorName") or "the creator"
	followInfo.Text = "1. Follow " .. name .. " on Roblox (keep this panel open)\n2. Press Claim to get $"
		.. Config.Format(Config.FollowRewardCash) .. "!"
	local claimed = player:GetAttribute("FollowRewardClaimed") == true
	if standSub then
		standSub.Text = claimed and "Thanks for following!" or ("Follow " .. name .. "!")
	end
	if standPrompt then
		standPrompt.Enabled = not claimed
	end
	if claimed then
		follow.Visible = false
	end
end
if standPrompt then
	standPrompt.Triggered:Connect(function()
		for _, name in { "Shop", "Admin" } do
			local panel = gui:FindFirstChild(name)
			if panel then
				panel.Visible = false
			end
		end
		follow.Visible = true
	end)
end
ReplicatedStorage:GetAttributeChangedSignal("CreatorName"):Connect(refreshFollow)
player:GetAttributeChangedSignal("FollowRewardClaimed"):Connect(refreshFollow)
refreshFollow()

-- Opening the panel tells the server to note the creator's follower count.
follow:GetPropertyChangedSignal("Visible"):Connect(function()
	if follow.Visible then
		followResult.Text = ""
		task.spawn(function()
			local ok, success, msg = pcall(function()
				return Remotes.ClaimFollowReward:InvokeServer("open")
			end)
			if ok and not success and msg and msg ~= "" then
				followResult.Text = msg
			end
		end)
	end
end)

local claiming = false
claimButton.Activated:Connect(function()
	if claiming then
		return
	end
	claiming = true
	followResult.Text = "Checking..."
	local ok, _, msg = pcall(function()
		return Remotes.ClaimFollowReward:InvokeServer("claim")
	end)
	followResult.Text = ok and tostring(msg) or "Request failed, try again."
	claiming = false
end)


-- Shop panel
local shop = makePanel("Shop", "\u{1F6D2} Robux Shop", Color3.fromRGB(90, 220, 120))
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -64)
scroll.Position = UDim2.fromOffset(12, 56)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = shop
local shopList = Instance.new("UIListLayout")
shopList.Padding = UDim.new(0, 8)
shopList.Parent = scroll

local function shopRow(entry, isPass)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 62)
	row.BackgroundColor3 = Color3.fromRGB(40, 48, 68)
	row.Parent = scroll
	corner(row, 10)
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -150, 0, 30)
	name.Position = UDim2.fromOffset(12, 4)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = entry.Name .. (isPass and "  \u{2B50}" or "")
	name.Parent = row
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -150, 0, 22)
	desc.Position = UDim2.fromOffset(12, 34)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextScaled = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextColor3 = Color3.fromRGB(190, 200, 220)
	desc.Text = entry.Description or (entry.Kind == "Cash" and ("+$" .. Config.Format(entry.Amount) .. " cash")) or ""
	desc.Parent = row
	local buy = makeButton(row, "R$ ...", Color3.fromRGB(60, 190, 90), UDim2.fromOffset(126, 44), UDim2.new(1, -136, 0, 9))
	if entry.Id == 0 then
		buy.Text = "Not set up"
		buy.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
	else
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Id,
				isPass and Enum.InfoType.GamePass or Enum.InfoType.Product)
			buy.Text = (ok and info and info.PriceInRobux) and ("R$ " .. info.PriceInRobux) or "Buy"
		end)
	end
	buy.Activated:Connect(function()
		if entry.Id == 0 then
			toast.Text = "This item isn't set up yet (needs an ID in GameConfig)."
			toast.TextTransparency = 0
			toast.TextStrokeTransparency = 0.2
			task.delay(3, function()
				toast.TextTransparency = 1
				toast.TextStrokeTransparency = 1
			end)
		elseif isPass then
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.Id)
		end
	end)
end
for _, pass in Config.GamePasses do
	shopRow(pass, true)
end
for _, product in Config.Products do
	shopRow(product, false)
end

-- Admin panel
local admin = makePanel("Admin", "\u{1F6E0} Admin Panel", Color3.fromRGB(255, 160, 60))
local function box(placeholder, y)
	local b = Instance.new("TextBox")
	b.Size = UDim2.new(1, -24, 0, 38)
	b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = Color3.fromRGB(45, 52, 72)
	b.Font = Enum.Font.Gotham
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.PlaceholderText = placeholder
	b.PlaceholderColor3 = Color3.fromRGB(150, 160, 180)
	b.Text = ""
	b.ClearTextOnFocus = false
	b.Parent = admin
	corner(b, 8)
	return b
end
local targetBox = box("Player name (blank = you)", 56)
local valueBox = box("Amount / level / stage number", 100)
local result = Instance.new("TextLabel")
result.Size = UDim2.new(1, -24, 0, 30)
result.Position = UDim2.new(0, 12, 1, -40)
result.BackgroundTransparency = 1
result.Font = Enum.Font.FredokaOne
result.TextScaled = true
result.TextColor3 = Color3.fromRGB(255, 220, 120)
result.Text = ""
result.Parent = admin

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Size = UDim2.new(1, -24, 0, 210)
grid.Position = UDim2.fromOffset(12, 148)
grid.Parent = admin
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -5, 0, 46)
gridLayout.CellPadding = UDim2.fromOffset(10, 8)
gridLayout.Parent = grid

local commands = {
	{ "Cash", "\u{1F4B0} Give Cash", Color3.fromRGB(60, 170, 80) },
	{ "Speed", "\u{26A1} Set Speed Lv", Color3.fromRGB(50, 140, 230) },
	{ "Nests", "\u{1F513} Unlock All Nests", Color3.fromRGB(190, 140, 50) },
	{ "Stage", "\u{1F6AA} Go To Stage #", Color3.fromRGB(130, 90, 210) },
	{ "Restock", "\u{1F95A} Restock Heaps", Color3.fromRGB(60, 160, 170) },
	{ "Reset", "\u{267B} Reset Player", Color3.fromRGB(200, 90, 60) },
	{ "Kick", "\u{1F462} Kick Player", Color3.fromRGB(170, 40, 40) },
}
for _, cmd in commands do
	local b = makeButton(grid, cmd[2], cmd[3], UDim2.new())
	b.Activated:Connect(function()
		result.Text = "..."
		local ok, msg = pcall(function()
			return Remotes.AdminCommand:InvokeServer(cmd[1], targetBox.Text, valueBox.Text)
		end)
		result.Text = ok and tostring(msg) or "Request failed"
	end)
end

local function refreshAdmin()
	adminButton.Visible = player:GetAttribute("IsAdmin") == true
	if not adminButton.Visible then
		admin.Visible = false
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshAdmin)
refreshAdmin()

shopButton.Activated:Connect(function()
	admin.Visible = false
	follow.Visible = false
	shop.Visible = not shop.Visible
end)
adminButton.Activated:Connect(function()
	shop.Visible = false
	follow.Visible = false
	admin.Visible = not admin.Visible
end)

