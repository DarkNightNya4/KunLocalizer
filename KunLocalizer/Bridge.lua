local K = KunLocalizer
function K:InitializeDB()
    -- Revalidate persisted data. Never retain arbitrary fields or player/account details.
    local previous = KunLocalizerDB
    KunLocalizerDB = {schema = 1, entries = {}}
    self.captureSeen, self.captureBytes, self.dbReady = {}, 64, true
    self.previousCapture = previous
end
function K:RestoreCapture()
    local old = self.previousCapture
    self.previousCapture = nil
    if type(old) ~= "table" or old.schema ~= 1 or type(old.entries) ~= "table" then return end
    for i = 1, 256 do
        local row = old.entries[i]
        if row == nil then break end
        if type(row) == "table" then
            local a = self.adapters[row.adapter_id]
            if a and row.target_addon == a.target_addon and row.target_version == a.target_version
                and row.client_interface == 30300 then
                self:CaptureMissing(row.adapter_id, row.key, row.source, row.locale)
            end
        end
    end
end
