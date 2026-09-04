-- widget/modal.lua — модальное окно с ловушкой ввода

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Modal",
    schema = {
        title = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Заголовок модального окна",
        },
    },
    -- модальная ловушка: dispatcher спрашивает виджет в G5
    trapsInput = function(self)
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        -- затемнение фона на весь экран (позиция задаёт пользователь/anchor)
        canvas:rect(0, 0, l.w, l.h, P.overlay)
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
        if self.title ~= "" then
            canvas:text(self.title, x + 10, y + 20, { color = P.text })
        end
    end,
}
