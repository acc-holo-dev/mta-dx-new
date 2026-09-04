-- widget/slider.lua — ползунок

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Slider",
    interactive = true,
    focusable = true,
    schema = {
        value = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Текущее значение",
        },
        max = {
            type = "number", default = 100, invalidates = { prop.DIRTY.RENDER },
            doc = "Максимальное значение",
        },
        min = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Минимальное значение",
        },
        step = {
            type = "number", default = 1, invalidates = { prop.DIRTY.RENDER },
            doc = "Шаг изменения значения",
        },
    },
    -- нормализация после записи value: кламп + шаг
    setValue = function(self, v)
        local minV = self.min
        local maxV = self.max
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        local st = self.step
        if st and st > 0 then
            v = minV + math.floor((v - minV) / st + 0.5) * st
        end
        self.value = v
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local trackH = 4
        local ty = y + (l.h - trackH) / 2
        canvas:rect(x, ty, l.w, trackH, P.bgDisabled, { radius = 2 })
        local span = self.max - self.min
        if span <= 0 then span = 1 end
        local t = (self.value - self.min) / span
        local thumbX = x + l.w * t
        canvas:rect(x, ty, l.w * t, trackH, P.accent, { radius = 2 })
        local d = 12
        canvas:rect(thumbX - d / 2, y + (l.h - d) / 2, d, d, P.white, { radius = d / 2 })
    end,
}
