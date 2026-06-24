--!optimize 2
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const fast_spawn = require("./shared/fast_spawn")
const serdes = require("./shared/serdes")
const types = require("./shared/types")

const DEBUG: boolean = _G.DEBUG
const table_create = table.create -- This is not fast called (yet)

const metadata = serdes.metadata
const serializers, deserializers, static_sizes =
    metadata.serializers, metadata.deserializers, metadata.static_sizes
const read_packet, write_packet, write_packet_id, update_packet_length, read_ptr, advance_ptr =
    serdes.read_packet,
    serdes.write_packet,
    serdes.write_packet_id,
    serdes.update_packet_length,
    serdes.read_ptr,
    serdes.advance_ptr

type QueuedEvent<T = unknown> = {
    read event_id: types.EventId,
    read serdes_id: types.SerdesId<T>,
    read data: T,
}
const DEFAULT_EVENT_QUEUE_SIZE = 128
const DEFAULT_CELL_QUEUE_SIZE = 16
const DEFAULT_POLLING_QUEUE_SIZE = 128

type Callback<T = unknown> = (data: T) -> ()
type Iterator<T = unknown> = () -> () -> (number, T)
export type Client = {
    read reliable_socket: RemoteEvent,
    reliable_queue: { QueuedEvent },
    reliable_known_size: number,
    reliable_incoming_cells: { serdes.Cell },

    read unreliable_socket: UnreliableRemoteEvent,
    unreliable_queue: { QueuedEvent },
    unreliable_known_size: number,
    unreliable_incoming_cells: { serdes.Cell },

    read polling_iterators: { read [types.EventId]: Iterator },
    incoming_polling_queues: { [types.EventId]: { unknown } },

    read id_serdes_map: { read [types.EventId]: serdes.Id },
    id_callback_map: { [types.EventId]: Callback },
}

--- Creates and initializes a client based on all of the provided events.
--- The client must also be further started via client::begin_input and client::begin_processing.
--- ⚠️ Can yield in order to wait for the networking remotes to be created and replicated by the server.
const function initialize(namespace: types.Namespace): Client
    local id_serdes_map = {}
    local polling_iterators = {}
    local incoming_polling_queues = {}

    local queue: { types.Event | types.Namespace } = { namespace }
    while #queue > 0 do
        local member = assert(table.remove(queue), "Luau")
        if member.serdes then
            const event: types.Event = member :: any
            const event_id = event.id
            id_serdes_map[event_id] = event.serdes
            incoming_polling_queues[event_id] =
                table_create(DEFAULT_POLLING_QUEUE_SIZE)

            @native
            const function iterator(): () -> (number, unknown)
                const polling_queue = incoming_polling_queues[event_id]
                const size = #polling_queue
                local index = 0

                @native
                const function step(): (number, unknown)
                    index += 1
                    if index > size then
                        incoming_polling_queues[event_id] =
                            table_create(DEFAULT_POLLING_QUEUE_SIZE)
                        return nil :: any
                    end

                    const data = polling_queue[index]
                    return index, data
                end

                return step
            end
            polling_iterators[event_id] = iterator

            continue
        end

        for _, child in member do
            table.insert(queue, child)
        end
    end

    const reliable_socket =
        ReplicatedStorage:WaitForChild(shared.constants.reliable_remote_name)
    if not reliable_socket:IsA("RemoteEvent") then
        error(
            `The instance named {shared.constants.reliable_remote_name} parented to ReplicatedStorage isn't a remote event. Aborting initialization of networking client.`
        )
    end

    const unreliable_socket =
        ReplicatedStorage:WaitForChild(shared.constants.unreliable_remote_name)
    if not unreliable_socket:IsA("UnreliableRemoteEvent") then
        error(
            `The instance named {shared.constants.unreliable_remote_name} parented to ReplicatedStorage isn't an unreliable remote event. Aborting initialization of networking client.`
        )
    end

    return {
        reliable_socket = reliable_socket,
        reliable_queue = table_create<<QueuedEvent>>(DEFAULT_EVENT_QUEUE_SIZE),
        reliable_known_size = 0,
        reliable_incoming_cells = table_create<<serdes.Cell>>(
            DEFAULT_CELL_QUEUE_SIZE
        ),

        unreliable_socket = unreliable_socket,
        unreliable_queue = table_create<<QueuedEvent>>(
            DEFAULT_EVENT_QUEUE_SIZE
        ),
        unreliable_known_size = 0,
        unreliable_incoming_cells = table_create<<serdes.Cell>>(
            DEFAULT_CELL_QUEUE_SIZE
        ),

        polling_iterators = polling_iterators,
        incoming_polling_queues = incoming_polling_queues,

        id_serdes_map = id_serdes_map,
        id_callback_map = {},
    }
end

--- Connects a callback to the event, which is fired upon an incoming event being processed.
--- Mutually exclusive with client::iterate, and only available if the event isn't specified to use polling.
@native
const function connect<T>(
    client: Client,
    event: types.Event<T>,
    callback: Callback<T>
)
    const id = event.id
    if DEBUG == true and client.id_callback_map[id] ~= nil then
        warn(`DEBUG: Overwrote the callback for the event with id {id}.`)
    end

    if event.use_polling then
        error(
            `Tried to connect to an event with id {event.id} which uses polling.`
        )
    end

    client.id_callback_map[id] = callback
end

--- Iterates over all received data from this event queued since last iteration.
--- Mutually exclusive with client::connect, and only available if the event is specified to use polling.
@native
const function iterate<T>(client: Client, event: types.Event<T>): () -> (number, T)
    const id = event.id
    const iterator: Iterator<T> = client.polling_iterators[id]
    if not iterator then
        error(
            `Tried to iterate an event with id {event.id} which doesn't use polling.`
        )
    end

    return iterator()
end

--- Fires the event with the provided data through a reliable remote event.
@native
const function send<T>(client: Client, event: types.Event<T>, data: T)
    const id = event.id
    const serdes_id = client.id_serdes_map[id]
    const static_size = static_sizes[serdes_id]
    if static_size then
        client.reliable_known_size += static_size
    end

    table.insert(client.reliable_queue :: any, {
        event_id = id,
        serdes_id = serdes_id,
        data = data,
    }) -- Luau: any cast
end

--- Fires the event with the provided data through an unreliable remote event.
@native
const function send_unreliably<T>(client: Client, event: types.Event<T>, data: T)
    const id = event.id
    const serdes_id = client.id_serdes_map[id]
    const static_size = static_sizes[serdes_id]
    if static_size then
        client.unreliable_known_size += static_size
    end

    table.insert(client.unreliable_queue :: any, {
        event_id = id,
        serdes_id = serdes_id,
        data = data,
    }) -- Luau: any cast
end

--- Processes all outgoing events. Notably, no serialization is done before this is called, in order to process all writes at once. This might be changed in the future to reduce frametime spikes.
--- client::begin_processing automatically handles calling this function.
--- ⚠️ Should always be called *before* the incoming queue is processed (client::process).
@native
const function flush(client: Client, kind: "reliable" | "unreliable")
    local socket, queue, known_size
    if kind == "reliable" then
        socket, queue, known_size =
            client.reliable_socket,
            client.reliable_queue,
            client.reliable_known_size
    else
        socket, queue, known_size =
            (client.unreliable_socket :: any) :: RemoteEvent,
            client.unreliable_queue,
            client.unreliable_known_size
    end

    serdes.reserve_bytes(known_size)
    for _, event: QueuedEvent in queue do
        const serdes_id = event.serdes_id
        const serialize, size = serializers[serdes_id], static_sizes[serdes_id]
        if size then
            write_packet(event.event_id, size)
            serialize(event.data)
        else
            write_packet_id(event.event_id)
            const serialized_length = serialize(event.data)
            update_packet_length(serialized_length)
        end
    end

    if kind == "reliable" then
        client.reliable_queue =
            table_create<<QueuedEvent>>(DEFAULT_EVENT_QUEUE_SIZE)
        client.reliable_known_size = 0
    else
        client.unreliable_queue =
            table_create<<QueuedEvent>>(DEFAULT_EVENT_QUEUE_SIZE)
        client.unreliable_known_size = 0
    end

    const buf, references = serdes.flush()
    socket:FireServer(buf, references)
end

--- Processes all incoming events.
--- client::begin_processing automatically handles calling this function.
--- ⚠️ Should always be called *after* the outgoing event queue is flushed (client::flush).
@native
const function process(client: Client, kind: "reliable" | "unreliable")
    const queue = if kind == "reliable"
        then client.reliable_incoming_cells
        else client.unreliable_incoming_cells

    const id_serdes_map, id_callback_map, incoming_polling_queues =
        client.id_serdes_map,
        client.id_callback_map,
        client.incoming_polling_queues

    for _, cell in queue do
        const size = cell.size
        serdes.import_cell(cell)

        while read_ptr() < size do
            const event_id, packet_length = read_packet()
            const serdes_id = id_serdes_map[event_id]
            if serdes_id == nil then
                warn(
                    `Received potentially malformed event id: {event_id} with no bound serdes during processing.`
                )
                advance_ptr(packet_length) -- Advance the pointer to be able to recover from the error
                continue
            end

            const callback = id_callback_map[event_id]
            const polling_queue = incoming_polling_queues[event_id]
            if callback == nil and polling_queue == nil then
                warn(
                    `Received potentially malformed event id: {event_id} with no bound callback or polling queue during processing.`
                )
                advance_ptr(packet_length)
                continue
            end

            const deserialize = deserializers[serdes_id]
            const data = deserialize()

            if polling_queue then
                table.insert(polling_queue, data)
            else
                fast_spawn(callback, data)
            end
        end
    end

    if kind == "reliable" then
        client.reliable_incoming_cells =
            table_create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
    else
        client.unreliable_incoming_cells =
            table_create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
    end
    serdes.reset()
end

--- Starts listening to input from the networking remotes.
--- Returns a function which disconnects from the remotes.
const function begin_input(client: Client): () -> ()
    const function make_listener(kind: "reliable" | "unreliable")
        local fetch_queue
        if kind == "reliable" then
            @native
            function fetch_queue()
                return client.reliable_incoming_cells
            end
        else
            @native
            function fetch_queue()
                return client.unreliable_incoming_cells
            end
        end

        @native
        const function listener(data: buffer, references: serdes.References)
            assert(
                typeof(data) == "buffer",
                "Failed sanity check on incoming networking data being a buffer."
            )
            assert(
                typeof(references) == "table",
                "Failed sanity check on incoming networking references being a table."
            )

            const size = buffer.len(data)
            const cell: serdes.Cell = {
                references = references,
                buf = data,
                size = size,
                ptr = 0,
            }
            table.insert(fetch_queue(), cell)
        end

        return listener
    end

    const reliable_connection =
        client.reliable_socket.OnClientEvent:Connect(make_listener("reliable"))
    const unreliable_connection =
        client.unreliable_socket.OnClientEvent:Connect(
            make_listener("unreliable")
        )

    return function()
        reliable_connection:Disconnect()
        unreliable_connection:Disconnect()
    end
end

--- Sets up a loop which handles all inbound & outbound processing.
--- Shouldn't be used alongside client::flush and client::process.
--- The frequency should be measured in hertz (ticks per second), a sane default would be 60/30/24Hz, depending on your needs.
--- The maximum frequency is 60Hz, as the underlying loop relies on RunService.Heartbeat.
--- Returns a function which disconnects the processing loop.
const function begin_processing(client: Client, frequency: number): () -> ()
    -- thank you, @Hexcede!
    const tickrate = frequency
    const start_time = os.clock()
    local current_tick = 0

    @native
    const function networking_tick()
        flush(client, "reliable")
        flush(client, "unreliable")

        process(client, "reliable")
        process(client, "unreliable")

        current_tick += 1
    end

    const connection = RunService.Heartbeat:Connect(@native function()
        const target_tick = (os.clock() - start_time) * tickrate
        for _ = current_tick, target_tick do
            networking_tick()
        end
    end)

    return function()
        connection:Disconnect()
    end
end

return table.freeze {
    initialize = initialize,

    connect = connect,
    iterate = iterate,

    send = send,
    send_unreliably = send_unreliably,

    flush = flush,
    process = process,

    begin_input = begin_input,
    begin_processing = begin_processing,
}
