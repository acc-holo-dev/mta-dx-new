-- DXUI v2 — настройки ресурса.
-- Читается boot.lua до инициализации подсистем; все ключи имеют дефолты.

return {
    -- режим: dev включает pcall-изоляцию, схемные ошибки, инспектор
    mode      = "dev",
    -- приоритет обработчика onClientRender (меньше = раньше)
    priority  = "normal",
    -- глобальный множитель DPI (tokens.scale * instance scale)
    scale     = 1.0,
    -- тема по умолчанию (имя файла в theme/ без .lua)
    theme     = "dark",
}
