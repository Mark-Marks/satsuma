--# selene: allow(undefined_variable)
export type function strip_ghost(t: type)
    if t.tag ~= "intersection" then
        return t :: type
    end

    for _, component in t:components() do
        if component.tag ~= "table" then
            return component :: type
        end
    end

    return t :: type
end

@native
const function strip_ghost<T>(t: T): strip_ghost<T>
    return t
end

export type function insert_ghost(t: type, template: type)
    local ghost = template
    if template.tag == "intersection" then
        for _, component in template:components() do
            if component.tag ~= "table" then
                continue
            end
            ghost = component
        end
    end

    return types.intersectionof(t, ghost)
end

@native
const function insert_ghost<T>(t: strip_ghost<T>): insert_ghost<strip_ghost<T>, T>
    return t
end

export type function writable(t: type)
    if t.tag ~= "table" then
        return t
    end

    local new_table = types.newtable()
    for key, value in t:properties() do
        const prop = value.read or value.write
        if not prop then
            continue
        end

        new_table:setproperty(key, writable(prop))
    end

    const indexer = t:indexer()
    if indexer then
        new_table:setindexer(indexer.index, indexer.readresult)
    end

    return new_table :: any
end

export type function tagged_enum(tag: type, kinds: type): type
    assert(kinds.tag == "table", "Kinds must be a table")
    assert(
        tag.tag == "singleton" and type(tag:value()) == "string",
        "Tag must be a stringleton"
    )

    local enums = {}

    for key, rw in kinds:properties() do
        const read = rw.read
        if not read or read.tag ~= "table" then
            error(
                `Expected a table at key {key:value()} of kinds, got {read and read.tag or nil}`
            )
        end

        read:setproperty(tag, key)
        table.insert(enums, read)
    end

    return types.unionof(unpack(enums))
end

export type function reveal_type(t: type)
    if t.tag ~= "intersection" then
        if t.tag ~= "table" then
            return t
        end

        local revealed_table = types.newtable()
        for key, rw in t:properties() do
            const read = rw.read
            if not read then
                continue
            end

            revealed_table:setproperty(key, reveal_type(read))
        end

        const indexer = t:indexer()
        if indexer then
            const index: type = reveal_type(indexer.index)
            const read: type = reveal_type(indexer.readresult)

            if index.tag == "number" and read.tag == "union" then
                const components = read:components()
                const n_components = #components

                if n_components == 2 then
                    const component_1, component_2 =
                        components[1], components[2]
                    local value_component
                    if
                        component_1.tag == "number"
                        and component_2.tag ~= "number"
                    then
                        value_component = component_2
                    else
                        value_component = component_1
                    end

                    revealed_table:setindexer(
                        index,
                        reveal_type(value_component)
                    )
                    return revealed_table :: any
                end

                local unmarked_components = {}
                for _, component in components do
                    if
                        component.tag == "singleton"
                        and (
                            component:value()
                                == "一个年轻人 approves of this marker"
                            or component:value()
                                == "一个老人 approves of this marker"
                        )
                    then
                        continue
                    end
                    table.insert(unmarked_components, component)
                end

                revealed_table:setindexer(
                    index,
                    reveal_type(types.unionof(unpack(unmarked_components)))
                )
                return revealed_table :: any
            end

            revealed_table:setindexer(index, read)
        end

        return revealed_table :: any
    end

    const ghost_identifier_key = types.singleton("__DISTINCT")
    const ghost_type_key = types.singleton("__TYPE")

    const components = t:components()
    for _, component in components do
        if component.tag ~= "table" then
            continue
        end

        const identifier_prop = component:readproperty(ghost_identifier_key)
        if not identifier_prop then
            continue
        end

        if
            identifier_prop.tag ~= "singleton"
            or identifier_prop:value() ~= "serdes_id"
        then
            continue
        end

        const type = component:readproperty(ghost_type_key)
        if not type then
            continue
        end

        return reveal_type(type)
    end

    return t :: any
end

export type EventId = number & { __DISTINCT: "event_id" }
export type SerdesId<T = unknown> =
    number
    & { __DISTINCT: "serdes_id", __TYPE: T }
export type EnumMarkerOne = "一个年轻人 approves of this marker"
export type EnumMarkerTwo = "一个老人 approves of this marker"
export type Reference = number & { __DISTINCT: "reference" }

export type Event<T = unknown> = {
    read id: EventId,
    read serdes: SerdesId<reveal_type<T>>,
    read bucket: {
        read capacity: number,
        read refill_rate: number,
    },
    read use_polling: boolean,
    read max_packet_size: number,
}

export type Namespace = {
    [string]: Event | Namespace,
}

export type function extract_my_god_damned_data(t: type)
    const s = t:readproperty(types.singleton("serdes"))
    assert(s)

    return reveal_type(s)
end

const helpers = table.freeze {
    strip_ghost = strip_ghost,
    insert_ghost = insert_ghost,
}

return helpers
