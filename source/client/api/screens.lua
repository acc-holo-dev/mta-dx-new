-- api/screens.lua — Screen Stack: push/pop экранов с историей (task.md §3.8)
--
-- Экран — корневой виджет (обычно Window/Panel), переданный в управление
-- стеку. push прячет текущий экран (visible=false), показывает новый и
-- запоминает фокус; pop снимает экран, возвращает прежний и ВОССТАНАВЛИВАЕТ
-- фокус. Переходы — transition-токены: "slide" твином координаты (конвейер
-- твинов §5); "fade" ждёт opacity-канал в холсте (не реализован).
--
-- Сериализация раскладки (§3.8): saveLayout() -> XML-строка (позиции/размеры
-- окон среди корней кадра + текущая палитра), loadLayout(xml) применяет.
-- Файловый I/O — за вызывающей стороной (whitelist §2): boot пишет
-- layout.xml командами dxui:save-layout / dxui:load-layout, потребители
-- хранят строку как им удобно.

local DXUI = _G.DXUI

local screens = {}

local stack = {}  -- { root=, prev=, prevFocus= }
local current = nil

-- первый фокусируемый виджет экрана (pre-order, видимые ветви)
local function firstFocusable(root)
    local focus = DXUI.focus
    local found = nil
    local function walk(node)
        if found then return end
        local inod = rawget(node, "_")
        if inod == nil then return end
        if inod.data.visible == false then return end
        local spec = rawget(node, "_renderSpec")
        if spec and spec.focusable then
            found = node
            return
        end
        local children = inod.children
        for i = 1, #children do
            walk(children[i])
        end
    end
    walk(root)
    return found
end

-- push(root, opts?): показать экран поверх текущего.
-- opts.transition = "slide" — появление снизу вверх (0.25 с, outQuad)
function screens.push(root, opts)
    if type(root) ~= "table" or current == root then return root end
    local prev = current
    local prevFocus = DXUI.focus.get()
    if prev then
        prev.visible = false
    end
    DXUI.frame.add(root)
    stack[#stack + 1] = { root = root, prev = prev, prevFocus = prevFocus }
    current = root
    if opts and opts.transition == "slide" then
        local targetY = root.y
        root.y = targetY + 40
        DXUI.tween.to(root, 0.25, { y = targetY, easing = "outQuad" })
    end
    local f = firstFocusable(root)
    if f then
        DXUI.focus.set(f)
        if DXUI.focus.isEditable(f) then
            DXUI.focus.setEditing(true)
        end
    else
        DXUI.focus.clear()
    end
    return root
end

-- pop(opts?): снять текущий экран и вернуть предыдущий.
-- opts.destroy = true — уничтожить корень снятого экрана
function screens.pop(opts)
    local entry = stack[#stack]
    if entry == nil then return nil end
    stack[#stack] = nil
    DXUI.frame.remove(entry.root)
    if opts and opts.destroy and entry.root.destroy then
        entry.root:destroy()
    end
    current = entry.prev
    if current then
        current.visible = true
    end
    -- возврат восстанавливает фокус (§3.8), если узел ещё жив
    local pf = entry.prevFocus
    if pf ~= nil and rawget(pf, "_") ~= nil then
        DXUI.focus.set(pf)
    else
        DXUI.focus.clear()
    end
    return entry.root
end

function screens.current()
    return current
end

function screens.depth()
    return #stack
end

-- снять все экраны (destroy корней — по умолчанию)
function screens.clear(opts)
    local destroy = opts == nil or opts.destroy ~= false
    for i = #stack, 1, -1 do
        local e = stack[i]
        DXUI.frame.remove(e.root)
        if destroy and e.root.destroy then
            e.root:destroy()
        end
        stack[i] = nil
    end
    current = nil
    DXUI.focus.clear()
end

-- ---------------------------------------------------------------- сериализация

local function esc(s)
    return tostring(s):gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;")
end

-- XML: окна среди корней кадра (по заголовку) + текущие значения палитры
function screens.saveLayout()
    local parts = {}
    parts[#parts + 1] = '<dxui version="2">'
    local roots = DXUI.frame.roots()
    for i = 1, #roots do
        local inod = rawget(roots[i], "_")
        if inod and inod.widgetType == "Window" then
            local d = inod.data
            parts[#parts + 1] = ('  <window title="%s" x="%d" y="%d" width="%d" height="%d"/>')
                :format(esc(d.title or ""), d.x or 0, d.y or 0, d.width or 0, d.height or 0)
        end
    end
    local palette = DXUI.palette
    local keys = {}
    for k in pairs(palette) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = ('  <color name="%s" value="0x%08X"/>'):format(k, palette[k])
    end
    parts[#parts + 1] = "</dxui>"
    return table.concat(parts, "\n")
end

-- применить XML из saveLayout; окна находятся по заголовку среди корней
function screens.loadLayout(xml)
    if type(xml) ~= "string" then return false end
    local applied = false
    local byTitle = {}
    local roots = DXUI.frame.roots()
    for i = 1, #roots do
        local inod = rawget(roots[i], "_")
        if inod and inod.widgetType == "Window" then
            byTitle[tostring(inod.data.title)] = roots[i]
        end
    end
    for attrs in xml:gmatch("<window%s+(.-)/>") do
        local t = {}
        for k, v in attrs:gmatch('(%w+)="(.-)"') do
            t[k] = v
        end
        local win = byTitle[t.title]
        if win then
            if t.x then win.x = tonumber(t.x) end
            if t.y then win.y = tonumber(t.y) end
            if t.width then win.width = tonumber(t.width) end
            if t.height then win.height = tonumber(t.height) end
            applied = true
        end
    end
    local theme = {}
    for name, value in xml:gmatch('<color%s+name="(.-)"%s+value="(.-)"%s*/>') do
        local n = tonumber(value)
        if n then
            theme[name] = n
        end
    end
    if next(theme) then
        DXUI.theme.apply(theme)
        applied = true
    end
    return applied
end

if _G.DXUI == nil then _G.DXUI = {} end
DXUI.screens = screens
return screens
