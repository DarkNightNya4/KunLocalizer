-- 用户通过桌面v4配置启用后，游玩查看提示框时累积采集；默认不采集、不请求AI。
local K,C,T=KunLocalizer,KunLocalizer.TooltipCapture,KunLocalizer.Tooltips
local A={enabled=false,paused=false,hooked=false};K.AutoCapture=A
local function report(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("KunLocalizer: "..text)end
end
local function token(row)return row.kind..":"..row.id..":"..row.side..":"..row.line.."\0"..row.source end
local function validRow(row)
    return type(row)=="table" and (row.kind=="item" or row.kind=="spell") and type(row.id)=="number"
        and row.id>0 and row.id<=2147483647 and row.id==math.floor(row.id)
        -- 专用等级槽仅供技能实体的第1槽；旧左右列批次保持兼容。
        and (row.side=="left" or row.side=="right" or (row.side=="rank" and row.kind=="spell" and row.line==1))
        and (row.side~="rank" or T:IsRankSource(row.source))
        and type(row.line)=="number" and row.line>=1 and row.line<=40 and row.line==math.floor(row.line) and K:String(row.source,512)
end
function A:Restore(config)
    -- 已有数据不匹配或损坏时保留并停止，不能用新会话覆盖尚未导入的数据。
    local db=KunLocalizerAutoDB
    if db==nil then
        db={schema=1,profile_id=config.profile_id,revision=config.revision,content_id=config.target_version,
            source_locale=config.source_locale,target_locale=config.target_locale,entries={}}
        KunLocalizerAutoDB=db
    end
    if type(db)~="table" or db.schema~=1 or db.profile_id~=config.profile_id or db.revision~=config.revision
        or db.content_id~=config.target_version or db.source_locale~=config.source_locale or db.target_locale~=config.target_locale
        or type(db.entries)~="table" then return nil end
    local fields=0;for _ in pairs(db)do fields=fields+1 end;if fields~=7 then return nil end
    local seen,bytes,count={},1024,0
    for i,row in pairs(db.entries)do
        count=count+1
        if type(i)~="number" or i~=math.floor(i) or i<1 or i>128 or not validRow(row) then return nil end
        local fields=0;for _ in pairs(row)do fields=fields+1 end;if fields~=5 then return nil end
        local key=token(row);if seen[key]then return nil end;seen[key]=true
        bytes=bytes+4*(#row.source+128)+256
    end
    if count>128 or bytes>60000 then return nil end
    for i=1,count do if not db.entries[i]then return nil end end
    return db,seen,bytes,count
end
function A:Pause(reason)
    -- 会话暂停保持所有已采集数据；重新加载后仍以桌面已同步配置决定是否启动。
    self.enabled=false;self.paused=true;self.pending=nil
    if K.PanelNote then K:PanelNote(reason or 'capture.paused')end
end
function A:Collect(tip,kind)
    if not self.enabled or self.paused or C.armed or not K.loggedIn or InCombatLockdown() or not T:IsAllowed(tip)
        or type(tip.IsShown)~="function" or not tip:IsShown() then return end
    local config=K:GetConfiguration("Grimfall.Tooltips",self.content)
    if K.Startup and not K.Startup:AutoCaptureAllowed(config)then self:Pause();return end
    if not config or config.revision~=self.revision or K.configurationConflicts["Grimfall.Tooltips:"..self.content] then self:Pause();return end
    local id=T:Entity(tip,kind);if not id then return end
    if not K:CaptureEnabled(config,kind,id,true,T:ObservedCategory(tip,kind,id))then return end
    if kind=="spell" then
        if config.schema<5 and not config.capture_spells then return end
    elseif kind=="item" then
        if not config.translate_items or type(GetItemInfo)~="function" then return end
        -- 使用客户端已缓存物品的装备位置区分装备；未知数据跳过，不猜物品类别。
        local _,link=tip:GetItem();if type(link)~="string" then return end
        local name,_,_,_,_,_,_,_,equip=GetItemInfo(link)
        if not name or type(equip)~="string" then return end
        if (equip=="" and not config.capture_items) or (equip~="" and not config.capture_equipment) then return end
    else return end
    local rows=C:Read(tip,kind,id);if not rows then return end
    local db,seen,bytes,count=self:Restore(config)
    if not db then self:Pause('capture.preserved');report("Auto capture paused: preserve/import existing records before changing settings.");return end
    if K.EntityRefresh then
        -- 同ID原文变化进入独立最新快照队列；旧批次及其他实体不被覆盖。
        local ok=K.EntityRefresh:Consider(config,kind,id,rows,db.entries)
        if not ok then self:Pause('refresh.rejected');return end
    end
    local latest={};bytes=1024
    -- 仅当前匹配修订的同一ID更新为最新完整快照；其他ID和不匹配的保留批次不动。
    for _,row in ipairs(db.entries)do if row.kind~=kind or row.id~=id then latest[#latest+1]=row end end
    for _,row in ipairs(rows)do latest[#latest+1]=row end
    for _,row in ipairs(latest)do bytes=bytes+4*(#row.source+128)+256 end
    if #latest>128 or bytes>60000 then self:Pause('capture.full');report("Auto capture full. Import before clearing; previous records preserved.");return end
    db.entries=latest
end
function A:Start(content)
    local config=K:GetConfiguration("Grimfall.Tooltips",content)
    if not K.loggedIn or not config or (config.schema~=4 and config.schema~=5) or not config.auto_capture
        or K.configurationConflicts["Grimfall.Tooltips:"..content] then return false end
    if InCombatLockdown() or C.armed or (K.Startup and not K.Startup:AutoCaptureAllowed(config))then return false end
    local db,_,_,count=self:Restore(config)
    if not db or count>=128 then self:Pause(db and 'capture.full' or 'capture.preserved');return false end
    if self.hooked=="failed" then return false end
    if not self.hooked then
        self.hooked="failed"
        local ok=pcall(function()
            for _,kind in ipairs({"item","spell"})do
                local category=kind
                GameTooltip:HookScript(kind=="item" and "OnTooltipSetItem" or "OnTooltipSetSpell",function(tip)
                    -- 事件可能早于Show；延后一小段，仅对实际可见且仍是该实体的框采集。
                    local ok=pcall(function()
                        if A.enabled and not A.paused then
                            A.pending={tip=tip,kind=category,id=T:Entity(tip,category),at=GetTime()+0.1}
                        end
                    end)
                    if not ok then A:Pause('capture.error');report("Auto capture paused: callback error; saved records preserved.")end
                end)
            end
            GameTooltip:HookScript("OnTooltipCleared",function()A.pending=nil end)
        end)
        if not ok then return false end
        self.hooked=true
    end
    self.content=content;self.revision=config.revision;self.paused=false;self.enabled=true;return true
end
function A:Resume()
    -- 会话恢复不改共享配置；恢复失败也保留暂停及原始批次。
    if not K.loggedIn or InCombatLockdown() or C.armed then return false,'capture_blocked'end
    self.paused=false;self:MaybeStart()
    if not self.enabled then self:Pause();return false,'capture_blocked'end
    if K.PanelNote then K:PanelNote('capture.resumed')end
    return true,'capture_resumed'
end
function A:MaybeStart()
    if self.paused or not K.loggedIn then return end
    local content
    for _,config in pairs(K.configurations)do
        if config.target_addon=="Grimfall.Tooltips" then
            if content then self.enabled=false;return end
            content=config.target_version
        end
    end
    if not content then self.enabled=false;return end
    if not self:Start(content)then self.enabled=false end
end
SLASH_KUNLOCALIZERAUTO1="/kunlocauto"
SlashCmdList.KUNLOCALIZERAUTO=function(command)
    if command=="pause" or command=="off" then A:Pause();report("Auto capture paused for this session (reload follows desktop settings).")
    elseif command=="resume" or command=="on" then A:Resume();report(A.enabled and "Auto capture running." or "Auto capture not started; check settings or existing records.")
    elseif command=="clear confirm" then
        -- 明确二次命令才删除本插件自动记录，保留旧手动记录及其他SavedVariables。
        A:Pause();KunLocalizerAutoDB=nil;report("Automatic records cleared. Use /kunlocauto resume to restart.")
    else
        local db=KunLocalizerAutoDB;local count=type(db)=="table" and type(db.entries)=="table" and #db.entries or 0
        report((A.enabled and "Auto capture running: " or "Auto capture paused: ")..tostring(count).." / 128 rows. Pause/resume; import before clear confirm.")
    end
end
local lifecycle=CreateFrame("Frame");lifecycle:RegisterEvent("PLAYER_LEAVING_WORLD")
lifecycle:SetScript("OnEvent",function(_,event)if event=="PLAYER_LEAVING_WORLD" then A.enabled=false;A.pending=nil end end)
lifecycle:SetScript("OnUpdate",function()
    -- 每个提示框事件最多一次复查，不后台枚举物品、读取内存或持续轮询内容。
    local pending=A.pending
    if pending and GetTime()>=pending.at then
        A.pending=nil
        local ok=pcall(function()
            if pending.id and T:Entity(pending.tip,pending.kind)==pending.id then A:Collect(pending.tip,pending.kind)end
        end)
        if not ok then A:Pause('capture.error');report("Auto capture paused: callback error; saved records preserved.")end
    end
end)
