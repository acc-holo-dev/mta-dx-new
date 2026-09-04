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
