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
        _G.DXUI.frame.add(instance) -- publish-паттерн: читается на момент вызова
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
