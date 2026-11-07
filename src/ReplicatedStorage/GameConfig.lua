-- Eggs are stolen from guarded heaps. In your pen they incubate, then hatch
-- into a random pet from their pool. Pets earn cash every second.
local Config = {}

Config.StartingCash = 100
-- Speed levels are earned by running on treadmills. Each level adds
-- SpeedPerLevel walk speed. Carrying an item slows you to CarrySpeedFactor.
Config.BaseSpeed = 16
Config.SpeedPerLevel = 1
Config.CarrySpeedFactor = 0.75

-- Each pen has its own treadmill. Standing on it locks you in place running
-- and earns speed XP until you jump off.
Config.TreadmillXPPerSecond = 3
Config.LooseLifetime = 30
Config.SellRefund = 0.5

-- Pen nests: you start with a few and buy the rest with cash.
Config.StartingSlots = 3
function Config.SlotCost(slot)
	return math.floor(250 * 2.2 ^ (slot - Config.StartingSlots - 1))
end

-- Treadmill upgrades: each level adds +50% treadmill XP.
Config.MaxTreadmillLevel = 10
function Config.TreadmillUpgradeCost(level)
	return math.floor(300 * 2.4 ^ level)
end
function Config.TreadmillXPMultiplier(level)
	return 1 + 0.5 * level
end

Config.Pets = {
	Puppy = { Name = "Puppy", Rarity = "Common", Income = 3,
		Color = Color3.fromRGB(235, 220, 195), Accent = Color3.fromRGB(150, 100, 60), Ears = "Floppy",
		TextColor = Color3.fromRGB(230, 230, 230) },
	Husky = { Name = "Husky", Rarity = "Uncommon", Income = 7,
		Color = Color3.fromRGB(130, 135, 145), Accent = Color3.fromRGB(245, 245, 250), Ears = "Pointy",
		TextColor = Color3.fromRGB(120, 230, 120) },
	BlackCat = { Name = "Black Cat", Rarity = "Uncommon", Income = 7,
		Color = Color3.fromRGB(40, 40, 48), Accent = Color3.fromRGB(150, 110, 200), Ears = "Pointy",
		TextColor = Color3.fromRGB(120, 230, 120) },
	Kitty = { Name = "Kitty", Rarity = "Uncommon", Income = 8,
		Color = Color3.fromRGB(245, 160, 70), Accent = Color3.fromRGB(255, 235, 210), Ears = "Pointy",
		TextColor = Color3.fromRGB(120, 230, 120) },
	Bunny = { Name = "Bunny", Rarity = "Rare", Income = 20,
		Color = Color3.fromRGB(255, 205, 225), Accent = Color3.fromRGB(255, 255, 255), Ears = "Long",
		TextColor = Color3.fromRGB(80, 170, 255) },
	Fox = { Name = "Fox", Rarity = "Epic", Income = 60,
		Color = Color3.fromRGB(230, 100, 30), Accent = Color3.fromRGB(255, 250, 240), Ears = "Pointy", BigTail = true,
		TextColor = Color3.fromRGB(190, 90, 255) },
	Panda = { Name = "Panda", Rarity = "Legendary", Income = 180,
		Color = Color3.fromRGB(250, 250, 250), Accent = Color3.fromRGB(30, 30, 35), Ears = "Round", Scale = 1.15,
		TextColor = Color3.fromRGB(255, 190, 40) },
	Dragon = { Name = "Dragon", Rarity = "Mythic", Income = 600,
		Color = Color3.fromRGB(60, 180, 90), Accent = Color3.fromRGB(255, 210, 60), Ears = "Horns", Wings = true, Scale = 1.25,
		TextColor = Color3.fromRGB(255, 80, 80), Glow = true },
	Unicorn = { Name = "Unicorn", Rarity = "Secret", Income = 2000,
		Color = Color3.fromRGB(255, 255, 255), Accent = Color3.fromRGB(255, 100, 200), Ears = "Pointy", Horn = true, Mane = true,
		Wings = true, Scale = 1.3, TextColor = Color3.fromRGB(255, 255, 255), Glow = true },
	-- Only from the rare night eggs:
	Phoenix = { Name = "Phoenix", Rarity = "Eternal", Income = 8000,
		Color = Color3.fromRGB(255, 90, 30), Accent = Color3.fromRGB(255, 220, 60), Ears = "Pointy", Wings = true, BigTail = true,
		Scale = 1.35, TextColor = Color3.fromRGB(255, 140, 40), Glow = true },
	Seraph = { Name = "Seraph", Rarity = "Divine", Income = 30000,
		Color = Color3.fromRGB(255, 250, 235), Accent = Color3.fromRGB(255, 215, 90), Ears = "Long", Wings = true, Horn = true,
		Mane = true, Scale = 1.45, TextColor = Color3.fromRGB(255, 240, 150), Glow = true },
}
-- A pet sells for this many seconds of its income.
Config.PetSellSeconds = 15

-- Weight = how often the egg shows up on a heap (among that stage's eggs).
-- Hatches = weighted pet pool.
-- Shape = "Box" items are pet boxes: they "open" instead of hatch.
Config.Eggs = {
	{ Name = "Cardboard Box", Rarity = "Common", Price = 40, HatchTime = 10, Weight = 50, Shape = "Box",
		Color = Color3.fromRGB(190, 145, 95), Spots = Color3.fromRGB(225, 200, 150), Material = Enum.Material.SmoothPlastic,
		TextColor = Color3.fromRGB(230, 230, 230), Hatches = { Puppy = 55, Kitty = 45 } },
	{ Name = "Gift Box", Rarity = "Uncommon", Price = 200, HatchTime = 18, Weight = 25, Shape = "Box",
		Color = Color3.fromRGB(220, 60, 70), Spots = Color3.fromRGB(255, 215, 70), Material = Enum.Material.SmoothPlastic,
		TextColor = Color3.fromRGB(120, 230, 120), Hatches = { Puppy = 25, Kitty = 25, Husky = 25, BlackCat = 25 } },
	{ Name = "Common Egg", Rarity = "Common", Price = 50, HatchTime = 10, Weight = 50,
		Color = Color3.fromRGB(245, 240, 225), Spots = Color3.fromRGB(200, 190, 170), Material = Enum.Material.SmoothPlastic,
		TextColor = Color3.fromRGB(230, 230, 230), Hatches = { Puppy = 70, Kitty = 25, Bunny = 5 } },
	{ Name = "Speckled Egg", Rarity = "Uncommon", Price = 250, HatchTime = 20, Weight = 25,
		Color = Color3.fromRGB(215, 185, 140), Spots = Color3.fromRGB(120, 85, 50), Material = Enum.Material.SmoothPlastic,
		TextColor = Color3.fromRGB(120, 230, 120), Hatches = { Kitty = 50, Bunny = 35, Fox = 15 } },
	{ Name = "Ocean Egg", Rarity = "Rare", Price = 1000, HatchTime = 30, Weight = 12,
		Color = Color3.fromRGB(60, 150, 240), Spots = Color3.fromRGB(180, 230, 255), Material = Enum.Material.Glass,
		TextColor = Color3.fromRGB(80, 170, 255), Hatches = { Bunny = 40, Fox = 45, Panda = 15 } },
	{ Name = "Lava Egg", Rarity = "Epic", Price = 5000, HatchTime = 45, Weight = 7,
		Color = Color3.fromRGB(60, 30, 25), Spots = Color3.fromRGB(255, 110, 30), Material = Enum.Material.CrackedLava,
		TextColor = Color3.fromRGB(190, 90, 255), Hatches = { Fox = 40, Panda = 45, Dragon = 15 } },
	{ Name = "Galaxy Egg", Rarity = "Legendary", Price = 20000, HatchTime = 60, Weight = 4,
		Color = Color3.fromRGB(70, 30, 140), Spots = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic,
		TextColor = Color3.fromRGB(255, 190, 40), Hatches = { Panda = 50, Dragon = 40, Unicorn = 10 }, Glow = true },
	{ Name = "Golden Egg", Rarity = "Mythic", Price = 75000, HatchTime = 90, Weight = 1.5,
		Color = Color3.fromRGB(255, 205, 50), Spots = Color3.fromRGB(255, 250, 200), Material = Enum.Material.Foil,
		TextColor = Color3.fromRGB(255, 80, 80), Hatches = { Dragon = 60, Unicorn = 40 }, Glow = true },
	-- Rare night eggs: never on heaps (Weight 0); see Config.NightRareEggs.
	{ Name = "Secret Egg", Rarity = "Secret", Price = 250000, HatchTime = 120, Weight = 0,
		Color = Color3.fromRGB(30, 25, 40), Spots = Color3.fromRGB(255, 100, 200), Material = Enum.Material.SmoothPlastic,
		TextColor = Color3.fromRGB(255, 255, 255), Hatches = { Dragon = 30, Unicorn = 70 }, Glow = true },
	{ Name = "Eternal Egg", Rarity = "Eternal", Price = 1000000, HatchTime = 150, Weight = 0,
		Color = Color3.fromRGB(255, 110, 30), Spots = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon,
		TextColor = Color3.fromRGB(255, 140, 40), Hatches = { Unicorn = 40, Phoenix = 60 }, Glow = true },
	{ Name = "Divine Egg", Rarity = "Divine", Price = 5000000, HatchTime = 180, Weight = 0,
		Color = Color3.fromRGB(255, 250, 230), Spots = Color3.fromRGB(255, 210, 80), Material = Enum.Material.Neon,
		TextColor = Color3.fromRGB(255, 240, 150), Hatches = { Phoenix = 40, Seraph = 60 }, Glow = true },
}

function Config.FindEgg(name)
	for _, e in Config.Eggs do
		if e.Name == name then
			return e
		end
	end
	return nil
end

-- Stages run west from the pens: each one deeper is harder, with rarer loot
-- and faster guards (NPCs a bit bigger than players). Each stage has two
-- guarded heaps of eggs (sometimes already-hatched pets). Carry speed is 75%
-- of walk speed, so train on treadmills to outrun later guards.
Config.LootRespawnTime = 8
-- Day/night cycle: steal during the day; at night every guarded heap is
-- cleared and restocked with fresh loot when the next day starts.
Config.DayLength = 300 -- seconds
Config.NightLength = 20 -- seconds
-- Each nightfall there's this chance a rare egg appears somewhere in a random
-- biome. It stays until the next nightfall; that biome's guard protects it.
Config.NightRareEggChance = 0.5
Config.NightRareEggs = {
	{ Name = "Secret Egg", Weight = 70 },
	{ Name = "Eternal Egg", Weight = 25 },
	{ Name = "Divine Egg", Weight = 5 },
}
Config.StageStartX = 40 -- east edge of stage 1; each stage is StageLength deep
Config.StageLength = 110
Config.ChaseOverrun = 40 -- guards chase this far past their stage's entrance
Config.GuardCatchRange = 5.5
Config.Guards = {
	-- Sleeps = dozes in a chair until someone steals from her heap.
	{ Stage = "House", Name = "Grandma", Title = "", Speed = 10, Scale = 1.5, Look = "Grandma", Sleeps = true, WakeEmoji = "👵 ",
		Eggs = { "Cardboard Box", "Gift Box" }, PetChance = 0.25,
		Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(150, 90, 160),
		Floor = Color3.fromRGB(165, 115, 70), FloorMaterial = Enum.Material.WoodPlanks },
	{ Stage = "Forest", Name = "Chicken", Title = "", Speed = 13, Scale = 1.4, Look = "Chicken", Sleeps = true, WakeEmoji = "🐔 ",
		ZzzText = "Z z z", ZzzColor = Color3.fromRGB(70, 140, 255), ZzzOffset = Vector3.new(1.5, 4, 0),
		Eggs = { "Speckled Egg", "Ocean Egg" }, PetChance = 0.25,
		Skin = Color3.fromRGB(250, 250, 245), Shirt = Color3.fromRGB(200, 50, 45),
		Floor = Color3.fromRGB(75, 125, 55), FloorMaterial = Enum.Material.Grass },
	{ Stage = "Lab", Name = "Mad Scientist", Title = "", Speed = 16, Scale = 1.6, Look = "Scientist",
		Eggs = { "Ocean Egg", "Lava Egg" }, PetChance = 0.3,
		Skin = Color3.fromRGB(240, 200, 165), Shirt = Color3.fromRGB(240, 240, 240), Pants = Color3.fromRGB(35, 35, 40),
		Floor = Color3.fromRGB(225, 228, 232), FloorMaterial = Enum.Material.SmoothPlastic },
	{ Stage = "Snow", Name = "Krusher", Title = "the Brute", Speed = 19, Scale = 1.8,
		Eggs = { "Lava Egg", "Galaxy Egg" }, PetChance = 0.3,
		Skin = Color3.fromRGB(150, 110, 170), Shirt = Color3.fromRGB(40, 40, 45),
		Floor = Color3.fromRGB(235, 240, 250), FloorMaterial = Enum.Material.Snow },
	{ Stage = "Volcano", Name = "King Gorath", Title = "the Guard King", Speed = 22, Scale = 2,
		Eggs = { "Galaxy Egg", "Golden Egg" }, PetChance = 0.35, Crown = true,
		Skin = Color3.fromRGB(200, 90, 70), Shirt = Color3.fromRGB(230, 180, 40),
		Floor = Color3.fromRGB(55, 45, 45), FloorMaterial = Enum.Material.Basalt, Lava = true },
}

-- Stage i spans X from StageEast(i) down to StageEast(i) - StageLength.
function Config.StageEast(i)
	return Config.StageStartX - (i - 1) * Config.StageLength
end

-- Admins: only the game's owner sees the admin button (plus UserIds added here).
-- Add more admins by UserId here.
Config.Admins = {}

-- Follow reward: follow the game's creator on Roblox, then claim this much cash
-- once (saved per player). Roblox only exposes follower *counts* publicly, so
-- the server checks that the creator's count went up after the player opened
-- the reward panel. Goes through a public proxy (game servers can't call
-- roblox.com directly). Needs HTTP enabled.
Config.FollowRewardCash = 5000
Config.FollowProxyHost = "friends.roproxy.com"


-- Robux items. Create each one on the Creator Dashboard (create.roblox.com ->
-- your game -> Monetization), then paste its ID here. Prices are set there too.
-- Developer Products can be bought again and again:
Config.Products = {
	{ Name = "Pile of Cash", Kind = "Cash", Amount = 1000, Id = 0 },
	{ Name = "Bag of Cash", Kind = "Cash", Amount = 15000, Id = 0 },
	{ Name = "Vault of Cash", Kind = "Cash", Amount = 250000, Id = 0 },
	{ Name = "Speed Boost", Kind = "Speed", Amount = 3, Id = 0, Description = "+3 speed levels" },
}
-- Game Passes are bought once and kept forever:
Config.GamePasses = {
	{ Name = "Donation (small)", Kind = "Donation", Id = 2063834767, Description = "Support the creator ❤️" },
	{ Name = "Donation (Big)", Kind = "Donation", Id = 2063872754, Description = "Support the creator big time ❤️" },
	{ Name = "2x Money", Kind = "DoubleCash", Id = 2064126372, Description = "Your pets earn double cash" },
	{ Name = "2x Treadmill speed", Kind = "DoubleXP", Id = 2063631176, Description = "Train twice as fast" },
}

local function weightedPick(entries, weightOf)
	local total = 0
	for _, e in entries do
		total += weightOf(e)
	end
	local r = math.random() * total
	for _, e in entries do
		r -= weightOf(e)
		if r <= 0 then
			return e
		end
	end
	return entries[1]
end

function Config.RollEgg()
	return weightedPick(Config.Eggs, function(e)
		return e.Weight
	end)
end

function Config.RollPet(egg)
	local names = {}
	for name in egg.Hatches do
		table.insert(names, name)
	end
	table.sort(names)
	local name = weightedPick(names, function(n)
		return egg.Hatches[n]
	end)
	return Config.Pets[name]
end

function Config.SpeedXPNeeded(level)
	return math.floor(10 * 1.35 ^ level)
end

function Config.WalkSpeed(level, carrying)
	local speed = Config.BaseSpeed + level * Config.SpeedPerLevel
	return carrying and speed * Config.CarrySpeedFactor or speed
end

function Config.Format(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

-- How far above a surface the model's pivot sits so it stands on it.
function Config.StandHeight(kind, t)
	if kind == "Egg" then
		return t.Shape == "Box" and 1.5 or 2
	end
	return 1.7 * (t.Scale or 1)
end

-- Builds a pet box: a cardboard carrier with tape and air holes, or a gift box
-- with a ribbon and bow. Body is the PrimaryPart.
local function buildBox(t)
	local model = Instance.new("Model")
	model.Name = t.Name
	local body
	local function piece(name, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CFrame = cf
		if body then
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		else
			p.Anchored = true
		end
		p.Parent = model
		return p
	end
	body = piece("Body", Vector3.new(3, 3, 3), CFrame.new(), t.Color)
	model.PrimaryPart = body
	if t.Name == "Gift Box" then
		piece("RibbonX", Vector3.new(3.06, 3.06, 0.5), CFrame.new(), t.Spots)
		piece("RibbonZ", Vector3.new(0.5, 3.06, 3.06), CFrame.new(), t.Spots)
		for _, s in { -1, 1 } do
			piece("Bow", Vector3.new(0.9, 0.7, 0.5), CFrame.new(s * 0.45, 1.8, 0) * CFrame.Angles(0, 0, s * 0.5), t.Spots)
		end
	else
		piece("Tape", Vector3.new(0.7, 0.06, 3.04), CFrame.new(0, 1.5, 0), t.Spots)
		piece("FlapSeam", Vector3.new(3.02, 0.05, 0.08), CFrame.new(0, 1.52, 0), t.Color:Lerp(Color3.new(0, 0, 0), 0.3))
		-- Air holes on two sides so you know something is inside.
		for _, side in { -1, 1 } do
			for _, y in { 0.4, -0.4 } do
				for _, z in { -0.6, 0, 0.6 } do
					piece("Hole", Vector3.new(0.05, 0.25, 0.25), CFrame.new(side * 1.51, y, z), Color3.fromRGB(40, 30, 25))
				end
			end
		end
	end
	model:SetAttribute("EggType", t.Name)
	return model
end

-- Builds an egg Model (3x4 ellipsoid with spots). Body is the PrimaryPart.
function Config.BuildEgg(t)
	if t.Shape == "Box" then
		return buildBox(t)
	end
	local model = Instance.new("Model")
	model.Name = t.Name
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 4, 3)
	body.Color = t.Color
	body.Material = t.Material
	body.Anchored = true
	body.CanCollide = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.Parent = model
	model.PrimaryPart = body

	-- Spots scattered over the shell.
	local rng = Random.new(#t.Name * 7)
	for _ = 1, 7 do
		local yaw = rng:NextNumber(0, math.pi * 2)
		local y = rng:NextNumber(-1.2, 1.3)
		local ring = math.sqrt(math.max(0, 1 - (y / 2) ^ 2)) * 1.5
		local pos = Vector3.new(math.cos(yaw) * ring, y, math.sin(yaw) * ring)
		local spot = Instance.new("Part")
		spot.Name = "Spot"
		spot.Shape = Enum.PartType.Ball
		local d = rng:NextNumber(0.5, 0.85)
		spot.Size = Vector3.new(d, d, d)
		spot.Color = t.Spots
		spot.Material = t.Glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
		spot.CanCollide = false
		spot.Massless = true
		spot.CFrame = CFrame.new(pos * 0.93)
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = spot
		w.Parent = spot
		spot.Parent = model
	end

	if t.Glow then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = t.Spots
		sparkles.Parent = body
		local light = Instance.new("PointLight")
		light.Color = t.Color
		light.Range = 12
		light.Brightness = 2
		light.Parent = body
	end
	model:SetAttribute("EggType", t.Name)
	return model
end

-- Builds a blocky pet Model facing -Z, with Body as the PrimaryPart.
-- Every part is welded to Body, so anchoring/moving Body moves the whole pet.
function Config.BuildPet(t)
	local s = t.Scale or 1
	local model = Instance.new("Model")
	model.Name = t.Name

	local body
	local function piece(name, size, offset, color, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.Massless = true
		p.CastShadow = true
		if props then
			for k, v in props do
				p[k] = v
			end
		end
		if body then
			p.CFrame = body.CFrame * (offset.Rotation + offset.Position * s)
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		else
			p.CFrame = CFrame.new()
		end
		p.Parent = model
		return p
	end
	local V, C = Vector3.new, CFrame.new
	local black = Color3.fromRGB(25, 25, 30)

	body = piece("Body", V(2.2, 1.8, 2.8), C(), t.Color, { Anchored = true, Massless = false })
	model.PrimaryPart = body
	piece("Belly", V(1.8, 0.3, 2.2), C(0, -0.8, 0), t.Accent)
	local head = piece("Head", V(2, 1.8, 1.8), C(0, 0.9, -1.7), t.Color)
	piece("Snout", V(1, 0.6, 0.4), C(0, 0.55, -2.75), t.Accent)
	piece("Nose", V(0.35, 0.25, 0.1), C(0, 0.75, -2.98), black)
	for _, x in { -0.5, 0.5 } do
		piece("Eye", V(0.35, 0.45, 0.1), C(x, 1.25, -2.62), black)
		piece("Shine", V(0.12, 0.12, 0.05), C(x + 0.08, 1.38, -2.68), Color3.new(1, 1, 1))
	end
	for _, x in { -0.65, 0.65 } do
		for _, z in { -0.9, 0.9 } do
			piece("Leg", V(0.6, 1, 0.6), C(x, -1.2, z), t.Name == "Panda" and t.Accent or t.Color)
		end
	end

	local ears = t.Ears
	for _, side in { -1, 1 } do
		if ears == "Floppy" then
			piece("Ear", V(0.35, 1.2, 0.8), C(side * 1.15, 0.8, -1.7), t.Accent)
		elseif ears == "Pointy" then
			piece("Ear", V(0.5, 0.7, 0.5), C(side * 0.6, 2.05, -1.6), t.Color)
			piece("EarInner", V(0.3, 0.45, 0.1), C(side * 0.6, 2.0, -1.88), t.Accent)
		elseif ears == "Long" then
			piece("Ear", V(0.45, 1.8, 0.35), C(side * 0.5, 2.6, -1.5) * CFrame.Angles(0, 0, side * -0.15), t.Color)
			piece("EarInner", V(0.25, 1.4, 0.1), C(side * 0.5, 2.55, -1.7) * CFrame.Angles(0, 0, side * -0.15), t.Accent)
		elseif ears == "Round" then
			piece("Ear", V(0.7, 0.7, 0.4), C(side * 0.85, 1.95, -1.5), t.Accent)
			piece("EyePatch", V(0.6, 0.7, 0.05), C(side * 0.5, 1.2, -2.6), t.Accent)
		elseif ears == "Horns" then
			piece("Horn", V(0.3, 0.9, 0.3), C(side * 0.6, 2.1, -1.3) * CFrame.Angles(-0.4, 0, side * -0.3), t.Accent)
		end
	end

	if t.BigTail then
		piece("Tail", V(0.8, 0.8, 1.6), C(0, 0.4, 2.0) * CFrame.Angles(0.5, 0, 0), t.Color)
		piece("TailTip", V(0.6, 0.6, 0.6), C(0, 0.95, 2.75), t.Accent)
	else
		piece("Tail", V(0.35, 0.35, 0.9), C(0, 0.6, 1.7) * CFrame.Angles(0.6, 0, 0), t.Ears == "Long" and t.Accent or t.Color)
	end

	if t.Wings then
		for _, side in { -1, 1 } do
			piece("Wing", V(0.15, 1.4, 2), C(side * 1.4, 1.0, 0.2) * CFrame.Angles(0, 0, side * -0.6), t.Accent,
				{ Material = Enum.Material.Neon, Transparency = 0.15 })
		end
	end

	if t.Horn then
		piece("Horn", V(0.3, 1.3, 0.3), C(0, 2.25, -2.2) * CFrame.Angles(-0.45, 0, 0), Color3.fromRGB(255, 215, 80),
			{ Material = Enum.Material.Neon })
	end

	if t.Mane then
		local mane = piece("Mane", V(0.4, 1.6, 1.6), C(0, 1.4, -0.7), t.Accent, { Material = Enum.Material.Neon })
		mane:AddTag("RainbowPart")
	end

	if t.Glow then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = t.Accent
		sparkles.Parent = body
		local light = Instance.new("PointLight")
		light.Color = t.Accent
		light.Range = 12
		light.Brightness = 2
		light.Parent = body
	end

	model:SetAttribute("PetType", t.Name)
	return model
end


return Config
