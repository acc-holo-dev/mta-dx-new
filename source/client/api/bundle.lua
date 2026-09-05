-- api/bundle.lua — СГЕНЕРИРОВАН `python dxui.py build`. Не править руками.
-- Исходники всех модулей одной строкой: их исполняет потребитель import(2)
-- в собственной Lua VM (MTA-ресурсы изолированы, P2/P3 из task.md).

local BUNDLE = [========[
(function()
-- core/class.lua — минимальный OOP-хелпер (Lua 5.1, zero-dependency)
--
-- Соглашения:
--   * class.define(name, super) -> cls
--   * cls(...) и cls.new(...) — эквивалентные конструкторы; метод __init(obj, ...)
--     вызывается вручную В ЦЕПОЧКЕ (каждый __init решает, звать ли super).
--   * class.isinstance(obj, cls) — принадлежность по __super-цепочке класса объекта.

local setmetatable = setmetatable
local rawget = rawget
local type = type

local function define(name, super)
    if super ~= nil and type(super) ~= "table" then
        error(("class.define: super must be a table, got %s"):format(type(super)), 2)
    end

    local cls = {
        __name  = name,
        __super = super,
    }

    -- Наследование метаметодов доступа (Node и его подклассы определяют
    -- __index/__newindex ФУНКЦИЯМИ). Суперкласс с таблицей-__index —
    -- обычное поведение (cls.__index = cls).
    local superIndex = nil
    local superNewindex = nil
    if super ~= nil then
        superIndex = rawget(super, "__index")
        superNewindex = rawget(super, "__newindex")
    end

    if type(superIndex) == "function" then
        -- сначала raw-поле объекта, затем цепочка классов,
        -- в конце — фолбэк суперкласса (prop.get у Node)
        cls.__index = function(self, key)
            local cur = cls
            while cur do
                local v = rawget(cur, key)
                if v ~= nil then return v end
                cur = rawget(cur, "__super")
            end
            return superIndex(self, key)
        end
    else
        cls.__index = cls
    end

    if type(superNewindex) == "function" then
        -- внутренние поля "_" — только через rawset ядра (даём ошибить Node)
        -- методы самого класса (spec-методы виджета) допускают
        -- per-instance shadow; методы Node — зарезервированы (через super)
        cls.__newindex = function(self, key, value)
            if key:sub(1, 1) ~= "_" then
                local cur = cls
                while cur and cur ~= super do
                    if rawget(cur, key) ~= nil then
                        rawset(self, key, value)
                        return
                    end
                    cur = rawget(cur, "__super")
                end
            end
            superNewindex(self, key, value)
        end
    end

    function cls.new(...)
        local obj = setmetatable({}, cls)
        local init = rawget(cls, "__init")
        if init then init(obj, ...) end
        return obj
    end

    local mt = super and { __index = super } or {}
    mt.__call = function(self, ...)
        local obj = setmetatable({}, cls)
        local init = rawget(cls, "__init")
        if init then init(obj, ...) end
        return obj
    end

    return setmetatable(cls, mt)
end

-- isinstance(obj, cls): класс объекта (метатаблица obj) == cls или его наследник
local function isinstance(obj, cls)
    local cur = getmetatable(obj)
    while cur do
        if cur == cls then return true end
        cur = rawget(cur, "__super")
    end
    return false
end

-- methodOf(obj, name): метод по цепочке КЛАССОВ без prop.get-фолбэка Node.
-- Обычное чтение obj.name для несуществующего метода уходит в систему
-- свойств и бросает "property does not exist" — здесь безопасный nil.
-- Для диспетчера ввода: focused.inputKey как ГАРД прочесть нельзя.
local function methodOf(obj, name)
    local cur = getmetatable(obj)
    while cur do
        local v = rawget(cur, name)
        if v ~= nil then return v end
        cur = rawget(cur, "__super")
    end
    return nil
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.class = { define = define, isinstance = isinstance, methodOf = methodOf }
return _G.DXUI.class

end)();
(function()
-- core/log.lua — уровневый лог с категориями и rate-limit (zero-dependency)
--
--   * log.level("warn") — глобальный порог; ниже порога сообщения отбрасываются.
--   * log.emit(level, category, fmt, ...) — форматирование только если
--     сообщение реально пишется ( горячий путь не платит за __tostring).
--   * log.setSink(f) — приёмщик: f(level, category, msg, timeMs); по умолчанию — io.stderr.
--   * log.rateLimit(category, msg, n) — не более n повторов подряд.
--
-- boot.lua подменяет sink на outputConsoleBox/outputDebugString.

local type = type
local pairs = pairs
local select = select
local tostring = tostring
local format = string.format
local tconcat = table.concat

local LEVELS = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, off = 99 }
local current = LEVELS.info
local sink = nil
local counters = {}
local rateN = 10

local function ensure(level)
    local l = LEVELS[level]
    if not l then error(("log: unknown level %q"):format(tostring(level)), 2) end
    return l
end

local function emit(level, category, fmt, ...)
    local lv = LEVELS[level]
    if not lv then
        error(("log: unknown level %q"):format(tostring(level)), 2)
    end
    if lv < current then return end
    local msg
    if select("#", ...) == 0 then
        msg = fmt
    else
        local ok, res = pcall(format, fmt, ...)
        msg = ok and res or tostring(fmt)
    end
    if sink == nil then
        sink = function(_level, _cat, m)
            io.stderr:write(("[%s][%s] %s\n"):format(_level, _cat, m))
        end
    end
    sink(level, category, msg)
end

local Log = {}

for name, lv in pairs(LEVELS) do
    if name ~= "off" then
        Log[name] = function(category, fmt, ...)
            if lv >= current then
                emit(name, category, fmt, ...)
            end
        end
    end
end

function Log.setLevel(level)
    ensure(level)
    current = LEVELS[level]
end

function Log.setSink(f)
    if type(f) ~= "function" then
        error("log.setSink: sink must be a function", 2)
    end
    sink = f
end

-- rate-limit: категория+ключ не более n сообщений подряд, дальше глушим
function Log.rateLimit(category, key, n)
    local k = category .. "\0" .. tostring(key)
    local c = counters[k]
    if c == nil then
        counters[k] = 1
        return true
    end
    if c >= (n or rateN) then
        return false
    end
    counters[k] = c + 1
    return true
end

function Log.resetCounters()
    counters = {}
end

-- тестовый доступ
function Log._test()
    return LEVELS, current
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.log = Log
return Log

end)();
(function()
-- core/signal.lua — сигнал: GoodSignal-контракт + изоляция ошибок
--
-- Требования (task.md §3.3):
--   * connect(fn, opts) -> connection; disconnect() внутри emit не рвёт обход
--   * opts.once — одноразовый обработчик
--   * opts.weak — слабая связь: если handler стал мусором, связь исчезает после GC
--   * изоляция ошибок: dev — pcall + sink (упавший не рвёт остальных), prod — без обёрток
--   * внутри фреймворка triggerEvent запрещён (здесь его просто нет)
--
-- Реализация: массив связей; удаление помечает слот false и компактифицирует
-- после завершения всех вложенных emit. Слабая связь хранит handler в
-- weak-value таблице — сбор handler-GC проверяется при fire.

local setmetatable = setmetatable
local type = type
local pcall = pcall
local error = error

local IS_DEV = true
local onError -- необязательный приёмник ошибок dev-изоляции: f(err, traceback)

local Connection = {}
Connection.__index = Connection

local Signal = {}
Signal.__index = Signal

function Connection:disconnect()
    local list = self._list
    if list then
        -- маркер false — «дырок» не создаём, см. Signal:_compact
        for i = 1, #list do
            if list[i] == self then
                list[i] = false
                break
            end
        end
        self._list = nil
        self._weakbox = nil
    end
end

-- соединён ли обработчик (false после disconnect и для once, отработавшего fire)
-- прим. для weak-связей true означает только «не отключён вручную»
function Connection:isConnected()
    return self._list ~= nil
end

function Signal.new()
    return setmetatable({
        _list      = {},  -- список связей; false = удалённая
        _iterating = 0,   -- глубина вложенных fire
        _dirty     = false,
    }, Signal)
end

function Signal:connect(handler, opts)
    if type(handler) ~= "function" then
        error("signal:connect: handler must be a function", 2)
    end
    opts = opts or {}

    local conn = setmetatable({}, Connection)
    conn._signal = self
    conn._list   = self._list
    conn._once   = opts.once == true

    if opts.weak then
        conn._weakbox = setmetatable({ fn = handler }, { __mode = "v" })
    else
        conn._handler = handler
    end

    self._list[#self._list + 1] = conn
    return conn
end

local function _invoke(self, fn, ...)
    if IS_DEV then
        local ok, err = pcall(fn, ...)
        if not ok then
            if onError then
                onError(err, debug.traceback and debug.traceback("", 2) or "")
            else
                error(err, 0)
            end
        end
    else
        fn(...)
    end
end

function Signal:fire(...)
    local list = self._list
    local count = #list
    if count == 0 then return end

    self._iterating = self._iterating + 1

    for i = 1, count do
        local conn = list[i]
        if conn ~= false and conn ~= nil then
            local handler
            if conn._weakbox then
                handler = conn._weakbox.fn
                if handler == nil then
                    -- handler собран GC — связь исчезает
                    list[i] = false
                    conn._list = nil
                    self._dirty = true
                end
            else
                handler = conn._handler
            end

            if handler then
                if conn._once then
                    list[i] = false
                    conn._list = nil
                    self._dirty = true
                end
                _invoke(self, handler, ...)
            end
        end
    end

    self._iterating = self._iterating - 1
    if self._iterating == 0 and self._dirty then
        self:_compact()
    end
end

function Signal:dispatch(...) self:fire(...) end
function Signal:emit(...) self:fire(...) end

function Signal:disconnectAll()
    for i = 1, #self._list do
        if self._list[i] ~= false then
            self._list[i]._list = nil
            self._list[i] = false
        end
    end
    self._dirty = true
    if self._iterating == 0 then
        self:_compact()
    end
end

function Signal:getConnectionCount()
    local n = 0
    for i = 1, #self._list do
        if self._list[i] ~= false then n = n + 1 end
    end
    return n
end

function Signal:_compact()
    local list = self._list
    local w = 1
    for i = 1, #list do
        local v = list[i]
        if v ~= false then
            list[w] = v
            w = w + 1
        end
    end
    for i = #list, w, -1 do
        list[i] = nil
    end
    self._dirty = false
end

local function setDevMode(dev, errSink)
    IS_DEV = dev == true
    onError = errSink
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.signal = { new = Signal.new, setDevMode = setDevMode }
return _G.DXUI.signal

end)();
(function()
-- core/pool.lua — пул объектов
--
--   * pool.new(reset, alloc) — reset(obj) подготавливает к переиспользованию,
--     alloc() создаёт новый объект, если свободных нет.
--   * get()/release(obj) — амортизированное O(1), zero allocations steady-state.
--   * release() объекта, не принадлежащего пулу, — ошибка в dev.
--
-- Использование: вектора, цвета, команды холста (task.md §6.1 «пулы объектов»).

local type = type
local tremove = table.remove
local error = error

local Pool = {}
Pool.__index = Pool

local function new(reset, alloc)
    if type(reset) ~= "function" or type(alloc) ~= "function" then
        error("pool.new: reset and alloc must be functions", 2)
    end
    return setmetatable({
        _free  = {},
        _reset = reset,
        _alloc = alloc,
    }, Pool)
end

function Pool:get()
    local free = self._free
    local n = #free
    if n > 0 then
        local obj = free[n]
        free[n] = nil
        return obj
    end
    return self._alloc()
end

function Pool:release(obj)
    if obj == nil then return end
    self._reset(obj)
    self._free[#self._free + 1] = obj
end

function Pool:size()
    return #self._free
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.pool = { new = new }
return _G.DXUI.pool

end)();
(function()
-- core/time.lua — единый клок фреймворка
--
-- Правило task.md §5: «единый клок из core/time — никаких таймеров в виджетах».
-- Источник времени подключается один раз: boot.lua решает, живём ли мы в MTA
-- (getTickCount + dxui-настройки) или в headless-тестах (os.clock монотонного
-- источника). Все остальные модули читают только time.now().

local type = type

local nowFn = function() return 0 end

-- возвращает ms с фиксированной точки отсчёта (монотонно)
local function now()
    return nowFn()
end

-- подключение источника: boot.lua / тестовый раннер
local function setSource(fn)
    if type(fn) ~= "function" then
        error("time.setSource: fn must be a function", 2)
    end
    nowFn = fn
end

-- глава зоопарка: производные утилиты
local function seconds(sec)
    return sec * 1000
end

local function minutes(min)
    return min * 60000
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.time = { now = now, setSource = setSource, seconds = seconds, minutes = minutes }
return _G.DXUI.time

end)();
(function()
-- node/prop.lua — схема свойств + инвалидация (task.md §3.2)
--
-- Контракт:
--   * Схема свойства: { type, default, invalidates = { DIRTY.RENDER, ... }, doc }.
--   * Запись — только через метаметоды Node; прямая запись в _data извне запрещена.
--   * Инвалидация — dirty-списки LAYOUT/RENDER; узел в списке единожды при N записей.
--   * Равное значение не инвалидирует.
--   * Несоответствие типа → ошибка в dev (имя виджета, свойство, ожидание); лог в prod.
--   * Необъявленное свойство → ошибка схемы в dev.
--   * transform(v, node) — однократный парсинг на установке (#hex → упакованное число и т.п.).

local type = type
local rawget = rawget
local setmetatable = setmetatable
local pairs = pairs
local error = error

local prop = {}

prop.DIRTY = { LAYOUT = 1, RENDER = 2 }

local DIRTY = prop.DIRTY

-- ---------------------------------------------------------------- dirty lists

local lists = {
    [DIRTY.LAYOUT] = {},
    [DIRTY.RENDER] = {},
}

local IS_DEV = true
local errorSink = nil -- f(level, msg) для prod-лога; dev-режим ошибается

local function mark(node, flag)
    -- dedupe: узел попадает в список единожды при N записей
    local inod = node._
    local set = inod.dirtySet
    if set == nil then
        set = {}
        inod.dirtySet = set
    end
    if not set[flag] then
        set[flag] = true
        lists[flag][#lists[flag] + 1] = node
    end
end

-- Обход пасса: вызывает fn(node) для каждого грязного узла.
-- Узлы, отмеченные грязными ВО ВРЕМЯ обхода, обрабатываются следующим flush —
-- новые записи не пропадают и не искажают текущую пассу.
function prop.flush(flag, fn)
    local list = lists[flag]
    local n = #list
    if n == 0 then return 0 end
    for i = 1, n do
        local node = list[i]
        local set = node._ and node._.dirtySet
        if set then
            set[flag] = nil
        end
        fn(node)
    end
    -- снимаем только обработанные элементы; новые — в конце списка
    for i = n, 1, -1 do
        table.remove(list, i)
    end
    return n
end

-- удаление узла из всех списков (destroy) — O(списки)
local function removeFromLists(node)
    for _, list in pairs(lists) do
        for i = #list, 1, -1 do
            if list[i] == node then
                table.remove(list, i)
            end
        end
    end
    node._.dirtySet = nil
end

-- ---------------------------------------------------------------- validation

local function checkType(expected, value)
    local t = type(value)
    if expected == "color" then
        return t == "string" or t == "table"
    end
    return t == expected
end

-- ---------------------------------------------------------------- schema API

-- компилирует схему: key -> { type, default, invalidates, doc, transform }
function prop.compile(name, schema)
    local compiled = {}
    for key, spec in pairs(schema) do
        if type(spec) ~= "table" then
            error(("prop.compile[%s.%s]: spec must be a table"):format(tostring(name), tostring(key)), 2)
        end
        if spec.type == nil then
            error(("prop.compile[%s.%s]: spec.type required"):format(tostring(name), tostring(key)), 2)
        end
        local entry = {
            key         = key,
            type        = spec.type,
            default     = spec.default,
            transform   = spec.transform,
            doc         = spec.doc or "",
            invalidates = {},
        }
        -- привязка к токену темы (style/theme батчево обновляет default)
        if spec.token ~= nil then
            entry.token = spec.token
        end
        -- переход (style/transitions): запись твинит вместо прыжка
        if spec.transition ~= nil then
            entry.transition = spec.transition
        end
        if spec.invalidates then
            for _, f in ipairs(spec.invalidates) do
                entry.invalidates[#entry.invalidates + 1] = f
            end
        end
        compiled[key] = entry
    end
    return compiled
end

local function devError(msg)
    if IS_DEV then
        error(msg, 3)
    elseif errorSink then
        errorSink("error", msg)
    end
end

-- установка значения напрямую (твины пишут так: без планирования переходов)
local function forceSet(node, key, value)
    local inod = node._
    local spec = inod.schema[key]
    local data = inod.data
    if data[key] == value then
        return false
    end
    if spec.transform then
        value = spec.transform(value, node)
    end
    data[key] = value
    local inv = spec.invalidates
    for i = 1, #inv do
        mark(node, inv[i])
    end
    return true
end

-- установка значения через схему; возвращает true, если значение изменилось.
-- Свойство с transition = { duration, easing } не прыгает: prop.set
-- планирует твин (anim/tween), интерполяция идёт через ту же систему.
function prop.set(node, key, value)
    local inod = node._
    local spec = inod.schema[key]
    if spec == nil then
        devError(("dxui: property '%s' does not exist on '%s'"):format(tostring(key), tostring(inod.widgetType)))
        return false
    end
    if not checkType(spec.type, value) then
        devError(("dxui: %s.%s expects %s, got %s"):format(
            tostring(inod.widgetType), tostring(key), spec.type, type(value)))
        return false
    end
    if spec.transform then
        value = spec.transform(value, node)
    end
    local data = inod.data
    if data[key] == value then
        return false -- равное значение не инвалидирует
    end
    local tweener = _G.DXUI.tween
    if spec.transition ~= nil and tweener ~= nil then
        local tweening = inod.tweening
        if tweening == nil or not tweening[key] then
            tweener.transitionTo(node, key, value, spec.transition)
            return true
        end
        -- интерполяция идёт: твин сам дожмёт до целевого значения
        return false
    end
    data[key] = value
    local inv = spec.invalidates
    for i = 1, #inv do
        mark(node, inv[i])
    end
    return true
end

local function get(node, key)
    local inod = node._
    local spec = inod.schema[key]
    if spec == nil then
        devError(("dxui: property '%s' does not exist on '%s'"):format(tostring(key), tostring(inod.widgetType)))
        return nil
    end
    local v = inod.data[key]
    if v == nil then return spec.default end
    return v
end
prop.get = get

local function setDevMode(dev, sink)
    IS_DEV = dev == true
    errorSink = sink
end

prop.mark = mark
prop.removeFromLists = removeFromLists
prop.setDevMode = setDevMode
prop.forceSet = forceSet

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.prop = prop
return prop

end)();
(function()
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

end)();
(function()
-- node/tree_ops.lua — операции над деревом и Z-порядком
--
-- Z-порядок = позиция в children родителя (раньше = ниже).
-- В API узла — индекс в _children родителя; сквозной Z-порядок пиксельного
-- пересечения вычисляет input/hit_test по геометрии прошлого кадра.

local rawget = rawget
local error = error
local table_remove = table.remove

local DXUI = _G.DXUI
local Node = DXUI.Node

local tree_ops = {}

local function checkNode(node, fn)
    if node == nil then
        error(("tree_ops.%s: node is nil"):format(fn), 2)
    end
end

local function childrenOf(node)
    return rawget(node, "_").children
end

-- --- Z-порядок ------------------------------------------------------------

-- вверх в стопке родителя (к последнему индексу); у потолка — no-op
function tree_ops.bringToFront(node)
    checkNode(node, "bringToFront")
    local parent = rawget(node, "_").parent
    if parent == nil then return false end
    local siblings = childrenOf(parent)
    local n = #siblings
    if n <= 1 then return false end
    for i = 1, n do
        if siblings[i] == node then
            if i == n then return false end
            table_remove(siblings, i)
            siblings[n] = node
            return true
        end
    end
    return false
end

-- вниз в стопке родителя (к первому индексу)
function tree_ops.sendToBack(node)
    checkNode(node, "sendToBack")
    local parent = rawget(node, "_").parent
    if parent == nil then return false end
    local siblings = childrenOf(parent)
    local n = #siblings
    for i = 1, n do
        if siblings[i] == node then
            if i == 1 then return false end
            table_remove(siblings, i)
            table.insert(siblings, 1, node)
            return true
        end
    end
    return false
end

-- переставить узел внутри родителя на заданный индекс (0-based slot)
function tree_ops.setIndex(node, index)
    checkNode(node, "setIndex")
    local parent = rawget(node, "_").parent
    if parent == nil then return false end
    local siblings = childrenOf(parent)
    local n = #siblings
    if index < 1 or index > n then
        error(("tree_ops.setIndex: index %d out of range 1..%d"):format(index, n), 2)
    end
    local pos
    for i = 1, n do
        if siblings[i] == node then pos = i break end
    end
    if pos == nil then return false end
    table_remove(siblings, pos)
    local at = pos < index and index + 1 or index
    table.insert(siblings, at, node)
    return true
end

-- --- обхождение -----------------------------------------------------------

-- pre-order: узел, затем дети слева направо; fn(node) возвращает false = не спускаться
function tree_ops.walk(root, fn)
    checkNode(root, "walk")
    if fn(root) == false then return end
    local children = childrenOf(root)
    for i = 1, #children do
        tree_ops.walk(children[i], fn)
    end
end

-- вверх по цепочке родителей; fn(node) возвращает true = прекратить
function tree_ops.walkUp(node, fn)
    checkNode(node, "walkUp")
    local cur = rawget(node, "_").parent
    while cur do
        if fn(cur) then return end
        cur = rawget(cur, "_").parent
    end
end

-- первый узел (включая root), удовлетворяющий predicate
function tree_ops.findFirst(root, predicate)
    local found = nil
    tree_ops.walk(root, function(n)
        if found == nil and predicate(n) then found = n end
    end)
    return found
end

function tree_ops.isAncestorOf(ancestor, node)
    checkNode(ancestor, "isAncestorOf")
    checkNode(node, "isAncestorOf")
    local cur = rawget(node, "_").parent
    while cur do
        if cur == ancestor then return true end
        cur = rawget(cur, "_").parent
    end
    return false
end

DXUI.tree_ops = tree_ops
return tree_ops


end)();
(function()
-- layout/lay.lua — параметры раскладки узла
--
-- Раскладка оперяет интерфейсом: node.children (список) и node.lay (эта таблица).
-- G4 (widget/base) будет проектировать свои свойства в lay; виджеты-владельцы
-- живут своей жизнью, layout ни от кого кроме core не зависит.
--
-- Поля lay:
--   x, y, w, h      — геометрия (w/h — собственный размер; flex может менять)
--   dir             — "column" | "row" (направление главной оси)
--   gap             — интервал между детьми
--   align           — выравнивание по поперечной оси: "start"|"center"|"end"|"stretch"
--   grow, shrink    — доли в главном направлении
--   basis           — фиксированный размер в главном направлении (до grow)
--   padding         — {l, t, r, b} внутренние отступы контейнера
--   minW, maxW, minH, maxH — ограничения (constraints.lua)
--   anchor          — привязка к краям родителя { left|right|top|bottom = n, centerX, centerY }
--   scrollX, scrollY — смещение содержимого (ScrollPanel)
--   skipLayout      — true: ребёнок раскладкой не управляется (anchor/absolute)

local type = type
local pairs = pairs

local lay = {}

local DEFAULTS = {
    x = 0,
    y = 0,
    w = 0,
    h = 0,
    dir = "column",
    gap = 0,
    align = "start",
    grow = 0,
    shrink = 1,
    minW = 0,
    minH = 0,
    maxW = math.huge,
    maxH = math.huge,
    scrollX = 0,
    scrollY = 0,
    skipLayout = false,
}

-- создать lay-таблицу поверх переопределений
function lay.new(opts)
    local t = {}
    for k, v in pairs(DEFAULTS) do
        t[k] = v
    end
    t.padding = nil
    t.anchor = nil
    t.basis = nil
    if opts then
        for k, v in pairs(opts) do
            t[k] = v
        end
    end
    -- padding приходит числом или списком — нормализуем один раз при создании
    if t.padding ~= nil then
        t.padding = lay.normalizePadding(t.padding)
    end
    return t
end

function lay.valid(l)
    if type(l) ~= "table" then
        error("lay: expected a lay table", 2)
    end
end

local PAD_KEYS = { "l", "t", "r", "b" }

-- нормализация padding: число | {10} | {10,20} | {10,20,30,40} | {l=,t=,r=,b=}
function lay.normalizePadding(p)
    if p == nil then
        return nil
    end
    if type(p) == "number" then
        return { l = p, t = p, r = p, b = p }
    end
    -- уже нормализованная форма
    if p.l ~= nil or p.t ~= nil or p.r ~= nil or p.b ~= nil then
        return {
            l = p.l or 0, t = p.t or 0, r = p.r or 0, b = p.b or 0,
        }
    end
    local out = { l = 0, t = 0, r = 0, b = 0 }
    local n = #p
    if n == 1 then
        out.l, out.t, out.r, out.b = p[1], p[1], p[1], p[1]
    elseif n == 2 then
        out.t, out.b, out.l, out.r = p[1], p[1], p[2], p[2]
    elseif n >= 4 then
        out.l, out.t, out.r, out.b = p[1], p[2], p[3], p[4]
    end
    return out
end

-- публикация в глобальный namespace
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.lay = lay
return lay

end)();
(function()
-- layout/constraints.lua — ограничения размеров
--
-- clamp(lay): возвращает w/h узла, зажатые min/max (и aspect, если задан).

local math = math
local type = type

local constraints = {}

function constraints.clamp(lay)
    local w = lay.w or 0
    local h = lay.h or 0

    if lay.minW then w = math.max(w, lay.minW) end
    if lay.maxW then w = math.min(w, lay.maxW) end
    if lay.minH then h = math.max(h, lay.minH) end
    if lay.maxH then h = math.min(h, lay.maxH) end

    if lay.aspect then
        -- сохранение пропорций: приоритет у главного измерения
        if lay.dir == "row" then
            h = w / lay.aspect
            if h > (lay.maxH or math.huge) then h = lay.maxH end
            if h < (lay.minH or 0) then h = lay.minH end
            w = h * lay.aspect
        else
            w = h * lay.aspect
            if w > (lay.maxW or math.huge) then w = lay.maxW end
            if w < (lay.minW or 0) then w = lay.minW end
            h = w / lay.aspect
        end
    end

    lay.w = w
    lay.h = h
    return w, h
end

-- публикация в глобальный namespace
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.constraints = constraints
return constraints

end)();
(function()
-- layout/flex.lua — главная пасса раскладки (column | row)
--
-- Алгоритм (по мотивам Flutter Row/Column main-axis):
--   1. детям с basis назначается фиксированный размер главной оси;
--   2. остаток распределяется пропорционально grow;
--   3. позиционирование с учётом gap, align (поперечная ось),
--      padding контейнера и scrollX/scrollY.
-- Дети с skipLayout (anchor/absolute) игнорируются флексом.

local math = math
local type = type

local flex = {}

local function contentBox(lay)
    local p = lay.padding
    if p then
        return p.l or 0, p.t or 0, p.r or 0, p.b or 0
    end
    return 0, 0, 0, 0
end

-- возвращает (main, cross) размер контента контейнера
local function containerSize(lay)
    local pl, pt, pr, pb = contentBox(lay)
    local w = (lay.w or 0) - pl - pr
    local h = (lay.h or 0) - pt - pb
    if w < 0 then w = 0 end
    if h < 0 then h = 0 end
    return w, h, pl, pt
end

function flex.apply(node)
    local lay = node.lay
    local children = node.children
    if children == nil then return 0, 0 end

    local contentW, contentH, pl, pt = containerSize(lay)
    local isRow = lay.dir == "row"
    local gap = lay.gap or 0
    local scrollX = lay.scrollX or 0
    local scrollY = lay.scrollY or 0

    -- 1) разбиение детей на flex-участники
    local count = 0
    for _ = 1, #children do
        local c = children[_]
        if c and not c.lay.skipLayout then
            count = count + 1
        end
    end

    if count == 0 then return 0, 0 end

    -- 2) главные размеры: basis фиксирует, grow делит остаток
    local fixedTotal = 0
    local growTotal = 0
    for i = 1, #children do
        local c = children[i]
        if c and not c.lay.skipLayout then
            local cLay = c.lay
            if cLay.basis then
                fixedTotal = fixedTotal + cLay.basis
            else
                fixedTotal = fixedTotal + (isRow and cLay.w or cLay.h or 0)
            end
            if cLay.grow and cLay.grow > 0 then
                growTotal = growTotal + cLay.grow
            end
        end
    end

    local avail = (isRow and contentW or contentH)
    local spaceGaps = gap * (count - 1)
    local free = avail - fixedTotal - spaceGaps
    if free < 0 then free = 0 end

    -- 3) расстановка
    local cursor = isRow and pl or pt
    for i = 1, #children do
        local c = children[i]
        if c and not c.lay.skipLayout then
            local cLay = c.lay
            local main
            if cLay.basis then
                main = cLay.basis
            elseif cLay.grow and cLay.grow > 0 then
                main = free * cLay.grow / growTotal
            else
                main = isRow and (cLay.w or 0) or (cLay.h or 0)
            end

            -- поперечный размер и выравнивание
            local cross
            local crossPos
            if isRow then
                cross = cLay.h or 0
                crossPos = pt
                if lay.align == "center" then
                    crossPos = pt + (contentH - cross) / 2
                elseif lay.align == "end" then
                    crossPos = pt + contentH - cross
                elseif lay.align == "stretch" then
                    cLay.h = contentH
                    cross = contentH
                end
                cLay.x = cursor - scrollX
                cLay.y = crossPos - scrollY
                if not cLay.basis or cLay.grow and cLay.grow > 0 then
                    cLay.w = main
                end
            else
                cross = cLay.w or 0
                crossPos = pl
                if lay.align == "center" then
                    crossPos = pl + (contentW - cross) / 2
                elseif lay.align == "end" then
                    crossPos = pl + contentW - cross
                elseif lay.align == "stretch" then
                    cLay.w = contentW
                    cross = contentW
                end
                cLay.y = cursor - scrollY
                cLay.x = crossPos - scrollX
                if not cLay.basis or cLay.grow and cLay.grow > 0 then
                    cLay.h = main
                end
            end

            cursor = cursor + main + gap
        end
    end

    return contentW, contentH
end

-- публикация в глобальный namespace
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.flex = flex
return flex

end)();
(function()
-- layout/grid.lua — равномерная сетка
--
-- node.lay.grid = { cols = n, gap = m } (или cols = 0 -> авто: по строкам через rows)
-- Ячейки одинаковые: cellW = (contentW - (cols-1)*gap) / cols.

local math = math

local grid = {}

function grid.apply(node)
    local lay = node.lay
    local children = node.children
    if children == nil then return 0, 0 end

    local spec = lay.grid
    if not spec or not spec.cols or spec.cols < 1 then
        error("grid.apply: node.lay.grid.cols required", 2)
    end

    local cols = spec.cols
    local gap = spec.gap or 0
    local w = lay.w or 0
    local h = lay.h or 0

    local cellW = (w - gap * (cols - 1)) / cols
    local rowsCount = math.ceil(#children / cols)
    -- высота строки: подбирается так, чтобы заполнить контейнер
    local cellH = cellW
    if rowsCount > 0 then
        cellH = (h - gap * (rowsCount - 1)) / rowsCount
    end

    for i = 1, #children do
        local c = children[i]
        if c and not c.lay.skipLayout then
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            c.lay.x = col * (cellW + gap)
            c.lay.y = row * (cellH + gap)
            c.lay.w = cellW
            c.lay.h = cellH
        end
    end

    return w, h
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.grid = grid
return grid

end)();
(function()
-- layout/anchors.lua — привязка ребёнка к краям родителя
--
-- c.lay.anchor = { left = n } | { right = n } | { centerX = n } и комбинации
-- (по вертикали top/bottom/centerY). Размер задаётся явно (w/h) либо
-- растягивается между краями (left + right).
--
-- якоря применяются ПОСЛЕ флекс-пассы: дети с якорями должны иметь skipLayout.

local anchors = {}

local function applyAxis(anchor, parentStart, parentSize, size, lStart)
    -- lStart — дефолт слева (иначе просто позиция считается «старой»)
    if anchor.left ~= nil and anchor.right ~= nil then
        local x = parentStart + anchor.left
        local w = parentSize - anchor.left - anchor.right
        if w < 0 then w = 0 end
        return x, w
    elseif anchor.left ~= nil then
        return parentStart + anchor.left, size
    elseif anchor.right ~= nil then
        return parentStart + parentSize - size - anchor.right, size
    elseif anchor.centerX ~= nil then
        return parentStart + (parentSize - size) / 2 + anchor.centerX, size
    end
    return lStart, size
end

function anchors.apply(node)
    local children = node.children
    if children == nil then return end
    local lay = node.lay
    local pl, pt = 0, 0
    if lay.padding then
        pl = lay.padding.l or 0
        pt = lay.padding.t or 0
    end
    for i = 1, #children do
        local c = children[i]
        if c and c.lay.anchor then
            local a = c.lay.anchor
            local cw = c.lay.w or 0
            local ch = c.lay.h or 0
            c.lay.x, c.lay.w = applyAxis(a, pl, lay.w or 0, cw, c.lay.x)
            c.lay.y, c.lay.h = applyAxis(
                { left = a.top, right = a.bottom, centerX = a.centerY },
                pt, lay.h or 0, ch, c.lay.y
            )
        end
    end
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.anchors = anchors
return anchors

end)();
(function()
-- layout/measure.lua — замер содержимого
--
-- measure(node): рекурсивно считает минимальный размер контейнера по детям
-- (полезно для autoSize и дляgolden-сравнения с флексом).

local measure = {}

local function measureNode(node)
    local lay = node.lay
    local children = node.children

    if children == nil or #children == 0 then
        return lay.w or 0, lay.h or 0
    end

    local isRow = lay.dir == "row"
    local gap = lay.gap or 0
    local mainTotal = 0
    local crossMax = 0
    local count = 0

    for i = 1, #children do
        local c = children[i]
        if c and not c.lay.skipLayout then
            local w, h = measureNode(c)
            if isRow then
                mainTotal = mainTotal + w
                if h > crossMax then crossMax = h end
            else
                mainTotal = mainTotal + h
                if w > crossMax then crossMax = w end
            end
            count = count + 1
        end
    end

    local main = mainTotal + gap * (count - 1)
    if isRow then
        return main, crossMax
    else
        return crossMax, main
    end
end

measure.measure = measureNode

-- обёртка с учётом padding: внешний размер контейнера для уместить детей
function measure.fit(node)
    local lay = node.lay
    local w, h = measureNode(node)
    if lay.padding then
        w = w + (lay.padding.l or 0) + (lay.padding.r or 0)
        h = h + (lay.padding.t or 0) + (lay.padding.b or 0)
    end
    return w, h
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.measure = measure
return measure

end)();
(function()
-- registry/base.lua — базовый виджет: свойства геометрии + проекция в lay
--
-- Базовая схема (x/y/width/height/visible) есть у всех виджетов; запись
-- геометрии зеркалируется в node._.lay — раскладка (layout/) читает только lay.

local DXUI = _G.DXUI

local base = {}

-- базовая схема геометрии: у каждого виджета, расширяется спецификацией
function base.schema()
    local prop = DXUI.prop
    local DIRTY = prop.DIRTY
    return {
        x = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Позиция X относительно родителя",
        },
        y = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Позиция Y относительно родителя",
        },
        width = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Ширина виджета в пикселях",
        },
        height = {
            type = "number", default = 0, invalidates = { DIRTY.LAYOUT },
            doc = "Высота виджета в пикселях",
        },
        visible = {
            type = "boolean", default = true, invalidates = { DIRTY.RENDER },
            doc = "Видимость виджета",
        },
    }
end

-- словарь свойств -> поле lay для зеркалирования
function base.layMirror()
    return {
        x = "x",
        y = "y",
        width = "w",
        height = "h",
    }
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.base = base
return base

end)();
(function()
-- registry/registry.lua — реестр виджетов
--
-- КОНТРАКТ РАСШИРИЕМОСТИ (task.md §1): новый виджет = 1 файл, 0 правок ядра.
-- Виджет — таблица-спецификация:
--   { name = "Button", schema = {...}, init = fn?, render = fn, ... }
-- schema расширяет базовую схему геометрии; render(widget, canvas, x, y).

local DXUI = _G.DXUI
local class = DXUI.class
local Node = DXUI.Node
local prop = DXUI.prop
local base = DXUI.base
local lay_mod = DXUI.lay

local registry = {}
local widgets = {}   -- name -> class
local specs = {}     -- name -> spec

-- компиляция схемы виджета: базовая геометрия + спецификация
local function compileSchema(spec)
    local schema = base.schema()
    for k, v in pairs(spec.schema or {}) do
        schema[k] = v
    end
    -- зеркалирование геометрии в lay через transform
    local mirror = base.layMirror()
    for propName, layField in pairs(mirror) do
        local entry = schema[propName]
        if entry then
            local upstream = entry.transform
            entry.transform = function(v, node)
                local inod = rawget(node, "_")
                if inod and inod.lay then
                    inod.lay[layField] = v
                end
                if upstream then
                    return upstream(v, node)
                end
                return v
            end
        end
    end
    return prop.compile(spec.name, schema)
end

-- применяет стартовые свойства к узлу (конструктор виджета).
-- "children" не свойство: список детей забирает registry.create.
local function applyProps(node, props)
    if props == nil then return end
    for k, v in pairs(props) do
        if k ~= "children" then
            node[k] = v
        end
    end
end

function registry.define(spec)
    local name = spec.name
    if name == nil then
        error("registry.define: spec.name required", 2)
    end
    if spec.render == nil then
        error(("registry.define[%s]: spec.render required"):format(name), 2)
    end
    if widgets[name] ~= nil then
        error(("registry.define: widget '%s' already defined"):format(name), 2)
    end

    local WidgetClass = class.define(name, Node)
    local schema = compileSchema(spec)

    rawset(WidgetClass, "_widgetSpec", spec)
    -- style/theme батчево обновляет дефолты token-аннотированных свойств
    rawset(WidgetClass, "_compiledSchema", schema)

    -- методы из спецификации (select, toggle, ...) становятся методами класса;
    -- reserved: поля реестра, не методы виджета
    local reserved = {
        name = true, schema = true, required = true, init = true, render = true,
    }
    for k, v in pairs(spec) do
        if type(v) == "function" and not reserved[k] then
            rawset(WidgetClass, k, v)
        end
    end

    function WidgetClass.__init(self, props)
        Node.__init(self, name, schema)
        -- lay создаётся после Node.__init: internals уже есть
        rawget(self, "_").lay = lay_mod.new({})
        rawset(self, "_renderSpec", spec)
        -- свойства ДО init: init видит уже применённые значения (radioGroup и др.)
        applyProps(self, props)
        if spec.init then
            spec.init(self, props)
        end
    end

    -- события указателя до release идут этому виджету (task.md §3.4);
    -- dispatcher подключается лениво: input/ грузится после registry
    rawset(WidgetClass, "capturePointer", function(self)
        _G.DXUI.dispatcher.capture(self)
    end)

    -- уничтожение: снять фокус, если он был здесь (input/ лениво)
    rawset(WidgetClass, "destroy", function(self)
        local focus = _G.DXUI.focus
        if focus and focus.get() == self then
            focus.onNodeDestroyed(self)
        end
        Node.destroy(self)
    end)

    -- children = {...} в конструкторе: addChild после применения свойств
    local upstreamInit = WidgetClass.__init

    widgets[name] = WidgetClass
    specs[name] = spec
    return WidgetClass
end

-- фабрика: registry.create("Button", { text = "OK", children = {...} })
function registry.create(name, props)
    local WidgetClass = widgets[name]
    if WidgetClass == nil then
        error(("dxui: unknown widget '%s'"):format(tostring(name)), 2)
    end
    local spec = specs[name]
    if spec.required then
        for i = 1, #spec.required do
            local key = spec.required[i]
            if props == nil or props[key] == nil then
                error(("dxui: %s.%s is required"):format(tostring(name), tostring(key)), 2)
            end
        end
    end
    local node = WidgetClass.new(props)
    local children = props and props.children
    if children then
        for i = 1, #children do
            node:addChild(children[i])
        end
    end
    return node
end

function registry.get(name)
    return widgets[name]
end

function registry.getSpec(name)
    return specs[name]
end

function registry.names()
    local out = {}
    local n = 0
    for k in pairs(widgets) do
        n = n + 1
        out[n] = k
    end
    table.sort(out)
    return out
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.registry = registry
return registry

end)();
(function()
-- render/canvas.lua — command buffer кадра (task.md §3.6)
-- Пишется сценой (widgets/render pass), исполняется бэкендом.
--
-- Контракт:
--   * canvas.new() -> canvas
--   * canvas:rect(x, y, w, h, color, opts?)   opts = { radius = n }
--   * canvas:text(str, x, y, opts)            opts = { font = f, color = c,
--                                             alignX = "left"|"center"|"right",
--                                             alignY = "top"|"center"|"bottom" }
--                                             (x, y) — якорная точка текста:
--                                             для alignX="center" это центр по X
--                                             (текст рисуется вокруг неё)
--   * canvas:image(tex, x, y, w, h, opts?)    opts = { rotate = r, slice = {l,t,r,b} }
--   * canvas:clip(x, y, w, h) | canvas:clip() — push/pop клип-региона
--   * canvas:clear() — сброс буфера (команды возвращаются в пул)
--   * canvas:drain(backend) — исполнить все команды через бэкенд
--
-- Zero allocations steady-state: команды — пул таблиц, поля плоские.
-- Цвет — упакованное число (парсинг один раз при установке свойства, §3.2).

local setmetatable = setmetatable
local type = type

local Canvas = {}
Canvas.__index = Canvas

-- типы команд (числа — не строки: в горячем пути нет конкатенаций)
local CMD_RECT, CMD_TEXT, CMD_IMAGE, CMD_CLIP_PUSH, CMD_CLIP_POP =
      1, 2, 3, 4, 5

local function new()
    return setmetatable({
        cmds = {}, -- буфер команд; длину задаёт cmdCount
        cmdCount = 0,
        pool = {}, -- свободные команды
        poolCount = 0,
    }, Canvas)
end

-- берёт команду из пула или аллоцирует новую
local function acquire(self)
    local poolCount = self.poolCount
    if poolCount > 0 then
        local cmd = self.pool[poolCount]
        self.poolCount = poolCount - 1
        return cmd
    end
    return {}
end

local function push(self, cmd)
    self.cmdCount = self.cmdCount + 1
    self.cmds[self.cmdCount] = cmd
end

function Canvas:rect(x, y, w, h, color, opts)
    local cmd = acquire(self)
    cmd.kind = CMD_RECT
    cmd.x, cmd.y, cmd.w, cmd.h = x, y, w, h
    cmd.color = color
    cmd.radius = (opts and opts.radius) or nil
    cmd.font = nil
    cmd.str = nil
    cmd.tex = nil
    cmd.slice = nil
    cmd.rotate = nil
    cmd.alignX = nil
    cmd.alignY = nil
    push(self, cmd)
end

function Canvas:text(str, x, y, opts)
    local cmd = acquire(self)
    cmd.kind = CMD_TEXT
    cmd.str = str
    cmd.x, cmd.y = x, y
    cmd.font = opts and opts.font or nil
    cmd.color = opts and opts.color or nil
    cmd.alignX = opts and opts.alignX or nil
    cmd.alignY = opts and opts.alignY or nil
    cmd.w, cmd.h = nil, nil
    cmd.tex = nil
    cmd.radius = nil
    cmd.slice = nil
    cmd.rotate = nil
    push(self, cmd)
end

function Canvas:image(tex, x, y, w, h, opts)
    local cmd = acquire(self)
    cmd.kind = CMD_IMAGE
    cmd.tex = tex
    cmd.x, cmd.y, cmd.w, cmd.h = x, y, w, h
    cmd.rotate = (opts and opts.rotate) or nil
    cmd.slice = (opts and opts.slice) or nil
    cmd.color = nil
    cmd.radius = nil
    cmd.font = nil
    cmd.str = nil
    cmd.alignX = nil
    cmd.alignY = nil
    push(self, cmd)
end

function Canvas:clip(x, y, w, h)
    local cmd = acquire(self)
    if x == nil then
        cmd.kind = CMD_CLIP_POP
    else
        cmd.kind = CMD_CLIP_PUSH
        cmd.x, cmd.y, cmd.w, cmd.h = x, y, w, h
    end
    cmd.str = nil
    cmd.tex = nil
    cmd.color = nil
    cmd.radius = nil
    cmd.font = nil
    cmd.slice = nil
    cmd.rotate = nil
    cmd.alignX = nil
    cmd.alignY = nil
    push(self, cmd)
end

-- сброс буфера; команды возвращаются в пул
function Canvas:clear()
    local cmds = self.cmds
    local n = self.cmdCount
    if n == 0 then return end
    local pool = self.pool
    for i = 1, n do
        local cmd = cmds[i]
        -- освобождаем ссылки на пользовательские объекты
        cmd.str = nil
        cmd.tex = nil
        cmd.slice = nil
        cmd.alignX = nil
        cmd.alignY = nil
        pool[self.poolCount + i] = cmd
    end
    self.poolCount = self.poolCount + n
    self.cmdCount = 0
end

-- исполнение через бэкенд; после drain буфер чист
function Canvas:drain(backend)
    local n = self.cmdCount
    if n == 0 then return 0 end
    local cmds = self.cmds
    local pool = self.pool
    for i = 1, n do
        local cmd = cmds[i]
        local kind = cmd.kind
        if kind == CMD_RECT then
            backend:rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.color, cmd.radius)
        elseif kind == CMD_TEXT then
            backend:text(cmd.str, cmd.x, cmd.y, cmd.font, cmd.color, cmd.alignX, cmd.alignY)
        elseif kind == CMD_IMAGE then
            backend:image(cmd.tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.rotate, cmd.slice)
        elseif kind == CMD_CLIP_PUSH then
            backend:clipPush(cmd.x, cmd.y, cmd.w, cmd.h)
        else
            backend:clipPop()
        end
        -- возврат в пул сразу: steady-state без clear()
        local poolCount = self.poolCount
        pool[poolCount + 1] = cmd
        self.poolCount = poolCount + 1
    end
    self.cmdCount = 0
    return n
end

-- число команд в буфере (для инспектора/тестов)
function Canvas:getCommandCount()
    return self.cmdCount
end

-- экспорт констант для бэкендов/тестов
local module = {
    new = new,
    CMD_RECT = CMD_RECT,
    CMD_TEXT = CMD_TEXT,
    CMD_IMAGE = CMD_IMAGE,
    CMD_CLIP_PUSH = CMD_CLIP_PUSH,
    CMD_CLIP_POP = CMD_CLIP_POP,
}

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.canvas = module
return module

end)();
(function()
-- render/backend_mta.lua — ЕДИНСТВЕННОЕ место dxDraw* (task.md §2 whitelist)
--
-- Контракт цветов: весь фреймворк передаёт числа ARGB (AARRGGBB — так
-- записаны palette/tokens/темы). MTA ждёт ABGR (AABBGGRR) — R и B
-- поменяны; переводим ОДНОМ месте, здесь.
--
-- Скругление: если радиус > 0 и шейдер скругления доступен — шейдером,
-- с фолбэком на рисование без скругления (Auto-LOD сам отключает радиусы).

local type = type
local dxDrawRectangle = dxDrawRectangle
local dxDrawText = dxDrawText
local dxDrawImage = dxDrawImage
local dxDrawImageSection = dxDrawImageSection
local dxSetClipRegion = dxSetClipRegion

local backend = {}

local clipLevels = 0 -- на случай, если платформа не поддержала клиппинг

-- ARGB (AARRGGBB) -> MTA ABGR (AABBGGRR): обмен R и B
local function colorArg(color)
    if color == nil then
        return 0xFFFFFFFF -- white
    end
    if type(color) == "number" then
        local a = math.floor(color / 0x1000000) % 0x100
        local r = math.floor(color / 0x10000) % 0x100
        local g = math.floor(color / 0x100) % 0x100
        local b = color % 0x100
        return a * 0x1000000 + b * 0x10000 + g * 0x100 + r
    end
    -- value-объект {r,g,b,a}
    local r = color.r or 255
    local g = color.g or 255
    local b = color.b or 255
    local a = color.a or 255
    return a * 0x1000000 + b * 0x10000 + g * 0x100 + r
end

function backend:rect(x, y, w, h, color, radius)
    local c = colorArg(color)
    if radius and radius > 0 then
        -- TODO(G2+): шейдер скругления с фолбэком; пока — без скругления
        dxDrawRectangle(x, y, w, h, c, false)
    else
        dxDrawRectangle(x, y, w, h, c, false)
    end
end

function backend:text(str, x, y, font, color, alignX, alignY)
    local c = colorArg(color)
    alignX = alignX or "left"
    alignY = alignY or "top"
    -- MTA: alignX/alignY относительно КОРОБКИ текста; clip=false — коробка
    -- не клиппит, поэтому делаем её большой и ставим якорную точку (x, y)
    -- в нужное место коробки: для "center" это центр, для "right"/"bottom" — край
    local left, right = x, x + 10000
    if alignX == "center" then
        left, right = x - 10000, x + 10000
    elseif alignX == "right" then
        left, right = x - 10000, x
    end
    local top, bottom = y, y + 10000
    if alignY == "center" then
        top, bottom = y - 10000, y + 10000
    elseif alignY == "bottom" then
        top, bottom = y - 10000, y
    end
    dxDrawText(tostring(str), left, top, right, bottom, c, 1.0, font or "default", alignX, alignY, false, false, false, true)
end

function backend:image(tex, x, y, w, h, rotate, slice)
    -- MTA: dxDrawImage(x, y, w, h, tex, sourceX, sourceY, sourceW, sourceH, rotate)
    if slice then
        -- TODO(G4+): 9-slice секциями (координаты секций — в пикселях текстуры,
        -- требуется размер исходника из theme/assets); пока рисуем целиком
        dxDrawImage(x, y, w, h, tex, 0, 0, 0, 0, rotate or 0)
        return
    end
    dxDrawImage(x, y, w, h, tex, 0, 0, 0, 0, rotate or 0)
end

function backend:clipPush(x, y, w, h)
    if dxSetClipRegion(x, y, w, h) then
        clipLevels = clipLevels + 1
    end
end

function backend:clipPop()
    if clipLevels > 0 then
        clipLevels = clipLevels - 1
        dxSetClipRegion(false)
    end
end

-- renderToTexture: растеризация сцены в текстуру (RT-кэш статичных поддеревьев).
-- dxSetRenderTarget — глобальное состояние: только defer-обёрткой с
-- восстановлением прежней цели (task.md §2 P7).
function backend.renderToTexture(sceneFn, w, h)
    local rt = dxCreateRenderTarget(w, h, true)
    if not rt then
        return nil
    end
    local prev = dxGetRenderTargets()
    dxSetRenderTarget(rt, true)
    local ok, err = pcall(sceneFn)
    dxSetRenderTarget() -- всегда возвращаем прежнее состояние
    if not ok then
        return nil, err
    end
    return rt
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.backend_mta = backend
return backend

end)();
(function()
-- render/backend_headless.lua — исполнение команд в счётчики; бенчмарки для CI
--
-- Единственный бэкенд, живущий БЕЗ MTA: команды не рисуются, а считаются.
-- Используется тестовым раннером (unit) и CI-бюджетами (task.md §6.2):
--   * backend.execute проверяет invariants команд;
--   * backend.benchmark(fn, opts) — медиана 120 «кадров» после прогрева.

local type = type
local os_clock = os.clock
local table_sort = table.sort

local backend = {}

local counters = {
    rect = 0,
    text = 0,
    image = 0,
    clipPush = 0,
    clipPop = 0,
}

local errors = 0
local last = {}

-- ---------------------------------------------------------------- execute

function backend.reset()
    counters.rect = 0
    counters.text = 0
    counters.image = 0
    counters.clipPush = 0
    counters.clipPop = 0
    errors = 0
end

function backend.counters()
    return counters
end

-- валидация команд в headless: плохая команда не падает, но считается ошибкой
local function validNumber(v)
    return type(v) == "number"
end

function backend:rect(x, y, w, h, color, radius)
    if not (validNumber(x) and validNumber(y) and validNumber(w) and validNumber(h)) then
        errors = errors + 1
        return
    end
    if color ~= nil and type(color) ~= "number" and type(color) ~= "table" then
        errors = errors + 1
        return
    end
    last.kind = "rect"
    last.x, last.y, last.w, last.h, last.color, last.radius = x, y, w, h, color, radius
    counters.rect = counters.rect + 1
end

function backend:text(str, x, y, font, color, alignX, alignY)
    if type(str) ~= "string" then
        errors = errors + 1
        return
    end
    if not (validNumber(x) and validNumber(y)) then
        errors = errors + 1
        return
    end
    last.kind = "text"
    last.str, last.x, last.y, last.font, last.color = str, x, y, font, color
    last.alignX, last.alignY = alignX, alignY
    counters.text = counters.text + 1
end

function backend:image(tex, x, y, w, h, rotate, slice)
    if tex == nil then
        errors = errors + 1
        return
    end
    if not (validNumber(x) and validNumber(y) and validNumber(w) and validNumber(h)) then
        errors = errors + 1
        return
    end
    last.kind = "image"
    last.tex, last.x, last.y, last.w, last.h = tex, x, y, w, h
    last.rotate, last.slice = rotate, slice
    counters.image = counters.image + 1
end

function backend:clipPush(x, y, w, h)
    if not (validNumber(x) and validNumber(y) and validNumber(w) and validNumber(h)) then
        errors = errors + 1
        return
    end
    last.kind = "clipPush"
    counters.clipPush = counters.clipPush + 1
end

function backend:clipPop()
    last.kind = "clipPop"
    counters.clipPop = counters.clipPop + 1
end

function backend:getErrors()
    return errors
end

-- ---------------------------------------------------------------- benchmark

-- медиана кадров; одна «frame» = inner прогонов fn подряд (разрешение os.clock)
-- opts: { frames = 120, warmup = 30, inner = 10 }
function backend.benchmark(fn, opts)
    opts = opts or {}
    local frames = opts.frames or 120
    local warmup = opts.warmup or 30
    local inner = opts.inner or 10

    -- прогрев
    for _ = 1, warmup do
        fn()
    end

    local times = {}
    for _ = 1, frames do
        local t0 = os_clock()
        for _ = 1, inner do
            fn()
        end
        times[#times + 1] = (os_clock() - t0) * 1000 / inner
    end

    table_sort(times)
    local mid = math.floor(#times / 2) + 1
    return times[mid]
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.backend_headless = backend
return backend

end)();
(function()
-- render/frame.lua — пайплайн кадра виджетов
--
-- Кадр (порядок фиксирован, task.md §1):
--   1. layout: рекурсивная пасса раскладки корней (flex/anchors);
--   2. render: рекурсивный обход с накоплением мировых координат;
--      каждый виджет рисует через spec.render(widget, canvas, wx, wy).
-- Развилки (scroll, clip) используют lay, проходя транзитом.

local DXUI = _G.DXUI

local frame = {}
local roots = {}

local function layoutNode(node)
    local inod = rawget(node, "_")
    if inod == nil or inod.lay == nil then
        return
    end
    -- у контейнерных виджетов пассу выполняет их собственный render-спека;
    -- здесь — универсальный флекс по lay
    local children = inod.children
    if children and #children > 0 then
        local pseudo = { lay = inod.lay, children = {} }
        for i = 1, #children do
            local c = children[i]
            if c ~= nil then
                local cinod = rawget(c, "_")
                pseudo.children[#pseudo.children + 1] = {
                    lay = cinod.lay,
                    children = cinod.children,
                    __child = c,
                }
            end
        end
        DXUI.flex.apply(pseudo)
        -- вернуть геометрию из pseudo обратно в детей (flex пишет прямо в их lay)
        for i = 1, #pseudo.children do
            -- nothing: lay общий по ссылке
        end
    end
    -- рекурсия в детей
    if children then
        for i = 1, #children do
            local c = children[i]
            if c ~= nil then
                layoutNode(c)
            end
        end
    end
end

local function renderNode(node, canvas, ox, oy)
    local inod = rawget(node, "_")
    if inod == nil then return end
    local spec = rawget(node, "_renderSpec")
    local l = inod.lay
    if l == nil then return end
    local wx = ox + (l.x or 0)
    local wy = oy + (l.y or 0)

    if inod.data.visible == false then
        return -- заморозка скрытых поддеревьев (task.md §6.1)
    end

    if spec and spec.render then
        -- профилирование per-widget: единственный if в холодном пути
        local profiler = DXUI.profiler
        if profiler and profiler.isEnabled() then
            profiler.measure(inod.widgetType, spec.render, node, canvas, wx, wy)
        else
            spec.render(node, canvas, wx, wy)
        end
    end

    local children = inod.children
    if children then
        for i = 1, #children do
            local c = children[i]
            if c ~= nil then
                renderNode(c, canvas, wx, wy)
            end
        end
    end
end

function frame.add(root)
    roots[#roots + 1] = root
    return root
end

-- корни кадра (для input/dispatcher: сбор геометрии hit-test)
function frame.roots()
    return roots
end

function frame.remove(root)
    for i = 1, #roots do
        if roots[i] == root then
            table.remove(roots, i)
            return true
        end
    end
    return false
end

function frame.clear()
    for i = #roots, 1, -1 do
        roots[i] = nil
    end
end

-- полный кадр: раскладка всех корней + отрисовка в canvas
function frame.run(canvas)
    for i = 1, #roots do
        layoutNode(roots[i])
    end
    for i = 1, #roots do
        renderNode(roots[i], canvas, 0, 0)
    end
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.frame = frame
return frame

end)();
(function()
-- input/hit_test.lua — пространственный хеш (task.md §3.4)
--
-- Сетка 64px. insert(rect, node), query(x, y) → node сверху вниз по Z.
-- Z-порядок задаётся порядком вставки: pre-order обход дерева —
-- позже вставленный узел рисуется поверх и выигрывает hit-test.
--
-- Ориентир производительности: 10 000 прямоугольников / 1000 запросов
-- ≥ 20× линейного перебора (проверено в .debug/tests/test_input.lua).

local floor = math.floor
local pairs = pairs

local hit_test = {}
hit_test.__index = hit_test

local GRID = 64

function hit_test.new()
    return setmetatable({
        cells = {}, -- [cx][cy] = { rect, rect, ... }
        count = 0,
    }, hit_test)
end

function hit_test.clear(self)
    self.cells = {}
    self.count = 0
end

-- rect: узел с мировым прямоугольником; order — Z-штамп вставки
function hit_test.insert(self, x, y, w, h, node, order)
    local cx0 = floor(x / GRID)
    local cx1 = floor((x + w) / GRID)
    local cy0 = floor(y / GRID)
    local cy1 = floor((y + h) / GRID)
    local rect = { x = x, y = y, w = w, h = h, node = node, order = order }
    self.count = self.count + 1
    for cx = cx0, cx1 do
        local col = self.cells[cx]
        if col == nil then
            col = {}
            self.cells[cx] = col
        end
        for cy = cy0, cy1 do
            local cell = col[cy]
            if cell == nil then
                cell = {}
                col[cy] = cell
            end
            cell[#cell + 1] = rect
        end
    end
end

-- верхний узел под точкой (по Z); nil — точка свободна
function hit_test.query(self, x, y)
    local col = self.cells[floor(x / GRID)]
    if col == nil then return nil end
    local cell = col[floor(y / GRID)]
    if cell == nil then return nil end
    local best = nil
    local bestOrder = -1
    for i = 1, #cell do
        local r = cell[i]
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            if r.order > bestOrder then
                best = r.node
                bestOrder = r.order
            end
        end
    end
    return best
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.hit_test = hit_test
return hit_test

end)();
(function()
-- input/focus.lua — фокус и клавиатурная навигация (task.md §3.5)
--
-- Таблица решений:
--   * стрелки между элементами: обход по дереву раскладки, не по пикселям;
--   * Tab входит в редактирование, стрелка вправо — нет (иначе из поля не выйти);
--   * контейнер прокрутки в фокус-обходе пропускается;
--   * модальные окна: навигация заперта внутри верхней модали (ловушка);
--   * виртуализированный список: стрелка = следующая строка (dispatcher
--     подставляет строки как узлы через focus.addProxy).
--
-- Состояние editing: true, пока пользователь редактирует текст; в этом
-- режиме стрелки уходят в text/-ядро, а не в навигацию.

local rawget = rawget
local table_insert = table.insert

local focus = {}

local focused = nil
local editing = false
local modalStack = {}

-- rebuildable список фокусируемых узлов (лениво; инвалидация списком)
local listVersion = 0

local function markDirty()
    listVersion = listVersion + 1
end

-- ---------------------------------------------------------------- modal

-- ловушка: навигация и ввод заперты в поддереве node
function focus.pushModal(node)
    modalStack[#modalStack + 1] = node
    if focused ~= nil and not focus.isInsideModal(focused, node) then
        focused = nil
    end
    markDirty()
end

function focus.popModal()
    local node = table.remove(modalStack)
    if node then markDirty() end
    return node
end

function focus.getModal()
    return modalStack[#modalStack]
end

function focus.isInsideModal(node, modal)
    if modal == nil then return true end
    local cur = node
    while cur do
        if cur == modal then return true end
        cur = rawget(cur, "_").parent
    end
    return false
end

-- ---------------------------------------------------------------- состояние

function focus.get()
    return focused
end

-- вызывается без node при уничтожении узла
function focus.set(node)
    if focused == node then return end
    local prev = focused
    focused = node
    editing = false
    markDirty()
    if prev then prev:emit("blur") end
    if node then node:emit("focus") end
end

function focus.clear()
    focus.set(nil)
end

function focus.isEditing()
    return editing
end

-- Tab вошёл в поле / Tab вышел из поля (двигаемся дальше)
function focus.setEditing(on)
    editing = on == true
    return editing
end

-- узел способен к редактированию (Edit, Memo)
function focus.isEditable(node)
    local spec = rawget(node, "_renderSpec")
    return spec ~= nil and spec.editable == true
end

-- ---------------------------------------------------------------- обход

-- собирает все фокусируемые узлы: дерево раскладки, pre-order.
-- Контейнеры прокрутки сами не фокусируются (spec.focusable false).
-- roots — таблица корней (frame.roots()).
local function buildList(roots)
    local list = {}
    local modal = focus.getModal()
    local function walk(node, insideModal)
        if not insideModal and modal ~= nil then
            -- вне модали ничего не фокусируется
            return
        end
        local inod = rawget(node, "_")
        if inod == nil then return end
        if inod.data.visible == false then return end
        local spec = rawget(node, "_renderSpec")
        if spec and spec.focusable then
            list[#list + 1] = node
        end
        local children = inod.children
        for i = 1, #children do
            walk(children[i], insideModal)
        end
    end
    if modal == nil then
        for i = 1, #roots do
            walk(roots[i], true)
        end
    else
        walk(modal, true)
    end
    return list
end

-- dir: 1 = вперёд (Tab), -1 = назад (Shift+Tab)
-- возвращает новый сфокусированный узел (или nil)
function focus.navigate(roots, dir)
    local list = buildList(roots)
    local n = #list
    if n == 0 then
        focus.set(nil)
        return nil
    end
    if focused == nil then
        focus.set(list[1])
        return focused
    end
    local at = 0
    for i = 1, n do
        if list[i] == focused then
            at = i
            break
        end
    end
    local next
    if at == 0 then
        -- сфокусированный вне списка (модаль) — начинаем сначала
        next = list[1]
    else
        local idx = at + dir
        if idx > n then idx = 1 end
        if idx < 1 then idx = n end
        next = list[idx]
    end
    focus.set(next)
    return next
end

-- уничтожение узла: сбросить фокус, если он был здесь
function focus.onNodeDestroyed(node)
    if focused == node then
        focused = nil
        editing = false
    end
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.focus = focus
return focus

end)();
(function()
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

-- безопасный поиск метода: чтение focused.inputKey напрямую уходит в
-- prop.get-фолбэк и бросает "property does not exist" (MTA-сессия).
local methodOf = DXUI.class.methodOf

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
-- ВАЖНО: ранние выходы возвращают order — иначе order у родителя станет
-- nil (collect = единственный источник порядка) и следующий интерактивный
-- узел упадёт на order + 1.
local function isInteractive(node)
    local spec = rawget(node, "_renderSpec")
    if spec == nil then return false end
    if spec.interactive then return true end
    if spec.draggable then return true end
    return false
end

local function collect(node, ox, oy, order)
    local inod = rawget(node, "_")
    if inod == nil then return order end
    if inod.data.visible == false then return order end
    local l = inod.lay
    if l == nil then return order end
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
            local inputKey = methodOf(focused, "inputKey")
            if inputKey then inputKey(focused, key, false) end
            return
        end
        -- обход по дереву раскладки: вверх/вниз = сосед
        local dir = (key == "arrow_u" or key == "arrow_l") and -1 or 1
        DXUI.focus.navigate(dispatcher.roots, dir)
    else
        if focused ~= nil then
            local inputKey = methodOf(focused, "inputKey")
            if inputKey then inputKey(focused, key, false) end
        end
    end
end

local function onCharacter(ch)
    local focused = DXUI.focus.get()
    if focused == nil then return end
    local inputCharacter = methodOf(focused, "inputCharacter")
    if inputCharacter then
        inputCharacter(focused, ch)
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

end)();
(function()
-- text/editor.lua — headless-ядро ввода текста (task.md §3.7)
--
-- Конечный автомат БЕЗ отрисовки: caret/selection/undo(5)/blink.
-- Виджет (Edit/Memo) читает состояние и рисует его. Тестируется без игры.

local string_sub = string.sub
local string_find = string.find
local table_insert = table.insert
local table_remove = table.remove

local UNDO_DEPTH = 5
local BLINK_MS = 500

local Editor = {}
Editor.__index = Editor

local function new(text)
    local self = setmetatable({}, Editor)
    self.text = text or ""
    self.caret = 1 -- 1..#text+1 (Lua-индексация)
    self.anchor = 1 -- вторая граница выделения
    self.undoStack = {}
    self.undoCount = 0
    self.blinkPhase = 0
    return self
end

-- ---------------------------------------------------------------- selection

function Editor:hasSelection()
    return self.caret ~= self.anchor
end

function Editor:getSelection()
    local a, b = self.caret, self.anchor
    if a > b then a, b = b, a end
    return a, b
end

function Editor:selectionText()
    local a, b = self:getSelection()
    return string_sub(self.text, a, b - 1)
end

-- ---------------------------------------------------------------- editing

local function pushUndo(self)
    self.undoCount = self.undoCount + 1
    self.undoStack[self.undoCount] = { text = self.text, caret = self.caret }
    if self.undoCount > UNDO_DEPTH then
        table_remove(self.undoStack, 1)
        self.undoCount = self.undoCount - 1
    end
end

-- вставка/замата с учётом выделения; возвращает true, если текст изменился
function Editor:insert(str)
    if self:hasSelection() then
        self:delete() -- delete вызывает pushUndo
    else
        pushUndo(self)
    end
    local t = self.text
    local c = self.caret
    self.text = string_sub(t, 1, c - 1) .. str .. string_sub(t, c)
    self.caret = c + #str
    self.anchor = self.caret
    return true
end

-- удаление символа в направлении caret (-1 назад, 1 вперёд); при выделении
-- удаляется оно
function Editor:delete(dir)
    if self:hasSelection() then
        pushUndo(self)
        local a, b = self:getSelection()
        self.text = string_sub(self.text, 1, a - 1) .. string_sub(self.text, b)
        self.caret = a
        self.anchor = a
        return true
    end
    local pos = self.caret + (dir or 1)
    if dir == -1 then
        pos = self.caret - 1
    end
    if pos < 1 or pos > #self.text then
        return false
    end
    pushUndo(self)
    self.text = string_sub(self.text, 1, pos - 1) .. string_sub(self.text, pos + 1)
    self.caret = pos
    self.anchor = pos
    return true
end

-- ---------------------------------------------------------------- undo

function Editor:undo()
    local last = self.undoStack[self.undoCount]
    if last == nil then
        return false
    end
    self.undoCount = self.undoCount - 1
    self.text = last.text
    self.caret = last.caret
    self.anchor = self.caret
    return true
end

-- ---------------------------------------------------------------- движение

function Editor:move(delta, extendSelection)
    local pos = self.caret + delta
    if pos < 1 then pos = 1 end
    if pos > #self.text + 1 then pos = #self.text + 1 end
    self.caret = pos
    if not extendSelection then
        self.anchor = pos
    end
end

-- ---------------------------------------------------------------- blink

-- единый клок из core/time; caretVisible зовёт себя с now
function Editor:caretVisible(now)
    local phase = math.floor(now / BLINK_MS) % 2
    return phase == 0
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.editor = { new = new }
return _G.DXUI.editor

end)();
(function()
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

end)();
(function()
-- style/theme.lua — темы поверх токенов (task.md §5)
--
-- Тема — таблица переопределений поверх токенов. Смена — батчевое
-- обновление: одна запись на ключ, без аллокаций на виджет (300 виджетов
-- ≤ 5 мс по бюджету §6.2).
--
-- Дефолты схем виджетов, аннотированные token = "<имя>", обновляются
-- вместе с палитрой: явная установка свойства пользователем не страдает.

local pairs = pairs
local ipairs = ipairs
local rawget = rawget

local theme = {}

local themes = {}   -- name -> overrides

-- callback смены темы (инспектор/anim слушают)
theme.onChanged = nil

function theme.define(name, overrides)
    themes[name] = overrides
    return overrides
end

function theme.get(name)
    return themes[name]
end

-- батчевое применение: мутирует палитру и дефолты аннотированных схем
function theme.apply(overrides)
    local DXUI = _G.DXUI
    local palette = DXUI.palette
    for k, v in pairs(overrides) do
        palette[k] = v
    end
    -- дефолты свойств, привязанные к токенам
    local registry = DXUI.registry
    for _, name in ipairs(registry.names()) do
        local cls = registry.get(name)
        local schema = rawget(cls, "_compiledSchema")
        if schema then
            for _, entry in pairs(schema) do
                local tk = entry.token
                if tk and overrides[tk] ~= nil then
                    entry.default = overrides[tk]
                end
            end
        end
    end
    if theme.onChanged then
        theme.onChanged(overrides)
    end
    return overrides
end

function theme.applyNamed(name)
    local overrides = themes[name]
    if overrides == nil then
        error(("theme: '%s' is not defined"):format(tostring(name)), 2)
    end
    return theme.apply(overrides)
end

-- hot-reload (dev): reader() -> таблица переопределений (перечитал — применил)
function theme.reload(reader)
    local ok, overrides = pcall(reader)
    if not ok or type(overrides) ~= "table" then
        return false
    end
    theme.apply(overrides)
    return true
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.theme = theme
return theme

end)();
(function()
-- style/states.lua — состояния виджета (task.md §5)
--
-- Цепочка состояний: base → hover → pressed → focused → disabled.
-- Значение свойства = первый найденный в цепочке приоритет (disabled
-- старше всех). Сами флаги состояний хранит виджет в свойствах
-- (hovered/pressed/focused/disabled — как в темах).

local states = {}

local CHAIN = { "disabled", "focused", "pressed", "hovered", "base" }

-- layered: { base = {...}, hover = {...}, ... }
-- state: { hovered = bool, pressed = bool, focused = bool, disabled = bool }
local function pick(layered, state, key)
    for i = 1, #CHAIN do
        local layer = layered[CHAIN[i]]
        if layer and layer[key] ~= nil then
            return layer[key]
        end
    end
    return nil
end

-- разрешить полный набор свойств по состоянию: { ключ = значение }
function states.resolve(layered, state)
    local out = {}
    -- базовые значения
    if layered.base then
        for k, v in pairs(layered.base) do
            out[k] = v
        end
    end
    -- наслоения по цепочке (disabled сильнее всех)
    for i = #CHAIN, 1, -1 do
        local name = CHAIN[i]
        if state[name] and layered[name] then
            local layer = layered[name]
            for k, v in pairs(layer) do
                out[k] = v
            end
        end
    end
    return out
end

states.pick = pick

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.states = states
return states

end)();
(function()
-- style/transitions.lua — переходы состояний (task.md §5)
--
-- Схема свойства может объявить переход:
--   x = { type = "number", ..., transition = { duration = 0.15, easing = "outQuad" } }
--
-- Запись node.x = v в этом случае не прыгает: prop.set ставит твин
-- (anim/tween), и интерполяция идёт через ту же систему свойств —
-- конвейер переиспользуется. Твин пишет через prop.forceSet (мимо
-- планирования), поэтому рекурсии нет.

local transitions = {}

-- валидация описателя перехода на этапе компиляции схемы
function transitions.validate(owner, key, spec)
    if spec.duration == nil then
        error(("transitions[%s.%s]: duration required"):format(owner, tostring(key)), 2)
    end
    return true
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.transitions = transitions
return transitions

end)();
(function()
-- anim/easing.lua — функции облегчения (единый клок из core/time)

local easing = {}

function easing.linear(t) return t end

function easing.inQuad(t) return t * t end

function easing.outQuad(t) return t * (2 - t) end

function easing.inOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return -2 * t * t + 4 * t - 1
end

function easing.inCubic(t) return t * t * t end

function easing.outCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

function easing.outBack(t)
    local c = 1.70158
    local u = t - 1
    return 1 + (c + 1) * u * u * u + c * u * u
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.easing = easing
return easing

end)();
(function()
-- anim/tween.lua — твины и таймлайны поверх системы свойств (task.md §5)
--
--   animation.to(panel, 0.25, { x = 300, y = 40 }, { easing = "outQuad" })
--
-- * единый клок: core/time (никаких таймеров в виджетах);
-- * твины пишут через prop.forceSet — конвейер свойств переиспользуется
--   (инвалидация/dirty-списки работают как при прямой записи);
-- * prop.set для свойств с transition = { duration, easing } планирует
--   твин автоматически (см. style/transitions.lua);
-- * retarget: повторная запись свойства твинит от текущего значения.

local rawget = rawget
local pairs = pairs

local tween = {}

local active = {}   -- массив активных твинов
local count = 0     -- #active

local DXUI = _G.DXUI
local prop = DXUI.prop
local easing = DXUI.easing

-- в узле отмечается, какие свойства интерполируются (prop.set не
-- перезапланировывает твин того же свойства)
local function markTweening(node, key, on)
    local inod = rawget(node, "_")
    inod.tweening = inod.tweening or {}
    inod.tweening[key] = on or nil
    if on == nil and next(inod.tweening) == nil then
        inod.tweening = nil
    end
end

local function findActive(node, key)
    for i = 1, count do
        local tw = active[i]
        if tw.node == node and tw.key == key then
            return tw
        end
    end
    return nil
end

-- один твине на свойство узла: retarget от текущего значения
local function schedule(node, key, toValue, duration, easeName, start)
    local DXUIeasing = _G.DXUI.easing
    local ease = (easeName and DXUIeasing[easeName]) or DXUIeasing.outQuad
    local tw = findActive(node, key)
    if tw then
        tw.to = toValue
        tw.ease = ease
        return tw
    end
    count = count + 1
    tw = {
        node = node,
        key = key,
        from = nil,
        to = toValue,
        dur = duration,
        ease = ease,
        start = start or _G.DXUI.time.now(),
        after = nil,
    }
    active[count] = tw
    markTweening(node, key, true)
    return tw
end

-- публичный API: твин группы свойств за duration секунд
-- tween.to(node, duration, props, opts?) -> tween handle
function tween.to(node, duration, props, opts)
    opts = opts or {}
    local handle
    for key, value in pairs(props) do
        local tw = schedule(node, key, value, duration, opts.easing)
        handle = tw
    end
    return handle
end

-- планирование из prop.set (свойство с transition)
function tween.transitionTo(node, key, value, spec)
    local tw = schedule(node, key, value, spec.duration, spec.easing)
    return tw
end

-- одношотовый отложенный вызов (клок — общий)
function tween.after(delay, fn)
    count = count + 1
    local tw = {
        node = nil,
        after = fn,
        start = _G.DXUI.time.now(),
        delay = delay,
        key = nil,
    }
    active[count] = tw
    return tw
end

-- таймлайн: steps = { { to = {...}, dur = n, easing = "..." }, ... }
-- каждый шаг стартует после предыдущего
function tween.timeline(node, steps)
    local i = 0
    local function step()
        i = i + 1
        local s = steps[i]
        if s == nil then return end
        local handle = tween.to(node, s.dur, s.to, { easing = s.easing })
        if handle then
            handle.after = (i < #steps) and step or nil
        end
    end
    step()
end

function tween.activeCount()
    return count
end

function tween.clear()
    for i = 1, count do
        active[i] = nil
    end
    count = 0
end

-- обновление твинеров; вызывается boot.lua каждый кадр
function tween.tick()
    if count == 0 then return 0 end
    local now = _G.DXUI.time.now()
    local forceSet = prop.forceSet
    local n = count      -- граница на входе: твины, запланированные
    local w = 0          -- из after-колбэков, живут в n+1..count
    for i = 1, n do
        local tw = active[i]
        local keep = true
        if tw.key == nil then
            -- отложенный вызов (after)
            if now - tw.start >= tw.delay then
                tw.after()
                keep = false
            end
        else
            local elapsed = now - tw.start
            if elapsed >= tw.dur then
                forceSet(tw.node, tw.key, tw.to)
                markTweening(tw.node, tw.key, nil)
                -- до after: твин больше участвует в retarget-поиске
                tw.node = nil
                if tw.after then tw.after() end
                keep = false
            elseif elapsed >= 0 then
                if tw.from == nil then
                    tw.from = tw.node[tw.key]
                end
                local a = tw.ease(elapsed / tw.dur)
                local v = tw.from + (tw.to - tw.from) * a
                forceSet(tw.node, tw.key, v)
            end
        end
        if keep then
            w = w + 1
            active[w] = tw
        end
    end
    -- новые твины из колбэков (n+1..count) перемещаются за выжившими
    for i = n + 1, count do
        w = w + 1
        active[w] = active[i]
    end
    for i = count, w + 1, -1 do
        active[i] = nil
    end
    count = w
    return w
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.tween = tween
return tween

end)();
(function()
-- widget/palette.lua — фиксированные цвета до этапа theme/ (G6)

local palette = {
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

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.palette = palette
return palette

end)();
(function()
-- widget/button.lua — эталонная схема виджета (task.md §4.1)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Button",
    interactive = true,
    focusable = true,
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Надпись кнопки",
        },
        icon = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "Текстура-иконка",
        },
        disabled = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Блокировка кнопки",
        },
        onPress = {
            type = "function", invalidates = {},
            doc = "Обработчик нажатия (требуется)",
        },
        color = {
            type = "number", default = P.accent, invalidates = { prop.DIRTY.RENDER },
            token = "accent",
            doc = "Цвет фона кнопки",
        },
        textColor = {
            type = "number", default = P.white, invalidates = { prop.DIRTY.RENDER },
            token = "white",
            doc = "Цвет надписи",
        },
    },
    required = { "text", "onPress" },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local bg = self.color
        if self.disabled then
            bg = P.bgDisabled
        end
        canvas:rect(x, y, l.w, l.h, bg, { radius = 4 })
        if self.icon then
            canvas:image(self.icon, x, y, l.h, l.h)
        end
        local tx = x + (self.icon and l.h or 0)
        canvas:text(self.text, tx + l.w / 2, y + l.h / 2,
            { alignX = "center", alignY = "center", color = self.disabled and P.textDim or self.textColor })
    end,
}

end)();
(function()
-- widget/checkbox.lua — флажок с подписью

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Checkbox",
    interactive = true,
    focusable = true,
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Подпись чекбокса",
        },
        checked = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Состояние отметки",
        },
        boxColor = {
            type = "number", default = P.accent, invalidates = { prop.DIRTY.RENDER },
            token = "accent",
            doc = "Цвет отметенного состояния",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local boxSize = 16
        canvas:rect(x, y + (l.h - boxSize) / 2, boxSize, boxSize, self.checked and self.boxColor or P.bgHover, { radius = 3 })
        if self.checked then
            -- галочка
            canvas:rect(x + 3, y + (l.h - boxSize) / 2 + 3, boxSize - 6, boxSize - 6, P.white)
        end
        if self.text ~= "" then
            canvas:text(self.text, x + boxSize + 6, y + l.h / 2, { alignY = "center", color = P.text })
        end
    end,
}

end)();
(function()
-- widget/combobox.lua — выпадающий список

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Combobox",
    interactive = true,
    focusable = true,
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив вариантов",
        },
        selectedIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс выбранного варианта (0 = ничего)",
        },
        opened = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Раскрыт ли список",
        },
        itemHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота пункта списка",
        },
    },
    toggle = function(self)
        self.opened = not self.opened
        self:emit(self.opened and "opened" or "closed")
    end,
    pick = function(self, index)
        if self.items[index] == nil then
            return false
        end
        self.selectedIndex = index
        self.opened = false
        self:emit("picked", index)
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        -- поле выбора
        canvas:rect(x, y, l.w, l.h, P.bgHover, { radius = 4 })
        local current = self.items and self.items[self.selectedIndex] or nil
        canvas:text(tostring(current or "..."), x + 8, y + l.h / 2, { alignY = "center", color = P.text })
        -- стрелка
        local ax = x + l.w - 13
        canvas:text(self.opened and "^" or "v", ax, y + l.h / 2, { alignY = "center", color = P.textDim })
        -- раскрытый список
        if self.opened then
            local items = self.items or {}
            local n = #items
            local ih = self.itemHeight
            canvas:rect(x, y + l.h, l.w, n * ih, P.windowBg, { radius = 4 })
            for i = 1, n do
                local iy = y + l.h + (i - 1) * ih
                canvas:text(tostring(items[i]), x + 8, iy + ih / 2, { alignY = "center", color = P.text })
            end
        end
    end,
}


end)();
(function()
-- widget/contextmenu.lua — контекстное меню (строки = данные)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "ContextMenu",
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив пунктов: { {text=.., onPick=fn}, ... }",
        },
        itemHeight = {
            type = "number", default = 26, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота пункта",
        },
        hoverIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс пункта под курсором (0 = нет)",
        },
    },
    -- координаты пункта по индексу (для dispatcher/hit_test в G5)
    itemRect = function(self, index)
        local l = rawget(self, "_").lay
        return 0, (index - 1) * self.itemHeight, l.w, self.itemHeight
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items or {}
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 4 })
        for i = 1, #items do
            local iy = y + (i - 1) * self.itemHeight
            if i == self.hoverIndex then
                canvas:rect(x, iy, l.w, self.itemHeight, P.accentDim)
            end
            canvas:text(tostring(items[i].text or ""), x + 10, iy + self.itemHeight / 2, { alignY = "center", color = P.text })
        end
    end,
}


end)();
(function()
-- widget/edit.lua — однострочное поле ввода на text/ headless-ядре

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

local editor_mod = _G.DXUI.editor

return _G.DXUI.registry.define {
    name = "Edit",
    interactive = true,
    focusable = true,
    editable = true,
    schema = {
        placeholder = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Текст-подсказка при пустом поле",
        },
        maxLength = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Максимальная длина (0 = без ограничения)",
        },
        password = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Скрывать ввод звёздочками",
        },
    },
    -- текст хранится в editor-ядре; свойство text делегируется ниже
    init = function(self)
        rawget(self, "_").editor = editor_mod.new("")
    end,
    getText = function(self)
        return rawget(self, "_").editor.text
    end,
    setText = function(self, str)
        local ed = rawget(self, "_").editor
        ed.text = str
        ed.caret = #str + 1
        ed.anchor = ed.caret
    end,
    -- ввод символа (мост onClientCharacter приезжает сюда через dispatcher)
    inputCharacter = function(self, ch)
        local ed = rawget(self, "_").editor
        if self.maxLength > 0 and #ed.text >= self.maxLength then
            return false
        end
        ed:insert(ch)
        return true
    end,
    inputKey = function(self, key, down)
        local ed = rawget(self, "_").editor
        if key == "backspace" then
            return ed:delete(-1)
        elseif key == "delete" then
            return ed:delete(1)
        elseif key == "arrow_l" then
            ed:move(-1, down)
        elseif key == "arrow_r" then
            ed:move(1, down)
        elseif key == "home" then
            ed.caret = 1
            if not down then ed.anchor = 1 end
        elseif key == "end" then
            ed.caret = #ed.text + 1
            if not down then ed.anchor = ed.caret end
        end
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local ed = rawget(self, "_").editor
        canvas:rect(x, y, l.w, l.h, P.bg, { radius = 4 })
        local text = ed.text
        if text == "" and self.placeholder ~= "" then
            canvas:text(self.placeholder, x + 8, y + l.h / 2, { alignY = "center", color = P.textDim })
        else
            if self.password then
                local masked = ("*"):rep(#text)
                canvas:text(masked, x + 8, y + l.h / 2, { alignY = "center", color = P.text })
            else
                canvas:text(text, x + 8, y + l.h / 2, { alignY = "center", color = P.text })
            end
        end
    end,
}

end)();
(function()
-- widget/gridlist.lua — виртуализированная сетка данных (task.md §6.1:
-- 10 000 строк ≈ 20: узлов O(visible)+2, скролл подменяет данные)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "GridList",
    interactive = true,
    schema = {
        columns = {
            type = "number", default = 1, invalidates = { prop.DIRTY.RENDER },
            doc = "Число колонок",
        },
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив данных (строки или {text=...})",
        },
        rowHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки",
        },
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        virtualized = {
            type = "boolean", default = true, invalidates = { prop.DIRTY.RENDER },
            doc = "Рисовать только видимые строки",
        },
    },
    rowsTotal = function(self)
        local items = self.items
        local n = items and #items or 0
        local cols = math.max(1, self.columns)
        return math.ceil(n / cols)
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items or {}
        local n = #items
        local cols = math.max(1, self.columns)
        local rh = self.rowHeight
        local rows = math.ceil(n / cols)
        local colW = l.w / cols

        local firstRow = 0
        local lastRow = rows
        if self.virtualized then
            firstRow = math.floor(self.scrollY / rh)
            if firstRow < 0 then firstRow = 0 end
            lastRow = math.min(rows, firstRow + math.ceil(l.h / rh) + 2)
        end

        for row = firstRow + 1, lastRow do
            local rowY = y + (row - 1) * rh - self.scrollY
            for col = 1, cols do
                local idx = (row - 1) * cols + col
                if idx <= n then
                    local cellX = x + (col - 1) * colW
                    local item = items[idx]
                    if type(item) == "table" then
                        item = item.text
                    end
                    canvas:rect(cellX, rowY, colW, rh, row % 2 == 0 and P.bg or P.bgHover)
                    canvas:text(tostring(item), cellX + 6, rowY + rh / 2, { alignY = "center", color = P.text })
                end
            end
        end
    end,
}


end)();
(function()
-- widget/image.lua — растровое изображение

local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Image",
    schema = {
        texture = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "Текстура (создаётся dxCreateTexture)",
        },
        slice = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "9-slice поля: { left, top, right, bottom }",
        },
        rotate = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Поворот в радианах",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        if self.texture then
            canvas:image(self.texture, x, y, l.w, l.h, {
                rotate = self.rotate,
                slice = self.slice,
            })
        end
    end,
}

end)();
(function()
-- widget/label.lua — статический текст

local P = _G.DXUI.palette

return _G.DXUI.registry.define {
    name = "Label",
    schema = {
        text = {
            type = "string", default = "", invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            doc = "Отображаемый текст",
        },
        color = {
            type = "number", default = P.text, invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            token = "text",
            doc = "Цвет текста",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:text(self.text, x, y, { color = self.color })
    end,
}

end)();
(function()
-- widget/list.lua — список строк (виртуализуемый)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "List",
    interactive = true,
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив строк",
        },
        rowHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки",
        },
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        selectedIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс выбранной строки (0 = нет)",
        },
    },
    -- число строк, которые реально рисуются (виртуализация: O(visible)+2)
    visibleRows = function(self)
        local l = rawget(self, "_").lay
        return math.ceil(l.h / self.rowHeight) + 2
    end,
    rowsTotal = function(self)
        local items = self.items
        return items and #items or 0
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items
        local n = items and #items or 0
        local rh = self.rowHeight
        local first = math.floor(self.scrollY / rh)
        if first < 0 then first = 0 end
        local visible = math.ceil(l.h / rh) + 2
        for i = 1, math.min(first + visible, n) do
            local idx = i -- только строки в области экрана
            if idx > first then
                local rowY = y + (idx - 1) * rh - self.scrollY
                if rowY < y + l.h and rowY + rh > y then
                    if idx == self.selectedIndex then
                        canvas:rect(x, rowY, l.w, rh, P.bgHover)
                    end
                    canvas:text(tostring(items[idx]), x + 6, rowY + rh / 2, { alignY = "center", color = P.text })
                end
            end
        end
    end,
}


end)();
(function()
-- widget/memo.lua — многострочное поле (Edit на строчках + newline)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Memo",
    schema = {
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        lineHeight = {
            type = "number", default = 15, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки текста",
        },
    },
    init = function(self)
        rawget(self, "_").editor = _G.DXUI.editor.new("")
    end,
    getText = function(self)
        return rawget(self, "_").editor.text
    end,
    setText = function(self, str)
        local ed = rawget(self, "_").editor
        ed.text = str
        ed.caret = #str + 1
        ed.anchor = ed.caret
    end,
    inputCharacter = function(self, ch)
        rawget(self, "_").editor:insert(ch)
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local ed = rawget(self, "_").editor
        canvas:rect(x, y, l.w, l.h, P.bg, { radius = 4 })
        -- строки рисуются с учётом прокрутки
        local lineH = self.lineHeight
        local startLine = math.floor(self.scrollY / lineH)
        local visibleLines = math.ceil(l.h / lineH) + 1
        local line = 0
        local pos = 1
        while pos <= #ed.text and line < startLine + visibleLines do
            local nl = string_find(ed.text, "\n", pos, true)
            if line >= startLine then
                local seg = string.sub(ed.text, pos, nl and nl - 1 or #ed.text)
                local rowY = y + (line - startLine) * lineH - (self.scrollY % lineH)
                canvas:text(seg, x + 6, rowY, { color = P.text })
            end
            if not nl then break end
            pos = nl + 1
            line = line + 1
        end
    end,
}

end)();
(function()
-- widget/modal.lua — модальное окно с ловушкой ввода

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Modal",
    schema = {
        title = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Заголовок модального окна",
        },
    },
    -- модальная ловушка: dispatcher спрашивает виджет в G5
    trapsInput = function(self)
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        -- затемнение фона на весь экран (позиция задаёт пользователь/anchor)
        canvas:rect(0, 0, l.w, l.h, P.overlay)
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
        if self.title ~= "" then
            canvas:text(self.title, x + 10, y + 20, { color = P.text })
        end
    end,
}

end)();
(function()
-- widget/panel.lua — простейший контейнер с фоном

local P = _G.DXUI.palette

return _G.DXUI.registry.define {
    name = "Panel",
    schema = {
        color = {
            type = "number", default = P.bg, invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            token = "bg",
            doc = "Цвет фона панели (упакованное число)",
        },
        radius = {
            type = "number", default = 0, invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            doc = "Радиус скругления углов",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, self.color, { radius = self.radius })
    end,
}

end)();
(function()
-- widget/popup.lua — всплывающая панель

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Popup",
    schema = {
        anchorX = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "X точки появления",
        },
        anchorY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Y точки появления",
        },
    },
    open = function(self)
        self.visible = true
        self:emit("opened")
    end,
    close = function(self)
        self.visible = false
        self:emit("closed")
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
    end,
}

end)();
(function()
-- widget/progressbar.lua — индикатор прогресса

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "ProgressBar",
    schema = {
        value = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Текущее значение (0..max)",
        },
        max = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Максимальное значение",
        },
        color = {
            type = "number", default = P.accent, invalidates = { prop.DIRTY.RENDER },
            doc = "Цвет заполнения",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.bgDisabled, { radius = l.h / 2 })
        local maxV = self.max
        if maxV <= 0 then maxV = 1 end
        local v = self.value
        if v < 0 then v = 0 end
        if v > maxV then v = maxV end
        local w = l.w * (v / maxV)
        if w > 0 then
            canvas:rect(x, y, w, l.h, self.color, { radius = l.h / 2 })
        end
    end,
}

end)();
(function()
-- widget/radiobutton.lua — радиокнопка; группы через radioGroup

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

-- группа: radio widget (weak) -> true; переключение снимает прочих.
-- Слабые ключи: сборщик убирает уничтоженные виджеты сам.
local groups = {}

local function groupOf(name)
    local g = groups[name]
    if g == nil then
        g = setmetatable({}, { __mode = "k" })
        groups[name] = g
    end
    return g
end

local spec = _G.DXUI.registry.define {
    name = "RadioButton",
    interactive = true,
    focusable = true,
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Подпись радиокнопки",
        },
        selected = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Выбрана ли радиокнопка",
        },
        radioGroup = {
            type = "string", default = "default", invalidates = { prop.DIRTY.RENDER },
            doc = "Имя группы; в группе выбран максимум один",
        },
    },
    init = function(self)
        groupOf(self.radioGroup)[self] = true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local d = 16
        local cy = y + (l.h - d) / 2
        canvas:rect(x, cy, d, d, self.selected and P.accent or P.bgHover, { radius = d / 2 })
        if self.selected then
            canvas:rect(x + 5, cy + 5, d - 10, d - 10, P.white, { radius = (d - 10) / 2 })
        end
        if self.text ~= "" then
            canvas:text(self.text, x + d + 6, y + l.h / 2, { alignY = "center", color = P.text })
        end
    end,
}

-- сигнал смены выбора в группе
function spec:select()
    local g = groupOf(self.radioGroup)
    -- снять прочих
    for other in pairs(g) do
        if other ~= self then
            other.selected = false
        end
    end
    self.selected = true
    self:emit("changed")
end

return spec

end)();
(function()
-- widget/scroll.lua — полоса прокрутки (отдельно от ScrollPanel)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Scroll",
    interactive = true,
    schema = {
        position = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Текущая позиция прокрутки",
        },
        total = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Полная длина прокручиваемого содержимого",
        },
        viewport = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Размер видимой области",
        },
        horizontal = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Горизонтальная ориентация",
        },
    },
    -- длина бегунка: max(24px, viewport/total)
    thumbSize = function(self)
        local total = self.total
        if total < self.viewport then
            return 0 -- содержимое полностью видно — бегунок не нужен
        end
        local size = math.max(24, self.viewport * self.viewport / total)
        return size
    end,
    setScroll = function(self, pos)
        local maxScroll = self.total - self.viewport
        if maxScroll < 0 then maxScroll = 0 end
        if pos < 0 then pos = 0 end
        if pos > maxScroll then pos = maxScroll end
        self.position = pos
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local ts = self:thumbSize()
        if ts == 0 then return end
        canvas:rect(x, y, l.w, l.h, P.bgDisabled, { radius = 3 })
        local track = (self.horizontal and l.w or l.h)
        local maxScroll = self.total - self.viewport
        local t = maxScroll > 0 and (self.position / maxScroll) or 0
        local tx = x + (self.horizontal and t * (track - ts) or 0)
        local ty = y + (self.horizontal and 0 or t * (track - ts))
        if self.horizontal then
            canvas:rect(tx, y, ts, l.h, P.textDim, { radius = 3 })
        else
            canvas:rect(x, ty, l.w, ts, P.textDim, { radius = 3 })
        end
    end,
}

end)();
(function()
-- widget/scrollpanel.lua — контейнер с прокруткой содержимого
--
-- Держит единый lay.scrollY (см. layout/flex: дети смещаются при пассе),
-- выставляя Scroll-виджету размеры.

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "ScrollPanel",
    schema = {
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.LAYOUT, prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        rowHeight = {
            type = "number", default = 20, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Высота строки содержимого",
        },
    },
    -- контракт со Scroll: связывание задаёт пользователь обоими концами
    -- (scrollbar пишет scrollpanel.scrollY)
    scrollTo = function(self, pos)
        if pos < 0 then pos = 0 end
        self.scrollY = pos
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        -- прокрутка содержимого выполняется флексом через lay.scrollY
        l.scrollY = self.scrollY
        canvas:rect(x, y, l.w, l.h, P.bgDisabled, { radius = 4 })
        -- рамка сверху содержимого рисуется до детей (Z-порядок дерева)
    end,
}

end)();
(function()
-- widget/slider.lua — ползунок

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Slider",
    interactive = true,
    focusable = true,
    schema = {
        value = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Текущее значение",
        },
        max = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Максимальное значение",
        },
        min = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Минимальное значение",
        },
        step = {
            type = "number", default = 1, invalidates = { prop.DIRTY.RENDER },
            doc = "Шаг изменения значения",
        },
    },
    -- нормализация после записи value: кламп + шаг
    setValue = function(self, v)
        local minV = self.min
        local maxV = self.max
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        local st = self.step
        if st and st > 0 then
            v = minV + math.floor((v - minV) / st + 0.5) * st
        end
        self.value = v
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local trackH = 4
        local ty = y + (l.h - trackH) / 2
        canvas:rect(x, ty, l.w, trackH, P.bgDisabled, { radius = 2 })
        local span = self.max - self.min
        if span <= 0 then span = 1 end
        local t = (self.value - self.min) / span
        local thumbX = x + l.w * t
        canvas:rect(x, ty, l.w * t, trackH, P.accent, { radius = 2 })
        local d = 12
        canvas:rect(thumbX - d / 2, y + (l.h - d) / 2, d, d, P.white, { radius = d / 2 })
    end,
}

end)();
(function()
-- widget/tabpanel.lua — вкладки

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "TabPanel",
    schema = {
        tabs = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив вкладок: { {text=.., page=node}, ... }",
        },
        activeIndex = {
            type = "number", default = 1, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс активной вкладки (1-based)",
        },
        tabHeight = {
            type = "number", default = 30, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота полосы вкладок",
        },
    },
    select = function(self, index)
        local tabs = self.tabs
        if index < 1 or (tabs and index > #tabs) then
            return false
        end
        self.activeIndex = index
        self:emit("tabChanged", index)
        return true
    end,
    -- активная страница (рисуется вкладчиком кадров)
    activePage = function(self)
        local tab = self.tabs[self.activeIndex]
        return tab and tab.page or nil
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local tabs = self.tabs
        local n = tabs and #tabs or 0
        local tabW = n > 0 and l.w / n or l.w
        for i = 1, n do
            local tx = x + (i - 1) * tabW
            canvas:rect(tx, y, tabW, self.tabHeight, i == self.activeIndex and P.bgHover or P.bgDisabled)
            canvas:text(tostring(tabs[i].text or ""), tx + tabW / 2, y + self.tabHeight / 2,
                { alignX = "center", alignY = "center", color = P.text })
        end
        canvas:rect(x, y + self.tabHeight, l.w, l.h - self.tabHeight, P.bg)
        -- контент вкладки — ребёнок (page) в дереве виджетов
    end,
}


end)();
(function()
-- widget/tooltip.lua — подсказка (слабые ссылки, авто-скрытие)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Tooltip",
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Текст подсказки",
        },
        anchorX = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "X точки привязки",
        },
        anchorY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Y точки привязки",
        },
    },
    -- целевой виджет держится слабо: уничтожен — подсказка скрывается
    attachTo = function(self, target)
        self:signal("target-destroyed"):connect(function() end, { weak = true })
        target:signal("destroyed"):connect(function()
            self.visible = false
        end)
        self._target = nil -- сильную ссылку не храним
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        if self.text == "" then return end
        canvas:rect(x, y, l.w, l.h, P.bg, { radius = 4 })
        canvas:text(self.text, x + 8, y + l.h / 2, { alignY = "center", color = P.text })
    end,
}

end)();
(function()
-- widget/treelist.lua — дерево с раскрытием узлов

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "TreeList",
    interactive = true,
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Дерево: {{text=.., children={...}}, ...}",
        },
        rowHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки",
        },
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
    },
    -- раскрытие: открытые узлы по самому узлу
    toggle = function(self, node)
        node.open = not node.open
        self:emit("expanded", node)
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items or {}
        local rh = self.rowHeight
        -- ленивый flatten: только видимые строки
        local row = 0
        local maxRows = math.ceil(l.h / rh) + 2
        local depthAt = {}
        local function drawLevel(list, depth)
            for i = 1, #list do
                local node = list[i]
                row = row + 1
                if row * rh - self.scrollY >= 0 and (row - 1) * rh - self.scrollY <= l.h then
                    local rowY = y + (row - 1) * rh - self.scrollY
                    local indent = x + depth * 16
                    canvas:text(tostring(node.text or ""), indent + 6, rowY + rh / 2, { alignY = "center", color = P.text })
                end
                if node.children and node.open then
                    drawLevel(node.children, depth + 1)
                    if row > maxRows then return end
                end
            end
        end
        drawLevel(items, 0)
    end,
}


end)();
(function()
-- widget/window.lua — окно: заголовок, drag за тайтл, bringToFront по клику

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Window",
    interactive = true,
    schema = {
        title = {
            type = "string", default = "Window", invalidates = { prop.DIRTY.RENDER },
            doc = "Заголовок окна",
        },
        draggable = {
            type = "boolean", default = true, invalidates = { prop.DIRTY.RENDER },
            doc = "Разрешено ли перетаскивание за заголовок",
        },
        headerHeight = {
            type = "number", default = 28, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота заголовка окна",
        },
        padding = {
            type = "number", default = 10, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Внутренний отступ контента",
        },
    },
    -- drag за заголовок (вызывается input/dispatcher с дельтой)
    moveBy = function(self, dx, dy)
        self.x = self.x + dx
        self.y = self.y + dy
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
        -- заголовок
        canvas:rect(x, y, l.w, self.headerHeight, P.bgHover, { radius = 6 })
        canvas:text(self.title, x + 10, y + self.headerHeight / 2, { alignY = "center", color = P.text })
        -- контент рисуют дети с собственным смещением через lay
    end,
}

end)();
(function()
-- debug/inspector.lua — инспектор: дерево, диагностика «почему не видно»
--
-- Инспектор собирает информацию headless-совместимо (таблицы), а живой
-- overlay рисуется через обычный конвейер (canvas): платформенных вызовов
-- рисования вне whitelist нет. Переключение — boot (bindKey F8), рисование —
-- виджет DebugOverlay ниже.

local rawget = rawget

local inspector = {}

-- компактная строка состояния узла для дерева
local function describe(node)
    local inod = rawget(node, "_")
    local l = inod.lay
    return {
        type = inod.widgetType,
        x = l and l.x or 0,
        y = l and l.y or 0,
        w = l and l.w or 0,
        h = l and l.h or 0,
        visible = inod.data.visible ~= false,
        subscriptions = node:getSubscriptionCount(),
        childCount = #inod.children,
    }
end

-- полное дерево: { [1] = { node, info, children = {...} }}
function inspector.dump(root)
    local inod = rawget(root, "_")
    if inod == nil then return nil end
    local out = describe(root)
    out.children = {}
    local children = inod.children
    for i = 1, #children do
        out.children[i] = inspector.dump(children[i])
    end
    return out
end

-- диагностика «почему не видно» (task.md §8): первый найденный ответ
function inspector.diagnose(node)
    local cur = node
    while cur do
        local inod = rawget(cur, "_")
        if inod.data.visible == false then
            return ("visibility: '%s' скрыт (visible=false)")
                :format(inod.widgetType)
        end
        local l = inod.lay
        if l and (l.w == 0 or l.h == 0) then
            return ("size: '%s' с нулевым размером (%dx%d)")
                :format(inod.widgetType, l.w, l.h)
        end
        cur = inod.parent
    end
    return "visible"
end

-- ---------------------------------------------------------------- overlay

local registry = _G.DXUI.registry
local prop = _G.DXUI.prop
local P = _G.DXUI.palette

local overlay = registry.define {
    name = "DebugOverlay",
    schema = {
        lines = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "Строки статистики overlay",
        },
    },
    init = function(self)
        rawget(self, "_").lines = {}
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local lines = rawget(self, "_").lines
        canvas:rect(x, y, l.w, #lines * 16 + 10, P.overlay)
        for i = 1, #lines do
            canvas:text(lines[i], x + 8, y + i * 16, { color = P.white })
        end
    end,
}

local enabled = false
local instance = nil

function inspector.overlayEnable(on)
    enabled = on == true
    if enabled and instance == nil then
        instance = registry.create("DebugOverlay", { x = 8, y = 8, width = 280, height = 200 })
        _G.DXUI.frame.add(instance)
    end
    if instance ~= nil then
        instance.visible = enabled
    end
    return enabled
end

function inspector.overlaySet(lines)
    if instance == nil then return end
    local inod = rawget(instance, "_")
    inod.data.lines = lines
end

function inspector.overlayEnabled()
    return enabled
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.inspector = inspector
return inspector

end)();
(function()
-- debug/profiler.lua — per-widget стоимость кадра + статистика (task.md §8)
--
-- Замер выполняется через единый клок (core/time). Инструментация стоит
-- только при включённом профилировании: в холодном пути — один if.
-- Overlay рисует инспектор (dxui:stats), выборка берётся здесь.

local profiler = {}

local enabled = false
local samples = {}   -- widgetType -> { total, count, worst }
local lastFrameCost = 0
local frameCount = 0

local frameCosts = {}      -- кольцевой буфер, медиана
local FRAME_HISTORY = 120

local function now()
    return _G.DXUI.time.now()
end

function profiler.enable(on)
    enabled = on == true
    return enabled
end

function profiler.isEnabled()
    return enabled
end

-- обёртка замера вокруг одного вызова; возврат значения fn
function profiler.measure(widgetType, fn, ...)
    if not enabled then
        return fn(...)
    end
    local t0 = now()
    local result = fn(...)
    local dt = now() - t0
    local rec = samples[widgetType]
    if rec == nil then
        rec = { total = 0, count = 0, worst = 0 }
        samples[widgetType] = rec
    end
    rec.total = rec.total + dt
    rec.count = rec.count + 1
    if dt > rec.worst then rec.worst = dt end
    return result
end

-- фиксация стоимости кадра (boot: начало/конец onFrame)
function profiler.frameStart()
    frameCount = frameCount + 1
    return now()
end

function profiler.frameEnd(t0)
    lastFrameCost = now() - t0
    frameCosts[frameCount % FRAME_HISTORY + 1] = lastFrameCost
end

-- статистика для overlay/инспектора
function profiler.stats()
    local out = {}
    for widgetType, rec in pairs(samples) do
        out[#out + 1] = {
            type = widgetType,
            calls = rec.count,
            avg = rec.count > 0 and rec.total / rec.count or 0,
            worst = rec.worst,
        }
    end
    return out
end

-- меданные последних кадров (медиана 120 кадров после прогрева)
function profiler.medianFrameCost()
    local costs = {}
    for i = 1, FRAME_HISTORY do
        if frameCosts[i] then costs[#costs + 1] = frameCosts[i] end
    end
    if #costs == 0 then return 0 end
    table.sort(costs)
    local mid = math.floor(#costs / 2) + 1
    if #costs % 2 == 0 then
        return (costs[mid - 1] + costs[mid]) / 2
    end
    return costs[mid]
end

-- сброс (тесты)
function profiler.reset()
    samples = {}
    frameCosts = {}
    frameCount = 0
    lastFrameCost = 0
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.profiler = profiler
return profiler

end)();
]========]
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUIBundle = BUNDLE
return BUNDLE
