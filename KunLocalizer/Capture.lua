local K = KunLocalizer
K.captureSeen, K.captureBytes = {}, 64
function K:CaptureMissing(adapterID, key, source, locale)
    if not self:Identifier(adapterID) or not self:Identifier(key) or not self:String(source, 512) then return false end
    local a = self.adapters[adapterID]
    local config = a and self:GetConfiguration(a.target_addon, a.target_version)
    locale = locale or (config and config.target_locale) or GetLocale()
    if not self.dbReady or not a or a.segments[key] ~= source or not self:Identifier(locale) then return false end
    if self:Translate(a.target_addon, a.target_version, key, source, locale) ~= source then return false end
    local identity = adapterID .. ":" .. locale .. ":" .. key .. ":" .. source
    local size = 4 * (#adapterID + #a.target_addon + #a.target_version + #locale + #key + #source) + 256
    if self.captureSeen[identity] or #KunLocalizerDB.entries >= 256 or self.captureBytes + size > 65536 then return false end
    table.insert(KunLocalizerDB.entries, {adapter_id = adapterID, target_addon = a.target_addon,
        target_version = a.target_version, client_interface = 30300, locale = locale, key = key, source = source})
    self.captureSeen[identity], self.captureBytes = true, self.captureBytes + size
    return true
end
