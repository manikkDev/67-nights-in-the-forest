--[[
    @file    DonationService.luau
    @author  manik
    @date    2025

    @summary
    Completes Developer-Product donations made at the lobby stand.

    @description
    The lobby contains a donation stand whose tier buttons prompt
    repeatable Developer Product purchases.  Purchases do not complete
    unless a ProcessReceipt handler grants them, so this service installs
    the handler at init, validates the product against
    Constants.DONATION_TIERS, and fires a confirmation back to the buyer
    so the client can thank them.  Donations grant no gameplay benefit.
    The handler is installed unconditionally because it is a single
    global callback and donations are place-agnostic.

    @exports
    - Client.DonationConfirmed -> fired to the buyer with (price: number)
]]

-- // VARIABLES // --

-- | Services | --
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

-- | Objects | --
local DonationService = Knit.CreateService({
	Name = "DonationService",
	Client = {
		-- Fired to the buying player once their product is granted.
		DonationConfirmed = Knit.CreateSignal(),
	},
})

-- | State Management | --
-- Reverse lookup so receipts can be validated without scanning the table.
local priceByProductId = {}
for _, tier in ipairs(Constants.DONATION_TIERS) do
	if tier.ProductId > 0 then
		priceByProductId[tier.ProductId] = tier.Price
	end
end

-- // FUNCTIONS // --

--[[
    @summary  Grant known donation products, defer anything else.
    @param    receipt  table  -- Roblox receipt (PlayerId, ProductId, ...)
    @returns  Enum.ProductPurchaseDecision
]]
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local price = priceByProductId[receipt.ProductId]
	if not player or price == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DonationService.Client.DonationConfirmed:Fire(player, price)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- // INITIALIZATION // --

--[[
    @summary  Knit lifecycle init — installs the global receipt handler.
]]
function DonationService:KnitInit()
	MarketplaceService.ProcessReceipt = processReceipt
end

return DonationService
