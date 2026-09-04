-- widget/tabpanel.lua — вкладки

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "TabPanel",
    schema = {
        tabs = {
            type = "table",
            invalidates = { prop.DIRTY.RENDER },
            doc = "Массив вкладок: { {text=.., page=node}, ... }",
        },
        activeIndex = {
            type = "number", default = 1, invalidates = { prop.DIRTY.RENDER },
            doc = "Индекс активной вкладки (1-based)",
        },
        tabHeight = {
            type = "number", default = 30, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота полосы вкладок",
        },
    },
    select = function(self, index)
        local tabs = self.tabs
        if index < 1 or (tabs and index > #tabs) then
            return false
        end
        self.activeIndex = index
        self:emit("tabChanged", index)
        return true
    end,
    -- активная страница (рисуется вкладчиком кадров)
    activePage = function(self)
        local tab = self.tabs[self.activeIndex]
        return tab and tab.page or nil
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local tabs = self.tabs
        local n = tabs and #tabs or 0
        local tabW = n > 0 and l.w / n or l.w
        for i = 1, n do
            local tx = x + (i - 1) * tabW
            canvas:rect(tx, y, tabW, self.tabHeight, i == self.activeIndex and P.bgHover or P.bgDisabled)
            canvas:text(tostring(tabs[i].text or ""), tx + tabW / 2, y + self.tabHeight / 2, { color = P.text })
        end
        canvas:rect(x, y + self.tabHeight, l.w, l.h - self.tabHeight, P.bg)
        -- контент вкладки — ребёнок (page) в дереве виджетов
    end,
}

