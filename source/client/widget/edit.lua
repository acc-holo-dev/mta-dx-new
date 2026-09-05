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
        local inod = rawget(self, "_")
        if inod.ctrlHeld then
            return false -- Ctrl+C и т.п. не должны вставлять символы (§3.7)
        end
        local ed = inod.editor
        if self.maxLength > 0 and #ed.text >= self.maxLength then
            return false
        end
        ed:insert(ch)
        return true
    end,
    inputKey = function(self, key, down)
        local inod = rawget(self, "_")
        local ed = inod.editor
        -- модификаторы: отслеживаем И down, И up (dispatcher шлёт ups
        -- модификаторов отдельно — без них Ctrl «залипал» бы)
        if key == "lctrl" or key == "rctrl" then
            inod.ctrlHeld = down
            return true
        end
        if key == "lshift" or key == "rshift" then
            inod.shiftHeld = down
            return true
        end
        if inod.ctrlHeld then
            -- буфер обмена и undo — через мост dispatcher (§3.7)
            if key == "z" then
                return ed:undo()
            elseif key == "c" then
                if ed:hasSelection() then
                    _G.DXUI.dispatcher.setClipboard(ed:selectionText())
                    return true
                end
                return false
            elseif key == "x" then
                if ed:hasSelection() then
                    _G.DXUI.dispatcher.setClipboard(ed:selectionText())
                    return ed:delete(1)
                end
                return false
            elseif key == "v" then
                local text = _G.DXUI.dispatcher.getClipboard()
                if text and text ~= "" and (self.maxLength <= 0 or #ed.text < self.maxLength) then
                    return ed:insert(text)
                end
                return false
            end
            return true -- прочие Ctrl-комбинации глотаем, в поле не попадают
        end
        local extend = inod.shiftHeld == true
        if key == "backspace" then
            return ed:delete(-1)
        elseif key == "delete" then
            return ed:delete(1)
        elseif key == "arrow_l" then
            ed:move(-1, extend)
        elseif key == "arrow_r" then
            ed:move(1, extend)
        elseif key == "home" then
            ed.caret = 1
            if not extend then ed.anchor = 1 end
        elseif key == "end" then
            ed.caret = #ed.text + 1
            if not extend then ed.anchor = ed.caret end
        end
        return true
    end,
    render = function(self, canvas, x, y)
        local l = rawget(self, "_").lay
        local ed = rawget(self, "_").editor
        canvas:rect(x, y, l.w, l.h, P.bg, { radius = 4 })
        local text = ed.text
        if text == "" and self.placeholder ~= "" then
            canvas:text(self.placeholder, x + 8, y + l.h / 2, { alignY = "center", color = P.textDim })
        else
            if self.password then
                local masked = ("*"):rep(#text)
                canvas:text(masked, x + 8, y + l.h / 2, { alignY = "center", color = P.text })
            else
                canvas:text(text, x + 8, y + l.h / 2, { alignY = "center", color = P.text })
            end
        end
    end,
}
