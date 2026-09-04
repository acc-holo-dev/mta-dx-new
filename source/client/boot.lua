-- boot.lua — точка сборки; ЕДИНСТВЕННЫЙ платформенный мост кадра и ввода
-- (MTA-whitelist: boot.lua, render/backend_mta.lua, input/dispatcher.lua)
--
-- Пока (G2): клок, холст, один обработчик кадра с демо-прямоугольником.
-- По мере этапов сюда встанут пассы: input -> layout -> render (flush dirty).

local DXUI = _G.DXUI

-- ---------------------------------------------------------------- клок
DXUI.time.setSource(function()
    return getTickCount()
end)

-- ---------------------------------------------------------------- конфиг (meta.xml settings)
local function getSetting(key, default)
    local v = get(key)
    if v == nil or v == false then
        return default
    end
    return v
end

local PRIORITY_MAP = {
    low = "low",
    normal = "normal",
    high = "high",
}

local settings = {
    debug = getSetting("dxui_debug", true),
    priority = PRIORITY_MAP[getSetting("dxui_priority", "normal")] or "normal",
}

-- ---------------------------------------------------------------- кадр

local canvas = DXUI.canvas.new()
local backend = DXUI.backend_mta

local frameCount = 0

local function onFrame()
    frameCount = frameCount + 1

    -- демо-прямоугольник G2: подтверждает жизненный цикл кадра в игре
    canvas:rect(20, 20, 200, 60, 0xFF1E6FE8, { radius = 6 })
    canvas:text("DXUI v2 frame " .. frameCount, 28, 44, { color = 0xFFFFFFFF })

    canvas:drain(backend)
end

-- единственный обработчик; приоритет — из настроек
addEventHandler("onClientRender", root, onFrame, false, settings.priority == "low" and "low" or settings.priority)

DXUI.boot = {
    version = "0.1.0",
    frameCount = function()
        return frameCount
    end,
}
