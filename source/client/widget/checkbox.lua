-- widget/checkbox.lua — флажок с подписью

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Checkbox",
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Подпись чекбокса",
        },
        checked = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Состояние отметки",
        },
        boxColor = {
            type = "number", default = P.accent, invalidates = { prop.DIRTY.RENDER },
            doc = "Цвет отметенного состояния",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local boxSize = 16
        canvas:rect(x, y + (l.h - boxSize) / 2, boxSize, boxSize, self.checked and self.boxColor or P.bgHover, { radius = 3 })
        if self.checked then
            -- галочка
            canvas:rect(x + 3, y + (l.h - boxSize) / 2 + 3, boxSize - 6, boxSize - 6, P.white)
        end
        if self.text ~= "" then
            canvas:text(self.text, x + boxSize + 6, y + l.h / 2, { color = P.text })
        end
    end,
}
