-- widget/progressbar.lua — индикатор прогресса

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "ProgressBar",
    schema = {
        value = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Текущее значение (0..max)",
        },
        max = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Максимальное значение",
        },
        color = {
            type = "number", default = P.accent, invalidates = { prop.DIRTY.RENDER },
            doc = "Цвет заполнения",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.bgDisabled, { radius = l.h / 2 })
        local maxV = self.max
        if maxV <= 0 then maxV = 1 end
        local v = self.value
        if v < 0 then v = 0 end
        if v > maxV then v = maxV end
        local w = l.w * (v / maxV)
        if w > 0 then
            canvas:rect(x, y, w, l.h, self.color, { radius = l.h / 2 })
        end
    end,
}
