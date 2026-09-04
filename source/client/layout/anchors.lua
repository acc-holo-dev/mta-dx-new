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
