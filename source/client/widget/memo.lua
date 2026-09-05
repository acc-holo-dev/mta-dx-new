-- widget/memo.lua — многострочное поле (Edit на строчках + newline)

local P = _G.DXUI.palette
local prop = _G.DXUI.prop

return _G.DXUI.registry.define {
    name = "Memo",
    schema = {
        scrollY = {
            type = "number", default = 0, invalidates = { prop.DIRTY.RENDER },
            doc = "Вертикальная прокрутка (px)",
        },
        lineHeight = {
            type = "number", default = 15, invalidates = { prop.DIRTY.RENDER },
            doc = "Высота строки текста",
        },
    },
    init = function(self)
        rawget(self, "_").editor = _G.DXUI.editor.new("")
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
    inputCharacter = function(self, ch)
        if rawget(self, "_").ctrlHeld then
            return false -- Ctrl+C и т.п. не должны вставлять символы (§3.7)
        end
        rawget(self, "_").editor:insert(ch)
        return true
    end,
    inputKey = function(self, key, down)
        local inod = rawget(self, "_")
        local ed = inod.editor
        -- модификаторы: отслеживаем И down, И up (dispatcher шлёт ups)
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
                if text and text ~= "" then
                    return ed:insert(text)
                end
                return false
            end
            return true
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
        -- строки рисуются с учётом прокрутки
        local lineH = self.lineHeight
        local startLine = math.floor(self.scrollY / lineH)
        local visibleLines = math.ceil(l.h / lineH) + 1
        local line = 0
        local pos = 1
        while pos <= #ed.text and line < startLine + visibleLines do
            local nl = string_find(ed.text, "\n", pos, true)
            if line >= startLine then
                local seg = string.sub(ed.text, pos, nl and nl - 1 or #ed.text)
                local rowY = y + (line - startLine) * lineH - (self.scrollY % lineH)
                canvas:text(seg, x + 6, rowY, { color = P.text })
            end
            if not nl then break end
            pos = nl + 1
            line = line + 1
        end
    end,
}
