-- anim/tween.lua — твины и таймлайны поверх системы свойств (task.md §5)
--
--   animation.to(panel, 0.25, { x = 300, y = 40 }, { easing = "outQuad" })
--
-- * единый клок: core/time (никаких таймеров в виджетах);
-- * твины пишут через prop.forceSet — конвейер свойств переиспользуется
--   (инвалидация/dirty-списки работают как при прямой записи);
-- * prop.set для свойств с transition = { duration, easing } планирует
--   твин автоматически (см. style/transitions.lua);
-- * retarget: повторная запись свойства твинит от текущего значения.

local rawget = rawget
local pairs = pairs

local tween = {}

local active = {}   -- массив активных твинов
local count = 0     -- #active

local DXUI = _G.DXUI
local prop = DXUI.prop
local easing = DXUI.easing

-- в узле отмечается, какие свойства интерполируются (prop.set не
-- перезапланировывает твин того же свойства)
local function markTweening(node, key, on)
    local inod = rawget(node, "_")
    inod.tweening = inod.tweening or {}
    inod.tweening[key] = on or nil
    if on == nil and next(inod.tweening) == nil then
        inod.tweening = nil
    end
end

local function findActive(node, key)
    for i = 1, count do
        local tw = active[i]
        if tw.node == node and tw.key == key then
            return tw
        end
    end
    return nil
end

-- один твине на свойство узла: retarget от текущего значения
local function schedule(node, key, toValue, duration, easeName, start)
    local DXUIeasing = DXUI.easing
    local ease = (easeName and DXUIeasing[easeName]) or DXUIeasing.outQuad
    local tw = findActive(node, key)
    if tw then
        tw.to = toValue
        tw.ease = ease
        return tw
    end
    count = count + 1
    tw = {
        node = node,
        key = key,
        from = nil,
        to = toValue,
        dur = duration,
        ease = ease,
        start = start or DXUI.time.now(),
        after = nil,
    }
    active[count] = tw
    markTweening(node, key, true)
    return tw
end

-- публичный API: твин группы свойств за duration секунд
-- tween.to(node, duration, props, opts?) -> tween handle
function tween.to(node, duration, props, opts)
    opts = opts or {}
    local handle
    for key, value in pairs(props) do
        local tw = schedule(node, key, value, duration, opts.easing)
        handle = tw
    end
    return handle
end

-- планирование из prop.set (свойство с transition)
function tween.transitionTo(node, key, value, spec)
    local tw = schedule(node, key, value, spec.duration, spec.easing)
    return tw
end

-- одношотовый отложенный вызов (клок — общий)
function tween.after(delay, fn)
    count = count + 1
    local tw = {
        node = nil,
        after = fn,
        start = DXUI.time.now(),
        delay = delay,
        key = nil,
    }
    active[count] = tw
    return tw
end

-- таймлайн: steps = { { to = {...}, dur = n, easing = "..." }, ... }
-- каждый шаг стартует после предыдущего
function tween.timeline(node, steps)
    local i = 0
    local function step()
        i = i + 1
        local s = steps[i]
        if s == nil then return end
        local handle = tween.to(node, s.dur, s.to, { easing = s.easing })
        if handle then
            handle.after = (i < #steps) and step or nil
        end
    end
    step()
end

function tween.activeCount()
    return count
end

function tween.clear()
    for i = 1, count do
        active[i] = nil
    end
    count = 0
end

-- обновление твинеров; вызывается boot.lua каждый кадр
function tween.tick()
    if count == 0 then return 0 end
    local now = DXUI.time.now()
    local forceSet = prop.forceSet
    local n = count      -- граница на входе: твины, запланированные
    local w = 0          -- из after-колбэков, живут в n+1..count
    for i = 1, n do
        local tw = active[i]
        local keep = true
        if tw.key == nil then
            -- отложенный вызов (after)
            if now - tw.start >= tw.delay then
                tw.after()
                keep = false
            end
        else
            local elapsed = now - tw.start
            if elapsed >= tw.dur then
                forceSet(tw.node, tw.key, tw.to)
                markTweening(tw.node, tw.key, nil)
                -- до after: твин больше участвует в retarget-поиске
                tw.node = nil
                if tw.after then tw.after() end
                keep = false
            elseif elapsed >= 0 then
                if tw.from == nil then
                    tw.from = tw.node[tw.key]
                end
                local a = tw.ease(elapsed / tw.dur)
                local v = tw.from + (tw.to - tw.from) * a
                forceSet(tw.node, tw.key, v)
            end
        end
        if keep then
            w = w + 1
            active[w] = tw
        end
    end
    -- новые твины из колбэков (n+1..count) перемещаются за выжившими
    for i = n + 1, count do
        w = w + 1
        active[w] = active[i]
    end
    for i = count, w + 1, -1 do
        active[i] = nil
    end
    count = w
    return w
end

if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.tween = tween
return tween
