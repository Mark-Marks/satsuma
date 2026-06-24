--!optimize 2
export type TokenBucket = {
    read capacity: number,
    read refill_rate: number,
    read tokens: number,
}

type WritableBucket = TokenBucket & {
    tokens: number,
}

const function construct(capacity: number, refill_rate: number): TokenBucket
    return {
        capacity = capacity,
        refill_rate = refill_rate,
        tokens = capacity,
    }
end

--- Refils the token bucket with a preset amount of refill tokens.
--- Ideally, this should be regularly called every certain amount of time.
@native
const function refill(bucket: TokenBucket)
    -- Should be a simple equality comparison, although greater than or equal is used as a safeguard
    if bucket.tokens >= bucket.capacity then
        return
    end

    (bucket :: WritableBucket).tokens =
        math.min(bucket.tokens + bucket.refill_rate, bucket.capacity)
end

@native
const function remove(bucket: TokenBucket, tokens: number): boolean
    if bucket.tokens < tokens then
        return false
    end

    (bucket :: WritableBucket).tokens -= tokens
    return true
end

return table.freeze {
    construct = construct,
    refill = refill,
    remove = remove,
}
