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
        rawget(self, "_").editor:insert(ch)
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
