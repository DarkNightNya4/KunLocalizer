-- Shared project configuration v1. Imported only from a reviewed generated pack.
local K=KunLocalizer
-- 项目配置校验保持原契约；面板文案和布局独立到PanelLocale/Panel，不产生第二份项目状态。
-- 桌面同步只读检查此能力标记，不执行Lua探测核心版本。
K.configuration_api=5
K.configurations={}
K.configurationConflicts={}
local locales={enUS=true,zhCN=true,zhTW=true,deDE=true,esES=true,esMX=true,frFR=true,koKR=true,ruRU=true}
local fields={schema=true,profile_id=true,revision=true,target_addon=true,target_version=true,
    client_interface=true,source_locale=true,target_locale=true,display_mode=true,translate_items=true,translate_spells=true,
    auto_capture=true,capture_items=true,capture_equipment=true,capture_spells=true,
    translate_talents=true,translate_runes=true,translate_unclassified=true,
    capture_talents=true,capture_runes=true,capture_unclassified=true,entity_categories=true}
local function hex(value)
    return type(value)=="string" and #value==32 and not value:find("[^0-9a-f]")
end
-- 映射仅含有限实体类别；复制和按值比较，防止外部改动或重复注册误判。
local function copyMap(map)
    if not map then return nil end
    local copy={};for key,value in pairs(map)do copy[key]=value end;return copy
end
local function sameMap(a,b)
    if not a or not b then return a==b end
    for key,value in pairs(a)do if b[key]~=value then return false end end
    for key,value in pairs(b)do if a[key]~=value then return false end end
    return true
end
local plural={item="items",spell="spells",talent="talents",rune="runes",unclassified="unclassified"}
-- 翻译/采集共用类别入口，兼容配置仍使用原物品和技能主开关。
function K:ContentCategory(config,kind,id)
    if kind=="item" then return "item" end
    if kind~="spell" or type(id)~="number" or id<1 or id>2147483647 or id~=math.floor(id)then return nil end
    if not config or config.schema<5 then return "spell" end
    return config.entity_categories["spell."..string.format("%d",id)] or "unclassified"
end
function K:ProjectTranslationEnabled(config,kind,id)
    if not config or config.schema<3 then return true end
    if config.schema<5 then return (kind~="item" or config.translate_items) and (kind~="spell" or config.translate_spells)end
    local category=self:ContentCategory(config,kind,id)
    return category~=nil and config["translate_"..plural[category]]==true
end
function K:TranslationEnabled(config,kind,id)
    if not self:ProjectTranslationEnabled(config,kind,id) then return false end
    -- 本地显示只能缩小桌面允许范围；原项目配置和采集策略保持唯一来源。
    local category=self:ContentCategory(config,kind,id)
    return not self.Startup or self.Startup:CategoryEnabled(config,category)
end
function K:CaptureEnabled(config,kind,id,automatic,observed)
    -- 显示复选框不改变原文采集范围，包括旧配置的采集兼容路径。
    if config.schema<5 then return self:ProjectTranslationEnabled(config,kind,id)end
    local category=self:ContentCategory(config,kind,id)
    -- 只有已确认的专用天赋区可补充当前提示框类别，冲突则不采集。
    if observed then
        if category~="unclassified" and category~=observed then return false end
        category=observed
    end
    if not category then return false end
    -- 待分类原文用于发现新内容，单独选择采集；默认不因此允许翻译或付费。
    if category=="unclassified" then return not automatic or config.capture_unclassified end
    if not config["translate_"..plural[category]]then return false end
    return not automatic or category=="item" or config["capture_"..plural[category]]==true
end
function K:GetConfiguration(addon,version)
    if not self:Identifier(addon) or not self:Identifier(version) then return nil end
    local value=self.configurations[addon..":"..version]
    if not value then return nil end
    local copy={};for key,v in pairs(value)do copy[key]=key=="entity_categories" and copyMap(v) or v end;return copy
end
function K:RegisterConfiguration(data)
    if type(data)~="table" or (data.schema~=1 and data.schema~=2 and data.schema~=3 and data.schema~=4 and data.schema~=5) or data.client_interface~=30300
        or not hex(data.profile_id) or not hex(data.revision)
        or not self:Identifier(data.target_addon) or not self:Identifier(data.target_version)
        or not locales[data.source_locale] or not locales[data.target_locale]
        or data.source_locale==data.target_locale then return false end
    local count=0
    for key in pairs(data)do if not fields[key] then return false end;count=count+1 end
    if data.schema==1 then
        if count~=8 or data.display_mode~=nil then return false end
    elseif data.schema==2 then
        if count~=9 then return false end
    else
        -- 新开关仅属于已实现的提示框适配；未知类型/字段均拒绝加载。
        if count~=(data.schema==5 and 22 or data.schema==4 and 15 or 11) or data.target_addon~="Grimfall.Tooltips" or type(data.translate_items)~="boolean"
            or type(data.translate_spells)~="boolean" then return false end
    end
    if data.schema<3 and (data.translate_items~=nil or data.translate_spells~=nil) then return false end
    -- 老配置不得夹带新字段，新配置严格检查布尔范围及至少一个采集类型。
    for _,key in ipairs({"auto_capture","capture_items","capture_equipment","capture_spells"})do
        if data.schema>=4 then if type(data[key])~="boolean" then return false end
        elseif data[key]~=nil then return false end
    end
    for _,key in ipairs({"translate_talents","translate_runes","translate_unclassified","capture_talents","capture_runes","capture_unclassified"})do
        if data.schema==5 then if type(data[key])~="boolean" then return false end
        elseif data[key]~=nil then return false end
    end
    if data.schema==5 then
        if type(data.entity_categories)~="table" then return false end
        local total=0
        for entity,category in pairs(data.entity_categories)do
            total=total+1
            local id=type(entity)=="string" and entity:match("^spell%.([1-9]%d*)$")
            if not id or #id>10 or tonumber(id)>2147483647 or total>256
                or (category~="spell" and category~="talent" and category~="rune")then return false end
        end
        if data.auto_capture and not (data.capture_items or data.capture_equipment or data.capture_spells
            or data.capture_talents or data.capture_runes or data.capture_unclassified)then return false end
    elseif data.entity_categories~=nil then return false end
    if data.schema==4 and data.auto_capture and not (data.capture_items or data.capture_equipment or data.capture_spells) then return false end
    if data.schema~=1 and data.display_mode~="bilingual" and data.display_mode~="replace" then return false end
    local normalized={};for key in pairs(fields)do normalized[key]=key=="entity_categories" and copyMap(data[key]) or data[key]end
    normalized.display_mode=normalized.display_mode or "replace"
    local scope=data.target_addon..":"..data.target_version
    local old=self.configurations[scope]
    if old then
        for key in pairs(fields)do
            if (key=="entity_categories" and not sameMap(old[key],normalized[key]))
                or (key~="entity_categories" and old[key]~=normalized[key]) then
                self.configurationConflicts[scope]=true
                if self.loggedIn and self.Refresh then self:Refresh() end
                return false
            end
        end
        return true -- Identical registration is idempotent. Never silently override another profile.
    end
    local total=0;for _ in pairs(self.configurations)do total=total+1 end
    if total>=32 then return false end
    local copy=normalized
    self.configurations[scope]=copy
    if self.loggedIn and self.Refresh then self:Refresh() end
    return true
end
