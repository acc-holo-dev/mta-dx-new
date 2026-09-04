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
