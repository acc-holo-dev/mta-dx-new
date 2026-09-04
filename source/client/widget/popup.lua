-- widget/popup.lua — всплывающая панель

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Popup",
    schema = {
        anchorX = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "X точки появления",
        },
        anchorY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Y точки появления",
        },
    },
    open = function(self)
        self.visible = true
        self:emit("opened")
    end,
    close = function(self)
        self.visible = false
        self:emit("closed")
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        canvas:rect(x, y, l.w, l.h, P.windowBg, { radius = 6 })
    end,
}
