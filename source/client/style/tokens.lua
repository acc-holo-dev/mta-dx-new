-- style/tokens.lua — токены оформления (task.md §5)
--
-- Токены — единственный источник значений по умолчанию: palette, spacing,
-- font, radius, scale. Тема (style/theme) — таблица поверх токенов;
-- палитра мутируется батчевым обновлением при смене темы.

local tokens = {}

tokens.palette = {
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

tokens.spacing = { xs = 2, s = 4, m = 8, l = 16, xl = 24 }

tokens.font = {
    regular = "default",
    bold = "default-bold",
    title = "default-bold",
}

tokens.radius = { s = 2, m = 4, l = 8, xl = 12 }

-- глобальный множитель масштаба (DPI): применяется один раз в раскладке
tokens.scale = 1

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.tokens = tokens
return tokens
