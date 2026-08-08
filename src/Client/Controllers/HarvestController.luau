--[[
    @file    HarvestController.luau
    @author  manik
    @date    2025

    @summary
    Client-side axe tool handling, swing animation, and chop feedback.

    @description
    Listens for Tool.Activated on the locally-equipped Axe to trigger
    a swing animation and fire the server's RequestChop remote.  Also
    listens for the server's TreeChopped signal and applies a short
    procedural camera shake via Humanoid.CameraOffset.

    @exports
    - HarvestController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local HarvestController = Knit.CreateController({
	Name = "HarvestController",
})

-- | Configuration | --
local SHAKE_DURATION = 0.15
local SHAKE_MAGNITUDE = 0.12
local AXE_TOOL_NAME = "Axe"
local CHOP_COOLDOWN = 0.5

-- | State Management | --
local janitor = Janitor.new()
local toolJanitor = Janitor.new()
local charJanitor = Janitor.new()
local lastChopTime = 0
local equippedTool: Tool? = nil
local swingAnimationId: string? = nil
local cachedAnimTrack: AnimationTrack? = nil

-- // FUNCTIONS // --

--[[
    @summary  Apply a brief decaying random offset to the local
              character's camera to sell a chop impact.
]]
local function shakeCamera()
	task.spawn(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local elapsed = 0
		while elapsed < SHAKE_DURATION do
			local dt = task.wait()
			elapsed += dt
			local falloff = 1 - (elapsed / SHAKE_DURATION)
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * SHAKE_MAGNITUDE * falloff,
				(math.random() - 0.5) * 2 * SHAKE_MAGNITUDE * falloff,
				0
			)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

--[[
    @summary  Register the axe swing KeyframeSequence on the client and
              cache the Animation instance for playback.
    @desc     KeyframeSequenceProvider:RegisterKeyframeSequence must be
              called on the CLIENT to produce a hash that the client's
              Animator can actually load.  Server-registered hashes are
              not valid on the client.
]]
local function ensureSwingAnimation()
	if swingAnimationId then
		return
	end

	local kfs = ReplicatedStorage:FindFirstChild("AxeStrikeKeyframeSequence")
	if not kfs or not kfs:IsA("KeyframeSequence") then
		warn("[HarvestController] AxeStrikeKeyframeSequence not found in ReplicatedStorage")
		return
	end

	swingAnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
end

--[[
    @summary  Play the axe swing animation on the local character.
    @desc     Loads the registered animation onto the character's
              Animator.  Caches the AnimationTrack per character to
              avoid creating new tracks on every swing.
]]
local function playSwingAnimation()
	ensureSwingAnimation()
	if not swingAnimationId then
		return
	end

	local character = Players.LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- If we have a cached track and it still belongs to this animator, reuse it
	if cachedAnimTrack and cachedAnimTrack.Parent == animator then
		cachedAnimTrack:Play()
		return
	end

	-- Build a fresh Animation instance and load it
	local animInstance = Instance.new("Animation")
	animInstance.AnimationId = swingAnimationId

	cachedAnimTrack = animator:LoadAnimation(animInstance)
	cachedAnimTrack.Priority = Enum.AnimationPriority.Action
	cachedAnimTrack:Play()
end

--[[
    @summary  Handle a click-to-chop request from the equipped axe.
    @desc     Checks client-side cooldown, plays the swing animation,
              and fires the server RequestChop remote.
]]
local function onToolActivated()
	local now = os.clock()
	if (now - lastChopTime) < CHOP_COOLDOWN then
		return
	end
	lastChopTime = now

	playSwingAnimation()

	local harvestService = Knit.GetService("HarvestService")
	harvestService.RequestChop()
end

--[[
    @summary  Wire Tool.Activated on the given tool.
]]
local function wireTool(tool: Tool)
	toolJanitor:Clean()
	equippedTool = tool
	toolJanitor:Add(tool.Activated:Connect(onToolActivated), "Disconnect")
end

--[[
    @summary  Watch the player's Backpack and Character for the Axe tool
              being equipped.
]]
local function watchForAxe(player: Player)
	local function checkCharacter(character: Model)
		cachedAnimTrack = nil
		toolJanitor:Clean()
		charJanitor:Clean()

		local tool = character:FindFirstChild(AXE_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireTool(tool)
		end

		charJanitor:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == AXE_TOOL_NAME then
				wireTool(child)
			end
		end), "Disconnect")
	end

	janitor:Clean()
	janitor:Add(player.CharacterAdded:Connect(checkCharacter), "Disconnect")

	if player.Character then
		checkCharacter(player.Character)
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local existingAxe = backpack:FindFirstChild(AXE_TOOL_NAME)
		if existingAxe and existingAxe:IsA("Tool") then
			local char = player.Character
			if char then
				existingAxe.Parent = char
			end
		end

		janitor:Add(backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == AXE_TOOL_NAME then
				local char = player.Character
				if char then
					child.Parent = char
				end
			end
		end), "Disconnect")
	end
end

-- // INITIALIZATION // --

function HarvestController:KnitStart()
	local harvestService = Knit.GetService("HarvestService")
	harvestService.TreeChopped:Connect(function()
		shakeCamera()
	end)

	local player = Players.LocalPlayer
	watchForAxe(player)

	print("[HarvestController] Initialised — chop feedback wired")
end

return HarvestController
