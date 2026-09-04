-- input/dispatcher.lua — очередь событий + жесты + MTA-мост
-- (MTA-whitelist: события платформы живут здесь и только здесь)
--
-- Контракт (task.md §3.4):
--   * очередь (пул) → раздача один раз за кадр ДО пасса раскладки;
--   * hit-test против геометрии ПРОШЛОГО кадра — то, что видел игрок;
--   * жесты: tap, long-press (500 мс), drag (порог 4px);
--   * capturePointer(): события до release идут владельцу;
--   * события виджетов: сигналы "press"/"click"/"drag"/"longPress"/"hover"
--     через node:signal(...) — triggerEvent внутри фреймворка запрещён.
--
-- Мост к платформе — dispatcher.install() (вызывает boot.lua в игре);
-- headless-тесты подают события через dispatcher.enqueue().

local rawget = rawget
local table_insert = table.insert
local table_remove = table.remove

local DXUI = _G.DXUI

local dispatcher = {}

local LONG_PRESS_MS = 500
local DRAG_THRESHOLD = 4

dispatcher.LONG_PRESS_MS = LONG_PRESS_MS
dispatcher.DRAG_THRESHOLD = DRAG_THRESHOLD

local sh = DXUI.hit_test.new()
local queue = {}     -- очередь событий (переставляемый буфер)
local qHead = 0

-- состояние активного указателя
local pointer = {
    down = false,
    x = 0, y = 0,
    downX = 0, downY = 0, downTime = 0,
    target = nil,     -- узел под нажатием
    dragging = false,
}
local captured = nil -- владелец capturePointer()

-- ---------------------------------------------------------------- очередь

-- kind: "click"|"move"|"key"|"char"|"wheel"
-- click: (button, state, x, y); move: (x, y); key: (key, down);
-- char: (ch); wheel: (dx, dy)
local function enqueue(kind, a, b, c, d)
    qHead = qHead + 1
    local ev = queue[qHead]
    if ev == nil then
        ev = {}
        queue[qHead] = ev
    end
    ev.kind = kind
    ev.a, ev.b, ev.c, ev.d = a, b, c, d
end

dispatcher.enqueue = enqueue

-- сброс состояния (тесты)
function dispatcher.reset()
    sh:clear()
    for i = 1, qHead do
        queue[i].kind = nil
    end
    qHead = 0
    pointer.down = false
    pointer.target = nil
    pointer.dragging = false
    captured = nil
end

-- ---------------------------------------------------------------- сбор геометрии

-- собирает интерактивные узлы дерева в пространственный хеш.
-- Геометрия lay = прошлый кадр: dispatch() зовётся ДО пасса раскладки.
local function isInteractive(node)
    local spec = rawget(node, "_renderSpec")
    if spec == nil then return false end
    if spec.interactive then return true end
    if spec.draggable then return true end
    return false
end

local function collect(node, ox, oy, order)
    local inod = rawget(node, "_")
    if inod == nil then return end
    if inod.data.visible == false then return end
    local l = inod.lay
    if l == nil then return end
    local wx = ox + l.x
    local wy = oy + l.y
    if isInteractive(node) then
        sh:insert(wx, wy, l.w, l.h, node, order)
        order = order + 1
    end
    local children = inod.children
    for i = 1, #children do
        order = collect(children[i], wx, wy, order)
    end
    return order
end

-- ---------------------------------------------------------------- модали

local function targetAllowed(target)
    local modal = DXUI.focus.getModal()
    if modal == nil then return true end
    if target == nil then return false end -- клики мимо модали игнорируются
    return DXUI.focus.isInsideModal(target, modal)
end

-- ---------------------------------------------------------------- жесты

local function dragStart(x, y)
    local dx = x - pointer.x
    local dy = y - pointer.y
    if not pointer.dragging then
        local sx = x - pointer.downX
        local sy = y - pointer.downY
        if sx * sx + sy * sy < DRAG_THRESHOLD * DRAG_THRESHOLD then
            return
        end
        pointer.dragging = true
    end
    local target = captured or pointer.target
    if target then
        target:emit("drag", dx, dy, x, y)
    end
    pointer.x, pointer.y = x, y
end

-- ---------------------------------------------------------------- события

local function onClick(button, state, x, y)
    if button ~= "left" then return end
    if state == "down" then
        pointer.down = true
        pointer.x = x
        pointer.y = y
        pointer.downX = x
        pointer.downY = y
        pointer.downTime = DXUI.time.now()
        pointer.target = sh:query(x, y)
        pointer.dragging = false
        if targetAllowed(pointer.target) and pointer.target ~= nil then
            pointer.target:emit("press", x, y)
        end
    else
        if pointer.down and pointer.target then
            if not pointer.dragging then
                local duration = DXUI.time.now() - pointer.downTime
                if duration >= LONG_PRESS_MS then
                    pointer.target:emit("longPress", x, y)
                elseif targetAllowed(pointer.target) then
                    local target = captured or pointer.target
                    DXUI.focus.set(target)
                    if DXUI.focus.isEditable(target) then
                        DXUI.focus.setEditing(true)
                    end
                    target:emit("click", x, y)
                    -- Button: callback обязателен по схеме (§4.1)
                    local onPress = rawget(target, "_").data.onPress
                    if onPress then
                        onPress(target)
                    end
                end
            end
        end
        pointer.down = false
        pointer.target = nil
        pointer.dragging = false
        captured = nil
    end
end

local function onMove(x, y)
    if pointer.down then
        dragStart(x, y)
    end
end

local function onKey(key, down)
    if not down then return end
    local focused = DXUI.focus.get()
    if key == "tab" then
        if DXUI.focus.isEditing() then
            -- Tab выходит из редактирования и двигается дальше
            DXUI.focus.setEditing(false)
        end
        local next = DXUI.focus.navigate(dispatcher.roots, 1)
        if next ~= nil and DXUI.focus.isEditable(next) then
            DXUI.focus.setEditing(true)
        end
    elseif key == "arrow_u" or key == "arrow_d" or key == "arrow_l" or key == "arrow_r" then
        if focused == nil then return end
        if DXUI.focus.isEditing() and DXUI.focus.isEditable(focused) then
            -- стрелка не выводит из поля (§3.5)
            if focused.inputKey then focused:inputKey(key, false) end
            return
        end
        -- обход по дереву раскладки: вверх/вниз = сосед
        local dir = (key == "arrow_u" or key == "arrow_l") and -1 or 1
        DXUI.focus.navigate(dispatcher.roots, dir)
    else
        if focused ~= nil and focused.inputKey then
            focused:inputKey(key, false)
        end
    end
end

local function onCharacter(ch)
    local focused = DXUI.focus.get()
    if focused == nil then return end
    if focused.inputCharacter then
        focused:inputCharacter(ch)
    end
end

local function onWheel(dx, dy)
    local focused = DXUI.focus.get()
    if focused == nil then return end
    focused:emit("wheel", dx, dy)
end

-- раздача: один раз за кадр, ДО пасса раскладки
function dispatcher.dispatch(roots)
    dispatcher.roots = roots
    -- пересборка пространственного хеша по геометрии прошлого кадра
    sh:clear()
    local order = 0
    for i = 1, #roots do
        order = collect(roots[i], 0, 0, order)
    end
    -- раздача накопленной очереди
    local n = qHead
    if n == 0 then return end
    qHead = 0
    local events = {}
    for i = 1, n do
        events[i] = queue[i]
    end
    for i = 1, n do
        local ev = events[i]
        if ev.kind == "click" then
            onClick(ev.a, ev.b, ev.c, ev.d)
        elseif ev.kind == "move" then
            onMove(ev.a, ev.b)
        elseif ev.kind == "key" then
            onKey(ev.a, ev.b)
        elseif ev.kind == "char" then
            onCharacter(ev.a)
        elseif ev.kind == "wheel" then
            onWheel(ev.a, ev.b)
        end
    end
end

-- ---------------------------------------------------------------- capture

-- события указателя до release идут владельцу
function dispatcher.capture(node)
    captured = node
end

function dispatcher.releaseCapture()
    captured = nil
end

function dispatcher.getCaptured()
    return captured
end

-- ---------------------------------------------------------------- MTA-мост

function dispatcher.install()
    addEventHandler("onClientClick", root, function(button, state, x, y)
        enqueue("click", button, state, x, y)
    end)
    addEventHandler("onClientCursorMove", root, function(_, _, x, y)
        enqueue("move", x, y)
    end)
    addEventHandler("onClientKey", root, function(button, down)
        enqueue("key", button, down)
    end)
    addEventHandler("onClientCharacter", root, function(ch)
        enqueue("char", ch)
    end)
    addEventHandler("onClientMouseWheel", root, function(dx, dy)
        enqueue("wheel", dx, dy)
    end)
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.dispatcher = dispatcher
return dispatcher
