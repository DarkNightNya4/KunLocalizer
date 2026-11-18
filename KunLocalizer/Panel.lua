-- 自有面板：固定主区、双语本地偏好和可滚动技术详情；不修改项目/采集数据。
local K,I=KunLocalizer,KunLocalizer.PanelI18n
local P={expanded=false,customExpanded=false,elapsed=0};K.Panel=P
local WIDTH,BASE,EXTRA=620,704,224
local logKinds={['panel.shown']='log_open',['panel.details_toggle']='log_details',
    ['panel.custom_toggle']='log_details',['panel.drag_start']='log_drag',['panel.drag_stop']='log_drag',
    ['settings.requested']='log_settings',['capture.paused']='log_paused',['capture.resumed']='log_resumed',
    ['capture.preserved']='log_preserved',['capture.full']='log_full',['capture.error']='log_error',
    ['capture.reset']='log_batch_reset',['capture.reset_resumed']='log_batch_resumed',['capture.reset_rejected']='log_batch_rejected',
    ['capture.control_failed']='log_error',['panel.render_failed']='log_error',['panel.create_failed']='log_error',
    ['display.style_failed']='log_error',['display.change_failed']='log_error',['preferences.invalid']='log_error',
    ['refresh.queued']='log_refresh',['refresh.armed']='log_refresh_armed',
    ['refresh.rejected']='log_refresh_rejected',['refresh.expired']='log_refresh_expired',
    ['startup.auto']='log_startup',['startup.manual']='log_startup',['startup.change_blocked']='log_blocked',
    ['language.zhCN']='log_language',['language.enUS']='log_language',['preferences.migrated_v1']='log_preferences'}
for _,kind in ipairs({'item','spell','talent','rune'})do
    logKinds['display.'..kind..'.on']='log_settings';logKinds['display.'..kind..'.off']='log_settings'
end
for _,style in ipairs({'replace','bilingual','project'})do logKinds['display.style.'..style]='log_settings'end
-- 设置拒绝沿用固定双语原因，详细日志可见；简洁视图仍只显示采集和刷新。
for _,reason in ipairs({'combat','category_project','category_invalid','style_blocked','style_conflict','style_invalid'})do
    logKinds['settings.rejected.'..reason]=reason
end
logKinds['settings.applied']='style_synced'
function P:LogText()
    -- 只渲染有限自有事件白名单；未知载荷不回显，日志不写磁盘或参与同步。
    local lines={};local events=K.panelLog or {}
    -- 只反向显示最近24条，底层事件仍按发生顺序保存，避免影响其他诊断使用者。
    for index=#events,math.max(1,#events-23),-1 do
        local code=events[index];local key=logKinds[code]
        -- 简洁视图只显示已知采集/对象刷新事件；详细视图仍不回显未知原始载荷。
        local capture=key and (code:match('^capture%.') or code:match('^refresh%.'))
        if self.verboseLog or capture then
            lines[#lines+1]=tostring(index)..'. '..I:Text(key or 'log_other')..(key and ' ['..code..']' or '')
        end
    end
    return #lines>0 and table.concat(lines,'\n') or I:Text('log_empty')
end
function P:CustomGroup(config)
    -- 仅使用已有明确分类和当前范围已载入数据，不从任意物品/技能译名猜服务器分组。
    local result={name=I:Text('custom_unnamed'),entities=0,loaded=0}
    if not config or config.schema~=5 or config.target_addon~='Grimfall.Tooltips'
        or K.configurationConflicts[config.target_addon..':'..config.target_version]then return result end
    local entries=K.dictionary[config.target_addon..':'..config.target_version..':'..config.target_locale] or {}
    local seen,count={},0
    for key,row in pairs(entries)do
        count=count+1;if count>4096 then return {name=I:Text('custom_unnamed'),entities=0,loaded=0}end
        local id,side,line
        if type(key)=='string' then id,side,line=key:match('^spell%.([1-9]%d*)%.(%a+)%.([1-9]%d*)$')end
        id,line=tonumber(id),tonumber(line)
        if id and line and id<=2147483647 and line<=40
            and (side=='left' or side=='right' or (side=='rank' and line==1))
            and K:ContentCategory(config,'spell',id)=='rune'
            and type(row)=='table' and K:String(row.source,512) and K:String(row.text,4096)then
            result.loaded=result.loaded+1;seen[id]=true
        end
    end
    for _ in pairs(seen)do result.entities=result.entities+1 end
    if result.entities>0 then result.name=I:Text('custom_rune')end
    return result
end
-- 统计只读自有数据，按文本条目计数；不扫描游戏数据库、不恢复/迁移旧批次。
function P:Statistics(config)
    local result={available=false,retained=false,excluded=false,invalid=false}
    for _,category in ipairs({'item','spell','talent','rune','unclassified'})do
        result[category]={captured=0,loaded=0}
    end
    if not config or config.target_addon~='Grimfall.Tooltips'
        or K.configurationConflicts[config.target_addon..':'..config.target_version] then return result end
    result.available=true
    local seen={}
    local function category(kind,id)return K:ContentCategory(config,kind,id) or 'unclassified' end
    local function read(db,limit)
        if db==nil then return end
        if type(db)~='table' or db.schema~=1 or type(db.entries)~='table' then result.invalid=true;return end
        -- 不同项目/内容/语言的数据不混算；同身份旧修订保留展示并明确标记。
        if db.profile_id~=config.profile_id or db.content_id~=config.target_version
            or db.source_locale~=config.source_locale or db.target_locale~=config.target_locale then
            result.excluded=true;return
        end
        if type(db.revision)~='string' then result.invalid=true;return end
        local pending,count={},0
        for index,row in pairs(db.entries)do
            count=count+1
            if count>limit or type(index)~='number' or index<1 or index>limit or index~=math.floor(index)
                or type(row)~='table' or (row.kind~='item' and row.kind~='spell')
                or type(row.id)~='number' or row.id<1 or row.id>2147483647 or row.id~=math.floor(row.id)
                or type(row.line)~='number' or row.line<1 or row.line>40 or row.line~=math.floor(row.line)
                or (row.side~='left' and row.side~='right' and row.side~='rank')
                or (row.side=='rank' and (row.kind~='spell' or row.line~=1 or not K.Tooltips:IsRankSource(row.source)))
                or not K:String(row.source,512) then result.invalid=true;return end
            pending[index]=row
        end
        for index=1,count do if not pending[index]then result.invalid=true;return end end
        if db.revision~=config.revision then result.retained=true end
        for _,row in ipairs(pending)do
            local token=row.kind..'.'..row.id..'.'..row.side..'.'..row.line..'\0'..row.source
            if not seen[token]then
                seen[token]=true
                local bucket=result[category(row.kind,row.id)];bucket.captured=bucket.captured+1
            end
        end
    end
    read(KunLocalizerTooltipDB,80);read(KunLocalizerAutoDB,128)
    local entries=K.dictionary[config.target_addon..':'..config.target_version..':'..config.target_locale] or {}
    local pending,count={},0
    for key,entry in pairs(entries)do
        count=count+1
        -- 多包合并仍有工作量上限；超限不展示看似完整的部分数字。
        if count>4096 or type(key)~='string' then result.invalid=true;break end
        local kind,id,side,line=key:match('^(%a+)%.([1-9]%d*)%.(%a+)%.([1-9]%d*)$')
        id,line=tonumber(id),tonumber(line)
        if (kind=='item' or kind=='spell') and id<=2147483647 and line<=40
            and (side=='left' or side=='right' or (side=='rank' and kind=='spell' and line==1))
            and type(entry)=='table' and K:String(entry.source,512) and K:String(entry.text,4096)then
            local name=category(kind,id);pending[name]=(pending[name] or 0)+1
        end
    end
    for name,value in pairs(pending)do result[name].loaded=value end
    -- 任一自有数据损坏时改为未测量，避免误报完整统计；原始数据一字不改。
    if result.invalid then result.available=false end
    return result
end
local function text(parent,x,y,width,height,template)
    local f=parent:CreateFontString(nil,'OVERLAY',template or 'GameFontHighlightSmall')
    f:SetPoint('TOPLEFT',x,-y);f:SetWidth(width);f:SetHeight(height);f:SetJustifyH('LEFT');f:SetJustifyV('TOP')
    return f
end
local function button(parent,key,x,y,width,callback)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
    b:SetPoint('TOPLEFT',x,-y);b:SetWidth(width);b:SetHeight(26);b:SetScript('OnClick',callback)
    parent[key]=b;return b
end
local function profiles()
    local scopes={};for scope in pairs(K.configurations)do scopes[#scopes+1]=scope end
    table.sort(scopes);return scopes
end
local function flag(value)return I:Text(value and 'on' or 'off')end
local function chunk(value)
    -- 技术身份拆成短行，避免长无空格hash撑破框；仅显示不改原始身份。
    return tostring(value):gsub('([^\n]+)',function(line)
        local result={};for i=1,#line,32 do result[#result+1]=line:sub(i,i+31)end
        return table.concat(result,'\n')
    end)
end
function P:Create()
    local f=CreateFrame('Frame','KunLocalizerConfigurationPanel',UIParent)
    self.frame=f
    f:SetWidth(WIDTH);f:SetFrameStrata('DIALOG');f:EnableMouse(true)
    f:SetMovable(true);f:SetClampedToScreen(true)
    -- 只有顶部非交互区域可拖动，正文按钮/复选框不会触发移动。
    self.dragHandle=CreateFrame('Frame',nil,f)
    self.dragHandle:SetPoint('TOPLEFT',0,0);self.dragHandle:SetWidth(WIDTH);self.dragHandle:SetHeight(66)
    self.dragHandle:EnableMouse(true);self.dragHandle:RegisterForDrag('LeftButton')
    self.dragHandle:SetScript('OnDragStart',function()
        if InCombatLockdown()then return end
        P.dragging=true;f:StartMoving();K:PanelNote('panel.drag_start')
    end)
    self.dragHandle:SetScript('OnDragStop',function()P:EndDrag();P:Refresh()end)
    f:SetScript('OnHide',function()P:EndDrag()end)
    f:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12})
    self.title=text(f,22,18,180,24,'GameFontNormalLarge')
    self.subtitle=text(f,22,44,180,20)
    self.statCards={}
    for index,kind in ipairs({'item','spell','talent','rune'})do
        local x=214+(index-1)*96
        self.statCards[kind]={label=text(f,x,18,92,18,'GameFontNormal'),
            captured=text(f,x,40,92,26),loaded=text(f,x,68,92,26)}
        self.statCards[kind].loaded:SetTextColor(0.6,0.82,0.6)
    end
    self.statHint=text(f,22,100,576,30)
    self.languageLabel=text(f,22,80,122,20,'GameFontNormal')
    button(f,'chinese',154,72,160,function()K.Startup:SetUILanguage('zhCN');P:Refresh()end)
    button(f,'english',324,72,160,function()K.Startup:SetUILanguage('enUS');P:Refresh()end)
    self.startupLabel=text(f,22,120,122,20,'GameFontNormal')
    for _,mode in ipairs({'auto','manual'})do
        local choice=mode
        button(f,choice,choice=='auto' and 154 or 324,112,160,function()
            if K.Startup:SetMode(choice) then P.noticeKey=nil else P.noticeKey='combat';K:PanelNote('startup.change_blocked') end
            P:Refresh()
        end)
    end
    self.contentLabel=text(f,22,160,122,20,'GameFontNormal')
    -- 组背景先于子选项创建，避免后建背景覆盖复选框纹理；背景不接收鼠标。
    self.contentGroup=CreateFrame('Frame',nil,f)
    self.contentGroup:SetPoint('TOPLEFT',146,-208);self.contentGroup:SetWidth(454);self.contentGroup:SetHeight(76)
    self.contentGroup:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=8})
    self.contentChecks={}
    -- 第三排使用原生勾选纹理，四项固定对齐；rune旧键保留，玩家侧改称“自定义”。
    for index,category in ipairs({'item','spell','talent','rune'})do
        local kind=category
        local check=CreateFrame('CheckButton',nil,self.contentGroup,'UICheckButtonTemplate')
        check:SetPoint('TOPLEFT',154+(index-1)*112,-152);check:SetWidth(26);check:SetHeight(26)
        check.caption=text(check,30,5,kind=='rune' and 152 or 76,20)
        check:SetScript('OnClick',function()
            local scopes=profiles();local config=#scopes==1 and K.configurations[scopes[1]] or nil
            local selected=check:GetChecked() and true or false
            -- 第三方控件异常也只报告有限代码，不能从面板按钮把异常传播到游戏事件。
            local called,ok,reason=pcall(K.Startup.SetSharedCategory,K.Startup,config,kind,selected)
            if not called then K:PanelNote('display.change_failed');P.noticeKey='category_failed'
            else P.noticeKey=reason end
            P:Refresh()
        end)
        self.contentChecks[kind]=check
    end
    self.rows={}
    for index,key in ipairs({'project','translation','display','status','capture'})do
        local y=206+(index-1)*32
        self.rows[key]={label=text(f,22,y,122,24,'GameFontNormal'),value=text(f,154,y,442,30)}
    end
    -- 自定义为内容范围内部第二行；展开信息仍留在同一框内，不新增一级设置。
    self.customLabel=text(self.contentGroup,18,45,86,22,'GameFontNormal')
    f.customMore=button(self.contentGroup,'customMore',302,40,146,function()
        P.customExpanded=not P.customExpanded;K:PanelNote('panel.custom_toggle');P:Refresh()
    end)
    self.customInfo=text(self.contentGroup,18,78,422,42)
    self.notice=text(f,22,502,576,28)
    -- 永久共享开关与临时会话控制分开；全部复用已有采集器，不清理记录。
    self.captureCheck=CreateFrame('CheckButton',nil,f,'UICheckButtonTemplate')
    self.captureCheck:SetWidth(26);self.captureCheck:SetHeight(26)
    self.captureCheck.caption=text(self.captureCheck,30,5,164,20)
    self.captureCheck:SetScript('OnClick',function()
        local scopes=profiles();local c=#scopes==1 and K.configurations[scopes[1]] or nil
        local called,ok,reason=pcall(K.Startup.SetAutoCapture,K.Startup,c,P.captureCheck:GetChecked() and true or false)
        P.noticeKey=called and reason or 'category_failed';if not called then K:PanelNote('capture.control_failed')end
        P:Refresh()
    end)
    button(f,'capturePause',350,462,114,function()
        K.AutoCapture:Pause();P.noticeKey='capture_paused';P:Refresh()
    end)
    button(f,'captureResume',476,462,118,function()
        local called,ok,reason=pcall(K.AutoCapture.Resume,K.AutoCapture)
        P.noticeKey=called and reason or 'category_failed';if not called then K:PanelNote('capture.control_failed')end
        P:Refresh()
    end)
    self.styleButtons={}
    for index,mode in ipairs({'replace','bilingual','project'})do
        local choice=mode
        self.styleButtons[mode]=button(f,'style_'..mode,154+(index-1)*148,366,142,function()
            local scopes=profiles();local config=#scopes==1 and K.configurations[scopes[1]] or nil
            local called,ok,reason=pcall(K.Startup.SetDisplayMode,K.Startup,config,choice)
            P.noticeKey=not called and 'category_failed' or not ok and reason or 'style_session'
            if not called then K:PanelNote('display.style_failed')end
            P:Refresh()
        end)
    end
    local details=CreateFrame('Frame',nil,f);self.details=details
    details:SetPoint('TOPLEFT',22,-544);details:SetWidth(576);details:SetHeight(200)
    -- 手动刷新只操作输入ID对应的独立队列；不修改项目语言/分类或清空旧批次。
    self.refreshLabel=text(details,0,0,540,18,'GameFontNormal')
    self.refreshKind='item'
    self.refreshType=button(details,'refreshType',0,22,96,function()
        P.refreshKind=P.refreshKind=='item' and 'spell' or 'item';P:Refresh()
    end)
    self.refreshID=CreateFrame('EditBox',nil,details,'InputBoxTemplate')
    self.refreshID:SetPoint('TOPLEFT',108,-22);self.refreshID:SetWidth(100);self.refreshID:SetHeight(26)
    self.refreshID:SetAutoFocus(false);self.refreshID:SetNumeric(true);self.refreshID:SetMaxLetters(10)
    self.refreshID:SetFontObject(GameFontHighlightSmall)
    local function requestRefresh()
        local value=P.refreshID:GetText() or ''
        local id=value:match('^%d+$') and tonumber(value) or nil
        local called,ok,reason=pcall(K.EntityRefresh.Request,K.EntityRefresh,P.refreshKind,id)
        P.noticeKey=called and reason or 'refresh_unavailable'
        if not called or not ok then K:PanelNote('refresh.rejected')end
        P.refreshID:ClearFocus();P:Refresh()
    end
    self.refreshGo=button(details,'refreshGo',224,22,180,requestRefresh)
    self.refreshID:SetScript('OnEnterPressed',requestRefresh)
    self.refreshHint=text(details,0,54,540,32)
    local scroll=CreateFrame('ScrollFrame','KunLocalizerPanelDetailsScroll',details,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',0,-90);scroll:SetWidth(550);scroll:SetHeight(106)
    local child=CreateFrame('Frame',nil,scroll);child:SetWidth(530);child:SetHeight(196)
    scroll:SetScrollChild(child)
    self.detailsText=text(child,0,0,522,196)
    self.scroll,self.scrollChild=scroll,child
    self.logTitle=text(f,22,544,390,18,'GameFontNormal')
    -- 仅本次会话的显示筛选，不写共享配置、SavedVariables或采集记录。
    self.logDetailCheck=CreateFrame('CheckButton',nil,f,'UICheckButtonTemplate')
    self.logDetailCheck:SetWidth(26);self.logDetailCheck:SetHeight(26)
    self.logDetailCheck.caption=text(self.logDetailCheck,30,5,140,20)
    self.logDetailCheck:SetScript('OnClick',function()
        P.verboseLog=P.logDetailCheck:GetChecked() and true or false
        P.logScroll:SetVerticalScroll(0);P:Refresh()
    end)
    self.logScroll=CreateFrame('ScrollFrame','KunLocalizerPanelLogScroll',f,'UIPanelScrollFrameTemplate')
    self.logScroll:SetWidth(550);self.logScroll:SetHeight(80)
    self.logChild=CreateFrame('Frame',nil,self.logScroll);self.logChild:SetWidth(530);self.logChild:SetHeight(80)
    self.logScroll:SetScrollChild(self.logChild);self.logText=text(self.logChild,0,0,522,80)
    -- 为顶部统计统一下移原有控件，展开详情时不再移动主区；内容仍为第三排操作。
    local function down(widget,x,y)widget:SetPoint('TOPLEFT',x,-y-64)end
    down(self.languageLabel,22,80);down(f.chinese,154,72);down(f.english,324,72)
    down(self.startupLabel,22,120);down(f.auto,154,112);down(f.manual,324,112)
    down(self.contentLabel,22,160)
    -- 控件属于组容器，防止子框背景遮住父面板上的文字和勾选纹理。
    for index,kind in ipairs({'item','spell','talent'})do self.contentChecks[kind]:SetPoint('TOPLEFT',8+(index-1)*112,-8)end
    self.contentChecks.rune:SetPoint('TOPLEFT',108,-40)
    for index,key in ipairs({'project','translation','display','status','capture'})do
        down(self.rows[key].label,22,238+(index-1)*32);down(self.rows[key].value,154,238+(index-1)*32)
    end
    -- 页脚单独锚定，详情展开只增加下方区域，不挤动顶部语言/模式选择。
    local more=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
    more:SetPoint('BOTTOMLEFT',22,16);more:SetWidth(190);more:SetHeight(26)
    more:SetScript('OnClick',function()P.expanded=not P.expanded;K:PanelNote('panel.details_toggle');P:Refresh()end)
    f.more=more
    local close=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
    close:SetPoint('BOTTOMRIGHT',-22,16);close:SetWidth(120);close:SetHeight(26)
    close:SetScript('OnClick',function()f:Hide()end);f.close=close
    f:SetScript('OnUpdate',function(_,delta)
        P.elapsed=P.elapsed+delta;if P.elapsed<1 then return end;P.elapsed=0
        if not P.failed then P:Refresh() end
    end)
    if type(UISpecialFrames)=='table' then UISpecialFrames[#UISpecialFrames+1]='KunLocalizerConfigurationPanel' end
    f:Hide()
end
function P:EndDrag()
    if not self.dragging then return end
    local f=self.frame;f:StopMovingOrSizing();self.dragging=false
    -- 转成UIParent逻辑坐标，仅会话保存位置，不把分辨率/桌面坐标送入共享配置。
    local left,top,scale=f:GetLeft(),f:GetTop(),f:GetScale()
    if type(left)=='number' and type(top)=='number' then
        self.position={x=left*scale,y=UIParent:GetHeight()-top*scale}
    end
    K:PanelNote('panel.drag_stop')
end
function P:Place(height)
    if self.dragging then return end
    local f=self.frame;local width,screenHeight=UIParent:GetWidth(),UIParent:GetHeight()
    local scale=math.min(1,math.max(0.1,(width-24)/WIDTH),math.max(0.1,(screenHeight-24)/height))
    self.position=self.position or {x=(width-WIDTH*scale)/2,y=24}
    -- 顶缘锚定；正常空间足够时展开不移动顶部，仅在窗口越界时夹回可见区域。
    local x=math.max(12,math.min(self.position.x,width-WIDTH*scale-12))
    local y=math.max(12,math.min(self.position.y,screenHeight-height*scale-12))
    f:SetScale(scale);f:ClearAllPoints();f:SetPoint('TOPLEFT',UIParent,'TOPLEFT',x/scale,-y/scale)
end
function P:Render()
    local f=self.frame;local scopes=profiles();local c=#scopes==1 and K.configurations[scopes[1]] or nil
    if c and not K.configurationConflicts[scopes[1]] then K.Startup:ObserveSettings(c)end
    self.title:SetText(I:Text('title'));self.subtitle:SetText(I:Text('subtitle'))
    self.languageLabel:SetText(I:Text('language'));self.startupLabel:SetText(I:Text('startup'))
    local function selected(label,chosen)return label..(chosen and '  ['..I:Text('selected')..']' or '')end
    f.chinese:SetText(selected('简体中文',I:Language()=='zhCN'))
    f.english:SetText(selected('English',I:Language()=='enUS'))
    f.auto:SetText(selected(I:Text('auto'),K.Startup:Mode()=='auto'))
    f.manual:SetText(selected(I:Text('manual'),K.Startup:Mode()=='manual'))
    f.close:SetText(I:Text('close'));f.more:SetText(I:Text(self.expanded and 'hide_details' or 'details'))
    self.refreshLabel:SetText(I:Text('refresh_label'))
    self.refreshType:SetText(I:Text(self.refreshKind=='item' and 'items' or 'spells'))
    self.refreshGo:SetText(I:Text('refresh_go'));self.refreshHint:SetText(I:Text('refresh_hint'))
    self.contentLabel:SetText(I:Text('categories'))
    self.customLabel:SetText(I:Text('runes'))
    local group=self:CustomGroup(c)
    f.customMore:SetText(I:Text('custom_details')..(self.customExpanded and '  -' or '  +'))
    self.customInfo:SetText(I:Text('custom_scope')..' '..group.entities..' / '..group.loaded..'\n'..I:Text('custom_boundary'))
    if self.customExpanded then self.customInfo:Show()else self.customInfo:Hide()end
    local offset=self.customExpanded and 48 or 0
    self.contentGroup:SetHeight(76+offset)
    for index,key in ipairs({'project','translation','display','status','capture'})do
        local y=302+(index-1)*32+offset
        self.rows[key].label:SetPoint('TOPLEFT',22,-y);self.rows[key].value:SetPoint('TOPLEFT',154,-y)
    end
    self.notice:SetPoint('TOPLEFT',22,-502-offset);self.details:SetPoint('TOPLEFT',22,-544-offset)
    -- 日志固定在设置/技术详情下方，详情增加高度只向下推，不挤压顶部控件。
    local logY=544+offset+(self.expanded and EXTRA or 0)
    self.logTitle:SetPoint('TOPLEFT',22,-logY);self.logTitle:SetText(I:Text('log_title'))
    self.logDetailCheck:SetPoint('TOPLEFT',428,-logY+5)
    self.logDetailCheck:SetChecked(self.verboseLog and true or false)
    self.logDetailCheck.caption:SetText(I:Text('log_verbose'))
    self.logScroll:SetPoint('TOPLEFT',22,-logY-22)
    local logValue=self:LogText()
    if self.lastLog~=logValue then
        self.lastLog=logValue;self.logText:SetHeight(2048);self.logText:SetText(logValue)
        local size=math.min(2048,math.max(80,self.logText:GetStringHeight()+8))
        self.logText:SetHeight(size);self.logChild:SetHeight(size)
        -- 不在每秒刷新时强制滚回顶部，用户仍可查看已有日志。
        if not self.logInitialized then self.logScroll:SetVerticalScroll(0);self.logInitialized=true end
    end
    local captions={item='items',spell='spells',talent='talents',rune='runes'}
    local stats=self:Statistics(c)
    for kind,card in pairs(self.statCards)do
        card.label:SetText(I:Text(captions[kind]))
        card.captured:SetText(I:Text('stat_captured')..': '..(stats.available and stats[kind].captured or '—'))
        card.loaded:SetText(I:Text('stat_loaded')..': '..(stats.available and stats[kind].loaded or '—'))
    end
    local hint=I:Text(stats.invalid and 'stat_invalid' or not stats.available and 'stat_unavailable' or 'stat_hint')
    if stats.available then hint=hint..' '..I:Text('unknown')..': '..stats.unclassified.captured..' / '..stats.unclassified.loaded end
    if stats.retained then hint=hint..' '..I:Text('stat_retained') end
    if stats.excluded then hint=hint..' '..I:Text('stat_excluded') end
    self.statHint:SetText(hint)
    for kind,check in pairs(self.contentChecks)do
        local field=({item='translate_items',spell='translate_spells',talent='translate_talents',rune='translate_runes'})[kind]
        local supported=c and type(c[field])=='boolean'
        check.caption:SetText(kind=='rune' and group.name or I:Text(captions[kind]))
        check:SetChecked(c and K.Startup:CategorySelection(c,kind) or false)
        local usable=supported and not K.configurationConflicts[scopes[1]] and not InCombatLockdown()
            and not (K.TooltipCapture and K.TooltipCapture.armed) or false
        check:SetEnabled(usable);check.caption:SetTextColor(usable and 0.9 or 0.5,usable and 0.9 or 0.5,usable and 0.9 or 0.5)
    end
    for key,row in pairs(self.rows)do row.label:SetText(I:Text(key));row.value:SetText('—')end
    self.rows.project.value:SetText(c and c.target_addon or I:Text(#scopes==0 and 'no_project' or 'multiple'))
    if c then
        self.rows.translation.value:SetText(c.source_locale..'  →  '..c.target_locale)
        self.rows.display.value:SetText(I:Text(c.display_mode=='bilingual' and 'bilingual' or 'replace'))
    end
    self.rows.display.value:Hide()
    for mode,b in pairs(self.styleButtons)do
        b:SetPoint('TOPLEFT',mode=='replace' and 154 or mode=='bilingual' and 302 or 450,-366-offset)
        local db=K.Startup:SettingsData();local choice=db and db.request
        local chosen=type(choice)=='table' and type(choice.changes)=='table' and choice.changes.display_mode
        local overridden=type(choice)=='table' and c and choice.profile_id==c.profile_id and choice.revision==c.revision
            and choice.content_id==c.target_version and (chosen=='replace' or chosen=='bilingual')
        local selected=(mode=='project' and not overridden) or (mode~='project' and overridden and K.Startup:DisplayMode(c)==mode)
        b:SetText((selected and '* ' or '')..I:Text('style_'..mode))
        b:SetEnabled(c~=nil and not InCombatLockdown() and not K.configurationConflicts[scopes[1]]
            and not (K.TooltipCapture and K.TooltipCapture.armed))
    end
    local function state(module)return I:Text(module and module.enabled and not module.paused and 'running' or 'stopped')end
    self.rows.status.value:SetText(I:Text('tooltips')..': '..state(K.Tooltips)..' / '..I:Text('lists')..': '..state(K.ListNames))
    self.rows.capture.value:SetText(I:Text(K.AutoCapture and K.AutoCapture.enabled and not K.AutoCapture.paused and 'capture_on' or 'capture_wait'))
    self.captureCheck:SetPoint('TOPLEFT',154,-462-offset)
    f.capturePause:SetPoint('TOPLEFT',350,-462-offset);f.captureResume:SetPoint('TOPLEFT',476,-462-offset)
    self.captureCheck.caption:SetText(I:Text('capture_shared'))
    self.captureCheck:SetChecked(K.Startup:AutoCaptureSelection(c))
    local usable=c and type(c.auto_capture)=='boolean' and not K.configurationConflicts[scopes[1]]
        and not InCombatLockdown() and not (K.TooltipCapture and K.TooltipCapture.armed) or false
    self.captureCheck:SetEnabled(usable)
    f.capturePause:SetText(I:Text('capture_pause'));f.captureResume:SetText(I:Text('capture_resume'))
    f.capturePause:SetEnabled(K.AutoCapture.enabled)
    f.captureResume:SetEnabled(usable and K.Startup:AutoCaptureAllowed(c) and not K.AutoCapture.enabled)
    local conflict=false;for _,scope in ipairs(scopes)do if K.configurationConflicts[scope]then conflict=true end end
    -- 通用状态涵盖整批共享设置，不再只看display_mode。
    local status=K.Startup:SettingsStatus(c)
    self.notice:SetText(I:Text(self.noticeKey or (conflict and 'conflict' or status or 'category_hint')))
    self.notice:SetTextColor(conflict and 1 or 0.8,conflict and 0.35 or 0.8,conflict and 0.35 or 0.8)
    local height=BASE+offset+(self.expanded and EXTRA or 0);f:SetHeight(height)
    -- 拖动期间不重设位置；只缩放本面板，不改变客户端全局缩放。
    self:Place(height)
    if self.expanded then
        self.details:Show()
        local lines={I:Text('count')..': '..#scopes}
        for index=1,math.min(4,#scopes)do
            local config=K.configurations[scopes[index]]
            lines[#lines+1]='\n'..config.target_addon
            for _,entry in ipairs({{'version','target_version'},{'profile','profile_id'},{'revision','revision'},{'schema','schema'}})do
                lines[#lines+1]=I:Text(entry[1])..':\n'..chunk(config[entry[2]])
            end
            if config.schema==5 then lines[#lines+1]=I:Text('unknown')..': '..flag(config.translate_unclassified) end
        end
        local value=table.concat(lines,'\n')
        if self.lastDetails~=value then
            self.lastDetails=value;self.detailsText:SetHeight(4096);self.detailsText:SetText(value)
            local size=math.min(4096,math.max(196,self.detailsText:GetStringHeight()+8))
            self.detailsText:SetHeight(size);self.scrollChild:SetHeight(size);self.scroll:SetVerticalScroll(0)
        end
    else self.details:Hide() end
end
function P:Refresh()
    if not self.frame then return end
    -- 失败只隔离面板渲染，诊断仅保留代码，不把原始异常/用户文本写日志。
    local ok=pcall(self.Render,self)
    if not ok then
        self.failed=true;K:PanelNote('panel.render_failed')
        if self.notice then pcall(self.notice.SetText,self.notice,I:Text('failed')) end
    end
end
SLASH_KUNLOCALIZERCONFIG1='/kunloc'
SlashCmdList.KUNLOCALIZERCONFIG=function()
    if P.createFailed then return end
    if not P.frame then
        local ok=pcall(P.Create,P)
        if not ok then
            -- 部分构造失败也隐藏自有空壳，避免无关闭按钮的半成品拦住游戏输入。
            P.createFailed=true;K:PanelNote('panel.create_failed')
            if P.frame then pcall(P.frame.Hide,P.frame) end
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('KunLocalizer: '..I:Text('failed')) end
            return
        end
    end
    if P.frame:IsShown() then P.frame:Hide();return end
    P.failed=false;P.noticeKey=nil;P:Refresh();P.frame:Show();K:PanelNote('panel.shown')
end
SLASH_KUNLOCALIZERPANEL1='/kunlocpanel'
SlashCmdList.KUNLOCALIZERPANEL=function(command)
    if command~='log' or not DEFAULT_CHAT_FRAME then return end
    for index,code in ipairs(K.panelLog)do DEFAULT_CHAT_FRAME:AddMessage('KunLocalizer ['..index..'] '..code) end
end
