-- widget/gridlist.lua — виртуализированная сетка данных (task.md §6.1:
-- 10 000 строк ≈ 20: узлов O(visible)+2, скролл подменяет данные)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "GridList",
    interactive = true,
    focusable = true,
    -- стрелки вверх/вниз = выбранная строка (не навигация фокуса, §3.5)
    arrowNavigation = true,
    schema = {
        selectedIndex = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс выбранной ячейки (0 = нет)",
        },
        columns = {
            type = "number", default = 1, invalidates = { prop.DIRTY.RENDER },
            doc = "Число колонок",
        },
        items = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив данных (строки или {text=...})",
        },
        rowHeight = {
            type = "number", default = 24, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки",
        },
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        virtualized = {
            type = "boolean", default = true, invalidates = { prop.DIRTY.RENDER },
            doc = "Рисовать только видимые строки",
        },
    },
    rowsTotal = function(self)
        local items = self.items
        local n = items and #items or 0
        local cols = math.max(1, self.columns)
        return math.ceil(n / cols)
    end,
    -- стрелки: следующая/предыдущая ячейка + автоскролл к выбранной (§3.5)
    inputKey = function(self, key, down)
        if not down then return true end
        local items = self.items
        local n = items and #items or 0
        if n == 0 then return true end
        local sel = self.selectedIndex
        if key == "arrow_d" then
            sel = math.min(n, sel + 1)
        elseif key == "arrow_u" then
            sel = math.max(1, sel - 1)
        else
            return true
        end
        if sel ~= self.selectedIndex then
            self.selectedIndex = sel
            self:emit("selectionChanged", sel)
            local l = rawget(self, "_").lay
            local cols = math.max(1, self.columns)
            local rh = self.rowHeight
            local row = math.ceil(sel / cols)
            local top = (row - 1) * rh
            if top < self.scrollY then
                self.scrollY = top
            elseif top + rh > self.scrollY + l.h then
                self.scrollY = top + rh - l.h
            end
        end
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local items = self.items or {}
        local n = #items
        local cols = math.max(1, self.columns)
        local rh = self.rowHeight
        local rows = math.ceil(n / cols)
        local colW = l.w / cols

        local firstRow = 0
        local lastRow = rows
        if self.virtualized then
            firstRow = math.floor(self.scrollY / rh)
            if firstRow < 0 then firstRow = 0 end
            lastRow = math.min(rows, firstRow + math.ceil(l.h / rh) + 2)
        end

        for row = firstRow + 1, lastRow do
            local rowY = y + (row - 1) * rh - self.scrollY
            for col = 1, cols do
                local idx = (row - 1) * cols + col
                if idx <= n then
                    local cellX = x + (col - 1) * colW
                    local item = items[idx]
                    if type(item) == "table" then
                        item = item.text
                    end
                    if idx == self.selectedIndex then
                        canvas:rect(cellX, rowY, colW, rh, P.accentDim)
                    else
                        canvas:rect(cellX, rowY, colW, rh, row % 2 == 0 and P.bg or P.bgHover)
                    end
                    canvas:text(tostring(item), cellX + 6, rowY + rh / 2, { alignY = "center", color = P.text })
                end
            end
        end
    end,
}

