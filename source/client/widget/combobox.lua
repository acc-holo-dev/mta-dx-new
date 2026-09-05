-- widget/combobox.lua — выпадающий список

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Combobox",
    interactive = true,
    focusable = true,
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив вариантов",
        },
        selectedIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс выбранного варианта (0 = ничего)",
        },
        opened = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Раскрыт ли список",
        },
        itemHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота пункта списка",
        },
    },
    toggle = function(self)
        self.opened = not self.opened
        self:emit(self.opened and "opened" or "closed")
    end,
    pick = function(self, index)
        if self.items[index] == nil then
            return false
        end
        self.selectedIndex = index
        self.opened = false
        self:emit("picked", index)
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        -- поле выбора
        canvas:rect(x, y, l.w, l.h, P.bgHover, { radius = 4 })
        local current = self.items and self.items[self.selectedIndex] or nil
        canvas:text(tostring(current or "..."), x + 8, y + l.h / 2, { alignY = "center", color = P.text })
        -- стрелка
        local ax = x + l.w - 13
        canvas:text(self.opened and "^" or "v", ax, y + l.h / 2, { alignY = "center", color = P.textDim })
        -- раскрытый список
        if self.opened then
            local items = self.items or {}
            local n = #items
            local ih = self.itemHeight
            canvas:rect(x, y + l.h, l.w, n * ih, P.windowBg, { radius = 4 })
            for i = 1, n do
                local iy = y + l.h + (i - 1) * ih
                canvas:text(tostring(items[i]), x + 8, iy + ih / 2, { alignY = "center", color = P.text })
            end
        end
    end,
}

