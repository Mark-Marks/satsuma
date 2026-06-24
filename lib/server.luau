--!optimize 2
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const Players = game:GetService("Players")
const fast_spawn = require("./shared/fast_spawn")
const serdes = require("./shared/serdes")
const types = require("./shared/types")
const token_bucket = require("./shared/token_bucket")

const DEBUG: boolean = _G.DEBUG
const table_create = table.create

const metadata = serdes.metadata
const serializers, deserializers, static_sizes =
    metadata.serializers, metadata.deserializers, metadata.static_sizes
const read_packet, write_packet, write_packet_id, update_packet_length, read_ptr, advance_ptr, export_packet =
    serdes.read_packet,
    serdes.write_packet,
    serdes.write_packet_id,
    serdes.update_packet_length,
    serdes.read_ptr,
    serdes.advance_ptr,
    serdes.export_packet

type QueuedEvent<T = unknown> = {
    read event_id: types.EventId,
    read serdes_id: types.SerdesId<T>,
    read data: T,
    read recipients: { Player },
}
const DEFAULT_EVENT_QUEUE_SIZE = 128
const DEFAULT_CELL_QUEUE_SIZE = 16
const DEFAULT_POLLING_QUEUE_SIZE = 128 * Players.MaxPlayers
const DEFAULT_CLEANUP_QUEUE_SIZE = 4 * Players.MaxPlayers

type Callback<T = unknown> = (player: Player, data: T) -> ()
type Iterator<T = unknown> = () -> () -> (number, Player, T)
type PollPacket<T = unknown> = { data: T, player: Player }
export type Server = {
    read reliable_socket: RemoteEvent,
    reliable_queue: { QueuedEvent },
    reliable_known_sizes: { [Player]: number },
    reliable_total_known_size: number,
    reliable_incoming_cells: { [Player]: { serdes.Cell } },

    read unreliable_socket: UnreliableRemoteEvent,
    unreliable_queue: { QueuedEvent },
    unreliable_known_sizes: { [Player]: number },
    unreliable_total_known_size: number,
    unreliable_incoming_cells: { [Player]: { serdes.Cell } },

    scheduled_for_cleanup: { [Player]: true },

    read polling_iterators: { read [types.EventId]: Iterator },
    incoming_polling_queues: { [types.EventId]: { PollPacket } },

    read ratelimit_bucket_templates: {
        read [types.EventId]: token_bucket.TokenBucket,
    },
    read ratelimit_buckets: {
        read [Player]: { read [types.EventId]: token_bucket.TokenBucket },
    },
    read max_packet_sizes: { read [types.EventId]: number },
    began_processing: number,
    remaining_processing_budget: number,
    maximum_processing_budget: number,

    read id_serdes_map: { read [types.EventId]: serdes.Id },
    id_callback_map: { [types.EventId]: Callback },
}

--- Creates and initializes a server based on all of the provided events.
--- The server must also be further started via server::begin_input and server::begin_processing.
--- Accepts a maximum processing time allowed to inbound processing per frame, measured in seconds. This isn't a hard limit, as to my knowledge there's no inexpensive way of limiting the processing time of serdes (it'd have to be steppable and would need to check the processing time each step, both of which make it noticeably slower). Rather, after each processed event, the remaining time budget is checked, and if it's exceeded, the remaining events are dropped. A sane default for 60Hz processing would be 2/1000ths of a second, or 2 miliseconds. Remember to adjust it based on the frequency you set the processing to run!
const function initialize(
    namespace: types.Namespace,
    inbound_max_processing_time: number
): Server
    local id_serdes_map = {}
    local polling_iterators = {}
    local incoming_polling_queues = {}
    local ratelimit_bucket_templates = {}
    local max_packet_sizes = {}

    local queue: { types.Event | types.Namespace } = { namespace }
    while #queue > 0 do
        local member = assert(table.remove(queue), "Luau")
        if member.serdes then
            const event: types.Event = member :: any
            const event_id = event.id
            id_serdes_map[event_id] = event.serdes
            const bucket_template = token_bucket.construct(
                event.bucket.capacity,
                event.bucket.refill_rate
            )
            ratelimit_bucket_templates[event_id] = table.freeze(bucket_template)
            max_packet_sizes[event_id] = event.max_packet_size
            incoming_polling_queues[event_id] =
                table_create<<PollPacket>>(DEFAULT_POLLING_QUEUE_SIZE)

            @native
            const function iterator(): () -> (number, Player, unknown)
                const polling_queue = incoming_polling_queues[event_id]
                const size = #polling_queue
                local index = 0

                @native
                const function step(): (number, Player, unknown)
                    index += 1
                    if index > size then
                        incoming_polling_queues[event_id] =
                            table_create<<PollPacket>>(
                                DEFAULT_POLLING_QUEUE_SIZE
                            )
                        return nil :: any
                    end

                    const packet = polling_queue[index]
                    return index, packet.player, packet.data
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

    const reliable_socket = Instance.new("RemoteEvent")
    reliable_socket.Name = shared.constants.reliable_remote_name
    reliable_socket.Parent = ReplicatedStorage

    const unreliable_socket = Instance.new("UnreliableRemoteEvent")
    unreliable_socket.Name = shared.constants.unreliable_remote_name
    unreliable_socket.Parent = ReplicatedStorage

    return {
        reliable_socket = reliable_socket,
        reliable_queue = table_create<<QueuedEvent>>(DEFAULT_EVENT_QUEUE_SIZE),
        reliable_known_sizes = {},
        reliable_total_known_size = 0,
        reliable_incoming_cells = {},

        unreliable_socket = unreliable_socket,
        unreliable_queue = table_create<<QueuedEvent>>(
            DEFAULT_EVENT_QUEUE_SIZE
        ),
        unreliable_known_sizes = {},
        unreliable_total_known_size = 0,
        unreliable_incoming_cells = {},

        scheduled_for_cleanup = {},

        polling_iterators = polling_iterators,
        incoming_polling_queues = incoming_polling_queues,

        ratelimit_bucket_templates = ratelimit_bucket_templates,
        ratelimit_buckets = {},
        max_packet_sizes = max_packet_sizes,
        began_processing = 0,
        remaining_processing_budget = inbound_max_processing_time,
        maximum_processing_budget = inbound_max_processing_time,

        id_serdes_map = id_serdes_map,
        id_callback_map = {},
    }
end

--- Connects a callback to the event, which is fired upon an incoming event being processed.
--- Mutually exclusive with server::iterate, and only available if the event isn't specified to use polling.
@native
const function connect<T>(
    server: Server,
    event: types.Event<T>,
    callback: Callback<T>
)
    const id = event.id
    if DEBUG == true and server.id_callback_map[id] ~= nil then
        warn(`DEBUG: Overwrote the callback for the event with id {id}.`)
    end

    if event.use_polling then
        error(
            `Tried to connect to an event with id {event.id} which uses polling.`
        )
    end

    server.id_callback_map[id] = callback
end

--- Iterates over all received data from this event queued since last iteration.
--- Mutually exclusive with server::connect, and only available if the event is specified to use polling.
@native
const function iterate<T>(
    server: Server,
    event: types.Event<T>
): () -> (number, Player, T)
    const id = event.id
    const iterator: Iterator<T> = server.polling_iterators[id]
    if not iterator then
        error(
            `Tried to iterate an event with id {event.id} which doesn't use polling.`
        )
    end

    return iterator()
end

--- Fires the event with the provided data through a reliable remote event to the specified list of players.
@native
const function broadcast<T>(
    server: Server,
    event: types.Event<T>,
    recipients: { Player },
    data: T
)
    const id = event.id
    const serdes_id = server.id_serdes_map[id]
    const static_size = static_sizes[serdes_id]
    if static_size then
        server.reliable_total_known_size += static_size
        for _, recipient in recipients do
            if not server.reliable_known_sizes[recipient] then
                server.reliable_known_sizes[recipient] = 0
            end
            server.reliable_known_sizes[recipient] += static_size
        end
    end

    table.insert(server.reliable_queue :: any, {
        event_id = id,
        serdes_id = serdes_id,
        data = data,
        recipients = recipients,
    }) -- Luau: any cast
end

--- Fires the event with the provided data through a reliable remote event to all players.
@native
const function broadcast_all<T>(server: Server, event: types.Event<T>, data: T)
    broadcast(server, event, Players:GetPlayers(), data)
end

--- Fires the event with the provided data through a reliable remote event to the specified player.
@native
const function send<T>(
    server: Server,
    event: types.Event<T>,
    recipient: Player,
    data: T
)
    broadcast(server, event, { recipient }, data)
end

--- Fires the event with the provided data through an unreliable remote event to the specified list of players.
@native
const function broadcast_unreliably<T>(
    server: Server,
    event: types.Event<T>,
    recipients: { Player },
    data: T
)
    const id = event.id
    const serdes_id = server.id_serdes_map[id]
    const static_size = static_sizes[serdes_id]
    if static_size then
        server.unreliable_total_known_size += static_size
        for _, recipient in recipients do
            if not server.unreliable_known_sizes[recipient] then
                server.unreliable_known_sizes[recipient] = 0
            end
            server.unreliable_known_sizes[recipient] += static_size
        end
    end

    table.insert(server.unreliable_queue :: any, {
        event_id = id,
        serdes_id = serdes_id,
        data = data,
        recipients = recipients,
    }) -- Luau: any cast
end

--- Fires the event with the provided data through an unreliable remote event to all players.
@native
const function broadcast_all_unreliably<T>(
    server: Server,
    event: types.Event<T>,
    data: T
)
    broadcast_unreliably(server, event, Players:GetPlayers(), data)
end

--- Fires the event with the provided data through an unreliable remote event to the specified player.
@native
const function send_unreliably<T>(
    server: Server,
    event: types.Event<T>,
    recipient: Player,
    data: T
)
    broadcast_unreliably(server, event, { recipient }, data)
end

--- Processes all outgoing events. Notably, no serialization is done before this is called, in order to process all writes at once. This might be changed in the future to reduce frametime spikes.
--- server::begin_processing automatically handles calling this function.
--- ⚠️ Should always be called *before* the incoming queue is processed (server::process).
@native
const function flush(server: Server, kind: "reliable" | "unreliable")
    local socket, queue, known_sizes, total_known_size
    if kind == "reliable" then
        socket, queue, known_sizes, total_known_size =
            server.reliable_socket,
            server.reliable_queue,
            server.reliable_known_sizes,
            server.reliable_total_known_size
    else
        socket, queue, known_sizes, total_known_size =
            (server.unreliable_socket :: any) :: RemoteEvent,
            server.unreliable_queue,
            server.unreliable_known_sizes,
            server.unreliable_total_known_size
    end

    type Cursor = { buf: buffer, ptr: number }
    local per_player_outbound: { [Player]: Cursor } = {}
    for player, known_size in known_sizes do
        const buf = buffer.create(known_size)
        per_player_outbound[player] = {
            buf = buf,
            ptr = 0,
        }

        known_sizes[player] = 0
    end

    const scheduled_for_cleanup = server.scheduled_for_cleanup
    serdes.reserve_bytes(total_known_size)
    for _, event: QueuedEvent in queue do
        const serdes_id = event.serdes_id
        const serialize, size = serializers[serdes_id], static_sizes[serdes_id]
        local serialized_length
        if size then
            write_packet(event.event_id, size)
            serialize(event.data)
            serialized_length = size
        else
            write_packet_id(event.event_id)
            serialized_length = serialize(event.data)
            update_packet_length(serialized_length)
        end

        for _, recipient in event.recipients do
            if scheduled_for_cleanup[recipient] then
                continue
            end

            local outbound = per_player_outbound[recipient]
            outbound.buf =
                export_packet(serialized_length, outbound.buf, outbound.ptr)
            outbound.ptr += serialized_length
        end
    end

    if kind == "reliable" then
        server.reliable_queue =
            table_create<<QueuedEvent>>(DEFAULT_EVENT_QUEUE_SIZE)
        server.reliable_total_known_size = 0
    else
        server.unreliable_queue =
            table_create<<QueuedEvent>>(DEFAULT_EVENT_QUEUE_SIZE)
        server.unreliable_total_known_size = 0
    end

    -- TODO: Find a better way to do this without sacrificing performance
    const cell = serdes.export_cell()
    const references = cell.references
    serdes.reset()
    for player, outbound in per_player_outbound do
        const len = buffer.len(outbound.buf)
        local trimmed = outbound.buf
        if len > outbound.ptr then
            trimmed = buffer.create(outbound.ptr)
            buffer.copy(trimmed, 0, outbound.buf, 0, outbound.ptr)
        end

        socket:FireClient(player, trimmed, references)
    end
end

--- Processes all incoming events.
--- server::begin_processing automatically handles calling this function.
--- ⚠️ Should always be called *after* the outgoing event queue is flushed (server::flush).
@native
const function process(server: Server, kind: "reliable" | "unreliable")
    local queues = if kind == "reliable"
        then server.reliable_incoming_cells
        else server.unreliable_incoming_cells

    const id_serdes_map, id_callback_map, incoming_polling_queues, max_packet_sizes =
        server.id_serdes_map,
        server.id_callback_map,
        server.incoming_polling_queues,
        server.max_packet_sizes

    local remaining_processing_budget = server.maximum_processing_budget
    for player, queue in queues do
        local ran_out_of_budget = false

        for idx, cell in queue do
            local stop_processing_player = false
            const size = cell.size
            serdes.import_cell(cell)

            while read_ptr() < size do
                if remaining_processing_budget <= 0 then
                    ran_out_of_budget, stop_processing_player = true, true

                    const ptr = read_ptr()
                    const remaining_bytes = size - ptr
                    const remaining_data = buffer.create(remaining_bytes)
                    buffer.copy(
                        remaining_data,
                        0,
                        cell.buf,
                        ptr,
                        remaining_bytes
                    )
                    queue[idx] = {
                        buf = remaining_data,
                        ptr = 0,
                        references = cell.references,
                        size = remaining_bytes,
                    }

                    break
                end

                const started = os.clock()
                const event_id, packet_length = read_packet()
                const serdes_id, max_packet_size =
                    id_serdes_map[event_id], max_packet_sizes[event_id]

                if read_ptr() + packet_length > size then
                    warn(
                        `Player {player} sent an invalid packet for event id {event_id} which reports the size of {packet_length} at pointer {read_ptr()} and size of data of {size}. Dropping all remaining packets sent by the player.`
                    )
                    stop_processing_player = true
                    remaining_processing_budget -= os.clock() - started
                    break
                end

                if packet_length > max_packet_size then
                    warn(
                        `Player {player} exceeded max packet size {max_packet_size} for event id {event_id} with packet size of {packet_length}. Dropping all remaining packets sent by the player.`
                    )
                    stop_processing_player = true
                    remaining_processing_budget -= os.clock() - started
                    break
                end

                if serdes_id == nil then
                    warn(
                        `Received potentially malformed event id: {event_id} with no bound serdes during processing from player {player}.`
                    )
                    advance_ptr(packet_length)
                    remaining_processing_budget -= os.clock() - started
                    continue
                end

                const callback = id_callback_map[event_id]
                const polling_queue = incoming_polling_queues[event_id]
                if callback == nil and polling_queue == nil then
                    warn(
                        `Received potentially malformed event id: {event_id} with no bound callback or polling queue during processing from player {player}.`
                    )
                    advance_ptr(packet_length)
                    remaining_processing_budget -= os.clock() - started
                    continue
                end

                const deserialize = deserializers[serdes_id]
                const data = deserialize()

                if polling_queue then
                    table.insert(
                        polling_queue,
                        { data = data, player = player }
                    )
                else
                    fast_spawn(callback, player, data)
                end

                remaining_processing_budget -= os.clock() - started
            end

            if not ran_out_of_budget then
                queue[idx] = nil
            end

            if stop_processing_player and not ran_out_of_budget then
                queues[player] =
                    table.create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
                break
            end
        end

        if ran_out_of_budget then
            local remaining_data_starts_at = 0
            for idx, cell in queue do
                if cell ~= nil then
                    remaining_data_starts_at = idx
                    break
                end
            end

            if remaining_data_starts_at ~= 0 then
                local new_queue =
                    table.create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
                table.move(
                    queue,
                    remaining_data_starts_at,
                    #queue,
                    1,
                    new_queue
                )
                queues[player] = new_queue
            end

            break
        end

        queues[player] = table.create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
    end

    serdes.reset()
end

--- Sets up everything which relates to the player.
--- The server can function without this, as for safety event processing will create anything that hasn't been set up yet, although setting everything up before-hand will lower and smoothen out processing time.
--- server::begin_processing automatically handles calling this function.
@native
const function setup_player(server: Server, player: Player)
    if not server.reliable_known_sizes[player] then
        server.reliable_known_sizes[player] = 0
    end

    if not server.reliable_incoming_cells[player] then
        server.reliable_incoming_cells[player] =
            table_create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
    end

    if not server.unreliable_known_sizes[player] then
        server.unreliable_known_sizes[player] = 0
    end

    if not server.unreliable_incoming_cells[player] then
        server.unreliable_incoming_cells[player] =
            table_create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
    end

    local buckets = {}
    for event_id, template in server.ratelimit_bucket_templates do
        buckets[event_id] = table.clone(template)
    end
    (server :: types.writable<Server>).ratelimit_buckets[player] = buckets
end

--- Schedules for the cleanup of anything related to the player once all of the player's inbound packets have been processed. Any outbound packets will still be sent, as a check for cleaned up players will be more expensive in the long run than sending packets to dead players.
--- server::begin_processing automatically handles calling this function.
@native
const function cleanup_player(server: Server, player: Player)
    if server.scheduled_for_cleanup[player] ~= true then
        server.scheduled_for_cleanup[player] = true
    end
end

--- Checks if any players scheduled for cleanup may be cleaned up.
--- This entails checking if there's no more inbound or outbound data scheduled for the player, and if not, cleaning up all data on the server pertaining to them.
--- Should be called after server::begin_processing and server::begin_input.
--- server::begin_processing automatically handles calling this function.
@native
const function tick_player_cleanup(server: Server)
    for player in server.scheduled_for_cleanup do
        if
            #server.reliable_incoming_cells[player] > 0
            or #server.unreliable_incoming_cells[player] > 0
            or server.reliable_known_sizes[player] > 0
            or server.unreliable_known_sizes[player] > 0
        then
            continue
        end

        server.reliable_incoming_cells[player] = nil
        server.unreliable_incoming_cells[player] = nil
        server.reliable_known_sizes[player] = nil
        server.unreliable_known_sizes[player] = nil
        (server :: types.writable<Server>).ratelimit_buckets[player] = nil
        server.scheduled_for_cleanup[player] = nil
    end
end

--- Refills all ratelimit buckets for any players not scheduled for cleanup.
--- server::begin_processing automatically handles calling this function.
@native
const function refill_ratelimit_buckets(server: Server)
    const scheduled_for_cleanup = server.scheduled_for_cleanup

    for player, buckets in server.ratelimit_buckets do
        if scheduled_for_cleanup[player] then
            continue
        end

        for _, bucket in buckets do
            token_bucket.refill(bucket)
        end
    end
end

--- Starts listening to input from the networking remotes.
--- Returns a function which disconnects from the remotes.
const function begin_input(server: Server): () -> ()
    local reliable_incoming_cells = server.reliable_incoming_cells
    local unreliable_incoming_cells = server.unreliable_incoming_cells

    const function make_listener(kind: "reliable" | "unreliable")
        local fetch_queue
        if kind == "reliable" then
            @native
            function fetch_queue(player: Player)
                local incoming_queue = reliable_incoming_cells[player]
                if not incoming_queue then
                    incoming_queue =
                        table_create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
                    reliable_incoming_cells[player] = incoming_queue
                end
                return incoming_queue
            end
        else
            @native
            function fetch_queue(player: Player)
                local incoming_queue = unreliable_incoming_cells[player]
                if not incoming_queue then
                    incoming_queue =
                        table_create<<serdes.Cell>>(DEFAULT_CELL_QUEUE_SIZE)
                    unreliable_incoming_cells[player] = incoming_queue
                end
                return incoming_queue
            end
        end

        @native
        const function listener(
            player: Player,
            data: buffer,
            references: serdes.References
        )
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
            table.insert(fetch_queue(player), cell)
        end

        return listener
    end

    const reliable_connection =
        server.reliable_socket.OnServerEvent:Connect(make_listener("reliable"))
    const unreliable_connection =
        server.unreliable_socket.OnServerEvent:Connect(
            make_listener("unreliable")
        )

    return function()
        reliable_connection:Disconnect()
        unreliable_connection:Disconnect()
    end
end

--- Sets up a loop which handles all inbound & outbound processing.
--- Shouldn't be used alongside server::flush and server::process.
--- The frequency should be measured in hertz (1/ticks per second), a sane default would be 60/30/24Hz, depending on your needs.
--- The maximum frequency is 60Hz, as the underlying loop relies on RunService.Heartbeat.
--- Returns a function which disconnects the processing loop.
const function begin_processing(server: Server, frequency: number)
    -- thank you, @Hexcede!
    const tickrate = frequency
    const start_time = os.clock()
    local current_tick = 0

    local player_added_queue =
        table_create<<Player>>(DEFAULT_CLEANUP_QUEUE_SIZE)
    local player_removing_queue =
        table_create<<Player>>(DEFAULT_CLEANUP_QUEUE_SIZE)

    @native
    const function on_added(player)
        table.insert(player_added_queue, player)

        const idx = table.find(player_removing_queue, player)
        if idx then
            table.remove(player_removing_queue, idx)
        end
    end
    const player_added_connection = Players.PlayerAdded:Connect(on_added)

    @native
    const function on_removing(player)
        table.insert(player_removing_queue, player)

        const idx = table.find(player_added_queue, player)
        if idx then
            table.remove(player_added_queue, idx)
        end
    end
    const player_removing_connection =
        Players.PlayerRemoving:Connect(on_removing)

    @native
    const function networking_tick()
        for _, player in player_added_queue do
            setup_player(server, player)
        end
        player_added_queue = table_create<<Player>>(DEFAULT_CLEANUP_QUEUE_SIZE)

        flush(server, "reliable")
        flush(server, "unreliable")

        process(server, "reliable")
        process(server, "unreliable")

        for _, player in player_removing_queue do
            cleanup_player(server, player)
        end
        player_removing_queue =
            table_create<<Player>>(DEFAULT_CLEANUP_QUEUE_SIZE)

        tick_player_cleanup(server)

        current_tick += 1
    end

    local accum = 0
    @native
    const function loop(dt: number)
        const target_tick = (os.clock() - start_time) * tickrate
        for _ = current_tick, target_tick do
            networking_tick()
        end

        accum += dt
        if accum >= 1 then
            accum = 0
            refill_ratelimit_buckets(server)
        end
    end
    const loop_connection = RunService.Heartbeat:Connect(loop)

    return function()
        loop_connection:Disconnect()
        player_added_connection:Disconnect()
        player_removing_connection:Disconnect()
    end
end

return table.freeze {
    initialize = initialize,

    connect = connect,
    iterate = iterate,

    send = send,
    broadcast = broadcast,
    broadcast_all = broadcast_all,

    send_unreliably = send_unreliably,
    broadcast_unreliably = broadcast_unreliably,
    broadcast_all_unreliably = broadcast_all_unreliably,

    setup_player = setup_player,
    cleanup_player = cleanup_player,
    flush = flush,
    process = process,

    begin_input = begin_input,
    begin_processing = begin_processing,
}
