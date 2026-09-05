-- widget/window.lua — окно: заголовок, drag за тайтл, bringToFront по клику

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Window",
    interactive = true,
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
    -- §4.1: bringToFront по клику — dispatcher поднимает КОРЕНЬ дерева цели
    raiseOnPress = true,
    -- §4.1: drag за заголовок. Жесты — сигналы dispatcher (press/drag);
    -- moveBy вызывается dispatcher'ом с дельтой движения указателя
    init = function(self)
        self:signal("press"):connect(function(_, py)
            if not self.draggable then return end
            -- мировая Y окна = сумма lay.y по цепочке родителей
            local wy = 0
            local cur = self
            while cur do
                wy = wy + rawget(cur, "_").lay.y
                cur = rawget(cur, "_").parent
            end
            if py >= wy and py <= wy + self.headerHeight then
                self:capturePointer()
            end
        end)
        self:signal("drag"):connect(function(dx, dy)
            -- двигаем только если заголовок захватил указатель: иначе drag
            -- по телу окна (или по детям) перетаскивал бы окно
            if _G.DXUI.dispatcher.getCaptured() == self then
                self:moveBy(dx, dy)
            end
        end)
    end,
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
        canvas:text(self.title, x + 10, y + self.headerHeight / 2, { alignY = "center", color = P.text })
        -- контент рисуют дети с собственным смещением через lay
    end,
}
