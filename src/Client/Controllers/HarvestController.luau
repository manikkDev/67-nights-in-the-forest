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

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)
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
local swingAnimationId: string? = nil
local cachedAnimTrack: AnimationTrack? = nil
local gameStateController: any = nil

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
    @summary  Cache the axe swing Animation asset for playback.
    @desc     The server now publishes a short built-in R15 tool-slash
              Animation (asset 522635514), which is a quick overhead
              strike that fits an axe/pickaxe chop.
]]
local function ensureSwingAnimation()
	if swingAnimationId then
		return
	end

	local anim = ReplicatedStorage:FindFirstChild("AxeStrikeAnimation")
	if not anim or not anim:IsA("Animation") then
		warn("[HarvestController] AxeStrikeAnimation not found in ReplicatedStorage")
		return
	end

	swingAnimationId = anim.AnimationId
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
	if cachedAnimTrack then
		cachedAnimTrack.Priority = Enum.AnimationPriority.Action
		cachedAnimTrack:Play()
	end
end

--[[
    @summary  Handle a click-to-chop request from the equipped axe.
    @desc     Checks client-side cooldown, plays the swing animation,
              and fires the server RequestChop remote.
]]
local CarryController = require(script.Parent.CarryController)

local function onToolActivated()
	if not gameStateController or not gameStateController:IsInGame() then
		return
	end
	if CarryController.IsDragging() or CarryController.GetHoveredModel() then
		return
	end

	local now = os.clock()
	if (now - lastChopTime) < CHOP_COOLDOWN then
		return
	end
	lastChopTime = now

	playSwingAnimation()

	local combatService = Knit.GetService("CombatService")
	combatService:RequestAttack()
end

--[[
    @summary  Wire Tool.Activated on the given tool.
]]
local function wireTool(tool: Tool)
	toolJanitor:Cleanup()
	toolJanitor:Add(tool.Activated:Connect(onToolActivated), "Disconnect")
end

--[[
    @summary  Watch the player's Backpack and Character for the Axe tool
              being equipped.
]]
local function watchForAxe(player: Player)
	local function checkCharacter(character: Model)
		cachedAnimTrack = nil
		toolJanitor:Cleanup()
		charJanitor:Cleanup()

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

	janitor:Cleanup()
	janitor:Add(player.CharacterAdded:Connect(checkCharacter), "Disconnect")

	if player.Character then
		checkCharacter(player.Character)
	end
end

-- // INITIALIZATION // --

function HarvestController:KnitStart()
	if not ServerRole.IsGameServer() then return end
	gameStateController = Knit.GetController("GameStateController")
	local harvestService = Knit.GetService("HarvestService")
	harvestService.TreeChopped:Connect(function()
		shakeCamera()
	end)

	local player = Players.LocalPlayer

	local function onGameStarted()
		watchForAxe(player)
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

end

return HarvestController
