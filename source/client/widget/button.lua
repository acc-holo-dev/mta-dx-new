-- widget/button.lua — эталонная схема виджета (task.md §4.1)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Button",
    interactive = true,
    focusable = true,
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Надпись кнопки",
        },
        icon = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "Текстура-иконка",
        },
        disabled = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Блокировка кнопки",
        },
        onPress = {
            type = "function", invalidates = {},
            doc = "Обработчик нажатия (требуется)",
        },
        color = {
            type = "number", default = P.accent, invalidates = { prop.DIRTY.RENDER },
            doc = "Цвет фона кнопки",
        },
        textColor = {
            type = "number", default = P.white, invalidates = { prop.DIRTY.RENDER },
            doc = "Цвет надписи",
        },
    },
    required = { "text", "onPress" },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local bg = self.color
        if self.disabled then
            bg = P.bgDisabled
        end
        canvas:rect(x, y, l.w, l.h, bg, { radius = 4 })
        if self.icon then
            canvas:image(self.icon, x, y, l.h, l.h)
        end
        local tx = x + (self.icon and l.h or 0)
        canvas:text(self.text, tx + l.w / 2, y + l.h / 2, { color = self.disabled and P.textDim or self.textColor })
    end,
}
