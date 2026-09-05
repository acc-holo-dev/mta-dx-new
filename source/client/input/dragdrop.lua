-- input/dragdrop.lua — единый менеджер drag-and-drop (task.md §4.3)
--
-- source -> target со slots:
--   dragdrop.setSource(node, payload)   — node становится перетаскиваемой:
--     press + drag (порог dispatcher 4px) открывают сессию и захватывают
--     указатель; события до release идут источнику
--   dragdrop.registerTarget(node, slots) — зоны приёма:
--     nil / "default"            — вся площадь виджета, слот "default"
--     { {id=, x=, y=, w=, h=}, … } — зоны в локальных координатах виджета
--
-- Сигналы цели:  dragEnter(payload, slot) / dragOver(payload, slot, x, y) /
--                dragLeave(payload) / drop(payload, slot, x, y)
-- Сигналы источника: dragStart() / dragEnd(accepted, target, slot)
-- Активная пара для инспектора: dragdrop.active() -> {source, target, slot}

local DXUI = _G.DXUI

local dragdrop = {}

-- слабые ключи: уничтоженный виджет выпадает из регистрации сам
local sources = setmetatable({}, { __mode = "k" }) -- node -> payload
local targets = setmetatable({}, { __mode = "k" }) -- node -> slots

local session = nil -- { source, payload, target, slot }

local function worldRect(node)
    local x, y = 0, 0
    local cur = node
    while cur do
        local l = rawget(cur, "_").lay
        x = x + l.x
        y = y + l.y
        cur = rawget(cur, "_").parent
    end
    local l = rawget(node, "_").lay
    return x, y, l.w, l.h
end

-- слот под точкой (экранные координаты); nil, если мимо виджета/зон
local function slotAt(node, px, py)
    local slots = targets[node]
    if slots == nil then return nil end
    local wx, wy, w, h = worldRect(node)
    local lx, ly = px - wx, py - wy
    if lx < 0 or ly < 0 or lx > w or ly > h then return nil end
    if slots == "default" then return "default" end
    for i = 1, #slots do
        local s = slots[i]
        if lx >= s.x and lx <= s.x + s.w and ly >= s.y and ly <= s.y + s.h then
            return s.id or tostring(i)
        end
    end
    return nil
end

-- hit по ВСЕМ видимым узлам (pre-order = Z: позже в дереве = выше).
-- Собственный обход, а не dispatcher.query: пространственный хеш
-- dispatcher индексирует только интерактивные узлы, а drop-target может
-- быть любым (Panel и т.п.).
local function hitAll(px, py)
    local best, bestOrder = nil, -1
    local order = 0
    local function walk(node, ox, oy)
        local inod = rawget(node, "_")
        if inod == nil then return end
        if inod.data.visible == false then return end
        local l = inod.lay
        if l == nil then return end
        local wx, wy = ox + l.x, oy + l.y
        if px >= wx and px <= wx + l.w and py >= wy and py <= wy + l.h then
            if order > bestOrder then
                best, bestOrder = node, order
            end
        end
        order = order + 1
        local children = inod.children
        for i = 1, #children do
            walk(children[i], wx, wy)
        end
    end
    local roots = DXUI.frame.roots()
    for i = 1, #roots do
        walk(roots[i], 0, 0)
    end
    return best
end

-- цель и слот под точкой: ближайший ЗАРЕГИСТРИРОВАННЫЙ предок попадания
-- (собственное поддерево источника не считается целью)
local function resolveTarget(px, py)
    local hit = hitAll(px, py)
    if hit ~= nil then
        if hit == session.source or DXUI.tree_ops.isAncestorOf(session.source, hit) then
            hit = nil
        end
    end
    local cur = hit
    while cur do
        if targets[cur] ~= nil then
            return cur, slotAt(cur, px, py)
        end
        cur = rawget(cur, "_").parent
    end
    return nil, nil
end

local function updateHover(px, py)
    if session == nil then return end
    local target, slot = resolveTarget(px, py)
    if target ~= session.target or slot ~= session.slot then
        if session.target then
            session.target:emit("dragLeave", session.payload)
        end
        session.target, session.slot = target, slot
        if target then
            target:emit("dragEnter", session.payload, slot)
        end
    elseif target then
        target:emit("dragOver", session.payload, slot, px, py)
    end
end

-- ---------------------------------------------------------------- регистрация

function dragdrop.setSource(node, payload)
    sources[node] = payload
    -- сессия открывается по первому drag (порог 4px dispatcher уже пройден)
    node:signal("drag"):connect(function(dx, dy, px, py)
        if session == nil then
            session = { source = node, payload = sources[node] }
            node:capturePointer()
            node:emit("dragStart")
        end
        updateHover(px, py)
    end)
    node:signal("release"):connect(function(px, py)
        if session == nil or session.source ~= node then return end
        updateHover(px, py)
        local s = session
        session = nil
        if s.target then
            s.target:emit("drop", s.payload, s.slot, px, py)
            node:emit("dragEnd", true, s.target, s.slot)
        else
            node:emit("dragEnd", false, nil, nil)
        end
    end)
end

function dragdrop.registerTarget(node, slots)
    targets[node] = slots or "default"
end

function dragdrop.unregister(node)
    sources[node] = nil
    targets[node] = nil
end

-- ---------------------------------------------------------------- интроспекция

function dragdrop.active()
    if session == nil then return nil end
    local sin = rawget(session.source, "_")
    local tin = session.target and rawget(session.target, "_") or nil
    return {
        source = sin and sin.widgetType or "?",
        target = tin and tin.widgetType or nil,
        slot = session.slot,
    }
end

function dragdrop.reset()
    session = nil
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.dragdrop = dragdrop
return dragdrop
