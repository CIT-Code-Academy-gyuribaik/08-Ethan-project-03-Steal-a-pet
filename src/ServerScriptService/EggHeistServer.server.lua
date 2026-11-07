-- Egg Heist: sneak across the field, steal eggs/pets from the guarded heaps,
-- run back to your pen without getting caught, hatch eggs, and earn cash.
-- Pens are safe: there's no stealing from other players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.GameConfig)
local Remotes = ReplicatedStorage.EggHeistRemotes
local Notify = Remotes.Notify
local Knockback = Remotes.Knockback

local Map = workspace.EggHeist

local itemsFolder = Instance.new("Folder")
itemsFolder.Name = "Items"
itemsFolder.Parent = Map

local plotList = {} -- ordered pen states
local playerPlot = {} -- [Player] = pen state
local sections = {} -- guarded loot line sections
local items = {} -- [Model] = item data (eggs and pets)
local carrying = {} -- [Player] = item Model

local plotModels = Map.Plots:GetChildren()
table.sort(plotModels, function(a, b)
	return a.Name < b.Name
end)
for _, model in plotModels do
	local pedestals = {}
	for i = 1, #model.Pedestals:GetChildren() do
		pedestals[i] = model.Pedestals["Pedestal" .. i]
	end
	table.insert(plotList, {
		model = model,
		owner = nil,
		pedestals = pedestals,
		slots = {},
		unlocked = Config.StartingSlots,
	})
end

for _, model in Map.GuardLand.Sections:GetChildren() do
	local pads = {}
	for i = 1, #model.Pads:GetChildren() do
		pads[i] = model.Pads["Pad" .. i]
	end
	table.insert(sections, {
		model = model,
		cfg = Config.Guards[model:GetAttribute("Guard")],
		chaseLimitX = model:GetAttribute("ChaseLimitX"),
		pads = pads,
		slots = {},
		respawnAt = {},
	})
end

-- Helpers ---------------------------------------------------------------

local function notify(player, text)
	if player and player.Parent then
		Notify:FireClient(player, text)
	end
end

local function getRoot(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return root, hum
end

local function getCash(player)
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Cash")
end

local function applySpeed(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = Config.WalkSpeed(player:GetAttribute("SpeedLevel") or 0, carrying[player] ~= nil)
	end
end

local function freeSlot(plot)
	for i = 1, plot.unlocked do
		if plot.slots[i] == nil then
			return i
		end
	end
	return nil
end

local function standHeight(item)
	local data = items[item]
	return Config.StandHeight(data.kind, data.type)
end

-- Boxes "open"; eggs "hatch".
local function hatchWord(t)
	return t.Shape == "Box" and "Opening" or "Hatching"
end

local function incomeOf(data)
	return data.kind == "Pet" and data.type.Income or 0
end

local function sellValue(data)
	if data.kind == "Pet" then
		return data.type.Income * Config.PetSellSeconds
	end
	return math.floor(data.type.Price * Config.SellRefund)
end

local function clearPrompts(item)
	for _, c in item.PrimaryPart:GetChildren() do
		if c:IsA("ProximityPrompt") then
			c:Destroy()
		end
	end
end

local function addPrompt(item, name, action, hold)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = item.Name
	p.HoldDuration = hold
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = item.PrimaryPart
	return p
end

local function clearCarryWeld(item)
	local w = item.PrimaryPart:FindFirstChild("CarryWeld")
	if w then
		w:Destroy()
	end
end

local function destroyItem(item)
	items[item] = nil
	item:Destroy()
end

local function label(parent, name, y, h, color, text)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = UDim2.new(1, 0, h, 0)
	l.Position = UDim2.new(0, 0, y, 0)
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.Parent = parent
	return l
end

local function setStatus(item, text, color)
	local status = item.PrimaryPart.Info.Status
	status.Visible = text ~= nil
	if text then
		status.Text = text
		status.TextColor3 = color or Color3.new(1, 1, 1)
	end
end

local function makeItem(kind, t)
	local item = kind == "Egg" and Config.BuildEgg(t) or Config.BuildPet(t)
	item:SetAttribute("OwnerId", 0)

	local bb = Instance.new("BillboardGui")
	bb.Name = "Info"
	bb.Size = UDim2.fromOffset(170, 66)
	bb.StudsOffset = Vector3.new(0, kind == "Egg" and 3.8 or 3.6 * (t.Scale or 1), 0)
	bb.MaxDistance = 60
	bb.LightInfluence = 0
	bb.Parent = item.PrimaryPart
	label(bb, "Title", 0, 0.4, t.TextColor, t.Name)
	local sub = kind == "Pet" and (t.Rarity .. "  •  $" .. Config.Format(t.Income) .. "/s")
		or (t.Rarity .. "  •  " .. (t.Shape == "Box" and "opens" or "hatches") .. " in " .. t.HatchTime .. "s")
	label(bb, "Sub", 0.4, 0.3, Color3.fromRGB(255, 255, 255), sub)
	label(bb, "Status", 0.7, 0.3, Color3.new(1, 1, 1), "").Visible = false

	items[item] = { kind = kind, type = t, hatchLeft = t.HatchTime }
	return item
end

-- Carried items shrink so they don't block the carrier's camera.
local CARRY_SCALE = 0.55

local function setCarried(item, carried)
	item:ScaleTo(carried and CARRY_SCALE or 1)
	item.PrimaryPart.Info.Enabled = not carried
end

local function resetHome(data)
	data.homeSection = nil
	data.homePad = nil
end

-- Item state transitions ------------------------------------------------

local function placeOnPedestal(item, plot, slot)
	local data = items[item]
	clearCarryWeld(item)
	clearPrompts(item)
	setCarried(item, false)
	item.PrimaryPart.Anchored = true
	item.PrimaryPart.Massless = false
	-- Pedestal top is 1 stud above its center; face the pen's open front.
	item:PivotTo(plot.pedestals[slot].CFrame * CFrame.new(0, 1 + standHeight(item), 0) * CFrame.Angles(0, math.pi, 0))
	item.Parent = itemsFolder
	plot.slots[slot] = item
	data.state = "Pedestal"
	data.plot = plot
	data.slot = slot
	data.carrier = nil
	resetHome(data)
	item:SetAttribute("OwnerId", plot.owner and plot.owner.UserId or 0)
	if data.kind == "Egg" then
		setStatus(item, hatchWord(data.type) .. " in " .. data.hatchLeft .. "s", Color3.fromRGB(255, 230, 120))
	else
		setStatus(item, nil)
	end
	addPrompt(item, "Sell", "Sell for $" .. Config.Format(sellValue(data)), 0.6)
end

local function placeOnLine(item, section, pad)
	local data = items[item]
	clearCarryWeld(item)
	clearPrompts(item)
	setCarried(item, false)
	item.PrimaryPart.Anchored = true
	item.PrimaryPart.Massless = false
	-- Pads are spots on the loot heap; their Y is the surface the item sits on.
	-- The "Rare" pad is the night rare egg's spot somewhere in the biome.
	local isRare = pad == "Rare"
	local surface = isRare and section.rareSpot or section.pads[pad].Position
	local pos = surface + Vector3.new(0, standHeight(item), 0)
	if isRare then
		item:PivotTo(CFrame.new(pos))
	else
		-- Jumbled facing and a slight tilt so it reads as a pile, not a display.
		local yaw = math.rad((pad * 67) % 360)
		item:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad((pad % 3 - 1) * 8), 0, 0))
	end
	item.Parent = itemsFolder
	section.slots[pad] = item
	data.state = "Line"
	data.section = section
	data.pad = pad
	data.carrier = nil
	resetHome(data)
	item:SetAttribute("OwnerId", 0)
	setStatus(item, nil)
	-- Labels on a heap overlap into a mess; the prompt names the item instead.
	item.PrimaryPart.Info.Enabled = false
	local prompt = addPrompt(item, "Steal", "Steal", 0.8)
	prompt.MaxActivationDistance = 14
	prompt.ObjectText = item.Name .. " (" .. data.type.Rarity .. ")"
	if isRare then
		-- A far-visible marker so players can hunt it down.
		local bb = Instance.new("BillboardGui")
		bb.Name = "RareBeacon"
		bb.Size = UDim2.fromOffset(220, 40)
		bb.StudsOffset = Vector3.new(0, 5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 1000
		bb.LightInfluence = 0
		bb.Parent = item.PrimaryPart
		label(bb, "Title", 0, 1, data.type.TextColor, "✨ " .. string.upper(item.Name) .. " ✨")
		local hl = Instance.new("Highlight")
		hl.Name = "RareHighlight"
		hl.FillColor = data.type.TextColor
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.6
		hl.Parent = item
	end
end

local function hatch(egg)
	local data = items[egg]
	local plot, slot = data.plot, data.slot
	local petType = Config.RollPet(data.type)
	local pet = makeItem("Pet", petType)
	local pos = egg.PrimaryPart.Position
	destroyItem(egg)
	placeOnPedestal(pet, plot, slot)

	local burst = Instance.new("Part")
	burst.Anchored = true
	burst.CanCollide = false
	burst.Transparency = 1
	burst.Position = pos
	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(petType.TextColor)
	fx.LightEmission = 1
	fx.Size = NumberSequence.new(0.6, 0)
	fx.Speed = NumberRange.new(10, 18)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Lifetime = NumberRange.new(0.5, 0.9)
	fx.Enabled = false
	fx.Parent = burst
	burst.Parent = workspace
	fx:Emit(40)
	Debris:AddItem(burst, 2)

	local verb = data.type.Shape == "Box" and " had a " or " hatched a "
	notify(plot.owner, "🐣 Your " .. data.type.Name .. verb .. petType.Rarity .. " " .. petType.Name .. " inside! +$"
		.. Config.Format(petType.Income) .. "/s")
end

local function attachToCarrier(player, item)
	local root = getRoot(player)
	local data = items[item]
	clearPrompts(item)
	clearCarryWeld(item)
	setStatus(item, nil)
	setCarried(item, true)
	item:PivotTo(root.CFrame * CFrame.new(0, 3 + standHeight(item) * CARRY_SCALE, 0))
	item.PrimaryPart.Anchored = false
	item.PrimaryPart.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = item.PrimaryPart
	weld.Parent = item.PrimaryPart
	data.state = "Carried"
	data.carrier = player
	carrying[player] = item
	applySpeed(player)
	player:SetAttribute("Carrying", item.Name)
end

local function detach(player)
	local item = carrying[player]
	carrying[player] = nil
	player:SetAttribute("Carrying", nil)
	applySpeed(player)
	return item
end

local function makeLoose(item, position)
	local data = items[item]
	clearCarryWeld(item)
	clearPrompts(item)
	setCarried(item, false)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { itemsFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -50, 0), params)
	local groundY = hit and hit.Position.Y or 0
	item.PrimaryPart.Anchored = true
	item.PrimaryPart.Massless = false
	item:PivotTo(CFrame.new(position.X, groundY + standHeight(item), position.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0))
	item.Parent = itemsFolder
	item:SetAttribute("OwnerId", 0)
	data.state = "Loose"
	data.carrier = nil
	resetHome(data)
	data.droppedAt = os.clock()
	setStatus(item, "FREE! Grab it!", Color3.fromRGB(110, 255, 120))
	addPrompt(item, "Grab", "Grab (free!)", 0.5)
end

-- Drops whatever the player is carrying. Loot goes back onto the guard's heap
-- it was stolen from; anything else lands on the ground.
local function dropItem(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local item = detach(player)
	if not item or not items[item] then
		return
	end
	local data = items[item]
	local section, pad = data.homeSection, data.homePad
	if section and section.slots[pad] == item then
		placeOnLine(item, section, pad)
	else
		makeLoose(item, root and root.Position or item.PrimaryPart.Position)
	end
end

-- Prompt actions --------------------------------------------------------

local function canCarryNew(player)
	local plot = playerPlot[player]
	if not plot then
		return false
	end
	if carrying[player] then
		notify(player, "Your hands are full!")
		return false
	end
	if not freeSlot(plot) then
		notify(player, "Your pen is full! Sell something first.")
		return false
	end
	return getRoot(player) ~= nil
end

local guards = {} -- filled in the Guards section below; [section] = guard state

local function trySteal(player, item, data)
	if data.state ~= "Line" or not canCarryNew(player) then
		return
	end
	local isRare = data.pad == "Rare"
	if ReplicatedStorage:GetAttribute("Phase") == "Night" and not isRare then
		notify(player, "🌙 It's night - the guards are restocking. Wait for morning!")
		return
	end
	if isRare then
		for _, name in { "RareBeacon", "RareHighlight" } do
			local fx = item:FindFirstChild(name, true)
			if fx then
				fx:Destroy()
			end
		end
		for _, p in Players:GetPlayers() do
			notify(p, "✨ " .. player.DisplayName .. " grabbed the " .. item.Name .. "!")
		end
	end
	do
		-- The pad stays reserved so the item can go back if the thief is caught.
		local section = data.section
		data.homeSection = section
		data.homePad = data.pad
		data.section = nil
		data.pad = nil
		attachToCarrier(player, item)
		local guard = guards[section]
		if guard then
			guard.target = player
		end
		notify(player, "🏃 RUN! " .. section.cfg.Name .. " is after you! Get back to your pen!")
	end
end

local function trySell(player, item, data)
	if data.state ~= "Pedestal" or data.plot.owner ~= player then
		return
	end
	local refund = sellValue(data)
	data.plot.slots[data.slot] = nil
	getCash(player).Value += refund
	destroyItem(item)
	notify(player, "Sold for $" .. Config.Format(refund))
end

local function tryGrab(player, item, data)
	if data.state ~= "Loose" or not canCarryNew(player) then
		return
	end
	item:SetAttribute("OwnerId", player.UserId)
	attachToCarrier(player, item)
	notify(player, "Grabbed a " .. item.Name .. "! Get it home!")
end

-- Nest unlocks -------------------------------------------------------------

local HAY = Color3.fromRGB(225, 190, 95)

-- Unlocked nests look like hay bales; locked ones are faded, and the next
-- one up for purchase shows its price and an Unlock prompt.
local function refreshPedestals(plot)
	for i, ped in plot.pedestals do
		local unlocked = i <= plot.unlocked
		ped.Color = unlocked and HAY or Color3.fromRGB(130, 130, 130)
		ped.Transparency = unlocked and 0 or 0.55
		for _, name in { "Rim", "Band" } do
			local p = ped:FindFirstChild(name)
			if p then
				p.Transparency = unlocked and 0 or 1
			end
		end
		local oldGui = ped:FindFirstChild("LockGui")
		if oldGui then
			oldGui:Destroy()
		end
		local oldPrompt = ped:FindFirstChild("Unlock")
		if oldPrompt then
			oldPrompt:Destroy()
		end
		if not unlocked and plot.owner then
			local isNext = i == plot.unlocked + 1
			local gui = Instance.new("BillboardGui")
			gui.Name = "LockGui"
			gui.Size = UDim2.fromOffset(isNext and 130 or 40, isNext and 44 or 30)
			gui.StudsOffset = Vector3.new(0, 2.5, 0)
			gui.MaxDistance = 50
			gui.LightInfluence = 0
			gui.Parent = ped
			local l = label(gui, "Text", 0, 1, isNext and Color3.fromRGB(110, 255, 120) or Color3.fromRGB(200, 200, 200),
				isNext and ("🔒 $" .. Config.Format(Config.SlotCost(i))) or "🔒")
			l.TextScaled = true
			if isNext then
				local p = Instance.new("ProximityPrompt")
				p.Name = "Unlock"
				p.ActionText = "Unlock nest $" .. Config.Format(Config.SlotCost(i))
				p.ObjectText = "Nest " .. i
				p.HoldDuration = 0.5
				p.MaxActivationDistance = 10
				p.RequiresLineOfSight = false
				p.Parent = ped
			end
		end
	end
end

local function tryUnlock(player, plot)
	if plot.owner ~= player or plot.unlocked >= #plot.pedestals then
		return
	end
	local slot = plot.unlocked + 1
	local cost = Config.SlotCost(slot)
	local cash = getCash(player)
	if cash.Value < cost then
		notify(player, "Not enough cash! That nest costs $" .. Config.Format(cost))
		return
	end
	cash.Value -= cost
	plot.unlocked = slot
	refreshPedestals(plot)
	notify(player, "🪺 Nest " .. slot .. " unlocked! (" .. slot .. "/" .. #plot.pedestals .. ")")
end

-- Treadmill upgrades --------------------------------------------------------

local function tryUpgradeTreadmill(player)
	local level = player:GetAttribute("TreadmillLevel") or 0
	if level >= Config.MaxTreadmillLevel then
		notify(player, "Your treadmills are fully upgraded!")
		return
	end
	local cost = Config.TreadmillUpgradeCost(level)
	local cash = getCash(player)
	if cash.Value < cost then
		notify(player, "Not enough cash! Upgrade costs $" .. Config.Format(cost))
		return
	end
	cash.Value -= cost
	player:SetAttribute("TreadmillLevel", level + 1)
	notify(player, "⚙️ Treadmills upgraded to Lv " .. (level + 1) .. "! XP x"
		.. Config.TreadmillXPMultiplier(level + 1))
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if prompt.Name == "Unlock" then
		for _, plot in plotList do
			if prompt:IsDescendantOf(plot.model) then
				tryUnlock(player, plot)
			end
		end
		return
	elseif prompt.Name == "UpgradeTreadmill" then
		tryUpgradeTreadmill(player)
		return
	end
	local item = prompt.Parent and prompt.Parent.Parent
	local data = items[item]
	if not data then
		return
	end
	if prompt.Name == "Steal" then
		trySteal(player, item, data)
	elseif prompt.Name == "Sell" then
		trySell(player, item, data)
	elseif prompt.Name == "Grab" then
		tryGrab(player, item, data)
	end
end)

-- Loot line -----------------------------------------------------------------

local function rollLoot(cfg)
	local options = {}
	local total = 0
	for _, name in cfg.Eggs do
		for _, e in Config.Eggs do
			if e.Name == name then
				table.insert(options, e)
				total += e.Weight
			end
		end
	end
	local r = math.random() * total
	local eggType = options[1]
	for _, e in options do
		r -= e.Weight
		if r <= 0 then
			eggType = e
			break
		end
	end
	if math.random() < cfg.PetChance then
		return makeItem("Pet", Config.RollPet(eggType))
	end
	return makeItem("Egg", eggType)
end

task.spawn(function()
	while true do
		local now = os.clock()
		-- Heaps stay empty at night; they refill at dawn.
		if ReplicatedStorage:GetAttribute("Phase") ~= "Night" then
			for _, section in sections do
				for pad = 1, #section.pads do
					if section.slots[pad] == nil and now >= (section.respawnAt[pad] or 0) then
						placeOnLine(rollLoot(section.cfg), section, pad)
					end
				end
			end
		end
		task.wait(1)
	end
end)

-- Day / night cycle ---------------------------------------------------------
-- Day: steal as usual. Night: every guarded heap is cleared, and fresh loot is
-- rolled onto every pad when the next day starts. Phase and end time are
-- published as ReplicatedStorage attributes for the client HUD.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local DAY_CLOCK = Lighting.ClockTime
local NIGHT_CLOCK = 23.5

local function notifyAll(text)
	for _, p in Players:GetPlayers() do
		notify(p, text)
	end
end

local function clearHeaps()
	for _, section in sections do
		for pad = 1, #section.pads do
			local item = section.slots[pad]
			if item then
				local data = items[item]
				if data and data.state == "Line" then
					destroyItem(item)
				end
				-- Loot being carried keeps its thief (and its chasing guard), but
				-- its pad is freed: if the thief is caught it drops on the ground.
				section.slots[pad] = nil
			end
		end
		-- Last night's rare egg vanishes if nobody took it.
		local rare = section.slots.Rare
		if rare then
			local data = items[rare]
			if data and data.state == "Line" then
				destroyItem(rare)
			end
			section.slots.Rare = nil
		end
		table.clear(section.respawnAt)
	end
end

-- Finds open ground somewhere in a section's biome, away from its heap.
local function findRareSpot(section)
	local stage = section.model:GetAttribute("Guard")
	local east = Config.StageEast(stage)
	local center = section.model.Center.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { itemsFolder }
	for _, g in guards do
		table.insert(ignore, g.model)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	for _ = 1, 40 do
		local x = math.random() * (Config.StageLength - 20) + (east - Config.StageLength + 10)
		local z = math.random(-135, 135)
		if (Vector3.new(x, 0, z) - center * Vector3.new(1, 0, 1)).Magnitude > 25 then
			local hit = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -100, 0), params)
			if hit and hit.Normal.Y > 0.9 and hit.Position.Y < 6 then
				return hit.Position
			end
		end
	end
	return center + Vector3.new(0, 0, 40)
end

local function spawnRareEgg()
	if math.random() >= Config.NightRareEggChance or #sections == 0 then
		return
	end
	local total = 0
	for _, e in Config.NightRareEggs do
		total += e.Weight
	end
	local r = math.random() * total
	local pick = Config.NightRareEggs[1]
	for _, e in Config.NightRareEggs do
		r -= e.Weight
		if r <= 0 then
			pick = e
			break
		end
	end
	local eggType = Config.FindEgg(pick.Name)
	if not eggType then
		warn("Rare egg not found in Config.Eggs: " .. pick.Name)
		return
	end
	local section = sections[math.random(#sections)]
	section.rareSpot = findRareSpot(section)
	placeOnLine(makeItem("Egg", eggType), section, "Rare")
	notifyAll("✨ A " .. eggType.Rarity .. " " .. eggType.Name .. " appeared in the " .. section.cfg.Stage .. "! ✨")
end

local function setPhase(phase, length)
	ReplicatedStorage:SetAttribute("Phase", phase)
	ReplicatedStorage:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + length)
end

task.spawn(function()
	while true do
		setPhase("Day", Config.DayLength)
		task.wait(Config.DayLength)

		setPhase("Night", Config.NightLength)
		clearHeaps()
		notifyAll("🌙 Night falls! The guards are restocking every heap...")
		task.delay(2.5, spawnRareEgg)
		TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = NIGHT_CLOCK }):Play()
		task.wait(Config.NightLength)

		Lighting.ClockTime = 4
		TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = DAY_CLOCK }):Play()
		notifyAll("☀️ A new day! Fresh eggs and pets on every heap!")
	end
end)

-- Guards --------------------------------------------------------------------

local ANIMS = {
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	idle = "rbxassetid://507766388",
	sit = "rbxassetid://2506281703",
}

-- A big chicken built from parts around an invisible root, with a Humanoid so it
-- can walk with MoveTo. It has no animations; it hops as it moves instead.
local function buildChicken(section)
	local cfg = section.cfg
	local s = cfg.Scale
	local model = Instance.new("Model")
	model.Name = cfg.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.5, 2.5, 2.5) * s
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	local white, orange, red = cfg.Skin, Color3.fromRGB(245, 160, 40), cfg.Shirt
	local function piece(name, size, offset, color, shape, rot)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size * s
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Massless = true
		p.CFrame = root.CFrame * CFrame.new(offset * s) * (rot or CFrame.new())
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		return p
	end
	local V = Vector3.new
	local gray = Color3.fromRGB(228, 228, 222)
	piece("Body", V(3, 2.6, 3.6), V(0, 0, 0.2), white)
	piece("Head", V(2, 2.2, 1.8), V(0, 1.9, -1.7), white)
	piece("Beak", V(0.9, 0.6, 0.8), V(0, 1.8, -3), orange)
	piece("Wattle", V(0.5, 0.7, 0.3), V(0, 1.2, -2.75), red)
	piece("Comb", V(0.4, 0.7, 1), V(0, 3.3, -1.7), red)
	piece("Tail", V(2.2, 1.6, 0.9), V(0, 0.9, 2.1), gray)
	local legs = {}
	for _, x in { -1, 1 } do
		piece("Eye", V(0.1, 0.45, 0.35), V(x * 1.02, 2.2, -2.2), Color3.fromRGB(20, 20, 20))
		piece("Wing", V(0.4, 1.8, 2.6), V(x * 1.7, 0.1, 0.3), gray)
		table.insert(legs, piece("Leg", V(0.4, 1.4, 0.4), V(x * 0.6, -2, 0.2), orange))
		table.insert(legs, piece("Foot", V(0.9, 0.2, 1), V(x * 0.6, -2.7, -0.1), orange))
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	-- Feet bottom sits 2.8 below the root center; the root is 2.5 tall.
	-- Asleep, the legs tuck away and the body (bottom at 1.3) rests on the ground.
	hum.HipHeight = (2.8 - 1.25) * s
	hum.DisplayName = cfg.Name
	hum.NameDisplayDistance = 120
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	hum.Parent = model

	local home = section.model.Center.Position
	model:PivotTo(CFrame.lookAt(home + Vector3.new(0, 3 * s, 0), home + Vector3.new(1, 3 * s, 0)))
	model.Parent = section.model
	root:SetNetworkOwner(nil)
	hum.WalkSpeed = cfg.Speed * 0.5

	return {
		section = section,
		cfg = cfg,
		model = model,
		hum = hum,
		root = root,
		tracks = {},
		playing = nil,
		target = nil,
		patrol = section.model.PatrolA.Position,
		pausedUntil = 0,
		hop = true,
		baseHip = hum.HipHeight,
		sleepHip = 0.1 * s,
		legs = legs,
	}
end

local function buildGuard(section)
	local cfg = section.cfg
	if cfg.Look == "Chicken" then
		return buildChicken(section)
	end
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = cfg.Skin
	desc.LeftArmColor = cfg.Skin
	desc.RightArmColor = cfg.Skin
	desc.TorsoColor = cfg.Shirt
	desc.LeftLegColor = cfg.Pants or cfg.Shirt:Lerp(Color3.new(0, 0, 0), 0.4)
	desc.RightLegColor = cfg.Pants or cfg.Shirt:Lerp(Color3.new(0, 0, 0), 0.4)
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	rig.Name = cfg.Name
	local hum = rig:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = cfg.Title ~= "" and (cfg.Name .. " " .. cfg.Title) or cfg.Name
	hum.NameDisplayDistance = 120
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	rig:ScaleTo(cfg.Scale)

	local function attach(name, size, cf, color, material, parentPart, shape)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Massless = true
		p.CFrame = parentPart.CFrame * cf
		local w = Instance.new("WeldConstraint")
		w.Part0 = parentPart
		w.Part1 = p
		w.Parent = p
		p.Parent = rig
		return p
	end

	local hand = rig:FindFirstChild("RightHand")
	if cfg.Look == "Grandma" then
		local s = cfg.Scale
		local head = rig.Head
		local hy = head.Size.Y / 2
		local gray = Color3.fromRGB(215, 215, 220)
		-- Gray hair cap and a bun on top.
		attach("Hair", Vector3.new(1.25, 0.5, 1.25) * s, CFrame.new(0, hy - 0.1 * s, 0.05 * s), gray, Enum.Material.Fabric, head)
		attach("Bun", Vector3.new(0.7, 0.7, 0.7) * s, CFrame.new(0, hy + 0.25 * s, 0.25 * s), gray, Enum.Material.Fabric, head,
			Enum.PartType.Ball)
		-- Glasses.
		for _, x in { -0.22, 0.22 } do
			attach("Lens", Vector3.new(0.32, 0.26, 0.05) * s, CFrame.new(x * s, 0.08 * s, -head.Size.Z / 2 - 0.02 * s),
				Color3.fromRGB(30, 30, 35), Enum.Material.SmoothPlastic, head).Transparency = 0.3
		end
		-- A long dress over the legs.
		local torso = rig:FindFirstChild("LowerTorso")
		if torso then
			attach("Dress", Vector3.new(2.3, 2.2, 1.4) * s, CFrame.new(0, -1.1 * s, 0), cfg.Shirt, Enum.Material.Fabric, torso)
		end
		-- Rolling pin.
		if hand then
			attach("RollingPin", Vector3.new(2.6, 0.45, 0.45) * s, CFrame.new(0, -0.2 * s, -0.3 * s) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(220, 185, 140), Enum.Material.Wood, hand, Enum.PartType.Cylinder)
		end
	elseif cfg.Look == "Scientist" then
		local s = cfg.Scale
		local head = rig.Head
		local hy, hz = head.Size.Y / 2, head.Size.Z / 2
		local hairColor = Color3.fromRGB(235, 235, 240)
		local green = Color3.fromRGB(80, 255, 90)
		-- Wild spiky hair sticking out in every direction.
		local rng = Random.new(3)
		-- A ring of long spikes radiating outward, skipping the face...
		for i = 1, 12 do
			local yaw = i / 12 * math.pi * 2
			local facing = math.cos(yaw) > 0.75 -- yaw 0 points toward the face (-Z after the tilt below)
			if not facing then
				local tilt = rng:NextNumber(1.0, 1.35)
				attach("Spike", Vector3.new(0.26, 1.5, 0.26) * s,
					CFrame.new(0, hy * 0.55, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-tilt, 0, 0) * CFrame.new(0, 0.75 * s, 0),
					hairColor, Enum.Material.SmoothPlastic, head)
			end
		end
		-- ...and a few sticking straight up.
		for i = 1, 5 do
			local yaw = i / 5 * math.pi * 2
			attach("Spike", Vector3.new(0.26, 1.3, 0.26) * s,
				CFrame.new(0, hy, 0.1 * s) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-0.45, 0, 0) * CFrame.new(0, 0.6 * s, 0),
				hairColor, Enum.Material.SmoothPlastic, head)
		end
		attach("HairTop", Vector3.new(0.95, 0.25, 0.95) * s, CFrame.new(0, hy, 0.1 * s), hairColor, Enum.Material.SmoothPlastic, head)
		-- Glowing green goggles on a black strap.
		attach("GoggleStrap", Vector3.new(1.18, 0.14, 1.18) * s, CFrame.new(0, 0.12 * s, 0), Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic, head)
		for _, x in { -0.24, 0.24 } do
			attach("GoggleRim", Vector3.new(0.12, 0.42, 0.42) * s, CFrame.new(x * s, 0.12 * s, -hz - 0.04 * s) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(30, 30, 35), Enum.Material.Metal, head, Enum.PartType.Cylinder)
			attach("GoggleLens", Vector3.new(0.06, 0.32, 0.32) * s, CFrame.new(x * s, 0.12 * s, -hz - 0.1 * s) * CFrame.Angles(0, math.rad(90), 0),
				green, Enum.Material.Neon, head, Enum.PartType.Cylinder)
		end
		-- Lab coat tails hanging below the waist, with chemical splashes.
		local lower = rig:FindFirstChild("LowerTorso")
		local upper = rig:FindFirstChild("UpperTorso")
		if lower then
			for _, x in { -0.55, 0.55 } do
				attach("CoatTail", Vector3.new(0.95, 1.7, 1.15) * s, CFrame.new(x * s, -1 * s, 0.05 * s), cfg.Shirt, Enum.Material.Fabric, lower)
			end
			attach("Splash", Vector3.new(0.5, 0.4, 0.05) * s, CFrame.new(0.5 * s, -1.2 * s, -0.63 * s), green, Enum.Material.Neon, lower)
		end
		if upper then
			attach("Splash", Vector3.new(0.45, 0.35, 0.05) * s, CFrame.new(-0.45 * s, 0.1 * s, -upper.Size.Z / 2 - 0.02 * s), green, Enum.Material.Neon, upper)
			attach("Collar", Vector3.new(1.2, 0.3, 1.1) * s, CFrame.new(0, upper.Size.Y / 2 - 0.05 * s, 0), cfg.Shirt, Enum.Material.Fabric, upper)
		end
		-- A bubbling green potion flask in his hand.
		if hand then
			attach("Flask", Vector3.new(1.1, 0.75, 0.75) * s, CFrame.new(0, -0.6 * s, -0.2 * s) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(200, 240, 255), Enum.Material.Glass, hand, Enum.PartType.Cylinder).Transparency = 0.4
			attach("Potion", Vector3.new(0.7, 0.6, 0.6) * s, CFrame.new(0, -0.75 * s, -0.2 * s) * CFrame.Angles(0, 0, math.rad(90)),
				green, Enum.Material.Neon, hand, Enum.PartType.Cylinder)
			local potion = rig:FindFirstChild("Potion")
			if potion then
				local fx = Instance.new("ParticleEmitter")
				fx.Color = ColorSequence.new(green)
				fx.LightEmission = 1
				fx.Size = NumberSequence.new(0.25, 0)
				fx.Speed = NumberRange.new(1, 2)
				fx.Lifetime = NumberRange.new(0.6, 1)
				fx.Rate = 8
				fx.Parent = potion
			end
		end
	elseif hand then
		-- A club in the right hand.
		local s = cfg.Scale
		local club = Instance.new("Part")
		club.Name = "Club"
		club.Size = Vector3.new(0.5, 3.2, 0.5) * s
		club.Color = Color3.fromRGB(110, 75, 45)
		club.Material = Enum.Material.Wood
		club.CanCollide = false
		club.Massless = true
		club.CFrame = hand.CFrame * CFrame.Angles(math.rad(-70), 0, 0) * CFrame.new(0, 1.2 * s, 0)
		local knob = Instance.new("Part")
		knob.Name = "ClubHead"
		knob.Size = Vector3.new(1, 1.2, 1) * s
		knob.Color = Color3.fromRGB(90, 60, 35)
		knob.Material = Enum.Material.Wood
		knob.CanCollide = false
		knob.Massless = true
		knob.CFrame = club.CFrame * CFrame.new(0, 1.6 * s, 0)
		for _, p in { club, knob } do
			local w = Instance.new("WeldConstraint")
			w.Part0 = hand
			w.Part1 = p
			w.Parent = p
			p.Parent = rig
		end
	end
	if cfg.Crown then
		local head = rig:FindFirstChild("Head")
		local crown = Instance.new("Part")
		crown.Name = "Crown"
		crown.Size = Vector3.new(1.4, 0.6, 1.4) * cfg.Scale
		crown.Color = Color3.fromRGB(255, 210, 60)
		crown.Material = Enum.Material.Neon
		crown.CanCollide = false
		crown.Massless = true
		crown.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + crown.Size.Y / 2, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = crown
		w.Parent = crown
		crown.Parent = rig
	end

	local home = section.model.Center.Position
	rig:PivotTo(CFrame.lookAt(home + Vector3.new(0, 3 * cfg.Scale, 0), home + Vector3.new(1, 3 * cfg.Scale, 0)))
	rig.Parent = section.model
	local root = rig.HumanoidRootPart
	root:SetNetworkOwner(nil)
	hum.WalkSpeed = cfg.Speed * 0.5

	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local tracks = {}
	for name, id in ANIMS do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, a)
		if ok then
			track.Looped = true
			tracks[name] = track
		end
	end

	return {
		section = section,
		cfg = cfg,
		model = rig,
		hum = hum,
		root = root,
		tracks = tracks,
		playing = nil,
		target = nil,
		patrol = section.model.PatrolA.Position,
		pausedUntil = 0,
	}
end

local function playAnim(guard, name)
	if guard.playing == name then
		return
	end
	if guard.playing and guard.tracks[guard.playing] then
		guard.tracks[guard.playing]:Stop(0.2)
	end
	guard.playing = name
	if guard.tracks[name] then
		guard.tracks[name]:Play(0.2)
	end
end

-- Guards keep chasing a thief across the whole field and only give up once
-- the thief reaches the safe zone (the lobby strip in front of the pens).
local safeEdgeX = math.huge
local lobby = Map.GuardLand:FindFirstChild("Lobby")
if lobby then
	safeEdgeX = lobby.Position.X - lobby.Size.X / 2
end
for _, plot in plotList do
	local cf, size = plot.model:GetBoundingBox()
	safeEdgeX = math.min(safeEdgeX, cf.Position.X - size.X / 2)
end

local function inGuardZone(guard, pos)
	return pos.X < safeEdgeX
end

-- Guards only chase players carrying loot stolen from their own heap.
local function pickTarget(guard)
	local current = guard.target
	if current then
		local root = getRoot(current)
		local item = carrying[current]
		local data = item and items[item]
		if root and inGuardZone(guard, root.Position) and data and data.homeSection == guard.section then
			return current
		end
	end
	for player, item in carrying do
		local data = items[item]
		local root = getRoot(player)
		if data and data.homeSection == guard.section and root and inGuardZone(guard, root.Position) then
			return player
		end
	end
	return nil
end

local function catch(guard, player)
	local root = getRoot(player)
	if not root then
		return
	end
	local dir = (root.Position - guard.root.Position) * Vector3.new(1, 0, 1)
	Knockback:FireClient(player, dir.Magnitude > 0.1 and dir.Unit or guard.root.CFrame.LookVector)
	if carrying[player] then
		local name = carrying[player].Name
		dropItem(player)
		notify(player, "😵 " .. guard.cfg.Name .. " caught you! The " .. name .. " went back.")
	end
	guard.target = nil
	guard.pausedUntil = os.clock() + 1.5
end

-- Sleepy guards (Grandma) doze in a chair until someone steals from their heap.

local function headLabel(guard, name, text, color)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.fromScale(3, 1.5)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Enabled = false
	bb.Parent = guard.model.Head
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.Parent = bb
	return bb
end

local function fallAsleep(guard)
	guard.asleep = true
	if guard.seat then
		guard.seat:Sit(guard.hum)
	else
		-- Settle down on the ground with the legs tucked in.
		guard.hum:MoveTo(guard.root.Position)
		guard.hum.HipHeight = guard.sleepHip
		for _, leg in guard.legs do
			leg.Transparency = 1
		end
	end
	guard.zzz.Enabled = true
	guard.alert.Enabled = false
	playAnim(guard, "sit")
end

local function wakeUp(guard, thief)
	guard.asleep = false
	if guard.seat then
		guard.hum.Sit = false
		local weld = guard.seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	else
		guard.hum.HipHeight = guard.baseHip
		for _, leg in guard.legs do
			leg.Transparency = 0
		end
	end
	guard.zzz.Enabled = false
	guard.alert.Enabled = true
	playAnim(guard, "idle")
	-- She takes a moment to get up, giving the thief a head start.
	guard.pausedUntil = os.clock() + 0.8
	notify(thief, (guard.cfg.WakeEmoji or "") .. guard.cfg.Name .. " woke up! RUN!")
	task.delay(2, function()
		guard.alert.Enabled = false
	end)
end

for _, section in sections do
	local ok, guardOrErr = pcall(buildGuard, section)
	if ok then
		local guard = guardOrErr
		guards[section] = guard
		local chair = section.model:FindFirstChild("RockingChair")
		if section.cfg.Sleeps then
			guard.seat = chair and chair.SleepSeat
			guard.sleepPos = guard.seat and guard.seat.Position or section.model.Center.Position
			guard.zzz = headLabel(guard, "Zzz", section.cfg.ZzzText or "💤 Zzz", section.cfg.ZzzColor or Color3.fromRGB(180, 210, 255))
			if section.cfg.ZzzOffset then
				guard.zzz.StudsOffset = section.cfg.ZzzOffset
			end
			guard.alert = headLabel(guard, "Alert", "❗", Color3.fromRGB(255, 70, 70))
			if guard.seat then
				guard.model:PivotTo(guard.seat.CFrame * CFrame.new(0, 4, 0))
			end
			task.defer(fallAsleep, guard)
		end
	else
		warn("Failed to build guard " .. section.cfg.Name .. ": " .. tostring(guardOrErr))
	end
end

task.spawn(function()
	while true do
		local now = os.clock()
		for _, guard in guards do
			if guard.model.Parent then
				local hum, root = guard.hum, guard.root
				if guard.asleep then
					-- Stays dozing until a thief takes something from her heap.
					local thief = pickTarget(guard)
					if thief then
						guard.target = thief
						wakeUp(guard, thief)
					end
				elseif now < guard.pausedUntil then
					hum:MoveTo(root.Position)
					playAnim(guard, "idle")
				else
					guard.target = pickTarget(guard)
					local targetRoot = guard.target and getRoot(guard.target)
					if targetRoot then
						hum.WalkSpeed = guard.cfg.Speed
						hum:MoveTo(targetRoot.Position)
						playAnim(guard, "run")
						local flat = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
						if flat.Magnitude < Config.GuardCatchRange + guard.cfg.Scale then
							catch(guard, guard.target)
						end
					elseif guard.sleepPos then
						-- Nobody to chase: go back to the sleep spot and doze off.
						local flat = (guard.sleepPos - root.Position) * Vector3.new(1, 0, 1)
						if flat.Magnitude < 3.5 then
							fallAsleep(guard)
						else
							hum.WalkSpeed = guard.cfg.Speed * 0.5
							hum:MoveTo(guard.sleepPos)
							playAnim(guard, "walk")
						end
					else
						-- Patrol back and forth in front of the section.
						local model = guard.section.model
						local flat = (guard.patrol - root.Position) * Vector3.new(1, 0, 1)
						if flat.Magnitude < 4 then
							guard.patrol = guard.patrol == model.PatrolA.Position and model.PatrolB.Position
								or model.PatrolA.Position
						end
						hum.WalkSpeed = guard.cfg.Speed * 0.5
						hum:MoveTo(guard.patrol)
						playAnim(guard, "walk")
					end
				end
			end
		end
		task.wait(0.1)
	end
end)

-- Chickens hop while they walk.
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, guard in guards do
		if guard.hop and not guard.asleep then
			local moving = guard.root.AssemblyLinearVelocity.Magnitude > 1
			guard.hum.HipHeight = guard.baseHip + (moving and math.abs(math.sin(t * 14)) * 0.7 or 0)
		end
	end
end)

-- Lava (Volcano stage) -----------------------------------------------------

for _, lava in CollectionService:GetTagged("Lava") do
	lava.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end
		local _, hum = getRoot(player)
		if hum then
			hum.Health = 0
			notify(player, "🔥 You fell in the lava!")
		end
	end)
end

-- Treadmills -------------------------------------------------------------
-- Each pen has its own treadmill out front; only the pen's owner trains on it.
-- Stepping on locks you in place running, earning XP until you jump off.

local mounted = {} -- [Player] = plot whose treadmill they're on
local leftAt = {} -- [Player] = os.clock() when they last hopped off

local function updateBelt(plot)
	local mill = plot.model:FindFirstChild("Treadmill")
	if not mill then
		return
	end
	local owner = plot.owner
	mill.Console.Label.Text.Text = owner and (owner.DisplayName .. "'s Treadmill") or "\u{1F3C3} Treadmill"
	-- Clients scroll the belt slats while someone is running on it.
	local running = owner ~= nil and mounted[owner] == plot
	mill.Belt:SetAttribute("Running", running)
	mill.Belt:SetAttribute("Speed", running and Config.WalkSpeed(owner:GetAttribute("SpeedLevel") or 0, false) or 0)
end

local function onOwnTreadmill(player, root)
	local plot = playerPlot[player]
	local mill = plot and plot.model:FindFirstChild("Treadmill")
	if not mill then
		return false
	end
	local p = mill.Belt.CFrame:PointToObjectSpace(root.Position)
	local half = mill.Belt.Size / 2
	return math.abs(p.X) < half.X and math.abs(p.Z) < half.Z and p.Y > 0 and p.Y < 6
end

local function mount(player, plot)
	local root, hum = getRoot(player)
	local belt = plot.model.Treadmill.Belt
	-- Stand in the middle of the belt facing the console, held in place.
	local height = belt.Size.Y / 2 + hum.HipHeight + root.Size.Y / 2
	root.Anchored = true
	player.Character:PivotTo(belt.CFrame * CFrame.new(0, height, 0))
	mounted[player] = plot
	player:SetAttribute("OnTreadmill", true)
	updateBelt(plot)
	notify(player, "\u{1F3C3} Training! Press JUMP to get off.")
end

local function dismount(player)
	local plot = mounted[player]
	if not plot then
		return
	end
	mounted[player] = nil
	leftAt[player] = os.clock()
	player:SetAttribute("OnTreadmill", false)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local belt = plot.model.Treadmill.Belt
		-- Step off behind the treadmill.
		char:PivotTo(belt.CFrame * CFrame.new(0, 3, belt.Size.Z / 2 + 3))
		root.Anchored = false
	end
	updateBelt(plot)
end

Remotes.LeaveTreadmill.OnServerEvent:Connect(dismount)

task.spawn(function()
	local TICK = 0.25
	while true do
		task.wait(TICK)
		for _, player in Players:GetPlayers() do
			local root = getRoot(player)
			local level = player:GetAttribute("SpeedLevel") or 0
			if mounted[player] then
				if not root then
					mounted[player] = nil
					player:SetAttribute("OnTreadmill", false)
				else
					local mult = Config.TreadmillXPMultiplier(player:GetAttribute("TreadmillLevel") or 0)
					* (player:GetAttribute("XPBoost") or 1)
					local xp = (player:GetAttribute("SpeedXP") or 0) + Config.TreadmillXPPerSecond * mult * TICK
					local needed = Config.SpeedXPNeeded(level)
					if xp >= needed then
						xp -= needed
						level += 1
						player:SetAttribute("SpeedLevel", level)
						applySpeed(player)
						updateBelt(mounted[player])
						notify(player, "\u{26A1} SPEED UP! Level " .. level .. " (walk speed " .. Config.WalkSpeed(level, false) .. ")")
					end
					player:SetAttribute("SpeedXP", xp)
				end
			elseif root and onOwnTreadmill(player, root) and not carrying[player]
				and os.clock() - (leftAt[player] or 0) > 1 then
				mount(player, playerPlot[player])
			end
		end
	end
end)

-- Players & pens ----------------------------------------------------------

local function updateSign(plot)
	plot.model.Sign.Gui.Text.Text = plot.owner and (plot.owner.DisplayName .. "'s Pen") or "Empty Pen"
end

local function spawnAtPlot(player, char)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if root then
		task.wait()
		local sp = plot.model.SpawnPoint.CFrame
		-- Face toward the open front of the pen.
		char:PivotTo(sp * CFrame.new(0, 4, 0) * CFrame.Angles(0, math.pi, 0))
	end
end

-- Saving --------------------------------------------------------------------
-- Saves cash, speed, treadmill level, unlocked nests, and every pet/egg in the
-- pen (with egg hatch time left). Loaded on join; saved on leave, every
-- minute, and on server shutdown. A player whose data failed to load is never
-- saved, so a load hiccup can't wipe their progress.

local DataStoreService = game:GetService("DataStoreService")
local okData, playerStore = pcall(DataStoreService.GetDataStore, DataStoreService, "PlayerData_v1")
if not okData then
	warn("Saving: DataStore unavailable (" .. tostring(playerStore) .. ")")
	playerStore = nil
end
local AUTOSAVE_INTERVAL = 60
local dataLoaded = {} -- [Player] = true once their save was loaded (safe to save)
local pendingSaves = 0

local function saveKey(player)
	return "u_" .. player.UserId
end

local function petKeyOf(t)
	for key, pet in Config.Pets do
		if pet == t then
			return key
		end
	end
	return nil
end

-- Captures the player's progress right now (no yielding).
local function snapshot(player)
	local plot = playerPlot[player]
	local cash = getCash(player)
	local data = {
		Version = 1,
		Cash = cash and cash.Value or 0,
		SpeedLevel = player:GetAttribute("SpeedLevel") or 0,
		SpeedXP = player:GetAttribute("SpeedXP") or 0,
		TreadmillLevel = player:GetAttribute("TreadmillLevel") or 0,
		Unlocked = plot and plot.unlocked or nil,
		Items = {},
		NoPlot = plot == nil,
	}
	if plot then
		for slot, item in plot.slots do
			local d = items[item]
			if d and d.state == "Pedestal" then
				if d.kind == "Pet" then
					local key = petKeyOf(d.type)
					if key then
						table.insert(data.Items, { Slot = slot, Kind = "Pet", Id = key })
					end
				else
					table.insert(data.Items, { Slot = slot, Kind = "Egg", Id = d.type.Name, HatchLeft = d.hatchLeft })
				end
			end
		end
	end
	return data
end

local function savePlayer(player)
	if not playerStore or not dataLoaded[player] then
		return
	end
	local snap = snapshot(player)
	local key = saveKey(player)
	local userId = player.UserId
	pendingSaves += 1
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, err = pcall(playerStore.UpdateAsync, playerStore, key, function(old)
				-- No pen this session (all were taken): keep the pen saved last time.
				if snap.NoPlot and type(old) == "table" then
					snap.Items = old.Items
					snap.Unlocked = old.Unlocked
				end
				snap.NoPlot = nil
				return snap, { userId }
			end)
			if ok then
				break
			end
			warn("Saving " .. key .. " failed (try " .. attempt .. "): " .. tostring(err))
			task.wait(2)
		end
		pendingSaves -= 1
	end)
end

local function loadPlayer(player)
	if not playerStore then
		return
	end
	local ok, saved
	for _ = 1, 3 do
		ok, saved = pcall(playerStore.GetAsync, playerStore, saveKey(player))
		if ok then
			break
		end
		task.wait(2)
	end
	if not player.Parent then
		return
	end
	if not ok then
		warn("Loading " .. saveKey(player) .. " failed: " .. tostring(saved))
		if RunService:IsStudio() then
			notify(player, "⚠️ Saving is off in Studio - turn on Studio Access to API Services to test it.")
		else
			notify(player, "⚠️ Couldn't load your save - progress this session won't be saved. Try rejoining.")
		end
		return
	end

	if type(saved) == "table" then
		local cash = getCash(player)
		if cash and type(saved.Cash) == "number" then
			cash.Value = saved.Cash
		end
		player:SetAttribute("SpeedLevel", saved.SpeedLevel or 0)
		player:SetAttribute("SpeedXP", saved.SpeedXP or 0)
		player:SetAttribute("TreadmillLevel", saved.TreadmillLevel or 0)
		applySpeed(player)

		local plot = playerPlot[player]
		if plot then
			plot.unlocked = math.max(plot.unlocked, saved.Unlocked or Config.StartingSlots)
			for _, rec in saved.Items or {} do
				local t = (rec.Kind == "Pet" and Config.Pets[rec.Id]) or (rec.Kind == "Egg" and Config.FindEgg(rec.Id)) or nil
				if t then
					local slot = rec.Slot
					if type(slot) ~= "number" or slot > plot.unlocked or plot.slots[slot] ~= nil then
						slot = freeSlot(plot)
					end
					if slot then
						local item = makeItem(rec.Kind, t)
						if rec.Kind == "Egg" and type(rec.HatchLeft) == "number" then
							items[item].hatchLeft = math.max(1, rec.HatchLeft)
						end
						placeOnPedestal(item, plot, slot)
					end
				end
			end
			refreshPedestals(plot)
			updateBelt(plot)
		end
		notify(player, "💾 Welcome back! Your progress was loaded.")
	end
	dataLoaded[player] = true
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in Players:GetPlayers() do
			savePlayer(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		savePlayer(player)
		dataLoaded[player] = nil
	end
	local start = os.clock()
	while pendingSaves > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = Config.StartingCash
	cash.Parent = stats
	player:SetAttribute("Income", 0)
	player:SetAttribute("SpeedLevel", 0)
	player:SetAttribute("SpeedXP", 0)
	player:SetAttribute("TreadmillLevel", 0)

	for _, plot in plotList do
		if not plot.owner then
			plot.owner = player
			plot.unlocked = Config.StartingSlots
			plot.model:SetAttribute("OwnerId", player.UserId)
			playerPlot[player] = plot
			updateSign(plot)
			refreshPedestals(plot)
			updateBelt(plot)
			break
		end
	end

	local function onCharacter(char)
		local hum = char:WaitForChild("Humanoid")
		applySpeed(player)
		local wasOn = mounted[player]
		if wasOn then
			mounted[player] = nil
			player:SetAttribute("OnTreadmill", false)
			updateBelt(wasOn)
		end
		hum.Died:Connect(function()
			if carrying[player] then
				dropItem(player)
			end
		end)
		spawnAtPlot(player, char)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	if not playerPlot[player] then
		notify(player, "All pens are taken - you can still steal, but you can't keep anything!")
	end

	loadPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	-- Snapshot their pen before it's cleared below.
	savePlayer(player)
	dataLoaded[player] = nil
	if carrying[player] then
		dropItem(player)
	end
	mounted[player] = nil
	leftAt[player] = nil
	for _, guard in guards do
		if guard.target == player then
			guard.target = nil
		end
	end
	local plot = playerPlot[player]
	playerPlot[player] = nil
	if not plot then
		return
	end
	for slot, item in plot.slots do
		destroyItem(item)
		plot.slots[slot] = nil
	end
	plot.owner = nil
	plot.unlocked = Config.StartingSlots
	plot.model:SetAttribute("OwnerId", nil)
	updateSign(plot)
	refreshPedestals(plot)
	updateBelt(plot)
end)

for _, plot in plotList do
	refreshPedestals(plot)
	updateBelt(plot)
end

-- Income & hatching -------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		for _, plot in plotList do
			local owner = plot.owner
			if owner then
				local income = 0
				local toHatch = {}
				for _, item in plot.slots do
					local data = items[item]
					if data and data.state == "Pedestal" then
						if data.kind == "Egg" then
							data.hatchLeft -= 1
							if data.hatchLeft <= 0 then
								table.insert(toHatch, item)
							else
								setStatus(item, hatchWord(data.type) .. " in " .. data.hatchLeft .. "s", Color3.fromRGB(255, 230, 120))
							end
						end
						income += incomeOf(data)
					end
				end
				for _, egg in toHatch do
					hatch(egg)
				end
				income *= owner:GetAttribute("CashMultiplier") or 1
				owner:SetAttribute("Income", income)
				local cash = getCash(owner)
				if cash then
					cash.Value += income
				end
			end
		end
	end
end)

-- Per-frame: deposit carried items in your pen, expire loose items.
local depositTimer = 0
RunService.Heartbeat:Connect(function(dt)
	depositTimer += dt
	if depositTimer < 0.15 then
		return
	end
	depositTimer = 0
	local now = os.clock()
	for item, data in items do
		if data.state == "Loose" and now - data.droppedAt > Config.LooseLifetime then
			destroyItem(item)
		end
	end
	for player, item in carrying do
		local root = getRoot(player)
		local plot = playerPlot[player]
		if not root or not items[item] then
			dropItem(player)
		elseif plot then
			local localPos = plot.model.Floor.CFrame:PointToObjectSpace(root.Position)
			if math.abs(localPos.X) < 21 and math.abs(localPos.Z) < 21 and localPos.Y < 15 then
				local slot = freeSlot(plot)
				if slot then
					local data = items[item]
					local section = data.homeSection
					if section and section.slots[data.homePad] == item then
						section.slots[data.homePad] = nil
						section.respawnAt[data.homePad] = now + Config.LootRespawnTime
					end
					detach(player)
					placeOnPedestal(item, plot, slot)
					if data.kind == "Egg" then
						notify(player, "✅ " .. item.Name .. " secured! " .. hatchWord(data.type) .. " in " .. data.hatchLeft .. "s...")
					else
						notify(player, "✅ " .. item.Name .. " secured! +$" .. Config.Format(data.type.Income) .. "/s")
					end
				end
			end
		end
	end
end)

-- Robux shop ----------------------------------------------------------------

local MarketplaceService = game:GetService("MarketplaceService")

local function findById(list, id)
	for _, entry in list do
		if entry.Id ~= 0 and entry.Id == id then
			return entry
		end
	end
	return nil
end

local function setSpeedLevel(player, level)
	level = math.max(0, math.floor(level))
	player:SetAttribute("SpeedLevel", level)
	player:SetAttribute("SpeedXP", 0)
	applySpeed(player)
	local plot = playerPlot[player]
	if plot then
		updateBelt(plot)
	end
	return level
end

local function grantProduct(player, product)
	if product.Kind == "Cash" then
		getCash(player).Value += product.Amount
		notify(player, "\u{1F4B0} Thanks for your purchase! +$" .. Config.Format(product.Amount))
	elseif product.Kind == "Speed" then
		local level = setSpeedLevel(player, (player:GetAttribute("SpeedLevel") or 0) + product.Amount)
		notify(player, "\u{26A1} Thanks for your purchase! Speed is now level " .. level)
	end
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = findById(Config.Products, receipt.ProductId)
	if not player or not product or not getCash(player) then
		-- Roblox retries later (e.g. when the player rejoins).
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantProduct(player, product)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function applyPass(player, pass)
	if pass.Kind == "DoubleCash" then
		player:SetAttribute("CashMultiplier", 2)
	elseif pass.Kind == "DoubleXP" then
		player:SetAttribute("XPBoost", 2)
	end
end

local function checkPasses(player)
	for _, pass in Config.GamePasses do
		if pass.Id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns then
				applyPass(player, pass)
			end
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local pass = purchased and findById(Config.GamePasses, passId)
	if pass then
		applyPass(player, pass)
		if pass.Kind == "Donation" then
			notify(player, "\u{2764}\u{FE0F} Thank you so much for the donation!")
		else
			notify(player, "\u{1F389} You now own " .. pass.Name .. "!")
		end
	end
end)

-- Admin panel ---------------------------------------------------------------

local function isAdmin(player)
	if table.find(Config.Admins, player.UserId) then
		return true
	end
	-- Only the game's owner (plus anyone listed in Config.Admins).
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function findPlayer(caller, name)
	if not name or name == "" then
		return caller
	end
	name = string.lower(name)
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name):sub(1, #name) == name or string.lower(p.DisplayName):sub(1, #name) == name then
			return p
		end
	end
	return nil
end

local adminCommands = {}

function adminCommands.Cash(caller, target, value)
	local amount = tonumber(value) or 1000
	getCash(target).Value += amount
	return "Gave $" .. Config.Format(amount) .. " to " .. target.DisplayName
end

function adminCommands.Speed(_, target, value)
	local level = setSpeedLevel(target, tonumber(value) or 20)
	return target.DisplayName .. " is now speed level " .. level
end

function adminCommands.Nests(_, target)
	local plot = playerPlot[target]
	if not plot then
		return target.DisplayName .. " has no pen"
	end
	plot.unlocked = #plot.pedestals
	refreshPedestals(plot)
	return "Unlocked all nests for " .. target.DisplayName
end

function adminCommands.Reset(_, target)
	getCash(target).Value = Config.StartingCash
	target:SetAttribute("TreadmillLevel", 0)
	setSpeedLevel(target, 0)
	local plot = playerPlot[target]
	if plot then
		for slot, item in plot.slots do
			destroyItem(item)
			plot.slots[slot] = nil
		end
		plot.unlocked = Config.StartingSlots
		refreshPedestals(plot)
	end
	return "Reset " .. target.DisplayName
end

function adminCommands.Stage(_, target, value)
	local n = math.clamp(math.floor(tonumber(value) or 1), 1, #Config.Guards)
	local char = target.Character
	if not char or mounted[target] then
		return "Can't teleport " .. target.DisplayName .. " right now"
	end
	local x = Config.StageEast(n) - 6
	char:PivotTo(CFrame.lookAt(Vector3.new(x, 5, 0), Vector3.new(x - 10, 5, 0)))
	return "Teleported " .. target.DisplayName .. " to stage " .. n
end

function adminCommands.Restock()
	for _, section in sections do
		table.clear(section.respawnAt)
	end
	return "Restocking every heap"
end

function adminCommands.Kick(caller, target)
	if target == caller then
		return "You can't kick yourself"
	end
	target:Kick("You were kicked by an admin.")
	return "Kicked " .. target.Name
end

Remotes.AdminCommand.OnServerInvoke = function(player, command, targetName, value)
	if not isAdmin(player) then
		return "You are not an admin."
	end
	local handler = adminCommands[command]
	if type(handler) ~= "function" then
		return "Unknown command"
	end
	local target = findPlayer(player, targetName)
	if not target then
		return "No player named '" .. tostring(targetName) .. "'"
	end
	local ok, result = pcall(handler, player, target, value)
	return ok and result or ("Error: " .. tostring(result))
end

local function onJoinShopAdmin(player)
	player:SetAttribute("IsAdmin", isAdmin(player))
	task.spawn(checkPasses, player)
end
Players.PlayerAdded:Connect(onJoinShopAdmin)
for _, player in Players:GetPlayers() do
	onJoinShopAdmin(player)
end

-- Follow reward -------------------------------------------------------------
-- Follower lists need a logged-in account, but follow COUNTS are public.
-- When a player opens the panel we note the creator's follower count and the
-- player's own followings count. To claim, BOTH must have gone up: the player
-- followed someone, and the creator gained a follower, at the same time. Each
-- new creator follow pays out only once per server (creditedCount), and each
-- player can claim once ever (DataStore).

local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ClaimFollowReward = Remotes.ClaimFollowReward

local okStore, followStore = pcall(DataStoreService.GetDataStore, DataStoreService, "FollowReward")
if not okStore then
	warn("Follow reward: DataStore unavailable (" .. tostring(followStore) .. ")")
	followStore = nil
end

local creatorId = game.CreatorType == Enum.CreatorType.User and game.CreatorId or 0
local creatorName = "the creator"
task.spawn(function()
	if creatorId ~= 0 then
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, creatorId)
		if ok and name then
			creatorName = "@" .. name
		end
	end
	ReplicatedStorage:SetAttribute("CreatorName", creatorName)
end)

local followClaimed = {} -- [Player] = true once claimed
local followBaseline = {} -- [Player] = { creator = followers, mine = followings } when panel opened
local lastFollowCheck = {}
local creditedCount = 0 -- highest follower count already paid out in this server

-- kind = "followers" or "followings"
local function getCount(userId, kind)
	local url = "https://" .. Config.FollowProxyHost .. "/v1/users/" .. userId .. "/" .. kind .. "/count"
	local ok, body = pcall(HttpService.GetAsync, HttpService, url, true)
	if not ok then
		return nil, tostring(body)
	end
	local okJson, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not okJson or type(data) ~= "table" or type(data.count) ~= "number" then
		return nil, "bad response"
	end
	return data.count
end

local function loadFollowClaim(player)
	if not followStore then
		return
	end
	local ok, value = pcall(followStore.GetAsync, followStore, tostring(player.UserId))
	if ok and value then
		followClaimed[player] = true
		player:SetAttribute("FollowRewardClaimed", true)
	end
end

local function claimFollow(player)
	local baseline = followBaseline[player]
	if not baseline then
		return false, "Close and reopen this panel, then follow and claim."
	end
	if os.clock() - (lastFollowCheck[player] or -math.huge) < 8 then
		return false, "Please wait a few seconds before checking again."
	end
	lastFollowCheck[player] = os.clock()
	if not followStore then
		return false, "Saving is unavailable right now, try again later."
	end
	local mine, err = getCount(player.UserId, "followings")
	local count, err2 = getCount(creatorId, "followers")
	if not mine or not count then
		warn("Follow reward check failed: " .. tostring(err or err2))
		return false, "Couldn't check right now, try again in a minute."
	end
	local floor = math.max(baseline.creator, creditedCount)
	if mine <= baseline.mine or count <= floor then
		return false, "You haven't followed " .. creatorName .. " yet! Follow, wait a moment, then claim."
	end
	-- Reserve this follow before the (yielding) save so it can't pay out twice.
	creditedCount = floor + 1
	local alreadyClaimed = false
	local ok, saveErr = pcall(followStore.UpdateAsync, followStore, tostring(player.UserId), function(old)
		if old then
			alreadyClaimed = true
			return nil
		end
		return os.time()
	end)
	if not ok then
		creditedCount -= 1
		warn("Follow reward save failed: " .. tostring(saveErr))
		return false, "Couldn't save your claim, try again later."
	end
	followClaimed[player] = true
	player:SetAttribute("FollowRewardClaimed", true)
	if alreadyClaimed then
		creditedCount -= 1
		return false, "You already claimed this reward!"
	end
	local cash = getCash(player)
	if cash then
		cash.Value += Config.FollowRewardCash
	end
	notify(player, "⭐ Thanks for following! +$" .. Config.Format(Config.FollowRewardCash))
	return true, "Claimed +$" .. Config.Format(Config.FollowRewardCash) .. "!"
end

-- action "open": the panel was opened (record the baseline); "claim": check.
ClaimFollowReward.OnServerInvoke = function(player, action)
	if followClaimed[player] then
		return false, "You already claimed this reward!"
	end
	if creatorId == 0 then
		return false, "Follow reward isn't available in this game."
	end
	if player.UserId == creatorId then
		return false, "You can't follow yourself!"
	end
	if action == "open" then
		if not followBaseline[player] then
			local creatorCount = getCount(creatorId, "followers")
			local mine = getCount(player.UserId, "followings")
			if not creatorCount or not mine then
				return false, "Couldn't reach Roblox, try reopening in a minute."
			end
			followBaseline[player] = { creator = creatorCount, mine = mine }
		end
		return true, ""
	elseif action == "claim" then
		return claimFollow(player)
	end
	return false, ""
end

Players.PlayerAdded:Connect(loadFollowClaim)
for _, player in Players:GetPlayers() do
	task.spawn(loadFollowClaim, player)
end
Players.PlayerRemoving:Connect(function(player)
	followClaimed[player] = nil
	followBaseline[player] = nil
	lastFollowCheck[player] = nil
end)

