-- hot-theme.lua — переопределения токенов палитры для hot-reload (task.md §6, G6).
--
-- Раскомментируйте строки и сохраните файл: boot.lua перечитает его
-- сам (таймер 2 с, когда dxui_debug = true) и применит через theme.apply.
-- Формат: те же ключи, что в style/tokens.lua -> palette (числа ARGB).

return {
    -- Пример «тёмно-зелёная» тема:
    -- accent     = 0xFF00A86B,
    -- accentDim  = 0xFF0B7A50,
    -- windowBg   = 0xFF10231C,
    -- bg         = 0xFF0F1B15,
    -- bgHover    = 0xFF1A2C22,
    -- bgPressed  = 0xFF24402F,
    -- border     = 0xFF2A4A38,
    -- text       = 0xFFE6FFF2,
    -- textDim    = 0xFF79A98B,
}
