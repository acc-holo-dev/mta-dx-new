-- tests: core/class.lua

return function(test, pkg)
    local class = pkg("core/class.lua")

    test("define + new + call-constructor", function(t)
        local A = class.define("A")
        function A:__init(v) self.v = v end
        local a1 = A.new(5)
        t.eq(a1.v, 5)
        local a2 = A(7)
        t.eq(a2.v, 7)
    end)

    test("inheritance: super method visible", function(t)
        local A = class.define("A")
        function A:get() return "a" end
        local B = class.define("B", A)
        function B:get()
            -- собственный override
            return "b" .. A.get(self)
        end
        local b = B.new()
        t.eq(b:get(), "ba")
    end)

    test("isinstance walks __super chain", function(t)
        local A = class.define("A")
        local B = class.define("B", A)
        local C = class.define("C", B)
        local c = C.new()
        t.ok(class.isinstance(c, C))
        t.ok(class.isinstance(c, B))
        t.ok(class.isinstance(c, A))
        t.ok(not class.isinstance(A.new(), C))
    end)

    test("instance state is isolated", function(t)
        local A = class.define("A")
        function A:__init() self.list = {} end
        local a, b = A.new(), A.new()
        table.insert(a.list, 1)
        t.eq(#b.list, 0)
    end)
end
