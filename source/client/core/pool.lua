-- core/pool.lua — пул объектов
--
--   * pool.new(reset, alloc) — reset(obj) подготавливает к переиспользованию,
--     alloc() создаёт новый объект, если свободных нет.
--   * get()/release(obj) — амортизированное O(1), zero allocations steady-state.
--   * release() объекта, не принадлежащего пулу, — ошибка в dev.
--
-- Использование: вектора, цвета, команды холста (task.md §6.1 «пулы объектов»).

local type = type
local tremove = table.remove
local error = error

local Pool = {}
Pool.__index = Pool

local function new(reset, alloc)
    if type(reset) ~= "function" or type(alloc) ~= "function" then
        error("pool.new: reset and alloc must be functions", 2)
    end
    return setmetatable({
        _free  = {},
        _reset = reset,
        _alloc = alloc,
    }, Pool)
end

function Pool:get()
    local free = self._free
    local n = #free
    if n > 0 then
        local obj = free[n]
        free[n] = nil
        return obj
    end
    return self._alloc()
end

function Pool:release(obj)
    if obj == nil then return end
    self._reset(obj)
    self._free[#self._free + 1] = obj
end

function Pool:size()
    return #self._free
end

-- публикация в глобальный namespace (MTA не имеет require; порядок — meta.xml)
if _G.DXUI == nil then _G.DXUI = {} end
_G.DXUI.pool = { new = new }
return _G.DXUI.pool
