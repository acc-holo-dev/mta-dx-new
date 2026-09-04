-- text/editor.lua — headless-ядро ввода текста (task.md §3.7)
--
-- Конечный автомат БЕЗ отрисовки: caret/selection/undo(5)/blink.
-- Виджет (Edit/Memo) читает состояние и рисует его. Тестируется без игры.

local string_sub = string.sub
local string_find = string.find
local table_insert = table.insert
local table_remove = table.remove

local UNDO_DEPTH = 5
local BLINK_MS = 500

local Editor = {}
Editor.__index = Editor

local function new(text)
    local self = setmetatable({}, Editor)
    self.text = text or ""
    self.caret = 1 -- 1..#text+1 (Lua-индексация)
    self.anchor = 1 -- вторая граница выделения
    self.undoStack = {}
    self.undoCount = 0
    self.blinkPhase = 0
    return self
end

-- ---------------------------------------------------------------- selection

function Editor:hasSelection()
    return self.caret ~= self.anchor
end

function Editor:getSelection()
    local a, b = self.caret, self.anchor
    if a > b then a, b = b, a end
    return a, b
end

function Editor:selectionText()
    local a, b = self:getSelection()
    return string_sub(self.text, a, b - 1)
end

-- ---------------------------------------------------------------- editing

local function pushUndo(self)
    self.undoCount = self.undoCount + 1
    self.undoStack[self.undoCount] = { text = self.text, caret = self.caret }
    if self.undoCount > UNDO_DEPTH then
        table_remove(self.undoStack, 1)
        self.undoCount = self.undoCount - 1
    end
end

-- вставка/замата с учётом выделения; возвращает true, если текст изменился
function Editor:insert(str)
    if self:hasSelection() then
        self:delete() -- delete вызывает pushUndo
    else
        pushUndo(self)
    end
    local t = self.text
    local c = self.caret
    self.text = string_sub(t, 1, c - 1) .. str .. string_sub(t, c)
    self.caret = c + #str
    self.anchor = self.caret
    return true
end

-- удаление символа в направлении caret (-1 назад, 1 вперёд); при выделении
-- удаляется оно
function Editor:delete(dir)
    if self:hasSelection() then
        pushUndo(self)
        local a, b = self:getSelection()
        self.text = string_sub(self.text, 1, a - 1) .. string_sub(self.text, b)
        self.caret = a
        self.anchor = a
        return true
    end
    local pos = self.caret + (dir or 1)
    if dir == -1 then
        pos = self.caret - 1
    end
    if pos < 1 or pos > #self.text then
        return false
    end
    pushUndo(self)
    self.text = string_sub(self.text, 1, pos - 1) .. string_sub(self.text, pos + 1)
    self.caret = pos
    self.anchor = pos
    return true
end

-- ---------------------------------------------------------------- undo

function Editor:undo()
    local last = self.undoStack[self.undoCount]
    if last == nil then
        return false
    end
    self.undoCount = self.undoCount - 1
    self.text = last.text
    self.caret = last.caret
    self.anchor = self.caret
    return true
end

-- ---------------------------------------------------------------- движение

function Editor:move(delta, extendSelection)
    local pos = self.caret + delta
    if pos < 1 then pos = 1 end
    if pos > #self.text + 1 then pos = #self.text + 1 end
    self.caret = pos
    if not extendSelection then
        self.anchor = pos
    end
end

-- ---------------------------------------------------------------- blink

-- единый клок из core/time; caretVisible зовёт себя с now
function Editor:caretVisible(now)
    local phase = math.floor(now / BLINK_MS) % 2
    return phase == 0
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.editor = { new = new }
return _G.DXUI.editor
