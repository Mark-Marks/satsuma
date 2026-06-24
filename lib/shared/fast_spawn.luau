--!optimize 2
--[[
    https://github.com/ffrostfall/luausignal/blob/84a9672aed30c0e142a14fe3221eece4dda2516f/src/init.luau
    Copyright 2025 ffrostfall

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]
local free_thread: thread? = nil

@native
const function yield_loop()
    while true do
        -- note: this only supports 2 arguments because only at most 2 are used in the satsuma codebase
        -- you can just add more if you need to
        const callback: (...any) -> (), arg1, arg2 = coroutine.yield()
        const ref = free_thread
        free_thread = nil

        callback(arg1, arg2)

        free_thread = ref
    end
end

@native
const function fast_spawn<T..., R...>(callback: (T...) -> R..., ...: T...)
    if not free_thread then
        free_thread = task.spawn(yield_loop)
    end

    task.spawn(free_thread :: thread, ...)
end

return fast_spawn
