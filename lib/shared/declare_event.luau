const types = require("./types")
const serdes = require("./serdes")

const static_sizes = serdes.metadata.static_sizes
const DEFAULT_MAX_PACKET_SIZE = 8_000
const MAX_PACKET_SIZE = 2 ^ 16 - 1

export type Event<T = unknown> = types.Event<T>
export type EventId = types.EventId

local current_event_id = 0

--- Declares an event with the provided data type, set up with a rate limit which allows for players to call it based on the amount of calls left in their call budget.
--- The call budget is refilled every second with the specified amount of refills.
--- Accepts a setting to set the event to receiving data via polling, instead of callbacks.
--- Accepts a packet byte size limit, which defaults to 8000 bytes and is limited to 2^16-1, the limit of an uint8. This limit will automatically change to the static size of the data calculated by the serdes library, if it exists. Elsewise, if a static size doesn't exist, you should set a sane limit yourself to both keep the remote from being exploited to DDOS the server, and let all of the data you need to pass through and be processed.
const function declare_event<T>(declaration: {
    data_type: T,
    call_budget: number,
    budget_refill: number,
    use_polling: boolean?,
    max_packet_size: number?,
}): Event<types.reveal_type<T>>
    current_event_id += 1

    local max_packet_size: number? = static_sizes[declaration.data_type]
    if declaration.max_packet_size ~= nil then
        max_packet_size = declaration.max_packet_size
    end
    max_packet_size = max_packet_size or DEFAULT_MAX_PACKET_SIZE

    if max_packet_size > MAX_PACKET_SIZE then
        error(
            `Tried to create an event with either an implicit or explicit max packet size of over {MAX_PACKET_SIZE} (2^16-1) bytes.`
        )
    end

    return table.freeze {
        id = types.insert_ghost<<EventId>>(current_event_id),
        serdes = serdes.convert_tables(declaration.data_type),
        bucket = table.freeze {
            capacity = declaration.call_budget,
            refill_rate = declaration.budget_refill,
        },
        use_polling = declaration.use_polling or false,
        max_packet_size = max_packet_size,
    }
end

--- Luau: https://github.com/luau-lang/luau/issues/1947
--- This is literally 1947...
type HackyBullshitDefinitionPleaseFix =
    (<T>(
        declaration: {
            data_type: T,
            call_budget: number,
            budget_refill: number,
        }
    ) -> Event<types.reveal_type<T>>)
    & (<T>(
        declaration: {
            data_type: T,
            call_budget: number,
            budget_refill: number,
            use_polling: boolean,
        }
    ) -> Event<types.reveal_type<T>>)
    & (<T>(
        declaration: {
            data_type: T,
            call_budget: number,
            budget_refill: number,
            max_packet_size: number,
        }
    ) -> Event<types.reveal_type<T>>)
    & (<T>(
        declaration: {
            data_type: T,
            call_budget: number,
            budget_refill: number,
            use_polling: boolean,
            max_packet_size: number,
        }
    ) -> Event<types.reveal_type<T>>)

return declare_event :: HackyBullshitDefinitionPleaseFix
