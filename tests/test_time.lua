-- tests: core/time.lua

return function(test, pkg)
    local time = pkg("core/time.lua")

    test("default source returns 0", function(t)
        t.eq(time.now(), 0)
    end)

    test("setSource switches clock", function(t)
        local v = 100
        time.setSource(function() return v end)
        t.eq(time.now(), 100)
        v = 200
        t.eq(time.now(), 200)
    end)

    test("setSource rejects non-function", function(t)
        local ok = pcall(time.setSource, 42)
        t.ok(not ok)
    end)

    test("helpers", function(t)
        t.eq(time.seconds(1), 1000)
        t.eq(time.minutes(1), 60000)
    end)
end
