-- widget/window.lua — окно: заголовок, drag за тайтл, bringToFront по клику

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Window",
    schema = {
        title = {
            type = "string", default = "Window", invalidates = { prop.DIRTY.RENDER },
            doc = "Заголовок окна",
        },
        draggable = {
            type = "boolean", default = true, invalidates = { prop.DIRTY.RENDER },
            doc = "Разрешено ли перетаскивание за заголовок",
        },
        headerHeight = {
            type = "number", default = 28, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота заголовка окна",
        },
        padding = {
            type = "number", default = 10, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Внутренний отступ контента",
        },
    },
    -- drag за заголовок (вызывается input/dispatcher с дельтой)
    moveBy = function(self, dx, dy)
        self.x = self.x + dx
        self.y = self.y + dy
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
        -- заголовок
        canvas:rect(x, y, l.w, self.headerHeight, P.bgHover, { radius = 6 })
        canvas:text(self.title, x + 10, y + self.headerHeight / 2, { color = P.text })
        -- контент рисуют дети с собственным смещением через lay
    end,
}
