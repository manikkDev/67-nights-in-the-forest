--[[
    @file    GrinderService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative junk-to-scrap shredder placed next to the crafting bench.

    @description
    Uses a pre-placed "Shredder" model. A copy can live in
    ServerStorage.Assets["Assets Items"] for auto-placement, or the
    developer can drag a model named "Shredder" or "Grinder" directly
    into Workspace to position it by hand. Players interact via a
    ProximityPrompt to open the grind UI and convert junk into Scrap.

    @exports
    - Knit Signal: OpenGrinder()          (server -> client, open UI)
    - Knit Signal: GrinderProcessed()     (server -> client, VFX)
    - Knit Remote: GrindItem(junkId)      (client -> server)
    - Knit Remote: GrindAll()             (client -> server)
]]

-- // VARIABLES // --

-- | Services | --
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local GrinderService = Knit.CreateService({
	Name = "GrinderService",
	Client = {
		OpenGrinder = Knit.CreateSignal(),
		GrinderProcessed = Knit.CreateSignal(),
	},
})

-- | Configuration | --
-- Default spot: well clear of the bench (bench is at +14, 0, 0 from campfire).
local GRINDER_OFFSET = CFrame.new(14, 0, 18)
local GRIND_RANGE = 10
local GRIND_COOLDOWN = 0.15
local SHREDDER_ASSET_NAME = "Shredder"
local IDLE_SPIN_SPEED = 8      -- rad/s, slow idle rotation
local GRIND_SPIN_SPEED = 35    -- rad/s, fast grinding rotation
local GRIND_SOUND_ID = "rbxassetid://9116635756"

-- | State Management | --
local runStateService: any = nil
local inventoryService: any = nil
local grinderModel: Model? = nil
local grinderPosition: Vector3? = nil
local grinderPrimaryPart: BasePart? = nil
local isManualModel = false
local cooldowns: { [Player]: number } = {}
local bladePart: BasePart? = nil
local bladeHinge: HingeConstraint? = nil
local bladeAngularVel: AngularVelocity? = nil
local bladeAttachment0: Attachment? = nil
local bladeAttachment1: Attachment? = nil
local grindSound: Sound? = nil
local grindStopTimer: any = nil
local touchCooldowns: { [Model]: number } = {} -- debounce per junk model
local isNearGrinder: (Player) -> boolean

-- // FUNCTIONS // --

-- | Private | --

--[[
    @summary  Find the best part to use as PrimaryPart in a model.
    @desc     Prefers an existing PrimaryPart, then the largest part.
    @param    model  Model
    @returns  BasePart?
]]
local function findPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart.Parent then
		return model.PrimaryPart
	end

	local best: BasePart? = nil
	local bestVolume = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local volume = desc.Size.X * desc.Size.Y * desc.Size.Z
			if volume > bestVolume then
				bestVolume = volume
				best = desc
			end
		end
	end
	return best
end

--[[
    @summary  Find the blade/cylinder part in the shredder model.
    @desc     Searches for parts named Blade, Cylinder, Drum, Grinder, etc.
              Falls back to the smallest cylindrical part (likely the blade).
    @param    model  Model
    @returns  BasePart?
]]
local function findBladePart(model: Model): BasePart?
	local bladeNames = { "blade", "cylinder", "drum", "grinder", "spinner", "rotor", "gear", "teeth" }
	-- First, search by name
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local lowerName = desc.Name:lower()
			for _, bladeName in ipairs(bladeNames) do
				if lowerName:find(bladeName, 1, true) then
					return desc
				end
			end
		end
	end
	-- Fallback: find a part that has a Motor6D or HingeConstraint (already spinning)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("HingeConstraint") or desc:IsA("Motor6D") or desc:IsA("AngularConstraint") then
			local att0 = desc.Attachment0
			if att0 and att0.Parent and att0.Parent:IsA("BasePart") then
				return att0.Parent
			end
		end
	end
	return nil
end

--[[
    @summary  Anchor the shredder body but keep the blade free to spin.
    @desc     Anchors all parts except the blade part, disables scripts,
              destroys PackageLinks/Sounds that cause asset errors.
    @param    model  Model
    @param    blade  BasePart? -- the blade part to keep unanchored
]]
local function anchorAndSanitize(model: Model, blade: BasePart?)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
			desc.Disabled = true
		elseif desc:IsA("PackageLink") or desc:IsA("TextureConfiguration") then
			desc:Destroy()
		elseif desc:IsA("Sound") then
			-- Remove unauthorized sounds from the asset
			if desc.SoundId == "rbxassetid://6160151677" then
				desc:Destroy()
			end
		elseif desc:IsA("BasePart") then
			-- Anchor everything except the blade part
			if desc ~= blade then
				desc.Anchored = true
			else
				desc.Anchored = false
				desc.CanCollide = false
				desc.CanQuery = true
			end
		end
	end
end

--[[
    @summary  Set up a spinning blade on the shredder using HingeConstraint.
    @desc     Creates attachments and a HingeConstraint + AngularVelocity
              so the blade spins continuously at idle speed.
    @param    model  Model
    @param    blade  BasePart -- the blade part to spin
]]
local function setupBladeSpin(model: Model, blade: BasePart)
	-- Find an anchor part near the blade (the body part the blade attaches to)
	local anchorPart = model.PrimaryPart
	if not anchorPart or anchorPart == blade then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= blade and desc.Anchored then
				anchorPart = desc
				break
			end
		end
	end
	if not anchorPart or anchorPart == blade then
		-- Can't set up spin without an anchor
		blade.Anchored = true
		return
	end

	-- Create attachments on both the blade and the anchor
	bladeAttachment0 = Instance.new("Attachment")
	bladeAttachment0.Name = "BladeAtt"
	bladeAttachment0.Position = Vector3.zero
	bladeAttachment0.Parent = blade

	bladeAttachment1 = Instance.new("Attachment")
	bladeAttachment1.Name = "BladeAnchorAtt"
	bladeAttachment1.Position = blade.Position - anchorPart.Position
	bladeAttachment1.Parent = anchorPart

	-- HingeConstraint lets the blade rotate around the Y axis
	bladeHinge = Instance.new("HingeConstraint")
	bladeHinge.Name = "BladeHinge"
	bladeHinge.Attachment0 = bladeAttachment0
	bladeHinge.Attachment1 = bladeAttachment1
	bladeHinge.ActuatorType = Enum.ActuatorType.Motor
	bladeHinge.MotorMaxTorque = 1000
	bladeHinge.Parent = model

	-- AngularVelocity drives the spin speed
	bladeAngularVel = Instance.new("AngularVelocity")
	bladeAngularVel.Name = "BladeSpin"
	bladeAngularVel.Attachment0 = bladeAttachment0
	bladeAngularVel.AngularVelocity = Vector3.new(0, IDLE_SPIN_SPEED, 0)
	bladeAngularVel.MaxTorque = 1000
	bladeAngularVel.Parent = blade
end

--[[
    @summary  Find a manually placed Shredder/Grinder in Workspace.
    @returns  Model?
]]
local function findManualShredder(): Model?
	local workspaceModel = workspace:FindFirstChild("Shredder")
		or workspace:FindFirstChild("Grinder")
	if workspaceModel and workspaceModel:IsA("Model") then
		return workspaceModel
	end
	return nil
end

--[[
    @summary  Clone and prepare the Shredder asset from ServerStorage.
    @returns  Model?
]]
local function buildShredderModel(): Model?
	local itemsPath = ServerStorage.Assets:FindFirstChild(Constants.ITEMS_PATH)
	if not itemsPath then
		warn("[GrinderService] Assets Items folder not found in ServerStorage")
		return nil
	end

	local source = itemsPath:FindFirstChild(SHREDDER_ASSET_NAME)
	if not source then
		warn(("[GrinderService] '%s' asset not found in Assets Items"):format(SHREDDER_ASSET_NAME))
		return nil
	end

	local model = source:Clone()
	model.Name = "Grinder"
	return model
end

--[[
    @summary  Attach a Grind ProximityPrompt to the shredder model.
    @param    model  Model
]]
local function attachPrompt(model: Model)
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		warn("[GrinderService] Shredder model has no BasePart for ProximityPrompt")
		return
	end

	local existingPrompt = anchor:FindFirstChildWhichIsA("ProximityPrompt")
	local prompt = existingPrompt or Instance.new("ProximityPrompt")
	prompt.Name = "GrindPrompt"
	prompt.ActionText = "Grind"
	prompt.ObjectText = "Shredder"
	prompt.MaxActivationDistance = GRIND_RANGE
	prompt.HoldDuration = 0
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if runStateService:IsActive() and runStateService:IsMember(player) and isNearGrinder(player) then
			GrinderService.Client.OpenGrinder:Fire(player)
		end
	end)
end

--[[
    @summary  Find the player who owns/dropped a junk model.
    @param    model  Model
    @returns  Player?
]]
local function findOwner(model: Model): Player?
	local droppedBy = model:GetAttribute("DroppedBy")
	if droppedBy then
		for _, player in ipairs(Players:GetPlayers()) do
			if player.UserId == droppedBy then
				return player
			end
		end
	end
	return nil
end

--[[
    @summary  Auto-grind a junk or wood model that touched the shredder.
    @desc     Junk items -> Scrap (metal sheets). Wood -> WoodenSheet.
    @param    model  Model -- the dropped item model
]]
local function autoGrindTouched(model: Model)
	local resourceName = model:GetAttribute("Resource")
	if not resourceName then
		return
	end
	-- Only process junk items or Wood.
	local isJunk = JunkItemConfig[resourceName] ~= nil
	local isWood = resourceName == "Wood"
	if not isJunk and not isWood then
		return
	end
	-- Debounce: each model can only be ground once.
	if touchCooldowns[model] then
		return
	end
	touchCooldowns[model] = os.clock()

	local player = findOwner(model)
	if not player then
		return
	end
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local inventoryService = Knit.GetService("InventoryService")
	local craftingService = Knit.GetService("CraftingService")

	if isWood then
		-- Wood -> WoodenSheet (1 wood = 1 wooden sheet).
		-- WoodenSheet is a bench-only shared resource — it is NOT added
		-- to the player's personal inventory. It only goes to the shared
		-- crafting total so the whole team can craft from it.
		if runStateService:IsActive() and runStateService:IsMember(player) then
			model:Destroy()
			touchCooldowns[model] = nil
			GrinderService:StartGrindAnimation()
			GrinderService.Client.GrinderProcessed:Fire(player, {
				position = grinderPosition,
				scrapAmount = 1,
				junkId = "WoodenSheet",
			})
			GrinderService:StopGrindAnimation()
			craftingService:AddShreddedTotal("WoodenSheet", 1)
		end
	else
		local config = JunkItemConfig[resourceName]
		local added = inventoryService:AddResource(player, "Scrap", config.ScrapYield)
		if added > 0 then
			model:Destroy()
			touchCooldowns[model] = nil
			GrinderService:StartGrindAnimation()
			GrinderService.Client.GrinderProcessed:Fire(player, {
				position = grinderPosition,
				scrapAmount = added,
				junkId = resourceName,
			})
			GrinderService:StopGrindAnimation()
			craftingService:AddShreddedTotal("Scrap", added)
		end
	end
end

--[[
    @summary  Connect Touched events on all shredder parts so that
              any junk item that physically touches the shredder is
              instantly ground.
    @param    model  Model
]]
local function connectTouchHandlers(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Touched:Connect(function(hit)
				local hitModel = hit:FindFirstAncestorWhichIsA("Model")
				if not hitModel then
					return
				end
				-- Process models with a Resource attribute that's junk or Wood.
				local res = hitModel:GetAttribute("Resource")
				if res and (JunkItemConfig[res] or res == "Wood") then
					autoGrindTouched(hitModel)
				end
			end)
		end
	end
end

--[[
    @summary  Place the shredder next to the crafting bench.
    @desc     Called by CraftingService.placeBench() after the bench
              is positioned. A manually placed "Shredder"/"Grinder"
              in Workspace takes priority and is left exactly where the
              developer put it. Otherwise a copy is cloned from
              ServerStorage and placed at the configured offset.
    @param    campfireCFrame  CFrame  -- the campfire anchor
]]
function GrinderService:PlaceGrinder(campfireCFrame: CFrame)
	if grinderModel and not isManualModel then
		grinderModel:Destroy()
	end
	grinderModel = nil
	grinderPosition = nil
	grinderPrimaryPart = nil
	isManualModel = false

	local model = findManualShredder()
	if model then
		isManualModel = true
		-- Keep the model exactly where the developer placed it.
		model.Name = "Grinder"
	else
		model = buildShredderModel()
		if not model then
			return
		end

		-- Position the cloned shredder clearly clear of the bench.
		local pivot = model:GetPivot()
		local _, size = model:GetBoundingBox()
		local groundOffset = CFrame.new(0, size.Y * 0.5, 0)
		model:PivotTo(campfireCFrame * GRINDER_OFFSET * groundOffset * pivot.Rotation)
		model.Parent = runStateService:GetRuntimeFolder()
	end

	if not model then
		return
	end

	if not model.PrimaryPart then
		local primary = findPrimaryPart(model)
		if primary then
			model.PrimaryPart = primary
		end
	end

	-- Find the blade part before anchoring (so we keep it free to spin)
	bladePart = findBladePart(model)
	anchorAndSanitize(model, bladePart)
	attachPrompt(model)
	connectTouchHandlers(model)

	-- Set up the spinning blade if we found one
	if bladePart then
		setupBladeSpin(model, bladePart)
	end

	-- Create a persistent grinding sound on the shredder
	local soundAnchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if soundAnchor then
		grindSound = Instance.new("Sound")
		grindSound.Name = "GrindSound"
		grindSound.SoundId = GRIND_SOUND_ID
		grindSound.Volume = 0.6
		grindSound.Looped = true
		grindSound.RollOffMaxDistance = 30
		grindSound.RollOffMinDistance = 5
		grindSound.RollOffMode = Enum.RollOffMode.Linear
		grindSound.Parent = soundAnchor
	end

	grinderModel = model
	grinderPosition = model:GetPivot().Position
	grinderPrimaryPart = model.PrimaryPart
end

--[[
    @summary  Return whether a player is close enough to grind.
    @param    player  Player
    @returns  boolean
]]
isNearGrinder = function(player: Player): boolean
	if not grinderPosition then
		return false
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (rootPart.Position - grinderPosition).Magnitude <= GRIND_RANGE
end

--[[
    @summary  Process a single grind request with cooldown.
    @param    player  Player
    @param    junkId  string
    @returns  number  -- scrap granted
]]
local function processGrind(player: Player, junkId: string): number
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return 0
	end
	if not isNearGrinder(player) then
		return 0
	end
	local now = os.clock()
	if cooldowns[player] and now - cooldowns[player] < GRIND_COOLDOWN then
		return 0
	end
	cooldowns[player] = now

	local config = JunkItemConfig[junkId]
	if not config then
		return 0
	end

	local added = inventoryService:GrindJunk(player, junkId)
	if added > 0 then
		GrinderService:StartGrindAnimation()
		GrinderService.Client.GrinderProcessed:Fire(player, {
			position = grinderPosition,
			scrapAmount = added,
			junkId = junkId,
		})
		GrinderService:StopGrindAnimation()
		local craftingService = Knit.GetService("CraftingService")
		craftingService:AddShreddedTotal("Scrap", added)
	end
	return added
end

-- | Public | --

--[[
    @summary  Return the grinder's world position (for client VFX).
    @returns  Vector3?
]]
function GrinderService:GetGrinderPosition(): Vector3?
	return grinderPosition
end

--[[
    @summary  Return the grinder's primary part (for client VFX attachment).
    @returns  BasePart?
]]
function GrinderService:GetGrinderPrimaryPart(): BasePart?
	return grinderPrimaryPart
end

--[[
    @summary  Speed up the blade and play the grinding sound.
    @desc     Called when a junk item is being ground (via UI or drag).
]]
function GrinderService:StartGrindAnimation()
	if bladeAngularVel then
		bladeAngularVel.AngularVelocity = Vector3.new(0, GRIND_SPIN_SPEED, 0)
	end
	if grindSound and not grindSound.IsPlaying then
		grindSound:Play()
	end
	-- Cancel any pending stop timer
	if grindStopTimer then
		task.cancel(grindStopTimer)
		grindStopTimer = nil
	end
end

--[[
    @summary  Slow the blade back to idle and stop the sound after a delay.
    @desc     Called after grinding is complete.  The sound continues for
              1.5s then fades, matching the real game's behavior.
]]
function GrinderService:StopGrindAnimation()
	if grindStopTimer then
		task.cancel(grindStopTimer)
	end
	local capturedRunId = runStateService:GetRunId()
	grindStopTimer = task.delay(1.5, function()
		if not runStateService:IsCurrentRun(capturedRunId) then
			return
		end
		if bladeAngularVel then
			bladeAngularVel.AngularVelocity = Vector3.new(0, IDLE_SPIN_SPEED, 0)
		end
		if grindSound then
			grindSound:Stop()
		end
		grindStopTimer = nil
	end)
end

-- | Client Remotes | --

--[[
    @summary  Client-to-server: grind one junk item.
    @param    player  Player  -- injected by Knit
    @param    junkId  string
    @returns  number          -- scrap granted
]]
function GrinderService.Client:GrindItem(player: Player, junkId: string): number
	if typeof(junkId) ~= "string" then
		return 0
	end
	return processGrind(player, junkId)
end

--[[
    @summary  Client-to-server: grind all carried junk items.
    @desc     Iterates every junk item the player carries and grinds
              each one, returning the total scrap granted.
    @param    player  Player  -- injected by Knit
    @returns  number          -- total scrap granted
]]
function GrinderService.Client:GrindAll(player: Player): number
	if not runStateService:IsActive() or not runStateService:IsMember(player) then
		return 0
	end
	if not isNearGrinder(player) then
		return 0
	end
	if not inventoryService then
		return 0
	end
	local total = 0
	for junkId, _ in pairs(JunkItemConfig) do
		local count = inventoryService:GetResourceCount(player, junkId)
		for _ = 1, count do
			local added = processGrind(player, junkId)
			total += added
		end
	end
	return total
end

-- // INITIALIZATION // --

function GrinderService:KnitStart()
	runStateService = Knit.GetService("RunStateService")
	inventoryService = Knit.GetService("InventoryService")

	runStateService.RunCleaned:Connect(function()
		if grinderModel and not isManualModel then
			grinderModel:Destroy()
		end
		grinderModel = nil
		grinderPosition = nil
		grinderPrimaryPart = nil
		isManualModel = false
		cooldowns = {}
		bladePart = nil
		bladeHinge = nil
		bladeAngularVel = nil
		bladeAttachment0 = nil
		bladeAttachment1 = nil
		grindSound = nil
		if grindStopTimer then
			task.cancel(grindStopTimer)
			grindStopTimer = nil
		end
	end)

	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return GrinderService
