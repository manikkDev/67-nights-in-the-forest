--[[
    @file    GrinderController.luau
    @author  manik
    @date    2025

    @summary
    Client-side grinder UI, VFX, and blade animation.

    @description
    Listens for the OpenGrinder signal from the server, builds a UI
    panel showing carried junk items with their scrap yields, and
    fires GrindItem/GrindAll remotes when buttons are clicked. Also
    handles spark particles, grinding sound, and the spinning blade
    visual on the grinder model.
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local JunkItemConfig = require(ReplicatedStorage.Shared.JunkItemConfig)

-- | Objects | --
local GrinderController = Knit.CreateController({
	Name = "GrinderController",
})

-- | State Management | --
local grinderService: any = nil
local inventoryService: any = nil
local gui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil

-- Forward declaration so buildUi's callbacks can reference refreshList
-- before it is defined below.
local refreshList: () -> ()

-- // FUNCTIONS // --

--[[
    @summary  Return the bolt symbol string for a given count.
    @param    count  number
    @returns  string
]]
local function boltString(count: number): string
	local s = ""
	for _ = 1, count do
		s ..= "\u{1F529}"
	end
	return s
end

--[[
    @summary  Build the grinder UI once.
]]
local function buildUi()
	if gui then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GrinderGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui

	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "Panel"
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.Size = UDim2.new(0.6, 0, 0.6, 0)
	panelFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
	panelFrame.BorderSizePixel = 0
	panelFrame.Parent = screenGui
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(560, 480)
	sizeConstraint.MinSize = Vector2.new(300, 280)
	sizeConstraint.Parent = panelFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panelFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.new(0, 18, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(235, 225, 195)
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "SHREDDER  \u{2699}  JUNK \u{2192} SCRAP"
	title.Parent = panelFrame

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(44, 34)
	close.BackgroundColor3 = Color3.fromRGB(120, 55, 50)
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.TextSize = 18
	close.Parent = panelFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		screenGui.Enabled = false
	end)

	-- Grind All button
	local grindAll = Instance.new("TextButton")
	grindAll.Name = "GrindAll"
	grindAll.AnchorPoint = Vector2.new(0.5, 1)
	grindAll.Position = UDim2.new(0.5, 0, 1, -12)
	grindAll.Size = UDim2.new(0.7, 0, 0, 40)
	grindAll.BackgroundColor3 = Color3.fromRGB(70, 125, 70)
	grindAll.Font = Enum.Font.GothamBold
	grindAll.Text = "GRIND ALL"
	grindAll.TextColor3 = Color3.fromRGB(245, 245, 240)
	grindAll.TextSize = 18
	grindAll.Parent = panelFrame
	local grindAllCorner = Instance.new("UICorner")
	grindAllCorner.CornerRadius = UDim.new(0, 8)
	grindAllCorner.Parent = grindAll
	grindAll.Activated:Connect(function()
		if grinderService then
			grinderService:GrindAll():andThen(function()
				refreshList()
			end)
		end
	end)

	-- Recipe list
	local recipeList = Instance.new("ScrollingFrame")
	recipeList.Name = "JunkList"
	recipeList.Position = UDim2.new(0, 16, 0, 56)
	recipeList.Size = UDim2.new(1, -32, 1, -120)
	recipeList.BackgroundTransparency = 1
	recipeList.BorderSizePixel = 0
	recipeList.ScrollBarThickness = 6
	recipeList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	recipeList.CanvasSize = UDim2.new()
	recipeList.Parent = panelFrame
	listFrame = recipeList
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = recipeList
end

--[[
    @summary  Refresh the junk item list from the current inventory snapshot.
]]
refreshList = function()
	if not listFrame then
		return
	end

	-- Clear existing rows
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	if not inventoryService then
		return
	end

	local promise = inventoryService:GetSnapshot()
	if not promise then
		return
	end
	promise:andThen(function(snapshot)
		if typeof(snapshot) ~= "table" or typeof(snapshot.resources) ~= "table" then
			return
		end
		local resources = snapshot.resources
		local order = 0
		local hasAny = false
		for junkId, config in pairs(JunkItemConfig) do
			local count = resources[junkId] or 0
			if count > 0 then
				hasAny = true
				order += 1
				local row = Instance.new("TextButton")
				row.Name = junkId
				row.LayoutOrder = order
				row.Size = UDim2.new(1, -8, 0, 56)
				row.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				row.Font = Enum.Font.GothamBold
				row.TextColor3 = Color3.fromRGB(245, 245, 240)
				row.TextSize = 15
				row.TextWrapped = true
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.Text = string.format("  %s  %s  x%d  \u{2192}  %d Scrap",
					config.DisplayName, boltString(config.BoltCount), count, config.ScrapYield * count)
				row.Parent = listFrame
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 8)
				corner.Parent = row
				row.Activated:Connect(function()
					if grinderService then
						grinderService:GrindItem(junkId):andThen(function()
							refreshList()
						end)
					end
				end)
			end
		end

		if not hasAny then
			local empty = Instance.new("TextLabel")
			empty.Name = "Empty"
			empty.Size = UDim2.new(1, 0, 0, 40)
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.Gotham
			empty.TextColor3 = Color3.fromRGB(160, 160, 165)
			empty.TextSize = 16
			empty.Text = "No junk items to grind. Find junk at facilities in the forest!"
			empty.Parent = listFrame
		end
	end)
end

--[[
    @summary  Open the grinder UI.
]]
local function openGrinder()
	buildUi()
	refreshList()
	if gui then
		gui.Enabled = true
	end
end

--[[
    @summary  Find the grinder model in the workspace.
    @returns  Model?
]]
local function findGrinderModel(): Model?
	local runtime = workspace:FindFirstChild("Runtime")
	return runtime and runtime:FindFirstChild("Grinder")
end

--[[
    @summary  Find the best part to attach VFX to in the grinder model.
    @desc     Prefers the PrimaryPart, then the largest part.
    @param    model  Model
    @returns  BasePart?
]]
local function findVfxAnchor(model: Model): BasePart?
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
    @summary  Play any built-in grinding sounds the shredder asset has.
    @desc     Searches the model for Sound instances and plays them.
              Falls back to a default grinding sound if none are found.
    @param    model  Model
]]
local function playGrindSound(model: Model)
	local foundBuiltIn = false
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Sound") and desc.SoundId ~= "" then
			desc:Play()
			foundBuiltIn = true
		end
	end
	if not foundBuiltIn then
		-- Fallback grinding sound
		local sound = Instance.new("Sound")
		sound.Name = "GrindSoundFallback"
		sound.SoundId = "rbxassetid://9112810051"
		sound.Volume = 0.5
		sound.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if sound.Parent then
			sound:Play()
			task.delay(2, function()
				sound:Destroy()
			end)
		end
	end
end

--[[
    @summary  Play VFX when a junk item is ground.
    @param    payload  table  -- { position, scrapAmount, junkId }
]]
local function playVfx(payload: { [string]: any })
	if typeof(payload) ~= "table" or not payload.position then
		return
	end

	local grinder = findGrinderModel()
	if not grinder or not grinder:IsA("Model") then
		return
	end

	local anchor = findVfxAnchor(grinder)
	if not anchor then
		return
	end

	-- Spark particles attached to the shredder
	local attachment = Instance.new("Attachment")
	attachment.Name = "GrinderSparkAtt"
	attachment.Position = Vector3.new(0, 2, 0) -- offset above the anchor part
	attachment.Parent = anchor

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "GrinderSparks"
	particles.Texture = "rbxasset://textures/particles/spark.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
	particles.Size = NumberSequence.new(0.15, 0)
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Rate = 0
	particles.Speed = NumberRange.new(4, 8)
	particles.SpreadAngle = Vector2.new(45, 45)
	particles.Parent = attachment

	particles:Emit(15)
	task.delay(1, function()
		if attachment then
			attachment:Destroy()
		end
	end)

	-- Play grinding sound (built-in or fallback)
	playGrindSound(grinder)
end

-- // INITIALIZATION // --

function GrinderController:KnitStart()
	grinderService = Knit.GetService("GrinderService")
	inventoryService = Knit.GetService("InventoryService")

	grinderService.OpenGrinder:Connect(openGrinder)
	grinderService.GrinderProcessed:Connect(playVfx)
end

return GrinderController
