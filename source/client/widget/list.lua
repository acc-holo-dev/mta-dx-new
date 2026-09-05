-- widget/list.lua — список строк (виртуализуемый)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "List",
    interactive = true,
    schema = {
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив строк",
        },
        rowHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки",
        },
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        selectedIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс выбранной строки (0 = нет)",
        },
    },
    -- число строк, которые реально рисуются (виртуализация: O(visible)+2)
    visibleRows = function(self)
        local l = rawget(self, "_").lay
        return math.ceil(l.h / self.rowHeight) + 2
    end,
    rowsTotal = function(self)
        local items = self.items
        return items and #items or 0
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items
        local n = items and #items or 0
        local rh = self.rowHeight
        local first = math.floor(self.scrollY / rh)
        if first < 0 then first = 0 end
        local visible = math.ceil(l.h / rh) + 2
        for i = 1, math.min(first + visible, n) do
            local idx = i -- только строки в области экрана
            if idx > first then
                local rowY = y + (idx - 1) * rh - self.scrollY
                if rowY < y + l.h and rowY + rh > y then
                    if idx == self.selectedIndex then
                        canvas:rect(x, rowY, l.w, rh, P.bgHover)
                    end
                    canvas:text(tostring(items[idx]), x + 6, rowY + rh / 2, { alignY = "center", color = P.text })
                end
            end
        end
    end,
}

