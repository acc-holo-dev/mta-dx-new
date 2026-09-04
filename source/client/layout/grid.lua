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
