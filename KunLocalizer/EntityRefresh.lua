-- 单对象刷新队列：独立保存最新可见原文，不清空旧手动/自动批次，不调用AI。
local K,T,C=KunLocalizer,KunLocalizer.Tooltips,KunLocalizer.TooltipCapture
local R={acks={},armed=nil};K.EntityRefresh=R
local function integer(n,max)return type(n)=='number' and n>=1 and n<=max and n==math.floor(n)end
local function count(t,n)
    if type(t)~='table'then return false end
    local size=0;for _ in pairs(t)do size=size+1 end;return size==n
end
local function identity(db,c)
    return db.profile_id==c.profile_id and db.revision==c.revision and db.content_id==c.target_version
        and db.source_locale==c.source_locale and db.target_locale==c.target_locale
end
function R:Data(c)
    local db=KunLocalizerRefreshDB
    if db==nil then return {schema=1,profile_id=c.profile_id,revision=c.revision,content_id=c.target_version,
        source_locale=c.source_locale,target_locale=c.target_locale,serial=0,objects={}}end
    -- 旧身份/超限/损坏数据原样保留，不能把刷新动作变成隐式迁移或全量清空。
    if not count(db,8) or db.schema~=1 or not identity(db,c) or type(db.objects)~='table'
        or type(db.serial)~='number' or db.serial<0 or db.serial>1000000 or db.serial~=math.floor(db.serial)then return nil end
    local seen,tokens,n,rows,bytes={},{},0,0,1024
    for index,o in pairs(db.objects)do
        n=n+1
        if not integer(index,16) or not count(o,4) or (o.kind~='item' and o.kind~='spell') or not integer(o.id,2147483647)
            or type(o.token)~='string' or #o.token~=32 or o.token:find('[^0-9a-f]') or type(o.rows)~='table'then return nil end
        local key=o.kind..':'..o.id;if seen[key]then return nil end;seen[key]=true
        if tokens[o.token] or not tonumber(o.token,16) or tonumber(o.token,16)>db.serial or tonumber(o.token,16)<1 then return nil end
        tokens[o.token]=true
        local slots,m={},0
        for j,row in pairs(o.rows)do
            m=m+1
            if not integer(j,80) or not count(row,5) or row.kind~=o.kind or row.id~=o.id
                or not integer(row.line,40) or (row.side~='left' and row.side~='right' and row.side~='rank')
                or (row.side=='rank' and (o.kind~='spell' or row.line~=1 or not T:IsRankSource(row.source)))
                or not K:String(row.source,512)then return nil end
            local slot=row.side..row.line;if slots[slot]then return nil end;slots[slot]=true
            rows=rows+1;bytes=bytes+4*(#row.source+128)+256
        end
        if m==0 then return nil end
        for j=1,m do if not o.rows[j]then return nil end end
    end
    for j=1,n do if not db.objects[j]then return nil end end
    if n>16 or rows>128 or bytes>60000 then return nil end
    return db
end
function R:Accept(profile,content,source,target,tokens)
    -- 仅生成的已审校语言包携带回执；不执行第三方文本，不删除刷新队列。
    if not K:Identifier(profile) or not K:Identifier(content) or not K:Identifier(source)
        or not K:Identifier(target) or type(tokens)~='table'then return false end
    local pending,n={},0
    for i,token in pairs(tokens)do
        n=n+1;if not integer(i,16) or type(token)~='string' or #token~=32 or token:find('[^0-9a-f]')then return false end
        pending[token]=true
    end
    for i=1,n do if not tokens[i]then return false end end
    self.acks[profile..':'..content..':'..source..':'..target]=pending;return true
end
function R:Blocked(c,kind,id)
    local db=self:Data(c);if not db then return false end
    local ack=self.acks[c.profile_id..':'..c.target_version..':'..c.source_locale..':'..c.target_locale] or {}
    for _,o in ipairs(db.objects)do if o.kind==kind and o.id==id and not ack[o.token]then return true end end
    return false
end
function R:Queue(c,kind,id,rows)
    local db=self:Data(c);if not db or db.serial>=1000000 then return false,'refresh_preserved'end
    local objects={};for _,o in ipairs(db.objects)do if o.kind~=kind or o.id~=id then objects[#objects+1]=o end end
    local token=string.format('%032x',db.serial+1)
    objects[#objects+1]={kind=kind,id=id,token=token,rows=rows}
    local nextDB={schema=1,profile_id=c.profile_id,revision=c.revision,content_id=c.target_version,
        source_locale=c.source_locale,target_locale=c.target_locale,serial=db.serial+1,objects=objects}
    -- 候选完整校验后一次提交；额度不足时不丢旧对象、不留下半条记录。
    local old=KunLocalizerRefreshDB;KunLocalizerRefreshDB=nextDB
    if not self:Data(c)then KunLocalizerRefreshDB=old;return false,'refresh_full'end
    for tip,state in pairs(T.states)do
        if state.kind==kind and state.id==id then T:RestoreTip(tip,state);T.pending[tip]=nil;T.states[tip]=nil end
    end
    if K.Panel then K.Panel.noticeKey='refresh_queued'end
    K:PanelNote('refresh.queued');return true,'refresh_queued'
end
function R:Capture(c,kind,id,tip)
    if not K.loggedIn or InCombatLockdown() or C.armed or not T:IsAllowed(tip)
        or type(tip.IsShown)~='function' or not tip:IsShown() or T:Entity(tip,kind)~=id then return false,'refresh_unavailable'end
    if not K:CaptureEnabled(c,kind,id,false,T:ObservedCategory(tip,kind,id))then return false,'refresh_unavailable'end
    local rows=C:Read(tip,kind,id);if not rows then return false,'refresh_unavailable'end
    return self:Queue(c,kind,id,rows)
end
function R:Request(kind,id)
    local c;for _,config in pairs(K.configurations)do
        if config.target_addon=='Grimfall.Tooltips'then if c then return false,'refresh_unavailable'end;c=config end
    end
    if kind=='talent' or kind=='rune'then kind='spell'end
    if not c or K.configurationConflicts['Grimfall.Tooltips:'..c.target_version] or InCombatLockdown() or C.armed
        or (kind~='item' and kind~='spell') or not integer(id,2147483647)then return false,'refresh_unavailable'end
    if T:Entity(GameTooltip,kind)==id and GameTooltip:IsShown()then return self:Capture(c,kind,id,GameTooltip)end
    -- 输入ID不后台枚举对象；等待玩家在60秒内实际打开该ID提示框。
    if not self:Data(c)then return false,'refresh_preserved'end
    self.armed={config=c,kind=kind,id=id,deadline=GetTime()+60};K:PanelNote('refresh.armed')
    return true,'refresh_armed'
end
function R:Consider(c,kind,id,rows,previous)
    local known,complete={},false
    for _,row in ipairs(previous or {})do if row.kind==kind and row.id==id then known[row.side..row.line]=row.source;complete=true end end
    local dict=K.dictionary['Grimfall.Tooltips:'..c.target_version..':'..c.target_locale] or {}
    local db=self:Data(c);if not db then return false,'refresh_preserved'end
    for _,o in ipairs(db.objects)do if o.kind==kind and o.id==id then
        known={};complete=true
        for _,row in ipairs(o.rows)do known[row.side..row.line]=row.source end
    end end
    local slots={}
    for _,row in ipairs(rows)do
        slots[row.side..row.line]=true
        local entry=dict[kind..'.'..string.format('%d',id)..'.'..row.side..'.'..row.line]
        local source=known[row.side..row.line] or (entry and entry.source)
        if (complete and not known[row.side..row.line]) or (source and source~=row.source)then return self:Queue(c,kind,id,rows)end
    end
    if complete then for slot in pairs(known)do if not slots[slot]then return self:Queue(c,kind,id,rows)end end end
    return true
end
SLASH_KUNLOCALIZERREFRESH1='/kunlocrefresh'
SlashCmdList.KUNLOCALIZERREFRESH=function(command)
    local kind,number=command:match('^(%a+)%s+(%d+)%s*$')
    if command:match('^%s*$')then
        -- 优先采用最近一次白名单提示框的可靠实体，不按名称猜ID。
        local state=T.states[GameTooltip]
        if state and T:Entity(GameTooltip,state.kind)==state.id then kind=state.kind;number=state.id
        else
            local item,spell=T:Entity(GameTooltip,'item'),T:Entity(GameTooltip,'spell')
            if item and not spell then kind='item';number=item elseif spell and not item then kind='spell';number=spell end
        end
    end
    local ok,reason=R:Request(kind,tonumber(number))
    if not ok then K:PanelNote('refresh.rejected')end
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('KunLocalizer: '..(K.PanelI18n and K.PanelI18n:Text(reason) or reason))end
end
local frame=CreateFrame('Frame');frame:RegisterEvent('PLAYER_LEAVING_WORLD')
frame:SetScript('OnEvent',function()R.armed=nil end)
function R:Tick()
    local a=R.armed;if not a then return end
    if GetTime()>=a.deadline or InCombatLockdown()then
        R.armed=nil;if K.Panel then K.Panel.noticeKey='refresh_expired'end
        K:PanelNote('refresh.expired');return
    end
    local c=K:GetConfiguration('Grimfall.Tooltips',a.config.target_version)
    if not c or c.profile_id~=a.config.profile_id or c.revision~=a.config.revision then R.armed=nil;return end
    if GameTooltip:IsShown() and T:Entity(GameTooltip,a.kind)==a.id then
        R.armed=nil;local ok,reason=R:Capture(c,a.kind,a.id,GameTooltip)
        if not ok then if K.Panel then K.Panel.noticeKey=reason end;K:PanelNote('refresh.rejected')end
    end
end
frame:SetScript('OnUpdate',function()
    -- 插件回调错误只终止当前等待，避免每帧重复异常；不记录原始异常内容。
    if not R.armed then return end
    local ok=pcall(R.Tick,R)
    if not ok then R.armed=nil;K:PanelNote('refresh.rejected')end
end)
