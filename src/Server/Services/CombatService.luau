--[[
    @file    CombatService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative melee combat: range/cooldown/facing validation,
    NPC damage routing, and the Spear tool build/grant.

    @description
    A single click-to-attack remote drives both weapons.  The server
    finds the nearest registered `CombatTargetRegistry` NPC within
    range and facing angle of the attacker; if none is in range and
    the equipped tool is the Axe, the request falls back to
    HarvestService's tree-chop path so one click always does the
    contextually correct thing.  Never trusts a client-supplied target,
    distance, or damage amount.

    @exports
    - Knit Remote: RequestAttack()   (client -> server)
    - Knit Signal: AttackLanded(position, weaponName, wasImmune)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatTargetRegistry = require(script.Parent.Parent.CombatTargetRegistry)

-- | Objects | --
local CombatService = Knit.CreateService({
	Name = "CombatService",
	Client = {
		AttackLanded = Knit.CreateSignal(),
	},
})

-- | Configuration | --
local ITEMS_PATH = ServerStorage.Assets[Constants.ITEMS_PATH]
local AXE_TOOL_NAME = "Axe"
local SPEAR_TOOL_NAME = "Spear"
local ATTACK_RANGE = 8
local ATTACK_HALF_ANGLE = math.rad(60)
local WEAPON_DAMAGE = { Axe = 15, Spear = 25 }
local WEAPON_COOLDOWN = { Axe = 0.6, Spear = 0.9 }

-- | State Management | --
local harvestService: any = nil
local spawnService: any = nil
local spearTemplate: Tool? = nil
local attackCooldowns: { [Player]: number } = {}

-- // FUNCTIONS // --

--[[
    @summary  Build a wearable Spear Tool by cloning the Spear model
              and welding its parts onto a chosen Handle part.
    @returns  Tool?
]]
local function buildSpearTool(): Tool?
	local source = ITEMS_PATH:FindFirstChild("Spear")
	if not source then
		warn("[CombatService] Spear model not found in Assets Items")
		return nil
	end

	local clone = source:Clone()
	local handleModel = clone:FindFirstChild("handle")
	local originalShaft = handleModel and handleModel:FindFirstChild("Handle")
	local shaft = handleModel and handleModel:FindFirstChild("Grip")
	if not shaft or not shaft:IsA("BasePart") then
		warn("[CombatService] Spear hand grip not found")
		clone:Destroy()
		return nil
	end
	if originalShaft and originalShaft:IsA("BasePart") then
		originalShaft.Name = "Shaft"
	end

	local tool = Instance.new("Tool")
	tool.Name = SPEAR_TOOL_NAME
	tool.RequiresHandle = true
	tool.Grip = CFrame.Angles(0, 0, math.rad(90))

	shaft.Name = "Handle"
	shaft.CanCollide = false
	shaft.Anchored = false

	for _, child in ipairs(clone:GetChildren()) do
		if child == shaft then
			continue
		elseif child:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = shaft
			weld.Part1 = child
			weld.Parent = shaft
			child.Anchored = false
			child.CanCollide = false
			child.Parent = tool
		elseif child:IsA("Model") then
			for _, sub in ipairs(child:GetDescendants()) do
				if sub:IsA("BasePart") then
					sub.Anchored = false
					sub.CanCollide = false
					if sub ~= shaft then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = shaft
						weld.Part1 = sub
						weld.Parent = shaft
					end
				end
			end
			for _, sub in ipairs(child:GetChildren()) do
				sub.Parent = tool
			end
		end
	end

	shaft.Parent = tool
	clone:Destroy()
	return tool
end

--[[
    @summary  Return the cached Spear tool template for cloning by
              other services (e.g. LootService granting it from chests).
    @returns  Tool?
]]
function CombatService:GetSpearTemplate(): Tool?
	return spearTemplate
end

--[[
    @summary  Fire a Knit signal to every currently-connected player.
    @param    signal  KnitSignal
]]
local function broadcastToAll(signal, ...)
	for _, player in ipairs(Players:GetPlayers()) do
		signal:Fire(player, ...)
	end
end

--[[
    @summary  Return the player's currently-equipped weapon tool name,
              if any.
    @param    player  Player
    @returns  string?
]]
local function getEquippedWeaponName(player: Player): string?
	local character = player.Character
	if not character then
		return nil
	end
	local axe = character:FindFirstChild(AXE_TOOL_NAME)
	if axe and axe:IsA("Tool") then
		return AXE_TOOL_NAME
	end
	local spear = character:FindFirstChild(SPEAR_TOOL_NAME)
	if spear and spear:IsA("Tool") then
		return SPEAR_TOOL_NAME
	end
	return nil
end

--[[
    @summary  Find the nearest live combat target within range and
              facing angle of an attacking player.
    @param    player  Player
    @returns  Model?
]]
local function findNearestCombatTarget(player: Player): Model?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	local nearest: Model? = nil
	local nearestDist = math.huge

	for _, model in ipairs(CollectionService:GetTagged(CombatTargetRegistry.TagName)) do
		if not model:IsA("Model") or not model.Parent then
			continue
		end
		local targetPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HRP")
		if not targetPart or not targetPart:IsA("BasePart") then
			continue
		end

		local toTarget = targetPart.Position - rootPart.Position
		local dist = toTarget.Magnitude
		if dist > ATTACK_RANGE or dist <= 0 then
			continue
		end

		local angle = math.acos(math.clamp(rootPart.CFrame.LookVector.Unit:Dot(toTarget.Unit), -1, 1))
		if angle > ATTACK_HALF_ANGLE then
			continue
		end

		if dist < nearestDist then
			nearestDist = dist
			nearest = model
		end
	end

	return nearest
end

--[[
    @summary  Validate and process a melee attack request: hit the
              nearest in-range NPC, or fall back to tree chopping for
              the Axe when nothing is in range.
    @param    player  Player  -- injected by Knit
]]
function CombatService.Client:RequestAttack(player: Player)
	local weaponName = getEquippedWeaponName(player)
	if not weaponName then
		return
	end

	local now = os.clock()
	local cooldown = WEAPON_COOLDOWN[weaponName] or 1
	if attackCooldowns[player] and (now - attackCooldowns[player]) < cooldown then
		return
	end

	local target = findNearestCombatTarget(player)
	if target then
		attackCooldowns[player] = now
		local handlers = CombatTargetRegistry.Get(target)
		if handlers then
			local _killed, immune = handlers.ApplyDamage(WEAPON_DAMAGE[weaponName] or 10, player)
			broadcastToAll(CombatService.Client.AttackLanded, target:GetPivot().Position, weaponName, immune == true)
		end
		return
	end

	if weaponName == AXE_TOOL_NAME and harvestService then
		harvestService:TryChopNearest(player)
	end
end

-- // INITIALIZATION // --

function CombatService:KnitStart()
	harvestService = Knit.GetService("HarvestService")
	spawnService = Knit.GetService("SpawnService")

	spearTemplate = buildSpearTool()
end

Players.PlayerRemoving:Connect(function(player)
	attackCooldowns[player] = nil
end)

return CombatService
