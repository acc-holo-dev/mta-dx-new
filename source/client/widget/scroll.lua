-- widget/scroll.lua — полоса прокрутки (отдельно от ScrollPanel)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Scroll",
    interactive = true,
    schema = {
        position = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Текущая позиция прокрутки",
        },
        total = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Полная длина прокручиваемого содержимого",
        },
        viewport = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Размер видимой области",
        },
        horizontal = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Горизонтальная ориентация",
        },
    },
    -- длина бегунка: max(24px, viewport/total)
    thumbSize = function(self)
        local total = self.total
        if total < self.viewport then
            return 0 -- содержимое полностью видно — бегунок не нужен
        end
        local size = math.max(24, self.viewport * self.viewport / total)
        return size
    end,
    setScroll = function(self, pos)
        local maxScroll = self.total - self.viewport
        if maxScroll < 0 then maxScroll = 0 end
        if pos < 0 then pos = 0 end
        if pos > maxScroll then pos = maxScroll end
        self.position = pos
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local ts = self:thumbSize()
        if ts == 0 then return end
        canvas:rect(x, y, l.w, l.h, P.bgDisabled, { radius = 3 })
        local track = (self.horizontal and l.w or l.h)
        local maxScroll = self.total - self.viewport
        local t = maxScroll > 0 and (self.position / maxScroll) or 0
        local tx = x + (self.horizontal and t * (track - ts) or 0)
        local ty = y + (self.horizontal and 0 or t * (track - ts))
        if self.horizontal then
            canvas:rect(tx, y, ts, l.h, P.textDim, { radius = 3 })
        else
            canvas:rect(x, ty, l.w, ts, P.textDim, { radius = 3 })
        end
    end,
}
