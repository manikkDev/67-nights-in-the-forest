--[[
    @file    IntroAssets.luau
    @author  manik
    @date    2025

    @summary
    Optional image/color slots for the join intro sequence.

    @description
    Leave image ids empty to use the procedural silhouette placeholder.
    Drop rbxassetid values here later without changing flow code.
]]

return {
	TitleDeerImage = "",
	WaitingDeerImage = "",
	TitleColor = Color3.fromRGB(232, 220, 190),
	SubtitleColor = Color3.fromRGB(170, 160, 140),
	AccentGreen = Color3.fromRGB(80, 170, 70),
	Backdrop = Color3.fromRGB(0, 0, 0),

	-- Create Party UI
	PanelBackdrop = Color3.fromRGB(25, 25, 25),
	PanelBackgroundTransparency = 0.25,
	TitleHandwritten = Color3.fromRGB(230, 220, 200),
	BodyText = Color3.fromRGB(230, 220, 200),
	SizeButton = Color3.fromRGB(160, 160, 160),
	SizeButtonDisabled = Color3.fromRGB(90, 90, 90),
	SizeButtonSelected = Color3.fromRGB(255, 210, 50),
	CreateButton = Color3.fromRGB(95, 190, 70),
	CreateButtonDisabled = Color3.fromRGB(70, 120, 60),
	CloseButton = Color3.fromRGB(220, 60, 60),
	CustomizeButton = Color3.fromRGB(80, 80, 80),

	-- Story / Day 1
	StoryText = Color3.fromRGB(170, 90, 90),

	-- Title / Story screen
	StoryScreenBackdrop = Color3.fromRGB(22, 22, 22),
	StoryHeaderColor = Color3.fromRGB(230, 55, 55),
	StoryPanelBackdrop = Color3.fromRGB(38, 38, 38),
	StoryPanelImage = "rbxassetid://0",
	StoryPanelPlaceholder = Color3.fromRGB(55, 55, 55),
	StoryPanelCaption = Color3.fromRGB(235, 235, 235),
	PlayButtonColor = Color3.fromRGB(95, 190, 70),
	StoryPanelImages = {
		"", -- 1: deer
		"", -- 2: children
		"", -- 3: police tape/gates
		"", -- 4: player at gate
	},
	StoryPanels = {
		{ caption = "Reports were made of a <b>DEER</b> standing on two legs in an unnatural way in the forest" },
		{ caption = "The following week: <b>4 CHILDREN</b> went missing. It was clear something was very, very wrong with the forest" },
		{ caption = "After the <b>police</b> search revealed no clues about the missing children. The forest was promptly locked to the public" },
		{ caption = "You have <b>99 NIGHTS</b> to unravel the mysteries of the forest and figure out what is going on" },
	},
}
