-- 游戏本地显示启动偏好，不替代KunBox项目语言/类别，也不触发AI或采集清理。
local K=KunLocalizer
local S={inWorld=false,blocked={},elapsed=0};K.Startup=S
local displayKinds={item=true,spell=true,talent=true,rune=true}
local displayFields={item='translate_items',spell='translate_spells',talent='translate_talents',rune='translate_runes'}
local function validProfile(id)return type(id)=='string' and #id==32 and not id:find('[^0-9a-f]')end
local function displayChoices(value)
    -- 本地关闭项按项目隔离，最多8个项目×4类；只存true关闭标记，不存译文/账号。
    if type(value)~='table' then return nil end
    local result,count={},0
    for profile,flags in pairs(value)do
        count=count+1;if count>8 or not validProfile(profile) or type(flags)~='table' then return nil end
        local copy={};for kind,disabled in pairs(flags)do
            if not displayKinds[kind] or disabled~=true then return nil end;copy[kind]=true
        end
        if next(copy) then result[profile]=copy end
    end
    return result
end
-- 仅记录有限诊断代码，不保存聊天、账号、路径、API密钥或捕获原文；重载后清空。
K.panelLog={}
function K:PanelNote(code)
    if type(code)~='string' or #code>64 or code:find('[^%w_.%-]') then return end
    if #self.panelLog>=24 then table.remove(self.panelLog,1) end
    self.panelLog[#self.panelLog+1]=code
end
function S:RejectSettings(reason)
    -- 只记录固定拒绝原因，不拼接外部异常、配置值或任何用户文本。
    local allowed={combat=true,category_project=true,category_invalid=true,
        style_blocked=true,style_conflict=true,style_invalid=true}
    if not allowed[reason]then reason='style_blocked'end
    K:PanelNote('settings.rejected.'..reason);return false,reason
end
function S:Initialize()
    local old=KunLocalizerPreferences
    -- 只保存有限的模式字段；损坏数据回退手动，首次安装默认自动。
    local mode,language,choices='auto','auto',{}
    if old~=nil then
        mode='manual'
        if type(old)=='table' and (old.mode=='auto' or old.mode=='manual') then
            local count=0;for _ in pairs(old)do count=count+1 end
            if old.schema==1 and count==2 then mode=old.mode;K:PanelNote('preferences.migrated_v1')
            elseif old.schema==2 and count==3 and (old.ui_language=='auto' or old.ui_language=='zhCN' or old.ui_language=='enUS') then
                mode,language=old.mode,old.ui_language
            elseif old.schema==3 and count==4 and (old.ui_language=='auto' or old.ui_language=='zhCN' or old.ui_language=='enUS') then
                local validated=displayChoices(old.disabled_categories)
                if validated then mode,language,choices=old.mode,old.ui_language,validated else K:PanelNote('preferences.invalid') end
            else K:PanelNote('preferences.invalid') end
        else K:PanelNote('preferences.invalid') end
    end
    KunLocalizerPreferences={schema=3,mode=mode,ui_language=language,disabled_categories=choices};self.ready=true
end
function S:Mode()
    return self.ready and KunLocalizerPreferences.mode or 'manual'
end
function S:UILanguage()
    return self.ready and KunLocalizerPreferences.ui_language or 'auto'
end
function S:SetUILanguage(language)
    if language~='zhCN' and language~='enUS' then return false end
    if not self.ready then self:Initialize() end
    -- 切面板文案不停止翻译、不重置mode，更不改项目语言和旧采集批次。
    KunLocalizerPreferences.ui_language=language
    K:PanelNote('language.'..language)
    return true
end
function S:ProjectCategoryEnabled(config,category)
    if not config or config.target_addon~='Grimfall.Tooltips' or not displayKinds[category] then return false end
    if config.schema<5 and (category=='talent' or category=='rune') then return false end
    return config.schema<3 or config[displayFields[category]]==true
end
function S:CategoryEnabled(config,category)
    if not self.ready or not config or not displayKinds[category] then return true end
    local requested=self:RequestedCategory(config,category)
    -- 关闭请求立即缩小显示；启用仍受外层已加载项目配置约束。
    if requested~=nil then return requested end
    local flags=KunLocalizerPreferences.disabled_categories[config.profile_id]
    return not flags or not flags[category]
end
function S:RequestedCategory(config,category)
    return self:RequestedValue(config,displayFields[category])
end
function S:RequestedValue(config,field)
    local db=self:SettingsData();local request=db and db.request
    if not config or not request or request.profile_id~=config.profile_id or request.revision~=config.revision
        or request.content_id~=config.target_version or request.source_locale~=config.source_locale
        or request.target_locale~=config.target_locale or type(request.changes)~='table'then return nil end
    local value=request.changes[field]
    if type(value)=='boolean'then return value end
    return nil
end
function S:AutoCaptureSelection(config)
    local requested=self:RequestedValue(config,'auto_capture')
    if requested~=nil then return requested end
    return config and config.auto_capture==true or false
end
function S:AutoCaptureAllowed(config)
    -- 请求关闭即时停止，请求开启不能越过当前已加载的采集授权。
    return config and config.auto_capture==true and self:RequestedValue(config,'auto_capture')~=false
end
function S:SetAutoCapture(config,enabled)
    if type(enabled)~='boolean'then return self:RejectSettings('style_invalid')end
    local ok,reason=self:RequestSettings(config,{auto_capture=enabled})
    if not ok then return false,reason end
    if not enabled then K.AutoCapture:Pause()end
    -- 开启只登记永久配置请求，不自动解除会话暂停或触碰旧批次。
    return true,'capture_pending'
end
function S:CategorySelection(config,category)
    local requested=self:RequestedCategory(config,category)
    if requested~=nil then return requested end
    return self:ProjectCategoryEnabled(config,category) and self:CategoryEnabled(config,category)
end
function S:SetSharedCategory(config,category,enabled)
    -- 共享入口与旧本地SetCategory分开，不把历史本地偏好自动导入项目。
    if not displayKinds[category] or type(enabled)~='boolean' then return self:RejectSettings('category_invalid')end
    local ok,reason=self:RequestSettings(config,{[displayFields[category]]=enabled})
    if not ok then return false,reason end
    if not self.ready then self:Initialize()end
    -- 用户显式修改后只移除此项旧关闭标记，其余旧偏好不迁移。
    local choices=KunLocalizerPreferences.disabled_categories;local flags=choices[config.profile_id]
    if flags then flags[category]=nil;if not next(flags)then choices[config.profile_id]=nil end end
    if enabled and self:ProjectCategoryEnabled(config,category) then
        self.blocked.tooltip=nil;self.blocked.lists=nil
        if not K.Tooltips.enabled and K.Tooltips.errors==0 then K.Tooltips:Start(config.target_version,GameTooltip)end
        if not K.ListNames.enabled and not K.ListNames.reason:find('error',1,true)then K.ListNames:Start()end
    end
    K.Tooltips:RefreshDisplay(config)
    if K.ListNames.enabled then K.ListNames:Update()end
    return true,'category_pending'
end
function S:SetCategory(config,category,enabled)
    if not displayKinds[category] or type(enabled)~='boolean' or not config or not validProfile(config.profile_id) then return false,'category_invalid' end
    if type(InCombatLockdown)~='function' or InCombatLockdown() then return false,'combat' end
    local current=K:GetConfiguration(config.target_addon,config.target_version)
    if not current or current.profile_id~=config.profile_id or current.revision~=config.revision
        or K.configurationConflicts[config.target_addon..':'..config.target_version] then return false,'category_project' end
    if not self:ProjectCategoryEnabled(current,category) then return false,'category_project' end
    local profiles=0;for _,profile in pairs(K.configurations)do
        if profile.target_addon=='Grimfall.Tooltips' then profiles=profiles+1 end
    end
    if profiles~=1 then return false,'category_project' end
    if not self.ready then self:Initialize() end
    local choices=KunLocalizerPreferences.disabled_categories;local flags=choices[config.profile_id]
    if not enabled and not flags then
        local count=0;for _ in pairs(choices)do count=count+1 end
        if count>=8 then return false,'category_limit' end
        flags={};choices[config.profile_id]=flags
    end
    if flags then
        flags[category]=not enabled or nil
        if not next(flags) then choices[config.profile_id]=nil end
    end
    K:PanelNote('display.'..category..(enabled and '.on' or '.off'))
    if enabled and not (K.TooltipCapture and K.TooltipCapture.armed) then
        -- 重新勾选即是显式开启操作，手动模式无需再输入on；不改变启动模式偏好。
        self.blocked.tooltip=nil;self.blocked.lists=nil
        if not K.Tooltips.enabled and K.Tooltips.errors==0 then K.Tooltips:Start(current.target_version,GameTooltip) end
        if not K.ListNames.enabled and not K.ListNames.reason:find('error',1,true) then K.ListNames:Start() end
    end
    -- 复核当前显示，不停其他类别的显示器、不改变手动/自动模式或采集。
    if K.Tooltips then K.Tooltips:RefreshDisplay(current) end
    if K.ListNames and K.ListNames.enabled then K.ListNames:Update() end
    return true
end
function S:SetMode(mode)
    -- 战斗中不切换显示状态，避免恢复/重建UI时跨越原保护边界。
    if (mode~='auto' and mode~='manual') or type(InCombatLockdown)~='function' or InCombatLockdown() then return false end
    if not self.ready then self:Initialize() end
    KunLocalizerPreferences.mode=mode;self.blocked={}
    K:PanelNote('startup.'..mode)
    -- 切手动即停止显示，旧手动on命令仍可单独启动；不改任何翻译数据。
    if K.Tooltips then K.Tooltips:Stop() end
    if K.ListNames then K.ListNames:Stop() end
    if mode=='auto' then self:Try() end
    return true
end
-- v2共享字段白名单，与桌面shared_settings对应；类型/适用版本必须显式登记。
local sharedFields={display_mode=2,translate_items=3,translate_spells=3,translate_talents=5,
    translate_runes=5,translate_unclassified=5,auto_capture=4,capture_items=4,capture_equipment=4,
    capture_spells=4,capture_talents=5,capture_runes=5,capture_unclassified=5}
local function sharedValues(config)
    local result={};for key,minimum in pairs(sharedFields)do
        if config.schema>=minimum and config[key]~=nil then result[key]=config[key]end
    end;return result
end
local function sharedIdentity(config)
    return {profile_id=config.profile_id,revision=config.revision,content_id=config.target_version,
        source_locale=config.source_locale,target_locale=config.target_locale}
end
local function validSharedValues(value,empty)
    if type(value)~='table' or (not empty and not next(value))then return false end
    local count=0;for key,item in pairs(value)do
        count=count+1;if count>13 or not sharedFields[key]then return false end
        if key=='display_mode' then if item~='replace' and item~='bilingual'then return false end
        elseif type(item)~='boolean'then return false end
    end;return true
end
local function validSharedSnapshot(value,request)
    if type(value)~='table'then return false end
    local allowed={profile_id=true,revision=true,content_id=true,source_locale=true,target_locale=true}
    if request then allowed.base=true;allowed.changes=true else allowed.values=true end
    local count=0;for key in pairs(value)do count=count+1;if not allowed[key]then return false end end
    if count~=(request and 7 or 6)then return false end
    for _,key in ipairs({'profile_id','revision','content_id'})do
        local id=value[key];if type(id)~='string' or #id~=(key=='content_id' and 64 or 32)or id:find('[^0-9a-f]')then return false end
    end
    return K:Identifier(value.source_locale) and K:Identifier(value.target_locale) and value.source_locale~=value.target_locale
end
function S:SettingsData()
    local db=KunLocalizerSettings
    if type(db)~='table' or type(db.loaded)~='table' or type(db.request)~='table' then return nil end
    if db.schema==2 then
        -- 读取SavedVariables前检查有限数据结构，未知字段保留原盘但拒绝继续写入。
        local n=0;for key in pairs(db)do n=n+1;if key~='schema' and key~='loaded' and key~='request'then return nil end end
        if n~=3 or not validSharedSnapshot(db.loaded,false) or not validSharedValues(db.loaded.values,false)then return nil end
        if next(db.request)then
            if not validSharedSnapshot(db.request,true) or not validSharedValues(db.request.base,false) or not validSharedValues(db.request.changes,false)then return nil end
            for key in pairs(db.request.base)do if db.request.changes[key]==nil then return nil end end
            for key in pairs(db.request.changes)do if db.request.base[key]==nil then return nil end end
        end
        return db
    end
    if db.schema~=1 then return nil end
    local fields=0;for key in pairs(db)do fields=fields+1;if key~='schema' and key~='loaded' and key~='request'then return nil end end
    if fields~=3 then return nil end
    for _,snapshot in ipairs({db.loaded,db.request})do
        local count=0;for key in pairs(snapshot)do
            count=count+1
            if key~='profile_id' and key~='revision' and key~='content_id' and key~='source_locale' and key~='target_locale' and key~='display_mode'then return nil end
        end
        if count~=0 and count~=6 then return nil end
    end
    -- 旧样式请求仅按旧加载值迁移基准；不猜其他设置，不清空旧请求。
    local function identity(value)local copy={};for _,key in ipairs({'profile_id','revision','content_id','source_locale','target_locale'})do copy[key]=value[key]end;return copy end
    local loaded=identity(db.loaded);loaded.values={display_mode=db.loaded.display_mode}
    local request={};if next(db.request)then
        request=identity(db.request);request.base={display_mode=db.loaded.display_mode};request.changes={display_mode=db.request.display_mode}
    end
    if not validSharedSnapshot(loaded,false) or not validSharedValues(loaded.values,false)then return nil end
    if next(request) and (not validSharedSnapshot(request,true) or not validSharedValues(request.base,false)
        or not validSharedValues(request.changes,false))then return nil end
    return {schema=2,loaded=loaded,request=request}
end
function S:SettingsStatus(config)
    local db=self:SettingsData();local request=db and db.request
    if not config or not request or not next(request)then return nil end
    if request.profile_id~=config.profile_id or request.content_id~=config.target_version
        or request.source_locale~=config.source_locale or request.target_locale~=config.target_locale then return 'style_conflict'end
    local same=true
    for key,value in pairs(request.changes)do
        if config[key]~=value then
            same=false
            if config[key]~=request.base[key] then return 'style_conflict'end
        end
    end
    return same and 'style_synced' or 'style_session'
end
function S:DisplayMode(config)
    -- 已保存请求按项目及配置修订绑定，新配置加载后不套用过期请求。
    local db=self:SettingsData();local request=db and db.request
    if type(request)=='table' and config and request.profile_id==config.profile_id and request.revision==config.revision
        and request.content_id==config.target_version and request.source_locale==config.source_locale
        and request.target_locale==config.target_locale and type(request.changes)=='table'
        and (request.changes.display_mode=='replace' or request.changes.display_mode=='bilingual')then
        return request.changes.display_mode
    end
    return config and config.display_mode or 'replace'
end
function S:ObserveSettings(config)
    if not config or config.target_addon~='Grimfall.Tooltips' then return end
    -- 回执描述本次实际加载配置，不声称外部新文件已被游戏加载；保留待处理请求。
    local db=self:SettingsData()
    if KunLocalizerSettings~=nil and not db then return end
    local loaded=sharedIdentity(config);loaded.values=sharedValues(config)
    local request=db and db.request or {}
    -- 仅消解已完整应用的旧修订请求；身份/语言、字段版本或任一目标不符都保留。
    local applied=next(request) and request.revision~=config.revision
        and request.profile_id==config.profile_id and request.content_id==config.target_version
        and request.source_locale==config.source_locale and request.target_locale==config.target_locale
    if applied then
        for key,value in pairs(request.changes)do
            if config.schema<sharedFields[key] or config[key]~=value then applied=false;break end
        end
    end
    if applied then request={};K:PanelNote('settings.applied')end
    KunLocalizerSettings={schema=2,loaded=loaded,request=request}
end
function S:RequestSettings(config,changes,cancel)
    if type(InCombatLockdown)~='function' or InCombatLockdown()then return self:RejectSettings('combat') end
    if not config or config.target_addon~='Grimfall.Tooltips' then return self:RejectSettings('category_project') end
    local current=K:GetConfiguration(config.target_addon,config.target_version)
    if not current or current.profile_id~=config.profile_id or current.revision~=config.revision
        or K.configurationConflicts[config.target_addon..':'..config.target_version] then return self:RejectSettings('category_project') end
    local count=0;for _ in pairs(K.configurations)do count=count+1 end
    if count~=1 or (K.TooltipCapture and K.TooltipCapture.armed)then return self:RejectSettings('style_blocked') end
    -- 输入先完整检查，失败时不能消解旧请求或留下部分新变更。
    if not validSharedValues(changes,true) or (cancel and not sharedFields[cancel])then return self:RejectSettings('style_invalid')end
    for key in pairs(changes)do
        if current.schema<sharedFields[key] or current[key]==nil then return self:RejectSettings('style_invalid')end
    end
    self:ObserveSettings(current)
    local data=self:SettingsData()
    if not data or data.schema~=2 then return self:RejectSettings('style_blocked') end
    -- 用户选择写为变更请求，WoW重载/正常退出后桌面才可安全读取；不直接篡改生成配置。
    local old=data.request
    if next(old) and (old.revision~=current.revision or old.profile_id~=current.profile_id or old.content_id~=current.target_version
        or old.source_locale~=current.source_locale or old.target_locale~=current.target_locale)then return self:RejectSettings('style_conflict') end
    local request=sharedIdentity(current);request.base={};request.changes={}
    if next(old)then
        if type(old.base)~='table' or type(old.changes)~='table' then return self:RejectSettings('style_blocked')end
        for key,value in pairs(old.base)do request.base[key]=value end
        for key,value in pairs(old.changes)do request.changes[key]=value end
    end
    local count=0;for key,value in pairs(changes)do
        count=count+1
        if count>13 or not sharedFields[key] or current.schema<sharedFields[key]
            or (key=='display_mode' and value~='replace' and value~='bilingual')
            or (key~='display_mode' and type(value)~='boolean')then return self:RejectSettings('style_invalid') end
        if request.base[key]==nil then request.base[key]=current[key]end
        request.changes[key]=value
    end
    if cancel then
        if not sharedFields[cancel]then return self:RejectSettings('style_invalid')end
        request.base[cancel]=nil;request.changes[cancel]=nil
    end
    if not next(request.changes)then request={}end
    KunLocalizerSettings.request=request
    K:PanelNote('settings.requested');return true
end
function S:SetDisplayMode(config,mode)
    if mode~='replace' and mode~='bilingual' and mode~='project' then return self:RejectSettings('style_invalid')end
    local ok,reason=self:RequestSettings(config,mode=='project' and {} or {display_mode=mode},mode=='project' and 'display_mode' or nil)
    if not ok then return false,reason end
    -- 不启动已停止的显示器，不改本地启动/分类偏好；复用原文保护与实体复查。
    K:PanelNote('display.style.'..mode)
    if K.Tooltips then K.Tooltips:RefreshDisplay(config)end
    return true
end
function S:Try()
    -- API不可用也只降级为不启动，独立Demo/缺适配环境不能拖垮核心事件。
    if not self.inWorld or not K.loggedIn or self:Mode()~='auto' or type(InCombatLockdown)~='function' or InCombatLockdown()
        or (K.TooltipCapture and K.TooltipCapture.armed) then return end
    local content
    for _,c in pairs(K.configurations)do
        if c.target_addon=='Grimfall.Tooltips' then if content then return end;content=c.target_version end
    end
    local c=content and K:GetConfiguration('Grimfall.Tooltips',content)
    if c then self:ObserveSettings(c)end
    local dictionary=c and K.dictionary['Grimfall.Tooltips:'..content..':'..c.target_locale]
    if not c or K.configurationConflicts['Grimfall.Tooltips:'..content] or not dictionary or not next(dictionary) then return end
    -- 错误隔离停止后不循环重启；手动off在本登录会话保持，直到显式on/改模式。
    if not self.blocked.tooltip and not K.Tooltips.enabled and K.Tooltips.errors==0 then K.Tooltips:Start(content,GameTooltip) end
    if not self.blocked.lists and not K.ListNames.enabled and not K.ListNames.reason:find('error',1,true) then K.ListNames:Start() end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','PLAYER_LOGIN','PLAYER_ENTERING_WORLD','PLAYER_LEAVING_WORLD','PLAYER_REGEN_ENABLED'})do frame:RegisterEvent(event)end
frame:SetScript('OnEvent',function(_,event,name)
    if event=='ADDON_LOADED' and name=='KunLocalizer' then
        S:Initialize();if IsLoggedIn() then S.inWorld=true end
    end
    if event=='PLAYER_LOGIN' then S.blocked={};S.inWorld=true end
    if event=='PLAYER_ENTERING_WORLD' then S.inWorld=true end
    if event=='PLAYER_LEAVING_WORLD' then S.inWorld=false;return end
    S:Try()
end)
frame:SetScript('OnUpdate',function(_,delta)
    -- 每秒仅检查已知提示框/两个白名单列表，支持晚创建的N面板，不遍历全局UI。
    S.elapsed=S.elapsed+delta;if S.elapsed<1 then return end;S.elapsed=0;S:Try()
end)
SLASH_KUNLOCALIZERSTARTUP1='/kunlocmode'
SlashCmdList.KUNLOCALIZERSTARTUP=function(command)
    if command=='auto' or command=='manual' then S:SetMode(command) end
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('KunLocalizer: '..K.PanelI18n:Text('mode_status')..S:Mode()) end
end
