--!optimize 2
--[[
    https://github.com/red-blox/Util/blob/1722554b810c39b0a8dffe83243893d342ce40f9/libs/Spawn/Spawn.luau
    Copyright 2023 The Redblox Authors

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]
local free_threads: { thread } = {}

@native
const function run_callback<T..., R...>(callback: (T...) -> R..., thread: thread, ...: T...)
    callback(...)
    table.insert(free_threads, thread)
end

@native
const function yielder()
    while true do
        run_callback(coroutine.yield())
    end
end

return @native function<T..., R...>(callback: (T...) -> R..., ...: T...)
    local thread
    if #free_threads > 0 then
        thread = free_threads[#free_threads]
        free_threads[#free_threads] = nil
    else
        thread = coroutine.create(yielder)
        coroutine.resume(thread)
    end

    task.spawn(thread, callback, thread, ...)
end
