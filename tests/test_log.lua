-- tests: core/log.lua

return function(test, pkg)
    local log = pkg("core/log.lua")

    test("sink receives formatted message", function(t)
        local got = {}
        log.setSink(function(level, cat, msg)
            got = { level, cat, msg }
        end)
        log.setLevel("trace")
        log.info("test", "value=%d", 42)
        t.eq(got[1], "info")
        t.eq(got[2], "test")
        t.eq(got[3], "value=42")
    end)

    test("level threshold filters messages", function(t)
        local count = 0
        log.setSink(function() count = count + 1 end)
        log.setLevel("warn")
        log.debug("cat", "should be dropped")
        t.eq(count, 0)
        log.warn("cat", "should pass")
        t.eq(count, 1)
    end)

    test("no-arg message passes through as-is", function(t)
        local msg = nil
        log.setSink(function(_, _, m) msg = m end)
        log.setLevel("trace")
        log.info("cat", "plain % text")
        t.eq(msg, "plain % text")
    end)

    test("rateLimit caps repeats and resets", function(t)
        log.resetCounters()
        local allowed = 0
        for i = 1, 20 do
            if log.rateLimit("cat", "k", 3) then allowed = allowed + 1 end
        end
        t.eq(allowed, 3)
    end)
end
