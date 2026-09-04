-- widget/tooltip.lua — подсказка (слабые ссылки, авто-скрытие)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Tooltip",
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Текст подсказки",
        },
        anchorX = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "X точки привязки",
        },
        anchorY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Y точки привязки",
        },
    },
    -- целевой виджет держится слабо: уничтожен — подсказка скрывается
    attachTo = function(self, target)
        self:signal("target-destroyed"):connect(function() end, { weak = true })
        target:signal("destroyed"):connect(function()
            self.visible = false
        end)
        self._target = nil -- сильную ссылку не храним
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        if self.text == "" then return end
        canvas:rect(x, y, l.w, l.h, P.bg, { radius = 4 })
        canvas:text(self.text, x + 8, y + l.h / 2, { color = P.text })
    end,
}
