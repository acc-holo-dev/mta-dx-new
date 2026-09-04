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
