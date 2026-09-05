-- boot.lua — точка сборки; ЕДИНСТВЕННЫЙ платформенный мост кадра и ввода
-- для СОБСТВЕННОГО инстанса dxui-ресурса.
--
-- (MTA-whitelist: boot.lua, render/backend_mta.lua, input/dispatcher.lua)
--
-- Демо-экран по умолчанию выключен: это библиотека. Включить: /dxui:demo.
-- Потребители работают в своих VM через import(2) — см. api/exports.lua:
-- им этот boot не нужен, они получают свою копию фреймворка код-строкой.

local DXUI = _G.DXUI

-- ---------------------------------------------------------------- клок
DXUI.time.setSource(function()
    return getTickCount()
end)

-- ---------------------------------------------------------------- конфиг

-- get() отсутствует на клиенте в части сборок MTA: доступаемся безопасно
local function getSetting(key, default)
    local v = nil
    if type(get) == "function" then
        local ok, result = pcall(get, key)
        if ok then
            v = result
        end
    end
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

local registry = DXUI.registry
local frame = DXUI.frame
local dispatcher = DXUI.dispatcher
local inspector = DXUI.inspector
local profiler = DXUI.profiler
local canvas = DXUI.canvas.new()
local backend = DXUI.backend_mta

local function onFrame()
    -- ввод один раз за кадр ДО пасса раскладки (task.md §3.4)
    dispatcher.dispatch(frame.roots())
    -- твины: единый клок, никаких таймеров в виджетах (task.md §5)
    DXUI.tween.tick()
    local t0 = profiler.frameStart()
    frame.run(canvas)
    canvas:drain(backend)
    profiler.frameEnd(t0)
    -- overlay инспектора: статистика кадра
    if inspector.overlayEnabled() then
        local med = profiler.medianFrameCost()
        local lines = {
            ("dxui: median frame %.3f ms"):format(med),
            ("live nodes: %d | roots: %d"):format(DXUI.Node.getLiveCount(), #frame.roots()),
            ("active tweens: %d"):format(DXUI.tween.activeCount()),
        }
        local i = #lines
        for _, rec in ipairs(profiler.stats()) do
            if rec.worst > 0 then
                i = i + 1
                lines[i] = ("%-12s x%d avg %.4f worst %.4f ms")
                    :format(rec.type, rec.calls, rec.avg, rec.worst)
            end
        end
        -- активная пара drag-and-drop (§4.3: инспектор показывает пары)
        local dnd = DXUI.dragdrop and DXUI.dragdrop.active()
        if dnd then
            i = i + 1
            lines[i] = ("dnd: %s -> %s (%s)")
                :format(dnd.source, tostring(dnd.target), tostring(dnd.slot))
        end
        inspector.overlaySet(lines)
    end
end

-- единственный обработчик кадра; приоритет — из настроек
addEventHandler("onClientRender", root, onFrame, false,
    settings.priority == "low" and "low" or settings.priority)

-- ---------------------------------------------------------------- мост ввода

dispatcher.install()

-- ---------------------------------------------------------------- инспектор/профайлер
-- F8 — дерево/статистика; dxui:stats — то же командой

bindKey("F8", "down", function()
    if inspector.overlayEnabled() then
        inspector.overlayEnable(false)
        profiler.enable(false)
    else
        profiler.enable(true)
        inspector.overlayEnable(true)
    end
end)

addCommandHandler("dxui:stats", function()
    local on = not profiler.isEnabled()
    profiler.enable(on)
    inspector.overlayEnable(on)
end)

-- ---------------------------------------------------------------- демо
-- Демонстрационный экран G4/G5 — по команде, не при загрузке ресурса.

local demoWindow = nil

local function buildDemo()
    local window = registry.create("Window", {
        title = "DXUI v2 — демо",
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

    -- drag за заголовок и bringToFront по клику — в спецификации Window
    -- (§4.1): ручной wiring сигналов здесь не нужен
    return window
end

addCommandHandler("dxui:demo", function()
    if demoWindow == nil then
        demoWindow = buildDemo()
        frame.add(demoWindow)
    end
    demoWindow.visible = not demoWindow.visible
end)

-- ---------------------------------------------------------------- layout io
-- §3.8: позиции/размеры окон + тема в XML настроек ресурса (layout.xml).
-- Сериализация — в api/screens (headless), файлы — здесь (whitelist §2).

addCommandHandler("dxui:save-layout", function()
    local f = fileCreate("layout.xml")
    if not f then return end
    fileWrite(f, DXUI.screens.saveLayout())
    fileClose(f)
    outputChatBox("dxui: раскладка сохранена (layout.xml)")
end)

addCommandHandler("dxui:load-layout", function()
    if not fileExists("layout.xml") then
        outputChatBox("dxui: layout.xml не найден")
        return
    end
    local f = fileOpen("layout.xml", true)
    if not f then return end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    if DXUI.screens.loadLayout(src) then
        outputChatBox("dxui: раскладка применена (layout.xml)")
    end
end)

-- ---------------------------------------------------------------- hot-reload
-- dev: перечитываем тему по таймеру (файл = таблица переопределений токенов)

if settings.debug then
    local lastThemeSrc = nil
    setTimer(function()
        if fileExists("hot-theme.lua") then
            local f = fileOpen("hot-theme.lua")
            if f then
                local src = fileRead(f, fileGetSize(f))
                fileClose(f)
                if src ~= lastThemeSrc then
                    lastThemeSrc = src
                    local chunk = loadstring(src)
                    if chunk then
                        local ok, result = pcall(chunk)
                        if ok and type(result) == "table" then
                            DXUI.theme.apply(result)
                        end
                    end
                end
            end
        end
    end, 2000, 0)
end

DXUI.boot = {
    version = "0.1.0",
}
