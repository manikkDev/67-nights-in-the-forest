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

-- | Constants | --
local SHAKE_DURATION = 0.15
local SHAKE_MAGNITUDE = 0.12
local AXE_TOOL_NAME = "Axe"
local CHOP_COOLDOWN = 0.5

-- | Objects | --
local HarvestController = Knit.CreateController({
	Name = "HarvestController",
})

-- | State | --
local lastChopTime = 0
local equippedTool: Tool? = nil
local toolActivatedConnection: RBXScriptConnection? = nil
local toolChildAddedConnection: RBXScriptConnection? = nil
local backpackChildAddedConnection: RBXScriptConnection? = nil
local characterAddedConnection: RBXScriptConnection? = nil
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
	if toolActivatedConnection then
		toolActivatedConnection:Disconnect()
		toolActivatedConnection = nil
	end
	equippedTool = tool
	toolActivatedConnection = tool.Activated:Connect(onToolActivated)
end

--[[
    @summary  Watch the player's Backpack and Character for the Axe tool
              being equipped.
]]
local function watchForAxe(player: Player)
	local function checkCharacter(character: Model)
		-- Invalidate cached animation track on respawn
		cachedAnimTrack = nil

		if toolChildAddedConnection then
			toolChildAddedConnection:Disconnect()
			toolChildAddedConnection = nil
		end

		local tool = character:FindFirstChild(AXE_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireTool(tool)
		end

		toolChildAddedConnection = character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == AXE_TOOL_NAME then
				wireTool(child)
			end
		end)
	end

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
	end
	characterAddedConnection = player.CharacterAdded:Connect(checkCharacter)

	if player.Character then
		checkCharacter(player.Character)
	end

	-- Watch backpack for axe — auto-equip it when added
	if backpackChildAddedConnection then
		backpackChildAddedConnection:Disconnect()
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		-- Check if axe is already in backpack
		local existingAxe = backpack:FindFirstChild(AXE_TOOL_NAME)
		if existingAxe and existingAxe:IsA("Tool") then
			-- Auto-equip by parenting to character
			local char = player.Character
			if char then
				existingAxe.Parent = char
			end
		end

		backpackChildAddedConnection = backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == AXE_TOOL_NAME then
				-- Auto-equip the axe when it's added to the backpack
				local char = player.Character
				if char then
					child.Parent = char
				end
			end
		end)
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
