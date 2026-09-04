-- widget/panel.lua — простейший контейнер с фоном

local P = _G.DXUI.palette

return _G.DXUI.registry.define {
    name = "Panel",
    schema = {
        color = {
            type = "number", default = P.bg, invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            doc = "Цвет фона панели (упакованное число)",
        },
        radius = {
            type = "number", default = 0, invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            doc = "Радиус скругления углов",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, self.color, { radius = self.radius })
    end,
}
