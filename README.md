<div align="center">

My summer networking library

[![CI](https://img.shields.io/github/actions/workflow/status/mark-marks/satsuma/ci.yml?style=for-the-badge&label=CI)](https://github.com/mark-marks/satsuma/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](https://github.com/mark-marks/satsuma/blob/main/LICENSE)
<a href="https://pesde.dev/packages/marked/sastsuma"><img alt="Pesde" src="https://img.shields.io/badge/pesde-YOUSHOULDNTSEETHIS?style=for-the-badge&color=F19D1E&logo=data:image/svg%2bxml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMTAwIDEwMCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZmlsbC1ydWxlPSJldmVub2RkIiBjbGlwLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik00OS42MDI1IDBMOTIuOTAzOCAyNVY3NUw0OS42MDI1IDEwMEw2LjMwMTI3IDc1VjI1TDQ5LjYwMjUgMFpNMTQuMzAxMyAyOS42MTg4TDQ5LjYwMjUgOS4yMzc2TDg0LjkwMzggMjkuNjE4OFY3MC4zODEyTDQ5LjYwMjUgOTAuNzYyNEwzMy42MTQ4IDgxLjUzMTlWNjcuMzg0OEMzNC41MTY3IDY4LjUwNzEgMzUuNjM4OCA2OS40MjE1IDM2Ljk4MSA3MC4xMjc5QzM4Ljk3MDEgNzEuMTQ4IDQxLjAzNTcgNzEuNjU4IDQzLjE3NzkgNzEuNjU4QzQ2LjQ0MiA3MS42NTggNDkuMTQ1MiA3MC44OTI5IDUxLjI4NzMgNjkuMzYyOUM1My40ODA1IDY3Ljc4MTggNTUuMTEyNiA2NS43NjcyIDU2LjE4MzYgNjMuMzE5QzU3LjA5MTUgNjEuMzM4MiA1Ny42MzIgNTkuMjc0IDU3LjgwNTQgNTcuMTI2M0M1OS44NzIzIDU3Ljc0NTcgNjIuMjE1NyA1OC4wNTU0IDY0LjgzNTYgNTguMDU1NEM2Ny42OTE4IDU4LjA1NTQgNzAuMzY5NSA1Ny42NDczIDcyLjg2ODYgNTYuODMxM0M3NS4zNjc4IDU1Ljk2NDIgNzcuNDA3OSA1NC44MTY3IDc4Ljk4OSA1My4zODg2TDc1Ljc3NTggNDcuODAzOEM3NC41NTE3IDQ4LjkyNTggNzIuOTk2MSA0OS44NDM5IDcxLjEwOSA1MC41NTc5QzY5LjIyMTkgNTEuMjIxIDY3LjIwNzMgNTEuNTUyNSA2NS4wNjUyIDUxLjU1MjVDNjEuMzkyOSA1MS41NTI1IDU4LjY2NDMgNTAuNjg1NCA1Ni44NzkyIDQ4Ljk1MTNDNTYuNzE5NSA0OC43OTYyIDU2LjU2NyA0OC42MzY1IDU2LjQyMTcgNDguNDcyQzU1LjYxMDIgNDcuNTUzOSA1NS4wMjExIDQ2LjQ4OTYgNTQuNjU0NiA0NS4yNzkxTDU0LjY0NDMgNDUuMjQ1Mkw1NC42NjkgNDUuMjc5MUg3OS4yMTg1VjQxLjk4OTRDNzkuMjE4NSAzOS4wMzEzIDc4LjU1NTUgMzYuMzUzNiA3Ny4yMjk0IDMzLjk1NjVDNzUuOTU0MyAzMS41NTkzIDc0LjA5MjcgMjkuNjQ2NyA3MS42NDQ1IDI4LjIxODZDNjkuMjQ3NCAyNi43Mzk1IDY2LjM2NTcgMjYgNjIuOTk5NSAyNkM1OS42ODQzIDI2IDU2LjgwMjcgMjYuNzM5NSA1NC4zNTQ1IDI4LjIxODZDNTEuOTA2NCAyOS42NDY3IDUwLjAxOTMgMzEuNTU5MyA0OC42OTMyIDMzLjk1NjVDNDcuNjc0MyAzNS43OTgzIDQ3LjA0NjkgMzcuODA1NyA0Ni44MTA4IDM5Ljk3ODhDNDUuNjg4OCAzOS43MjggNDQuNDc3OCAzOS42MDI2IDQzLjE3NzkgMzkuNjAyNkM0MS4wMzU3IDM5LjYwMjYgMzguOTcwMSA0MC4xMTI3IDM2Ljk4MSA0MS4xMzI3QzM1LjMxNjIgNDEuOTY1MSAzMy45OTAyIDQzLjE1NDkgMzMuMDAyOCA0NC43MDIzVjQwLjM2NzdIMjAuNjg1NVY0Ni4yNTg1SDI1LjgxMTNWNzcuMDI2NkwxNC4zMDEzIDcwLjM4MTJWMjkuNjE4OFpNNTUuMTk2MSAzNi4wOTg2QzU0LjY1MjggMzcuMTAxNSA1NC4zMzIxIDM4LjEyMTYgNTQuMjM0IDM5LjE1ODhINzEuNzk3NkM3MS43OTc2IDM4LjAzNjcgNzEuNDQwNSAzNi45NDAxIDcwLjcyNjUgMzUuODY5MUM3MC4wNjM0IDM0Ljc0NyA2OS4wNjg5IDMzLjgwMzUgNjcuNzQyOCAzMy4wMzg0QzY2LjQ2NzcgMzIuMjczNCA2NC44ODY3IDMxLjg5MDggNjIuOTk5NSAzMS44OTA4QzYxLjExMjQgMzEuODkwOCA1OS41MDU4IDMyLjI5ODkgNTguMTc5OCAzMy4xMTQ5QzU2LjkwNDcgMzMuODggNTUuOTEwMSAzNC44NzQ1IDU1LjE5NjEgMzYuMDk4NlpNNDkuNjQ1MSA1MS41NjkyQzQ5LjMwNzYgNTAuNjY0MSA0OC44MzgxIDQ5Ljg3MSA0OC4yMzY3IDQ5LjE4OThDNDguMDg4NSA0OS4wMjE5IDQ3LjkzMjMgNDguODYwOSA0Ny43NjgxIDQ4LjcwNjdDNDYuMDg1IDQ3LjA3NDYgNDQuMDQ0OSA0Ni4yNTg1IDQxLjY0NzggNDYuMjU4NUM0MC4xMTc3IDQ2LjI1ODUgMzguNjEzMSA0Ni41NjQ1IDM3LjEzNCA0Ny4xNzY2QzM1Ljg1OTQgNDcuNjc3MyAzNC42ODYzIDQ4LjU0MzggMzMuNjE0OCA0OS43NzU5VjYxLjQ3QzM0LjY4NjMgNjIuNjY2NCAzNS44NTk0IDYzLjUzNzggMzcuMTM0IDY0LjA4NEMzOC42MTMxIDY0LjY5NjEgNDAuMTE3NyA2NS4wMDIxIDQxLjY0NzggNjUuMDAyMUM0NC4wNDQ5IDY1LjAwMjEgNDYuMDg1IDY0LjE4NjEgNDcuNzY4MSA2Mi41NTRDNDkuNDUxMiA2MC45MjE5IDUwLjI5MjggNTguNjAxMiA1MC4yOTI4IDU1LjU5MjFDNTAuMjkyOCA1NC4wNjc5IDUwLjA3NjkgNTIuNzI3IDQ5LjY0NTEgNTEuNTY5MloiIGZpbGw9IiNGRkZGRkYiPjwvcGF0aD4KPC9zdmc+" /></a>

</div>

---

&nbsp;

## 🚗 Satsuma

**Satsuma** is an ergonomic, probably pretty fast networking library. The main differences (and benefits) compared to others come via:
- Deferring all networking processing to a special networking tick
- Minimizing allocations as much as possible
- An extendible, stupidly fast 2k LOC serdes library derived from [holy](https://gist.github.com/hardlyardi/3ec65bd533b37095a48b3afadb08626c)
- A more data-oriented rather than object-oriented approach

&nbsp;

## 🪶 Quick start

> [!CAUTION]
> Here be dragons! Satsuma is entirely untested, and may break at a whim.\
> The three and a half thousand lines of code this repo contains were written in about 28 hours across 3 days, with no regard for fatigue.

First, create a file in your server and client folder each. These will contain the code necessary to initialize Satsuma on both ends:
```luau
-- server/net.luau
const satsuma = require("@pkg/satsuma").server
const events = require("@shared/events") -- this is a secret surprise i'll reveal in a couple of lines!

-- Create and initialize all data pertaining to the server
-- The 5/1000 here signifies 5 miliseconds, which is the maximum amount of time the server will allocate to processing inbound events per networking tick. Anything not processed is automatically moved onto the next networking tick to be processed
-- The processing time allocation isn't completely strict, as there's, to the author's knowledge, no available way to kill serdes in the midst of it running without sticking checks at every step of it, killing performance and readability
-- A sane default would be 2ms for a 60Hz networking loop - the time here is adjusted for a 24Hz loop
const server = satsuma.initialize(events, 5/1000)

-- Start the networking tick loop at the frequency of 24Hz (24 times a second)
-- This loop will automatically run all inbound & outbound processing, alongside refilling ratelimit
-- ⚠️ Beware, that refilling ratelimits will happen once a second, and not at the frequency of the networking loop
satsuma.begin_processing(server, 24)

-- Begins accepting and queueing any inbound events
satsuma.begin_input(server)

return server
```
```luau
-- client/net.luau
const satsuma = require("@pkg/satsuma").client
const events = require("@shared/events")

-- Create and initialize all data pertaining to the client
const client = satsuma.initialize(events)

-- Start the networking tick loop at the frequency of 24Hz (24 times a second)
-- This loop will automatically run all inbound & outbound processing
satsuma.begin_processing(client, 24)

-- Begins accepting and queueing any inbound events
satsuma.begin_input(server)

return server
```

Next, we'll set up a shared file containing all of the events we want to use.
```luau
-- shared/events.luau
const satsuma = require("@pkg/satsuma")
const t = satsuma.datatypes

return {
    my_event = satsuma.event {
        -- A struct!
        -- Structs can be defined with t.struct, though you may also simply use tables
        -- Beware that you cannot use this syntax inside an explicit t.struct / t.array / t.map
        data_type = {
            -- A string between 0 and 20 characters in length
            -- The length can be either a:
            --  -> literal, setting the exact length
            --  -> range, giving the length minimum and maximum bounds
            --  -> number type, specifying the length can at most be the maximum number a number type supports
            --     for example, uint8 would do 2^8-1 length at most
            -- Length defaults to a VLQ
            -- This applies to anything that accepts an optional length
            message = t.str(t.range(0, 20)),
            -- A double, the default number datatype in Luau
            sent_at = t.float64,
            -- An array of 16 bit integers
            -- The same principle applies as with structs - t.array may be used, though you may also use tables
            -- An optional length is accepted as a second value
            integers = { t.int16, t.literal(4) },
            -- An enum, allowing for either "fast" or "slow" to be passed
            -- ⚠️ Beware that for singletons, you have to type cast them, as otherwise they won't register as singletons
            kind = t.enum { "fast" :: "fast", "slow" :: "slow" },
            -- A tagged enum, allowing for multiple kinds of data
            packet = t.enum("size", {
                -- Each variant of a tagged enum must be a struct
                big = {
                    a_lot_of_data = t.buf(t.range(32_000, 64_000)),
                },
                small = {
                    a_bit_of_data = t.buf(t.range(0, 512)),
                }
            }),
            -- A literal
            -- This costs 0 bytes to send, as it's known on both sides ahead of time
            identifier = t.literal("my event"),
            -- A map of players to items
            -- The same principle applies as with structs and arrays - t.map may be used, though you may also use tables
            -- However, one limitation of this syntax is that you cannot define a length
            -- To do it, you must explicitly use t.map, albeit it has the pitfall of not being able to use the table syntax in it, as mentioned at the beginning of this file
            items = {
                -- ⚠️ Beware that explicit generic instantiation on t.instance is a must if you wish to get typechecking
                -- This comes from a limitation of the author not wanting to paste in a couple hundred lines of class names to instance types
                [t.instance<<Player>>("Player")] = {
                    name = t.str(t.range(0, 20)),
                    count = t.uint8,
                    rarity = t.enum { "common" :: "common", "rare" :: "rare", "epic" :: "epic", "legendary" :: "legendary" },
                    -- An optional previous owner
                    previous_owner = t.optional(t.instance<<Player>>("Player")),
                },
            },
        },
        -- The call budget defines how many times a player can send this event to the server
        -- The value provided here is a maximum amount of calls a player can have,
        call_budget = 3,
        -- being constantly refilled every second by the budget refill amount, allowing for both ratelimiting and accepting bursts
        budget_refill = 1,
        -- An optional setting allowing for the usage of polling
        -- This disables connecting to the event via [server/client].connect, and instead allows only for the usage of [server/client].iterate
        -- Useful for ECS
        use_polling = true,
        -- An optional maximum packet size is also accepted, maxing out at the uint16 limit of 2^16-1
        -- A VLQ isn't used instead of an uint16 for performance reasons
        -- This defaults to 8kB (8000 bytes), though it's automatically changed to the calculated static size of the provided data type, if one exists
        max_packet_size = 8_000,
    },

    -- This is a namespace
    -- Namespaces don't do anything special, except for allowing the organization of events, and potentially even importing them from other files
    --  -> for example, `meta = require("@self/meta")`
    -- All namespaces, no matter how deeply nested, are bubbled up to the top and processed as if all events were part of one namespace
    -- No naming conflicts happen, as names aren't used in any way internally, and exist only for organization by the user
    meta = {
        get_ready = satsuma.event {
            -- 0 bytes, literally nothing
            data_type = t.nothing,
            call_budget = 1,
            -- Can only be called once per server lifetime
            budget_refill = 0,
        }
    },
}
```
Not all datatypes which Satsuma provides were covered above, although it's a fair introduction.

Receiving data of an event is the same on both the client and the server, making use of `client.connect` / `client.iter` and `server.connect` / `server.iter` espectively.
The only difference, is that on the server a player whom the event has been sent by is provided.
Keep in mind that events without `use_polling` enabled cannot be iterated over, and events with `use_polling` enabled cannot be connected to.
A limit of one connection per event exists. You may bypass this by using a signal.
Connection callbacks are spawned in another Luau thread.
```luau
const satsuma = require("@pkg/satsuma").server
-- imagine if we could just do `const [.server, .events] = require("@server/net")` :<
const server = require("@server/net")
const events = require("@shared/events")

satsuma.connect(server, events.meta.get_ready, function(player)
    print(`{player} is now ready!`)
end)

for _, player, data in satsuma.iterate(server, events.my_event) do
    print(data)
end
```

For sending events, the client has the send function to its disposition, alongside the unreliable variant.
```luau
satsuma.send(client, events.meta.get_ready)
satsuma.send_unreliably(client, events.my_event, { ... })
```
The server has more functions, being able to:
```luau
-- Send an event to one player
satsuma.send(server, some_player, events.my_event, { ... })
-- Send an event to multiple players
satsuma.broadcast(server, { player_a, player_b, player_c }, events.my_event, { ... })
-- Or even to all players!
satsuma.broadcast_all(server, events.my_event, { ... })
```
The unreliable variants of each function also exist:
```luau
satsuma.send_unreliably(server, some_player, events.my_event, { ... })
satsuma.broadcast_unreliably(server, { player_a, player_b, player_c }, events.my_event, { ... })
satsuma.broadcast_all_unreliably(server, events.my_event, { ... })
```

Importantly, no distinction exists between reliable and unreliable events.\
Events are a description of data that may be sent alongside the network, alongside it's limitations, and reliably or unreliably are just methods with which they may be sent.

`_G.DEBUG = true` may be set before requiring Satsuma to catch any unintended usage that passes without it.

&nbsp;

## 📦 Installation

Satsuma is available for [pesde](https://pesde.dev/packages/marked/satsuma).

```sh
pesde add marked/satsuma
```

&nbsp;

## 📝 License

Satsuma is licensed under the [MIT License](LICENSE).

&nbsp;

## ⚒️ Contributing

This project does not allow contributions generated by large languages models (LLMs) and chatbots. This ban includes tools like ChatGPT, Ollama, Claude, Copilot, DeepSeek, and Devin AI. These steps are taken as precaution due to the potential negative influence of AI generated content on quality, as well as likely copyright violations. -- Taken from: [GNOME's libadwaita](https://gitlab.gnome.org/GNOME/libadwaita/-/blob/main/CONTRIBUTING.md?ref_type=heads#use-of-generative-ai)
