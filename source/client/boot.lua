-- boot.lua — точка сборки; ЕДИНСТВЕННЫЙ платформенный мост кадра и ввода
-- (MTA-whitelist: boot.lua, render/backend_mta.lua, input/dispatcher.lua)
--
-- G4: демо-экран — окно с кнопками (click), drag за заголовок, ввод в Edit.
-- Полный input/-пайплайн (spatial hash, focus, жесты) — этап G5;
-- здесь — минимальный мост платформенных событий к виджетам.

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

-- ---------------------------------------------------------------- демо-экран G4
-- click, drag окна, ввод — минимальная прослойка ввода прямо в boot.
-- Координаты детей — абсолютные внутри окна: мир = window lay + child lay.

local rawget = rawget
local registry = DXUI.registry
local frame = DXUI.frame
local canvas = DXUI.canvas.new()
local backend = DXUI.backend_mta

local window = registry.create("Window", {
    title = "DXUI v2 — демо G4",
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

-- ---------------------------------------------------------------- hit-test
-- по геометрии прошлого кадра (task.md §3.4): мировые прямоугольники

local function rectOf(node, parentX, parentY)
    local l = rawget(node, "_").lay
    return parentX + l.x, parentY + l.y, l.w, l.h
end

local hovered = false
local dragging = false
local dragDX, dragDY = 0, 0
local focusedEdit = nil

local function buttonAt(absX, absY)
    for _, btn in ipairs({ btnPlus, btnClose }) do
        local bx, by, bw, bh = rectOf(btn, window.x, window.y)
        if absX >= bx and absX <= bx + bw and absY >= by and absY <= by + bh then
            return btn
        end
    end
    return nil
end

local function editAt(absX, absY)
    local bx, by, bw, bh = rectOf(edit, window.x, window.y)
    if absX >= bx and absX <= bx + bw and absY >= by and absY <= by + bh then
        return edit
    end
    return nil
end

local function inHeader(absX, absY)
    local l = rawget(window, "_").lay
    local hx, hy = window.x, window.y
    local hw = l.w
    local hh = window.headerHeight
    return absX >= hx and absX <= hx + hw and absY >= hy and absY <= hy + hh
end

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if button ~= "left" then return end
    if state == "down" then
        -- drag за заголовок?
        if inHeader(absX, absY) then
            dragging = true
            dragDX = absX - window.x
            dragDY = absY - window.y
            return
        end
        local target = buttonAt(absX, absY)
        if target ~= nil then
            target.onPress()  -- у Button callback обязателен (required)
            return
        end
        local e = editAt(absX, absY)
        if e ~= nil then
            focusedEdit = e
            return
        end
        focusedEdit = nil
    else
        dragging = false
    end
    hovered = true
end)

addEventHandler("onClientCursorMove", function(_, _, absX, absY)
    if not dragging then return end
    window.x = absX - dragDX
    window.y = absY - dragDY
    window:moveBy(0, 0)
end)

-- ввод в Edit (P5: текст без IME — onClientCharacter)
addEventHandler("onClientCharacter", root, function(char)
    if focusedEdit ~= nil then
        focusedEdit:inputCharacter(char)
    end
end)

addEventHandler("onClientKey", function(button, down)
    if not down then return end
    if focusedEdit ~= nil and button == "backspace" then
        focusedEdit:inputKey("backspace")
    end
end)

-- ---------------------------------------------------------------- кадр

local function onFrame()
    frame.run(canvas)
    canvas:drain(backend)
end

-- единственный обработчик кадра; приоритет — из настроек
addEventHandler("onClientRender", root, onFrame, false,
    settings.priority == "low" and "low" or settings.priority)

DXUI.boot = {
    version = "0.1.0",
    demo = {
        window = window,
        edit = edit,
    },
}
