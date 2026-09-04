-- tests: core/signal.lua

return function(test, pkg)
    local signal = pkg("core/signal.lua")

    test("connect + fire", function(t)
        local s = signal.new()
        local n = 0
        s:connect(function(v) n = n + v end)
        s:fire(3)
        s:fire(4)
        t.eq(n, 7)
    end)

    test("multiple handlers, all fired", function(t)
        local s = signal.new()
        local acc = {}
        s:connect(function() acc[#acc + 1] = 1 end)
        s:connect(function() acc[#acc + 1] = 2 end)
        s:fire()
        t.eq(#acc, 2)
    end)

    test("disconnect works", function(t)
        local s = signal.new()
        local n = 0
        local c = s:connect(function() n = n + 1 end)
        s:fire()
        c:disconnect()
        s:fire()
        t.eq(n, 1)
        t.ok(not c:isConnected())
    end)

    test("disconnect inside emit does not break traversal (in-order, all fired)", function(t)
        local s = signal.new()
        local acc = {}
        local c1
        c1 = s:connect(function()
            acc[#acc + 1] = "c1"
            c1:disconnect()
        end)
        s:connect(function() acc[#acc + 1] = "c2" end)
        s:fire()
        t.eq(#acc, 2)
        t.eq(acc[1], "c1")
        t.eq(acc[2], "c2")
        t.eq(s:getConnectionCount(), 1)
    end)

    test("once fires exactly once", function(t)
        local s = signal.new()
        local n = 0
        s:connect(function() n = n + 1 end, { once = true })
        s:fire()
        s:fire()
        t.eq(n, 1)
        t.eq(s:getConnectionCount(), 0)
    end)

    test("weak connection survives while handler referenced", function(t)
        local s = signal.new()
        local n = 0
        local function handler() n = n + 1 end
        local c = s:connect(handler, { weak = true })
        s:fire()
        t.eq(n, 1)
        t.ok(c:isConnected())
    end)

    test("weak connection disappears after GC collects handler", function(t)
        local s = signal.new()
        local n = 0
        do
            local h = function() n = n + 1 end
            s:connect(h, { weak = true })
            h = nil
        end
        collectgarbage("collect")
        collectgarbage("collect")
        s:fire()
        t.eq(n, 0)
        t.eq(s:getConnectionCount(), 0)
    end)

    test("prod mode: no pcall overhead path still works", function(t)
        signal.setDevMode(false)
        local s = signal.new()
        local n = 0
        s:connect(function(v) n = v end)
        s:fire(9)
        t.eq(n, 9)
        signal.setDevMode(true)
    end)

    test("dev mode: one crashing handler does not stop the rest", function(t)
        local s = signal.new()
        local second = 0
        local received = nil
        signal.setDevMode(true, function(err) received = tostring(err) end)
        s:connect(function() error("boom") end)
        s:connect(function() second = 1 end)
        pcall(function() s:fire() end)
        t.eq(second, 1)
        t.ok(received ~= nil)
        signal.setDevMode(true)
    end)

    test("disconnectAll", function(t)
        local s = signal.new()
        local n = 0
        s:connect(function() n = n + 1 end)
        s:connect(function() n = n + 1 end)
        s:disconnectAll()
        s:fire()
        t.eq(n, 0)
        t.eq(s:getConnectionCount(), 0)
    end)

    test("stress: 1000 conns, connect/disconnect-in-emit interleave", function(t)
        local s = signal.new()
        local fired = 0
        local conns = {}
        for i = 1, 1000 do
            conns[i] = s:connect(function() fired = fired + 1 end)
        end
        s:fire()
        t.eq(fired, 1000)
        -- массовая отписка + повторный fire
        for i = 1, 1000 do
            if i % 2 == 0 then conns[i]:disconnect() end
        end
        fired = 0
        s:fire()
        t.eq(fired, 500)
    end)
end
