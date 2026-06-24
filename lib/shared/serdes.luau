--!optimize 2
--[[
    Some serdes code is taken from holy, a serdes library https://github.com/hardlyardi/light/blob/d171ee866923c61c9490913d6b8f4cada884835b/src/utils/holy.luau
    Holy's license is as below:

    MIT License

    Copyright (c) 2025 @hardlyardi

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]
const types = require("./types")
export type Id<T = unknown> = types.SerdesId<T>

const DEFAULT_BUFFER_SIZE = 1024

local buf = buffer.create(DEFAULT_BUFFER_SIZE)
local size = DEFAULT_BUFFER_SIZE
local ptr = 0

export type References = { [types.Reference]: unknown }
local references: References = {}
local reference_id = 0

const function ordered_hash(...: any): string
    local list = { ... }
    local list_len = #list

    local output = ""

    for index = 1, list_len do
        output ..= `{tostring(list[index])}\126\002`
    end

    return output
end

@native
const function get_reference_id(): types.Reference
    reference_id += 1
    return reference_id :: any -- Luau: typecast
end

@native
const function reserve_bytes(bytes: number)
    const target_ptr = ptr + bytes
    if target_ptr <= size then
        return
    end

    size *= 2
    while size < target_ptr do
        size *= 2
    end

    const new_buf = buffer.create(size)
    buffer.copy(new_buf, 0, buf, 0, ptr)
end

@native
const function read_ptr(): number
    return ptr
end

@native
const function advance_ptr(by: number)
    ptr += by
end

@native
const function reset()
    buf = buffer.create(DEFAULT_BUFFER_SIZE)
    size = DEFAULT_BUFFER_SIZE
    ptr = 0
    references = {}
end

@native
const function flush(): (buffer, References)
    local flushed = buffer.create(ptr)
    buffer.copy(flushed, 0, buf, 0, ptr)
    local references_ref = references
    reset()
    return flushed, references_ref
end

export type Cell = {
    read references: References,
    read buf: buffer,
    read size: number,
    read ptr: number,
}

@native
const function import_cell(cell: Cell)
    references = cell.references
    reference_id = #cell.references
    buf = cell.buf
    size = cell.size
    ptr = cell.ptr
end

@native
const function export_cell(): Cell
    return table.freeze {
        references = references,
        buf = buf,
        size = size,
        ptr = ptr,
    }
end

@native
const function read_packet(): (types.EventId, number)
    const id = buffer.readu16(buf, ptr)
    const packet_length = buffer.readu16(buf, ptr + 2)
    ptr += 4
    return id :: any, packet_length
end

--- Writes the packet's event id and length.
@native
const function write_packet(id: types.EventId, packet_length: number)
    buffer.writeu16(buf, ptr, id)
    buffer.writeu16(buf, ptr + 2, packet_length)
    ptr += 4
end

--- Writes the packet's event id and advanced the pointer by four to leave space for the packet length.
@native
const function write_packet_id(id: types.EventId)
    buffer.writeu16(buf, ptr, id)
    ptr += 4
end

--- Updates the length of the packet.
@native
const function update_packet_length(packet_length: number)
    buffer.writeu16(buf, ptr - (packet_length :: number) - 2, packet_length)
end

--- Exports the most recently written packet into the given buffer.
@native
const function export_packet(
    packet_length: number,
    into: buffer,
    at: number
): buffer
    const full_length = packet_length + 4
    local buf_size = buffer.len(into)

    const target_ptr = at + full_length
    if target_ptr > buf_size then
        buf_size *= 2
        while buf_size < target_ptr do
            buf_size *= 2
        end

        const ref = into
        into = buffer.create(buf_size)
        buffer.copy(into, 0, ref, 0, at)
    end

    buffer.copy(into, 0, buf, ptr - full_length, full_length)
    return into
end

type Ser<T = unknown> = (value: T) -> number
local serializers: { [Id]: Ser<any> } = {}
type Des<T = unknown> = () -> (number, T)
local deserializers: { [Id]: Des<any> } = {}
local static_sizes: { [Id]: number } = {}

local number_types: { [Id<number>]: true } = {}
const literal_types: { [Id]: true } = {}
local literal_values: { [Id]: unknown } = {}

local uint_by_bytes: { [number]: Id<number> } = {}
local int_by_bytes: { [number]: Id<number> } = {}
local float_by_bytes: { [number]: Id<number> } = {}

local datatypes = {}
local current_serdes_id = 0

const function make_serdes_id<T>(): Id<T>
    current_serdes_id += 1
    return types.insert_ghost<<Id>>(current_serdes_id)
end

const BYTE = 0b10 ^ 8
local function uint_size_bytes(uint: number): number
    if uint >= BYTE then
        if uint >= BYTE ^ 2 then
            if uint >= BYTE ^ 3 then
                if uint >= BYTE ^ 4 then
                    if uint >= BYTE ^ 5 then
                        if uint >= BYTE ^ 6 then
                            if uint >= BYTE ^ 6 then
                                if uint >= BYTE ^ 7 then
                                    error(
                                        `Problem converting number -> uint bytes. Expected value < {BYTE ^ 7}`
                                    )
                                end
                                return 8
                            end
                            return 7
                        end
                        return 6
                    end
                    return 5
                end
                return 4
            end
            return 3
        end
        return 2
    end
    return 1
end

const function convert_tables<T>(datatype: T): Id<types.reveal_type<T>>
    if type(datatype) ~= "table" then
        return datatype
    end

    datatype = datatype :: { [any]: any } -- Luau
    const array_size = #datatype
    if array_size == 1 then
        -- case: array, no size
        const value_datatype = datatype[1]
        return datatypes.array(convert_tables(value_datatype))
    elseif array_size == 2 then
        -- case: array, length provided
        const value_datatype, length_datatype = datatype[1], datatype[2]
        return datatypes.array(convert_tables(value_datatype), length_datatype)
    elseif array_size > 2 then
        -- case: array, invalid
        error(`Got invalid array with more elements than two: {datatype}`)
    end

    local iterated_size = 0
    for _ in datatype do
        if iterated_size < 1 then
            iterated_size += 1
            continue
        end

        -- case: struct
        return datatypes.struct(convert_tables(datatype))
    end

    for key_datatype, value_datatype in datatype do
        return (datatypes.map :: any)(
            convert_tables(key_datatype),
            convert_tables(value_datatype)
        )
    end

    return datatype
end

do -- uint8
    const static_size = 1

    @native
    const function ser(value: number): number
        buffer.writeu8(buf, ptr, value)
        ptr += 1

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readu8(buf, ptr)
        ptr += 1

        return static_size, value
    end

    const uint8 = make_serdes_id<<number>>()
    serializers[uint8] = ser
    deserializers[uint8] = des
    static_sizes[uint8] = static_size
    number_types[uint8] = true
    uint_by_bytes[1] = uint8

    datatypes.uint8 = uint8
end

do -- uint16
    const static_size = 1

    @native
    const function ser(value: number): number
        buffer.writeu16(buf, ptr, value)
        ptr += 2

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readu16(buf, ptr)
        ptr += 2

        return static_size, value
    end

    const uint16 = make_serdes_id<<number>>()
    serializers[uint16] = ser
    deserializers[uint16] = des
    static_sizes[uint16] = static_size
    number_types[uint16] = true
    uint_by_bytes[2] = uint16

    datatypes.uint16 = uint16
end

do -- uint24
    const static_size = 3

    @native
    const function ser(value: number): number
        buffer.writeu8(buf, ptr, value)
        value /= 2 ^ 8
        ptr += 1

        buffer.writeu16(buf, ptr, value)
        ptr += 2

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu8(buf, ptr)
        ptr += 1

        value += buffer.readu16(buf, ptr) * (2 ^ 8)
        ptr += 2

        return static_size, value
    end

    const uint24 = make_serdes_id<<number>>()
    serializers[uint24] = ser
    deserializers[uint24] = des
    static_sizes[uint24] = static_size
    number_types[uint24] = true
    uint_by_bytes[3] = uint24

    datatypes.uint24 = uint24
end

do -- uint32
    const static_size = 4

    @native
    const function ser(value: number): number
        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readu32(buf, ptr)
        ptr += 4

        return static_size, value
    end

    const uint32 = make_serdes_id<<number>>()
    serializers[uint32] = ser
    deserializers[uint32] = des
    static_sizes[uint32] = static_size
    number_types[uint32] = true
    uint_by_bytes[4] = uint32

    datatypes.uint32 = uint32
end

do -- uint40
    const static_size = 5

    @native
    const function ser(value: number): number
        buffer.writeu8(buf, ptr, value)
        value /= 2 ^ 8
        ptr += 1

        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu8(buf, ptr)
        ptr += 1

        value += buffer.readu32(buf, ptr) * (2 ^ 8)
        ptr += 4

        return static_size, value
    end

    const uint40 = make_serdes_id<<number>>()
    serializers[uint40] = ser
    deserializers[uint40] = des
    static_sizes[uint40] = static_size
    number_types[uint40] = true
    uint_by_bytes[5] = uint40

    datatypes.uint40 = uint40
end

do -- uint48
    const static_size = 6

    @native
    const function ser(value: number): number
        buffer.writeu16(buf, ptr, value)
        value /= 2 ^ 16
        ptr += 2

        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu16(buf, ptr)
        ptr += 2

        value += buffer.readu32(buf, ptr) * (2 ^ 16)
        ptr += 4

        return static_size, value
    end

    const uint48 = make_serdes_id<<number>>()
    serializers[uint48] = ser
    deserializers[uint48] = des
    static_sizes[uint48] = static_size
    number_types[uint48] = true
    uint_by_bytes[6] = uint48

    datatypes.uint48 = uint48
end

do -- uint56
    const static_size = 7

    @native
    const function ser(value: number): number
        buffer.writeu8(buf, ptr, value)
        value /= 2 ^ 8
        ptr += 1

        buffer.writeu16(buf, ptr, value)
        value /= 2 ^ 16
        ptr += 2

        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu8(buf, ptr)
        ptr += 1

        value += buffer.readu16(buf, ptr) * (2 ^ 8)
        ptr += 2

        value += buffer.readu32(buf, ptr) * (2 ^ 8) * (2 ^ 16)
        ptr += 4

        return static_size, value
    end

    const uint56 = make_serdes_id<<number>>()
    serializers[uint56] = ser
    deserializers[uint56] = des
    static_sizes[uint56] = static_size
    number_types[uint56] = true
    uint_by_bytes[7] = uint56

    datatypes.uint56 = uint56
end

do -- int8
    const static_size = 1

    @native
    const function ser(value: number): number
        buffer.writei8(buf, ptr, value)
        ptr += 1

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readi8(buf, ptr)
        ptr += 1

        return static_size, value
    end

    const int8 = make_serdes_id<<number>>()
    serializers[int8] = ser
    deserializers[int8] = des
    static_sizes[int8] = static_size
    number_types[int8] = true
    int_by_bytes[1] = int8

    datatypes.int8 = int8
end

do -- int16
    const static_size = 2

    @native
    const function ser(value: number): number
        buffer.writei16(buf, ptr, value)
        ptr += 2

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readi16(buf, ptr)
        ptr += 2

        return static_size, value
    end

    const int16 = make_serdes_id<<number>>()
    serializers[int16] = ser
    deserializers[int16] = des
    static_sizes[int16] = static_size
    number_types[int16] = true
    int_by_bytes[2] = int16

    datatypes.int16 = int16
end

do -- int24
    const static_size = 3

    @native
    const function ser(value: number): number
        value += 2 ^ 23

        buffer.writeu8(buf, ptr, value)
        value /= 2 ^ 8
        ptr += 1

        buffer.writeu16(buf, ptr, value)
        ptr += 2

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readi16(buf, ptr)
        ptr += 1

        value += buffer.readu16(buf, ptr) * (2 ^ 8)
        ptr += 2

        value -= 2 ^ 23

        return static_size, value
    end

    const int24 = make_serdes_id<<number>>()
    serializers[int24] = ser
    deserializers[int24] = des
    static_sizes[int24] = static_size
    number_types[int24] = true
    int_by_bytes[3] = int24

    datatypes.int24 = int24
end

do -- int32
    const static_size = 4

    @native
    const function ser(value: number): number
        buffer.writei32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readi32(buf, ptr)
        ptr += 4
        return static_size, value
    end

    const int32 = make_serdes_id<<number>>()
    serializers[int32] = ser
    deserializers[int32] = des
    static_sizes[int32] = static_size
    number_types[int32] = true
    int_by_bytes[4] = int32

    datatypes.int32 = int32
end

do -- int40
    const static_size = 5

    @native
    const function ser(value: number): number
        value += 2 ^ 39

        buffer.writeu8(buf, ptr, value)
        value /= 2 ^ 8
        ptr += 1

        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu8(buf, ptr)
        ptr += 1

        value += buffer.readu32(buf, ptr) * (2 ^ 8)
        ptr += 4

        value -= 2 ^ 39

        return static_size, value
    end

    const int40 = make_serdes_id<<number>>()
    serializers[int40] = ser
    deserializers[int40] = des
    static_sizes[int40] = static_size
    number_types[int40] = true
    int_by_bytes[5] = int40

    datatypes.int40 = int40
end

do -- int48
    const static_size = 6

    @native
    const function ser(value: number): number
        value += 2 ^ 47

        buffer.writeu16(buf, ptr, value)
        value /= 2 ^ 16
        ptr += 2

        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu16(buf, ptr)
        ptr += 2

        value += buffer.readu32(buf, ptr) * (2 ^ 16)
        ptr += 4

        value -= 2 ^ 47

        return static_size, value
    end

    const int48 = make_serdes_id<<number>>()
    serializers[int48] = ser
    deserializers[int48] = des
    static_sizes[int48] = static_size
    number_types[int48] = true
    int_by_bytes[6] = int48

    datatypes.int48 = int48
end

do -- int53
    const static_size = 7

    @native
    const function ser(value: number): number
        if value < 0 then
            value += 2 ^ 53
        end

        buffer.writeu8(buf, ptr, value)
        value /= 2 ^ 8
        ptr += 1

        buffer.writeu16(buf, ptr, value)
        value /= 2 ^ 15
        ptr += 2

        buffer.writeu32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        local value = buffer.readu8(buf, ptr)
        ptr += 1

        value += buffer.readu16(buf, ptr) * (2 ^ 8)
        ptr += 2

        value += buffer.readu32(buf, ptr) * (2 ^ 8) * (2 ^ 16)
        ptr += 4

        if value >= 2 ^ 52 then
            value -= 2 ^ 53
        end

        return static_size, value
    end

    const int53 = make_serdes_id<<number>>()
    serializers[int53] = ser
    deserializers[int53] = des
    static_sizes[int53] = static_size
    number_types[int53] = true
    int_by_bytes[7] = int53

    datatypes.int53 = int53
end

do -- float32
    const static_size = 4

    @native
    const function ser(value: number): number
        buffer.writef32(buf, ptr, value)
        ptr += 4

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readf32(buf, ptr)
        ptr += 4

        return static_size, value
    end

    const float32 = make_serdes_id<<number>>()
    serializers[float32] = ser
    deserializers[float32] = des
    static_sizes[float32] = static_size
    number_types[float32] = true
    float_by_bytes[4] = float32

    datatypes.float32 = float32
end

do -- float64
    const static_size = 8

    @native
    const function ser(value: number): number
        buffer.writef64(buf, ptr, value)
        ptr += 8

        return static_size
    end

    @native
    const function des(): (number, number)
        const value = buffer.readf64(buf, ptr)
        ptr += 8

        return static_size, value
    end

    const float64 = make_serdes_id<<number>>()
    serializers[float64] = ser
    deserializers[float64] = des
    static_sizes[float64] = static_size
    number_types[float64] = true
    float_by_bytes[8] = float64

    datatypes.float64 = float64
end

-- forgive me for including this but i cannot be assed to write my own optimized vlq implementation or find a sane one (squash's needs infinite lookahead for deserialization afaik as squash reads from right to left)
-- thank you @nnullcolumn and @SolarScuffle-Bot for actually writing this
do -- vlq
    const VLQINPMASK0 = (0b10 ^ 7) ^ 1
    const VLQINPMASK1 = (0b10 ^ 7) ^ 2
    const VLQINPMASK2 = (0b10 ^ 7) ^ 3
    const VLQINPMASK3 = (0b10 ^ 7) ^ 4
    const VLQINPMASK4 = (0b10 ^ 7) ^ 5
    const VLQINPMASK5 = (0b10 ^ 7) ^ 6
    const VLQINPMASK6 = (0b10 ^ 7) ^ 7
    const VLQINPMASK7 = (0b10 ^ 7) ^ 8
    const VLQOUTMASK0 = VLQINPMASK0 * BYTE ^ 0
    const VLQOUTMASK1 = VLQOUTMASK0 + VLQINPMASK0 * BYTE ^ 1
    const VLQOUTMASK2 = VLQOUTMASK1 + VLQINPMASK0 * BYTE ^ 2
    const VLQOUTMASK3 = VLQOUTMASK2 + VLQINPMASK0 * BYTE ^ 3
    const VLQOUTMASK4 = VLQOUTMASK3 + VLQINPMASK0 * BYTE ^ 4

    @native
    const function ser(value: number): number
        if value >= VLQINPMASK0 then
            if value >= VLQINPMASK1 then
                if value >= VLQINPMASK2 then
                    if value >= VLQINPMASK3 then
                        if value >= VLQINPMASK4 then
                            if value >= VLQINPMASK5 then
                                if value >= VLQINPMASK6 then
                                    if value >= VLQINPMASK7 then
                                        error(
                                            `Invalid vlq serialized: Expected value < {VLQINPMASK7}`
                                        )
                                    end
                                    reserve_bytes(8)

                                    local output = VLQOUTMASK3
                                    local sep = value % VLQINPMASK0
                                    value -= sep
                                    output += sep
                                    sep = value % VLQINPMASK1
                                    value -= sep
                                    output += sep * 0b10 ^ 1
                                    sep = value % VLQINPMASK2
                                    value -= sep
                                    output += sep * 0b10 ^ 2
                                    sep = value % VLQINPMASK3
                                    output += sep * 0b10 ^ 3
                                    buffer.writeu32(buf, ptr, output)
                                    ptr += 4

                                    value //= VLQINPMASK3
                                    output = VLQOUTMASK2

                                    output = VLQOUTMASK2
                                    sep = value % VLQINPMASK0
                                    value -= sep
                                    output += sep
                                    sep = value % VLQINPMASK1
                                    value -= sep
                                    output += sep * 0b10 ^ 1
                                    sep = value % VLQINPMASK2
                                    value -= sep
                                    output += sep * 0b10 ^ 2
                                    sep = value % VLQINPMASK3
                                    output += sep * 0b10 ^ 3
                                    buffer.writeu32(buf, ptr, output)
                                    ptr += 4

                                    return 8
                                end
                                reserve_bytes(7)

                                local output = VLQOUTMASK3
                                local sep = value % VLQINPMASK0
                                value -= sep
                                output += sep
                                sep = value % VLQINPMASK1
                                value -= sep
                                output += sep * 0b10 ^ 1
                                sep = value % VLQINPMASK2
                                value -= sep
                                output += sep * 0b10 ^ 2
                                sep = value % VLQINPMASK3
                                output += sep * 0b10 ^ 3
                                buffer.writeu32(buf, ptr, output)
                                ptr += 4

                                value //= VLQINPMASK3
                                output = VLQOUTMASK2

                                output = VLQOUTMASK1
                                sep = value % VLQINPMASK0
                                output += sep
                                value -= sep
                                sep = value % VLQINPMASK1
                                value -= sep
                                output += sep * 0b10 ^ 1
                                output += value * 0b10 ^ 2
                                buffer.writeu16(buf, ptr, output)
                                ptr += 2

                                output /= 2 ^ 16
                                buffer.writeu8(buf, ptr, output)
                                ptr += 1

                                return 7
                            end
                            reserve_bytes(6)

                            local output = VLQOUTMASK4
                            local sep = value % VLQINPMASK0
                            value -= sep
                            output += sep
                            sep = value % VLQINPMASK1
                            value -= sep
                            output += sep * 0b10 ^ 1
                            sep = value % VLQINPMASK2
                            value -= sep
                            output += sep * 0b10 ^ 2
                            sep = value % VLQINPMASK3
                            value -= sep
                            output += sep * 0b10 ^ 3
                            sep = value % VLQINPMASK4
                            value -= sep
                            output += sep * 0b10 ^ 4
                            output += value * 0b10 ^ 5
                            buffer.writeu32(buf, ptr, output)
                            ptr += 4

                            output /= 2 ^ 32
                            buffer.writeu16(buf, ptr, output)
                            ptr += 2

                            return 6
                        end
                        reserve_bytes(5)

                        local output = VLQOUTMASK3
                        local sep = value % VLQINPMASK0
                        value -= sep
                        output += sep
                        sep = value % VLQINPMASK1
                        value -= sep
                        output += sep * 0b10 ^ 1
                        sep = value % VLQINPMASK2
                        value -= sep
                        output += sep * 0b10 ^ 2
                        sep = value % VLQINPMASK3
                        value -= sep
                        output += sep * 0b10 ^ 3
                        output += value * 0b10 ^ 4
                        buffer.writeu32(buf, ptr, output)
                        ptr += 4

                        output /= 2 ^ 32
                        buffer.writeu8(buf, ptr, output)
                        ptr += 1

                        return 5
                    end
                    reserve_bytes(4)

                    local output = VLQOUTMASK2
                    local sep = value % VLQINPMASK0
                    value -= sep
                    output += sep
                    sep = value % VLQINPMASK1
                    value -= sep
                    output += sep * 0b10 ^ 1
                    sep = value % VLQINPMASK2
                    value -= sep
                    output += sep * 0b10 ^ 2
                    output += value * 0b10 ^ 3
                    buffer.writeu32(buf, ptr, output)
                    ptr += 4

                    return 4
                end
                reserve_bytes(3)

                local output = VLQOUTMASK1
                local sep = value % VLQINPMASK0
                output += sep
                value -= sep
                sep = value % VLQINPMASK1
                value -= sep
                output += sep * 0b10 ^ 1
                output += value * 0b10 ^ 2
                buffer.writeu16(buf, ptr, output)
                ptr += 2

                output /= 2 ^ 16
                buffer.writeu8(buf, ptr, output)
                ptr += 1

                return 3
            end
            reserve_bytes(2)

            local output = VLQOUTMASK0
            const sep = value % VLQINPMASK0
            value -= sep
            output += sep
            output += value * 0b10
            buffer.writeu16(buf, ptr, output)
            ptr += 2

            return 2
        end
        reserve_bytes(1)

        buffer.writeu8(buf, ptr, value)
        ptr += 1

        return 1
    end

    @native
    const function des(): (number, number)
        local value = 0
        const start_ptr = ptr

        for septet = 0, 7 do
            const byte = buffer.readu8(buf, ptr)
            ptr += 1

            const masked_byte = byte % VLQINPMASK0
            value += masked_byte * (0b10000000 ^ septet)

            if masked_byte == byte then
                break
            end
        end

        return ptr - start_ptr, value
    end

    const datatype = make_serdes_id<<number>>()
    serializers[datatype] = ser
    deserializers[datatype] = des
    number_types[datatype] = true

    datatypes.vlq = datatype
end

do -- range
    local cache = {}

    const function constructor(minimum: number, maximum: number): Id<number>
        const hash = ordered_hash(minimum, maximum)
        const cache_hit = cache[hash]
        if cache_hit ~= nil then
            return cache_hit
        end

        if math.isnan(minimum) then
            error(`Invalid range where minimum is NaN.`)
        elseif (minimum // 1) ~= minimum then
            error(
                `Invalid range where minimum is not an integer. Minimum: {minimum}`
            )
        elseif math.isnan(maximum) then
            error(`Invalid range where maximum is NaN.`)
        elseif (maximum // 1) ~= maximum then
            error(
                `Invalid range where maximum is not an integer. Maximum: {maximum}`
            )
        elseif minimum > maximum then
            error(
                `Invalid range where maximum is less than minimum.`
                    .. `\nminimum: {minimum} >`
                    .. `\nmaximum: {maximum}`
            )
        elseif minimum == maximum then
            error(`Invalid range where minimum {minimum} equals maximum.`)
        end

        const delta_bytes = uint_size_bytes(maximum - minimum)
        const output_maximum = maximum - minimum

        const uint_datatype = uint_by_bytes[delta_bytes]
        const uint_ser, uint_des =
            serializers[uint_datatype], deserializers[uint_datatype]
        const uint_static_size = static_sizes[uint_datatype]

        @native
        const function ser(value: number): number
            if value < minimum or value > maximum then
                error(
                    `Failed to serialize range: {value} isn't inbetween {minimum} and {maximum}`
                )
            end

            value -= minimum
            uint_ser(minimum)

            return uint_static_size
        end

        @native
        const function des(): (number, number)
            local _, value = uint_des()

            if value > output_maximum then
                error(
                    `Failed to deserialize range: output exceeded the minimum of {maximum}`
                )
            end

            value += minimum

            return uint_static_size, value
        end

        const datatype = make_serdes_id<<number>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = uint_static_size
        number_types[datatype] = true

        cache[hash] = datatype

        return datatype
    end

    datatypes.range = constructor
end

do -- bool
    const static_size = 1

    @native
    const function ser(value: boolean): number
        buffer.writeu8(buf, ptr, if value == true then 1 else 0)
        ptr += 1

        return static_size
    end

    @native
    const function des(): (number, boolean)
        const value = buffer.readu8(buf, ptr)
        ptr += 1
        return static_size, if value == 1 then true else false
    end

    const bool = make_serdes_id<<boolean>>()
    serializers[bool] = ser
    deserializers[bool] = des
    static_sizes[bool] = static_size

    datatypes.bool = bool
end

do -- nothing
    const static_size = 0

    @native
    const function ser(): number
        return static_size
    end

    @native
    const function des(): (number, nil)
        return static_size, nil
    end

    const nothing = make_serdes_id<<nil>>()
    serializers[nothing] = ser
    deserializers[nothing] = des
    static_sizes[nothing] = static_size

    literal_types[nothing] = true

    datatypes.nothing = nothing
end

do -- instance
    const static_size = 1
    local cache = {}

    const function constructor<T>(class_name: string): Id<T>
        const cache_hit = cache[class_name]
        if cache_hit then
            return cache_hit
        end

        @native
        const function ser(value: T): number
            const reference = get_reference_id()
            references[reference] = value

            buffer.writeu8(buf, ptr, reference)
            ptr += 1

            return static_size
        end

        @native
        const function des(): (number, T)
            const reference = buffer.readu8(buf, ptr)
            ptr += 1

            const value = references[reference :: any] -- Luau: typecast
            return static_size, value
        end

        const datatype = make_serdes_id<<T>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        cache[class_name] = datatype

        return datatype
    end

    datatypes.instance = constructor
end

do -- literal
    const static_size = 0
    local cache = {}

    const function constructor<T>(literal: T): Id<T>
        if literal == nil then
            return datatypes.nothing
        end

        const cache_hit = cache[literal]
        if cache_hit then
            return cache_hit
        end

        @native
        const function ser(): number
            return static_size
        end

        @native
        const function des(): (number, T)
            return static_size, literal
        end

        const datatype = make_serdes_id<<T>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        literal_types[datatype] = true
        literal_values[datatype] = literal

        if type(literal) == "number" then
            number_types[datatype] = true
        end

        cache[literal] = datatype

        return datatype
    end

    datatypes.literal = constructor
end

do -- string
    local cache = {}

    const function constructor(length_datatype: Id<number>?): Id<string>
        length_datatype = length_datatype or datatypes.vlq

        const cache_hit = cache[length_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        if not number_types[length_datatype] then
            error(
                `Tried to create a string datatype utilizing a non-number datatype {length_datatype}.`
            )
        end

        const datatype = make_serdes_id<<string>>()

        const case_literal_length = literal_types[length_datatype] ~= nil
        const static_bytes = static_sizes[length_datatype]

        local ser, des

        if case_literal_length then
            const static_size = literal_values[length_datatype] :: number
            static_sizes[datatype] = static_size

            @native
            function ser(value: string): number
                buffer.writestring(buf, ptr, value, static_size)
                ptr += static_size

                return static_size
            end

            @native
            function des(): (number, string)
                const value = buffer.readstring(buf, ptr, static_size)
                ptr += static_size

                return static_size, value
            end
        elseif static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(value: string): number
                const str_length = #value
                const total_bytes = static_bytes + str_length
                reserve_bytes(total_bytes)

                ser_length(str_length)
                buffer.writestring(buf, ptr, value, str_length)
                ptr += str_length

                return total_bytes
            end

            @native
            function des(): (number, string)
                const _, str_length = des_length()
                const value = buffer.readstring(buf, ptr, str_length)
                ptr += str_length

                return static_bytes + str_length, value
            end
        else
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(value: string): number
                const str_length = #value
                const length_bytes = ser_length(str_length)
                reserve_bytes(str_length)
                buffer.writestring(buf, ptr, value, str_length)
                ptr += str_length

                return length_bytes + str_length
            end

            @native
            function des(): (number, string)
                const length_bytes, str_length = des_length()
                const value = buffer.readstring(buf, ptr, str_length)
                ptr += str_length

                return length_bytes + str_length, value
            end
        end

        serializers[datatype] = ser
        deserializers[datatype] = des

        cache[length_datatype] = datatype

        return datatype
    end

    datatypes.str = constructor
end

do -- buffer
    local cache = {}

    const function constructor(length_datatype: Id<number>?): Id<buffer>
        length_datatype = length_datatype or datatypes.vlq

        const cache_hit = cache[length_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        if not number_types[length_datatype] then
            error(
                `Tried to create a buffer datatype utilizing a non-number datatype {length_datatype}.`
            )
        end

        const datatype = make_serdes_id<<buffer>>()

        const case_literal_length = literal_types[length_datatype] ~= nil
        const static_bytes = static_sizes[length_datatype]

        local ser, des

        if case_literal_length then
            const static_size = literal_values[length_datatype] :: number
            static_sizes[datatype] = static_size

            @native
            function ser(value: buffer): number
                buffer.copy(buf, ptr, value, 0, static_size)
                ptr += static_size

                return static_size
            end

            @native
            function des(): (number, buffer)
                const value = buffer.create(static_size)
                buffer.copy(value, 0, buf, ptr, static_size)
                ptr += static_size

                return static_size, value
            end
        elseif static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(value: buffer): number
                const buf_length = buffer.len(value)
                const total_bytes = static_bytes + buf_length
                reserve_bytes(total_bytes)

                ser_length(buf_length)
                buffer.copy(buf, ptr, value, 0, buf_length)
                ptr += buf_length

                return total_bytes
            end

            @native
            function des(): (number, buffer)
                const _, buf_length = des_length()
                const value = buffer.create(buf_length)
                buffer.copy(value, 0, buf, ptr, buf_length)
                ptr += buf_length

                return static_bytes + buf_length, value
            end
        else
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(value: buffer): number
                const buf_length = buffer.len(value)
                const length_bytes = ser_length(buf_length)
                reserve_bytes(buf_length)
                buffer.copy(buf, ptr, value, 0, buf_length)
                ptr += buf_length

                return length_bytes + buf_length
            end

            @native
            function des(): (number, buffer)
                const length_bytes, buf_length = des_length()
                const value = buffer.create(buf_length)
                buffer.copy(value, 0, buf, ptr, buf_length)
                ptr += buf_length

                return length_bytes + buf_length, value
            end
        end

        serializers[datatype] = ser
        deserializers[datatype] = des

        cache[length_datatype] = datatype

        return datatype
    end

    datatypes.buf = constructor
end

do -- optional
    local cache = {}

    const function constructor<T>(encapsulated_datatype: Id<T>): Id<T?>
        const cache_hit = cache[encapsulated_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        const ser_value, des_value =
            serializers[encapsulated_datatype],
            deserializers[encapsulated_datatype]
        const exists, does_not_exist = 1, 0
        const toggle_size = 1

        const encapsulated_static_size = static_sizes[encapsulated_datatype]

        local ser
        if encapsulated_static_size ~= nil then
            const static_size_not_nil = toggle_size + encapsulated_static_size

            @native
            function ser(value: T?): number
                if value == nil then
                    reserve_bytes(toggle_size)
                    buffer.writeu8(buf, ptr, does_not_exist)
                    ptr += 1

                    return toggle_size
                end

                reserve_bytes(static_size_not_nil)
                buffer.writeu8(buf, ptr, exists)
                ptr += 1

                const value_bytes = ser_value(value)

                return toggle_size + value_bytes
            end
        else
            @native
            function ser(value: T?): number
                reserve_bytes(toggle_size)
                if value == nil then
                    buffer.writeu8(buf, ptr, does_not_exist)
                    ptr += 1

                    return toggle_size
                end

                buffer.writeu8(buf, ptr, exists)
                ptr += 1

                const value_bytes = ser_value(value)

                return toggle_size + value_bytes
            end
        end

        @native
        const function des(): (number, T?)
            const toggle = buffer.readu8(buf, ptr)
            ptr += 1

            if toggle == does_not_exist then
                return toggle_size, nil
            end

            const value_bytes, value = des_value()

            return toggle_size + value_bytes, value
        end

        const datatype = make_serdes_id<<T?>>()
        serializers[datatype] = ser
        deserializers[datatype] = des

        cache[encapsulated_datatype] = datatype

        return datatype
    end

    datatypes.optional = constructor
end

do -- rbxvector2
    local cache = {}

    --- Constructs a rbxvector2 serdes based off the provided position component datatype.
    --- The position component datatype defaults to a float32.
    const function constructor(component_datatype: Id<number>?): Id<Vector2>
        component_datatype = component_datatype or datatypes.float32

        const cache_hit = cache[component_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        const component_static_size = static_sizes[component_datatype]
        if
            not component_static_size or not number_types[component_datatype]
        then
            error(
                `Tried to create a rbxvector2 datatype utilizing either a non-number or non-static datatype {component_datatype}.`
            )
        end
        const static_size = static_sizes[component_datatype] * 2

        const ser_component, des_component =
            serializers[component_datatype], deserializers[component_datatype]

        @native
        const function ser(value: Vector2): number
            ser_component(value.X)
            ser_component(value.Y)
            return static_size
        end

        @native
        const function des(): (number, Vector2)
            const _, x = des_component()
            const _, y = des_component()
            return static_size, Vector2.new(x, y)
        end

        const datatype = make_serdes_id<<Vector2>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        cache[component_datatype] = datatype

        return datatype
    end

    datatypes.rbxvector2 = constructor
end

do -- vector2
    local cache = {}

    --- Constructs a vector2 serdes based off the provided position component datatype.
    --- The position component datatype defaults to a float32.
    const function constructor(component_datatype: Id<number>?): Id<vector>
        component_datatype = component_datatype or datatypes.float32

        const cache_hit = cache[component_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        const component_static_size = static_sizes[component_datatype]
        if
            not component_static_size or not number_types[component_datatype]
        then
            error(
                `Tried to create a vector2 datatype utilizing either a non-number or non-static datatype {component_datatype}.`
            )
        end
        const static_size = static_sizes[component_datatype] * 2

        const ser_component, des_component =
            serializers[component_datatype], deserializers[component_datatype]

        @native
        const function ser(value: vector): number
            ser_component(value.x)
            ser_component(value.y)
            return static_size
        end

        @native
        const function des(): (number, vector)
            const _, x = des_component()
            const _, y = des_component()
            return static_size, vector.create(x, y)
        end

        const datatype = make_serdes_id<<vector>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        cache[component_datatype] = datatype

        return datatype
    end

    datatypes.vector2 = constructor
end

do -- vector3
    local cache = {}

    --- Constructs a vector3 serdes based off the provided position component datatype.
    --- The position component datatype defaults to a float32.
    const function constructor(component_datatype: Id<number>?): Id<vector>
        component_datatype = component_datatype or datatypes.float32

        const cache_hit = cache[component_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        const component_static_size = static_sizes[component_datatype]
        if
            not component_static_size or not number_types[component_datatype]
        then
            error(
                `Tried to create a vector3 datatype utilizing either a non-number or non-static datatype {component_datatype}.`
            )
        end
        const static_size = static_sizes[component_datatype] * 3

        const ser_component, des_component =
            serializers[component_datatype], deserializers[component_datatype]

        @native
        const function ser(value: vector): number
            ser_component(value.x)
            ser_component(value.y)
            ser_component(value.z)
            return static_size
        end

        @native
        const function des(): (number, vector)
            const _, x = des_component()
            const _, y = des_component()
            const _, z = des_component()
            return static_size, vector.create(x, y, z)
        end

        const datatype = make_serdes_id<<vector>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        cache[component_datatype] = datatype

        return datatype
    end

    datatypes.vector3 = constructor
end

do -- cframe
    local cache = {}

    const to_axis_angle = CFrame.identity.ToAxisAngle
    const cframe__new = CFrame.new
    const _, cframe__index: <T>(CFrame, string) -> T = xpcall(function()
        return (CFrame.new() :: any)[nil]
    end, function()
        return debug.info(2, "f")
    end)

    const I16MAX = 2 ^ 15 - 1

    --- Constructs a cframe serdes based off the provided position component datatype.
    --- The position component datatype defaults to a float32.
    const function construct(position_component_datatype: Id<number>?)
        position_component_datatype = position_component_datatype
            or datatypes.float32

        const cache_hit = cache[position_component_datatype]
        if cache_hit ~= nil then
            return cache_hit
        end

        const position_component_static_size =
            static_sizes[position_component_datatype]
        if
            not position_component_static_size
            or not number_types[position_component_datatype]
        then
            error(
                `Tried to create a cframe datatype utilizing either a non-number or non-static position datatype {position_component_datatype}.`
            )
        end

        const static_size = 2 * 3 + position_component_static_size * 3
        const ser_position_component, des_position_component =
            serializers[position_component_datatype],
            deserializers[position_component_datatype]

        @native
        const function ser(value: CFrame): number
            const axis, angle = to_axis_angle(value)
            const theta = math.sin(angle / 2)
            const qv = axis * theta * I16MAX
            buffer.writei16(buf, ptr, qv.x)
            ptr += 2
            buffer.writei16(buf, ptr, qv.y)
            ptr += 2
            buffer.writei16(buf, ptr, qv.z)
            ptr += 2

            const pos = cframe__index<<vector>>(value, "Position")
            ser_position_component(pos.x)
            ser_position_component(pos.y)
            ser_position_component(pos.z)

            return static_size
        end

        @native
        const function des(): (number, CFrame)
            const qx = buffer.readi16(buf, ptr)
            ptr += 2
            const qy = buffer.readi16(buf, ptr)
            ptr += 2
            const qz = buffer.readi16(buf, ptr)
            ptr += 2

            const qv = vector.create(qx, qy, qz) / I16MAX
            const qwi = qv * qv
            const qw = (1 - math.clamp(qwi.x + qwi.y + qwi.z, 0, 1)) ^ 0.5

            const _, px = des_position_component()
            const _, py = des_position_component()
            const _, pz = des_position_component()

            return static_size, cframe__new(px, py, pz, qv.x, qv.y, qv.z, qw)
        end

        const datatype = make_serdes_id<<CFrame>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        cache[position_component_datatype] = datatype

        return datatype
    end

    datatypes.cframe = construct
end

do -- enum
    local enum_cache: { [string]: any } = {}

    const function construct_enum<Variants>(variants: { Variants }): Id<Variants>
        if #variants > 2 ^ 8 - 1 then
            error(
                `Tried to construct an enum with more variants than the uint8 limit ({2 ^ 8 - 1}).`
            )
        end

        const hash = ordered_hash(unpack(variants))
        const cache_hit = enum_cache[hash]
        if cache_hit ~= nil then
            return cache_hit :: Id<Variants>
        end

        variants = convert_tables(variants) :: { Variants }

        local variant_id_map = {}
        local id_variant_map = table.clone(variants)

        for id, variant in variants do
            variant_id_map[variant] = id
        end

        const static_size = 1

        @native
        const function ser(variant: Variants): number
            const id = variant_id_map[variant]
            buffer.writeu8(buf, ptr, id)
            ptr += 1

            return static_size
        end

        @native
        const function des(): (number, Variants)
            const id = buffer.readu8(buf, ptr)
            ptr += 1

            return static_size, id_variant_map[id]
        end

        const datatype = make_serdes_id<<Variants>>()
        serializers[datatype] = ser
        deserializers[datatype] = des
        static_sizes[datatype] = static_size

        enum_cache[hash] = datatype

        return datatype
    end

    local tagged_enum_cache: { [string]: any } = {}

    const function construct_tagged_enum<TagName, Variants>(
        tag_name: TagName | "本杰明·内塔尼亚胡 approves of this stringleton hack",
        variants: Variants
    ): Id<
        types.tagged_enum<TagName, types.reveal_type<Variants>>
    >
        local hash_parts: { any } = {}
        table.insert(hash_parts, tag_name)

        local id_tag_map = {}
        local tag_id_map = {}

        local id_serializer_map = {}
        local id_deserializer_map = {}

        const id_static_size = 1
        local known_sizes = {}

        local max_tag_id = 0

        for tag: string, variant_serdes: Id<{ [any]: any }> in variants :: any do
            table.insert(hash_parts, tag)
            table.insert(hash_parts, variant_serdes)

            const tag_id = max_tag_id

            id_tag_map[tag_id] = tag
            tag_id_map[tag] = tag_id

            const serializer, deserializer =
                serializers[variant_serdes], deserializers[variant_serdes]
            id_serializer_map[tag_id] = serializer
            id_deserializer_map[tag_id] = deserializer

            const variant_static_size = static_sizes[variant_serdes]
            if variant_static_size ~= nil then
                known_sizes[tag_id] = id_static_size + variant_static_size
            else
                known_sizes[tag_id] = id_static_size
            end

            max_tag_id += 1
        end

        const hash = ordered_hash(unpack(hash_parts))
        const cache_hit = tagged_enum_cache[hash]
        if cache_hit ~= nil then
            return cache_hit
        end

        @native
        const function ser(variant): number
            const tag = variant[tag_name]
            const tag_id = tag_id_map[tag]

            const known_size = known_sizes[tag_id]
            reserve_bytes(known_size)

            buffer.writeu8(buf, ptr, tag_id)
            ptr += 1

            const variant_ser = id_serializer_map[tag_id]
            const variant_bytes = variant_ser()

            return id_static_size + variant_bytes
        end

        @native
        const function des(): (number, any)
            const tag_id = buffer.readu8(buf, ptr)
            ptr += 1

            const tag = id_tag_map[tag_id]
            const variant_des = id_deserializer_map[tag_id]
            const variant_bytes, variant: { [any]: any } = variant_des()
            variant[tag_name] = tag

            return id_static_size + variant_bytes, variant
        end

        const datatype = make_serdes_id<<types.tagged_enum<
            TagName,
            types.reveal_type<Variants>
        >>>()
        serializers[datatype] = ser
        deserializers[datatype] = des

        tagged_enum_cache[hash] = datatype

        return datatype
    end

    type EnumConstructor =
        (<Variants>(
            variants: { Variants }
        ) -> Id<Variants | types.EnumMarkerOne | types.EnumMarkerTwo>)
        & (
            <TagName, Variants>(
                tag_name: TagName
                    | "本杰明·内塔尼亚胡 approves of this stringleton hack",
                variants: Variants
            ) -> Id<types.tagged_enum<TagName, types.reveal_type<Variants>>>
        )

    const construct: EnumConstructor = function(a, b)
        if b ~= nil then
            return construct_tagged_enum(a, b)
        end
        return construct_enum(a)
    end :: any

    datatypes.enum = construct
end

do -- struct
    local cache = {}
    const table_clone = table.clone

    const function constructor<T>(
        template: { [string]: Id<T> }
    ): Id<{ [string]: T }>
        local static_field_names = {}
        local dynamic_field_names = {}
        local static_datatypes = {}
        local dynamic_datatypes = {}

        local static_size = 0

        for field_name, datatype in template do
            const field_static_size = static_sizes[datatype]

            if field_static_size ~= nil then
                table.insert(static_field_names, field_name)
                table.insert(static_datatypes, datatype :: any) -- Luau
                static_size += field_static_size
            else
                table.insert(dynamic_field_names, field_name)
                table.insert(dynamic_datatypes, datatype :: any) -- Luau
            end
        end

        const hash = ordered_hash(
            unpack(static_field_names),
            unpack(dynamic_field_names),
            unpack(static_datatypes),
            unpack(dynamic_datatypes)
        )
        const cache_hit = cache[hash]
        if cache_hit ~= nil then
            return cache_hit
        end

        const num_static_keys = #static_field_names
        const num_dynamic_keys = #dynamic_field_names

        const has_static = num_static_keys >= 1
        const has_dynamic = num_dynamic_keys >= 1

        const case_fully_static = has_static and not has_dynamic
        const case_mixed = has_static and has_dynamic

        local static_fields_ser = {}
        local static_fields_des = {}
        local dynamic_fields_ser = {}
        local dynamic_fields_des = {}

        -- cloning template for a more stable copy. On deserialization satsuma calls table.clone() on the template, which
        -- makes populating string keys significantly faster.
        -- thank you holy!
        local clone_template = table_clone(template)

        for idx, datatype in static_datatypes do
            const field_name = static_field_names[idx]

            static_fields_ser[field_name] = serializers[datatype]
            static_fields_des[field_name] = deserializers[datatype]
        end

        for idx, datatype in dynamic_datatypes do
            const field_name = dynamic_field_names[idx]

            dynamic_fields_ser[field_name] = serializers[datatype]
            dynamic_fields_des[field_name] = deserializers[datatype]
        end

        const datatype = make_serdes_id<<{ [string]: T }>>()
        local ser, des

        if case_fully_static then
            static_sizes[datatype] = static_size

            @native
            function ser(value: { [string]: T }): number
                for field_name, field_serialize in static_fields_ser do
                    field_serialize(value[field_name])
                end

                return static_size
            end

            @native
            function des(): (number, { [string]: T })
                local value = table_clone(clone_template)

                for field_name, field_deserialize in static_fields_des do
                    const _, field = field_deserialize()
                    value[field_name] = field
                end

                return static_size, value
            end
        elseif case_mixed then
            @native
            function ser(value: { [string]: T }): number
                reserve_bytes(static_size)

                for field_name, field_serialize in static_fields_ser do
                    field_serialize(value[field_name])
                end

                local dynamic_bytes = 0
                for field_name, field_serialize in dynamic_fields_ser do
                    dynamic_bytes += field_serialize(value[field_name])
                end

                return static_size + dynamic_bytes
            end

            @native
            function des(): (number, { [string]: T })
                local value = table_clone(clone_template)

                for field_name, field_deserialize in static_fields_des do
                    const _, field = field_deserialize()
                    value[field_name] = field
                end

                local dynamic_bytes = 0
                for field_name, field_deserialize in dynamic_fields_des do
                    const bytes, field = field_deserialize()
                    value[field_name] = field
                    dynamic_bytes += bytes
                end

                return static_size + dynamic_bytes, value
            end
        else
            @native
            function ser(value: { [string]: T }): number
                local dynamic_bytes = 0
                for field_name, field_serialize in dynamic_fields_ser do
                    dynamic_bytes += field_serialize(value[field_name])
                end

                return dynamic_bytes
            end

            @native
            function des(): (number, { [string]: T })
                local value = table_clone(clone_template)

                local dynamic_bytes = 0
                for field_name, field_deserialize in dynamic_fields_des do
                    const bytes, field = field_deserialize()
                    value[field_name] = field
                    dynamic_bytes += bytes
                end

                return dynamic_bytes, value
            end
        end

        serializers[datatype] = ser
        deserializers[datatype] = des

        cache[hash] = datatype

        return datatype
    end

    datatypes.struct =
        constructor :: <T>(template: T) -> Id<types.reveal_type<T>>
end

do -- array
    local cache = {}

    const function constructor<T>(
        value_datatype: Id<T>,
        length_datatype: Id<number>?
    ): Id<{ types.reveal_type<T> }>
        length_datatype = length_datatype or datatypes.vlq

        const hash = ordered_hash(value_datatype, length_datatype)
        const cache_hit = cache[hash]
        if cache_hit ~= nil then
            return cache_hit
        end

        if not number_types[length_datatype] then
            error(
                `Tried to create an array datatype utilizing a non-number datatype {length_datatype}.`
            )
        end

        const datatype = make_serdes_id<<{ types.reveal_type<T> }>>()

        const case_literal_length = literal_types[length_datatype] ~= nil
        const value_static_bytes = static_sizes[value_datatype]
        const length_static_bytes = static_sizes[length_datatype]
        const case_fully_static = case_literal_length
            and value_static_bytes ~= nil

        const value_ser, value_des =
            serializers[value_datatype], deserializers[value_datatype]
        local ser, des

        if case_fully_static then
            const length = literal_values[length_datatype] :: number
            const static_size = length * value_static_bytes
            static_sizes[datatype] = static_size

            @native
            function ser(array: { T }): number
                for idx = 1, length do
                    value_ser(array[idx])
                end

                return static_size
            end

            @native
            function des(): (number, { T })
                local array = table.create<<T>>(length)

                for idx = 1, length do
                    const _, value = value_des()
                    array[idx] = value
                end

                return static_size, array
            end
        elseif case_literal_length then
            const length = literal_values[length_datatype] :: number

            @native
            function ser(array: { T }): number
                local dynamic_bytes = 0
                for idx = 1, length do
                    dynamic_bytes += value_ser(array[idx])
                end

                return dynamic_bytes
            end

            @native
            function des(): (number, { T })
                local array = table.create<<T>>(length)

                local dynamic_bytes = 0
                for idx = 1, length do
                    const bytes, value = value_des()
                    array[idx] = value
                    dynamic_bytes += bytes
                end

                return dynamic_bytes, array
            end
        elseif length_static_bytes ~= nil and value_static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(array: { T }): number
                const arr_length = #array
                const full_size = length_static_bytes
                    + arr_length * value_static_bytes
                reserve_bytes(full_size)
                ser_length(arr_length)

                for _, value in array do
                    value_ser(value)
                end

                return full_size
            end

            @native
            function des(): (number, { T })
                const _, arr_length = des_length()
                local array = table.create<<T>>(arr_length)

                for idx = 1, arr_length do
                    const _, value = value_des()
                    array[idx] = value
                end

                return length_static_bytes + arr_length * value_static_bytes,
                    array
            end
        elseif length_static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(array: { T }): number
                const arr_length = #array
                reserve_bytes(length_static_bytes)
                ser_length(arr_length)

                local dynamic_bytes = 0
                for _, value in array do
                    dynamic_bytes += value_ser(value)
                end

                return length_static_bytes + dynamic_bytes
            end

            @native
            function des(): (number, { T })
                const _, arr_length = des_length()
                local array = table.create<<T>>(arr_length)

                local dynamic_bytes = 0
                for idx = 1, arr_length do
                    const bytes, value = value_des()
                    array[idx] = value
                    dynamic_bytes += bytes
                end

                return dynamic_bytes, array
            end
        elseif value_static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(array: { T }): number
                const arr_length = #array
                const length_bytes = ser_length(arr_length)

                const known_size = value_static_bytes * arr_length
                reserve_bytes(known_size)

                for _, value in array do
                    value_ser(value)
                end

                return length_bytes + known_size
            end

            @native
            function des(): (number, { T })
                const length_bytes, arr_length = des_length()
                const known_size = value_static_bytes * arr_length

                local array = table.create<<T>>(arr_length)
                for idx = 1, arr_length do
                    const _, value = value_des()
                    array[idx] = value
                end

                return length_bytes + known_size, array
            end
        else
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(array: { T }): number
                const arr_length = #array
                local dynamic_bytes = 0
                dynamic_bytes += ser_length(arr_length)

                for _, value in array do
                    dynamic_bytes += value_ser(value)
                end

                return dynamic_bytes
            end

            @native
            function des(): (number, { T })
                local dynamic_bytes = 0
                const length_bytes, arr_length = des_length()
                dynamic_bytes += length_bytes

                local array = table.create<<T>>(arr_length)
                for idx = 1, arr_length do
                    const bytes, value = value_des()
                    array[idx] = value
                    dynamic_bytes += bytes
                end

                return dynamic_bytes, array
            end
        end

        serializers[datatype] = ser
        deserializers[datatype] = des

        cache[hash] = datatype

        return datatype
    end

    datatypes.array = constructor
end

do -- map
    local cache = {}

    const function constructor<K, V>(
        key_datatype: Id<K>,
        value_datatype: Id<V>,
        length_datatype: Id<number>?
    ): Id<{ [types.reveal_type<K>]: types.reveal_type<V> }>
        length_datatype = length_datatype or datatypes.vlq

        const hash = ordered_hash(key_datatype, value_datatype, length_datatype)
        const cache_hit = cache[hash]
        if cache_hit ~= nil then
            return cache_hit
        end

        if not number_types[length_datatype] then
            error(
                `Tried to create a map datatype utilizing a non-number datatype {length_datatype}.`
            )
        end

        const datatype =
            make_serdes_id<<{ [types.reveal_type<K>]: types.reveal_type<V> }>>()

        const case_literal_length = literal_types[length_datatype] ~= nil
        const key_static_bytes = static_sizes[key_datatype]
        const value_static_bytes = static_sizes[value_datatype]
        const length_static_bytes = static_sizes[length_datatype]
        const case_fully_static = case_literal_length
            and key_static_bytes ~= nil
            and value_static_bytes ~= nil

        const key_ser, key_des =
            serializers[key_datatype], deserializers[key_datatype]
        const value_ser, value_des =
            serializers[value_datatype], deserializers[value_datatype]
        local ser, des

        if case_fully_static then
            const length = literal_values[length_datatype] :: number
            const static_size = length * (key_static_bytes + value_static_bytes)
            static_sizes[datatype] = static_size

            @native
            function ser(map: { [K]: V }): number
                for key, value in map do
                    key_ser(key)
                    value_ser(value)
                end

                return static_size
            end

            @native
            function des(): (number, { [K]: V })
                local map = {}

                for _ = 1, length do
                    const _, key = key_des()
                    const _, value = value_des()
                    map[key] = value
                end

                return static_size, map
            end
        elseif case_literal_length and key_static_bytes ~= nil then
            const length = literal_values[length_datatype] :: number
            const known_size = length * key_static_bytes

            @native
            function ser(map: { [K]: V }): number
                local dynamic_bytes = 0
                reserve_bytes(known_size)

                for key, value in map do
                    key_ser(key)
                    dynamic_bytes += value_ser(value)
                end

                return known_size + dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                local dynamic_bytes = 0
                local map = {}

                for _ = 1, length do
                    const _, key = key_des()
                    const bytes, value = value_des()
                    map[key] = value
                    dynamic_bytes += bytes
                end

                return known_size + dynamic_bytes, map
            end
        elseif case_literal_length and value_static_bytes ~= nil then
            const length = literal_values[length_datatype] :: number
            const known_size = length * value_static_bytes

            @native
            function ser(map: { [K]: V }): number
                local dynamic_bytes = 0
                reserve_bytes(known_size)

                for key, value in map do
                    dynamic_bytes += key_ser(key)
                    value_ser(value)
                end

                return known_size + dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                local dynamic_bytes = 0
                local map = {}

                for _ = 1, length do
                    const bytes, key = key_des()
                    const _, value = value_des()
                    map[key] = value
                    dynamic_bytes += bytes
                end

                return known_size + dynamic_bytes, map
            end
        elseif case_literal_length then
            const length = literal_values[length_datatype] :: number

            @native
            function ser(map: { [K]: V }): number
                local dynamic_bytes = 0

                for key, value in map do
                    dynamic_bytes += key_ser(key)
                    dynamic_bytes += value_ser(value)
                end

                return dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                local dynamic_bytes = 0
                local map = {}

                for _ = 1, length do
                    const key_bytes, key = key_des()
                    const value_bytes, value = value_des()
                    map[key] = value
                    dynamic_bytes += key_bytes + value_bytes
                end

                return dynamic_bytes, map
            end
        elseif
            length_static_bytes ~= nil
            and key_static_bytes ~= nil
            and value_static_bytes ~= nil
        then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]
            const kvpair_size = key_static_bytes + value_static_bytes

            @native
            function ser(map: { [K]: V }): number
                local length = 0
                for _ in map do
                    length += 1
                end

                const full_size = length_static_bytes + kvpair_size * length
                reserve_bytes(full_size)

                ser_length(length)
                for key, value in map do
                    key_ser(key)
                    value_ser(value)
                end

                return full_size
            end

            @native
            function des(): (number, { [K]: V })
                const _, length = des_length()
                local map = {}

                for _ = 1, length do
                    const _, key = key_des()
                    const _, value = value_des()
                    map[key] = value
                end

                return length_static_bytes + kvpair_size * length, map
            end
        elseif length_static_bytes ~= nil and key_static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(map: { [K]: V }): number
                local length = 0
                for _ in map do
                    length += 1
                end

                const known_size = length_static_bytes
                    + key_static_bytes * length
                reserve_bytes(known_size)

                local dynamic_bytes = 0
                ser_length(length)
                for key, value in map do
                    key_ser(key)
                    dynamic_bytes += value_ser(value)
                end

                return known_size + dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                const _, length = des_length()
                local map = {}

                local dynamic_bytes = 0
                for _ = 1, length do
                    const _, key = key_des()
                    const bytes, value = value_des()
                    map[key] = value
                    dynamic_bytes += bytes
                end

                return dynamic_bytes
                    + length_static_bytes
                    + key_static_bytes * length,
                    map
            end
        elseif length_static_bytes ~= nil and value_static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(map: { [K]: V }): number
                local length = 0
                for _ in map do
                    length += 1
                end

                const known_size = length_static_bytes
                    + value_static_bytes * length
                reserve_bytes(known_size)

                local dynamic_bytes = 0
                ser_length(length)
                for key, value in map do
                    dynamic_bytes += key_ser(key)
                    value_ser(value)
                end

                return known_size + dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                const _, length = des_length()
                local map = {}

                local dynamic_bytes = 0
                for _ = 1, length do
                    const bytes, key = key_des()
                    const _, value = value_des()
                    map[key] = value
                    dynamic_bytes += bytes
                end

                return dynamic_bytes
                    + length_static_bytes
                    + value_static_bytes * length,
                    map
            end
        elseif length_static_bytes ~= nil then
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(map: { [K]: V }): number
                local length = 0

                reserve_bytes(length_static_bytes)

                local dynamic_bytes = 0
                const length_ptr = ptr
                ptr += length_static_bytes

                for key, value in map do
                    length += 1
                    dynamic_bytes += key_ser(key)
                    dynamic_bytes += value_ser(value)
                end

                const cur_ptr = ptr
                ptr = length_ptr
                ser_length(length)
                ptr = cur_ptr

                return length_static_bytes + dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                const _, length = des_length()
                local map = {}

                local dynamic_bytes = 0
                for _ = 1, length do
                    const key_bytes, key = key_des()
                    const value_bytes, value = value_des()
                    map[key] = value
                    dynamic_bytes += key_bytes + value_bytes
                end

                return length_static_bytes + dynamic_bytes, map
            end
        else
            const ser_length, des_length =
                serializers[length_datatype], deserializers[length_datatype]

            @native
            function ser(map: { [K]: V }): number
                local length = 0
                for _ in map do
                    length += 1
                end

                local dynamic_bytes = 0
                dynamic_bytes += ser_length(length)

                for key, value in map do
                    dynamic_bytes += key_ser(key)
                    dynamic_bytes += value_ser(value)
                end

                return dynamic_bytes
            end

            @native
            function des(): (number, { [K]: V })
                local dynamic_bytes = 0
                const length_bytes, length = des_length()
                dynamic_bytes += length_bytes

                local map = {}

                for _ = 1, length do
                    const key_bytes, key = key_des()
                    const value_bytes, value = value_des()
                    map[key] = value
                    dynamic_bytes += key_bytes + value_bytes
                end

                return dynamic_bytes, map
            end
        end

        serializers[datatype] = ser
        deserializers[datatype] = des

        cache[hash] = datatype

        return datatype
    end

    datatypes.map = constructor
end

return table.freeze {
    reserve_bytes = reserve_bytes,
    read_ptr = read_ptr,
    advance_ptr = advance_ptr,

    reset = reset,
    flush = flush,

    import_cell = import_cell,
    export_cell = export_cell,

    read_packet = read_packet,
    write_packet = write_packet,
    write_packet_id = write_packet_id,
    update_packet_length = update_packet_length,
    export_packet = export_packet,

    make_serdes_id = make_serdes_id,
    ordered_hash = ordered_hash,
    datatypes = datatypes,

    uint_size_bytes = uint_size_bytes,
    convert_tables = convert_tables,

    metadata = table.freeze {
        serializers = serializers,
        deserializers = deserializers,
        static_sizes = static_sizes,

        number_types = number_types,
        literal_types = literal_types,
        literal_values = literal_values,

        uint_by_bytes = uint_by_bytes,
        int_by_bytes = int_by_bytes,
        float_by_bytes = float_by_bytes,
    },
}
