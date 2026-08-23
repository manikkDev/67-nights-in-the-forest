--[[
    @file    CombatController.luau
    @author  manik
    @date    2025

    @summary
    Client-side Spear tool handling and shared melee/NPC-attack VFX.

    @description
    Wires the Spear's swing (the Axe's swing is handled by
    HarvestController, which now also routes through CombatService).
    Plays a spark burst and camera shake when a weapon hit lands, and
    a brief red damage flash when the local player is struck by an
    NPC or the Deer/Ram Monster stalkers.

    @exports
    - CombatController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- | Objects | --
local CombatController = Knit.CreateController({
	Name = "CombatController",
})

-- | Configuration | --
local SPEAR_TOOL_NAME = "Spear"
local SHAKE_DURATION = 0.15
local SHAKE_MAGNITUDE = 0.16
local DAMAGE_FLASH_DURATION = 0.35
local DAMAGE_FLASH_TINT = Color3.fromRGB(160, 0, 0)

-- | State Management | --
local janitor = Janitor.new()
local toolJanitor = Janitor.new()
local charJanitor = Janitor.new()
local gameStateController: any = nil
local damageCorrection: ColorCorrectionEffect? = nil

-- // FUNCTIONS // --

--[[
    @summary  Apply a brief decaying random offset to the local
              character's camera to sell an attack impact.
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
    @summary  Spawn a short spark particle burst at a world position.
    @param    position  Vector3
]]
local function spawnHitSpark(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new(0.25, 0.02)
	emitter.Rate = 0
	emitter.Parent = anchor

	emitter:Emit(16)
	Debris:AddItem(anchor, 1.5)
end

--[[
    @summary  Ensure a dedicated ColorCorrectionEffect exists for the
              damage flash so it doesn't fight CampSafetyController's.
    @returns  ColorCorrectionEffect
]]
local function ensureDamageCorrection(): ColorCorrectionEffect
	if damageCorrection and damageCorrection.Parent then
		return damageCorrection
	end
	local existing = Lighting:FindFirstChild("CombatDamageCorrection")
	if existing and existing:IsA("ColorCorrectionEffect") then
		damageCorrection = existing
		return existing
	end
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "CombatDamageCorrection"
	correction.TintColor = Color3.new(1, 1, 1)
	correction.Parent = Lighting
	damageCorrection = correction
	return correction
end

--[[
    @summary  Flash the screen red briefly to signal the local player
              was struck.
]]
local function flashDamage()
	local correction = ensureDamageCorrection()
	correction.TintColor = DAMAGE_FLASH_TINT
	TweenService:Create(correction, TweenInfo.new(DAMAGE_FLASH_DURATION, Enum.EasingStyle.Quad), {
		TintColor = Color3.new(1, 1, 1),
	}):Play()
end

--[[
    @summary  Wire Tool.Activated on the given Spear tool.
    @param    tool  Tool
]]
local function wireSpear(tool: Tool)
	toolJanitor:Cleanup()
	toolJanitor:Add(tool.Activated:Connect(function()
		if not gameStateController or not gameStateController:IsInGame() then
			return
		end
		local combatService = Knit.GetService("CombatService")
		combatService.RequestAttack()
	end), "Disconnect")
end

--[[
    @summary  Watch the player's Backpack and Character for the Spear
              tool being equipped.
    @param    player  Player
]]
local function watchForSpear(player: Player)
	local function checkCharacter(character: Model)
		toolJanitor:Cleanup()
		charJanitor:Cleanup()

		local tool = character:FindFirstChild(SPEAR_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			wireSpear(tool)
		end

		charJanitor:Add(character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child.Name == SPEAR_TOOL_NAME then
				wireSpear(child)
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

function CombatController:KnitStart()
	gameStateController = Knit.GetController("GameStateController")
	local player = Players.LocalPlayer

	local function onGameStarted()
		watchForSpear(player)
	end

	if gameStateController and gameStateController:IsInGame() then
		onGameStarted()
	else
		if gameStateController then
			gameStateController.GameStarted:Connect(onGameStarted)
		end
	end

	local combatService = Knit.GetService("CombatService")
	combatService.AttackLanded:Connect(function(position: Vector3, _weaponName: string, wasImmune: boolean)
		spawnHitSpark(position)
		if not wasImmune then
			shakeCamera()
		end
	end)

	local animalAIService = Knit.GetService("AnimalAIService")
	animalAIService.NpcAttacked:Connect(function(_position: Vector3)
		shakeCamera()
		flashDamage()
	end)

	local deerService = Knit.GetService("DeerService")
	deerService.StalkerContact:Connect(function(_position: Vector3, _key: string)
		shakeCamera()
		flashDamage()
	end)

end

return CombatController
