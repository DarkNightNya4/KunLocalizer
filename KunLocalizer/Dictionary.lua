local K = KunLocalizer
local function scope(addon, version, locale) return addon .. ":" .. version .. ":" .. locale end
K.dictionary = {}
function K:RegisterPack(pack)
    if type(pack) ~= "table" or pack.schema ~= 1 or pack.client_interface ~= 30300
        or not self:Identifier(pack.pack_id) or self.packs[pack.pack_id]
        or not self:Identifier(pack.target_addon) or not self:Identifier(pack.target_version)
        or not self:Identifier(pack.locale) or type(pack.entries) ~= "table" then return false end
    local name = scope(pack.target_addon, pack.target_version, pack.locale)
    local old, pending, count, bytes = self.dictionary[name] or {}, {}, 0, 0
    for i, entry in pairs(pack.entries) do
        count = count + 1
        if type(i) ~= "number" or i < 1 or i > 256 or i ~= math.floor(i)
            or type(entry) ~= "table" or not self:Identifier(entry.key)
            or not self:String(entry.source, 512) or not self:String(entry.text, 4096)
            or pending[entry.key] or old[entry.key] then return false end
        bytes = bytes + 4 * (#entry.key + #entry.source + #entry.text) + 256
        if bytes > 65536 then return false end
        pending[entry.key] = {source = entry.source, text = entry.text}
    end
    if count == 0 or count > 256 then return false end
    for i = 1, count do if not pack.entries[i] then return false end end
    for key, value in pairs(pending) do old[key] = value end
    self.dictionary[name], self.packs[pack.pack_id] = old, true
    if self.loggedIn then self:Refresh() end
    return true
end
function K:Translate(addon, version, key, source, locale)
    if not self:Identifier(addon) or not self:Identifier(version) or not self:Identifier(key) then return source end
    if self.configurationConflicts[addon..":"..version] then return source end
    local config = self:GetConfiguration(addon, version)
    -- 公共翻译接口也遵守分类开关，避免适配器外调用绕过桌面设置。
    if config and addon=="Grimfall.Tooltips" then
        local kind,id=key:match("^(%a+)%.(%d+)%.")
        if not self:TranslationEnabled(config,kind,tonumber(id))then return source end
        -- 刷新对象在新语言包确认回执到达前回退原文，防止沿用已知错误译文。
        if self.EntityRefresh and self.EntityRefresh:Blocked(config,kind,tonumber(id))then return source end
    end
    locale = locale or (config and config.target_locale) or GetLocale()
    if not self:Identifier(locale) then return source end
    local entries = self.dictionary[scope(addon, version, locale)]
    local entry = entries and entries[key]
    if entry and entry.source == source then return entry.text end
    return source
end
