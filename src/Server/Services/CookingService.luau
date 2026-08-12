--[[
    @file    CookingService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative raw-meat-to-cooked-meat conversion at the Bonfire.

    @description
    Wires a "Cook Meat" ProximityPrompt onto the Campfire anchor.  While
    the fire is lit, triggering it converts all of the player's carried
    RawMeat into CookedMeat (which restores more Hunger when eaten via
    ForageService's RequestEat).  Mirrors CampfireService's all-at-once
    feed pattern for consistency.

    @exports
    - (no public API; entirely ProximityPrompt driven)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CookingService = Knit.CreateService({
	Name = "CookingService",
})

-- | Configuration | --
local COOK_RANGE = 10
local COOK_COOLDOWN = 1

-- | State Management | --
local worldService: any? = nil
local inventoryService: any? = nil
local campfireService: any? = nil
local playerDataService: any? = nil
local campfirePart: BasePart? = nil
local cookPrompt: ProximityPrompt? = nil
local cookPromptConnection: RBXScriptConnection? = nil
local cookCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

--[[
    @summary  Wire the Cook Meat ProximityPrompt onto the Campfire anchor.
              Retries until WorldService has placed the campfire.
]]
local function setupCookPrompt()
	if not worldService then
		task.defer(setupCookPrompt)
		return
	end

	local anchor = worldService:GetCampfire()
	if not anchor then
		task.defer(setupCookPrompt)
		return
	end

	campfirePart = anchor :: BasePart

	-- Parent the cook prompt to the PromptAnchor (or fire center) so it
	-- shares a properly-sized BasePart parent with the feed prompt.
	local bonfire = worldService:GetBonfire()
	local promptAnchor = bonfire and bonfire:FindFirstChild("PromptAnchor")
	local fireCenter = bonfire and bonfire:FindFirstChild("Fire")
	local promptParent = (promptAnchor and promptAnchor:IsA("BasePart")) and promptAnchor or (fireCenter and fireCenter:IsA("BasePart")) and fireCenter or campfirePart

	local existing = promptParent:FindFirstChild("CookMeatPrompt")
	if not (existing and existing:IsA("ProximityPrompt")) and campfirePart then
		existing = campfirePart:FindFirstChild("CookMeatPrompt")
	end
	if existing and existing:IsA("ProximityPrompt") then
		local prompt = existing :: ProximityPrompt
		prompt.Parent = promptParent
		cookPrompt = prompt
	else
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CookMeatPrompt"
		prompt.ActionText = "Cook Meat"
		prompt.ObjectText = "Campfire"
		prompt.MaxActivationDistance = COOK_RANGE + 2
		prompt.HoldDuration = 0.3
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.KeyboardKeyCode = Enum.KeyCode.R
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent
		cookPrompt = prompt
	end

	if cookPrompt then
		cookPrompt.RequiresLineOfSight = false
		cookPrompt.KeyboardKeyCode = Enum.KeyCode.R
		cookPrompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	end

	print("[CookingService] Cook Meat prompt wired")
end

--[[
    @summary  Validate and process a cook request, converting all of the
              player's RawMeat into CookedMeat if the fire is lit.
    @param    player  Player  -- the cooking player
]]
local function cookMeat(player: Player)
	if not campfirePart then
		return
	end

	local now = os.clock()
	if cookCooldowns[player] and (now - cookCooldowns[player]) < COOK_COOLDOWN then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	if (rootPart.Position - campfirePart.Position).Magnitude > COOK_RANGE then
		return
	end

	if not campfireService or not campfireService:IsLit() then
		return
	end

	cookCooldowns[player] = now

	if not playerDataService then
		return
	end
	local data = playerDataService:GetData(player)
	local rawMeat = data and data.Resources.RawMeat or 0
	if rawMeat <= 0 then
		return
	end

	if not inventoryService or not inventoryService:ConsumeResource(player, "RawMeat", rawMeat) then
		return
	end
	inventoryService:AddResource(player, "CookedMeat", rawMeat)
end

--[[
    @summary  Route a global ProximityPrompt trigger to the cook handler.
    @param    prompt  ProximityPrompt  -- the triggered prompt
    @param    player  Player           -- the triggering player
]]
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt == cookPrompt then
		cookMeat(player)
	end
end

--[[
    @summary  Keep the Cook Meat prompt hidden when the fire is not lit so
              it cannot block the Feed prompt.
]]
local function updateCookPromptEnabled()
	if not cookPrompt then
		return
	end
	if not campfireService then
		cookPrompt.Enabled = true
		return
	end
	cookPrompt.Enabled = campfireService:IsLit()
end

-- // INITIALIZATION // --

function CookingService:KnitStart()
	worldService = Knit.GetService("WorldService")
	inventoryService = Knit.GetService("InventoryService")
	campfireService = Knit.GetService("CampfireService")
	playerDataService = Knit.GetService("PlayerDataService")

	setupCookPrompt()
	if cookPrompt then
		if cookPromptConnection then
			cookPromptConnection:Disconnect()
		end
		cookPromptConnection = cookPrompt.Triggered:Connect(function(player)
			onPromptTriggered(cookPrompt, player)
		end)
	end
	RunService.Heartbeat:Connect(updateCookPromptEnabled)
	updateCookPromptEnabled()

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[CookingService] Initialised — cooking active")
end

Players.PlayerRemoving:Connect(function(player)
	cookCooldowns[player] = nil
end)

return CookingService
