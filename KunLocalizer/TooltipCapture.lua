-- Opt-in one-entity capture. SavedVariables are written by WoW, never by desktop live edits.
local K,T=KunLocalizer,KunLocalizer.Tooltips
local C={armed=false,hooked={}}
K.TooltipCapture=C
local function report(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("KunLocalizer: "..text) end
end
local function diagnostic(text)
    local plain=text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):lower()
    return plain:match("^%s*spell%s*id%s*:") or plain:match("^%s*item%s*id%s*:")
        or plain:match("^%s*图标路径%s*:") or plain:match("^%s*icon%s*path%s*:")
        or plain:match("^%s*interface[\\/]icons[\\/]")
end
function C:Stop()self.armed=false;self.config=nil end
function C:Read(tip,kind,id)
    -- 手动与被动采集共用白名单、文本预算、诊断行排除和原文读取逻辑。
    if not T:IsAllowed(tip) or T:Entity(tip,kind)~=id then return nil end
    local name=tip:GetName();local count=tip:NumLines()
    if type(name)~="string" or type(count)~="number" or count<1 or count>40 or count~=math.floor(count) then
        return nil
    end
    local entries,bytes={},1024
    for n=1,count do
        for _,side in ipairs({"Left","Right","Rank"})do
            local label=T:Region(tip,kind,side,n)
            if label and label.IsProtected and not label:IsProtected() and label.GetText then
                local source=label:GetText()
                -- 兼容本模块已经显示的译文，始终采原文而非双语拼接/覆盖结果。
                local state=T.states[tip];local old=state and state.id==id and state.kind==kind and state.lines[side..n]
                if old and old.label==label and source==old.text then source=old.source end
                if type(source)=="string" and source:match("%S") and not diagnostic(source)
                    and (side~="Rank" or T:IsRankSource(source)) then
                    if not K:String(source,512) then return nil end
                    bytes=bytes+4*(#source+64)+256
                    if bytes>60000 then return nil end
                    entries[#entries+1]={kind=kind,id=id,side=side:lower(),line=n,source=source}
                end
            end
        end
    end
    if #entries==0 or #entries>80 then return nil end
    return entries
end
function C:Capture(tip,kind)
    if not self.armed then return end
    if GetTime()>=self.deadline or InCombatLockdown() then self:Stop();return end
    if kind~=self.kind or not T:IsAllowed(tip) or T:Entity(tip,kind)~=self.id then return end
    local config=self.config;local id=self.id
    self:Stop() -- 单对象仍只消费一次，失败不自动重试或覆盖旧记录。
    local live=K:GetConfiguration("Grimfall.Tooltips",config.target_version)
    if not live or K.configurationConflicts["Grimfall.Tooltips:"..config.target_version]
        or live.profile_id~=config.profile_id or live.revision~=config.revision then return end
    if not K:CaptureEnabled(live,kind,id,false,T:ObservedCategory(tip,kind,id))then return end
    local entries=self:Read(tip,kind,id)
    if not entries then report("Capture failed: unsupported or oversized tooltip.");return end
    KunLocalizerTooltipDB={schema=1,profile_id=config.profile_id,revision=config.revision,
        content_id=config.target_version,source_locale=config.source_locale,target_locale=config.target_locale,
        kind=kind,id=id,entries=entries}
    report("Captured "..#entries.." rows. Exit normally or reload to save; preview the file in KunBox.")
    return true
end
function C:Arm(content,kind,id,tip)
    self:Stop()
    if not K.loggedIn or InCombatLockdown() or (kind~="item" and kind~="spell") or type(id)~="number"
        or id<1 or id>2147483647 or id~=math.floor(id) or not T:IsAllowed(tip) then return false end
    local config=K:GetConfiguration("Grimfall.Tooltips",content)
    if not config or K.configurationConflicts["Grimfall.Tooltips:"..content] then return false end
    -- 未选类别不启动采集，避免桌面关闭后游戏仍继续获取该类别。
    if not K:CaptureEnabled(config,kind,id,false,T:ObservedCategory(tip,kind,id))then return false end
    T:Stop() -- Never capture our own bilingual/translated presentation.
    if self.hooked[tip]=="failed" then return false end
    if not self.hooked[tip] then
        self.hooked[tip]="failed"
        local ok=pcall(function()
            for _,category in ipairs({"item","spell"})do
                local value=category
                tip:HookScript(value=="item" and "OnTooltipSetItem" or "OnTooltipSetSpell",function(frame)
                    local success=pcall(C.Capture,C,frame,value)
                    if not success then C:Stop();report("Capture failed: tooltip callback error.")end
                end)
            end
        end)
        if not ok then return false end
        self.hooked[tip]=true
    end
    self.config=config;self.kind=kind;self.id=id;self.deadline=GetTime()+60;self.armed=true
    report("Capture armed for "..kind.." "..id.." for 60 seconds. Reopen its tooltip. This replaces the previous capture only after success.")
    return true
end
function C:CaptureTalent(content,id,tip)
    -- 只采玩家已展开的完整天赋提示框，避免把API效果等级当作可见已学等级。
    self:Stop()
    if not T:IsAllowed(tip) or type(tip.IsShown)~="function" or not tip:IsShown()
        or T:Entity(tip,"spell")~=id then return false end
    local label=T:Region(tip,"spell","Rank",1)
    if not label or type(label.GetText)~="function" then return false end
    if not self:Arm(content,"spell",id,tip) then return false end
    -- Arm会先恢复自身译文；只接受实际可见的原始等级，不从Spell Rank推断。
    if not T:IsRankSource(label:GetText())then self:Stop();return false end
    return self:Capture(tip,"spell")
end
SLASH_KUNLOCALIZERTOOLTIPCAPTURE1="/kunloccapture"
SlashCmdList.KUNLOCALIZERTOOLTIPCAPTURE=function(command)
    if command=="stop" then C:Stop();report("Capture stopped.");return end
    local kind,number=command:match("^(%a+)%s+(%d+)%s*$")
    local content
    for _,config in pairs(K.configurations)do
        if config.target_addon=="Grimfall.Tooltips" then
            if content then report("Multiple content profiles; resolve them in KunBox before capture.");return end
            content=config.target_version
        end
    end
    if kind=="talent" then
        local ok=content and C:CaptureTalent(content,tonumber(number),GameTooltip)
        if not ok then report("Talent not captured. Hover its complete tooltip with visible Rank, then use /kunloccapture talent ID.")end
        return
    end
    if not content or not C:Arm(content,kind,tonumber(number),GameTooltip) then
        report("Not armed. Load a KunBox tooltip capture profile, then use /kunloccapture spell 16342 or /kunloccapture item ID.")
    end
end
local timer=CreateFrame("Frame")
timer:RegisterEvent("PLAYER_LEAVING_WORLD");timer:RegisterEvent("PLAYER_REGEN_DISABLED")
timer:SetScript("OnEvent",function()C:Stop()end)
timer:SetScript("OnUpdate",function()if C.armed and GetTime()>=C.deadline then C:Stop();report("Capture timed out.")end end)
