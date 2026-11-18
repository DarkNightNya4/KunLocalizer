-- Explicitly started, bounded tooltip adapter. No global SetText/handler replacement.
local K=KunLocalizer
-- 延迟复查只保存白名单提示框任务，不建立全局文本Hook。
local T={enabled=false,hooked={},states={},pending={},errors=0}
K.Tooltips=T
local namespace="Grimfall.Tooltips"
local function integer(n,max)
    return type(n)=="number" and n>0 and n==math.floor(n) and n<=max
end
local function safe(region)
    return region and type(region.IsProtected)=="function" and not region:IsProtected()
end
local function allowed(tip)
    for _,name in ipairs({"GameTooltip","ItemRefTooltip","ShoppingTooltip1","ShoppingTooltip2","ShoppingTooltip3"})do
        if tip==_G[name] then return safe(tip) end
    end
    return false
end
local function entity(tip,kind)
    if kind=="item" and type(tip.GetItem)=="function" then
        local ok,_,link=pcall(tip.GetItem,tip)
        local id=ok and type(link)=="string" and tonumber(link:match("item:(%d+):"))
        if integer(id,2147483647) then return id end
    elseif kind=="spell" and type(tip.GetSpell)=="function" then
        local ok,_,a,b=pcall(tip.GetSpell,tip)
        if not ok then return nil end
        local second=integer(a,2147483647) and a or nil
        local third=integer(b,2147483647) and b or nil
        if second and third and second~=third then return nil end -- Ambiguous client variant.
        return third or second
    end
end
local function combat()return type(InCombatLockdown)~="function" or InCombatLockdown()end
function T:Entity(tip,kind)return entity(tip,kind)end
function T:IsAllowed(tip)return allowed(tip)end
function T:Region(tip,kind,side,line,includeHidden)
    if side~="Rank" then return _G[tip:GetName().."Text"..side..line] end
    -- 实机确认的Grimfall天赋等级是专用直属FontString，不挪用标准左右列行号。
    if tip~=GameTooltip or kind~="spell" or line~=1 then return nil end
    local label=_G.ClasslessFrame_FreepickTalentTooltipRankOverlay
    if safe(label) and type(label.GetParent)=="function" and label:GetParent()==tip
        and type(label.IsObjectType)=="function" and label:IsObjectType("FontString")
        and type(label.IsShown)=="function" and (includeHidden or label:IsShown()) then return label end
end
function T:IsRankSource(text)
    -- 已学数可以为0；总等级必须有限，且不能用GetSpell返回值代替原文。
    if type(text)~="string" then return false end
    local current,total=text:match("^Rank%s+(%d+)/(%d+)$")
    current,total=tonumber(current),tonumber(total)
    return current~=nil and total~=nil and total>=1 and total<=100 and current<=total
end
function T:ObservedCategory(tip,kind,id)
    if entity(tip,kind)~=id then return nil end
    local label=self:Region(tip,kind,"Rank",1)
    if not label or type(label.GetText)~="function" then return nil end
    local source=label:GetText();local state=self.states[tip]
    local old=state and state.id==id and state.kind==kind and state.lines.Rank1
    if old and old.label==label and old.text==source then source=old.source end
    if self:IsRankSource(source)then return "talent"end
end
local function numbers(text)
    -- 等级文字翻译可以换语言，但已学数/总等级必须按顺序保持。
    local result={};for value in text:gmatch("%d+")do result[#result+1]=value end
    return table.concat(result,"\0")
end
local function tokens(text)
    local out,p={},1
    while true do
        local at=text:find("|",p,true)
        if not at then return table.concat(out,"\0") end
        local rest=text:sub(at)
        local token=rest:match("^|H.-|h.-|h") or rest:match("^|T.-|t") or rest:match("^|c%x%x%x%x%x%x%x%x")
            or rest:match("^|r") or rest:match("^||")
        if not token then return nil end
        out[#out+1]=token;p=at+#token
    end
end
local function dispatch(tip,kind)
    local ok=pcall(T.Apply,T,tip,kind)
    if not ok then T.errors=T.errors+1;T.enabled=false;T.busy=false end
    -- 部分扩展会在首次事件之后追加文字；限定两秒内最多十次复查。
    local state=T.states[tip]
    if ok and T.enabled and state and type(GetTime)=="function" then
        T.pending[tip]={kind=kind,id=state.id,deadline=GetTime()+2,next=GetTime()+0.2,remaining=10}
    end
end
local function appendedTranslation(config,kind,id,side,source)
    -- 仅复用同一内容版本、物品/技能、同侧且原文完全相同的唯一审校译文。
    -- 不以关键词猜测，不跨实体查找，存在不同译文时拒绝选择。
    local entries=K.dictionary[namespace..":"..config.target_version..":"..config.target_locale] or {}
    local prefix=kind.."."..string.format("%d",id).."."..side:lower().."."
    local found
    for key,row in pairs(entries)do
        local tail=key:sub(#prefix+1)
        if key:sub(1,#prefix)==prefix and tail:match("^%d+$") and integer(tonumber(tail),40)
            and row.source==source then
            if found and found~=row.text then return source end
            found=row.text
        end
    end
    return found or source
end
function T:Apply(tip,kind)
    if not self.enabled or self.busy or not K.loggedIn or combat() or not allowed(tip) then return end
    local config=K:GetConfiguration(namespace,self.content)
    if not config or K.configurationConflicts[namespace..":"..self.content] then self:Stop();return end
    -- v1/v2保持兼容；v3及以上严格遵从桌面项目的类别开关。
    local id=entity(tip,kind)
    if not K:TranslationEnabled(config,kind,id)then return end
    if K.EntityRefresh and K.EntityRefresh:Blocked(config,kind,id)then return end
    if not id or type(tip.GetName)~="function" or type(tip.NumLines)~="function" then return end
    local count=tip:NumLines();local name=tip:GetName()
    if not integer(count,40) or type(name)~="string" then return end
    local previous=self.states[tip]
    -- 固定首次布局边界，只有后追加的新行允许使用同实体原文精确回退。
    local same=previous and previous.id==id and previous.kind==kind
    local state={id=id,kind=kind,initialCount=same and previous.initialCount or count,lines={}};self.states[tip]=state
    self.busy=true
    for n=1,count do
        for _,side in ipairs({"Left","Right","Rank"})do
            local label=self:Region(tip,kind,side,n)
            if safe(label) and type(label.GetText)=="function" and type(label.SetText)=="function" then
                local source=label:GetText();local slot=side..n
                local old=previous and previous.id==id and previous.kind==kind and previous.lines[slot]
                if old and old.label==label and source==old.text then source=old.source end
                if K:String(source,512) and (side~="Rank" or self:IsRankSource(source)) then
                    local key=kind.."."..string.format("%d",id).."."..side:lower().."."..n
                    local text=K:Translate(namespace,self.content,key,source)
                    if text==source and n>state.initialCount then
                        text=appendedTranslation(config,kind,id,side,source)
                    end
                    if text~=source and K:String(text,4096) and tokens(source) and tokens(source)==tokens(text)
                        and (side~="Rank" or numbers(source)==numbers(text)) then
                        -- 写入前记录原文；复查发现已是目标文本时不重复写入或拼接双语。
                        -- 面板会话样式不更改项目配置；无启动模块时仍使用桌面默认。
                        local mode=K.Startup and K.Startup:DisplayMode(config) or config.display_mode
                        local display=mode=="bilingual" and (source.."\n"..text) or text
                        state.lines[slot]={label=label,source=source,text=display,rank=side=="Rank"}
                        local ok=true
                        if label:GetText()~=display then ok=pcall(label.SetText,label,display)end
                        if not ok then self.errors=self.errors+1;self.enabled=false;self.busy=false;return end
                    end
                end
            end
        end
    end
    -- 等级区域临时隐藏时保留原文恢复记录，不在隐藏区域重新写译文。
    local oldRank=same and previous.lines.Rank1
    if oldRank and not state.lines.Rank1 and self:Region(tip,kind,"Rank",1,true)==oldRank.label
        and oldRank.label:GetText()==oldRank.text then state.lines.Rank1=oldRank end
    self.busy=false
end
function T:RestoreTip(tip,state)
    -- 只恢复仍属于同一实体且仍为本插件译文的未保护文字，外部改动不覆盖。
    if combat() or not allowed(tip) or entity(tip,state.kind)~=state.id then return end
    for _,row in pairs(state.lines)do
        if safe(row.label) and (not row.rank or self:Region(tip,state.kind,'Rank',1,true)==row.label)
            and row.label:GetText()==row.text then pcall(row.label.SetText,row.label,row.source) end
    end
end
function T:RefreshDisplay(config)
    if not self.enabled or combat() or self.content~=config.target_version then return end
    for tip,state in pairs(self.states)do
        if not K:TranslationEnabled(config,state.kind,state.id) then
            self:RestoreTip(tip,state);self.pending[tip]=nil
            -- 留有限实体标识以便同一可见提示框重新勾选后恢复；清空事件仍会丢弃它。
            self.states[tip]={id=state.id,kind=state.kind,initialCount=state.initialCount,lines={}}
        else self:Apply(tip,state.kind) end
    end
end
function T:Stop()
    self.enabled=false
    -- 关闭翻译和开始采集时一并取消延迟任务，禁止回调重新启用。
    self.pending={}
    -- Never restore stale/reused controls or change protected/combat UI.
    if not combat() then
        for tip,state in pairs(self.states)do
            self:RestoreTip(tip,state)
        end
    end
    self.states={};self.content=nil
end
function T:Start(content,tip)
    self:Stop()
    if K.TooltipCapture and K.TooltipCapture.armed then return false end
    if not K.loggedIn or combat() or type(content)~="string" or #content~=64 or content:find("[^0-9a-f]")
        or not allowed(tip) or type(tip.HookScript)~="function" then return false end
    local config=K:GetConfiguration(namespace,content)
    local dictionary=K.dictionary[namespace..":"..content..":"..(config and config.target_locale or "")]
    if not config or K.configurationConflicts[namespace..":"..content] or not dictionary or not next(dictionary) then return false end
    if self.hooked[tip]=="failed" then return false end
    if not self.hooked[tip] then
        self.hooked[tip]="failed"
        local ok=pcall(function()
            tip:HookScript("OnTooltipSetItem",function(frame)dispatch(frame,"item")end)
            tip:HookScript("OnTooltipSetSpell",function(frame)dispatch(frame,"spell")end)
            -- 提示框清空后，旧实体的状态和复查任务都不能沿用。
            tip:HookScript("OnTooltipCleared",function(frame)T.states[frame]=nil;T.pending[frame]=nil end)
        end)
        if not ok then return false end -- Existing callbacks remain untouched; partial hooks stay inert.
        self.hooked[tip]=true
    end
    self.content=content;self.enabled=true;return true
end
local lifecycle=CreateFrame("Frame")
lifecycle:RegisterEvent("PLAYER_LEAVING_WORLD")
lifecycle:SetScript("OnEvent",function()T:Stop()end)
-- 使用3.3.5a已有的OnUpdate/GetTime；只运行显式开启后的有限提示框任务。
lifecycle:SetScript("OnUpdate",function()
    if not next(T.pending) then return end
    local now=GetTime()
    for tip,job in pairs(T.pending)do
        if not T.enabled or combat() or not allowed(tip) or type(tip.IsShown)~="function" or not tip:IsShown()
            or entity(tip,job.kind)~=job.id or now>job.deadline or job.remaining<=0 then
            T.pending[tip]=nil
        elseif now>=job.next then
            job.remaining=job.remaining-1;job.next=now+0.2
            -- 延迟复查不重新排队；异常立即停止，沿用原错误隔离边界。
            local ok=pcall(T.Apply,T,tip,job.kind)
            if not ok then T.errors=T.errors+1;T.enabled=false;T.busy=false;T.pending={} end
        end
    end
end)
SLASH_KUNLOCALIZERTOOLTIPS1="/kunloctooltips"
SlashCmdList.KUNLOCALIZERTOOLTIPS=function(command)
    -- 显式手动关闭在自动模式本会话内仍有效，不被后台启动检查反向开启。
    if K.Startup and (command=='on' or command=='off') then K.Startup.blocked.tooltip=command=='off' end
    if command=="off" then T:Stop();return end
    if command~="on" then return end
    local content
    for _,config in pairs(K.configurations)do
        if config.target_addon==namespace then
            if content then return end
            content=config.target_version
        end
    end
    local ok=content and T:Start(content,GameTooltip)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(ok and "KunLocalizer: tooltip translation enabled for the loaded profile (game result unverified)."
            or "KunLocalizer: not enabled; check profile, dictionary, capture state and combat status.")
    end
end
