-- widget/palette.lua — фиксированные цвета до этапа theme/ (G6)

local palette = {
    bg         = 0xFF1E2430,
    bgHover    = 0xFF2A3546,
    bgPressed  = 0xFF34435C,
    bgDisabled = 0xFF1A1F28,
    border     = 0xFF3A4456,
    text       = 0xFFE8ECF2,
    textDim    = 0xFF8A93A3,
    accent     = 0xFF1E6FE8,
    accentDim  = 0xFF153F83,
    danger     = 0xFFE85151,
    overlay    = 0xB4000000,
    windowBg   = 0xFF222A38,
    white      = 0xFFFFFFFF,
}

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.palette = palette
return palette
