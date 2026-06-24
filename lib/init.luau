const client = require("@self/client")
const server = require("@self/server")
const declare_event = require("@self/shared/declare_event")
const serdes = require("@self/shared/serdes")
const types = require("@self/shared/types")

export type EventId = types.EventId
export type SerdesId<T = unknown> = types.SerdesId<T>
export type Reference = types.Reference
export type Event<T = unknown> = types.Event<T>
export type Namespace = types.Namespace

export type reveal_type<T> = types.reveal_type<T>

return {
    client = client,
    server = server,

    event = declare_event,
    serdes = serdes,
    datatypes = serdes.datatypes,
}
