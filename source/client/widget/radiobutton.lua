-- widget/radiobutton.lua — радиокнопка; группы через radioGroup

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

-- группа: value -> radio widget; переключение снимает прочих
local groups = {}

local function groupOf(name)
    local g = groups[name]
    if g == nil then
        g = {}
        groups[name] = g
    end
    return g
end

local spec = _G.DXUI.registry.define {
    name = "RadioButton",
    schema = {
        text = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Подпись радиокнопки",
        },
        selected = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Выбрана ли радиокнопка",
        },
        radioGroup = {
            type = "string", default = "default", invalidates = { prop.DIRTY.RENDER },
            doc = "Имя группы; в группе выбран максимум один",
        },
    },
    init = function(self)
        local name = tostring(self)
        groupOf("default")[name] = self
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local d = 16
        local cy = y + (l.h - d) / 2
        canvas:rect(x, cy, d, d, self.selected and P.accent or P.bgHover, { radius = d / 2 })
        if self.selected then
            canvas:rect(x + 5, cy + 5, d - 10, d - 10, P.white, { radius = (d - 10) / 2 })
        end
        if self.text ~= "" then
            canvas:text(self.text, x + d + 6, y + l.h / 2, { color = P.text })
        end
    end,
}

-- сигнал смены выбора в группе
function spec:select()
    local groupName = self.radioGroup
    local g = groupOf(groupName)
    -- снять прочих
    for _, other in pairs(g) do
        if other ~= self then
            other.selected = false
        end
    end
    self.selected = true
    self:emit("changed")
end

return spec
