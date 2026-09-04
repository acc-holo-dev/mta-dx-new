-- widget/label.lua — статический текст

local P = _G.DXUI.palette

return _G.DXUI.registry.define {
    name = "Label",
    schema = {
        text = {
            type = "string", default = "", invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            doc = "Отображаемый текст",
        },
        color = {
            type = "number", default = P.text, invalidates = { _G.DXUI.prop.DIRTY.RENDER },
            doc = "Цвет текста",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:text(self.text, x, y, { color = self.color })
    end,
}
