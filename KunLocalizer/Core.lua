KunLocalizer = { api_version = 1, packs = {}, adapters = {}, loggedIn = false }
local K = KunLocalizer
function K:Identifier(v)
    return type(v) == "string" and #v > 0 and #v <= 64 and not string.find(v, "[^%w_.%-]")
end
function K:String(v, limit)
    return type(v) == "string" and #v > 0 and #v <= limit
        and not string.find(v, "[%z\1-\8\11\12\14-\31]")
end
