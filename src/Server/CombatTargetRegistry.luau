--[[
    @file    CombatTargetRegistry.luau
    @author  manik
    @date    2025

    @summary
    Shared lookup so CombatService can damage any NPC without knowing
    which owning service spawned it.

    @description
    AnimalAIService, DeerService, and CultistRaidService each register
    their spawned models here with a damage handler.  CombatService
    only needs a Model to find and drive that handler, and the
    "CombatTarget" CollectionService tag lets it enumerate every live
    target in one pass regardless of species.

    @exports
    - CombatTargetRegistry.Register(model, handlers)
    - CombatTargetRegistry.Unregister(model)
    - CombatTargetRegistry.Get(model) -> handlers?
]]

-- // VARIABLES // --

-- | Services | --
local CollectionService = game:GetService("CollectionService")

-- | Configuration | --
local TAG_NAME = "CombatTarget"

-- | State Management | --
local registry: { [Model]: any } = {}

-- // FUNCTIONS // --

--[[
    @summary  Register a spawned NPC model as a valid combat target.
    @param    model     Model    -- the NPC model
    @param    handlers  table    -- { ApplyDamage: (amount, attacker) -> (killed: boolean, immune: boolean), IsImmune: boolean? }
]]
local function register(model: Model, handlers: any)
	registry[model] = handlers
	CollectionService:AddTag(model, TAG_NAME)
end

--[[
    @summary  Remove a model from the combat target registry.
    @param    model  Model
]]
local function unregister(model: Model)
	registry[model] = nil
	if model.Parent then
		CollectionService:RemoveTag(model, TAG_NAME)
	end
end

--[[
    @summary  Return the damage handlers registered for a model, if any.
    @param    model  Model
    @returns  table?
]]
local function get(model: Model): any
	return registry[model]
end

return {
	TagName = TAG_NAME,
	Register = register,
	Unregister = unregister,
	Get = get,
}
