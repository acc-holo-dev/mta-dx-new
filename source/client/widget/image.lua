-- widget/image.lua — растровое изображение

local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Image",
    schema = {
        texture = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "Текстура (создаётся dxCreateTexture)",
        },
        slice = {
            type = "table", invalidates = { prop.DIRTY.RENDER },
            doc = "9-slice поля: { left, top, right, bottom }",
        },
        rotate = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Поворот в радианах",
        },
    },
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        if self.texture then
            canvas:image(self.texture, x, y, l.w, l.h, {
                rotate = self.rotate,
                slice = self.slice,
            })
        end
    end,
}
