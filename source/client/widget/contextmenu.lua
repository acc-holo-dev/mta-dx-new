-- widget/contextmenu.lua — контекстное меню (строки = данные)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "ContextMenu",
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив пунктов: { {text=.., onPick=fn}, ... }",
        },
        itemHeight = {
            type = "number", default = 26, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота пункта",
        },
        hoverIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс пункта под курсором (0 = нет)",
        },
    },
    -- координаты пункта по индексу (для dispatcher/hit_test в G5)
    itemRect = function(self, index)
        local l = rawget(self, "_").lay
        return 0, (index - 1) * self.itemHeight, l.w, self.itemHeight
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items or {}
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 4 })
        for i = 1, #items do
            local iy = y + (i - 1) * self.itemHeight
            if i == self.hoverIndex then
                canvas:rect(x, iy, l.w, self.itemHeight, P.accentDim)
            end
            canvas:text(tostring(items[i].text or ""), x + 10, iy + self.itemHeight / 2, { alignY = "center", color = P.text })
        end
    end,
}

