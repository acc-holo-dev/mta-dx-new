-- node/node.lua — узел дерева: свойства, дети, сигналы, уничтожение
--
-- Свойства читаются/пишутся ТОЛЬКО через metamethods (node.<prop> = v):
-- прямая запись в _data извне запрещена (task.md §3.2).
--
-- Все внутренние поля живут в ЕДИНОМ raw-поле "_" (Node.__internals):
-- Lua вызывает __newindex только для отсутствующих ключей, поэтому единственный
-- способ запретить запись n._data = ... снаружи — не иметь таких raw-полей.
-- Поле "_" само по записи не проверяется: internals — контракт ядра.

local rawget = rawget
local rawset = rawset
local pairs = pairs
local table_remove = table.remove
local error = error

local DXUI = _G.DXUI

local class = DXUI.class
local signal = DXUI.signal
local prop = DXUI.prop

local Node = class.define("Node")

local liveCount = 0

function Node.getLiveCount()
    return liveCount
end

-- поиск метода по __super-цепочке (поддержка наследования из registry/)
local function findMethod(cls, key)
    local cur = cls
    while cur do
        local m = rawget(cur, key)
        if m ~= nil then return m end
        cur = rawget(cur, "__super")
    end
    return nil
end

-- внутренности узла; снаружи читать можно, писать — нельзя
local function internals(node)
    return rawget(node, "_")
end

-- ------------------------------------------------------------------ create

function Node.__init(self, widgetType, schema)
    rawset(self, "_", {
        widgetType = widgetType or "Node",
        schema     = schema or {},
        data       = {},       -- значения свойств (только через prop)
        children   = {},       -- ipairs священен: nil-дыр нет (task.md §10)
        parent     = nil,
        signals    = nil,      -- lazily: name -> signal
        destroyed  = false,
        dirtySet   = nil,      -- флаг dirty-списков (см. node/prop.lua)
    })
    liveCount = liveCount + 1
end

-- ------------------------------------------------------------------ signals

-- ленивое создание сигнала: без подписчиков — без объектов
function Node:signal(name)
    local inod = internals(self)
    if inod.signals == nil then
        inod.signals = {}
    end
    local s = inod.signals[name]
    if s == nil then
        s = signal.new()
        inod.signals[name] = s
    end
    return s
end

function Node:emit(name, ...)
    local inod = internals(self)
    if inod.signals then
        local s = inod.signals[name]
        if s then s:fire(...) end
    end
end

local function disconnectAllSignals(self)
    local inod = internals(self)
    if inod.signals then
        for _, s in pairs(inod.signals) do
            s:disconnectAll()
        end
        inod.signals = nil
    end
end

-- сумма живых подписок узла (для инспектора и тестов «после destroy = 0»)
function Node:getSubscriptionCount()
    local n = 0
    local inod = internals(self)
    if inod.signals then
        for _, s in pairs(inod.signals) do
            n = n + s:getConnectionCount()
        end
    end
    return n
end

-- ------------------------------------------------------------------ tree

function Node:addChild(child)
    if child == nil then
        error("Node:addChild: child is nil", 2)
    end
    if internals(self).destroyed then
        error("Node:addChild: node is destroyed", 2)
    end
    if child == self then
        error("Node:addChild: cannot add self", 2)
    end
    local old = internals(child).parent
    if old then
        old:removeChild(child)
    end
    internals(child).parent = self
    local children = internals(self).children
    children[#children + 1] = child
    return child
end

function Node:removeChild(child)
    local children = internals(self).children
    for i = 1, #children do
        if children[i] == child then
            table_remove(children, i)
            internals(child).parent = nil
            return true
        end
    end
    return false
end

function Node:getChildren()
    return internals(self).children
end

function Node:getParent()
    return internals(self).parent
end

-- полный разрыв: дети, сигналы, dirty-списки, ссылки родителя
function Node:destroy()
    local inod = internals(self)
    if inod.destroyed then return end
    inod.destroyed = true

    -- дети снизу вверх
    local children = inod.children
    for i = #children, 1, -1 do
        local c = children[i]
        if c ~= nil then c:destroy() end
    end

    local parent = inod.parent
    if parent then
        parent:removeChild(self)
    end
    disconnectAllSignals(self)
    prop.removeFromLists(self)
    liveCount = liveCount - 1
end

function Node:isDestroyed()
    return internals(self).destroyed
end

function Node:getWidgetType()
    return internals(self).widgetType
end

-- ------------------------------------------------------------------ property access

function Node.__index(self, key)
    -- внутренности (raw-поле "_" всегда существует)
    local v = rawget(self, key)
    if v ~= nil then return v end
    -- внутренние поля не читаются через __index: их нет в raw,
    -- а схемы про них не знают; методы с "_" в начале не выпускаем
    if key:sub(1, 1) == "_" then
        return findMethod(Node, key)
    end
    local m = findMethod(Node, key)
    if m ~= nil then return m end
    return prop.get(self, key)
end

function Node.__newindex(self, key, value)
    if key:sub(1, 1) == "_" then
        error(("dxui: internal field '%s' is read-only from outside"):format(tostring(key)), 2)
    end
    if findMethod(Node, key) ~= nil then
        error(("dxui: '%s' is a reserved Node name"):format(tostring(key)), 2)
    end
    prop.set(self, key, value)
end

DXUI.Node = Node
return Node
