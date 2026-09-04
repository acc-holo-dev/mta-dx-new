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

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.class = { define = define, isinstance = isinstance }
return _G.DXUI.class
