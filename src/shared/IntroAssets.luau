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
}
