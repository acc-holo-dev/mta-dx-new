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

-- установка значения через схему; возвращает true, если значение изменилось
function prop.set(node, key, value)
    local inod = node._
    local spec = inod.schema[key]
    if spec == nil then
        devError(("dxui: property '%s' does not exist on '%s'"):format(tostring(key), tostring(inod.widgetType)))
        return false
    end
    if not checkType(spec.type, value) then
        devError(("dxui: %s.%s expects %s, got %s"):format(
            tostring(inod.widgetType), tostring(key), tostring(spec.type), type(value)))
        return false
    end
    if spec.transform then
        value = spec.transform(value, node)
    end
    local data = inod.data
    if data[key] == value then
        return false -- равное значение не инвалидирует
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

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.prop = prop
return prop
