-- widget/scrollpanel.lua — контейнер с прокруткой содержимого
--
-- Держит единый lay.scrollY (см. layout/flex: дети смещаются при пассе),
-- выставляя Scroll-виджету размеры.

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "ScrollPanel",
    schema = {
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.LAYOUT, prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        rowHeight = {
            type = "number", default = 20, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Высота строки содержимого",
        },
    },
    -- контракт со Scroll: связывание задаёт пользователь обоими концами
    -- (scrollbar пишет scrollpanel.scrollY)
    scrollTo = function(self, pos)
        if pos < 0 then pos = 0 end
        self.scrollY = pos
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        -- прокрутка содержимого выполняется флексом через lay.scrollY
        l.scrollY = self.scrollY
        canvas:rect(x, y, l.w, l.h, P.bgDisabled, { radius = 4 })
        -- рамка сверху содержимого рисуется до детей (Z-порядок дерева)
    end,
}
