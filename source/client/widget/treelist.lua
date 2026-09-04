-- widget/treelist.lua — дерево с раскрытием узлов

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "TreeList",
    interactive = true,
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Дерево: {{text=.., children={...}}, ...}",
        },
        rowHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки",
        },
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
    },
    -- раскрытие: открытые узлы по самому узлу
    toggle = function(self, node)
        node.open = not node.open
        self:emit("expanded", node)
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items or {}
        local rh = self.rowHeight
        -- ленивый flatten: только видимые строки
        local row = 0
        local maxRows = math.ceil(l.h / rh) + 2
        local depthAt = {}
        local function drawLevel(list, depth)
            for i = 1, #list do
                local node = list[i]
                row = row + 1
                if row * rh - self.scrollY >= 0 and (row - 1) * rh - self.scrollY <= l.h then
                    local rowY = y + (row - 1) * rh - self.scrollY
                    local indent = x + depth * 16
                    canvas:text(tostring(node.text or ""), indent + 6, rowY + rh / 2, { color = P.text })
                end
                if node.children and node.open then
                    drawLevel(node.children, depth + 1)
                    if row > maxRows then return end
                end
            end
        end
        drawLevel(items, 0)
    end,
}

