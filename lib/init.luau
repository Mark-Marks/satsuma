-- TODO: Change these imports to local in the future once pesde gets support for it or an official Luau package manager everyone switches to comes out
local client = require("@self/client")
local declare_event = require("@self/shared/declare_event")
local serdes = require("@self/shared/serdes")
local server = require("@self/server")
local types = require("@self/shared/types")

export type EventId = types.EventId
export type SerdesId<T = unknown> = types.SerdesId<T>
export type Reference = types.Reference
export type Event<T = unknown> = types.Event<T>
export type Namespace = types.Namespace

--- Reveals the type of a serdes id
export type reveal<T> = types.reveal_type<T>
--- Extracts the type of an event
export type extract<T> = types.extract_my_god_damned_data<T>

return {
    client = client,
    server = server,

    event = declare_event,
    serdes = serdes,
    datatypes = serdes.datatypes,
}
