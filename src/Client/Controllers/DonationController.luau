--[[
    @file    DonationController.luau
    @author  manik
    @date    2025

    @summary
    Wires the lobby donation stand's tier buttons to purchase prompts.

    @description
    Finds the DonationStand model inside Workspace["lobby-map"] and
    connects every tier button on its sign SurfaceGui so a click prompts
    the matching repeatable Developer Product.  When the server confirms
    a purchase it fires DonationConfirmed and this controller shows a
    brief thank-you toast.  Lobby-only — returns early on real game
    servers (Studio still initialises so the stand is testable there).

    @exports
    - none
]]

-- // VARIABLES // --

-- | Services | --
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local ServerRole = require(ReplicatedStorage.Shared.ServerRole)

-- | Objects | --
local DonationController = Knit.CreateController({
	Name = "DonationController",
})

local localPlayer = Players.LocalPlayer
local warnedMissingIds = false

-- // FUNCTIONS // --

--[[
    @summary  Show a brief thank-you toast after a confirmed donation.
    @param    price  number  -- Robux amount that was purchased
]]
local function showThankYou(price: number)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("DonationToast")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DonationToast"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.12, 0)
	label.Size = UDim2.new(0, 520, 0, 56)
	label.BackgroundColor3 = Color3.fromRGB(30, 22, 14)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(255, 214, 120)
	label.Text = ("Thank you for the %s tip!"):format(tostring(price))
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 90, 30)
	stroke.Thickness = 2
	stroke.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	gui.Parent = playerGui
	task.delay(3.5, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		gui:Destroy()
	end)
end

--[[
    @summary  Connect every tier button on the stand's sign SurfaceGui.
    @param    stand  Model  -- Workspace["lobby-map"].DonationStand
]]
local function wireStand(stand: Instance)
	local tiers = stand:WaitForChild("Sign"):WaitForChild("BoardGui"):WaitForChild("Tiers")
	for index, tier in ipairs(Constants.DONATION_TIERS) do
		local button = tiers:FindFirstChild("Tier" .. index)
		if button then
			button.Activated:Connect(function()
				if tier.ProductId == 0 then
					if not warnedMissingIds then
						warnedMissingIds = true
						warn("[DonationController] Donation tiers are not configured yet (ProductId = 0 in Constants.DONATION_TIERS)")
					end
					return
				end
				MarketplaceService:PromptProductPurchase(localPlayer, tier.ProductId)
			end)
		end
	end
end

-- // INITIALIZATION // --

--[[
    @summary  Knit lifecycle start — wires the stand and the thank-you
              toast.  Inert on real game servers and when the lobby map
              has no donation stand.
]]
function DonationController:KnitStart()
	if ServerRole.IsGameServer() and not RunService:IsStudio() then
		return
	end

	local donationService = Knit.GetService("DonationService")
	donationService.DonationConfirmed:Connect(showThankYou)

	task.spawn(function()
		local lobbyMap = workspace:WaitForChild("lobby-map", 15)
		local stand = lobbyMap and lobbyMap:WaitForChild("DonationStand", 15)
		if not stand then
			return
		end
		wireStand(stand)
	end)
end

return DonationController
