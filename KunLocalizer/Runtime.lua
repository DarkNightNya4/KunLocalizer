local K = KunLocalizer
function K:Refresh()
    if not self.loggedIn or self.refreshing then return end
    self.refreshing = true
    for id, a in pairs(self.adapters) do
        if IsAddOnLoaded(a.target_addon) and GetAddOnMetadata(a.target_addon, "Version") == a.target_version then
            -- Adapter failures stay local. No global SetText hook or protected UI access.
            pcall(a.apply, self, id)
        end
    end
    self.refreshing = false
end
