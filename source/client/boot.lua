-- boot.lua — точка сборки; ЕДИНСТВЕННЫЙ платформенный мост кадра и ввода
-- (MTA-whitelist: boot.lua, render/backend_mta.lua, input/dispatcher.lua)
--
-- G5: ввод полностью в input/dispatcher — очередь, hit-test, жесты, фокус.
-- boot только подключает мост платформы и строит демо-экран.

local DXUI = _G.DXUI

-- ---------------------------------------------------------------- клок
DXUI.time.setSource(function()
    return getTickCount()
end)

-- ---------------------------------------------------------------- конфиг

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

-- ---------------------------------------------------------------- демо-экран G5
-- click, drag окна, ввод, Tab/стрелки — всё через input/dispatcher.

local registry = DXUI.registry
local frame = DXUI.frame
local dispatcher = DXUI.dispatcher
local canvas = DXUI.canvas.new()
local backend = DXUI.backend_mta

local window = registry.create("Window", {
    title = "DXUI v2 — демо G5",
    x = 120, y = 100, width = 320, height = 240,
})
local label = registry.create("Label", { text = "Счёт: 0", x = 20, y = 40, width = 280, height = 24 })
local edit = registry.create("Edit", { x = 20, y = 70, width = 280, height = 28, placeholder = "Введите текст…" })
local checkbox = registry.create("Checkbox", { text = " ввод работает", x = 20, y = 105, width = 280, height = 24 })

local count = 0
local btnPlus = registry.create("Button", {
    text = "+1", x = 20, y = 140, width = 130, height = 32,
    onPress = function()
        count = count + 1
        label.text = "Счёт: " .. count
    end,
})
local btnClose = registry.create("Button", {
    text = "Скрыть", x = 160, y = 140, width = 140, height = 32,
    onPress = function()
        window.visible = false
    end,
})

window:addChild(label)
window:addChild(edit)
window:addChild(checkbox)
window:addChild(btnPlus)
window:addChild(btnClose)

frame.add(window)

-- drag окна за заголовок: press в зоне тайтла захватывает указатель
window:signal("press"):connect(function(_, _)
    window:capturePointer()
end)
window:signal("drag"):connect(function(dx, dy)
    window:moveBy(dx, dy)
end)

-- ---------------------------------------------------------------- мост платформы
dispatcher.install()

-- ---------------------------------------------------------------- кадр

local function onFrame()
    -- ввод один раз за кадр ДО пасса раскладки (task.md §3.4)
    dispatcher.dispatch(frame.roots())
    -- твины: единый клок, никаких таймеров в виджетах (task.md §5)
    DXUI.tween.tick()
    frame.run(canvas)
    canvas:drain(backend)
end

-- единственный обработчик кадра; приоритет — из настроек
addEventHandler("onClientRender", root, onFrame, false,
    settings.priority == "low" and "low" or settings.priority)

-- ---------------------------------------------------------------- hot-reload
-- dev: перечитываем тему по таймеру (файл = таблица переопределений токенов)

if settings.debug then
    local hot = {}
    DXUI.theme.define("hot", {})
    setTimer(function()
        if fileExists("hot-theme.lua") then
            local f = fileOpen("hot-theme.lua")
            if f then
                local src = fileRead(f, fileGetSize(f))
                fileClose(f)
                local chunk = loadstring(src)
                if chunk then
                    local ok, result = pcall(chunk)
                    if ok and type(result) == "table" then
                        DXUI.theme.apply(result)
                    end
                end
            end
        end
    end, 2000, 0)
    hot = nil
end

DXUI.boot = {
    version = "0.1.0",
    demo = {
        window = window,
        edit = edit,
    },
}
