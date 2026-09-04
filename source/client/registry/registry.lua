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
