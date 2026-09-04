-- tests/run.lua — headless тестовый раннер (Lua 5.1)
-- Запуск: .debug/lua51/lua.exe tests/run.lua

local ROOT = (arg and arg[0] and arg[0]:match("^(.*)[/\\]") or ".") .. "/.."
ROOT = ROOT:gsub("\\", "/")
if ROOT == "" then ROOT = ".." end

local passed, failed = 0, 0
local currentFile = nil
local currentName = nil

local function onFail(msg)
    local where = (currentFile or "?") .. " :: " .. (currentName or "?")
    io.stderr:write(("FAIL %s\n    %s\n"):format(where, msg))
end

local function eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == "table" then
        for k, v in pairs(a) do
            if not eq(v, b[k]) then return false end
        end
        for k in pairs(b) do
            if a[k] == nil then return false end
        end
        return true
    end
    return a == b
end

local function test(name, fn)
    currentName = name
    local ok, err
    -- изоляция упавшего теста: набор продолжает работать
    local function run()
        fn({
            eq = function(a, b)
                if not eq(a, b) then
                    error(("expected %s, got %s"):format(tostring(b), tostring(a)), 2)
                end
            end,
            ok = function(cond)
                if not cond then error("expected truthy", 2) end
            end,
        })
    end
    if _TEST_NO_ISOLATION then
        run()
        passed = passed + 1
    else
        ok, err = pcall(run)
        if not ok then
            failed = failed + 1
            onFail(tostring(err))
        else
            passed = passed + 1
        end
    end
end

local function pkg(rel)
    local ok, mod = pcall(dofile, ROOT .. "/source/client/" .. rel)
    if not ok then
        io.stderr:write("LOAD ERROR " .. rel .. ": " .. tostring(mod) .. "\n")
        os.exit(1)
    end
    return mod
end

local files = {
    "test_class.lua",
    "test_signal.lua",
    "test_log.lua",
    "test_time.lua",
    "test_pool.lua",
}

for _, f in ipairs(files) do
    currentFile = f
    currentName = nil
    local body, err = loadfile(ROOT .. "/tests/" .. f)
    if not body then
        io.stderr:write("SYNTAX ERROR " .. f .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    local register = body()
    if type(register) ~= "function" then
        io.stderr:write("BAD SHAPE " .. f .. ": expected function(test, pkg)\n")
        os.exit(1)
    end
    register(test, pkg)
end

print(("core: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
