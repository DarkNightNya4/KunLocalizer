local K = KunLocalizer
-- Only reviewed, installed Lua adapters may call this. Packs contain no callbacks.
function K:RegisterAdapter(id, adapter)
    if not self:Identifier(id) or self.adapters[id] or type(adapter) ~= "table"
        or not self:Identifier(adapter.target_addon) or not self:Identifier(adapter.target_version)
        or type(adapter.apply) ~= "function" or type(adapter.segments) ~= "table" then return false end
    local segments, count = {}, 0
    for key, source in pairs(adapter.segments) do
        count = count + 1
        if count > 256 or not self:Identifier(key) or not self:String(source, 512) then return false end
        segments[key] = source
    end
    self.adapters[id] = { target_addon = adapter.target_addon, target_version = adapter.target_version,
        segments = segments, apply = adapter.apply }
    if self.loggedIn then self:Refresh() end
    return true
end
