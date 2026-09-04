-- widget/edit.lua — однострочное поле ввода на text/ headless-ядре

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

local editor_mod = _G.DXUI.editor

return _G.DXUI.registry.define {
    name = "Edit",
    interactive = true,
    focusable = true,
    editable = true,
    schema = {
        placeholder = {
            type = "string", default = "", invalidates = { prop.DIRTY.RENDER },
            doc = "Текст-подсказка при пустом поле",
        },
        maxLength = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Максимальная длина (0 = без ограничения)",
        },
        password = {
            type = "boolean", default = false, invalidates = { prop.DIRTY.RENDER },
            doc = "Скрывать ввод звёздочками",
        },
    },
    -- текст хранится в editor-ядре; свойство text делегируется ниже
    init = function(self)
        rawget(self, "_").editor = editor_mod.new("")
    end,
    getText = function(self)
        return rawget(self, "_").editor.text
    end,
    setText = function(self, str)
        local ed = rawget(self, "_").editor
        ed.text = str
        ed.caret = #str + 1
        ed.anchor = ed.caret
    end,
    -- ввод символа (мост onClientCharacter приезжает сюда через dispatcher)
    inputCharacter = function(self, ch)
        local ed = rawget(self, "_").editor
        if self.maxLength > 0 and #ed.text >= self.maxLength then
            return false
        end
        ed:insert(ch)
        return true
    end,
    inputKey = function(self, key, down)
        local ed = rawget(self, "_").editor
        if key == "backspace" then
            return ed:delete(-1)
        elseif key == "delete" then
            return ed:delete(1)
        elseif key == "arrow_l" then
            ed:move(-1, down)
        elseif key == "arrow_r" then
            ed:move(1, down)
        elseif key == "home" then
            ed.caret = 1
            if not down then ed.anchor = 1 end
        elseif key == "end" then
            ed.caret = #ed.text + 1
            if not down then ed.anchor = ed.caret end
        end
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local ed = rawget(self, "_").editor
        canvas:rect(x, y, l.w, l.h, P.bg, { radius = 4 })
        local text = ed.text
        if text == "" and self.placeholder ~= "" then
            canvas:text(self.placeholder, x + 8, y + l.h / 2, { color = P.textDim })
        else
            if self.password then
                local masked = ("*"):rep(#text)
                canvas:text(masked, x + 8, y + l.h / 2, { color = P.text })
            else
                canvas:text(text, x + 8, y + l.h / 2, { color = P.text })
            end
        end
    end,
}
