-- Grimfall已定位的技能/Rune列表显示层；不替换原始文字或全局SetText。
local K=KunLocalizer
local L={enabled=false,states={},elapsed=0,cache={},owned={},created=0,reason='idle',rendered=0};K.ListNames=L
local rootName='ClasslessFrame_FreepickRunicEnhancementsJournaliconsFrame'
local profiles={
    {name=rootName,prefix=rootName..'spellButton',kind='CheckButton'},
    -- 实机定位：命名ScrollFrame里的滚动子容器和技能按钮均匿名。
    {name='ClasslessFrame_FreepickClassSpecSpellListScrollFrame',scroll=true,kind='Button'},
}
local function container(profile)
    local root=_G[profile.name]
    if not root then return nil end
    if profile.scroll then
        if type(root.GetScrollChild)~='function' or type(root.IsObjectType)~='function' or not root:IsObjectType('ScrollFrame')then return nil end
        local ok,child=pcall(root.GetScrollChild,root)
        if not ok or not child or type(child.GetParent)~='function' or child:GetParent()~=root then return nil end
        return child
    end
    return root
end
local function safe(object)
    return object and type(object.IsProtected)=='function' and not object:IsProtected()
end
local function visible(object)
    -- IsVisible包含父容器状态，避免隐藏页面的子控件仍被算作实际显示。
    if type(object.IsVisible)=='function'then return object:IsVisible()end
    return object:IsShown()
end
local function member(label,button,root,row)
    if not safe(label) or not safe(button) or label:GetParent()~=button then return false end
    if row then
        if not safe(row) or button:GetParent()~=row or row:GetParent()~=root then return false end
    elseif button:GetParent()~=root then return false end
    -- 检查列表及自定义父级；UIParent只是未被修改的公共顶层，不作为写入目标。
    -- 真实客户端UIParent受保护，不能据此误判所有未保护子区域也不可修改。
    local current=root
    for _=1,16 do
        if not current then return true end
        if current==_G.UIParent and current~=root then return true end
        if not safe(current)then return false end
        current=current:GetParent()
    end
    return false
end
function L:Restore(label,state)
    -- 只恢复本模块隐藏且仍保持alpha=0的原标签，不覆盖外部重新设置的透明度。
    if not member(label,state.button,state.root,state.row) or not safe(state.overlay)then return false end
    state.overlay:Hide()
    if label:GetAlpha()==0 then label:SetAlpha(state.alpha)end
    return true
end
function L:Clear()
    for label,state in pairs(self.states)do if self:Restore(label,state)then self.states[label]=nil end end
end
function L:Stop()self.enabled=false;self:Clear()end
function L:Names(config)
    -- 仅复用当前语言包的唯一技能标题，存在同名多实体时不猜测来源。
    local result={}
    for key,row in pairs(K.dictionary['Grimfall.Tooltips:'..config.target_version..':'..config.target_locale] or {})do
        local id=key:match('^spell%.([1-9]%d*)%.left%.1$')
        if id then
            if result[row.source]~=nil then result[row.source]=false
            else result[row.source]={key=key,source=row.source}end
        end
    end
    return result
end
function L:RenderProfile(profile,config,names,seen)
    local root=container(profile)
    if not root then return end
    if not safe(root)then self.reason='protected-root';return end
    if not visible(root)then return end
    local buttons={root:GetChildren()};self.reason='no-match';self.phase='regions'
    -- 单列表超限不影响另一个已经验证的列表，不扩张扫描范围。
    if #buttons>128 then self.reason='list-limit';return end
    for _,button in ipairs(buttons)do
        local name=button:GetName()
        local slot=profile.prefix and type(name)=='string' and name:sub(1,#profile.prefix)==profile.prefix and name:sub(#profile.prefix+1)
        local matches=profile.scroll and name==nil or (slot and slot:match('^[1-9]%d*$') and tonumber(slot)<=128)
        if matches and safe(button)
            and button:GetParent()==root and visible(button) and button:IsObjectType(profile.kind)then
            -- Rune文字直属CheckButton；技能文字位于直属普通Frame中，排除子Button。
            local owners=profile.scroll and {button:GetChildren()} or {button}
            if #owners<=8 then for _,owner in ipairs(owners)do
            local nested=profile.scroll and owner:GetParent()==button and owner:GetObjectType()=='Frame'
            if (not profile.scroll or nested) and safe(owner) and visible(owner)then
            local regions={owner:GetRegions()}
            if #regions<=32 then for _,label in ipairs(regions)do
                local entryButton=profile.scroll and button or nil
                if not self.owned[label] and label:IsObjectType('FontString') and member(label,owner,root,entryButton) and label:IsShown()then
                    local original=label:GetText();local row=names[original]
                    local text=row and K:Translate('Grimfall.Tooltips',self.content,row.key,original)
                    if text and text~=original then
                        self.phase='create'
                        local state=self.states[label]
                        if not state then
                            local overlay=self.cache[label]
                            if not overlay then
                                if self.created>=128 then self:Stop();return end
                                overlay=owner:CreateFontString(nil,'OVERLAY');self.cache[label]=overlay;self.owned[overlay]=true;self.created=self.created+1
                            end
                            state={overlay=overlay,alpha=label:GetAlpha(),root=root,button=owner,row=entryButton};self.states[label]=state
                        end
                        local overlay=state.overlay
                        self.phase='layout'
                        if label:GetAlpha()>0 then state.alpha=label:GetAlpha()end
                        overlay:ClearAllPoints();overlay:SetAllPoints(label)
                        local font,size,flags=label:GetFont();overlay:SetFont(font,size,flags)
                        overlay:SetTextColor(label:GetTextColor());overlay:SetJustifyH(label:GetJustifyH());overlay:SetJustifyV(label:GetJustifyV())
                        overlay:SetText(config.display_mode=='bilingual' and original..'\n'..text or text)
                        -- 名称区放不下时回退原文，不挤占图标/等级/其他条目。
                        if state.alpha>0 and overlay:GetStringHeight()<=label:GetHeight()+1 then
                            self.phase='show';overlay:SetAlpha(state.alpha);label:SetAlpha(0);overlay:Show();seen[label]=true;self.rendered=self.rendered+1
                        else self.reason='no-space'end
                    end
                end
            end end
            end
            end end
        end
    end
end
function L:Update()
    -- 两个明确列表共享一次状态/清理，不因Rune页隐藏而误清技能页覆盖。
    self.rendered=0;self.reason='checking';self.phase='eligibility'
    if not self.enabled or not K.loggedIn then self.reason='idle';self:Clear();return end
    if InCombatLockdown()then self.reason='combat';self:Clear();return end
    local config=K:GetConfiguration('Grimfall.Tooltips',self.content)
    if not config or K.configurationConflicts['Grimfall.Tooltips:'..self.content]
        or (config.schema>=3 and config.schema<5 and not config.translate_spells) then self:Stop();return end
    local names=self:Names(config);local seen={};self.reason='no-visible-list'
    for _,profile in ipairs(profiles)do
        if not self.enabled then break end
        self:RenderProfile(profile,config,names,seen)
    end
    if not self.enabled then self:Clear();return end
    -- 翻页、搜索或条目复用后，底层英文改变就重新匹配；原GetText及点击数据从未修改。
    for label,state in pairs(self.states)do if not seen[label]then if self:Restore(label,state)then self.states[label]=nil end end end
    if self.rendered>0 then self.reason='displayed'end
end
function L:Start()
    self:Stop();if not K.loggedIn or InCombatLockdown()then return false end
    local content
    for _,config in pairs(K.configurations)do
        if config.target_addon=='Grimfall.Tooltips' then if content then return false end;content=config.target_version end
    end
    if not content then return false end
    local available=false
    for _,profile in ipairs(profiles)do if safe(container(profile))then available=true end end
    if not available then return false end
    self.content=content;self.enabled=true
    local ok=pcall(self.Update,self);if not ok then self.reason='error-'..tostring(self.phase);self:Stop()end
    return ok and self.enabled
end
SLASH_KUNLOCALIZERLISTS1='/kunloclists'
SlashCmdList.KUNLOCALIZERLISTS=function(command)
    -- 列表显示和提示框各自保留手动控制，自动模式不能覆盖本会话的off。
    if K.Startup and (command=='on' or command=='off') then K.Startup.blocked.lists=command=='off' end
    if command=='off'then L:Stop();return end
    if command=='on'then
        local ok=L:Start()
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(ok and 'KunLocalizer: List names display requested; /kunloclists status to check.' or 'KunLocalizer: Open a supported list; check configuration.')end
    elseif command=='status'then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('KunLocalizer: list '..tostring(L.enabled)..' / '..L.reason..' / displayed '..L.rendered..' / overlays '..L.created)end
    end
end
local frame=CreateFrame('Frame');frame:RegisterEvent('PLAYER_LEAVING_WORLD')
frame:SetScript('OnEvent',function(_,event)if event=='PLAYER_LEAVING_WORLD'then L:Stop()end end)
frame:SetScript('OnUpdate',function(_,delta)
    -- 仅显式启用时每0.3秒检查已确认的两个列表，绝不遍历全局UI。
    if not L.enabled and not next(L.states)then return end
    L.elapsed=L.elapsed+delta;if L.elapsed<0.3 then return end;L.elapsed=0
    if not L.enabled then L:Clear();return end
    local ok=pcall(L.Update,L);if not ok then L.reason='error-'..tostring(L.phase);L:Stop()end
end)
