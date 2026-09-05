-- widget/window.lua — окно: заголовок, drag за тайтл, resize-маркеры (§4.1),
-- bringToFront по клику. Маркеры: 4 угла + 4 ребра (зона 6px у краёв).

local P = _G.DXUI.palette
local prop = _G.DXUI.prop
local DXUI = _G.DXUI -- namespace на момент загрузки: вызовы идут по нему,
                     -- а не по _G (у потребителя import(2) хост может
                     -- подменять _G.DXUI между загрузкой и вызовом)

local MARKER = 6 -- зона захвата маркера у края окна

return _G.DXUI.registry.define {
    name = "Window",
    interactive = true,
    -- §4.1: bringToFront по клику — dispatcher поднимает КОРЕНЬ дерева цели
    raiseOnPress = true,
    schema = {
        title = {
            type = "string", default = "Window", invalidates = { prop.DIRTY.RENDER },
            doc = "Заголовок окна",
        },
        draggable = {
            type = "boolean", default = true, invalidates = { prop.DIRTY.RENDER },
            doc = "Разрешено ли перетаскивание за заголовок",
        },
        resizable = {
            type = "boolean", default = true, invalidates = { prop.DIRTY.RENDER },
            doc = "Разрешены ли resize-маркеры по краям окна",
        },
        headerHeight = {
            type = "number", default = 28, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота заголовка окна",
        },
        minWidth = {
            type = "number", default = 80, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Минимальная ширина при ресайзе маркерами",
        },
        minHeight = {
            type = "number", default = 50, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Минимальная высота при ресайзе маркерами",
        },
        padding = {
            type = "number", default = 10, invalidates = { prop.DIRTY.LAYOUT },
            doc = "Внутренний отступ контента",
        },
    },
    -- мировые координаты узла = сумма lay по цепочке родителей
    worldPosition = function(self)
        local wx, wy = 0, 0
        local cur = self
        while cur do
            local l = rawget(cur, "_").lay
            wx = wx + l.x
            wy = wy + l.y
            cur = rawget(cur, "_").parent
        end
        return wx, wy
    end,
    -- drag за заголовок (вызывается input/dispatcher с дельтой)
    moveBy = function(self, dx, dy)
        self.x = self.x + dx
        self.y = self.y + dy
    end,
    -- ресайз маркерами: режим {l,r,t,b} — какие края тянем (§4.1, 8 маркеров)
    resizeBy = function(self, dx, dy)
        local m = rawget(self, "_").resizeMode
        if m == nil then return end
        if m.r then
            self.width = math.max(self.minWidth, self.width + dx)
        end
        if m.b then
            self.height = math.max(self.minHeight, self.height + dy)
        end
        if m.l then
            local newW = math.max(self.minWidth, self.width - dx)
            self.x = self.x + (self.width - newW)
            self.width = newW
        end
        if m.t then
            local newH = math.max(self.minHeight, self.height - dy)
            self.y = self.y + (self.height - newH)
            self.height = newH
        end
    end,
    init = function(self)
        self:signal("press"):connect(function(px, py)
            local inod = rawget(self, "_")
            inod.resizeMode = nil
            local wx, wy = self:worldPosition()
            local l = inod.lay
            local lx, ly = px - wx, py - wy
            local left = lx <= MARKER
            local right = lx >= l.w - MARKER
            local top = ly <= MARKER
            local bottom = ly >= l.h - MARKER
            -- маркеры (углы и рёбра) приоритетнее drag заголовка:
            -- press может попасть только внутрь rect окна, зоны снаружи недостижимы
            if self.resizable and (left or right or top or bottom) then
                inod.resizeMode = { l = left, r = right, t = top, b = bottom }
                self:capturePointer()
            elseif self.draggable and ly <= self.headerHeight then
                self:capturePointer()
            end
        end)
        self:signal("drag"):connect(function(dx, dy)
            -- двигаем/растягиваем только если окно захватило указатель:
            -- иначе drag по телу или по детям перетаскивал бы окно
            if DXUI.dispatcher.getCaptured() ~= self then return end
            if rawget(self, "_").resizeMode then
                self:resizeBy(dx, dy)
            else
                self:moveBy(dx, dy)
            end
        end)
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
        -- заголовок
        canvas:rect(x, y, l.w, self.headerHeight, P.bgHover, { radius = 6 })
        canvas:text(self.title, x + 10, y + self.headerHeight / 2, { alignY = "center", color = P.text })
        -- контент рисуют дети с собственным смещением через lay
        -- маркеры ресайза — когда окно в фокусе (§4.1)
        local focus = DXUI.focus
        if self.resizable and focus and focus.get() == self then
            local M = MARKER
            canvas:rect(x, y, M, M, P.accent)
            canvas:rect(x + l.w - M, y, M, M, P.accent)
            canvas:rect(x, y + l.h - M, M, M, P.accent)
            canvas:rect(x + l.w - M, y + l.h - M, M, M, P.accent)
            canvas:rect(x + l.w / 2 - M / 2, y, M, M, P.border)
            canvas:rect(x + l.w / 2 - M / 2, y + l.h - M, M, M, P.border)
            canvas:rect(x, y + l.h / 2 - M / 2, M, M, P.border)
            canvas:rect(x + l.w - M, y + l.h / 2 - M / 2, M, M, P.border)
        end
    end,
}
