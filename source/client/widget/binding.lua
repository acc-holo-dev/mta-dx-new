-- widget/binding.lua — observable/binding (task2.md T21)
--
-- observable(initial) -> { get, set, subscribe } — реактивная ячейка:
-- set с равным значением молчит; подписчики зовутся синхронно, в порядке
-- подписки. subscribe(fn) -> connection:disconnect() — отписка безопасна
-- внутри самого колбэка.
--
-- bind(widget, { prop = observable, ... }) — мост в свойства виджета:
-- применяет начальное значение и дальше пишет widget[prop] на каждый set.
-- Возвращает handle:disconnect() (отписывает все связи). Прямой обратной
-- записи (виджет -> observable) нет: читайте события виджета и зовите set.

local binding = {}

function binding.observable(initial)
    local value = initial
    local subs = {}
    local obs = {}

    function obs.get()
        return value
    end

    function obs.set(v)
        if v == value then return end
        value = v
        -- копия на случай отписки внутри колбэка
        local snapshot = {}
        for i = 1, #subs do
            snapshot[i] = subs[i]
        end
        for i = 1, #snapshot do
            snapshot[i](v)
        end
    end

    function obs.subscribe(fn)
        subs[#subs + 1] = fn
        local alive = true
        local conn = {}
        function conn.disconnect()
            if not alive then return end
            alive = false
            for i = 1, #subs do
                if subs[i] == fn then
                    table.remove(subs, i)
                    return
                end
            end
        end
        return conn
    end

    return obs
end

function binding.bind(widget, map)
    local conns = {}
    for prop, obs in pairs(map) do
        conns[#conns + 1] = obs.subscribe(function(v)
            widget[prop] = v
        end)
        widget[prop] = obs.get()
    end
    local handle = {}
    function handle.disconnect()
        for i = 1, #conns do
            conns[i].disconnect()
        end
    end
    return handle
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.binding = binding
return binding
