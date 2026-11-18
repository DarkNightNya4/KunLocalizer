-- 显式批次清理：SHA-256绑定全部规范化内容，执行时核对实时Lua表；不联网、不写其他保存根。
local K,A,C=KunLocalizer,KunLocalizer.AutoCapture,KunLocalizer.TooltipCapture
local R={used={},count=0};K.BatchReset=R
local M=4294967296
-- Lua5.1算术后备，不要求现代位运算API；已有bit库时仅用其基础运算加速。
local native=type(bit)=='table' and type(bit.band)=='function' and type(bit.bxor)=='function' and bit
local function operation(a,b,isXor)
    local result,power=0,1
    for i=1,32 do
        local x,y=a%2,b%2
        if (isXor and x~=y)or(not isXor and x==1 and y==1)then result=result+power end
        a=math.floor(a/2);b=math.floor(b/2);power=power*2
    end
    return result
end
local function band(a,b)if native then return native.band(a,b)%M end;return operation(a,b,false)end
local function xor(a,b)if native then return native.bxor(a,b)%M end;return operation(a,b,true)end
local function rotate(x,n)return math.floor(x/2^n)+(x*2^(32-n))%M end
local function word(x)return string.char(math.floor(x/16777216)%256,math.floor(x/65536)%256,math.floor(x/256)%256,x%256)end
local constants={
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
function R:Hash(s)
    if type(s)~='string' or #s>60000 then return nil end
    local length=#s;s=s..'\128'..string.rep('\0',(55-length)%64)..word(0)..word(length*8)
    local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    for offset=1,#s,64 do
        local w={}
        for i=1,16 do local p=offset+(i-1)*4;local a,b,c,d=s:byte(p,p+3);w[i]=a*16777216+b*65536+c*256+d end
        for i=17,64 do
            local x,y=w[i-15],w[i-2]
            local a=xor(xor(rotate(x,7),rotate(x,18)),math.floor(x/8))
            local b=xor(xor(rotate(y,17),rotate(y,19)),math.floor(y/1024))
            w[i]=(w[i-16]+a+w[i-7]+b)%M
        end
        local a,b,c,d,e,f,g,j=unpack(h)
        for i=1,64 do
            local s1=xor(xor(rotate(e,6),rotate(e,11)),rotate(e,25))
            local ch=xor(band(e,f),band(M-1-e,g))
            local t1=(j+s1+ch+constants[i]+w[i])%M
            local s0=xor(xor(rotate(a,2),rotate(a,13)),rotate(a,22))
            local maj=xor(xor(band(a,b),band(a,c)),band(b,c))
            j,g,f,e,d,c,b,a=g,f,e,(d+t1)%M,c,b,a,(t1+s0+maj)%M
        end
        local values={a,b,c,d,e,f,g,j};for i=1,8 do h[i]=(h[i]+values[i])%M end
    end
    local out={};for i=1,8 do out[i]=string.format('%08x',h[i])end;return table.concat(out)
end
local function hex(s,n)return type(s)=='string' and #s==n and not s:find('[^0-9a-f]')end
local locales={enUS=true,zhCN=true,zhTW=true,deDE=true,esES=true,esMX=true,frFR=true,koKR=true,ruRU=true}
function R:Digest(db)
    if type(db)~='table' or db.schema~=1 or not hex(db.profile_id,32)or not hex(db.revision,32)
        or not hex(db.content_id,64)or not locales[db.source_locale]or not locales[db.target_locale]
        or db.source_locale==db.target_locale or type(db.entries)~='table' then return nil end
    local n=0;for _ in pairs(db)do n=n+1 end;if n~=7 then return nil end
    local count=0;for i in pairs(db.entries)do
        if type(i)~='number'or i~=math.floor(i)or i<1 or i>128 then return nil end;count=count+1
    end
    local out={'KLB-AUTO-RESET-1\0'};local seen={}
    local function add(s)out[#out+1]=tostring(#s)..':'..s end
    for _,s in ipairs({db.profile_id,db.revision,db.content_id,db.source_locale,db.target_locale,tostring(count)})do add(s)end
    for i=1,count do
        local row=db.entries[i]
        if type(row)~='table' or(row.kind~='item'and row.kind~='spell')or type(row.id)~='number'or row.id<1 or row.id>2147483647
            or row.id~=math.floor(row.id)or type(row.line)~='number'or row.line<1 or row.line>40 or row.line~=math.floor(row.line)
            or not K:String(row.source,512)or(row.side~='left'and row.side~='right'and row.side~='rank')
            or(row.side=='rank'and(row.kind~='spell'or row.line~=1 or not K.Tooltips:IsRankSource(row.source)))then return nil end
        local fields=0;for _ in pairs(row)do fields=fields+1 end;if fields~=5 then return nil end
        local key=row.kind..':'..row.id..':'..row.side..':'..row.line..'\0'..row.source
        if seen[key]then return nil end;seen[key]=true
        for _,s in ipairs({row.kind,string.format('%.0f',row.id),row.side,tostring(row.line),row.source})do add(s)end
    end
    return self:Hash(table.concat(out))
end
function R:Execute(expected,resume)
    if not hex(expected,64)or type(resume)~='boolean'or not K.loggedIn or InCombatLockdown()or C.armed
        or self.used[expected]or self.count>=64 then return false,'reset_blocked' end
    local db=KunLocalizerAutoDB;local ok,digest=pcall(self.Digest,self,db)
    if not ok or not digest or digest~=expected or #db.entries==0 then return false,'batch_changed' end
    local config=K:GetConfiguration('Grimfall.Tooltips',db.content_id)
    if not config or config.profile_id~=db.profile_id or config.source_locale~=db.source_locale or config.target_locale~=db.target_locale
        or K.configurationConflicts['Grimfall.Tooltips:'..db.content_id]then return false,'reset_blocked' end
    if resume and(not config.auto_capture or (K.Startup and not K.Startup:AutoCaptureAllowed(config))or A.hooked=='failed')then return false,'reset_blocked' end
    -- 当前批次严格匹配后才删除；续采失败恢复原Lua表并暂停，不动其他保存根。
    A:Pause();KunLocalizerAutoDB=nil
    if resume then
        local success,started=pcall(A.Resume,A)
        if not success or not started then KunLocalizerAutoDB=db;A:Pause();return false,'resume_failed' end
    end
    self.used[expected]=true;self.count=self.count+1
    if K.PanelNote then K:PanelNote(resume and 'capture.reset_resumed'or'capture.reset')end
    return true,resume and 'reset_resumed'or'reset_done'
end
local previous=SlashCmdList.KUNLOCALIZERAUTO
SlashCmdList.KUNLOCALIZERAUTO=function(command)
    local action=type(command)=='string'and command:match('^(%S+)')
    if action=='reset'or action=='reset-resume' then
        local digest=command:match('^%S+ ([0-9a-f]+)$');local ok,reason=R:Execute(digest,action=='reset-resume')
        if not ok and K.PanelNote then K:PanelNote('capture.reset_rejected')end
        local key=ok and(action=='reset-resume'and'batch_reset_resumed'or'batch_reset_done')or'batch_reset_rejected'
        local text=K.PanelI18n and K.PanelI18n:Text(key)or key
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('KunLocalizer: '..text..' ['..reason..']')end
    else previous(command)end
end
