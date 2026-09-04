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
