local K = KunLocalizer
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "KunLocalizer" then K:InitializeDB() end
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and name == "KunLocalizer" and IsLoggedIn()) then
        K.loggedIn = true
        K:RestoreCapture()
    end
    K:Refresh()
    -- 配置插件可能晚于核心加载，登录及加载事件后再检查用户的显式采集选择。
    if K.AutoCapture and (event=="PLAYER_LOGIN" or event=="ADDON_LOADED") then K.AutoCapture:MaybeStart()end
end)
