-- tests: core/pool.lua

return function(test, pkg)
    local pool = pkg("core/pool.lua")

    test("alloc when empty, reuse after release", function(t)
        local allocs = 0
        local p = pool.new(
            function(o) o.dirty = nil end,
            function() allocs = allocs + 1; return { id = allocs } end
        )
        local a = p:get()
        a.dirty = true
        t.eq(a.id, 1)
        p:release(a)
        local b = p:get()
        t.eq(b.id, 1) -- тот же объект
        t.eq(b.dirty, nil) -- сброшен
        t.eq(allocs, 1)
        local c = p:get()
        t.eq(c.id, 2)
        t.eq(allocs, 2)
    end)

    test("size reports free count", function(t)
        local p = pool.new(function() end, function() return {} end)
        local objs = {}
        for i = 1, 3 do objs[i] = p:get() end
        t.eq(p:size(), 0)
        for i = 1, 3 do p:release(objs[i]) end
        t.eq(p:size(), 3)
    end)

    test("release(nil) is a no-op", function(t)
        local p = pool.new(function() end, function() return {} end)
        p:release(nil)
        t.eq(p:size(), 0)
    end)

    test("new validates args", function(t)
        t.ok(not pcall(pool.new, nil, function() end))
        t.ok(not pcall(pool.new, function() end, "x"))
    end)
end
