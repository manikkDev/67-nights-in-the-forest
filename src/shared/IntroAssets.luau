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
}
