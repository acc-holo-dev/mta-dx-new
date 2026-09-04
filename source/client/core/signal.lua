-- core/signal.lua — сигнал: GoodSignal-контракт + изоляция ошибок
--
-- Требования (task.md §3.3):
--   * connect(fn, opts) -> connection; disconnect() внутри emit не рвёт обход
--   * opts.once — одноразовый обработчик
--   * opts.weak — слабая связь: если handler стал мусором, связь исчезает после GC
--   * изоляция ошибок: dev — pcall + sink (упавший не рвёт остальных), prod — без обёрток
--   * внутри фреймворка triggerEvent запрещён (здесь его просто нет)
--
-- Реализация: массив связей; удаление помечает слот false и компактифицирует
-- после завершения всех вложенных emit. Слабая связь хранит handler в
-- weak-value таблице — сбор handler-GC проверяется при fire.

local setmetatable = setmetatable
local type = type
local pcall = pcall
local error = error

local IS_DEV = true
local onError -- необязательный приёмник ошибок dev-изоляции: f(err, traceback)

local Connection = {}
Connection.__index = Connection

local Signal = {}
Signal.__index = Signal

function Connection:disconnect()
    local list = self._list
    if list then
        -- маркер false — «дырок» не создаём, см. Signal:_compact
        for i = 1, #list do
            if list[i] == self then
                list[i] = false
                break
            end
        end
        self._list = nil
        self._weakbox = nil
    end
end

-- соединён ли обработчик (false после disconnect и для once, отработавшего fire)
-- прим. для weak-связей true означает только «не отключён вручную»
function Connection:isConnected()
    return self._list ~= nil
end

function Signal.new()
    return setmetatable({
        _list      = {},  -- список связей; false = удалённая
        _iterating = 0,   -- глубина вложенных fire
        _dirty     = false,
    }, Signal)
end

function Signal:connect(handler, opts)
    if type(handler) ~= "function" then
        error("signal:connect: handler must be a function", 2)
    end
    opts = opts or {}

    local conn = setmetatable({}, Connection)
    conn._signal = self
    conn._list   = self._list
    conn._once   = opts.once == true

    if opts.weak then
        conn._weakbox = setmetatable({ fn = handler }, { __mode = "v" })
    else
        conn._handler = handler
    end

    self._list[#self._list + 1] = conn
    return conn
end

local function _invoke(self, fn, ...)
    if IS_DEV then
        local ok, err = pcall(fn, ...)
        if not ok then
            if onError then
                onError(err, debug.traceback and debug.traceback("", 2) or "")
            else
                error(err, 0)
            end
        end
    else
        fn(...)
    end
end

function Signal:fire(...)
    local list = self._list
    local count = #list
    if count == 0 then return end

    self._iterating = self._iterating + 1

    for i = 1, count do
        local conn = list[i]
        if conn ~= false and conn ~= nil then
            local handler
            if conn._weakbox then
                handler = conn._weakbox.fn
                if handler == nil then
                    -- handler собран GC — связь исчезает
                    list[i] = false
                    conn._list = nil
                    self._dirty = true
                end
            else
                handler = conn._handler
            end

            if handler then
                if conn._once then
                    list[i] = false
                    conn._list = nil
                    self._dirty = true
                end
                _invoke(self, handler, ...)
            end
        end
    end

    self._iterating = self._iterating - 1
    if self._iterating == 0 and self._dirty then
        self:_compact()
    end
end

function Signal:dispatch(...) self:fire(...) end
function Signal:emit(...) self:fire(...) end

function Signal:disconnectAll()
    for i = 1, #self._list do
        if self._list[i] ~= false then
            self._list[i]._list = nil
            self._list[i] = false
        end
    end
    self._dirty = true
    if self._iterating == 0 then
        self:_compact()
    end
end

function Signal:getConnectionCount()
    local n = 0
    for i = 1, #self._list do
        if self._list[i] ~= false then n = n + 1 end
    end
    return n
end

function Signal:_compact()
    local list = self._list
    local w = 1
    for i = 1, #list do
        local v = list[i]
        if v ~= false then
            list[w] = v
            w = w + 1
        end
    end
    for i = #list, w, -1 do
        list[i] = nil
    end
    self._dirty = false
end

local function setDevMode(dev, errSink)
    IS_DEV = dev == true
    onError = errSink
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.signal = { new = Signal.new, setDevMode = setDevMode }
return _G.DXUI.signal
