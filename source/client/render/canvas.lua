-- render/canvas.lua — command buffer кадра (task.md §3.6)
-- Пишется сценой (widgets/render pass), исполняется бэкендом.
--
-- Контракт:
--   * canvas.new() -> canvas
--   * canvas:rect(x, y, w, h, color, opts?)   opts = { radius = n }
--   * canvas:text(str, x, y, opts)            opts = { font = f, color = c,
--                                             alignX = "left"|"center"|"right",
--                                             alignY = "top"|"center"|"bottom" }
--                                             (x, y) — якорная точка текста:
--                                             для alignX="center" это центр по X
--                                             (текст рисуется вокруг неё)
--   * canvas:image(tex, x, y, w, h, opts?)    opts = { rotate = r, slice = {l,t,r,b} }
--   * canvas:clip(x, y, w, h) | canvas:clip() — push/pop клип-региона
--   * canvas:clear() — сброс буфера (команды возвращаются в пул)
--   * canvas:drain(backend) — исполнить все команды через бэкенд
--
-- Zero allocations steady-state: команды — пул таблиц, поля плоские.
-- Цвет — упакованное число (парсинг один раз при установке свойства, §3.2).

local setmetatable = setmetatable
local type = type

local Canvas = {}
Canvas.__index = Canvas

-- типы команд (числа — не строки: в горячем пути нет конкатенаций)
local CMD_RECT, CMD_TEXT, CMD_IMAGE, CMD_CLIP_PUSH, CMD_CLIP_POP =
      1, 2, 3, 4, 5

local function new()
    return setmetatable({
        cmds = {}, -- буфер команд; длину задаёт cmdCount
        cmdCount = 0,
        pool = {}, -- свободные команды
        poolCount = 0,
    }, Canvas)
end

-- берёт команду из пула или аллоцирует новую
local function acquire(self)
    local poolCount = self.poolCount
    if poolCount > 0 then
        local cmd = self.pool[poolCount]
        self.poolCount = poolCount - 1
        return cmd
    end
    return {}
end

local function push(self, cmd)
    self.cmdCount = self.cmdCount + 1
    self.cmds[self.cmdCount] = cmd
end

function Canvas:rect(x, y, w, h, color, opts)
    local cmd = acquire(self)
    cmd.kind = CMD_RECT
    cmd.x, cmd.y, cmd.w, cmd.h = x, y, w, h
    cmd.color = color
    cmd.radius = (opts and opts.radius) or nil
    cmd.font = nil
    cmd.str = nil
    cmd.tex = nil
    cmd.slice = nil
    cmd.rotate = nil
    cmd.alignX = nil
    cmd.alignY = nil
    push(self, cmd)
end

function Canvas:text(str, x, y, opts)
    local cmd = acquire(self)
    cmd.kind = CMD_TEXT
    cmd.str = str
    cmd.x, cmd.y = x, y
    cmd.font = opts and opts.font or nil
    cmd.color = opts and opts.color or nil
    cmd.alignX = opts and opts.alignX or nil
    cmd.alignY = opts and opts.alignY or nil
    cmd.w, cmd.h = nil, nil
    cmd.tex = nil
    cmd.radius = nil
    cmd.slice = nil
    cmd.rotate = nil
    push(self, cmd)
end

function Canvas:image(tex, x, y, w, h, opts)
    local cmd = acquire(self)
    cmd.kind = CMD_IMAGE
    cmd.tex = tex
    cmd.x, cmd.y, cmd.w, cmd.h = x, y, w, h
    cmd.rotate = (opts and opts.rotate) or nil
    cmd.slice = (opts and opts.slice) or nil
    cmd.color = nil
    cmd.radius = nil
    cmd.font = nil
    cmd.str = nil
    cmd.alignX = nil
    cmd.alignY = nil
    push(self, cmd)
end

function Canvas:clip(x, y, w, h)
    local cmd = acquire(self)
    if x == nil then
        cmd.kind = CMD_CLIP_POP
    else
        cmd.kind = CMD_CLIP_PUSH
        cmd.x, cmd.y, cmd.w, cmd.h = x, y, w, h
    end
    cmd.str = nil
    cmd.tex = nil
    cmd.color = nil
    cmd.radius = nil
    cmd.font = nil
    cmd.slice = nil
    cmd.rotate = nil
    cmd.alignX = nil
    cmd.alignY = nil
    push(self, cmd)
end

-- сброс буфера; команды возвращаются в пул
function Canvas:clear()
    local cmds = self.cmds
    local n = self.cmdCount
    if n == 0 then return end
    local pool = self.pool
    for i = 1, n do
        local cmd = cmds[i]
        -- освобождаем ссылки на пользовательские объекты
        cmd.str = nil
        cmd.tex = nil
        cmd.slice = nil
        cmd.alignX = nil
        cmd.alignY = nil
        pool[self.poolCount + i] = cmd
    end
    self.poolCount = self.poolCount + n
    self.cmdCount = 0
end

-- исполнение через бэкенд; после drain буфер чист
function Canvas:drain(backend)
    local n = self.cmdCount
    if n == 0 then return 0 end
    local cmds = self.cmds
    local pool = self.pool
    for i = 1, n do
        local cmd = cmds[i]
        local kind = cmd.kind
        if kind == CMD_RECT then
            backend:rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.color, cmd.radius)
        elseif kind == CMD_TEXT then
            backend:text(cmd.str, cmd.x, cmd.y, cmd.font, cmd.color, cmd.alignX, cmd.alignY)
        elseif kind == CMD_IMAGE then
            backend:image(cmd.tex, cmd.x, cmd.y, cmd.w, cmd.h, cmd.rotate, cmd.slice)
        elseif kind == CMD_CLIP_PUSH then
            backend:clipPush(cmd.x, cmd.y, cmd.w, cmd.h)
        else
            backend:clipPop()
        end
        -- возврат в пул сразу: steady-state без clear()
        local poolCount = self.poolCount
        pool[poolCount + 1] = cmd
        self.poolCount = poolCount + 1
    end
    self.cmdCount = 0
    return n
end

-- число команд в буфере (для инспектора/тестов)
function Canvas:getCommandCount()
    return self.cmdCount
end

-- экспорт констант для бэкендов/тестов
local module = {
    new = new,
    CMD_RECT = CMD_RECT,
    CMD_TEXT = CMD_TEXT,
    CMD_IMAGE = CMD_IMAGE,
    CMD_CLIP_PUSH = CMD_CLIP_PUSH,
    CMD_CLIP_POP = CMD_CLIP_POP,
}

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.canvas = module
return module
