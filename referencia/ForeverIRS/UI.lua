local _, I = ...
-- Built from the client's own templates (verified in the Forever UI source)
-- so the ledger matches Forever's Inspect window: metal frame, portrait,
-- bottom tabs, red panel buttons, coin icons.
local W,H=690,480
-- Drawn larger than the game's default panels: the small fonts are hard to
-- read at 100%. /irs scale overrides this; the window still fits the screen.
I.DEFAULT_SCALE=1.2
local WHITE,GREY,GOLD,GREEN={1,1,1},{.5,.5,.5},{1,.82,0},{.1,1,.1}
local TONE={positive=GREEN,neutral=GOLD,muted=GREY}
local MISSING="--"
local TABS={"Ledger","Activity","History","Characters"}
-- Section context makes the long statistic names redundant in the ledger.
local SHORT={daily="Earned per day",posted="Auctions posted",purchases="Auctions won",largestSale="Largest sale",largestBid="Largest bid",disenchanted="Disenchants"}
local w,ui
local function fit(frame,width,height)
    local scale=I.db and I.db.scale or I.DEFAULT_SCALE
    if frame then frame:SetScale(math.min(scale,(UIParent:GetWidth()-24)/width,(UIParent:GetHeight()-24)/height)) end
end
function I.FitWindows()
    -- The tabs hang below the frame and the portrait rises above it.
    fit(w,W,H+40);fit(I.reportWindow,560,420)
end
local function text(parent,font,x,y,width,height,justify,color)
    local f=parent:CreateFontString(nil,"OVERLAY",font)
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);f:SetSize(width,height)
    f:SetJustifyH(justify or "LEFT");f:SetJustifyV("MIDDLE");f:SetWordWrap(false)
    if color then f:SetTextColor(unpack(color)) end
    return f
end
local function fill(parent,x,y,width,height,r,g,b,a)
    local t=parent:CreateTexture(nil,"BORDER")
    t:SetColorTexture(r,g,b,a);t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);t:SetSize(width,height)
    return t
end
local function button(parent,label,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,22);b:SetText(label);b:SetScript("OnClick",fn)
    return b
end
local function heading(parent,title,x,y,width)
    local f=text(parent,"GameFontNormal",x,y,width,16)
    f:SetText(title);fill(parent,x,y-17,width,1,1,.82,0,.25)
    return f
end
-- Blizzard money style: real coin icons, empty denominations omitted.
function I.coins(n)
    if n==nil then return MISSING end
    n=math.floor(n)
    local letters=type(GetCVarBool)=="function" and GetCVarBool("colorblindMode")
    local parts={}
    for index,unit in ipairs({{10000,"Gold","g"},{100,"Silver","s"},{1,"Copper","c"}}) do
        local amount=math.floor(n/unit[1]);if index>1 then amount=amount%100 end
        if amount>0 or (index==3 and #parts==0) then
            local shown=index==1 and I.quantity(amount) or tostring(amount)
            parts[#parts+1]=shown..(letters and unit[3] or "|TInterface\\MoneyFrame\\UI-"..unit[2].."Icon:0:0:2:0|t")
        end
    end
    return table.concat(parts," ")
end
-- Missing is shown the way the game's own statistics pane shows it, never as zero.
local function show(f,snapshot,key)
    local entry=snapshot and snapshot.values and snapshot.values[key]
    if entry and entry.number~=nil and I.byKey[key][4] then f:SetText(I.coins(entry.number))
    elseif entry then f:SetText(I.value(snapshot,key))
    else f:SetText(MISSING) end
    f:SetTextColor(unpack(entry and WHITE or GREY))
end
local function classColor(class)
    if type(class)~="string" or class=="" or type(RAID_CLASS_COLORS)~="table" then return nil end
    local token
    for _,names in ipairs({LOCALIZED_CLASS_NAMES_MALE,LOCALIZED_CLASS_NAMES_FEMALE}) do
        if type(names)=="table" then for key,name in pairs(names) do if name==class then token=key end end end
    end
    local c=RAID_CLASS_COLORS[token or class:upper():gsub("%s","")]
    return c and {c.r,c.g,c.b}
end
local function identity(s)
    local parts={"Level "..tostring(s.level or "?").." "..I.text(s.class)}
    if s.guild and s.guild~="" then parts[#parts+1]="<"..I.text(s.guild)..">" end
    if s.realm and s.realm~="" then parts[#parts+1]=I.text(s.realm) end
    return table.concat(parts,"  ·  ")
end
local function timestamp(at,short)
    return type(at)=="number" and date(short and "%b %d, %H:%M" or "%b %d, %Y · %H:%M:%S",at) or MISSING
end
local function ago(at)
    local minutes=math.max(0,math.floor((GetServerTime()-at)/60))
    if minutes<1 then return "just now" elseif minutes<60 then return minutes.."m ago"
    elseif minutes<2880 then return math.floor(minutes/60).."h ago" end
    return math.floor(minutes/1440).."d ago"
end
local function hideTooltip(self)
    if GameTooltip and GameTooltip:GetOwner()==self then GameTooltip:Hide() end
end
local function explain(self)
    local key=self.key
    if not key or not GameTooltip then return end
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(I.byKey[key][3])
    local entry=I.snapshot and I.snapshot.values[key]
    GameTooltip:AddLine(entry and (entry.number~=nil and "Reported by WoW at capture time." or "Display only: this format could not be converted safely.") or I.reason(I.snapshot,key),1,1,1,true)
    if I.byKey[key][5] then GameTooltip:AddLine("Highest rank recorded; the profession may since have been unlearned.",.8,.8,.8,true) end
    GameTooltip:Show()
end
-- One striped statistic line: gold label, white value, hover for its source.
local function line(parent,x,y,width,index,valueWidth)
    local r=CreateFrame("Frame",nil,parent);r:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);r:SetSize(width,15)
    if index%2==1 then fill(r,0,0,width,15,1,1,1,.05) end
    valueWidth=valueWidth or 100
    r.name=text(r,"GameFontNormalSmall",4,0,width-valueWidth-8,15)
    r.value=text(r,"GameFontHighlightSmall",width-valueWidth-4,0,valueWidth,15,"RIGHT")
    r:EnableMouse(true);r:SetScript("OnEnter",explain);r:SetScript("OnLeave",hideTooltip)
    return r
end
local function section(parent,title,x,y,width,keys,full)
    heading(parent,title,x,y,width)
    local rows={}
    for n,key in ipairs(keys) do
        local r=line(parent,x,y-20-(n-1)*15,width,n);r.key=key
        r.name:SetText(not full and SHORT[key] or I.byKey[key][3]);rows[key]=r.value
    end
    ui.groups[#ui.groups+1]=rows
    return rows
end
local function makeReport()
    if I.reportWindow then return I.reportWindow end
    local f=CreateFrame("Frame","ForeverIRSReportWindow",UIParent,"ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(f);f:SetTitle("Copy report")
    f:SetSize(560,420);f:SetPoint("CENTER");f:SetFrameStrata("FULLSCREEN_DIALOG");f:SetToplevel(true)
    f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton");f:SetClampedToScreen(true)
    f:SetScript("OnDragStart",function()f:StartMoving()end);f:SetScript("OnDragStop",function()f:StopMovingOrSizing()end)
    if f.CloseButton then f.CloseButton:SetScript("OnClick",function()f:Hide()end) end
    text(f,"GameFontHighlightSmall",14,-30,530,24):SetText("Select all, then copy. Nothing is posted to chat.")
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",f,"TOPLEFT",14,-68);scroll:SetSize(506,320)
    local edit=CreateFrame("EditBox",nil,scroll)
    edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal);edit:SetSize(506,800)
    edit:SetScript("OnEscapePressed",function()f:Hide()end)
    scroll:SetScrollChild(edit)
    button(f,"Close",96,function()f:Hide()end):SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-6,4)
    tinsert(UISpecialFrames,"ForeverIRSReportWindow")
    f.edit=edit;f:Hide();I.reportWindow=f;return f
end
local function openReport()
    local f=makeReport();I.FitWindows();f:Show();f.edit:SetText(I.report(I.snapshot));f.edit:SetFocus();f.edit:HighlightText()
end
function I.RefreshAge()
    if not ui then return end
    if I.directoryMode then ui.age:SetText("Local history");return end
    local s=I.snapshot
    ui.age:SetText(s and ("Captured "..ago(s.at)) or "No snapshot")
end
local function renderHistory()
    local h=ui.history;local s=I.snapshot;local all=s and I.history(s.guid) or {}
    local pages=math.max(1,math.ceil(#all/9))
    I.historyPage=math.max(0,math.min(I.historyPage or 0,pages-1))
    h.caption:SetText("Local snapshots  ·  "..#all.." saved  ·  newest first")
    for index,row in ipairs(h.rows) do
        local position=#all-(I.historyPage*9+index-1);local snap=all[position]
        if snap then
            row.time:SetText(timestamp(snap.at,true))
            for _,key in ipairs({"peak","total"}) do
                local value=I.numeric(snap,key=="total" and "acquired" or key)
                row[key]:SetText(I.coins(value));row[key]:SetTextColor(unpack(value~=nil and WHITE or GREY))
            end
            local previous=all[position-1]
            local a,b=I.numeric(snap,"acquired"),I.numeric(previous,"acquired")
            local delta=previous and previous.build==snap.build and a and b and a>=b and a-b or nil
            row.delta:SetText(delta and "+ "..I.coins(delta) or MISSING);row.delta:SetTextColor(unpack(delta and GREEN or GREY))
            row.frame:Show()
        else row.frame:Hide() end
    end
    h.page:SetText("Page "..(I.historyPage+1).." / "..pages)
    h.previous:SetEnabled(I.historyPage>0);h.next:SetEnabled(I.historyPage<pages-1)
end
local function renderDirectory()
    local d=ui.directory;local rows,total=I.directoryRows(I.directoryQuery)
    local pages=math.max(1,math.ceil(#rows/9))
    I.directoryPage=math.max(0,math.min(I.directoryPage or 0,pages-1))
    d.caption:SetText(#rows.." / "..total.." characters")
    local sort=I.db.directorySort
    for key,header in pairs(d.headers) do
        local active=sort.key==key
        header:SetNormalFontObject(active and GameFontNormalSmall or GameFontHighlightSmall)
        header.arrow:SetShown(active)
        if active then header.arrow:SetTexCoord(0,1,sort.descending and 1 or 0,sort.descending and 0 or 1) end
    end
    for index,row in ipairs(d.rows) do
        local entry=rows[I.directoryPage*9+index]
        row.guid=entry and entry.guid or nil
        if entry then
            local s=entry.snapshot
            row.name:SetText(I.text(s.name)..(s.own and " (you)" or ""));row.name:SetTextColor(unpack(classColor(s.class) or WHITE))
            row.realm:SetText(I.text(s.realm).."  ·  "..I.text(s.class))
            row.level:SetText(s.level and I.quantity(s.level) or MISSING)
            row.peak:SetText(I.coins(entry.peak));row.peak:SetTextColor(unpack(entry.peak~=nil and WHITE or GREY))
            row.acquired:SetText(I.coins(entry.acquired));row.acquired:SetTextColor(unpack(entry.acquired~=nil and WHITE or GREY))
            row.lastSeen:SetText(timestamp(entry.lastSeen,true))
            row.count:SetText(tostring(entry.count));row:Show()
        else row:Hide() end
    end
    d.empty:SetText(total==0 and "No saved characters yet. Use My character or inspect a nearby player to save a capture."
        or "No saved characters match this search.")
    d.empty:SetShown(#rows==0)
    d.page:SetText("Page "..(I.directoryPage+1).." / "..pages)
    d.previous:SetEnabled(I.directoryPage>0);d.next:SetEnabled(I.directoryPage<pages-1)
end
local function makeDirectory()
    local d=CreateFrame("Frame",nil,w);d:SetPoint("TOPLEFT",w,"TOPLEFT",0,0);d:SetSize(W,H)
    d.rows={};d.headers={};ui.directory=d;I.directoryPanel=d
    d.search=CreateFrame("EditBox",nil,d,"SearchBoxTemplate")
    d.search:SetSize(240,20);d.search:SetPoint("TOPLEFT",d,"TOPLEFT",22,-70)
    d.search:SetAutoFocus(false);d.search:SetMaxLetters(100);d.search:SetText(I.directoryQuery or "")
    if d.search.Instructions then d.search.Instructions:SetText("Name, realm, guild or class") end
    -- Hooked so the template keeps its instructions text and clear button.
    d.search:HookScript("OnTextChanged",function(self)
        I.directoryQuery=self:GetText();I.directoryPage=0;renderDirectory()
    end)
    d.caption=text(d,"GameFontHighlightSmall",W-230,-70,214,20,"RIGHT")
    local columns={{"name","Character",14,220},{"level","Level",234,44},{"peak","Peak gold",278,130},
        {"acquired","Acquired",408,130},{"lastSeen","Last seen",538,88},{"count","Saves",626,48}}
    for _,def in ipairs(columns) do
        local key=def[1]
        local b=CreateFrame("Button",nil,d,"ColumnDisplayButtonShortTemplate")
        b:SetPoint("TOPLEFT",d,"TOPLEFT",def[3],-96);b:SetSize(def[4],19);b:SetText(def[2])
        b:SetScript("OnClick",function()I.sortDirectory(key);renderDirectory()end)
        b.arrow=b:CreateTexture(nil,"OVERLAY");b.arrow:SetAtlas("auctionhouse-ui-sortarrow",true)
        b.arrow:SetPoint("RIGHT",b,"RIGHT",-6,0);b.arrow:Hide()
        d.headers[key]=b
    end
    for index=1,9 do
        local row=CreateFrame("Button",nil,d)
        row:SetPoint("TOPLEFT",d,"TOPLEFT",14,-118-(index-1)*29);row:SetSize(W-30,29)
        if index%2==1 then fill(row,0,0,W-30,29,1,1,1,.05) end
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
        row:SetScript("OnClick",function(self)if self.guid then I.OpenSaved(self.guid)end end)
        row.name=text(row,"GameFontHighlight",6,-1,210,15)
        row.realm=text(row,"GameFontDisableSmall",6,-15,210,12)
        row.level=text(row,"GameFontHighlightSmall",220,0,44,29,"CENTER")
        row.peak=text(row,"GameFontHighlightSmall",264,0,124,29,"RIGHT")
        row.acquired=text(row,"GameFontHighlightSmall",394,0,124,29,"RIGHT")
        row.lastSeen=text(row,"GameFontHighlightSmall",524,0,82,29,"RIGHT",{.8,.8,.8})
        row.count=text(row,"GameFontHighlightSmall",612,0,42,29,"RIGHT")
        d.rows[index]=row
    end
    d.empty=text(d,"GameFontDisable",40,-190,W-80,50,"CENTER");d.empty:SetWordWrap(true)
    d.previous=button(d,"Previous",84,function()I.directoryPage=(I.directoryPage or 0)-1;renderDirectory()end)
    d.previous:SetPoint("TOPLEFT",d,"TOPLEFT",14,-386)
    d.page=text(d,"GameFontHighlightSmall",100,-386,96,22,"CENTER")
    d.next=button(d,"Next",84,function()I.directoryPage=(I.directoryPage or 0)+1;renderDirectory()end)
    d.next:SetPoint("TOPLEFT",d,"TOPLEFT",198,-386)
    text(d,"GameFontDisableSmall",300,-386,W-316,22,"RIGHT"):SetText("20 snapshots kept per character  ·  saved locally")
    d:SetScript("OnHide",function()d.search:ClearFocus()end)
end
local function selectTab(index)
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    if index==4 then I.OpenDirectory();return end
    if I.directoryMode then
        -- The directory hint no longer applies once a ledger is back on screen.
        I.status=I.snapshot and (I.snapshot.available.." / "..#I.fields.." counters available") or ""
    end
    I.directoryMode=false;I.activityMode=index==2;I.historyMode=index==3
    if index==3 then I.historyPage=0 end
    I.Render()
end
function I.Render()
    if not ui then return end
    local directory=I.directoryMode==true
    ui.ledger:SetShown(not directory);ui.directory:SetShown(directory)
    ui.copyButton:SetShown(not directory);ui.saveButton:SetShown(not directory)
    PanelTemplates_SetTab(w,directory and 4 or I.historyMode and 3 or I.activityMode and 2 or 1)
    ui.status:SetText(I.text(I.status or ""));ui.auto:SetChecked(I.db.autoInspect);I.RefreshAge()
    if directory then
        ui.name:SetText("Saved characters");ui.name:SetTextColor(unpack(WHITE))
        ui.identity:SetText("Click a column heading to sort; click it again to reverse.")
        renderDirectory();return
    end
    local s=I.snapshot;local subject=s or I.subjectInfo
    ui.name:SetText(subject and I.text(subject.name) or "Character ledger")
    ui.name:SetTextColor(unpack(subject and classColor(subject.class) or WHITE))
    ui.identity:SetText(subject and identity(subject) or "Select a nearby player or open your own statistics.")
    ui.walletTitle:SetText(I.savedView and "Wallet at capture" or "Current wallet")
    show(ui.cards.acquired,s,"acquired");show(ui.cards.peak,s,"peak")
    local wallet=s and s.own and s.wallet
    ui.cards.wallet:SetText(wallet and I.coins(wallet) or MISSING);ui.cards.wallet:SetTextColor(unpack(wallet and WHITE or GREY))
    ui.walletNote:SetText(s and not s.own and "Not visible for other players" or "Shown for your own characters")
    for _,rows in ipairs(ui.groups) do for key,f in pairs(rows) do show(f,s,key) end end
    local a=I.assess(s);local band=I.assessmentPanel
    band.title:SetText(a.title);band.title:SetTextColor(unpack(TONE[a.tone] or GREY))
    band.icon:SetShown(a.tone=="positive")
    band.title:SetPoint("TOPLEFT",band,"TOPLEFT",a.tone=="positive" and 24 or 4,-1)
    band.summary:SetText(a.summary)
    band.coverage:SetText(a.known.." / "..a.total.." counters readable")
    local gap,ratio=I.gap(s)
    ui.gap:SetText(gap~=nil and I.coins(gap) or MISSING);ui.gap:SetTextColor(unpack(gap~=nil and WHITE or GREY))
    ui.bar:SetWidth(math.max(.001,ratio and 240*ratio or .001));ui.bar:SetShown(ratio~=nil and ratio>0)
    ui.gapShare:SetText(ratio and ("Income covers "..math.floor(ratio*100).."% of peak") or "")
    local professions=I.professions(s)
    local positive={}
    for _,p in ipairs(professions) do if p.n and p.n>0 then positive[#positive+1]=p end end
    for n,row in ipairs(ui.professions) do
        local p=positive[n];row.key=p and p.key
        row.name:SetText(p and p.label..(p.highest and "*" or "") or n==1 and "No ranks recorded" or "")
        row.value:SetText(p and I.quantity(p.n) or "")
    end
    ui.profNote:SetText(#positive>4 and "+"..(#positive-4).." more in Activity  ·  * highest recorded" or "* highest recorded; may be unlearned")
    for n,row in ipairs(ui.activityProfessions) do
        local p=professions[n];row.key=p.key
        row.name:SetText(p.label..(p.highest and "*" or ""));show(row.value,s,p.key)
    end
    local history=s and I.history(s.guid) or {};local entry=s and I.db.characters[s.guid]
    ui.saved.count:SetText(tostring(#history).." / 20")
    ui.saved.first:SetText(entry and timestamp(entry.firstSeen,true) or MISSING)
    ui.saved.last:SetText(s and timestamp(s.at,true) or MISSING)
    ui.saved.build:SetText(s and I.text(s.build) or I.build())
    ui.body:SetShown(not I.historyMode and not I.activityMode)
    ui.history:SetShown(I.historyMode==true and not I.activityMode);ui.activity:SetShown(I.activityMode==true)
    if I.historyMode then renderHistory() end
end
local function makeLedger()
    local ledger=CreateFrame("Frame",nil,w);ledger:SetPoint("TOPLEFT",w,"TOPLEFT",0,0);ledger:SetSize(W,H);ui.ledger=ledger
    -- Headline figures.
    fill(ledger,10,-64,W-20,56,0,0,0,.3)
    for n,def in ipairs({{"acquired","Total gold acquired","Gross income recorded by the game"},
        {"peak","Most gold ever held","Historical high, not today's wallet"},{"wallet","Current wallet",""}}) do
        local x=14+(n-1)*225
        local title=text(ledger,"GameFontNormalSmall",x,-68,210,12);title:SetText(def[2])
        ui.cards[def[1]]=text(ledger,"GameFontHighlightLarge",x,-82,210,22)
        local note=text(ledger,"GameFontDisableSmall",x,-104,210,12);note:SetText(def[3])
        if def[1]=="wallet" then ui.walletTitle=title;ui.walletNote=note end
        if n>1 then fill(ledger,x-8,-68,1,48,1,1,1,.1) end
        local hit=CreateFrame("Frame",nil,ledger);hit:SetPoint("TOPLEFT",ledger,"TOPLEFT",x,-66);hit:SetSize(210,52)
        if def[1]~="wallet" then hit.key=def[1];hit:EnableMouse(true);hit:SetScript("OnEnter",explain);hit:SetScript("OnLeave",hideTooltip) end
    end
    -- Gameplay assessment; hover for the evidence and rules.
    local band=CreateFrame("Frame",nil,ledger);band:SetPoint("TOPLEFT",ledger,"TOPLEFT",10,-126);band:SetSize(W-20,40)
    I.assessmentPanel=band
    band.icon=band:CreateTexture(nil,"ARTWORK");band.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    band.icon:SetSize(16,16);band.icon:SetPoint("TOPLEFT",band,"TOPLEFT",4,-2)
    band.title=text(band,"GameFontNormal",4,-1,400,18)
    band.coverage=text(band,"GameFontDisableSmall",W-244,-1,220,18,"RIGHT")
    band.summary=text(band,"GameFontHighlightSmall",4,-21,W-48,14)
    band:EnableMouse(true)
    band:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        local a=I.assess(I.snapshot)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(a.title)
        GameTooltip:AddLine(a.coverage,.8,.8,.8,true);GameTooltip:AddLine(I.ASSESSMENT_NOTE,1,1,1,true)
        for _,entry in ipairs(a.evidence) do GameTooltip:AddLine(entry,.8,.85,.9,true) end
        GameTooltip:AddLine(I.ASSESSMENT_RULES,1,.82,0,true);GameTooltip:Show()
    end)
    band:SetScript("OnLeave",hideTooltip)
    -- Peak gold against recorded income, under the assessment on every ledger tab.
    local gapLine=CreateFrame("Frame",nil,ledger);gapLine:SetPoint("TOPLEFT",ledger,"TOPLEFT",10,-168);gapLine:SetSize(W-20,18)
    text(gapLine,"GameFontNormalSmall",4,0,150,18):SetText("Peak above recorded income")
    ui.gap=text(gapLine,"GameFontHighlightSmall",156,0,120,18)
    fill(gapLine,280,-5,240,8,0,0,0,.5)
    ui.bar=gapLine:CreateTexture(nil,"ARTWORK");ui.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ui.bar:SetVertexColor(1,.82,0);ui.bar:SetPoint("TOPLEFT",gapLine,"TOPLEFT",280,-5);ui.bar:SetSize(.001,8)
    ui.gapShare=text(gapLine,"GameFontDisableSmall",528,0,W-20-532,18,"RIGHT")
    gapLine:EnableMouse(true)
    gapLine:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("Peak above recorded income")
        GameTooltip:AddLine("Most gold ever held minus total gold acquired, never below zero. The bar shows recorded income as a share of peak gold.",1,1,1,true)
        if I.gap(I.snapshot)==nil then GameTooltip:AddLine("Needs both totals; one is missing from this capture.",.8,.8,.8,true) end
        GameTooltip:AddLine("Gold transfers, counter resets and missing counters affect the gap. It does not show where gold came from or indicate misconduct.",1,.82,0,true)
        GameTooltip:Show()
    end)
    gapLine:SetScript("OnLeave",hideTooltip)
    -- Ledger tab.
    ui.body=CreateFrame("Frame",nil,ledger);ui.body:SetPoint("TOPLEFT",ledger,"TOPLEFT",0,0);ui.body:SetSize(W,H)
    local body=ui.body
    section(body,"Income",14,-192,210,{"looted","quests","vendors","auctions","daily"})
    section(body,"Spending",239,-192,210,{"travel","postage","barber","respec"})
    text(body,"GameFontDisableSmall",243,-272,206,15):SetText("Tracked categories; not all expenses")
    section(body,"Auction activity",464,-192,210,{"posted","purchases","largestSale","largestBid"})
    section(body,"Gameplay",14,-301,210,{"questCount","kills","dungeons","disenchanted"})
    heading(body,"Professions",239,-301,210)
    for n=1,4 do ui.professions[n]=line(body,239,-321-(n-1)*15,210,n,60) end
    ui.profNote=text(body,"GameFontDisableSmall",243,-382,206,14)
    heading(body,"Your local record",464,-301,210)
    for n,def in ipairs({{"count","Snapshots"},{"first","First seen"},{"last","Captured"},{"build","Client"}}) do
        local r=line(body,464,-321-(n-1)*15,210,n,130);r:EnableMouse(false)
        r.name:SetText(def[2]);ui.saved[def[1]]=r.value
    end
    -- Activity tab.
    ui.activity=CreateFrame("Frame",nil,ledger);ui.activity:SetPoint("TOPLEFT",ledger,"TOPLEFT",0,0);ui.activity:SetSize(W,H)
    I.activityPanel=ui.activity
    ui.activity.rows=section(ui.activity,"Play history",14,-192,310,I.activityKeys,true)
    heading(ui.activity,"Professions",349,-192,325)
    text(ui.activity,"GameFontDisableSmall",349+325-184,-192,180,16,"RIGHT"):SetText("* highest rank recorded")
    for n=1,#I.professionKeys do ui.activityProfessions[n]=line(ui.activity,349,-212-(n-1)*15,325,n) end
    ui.activity.professions=ui.activityProfessions
    -- History tab.
    ui.history=CreateFrame("Frame",nil,ledger);ui.history:SetPoint("TOPLEFT",ledger,"TOPLEFT",0,0);ui.history:SetSize(W,H)
    local h=ui.history;h.rows={}
    h.caption=heading(h,"",14,-192,W-30)
    local columns={{"Observed",14,180,"LEFT"},{"Peak gold",194,150,"RIGHT"},{"Total acquired",344,160,"RIGHT"},{"Increase",504,166,"RIGHT"}}
    for _,def in ipairs(columns) do text(h,"GameFontNormalSmall",def[2]+4,-214,def[3]-8,14,def[4]):SetText(def[1]) end
    for n=1,9 do
        local row=CreateFrame("Frame",nil,h);row:SetPoint("TOPLEFT",h,"TOPLEFT",14,-230-(n-1)*17);row:SetSize(W-30,17)
        if n%2==1 then fill(row,0,0,W-30,17,1,1,1,.05) end
        local cells={}
        for index,key in ipairs({"time","peak","total","delta"}) do
            local def=columns[index]
            cells[key]=text(row,"GameFontHighlightSmall",def[2]-14+4,0,def[3]-8,17,def[4])
        end
        cells.frame=row;h.rows[n]=cells
    end
    h.previous=button(h,"Previous",84,function()I.historyPage=(I.historyPage or 0)-1;renderHistory()end)
    h.previous:SetPoint("TOPLEFT",h,"TOPLEFT",14,-388)
    h.page=text(h,"GameFontHighlightSmall",100,-388,96,22,"CENTER")
    h.next=button(h,"Next",84,function()I.historyPage=(I.historyPage or 0)+1;renderHistory()end)
    h.next:SetPoint("TOPLEFT",h,"TOPLEFT",198,-388)
    text(h,"GameFontDisableSmall",300,-388,W-316,22,"RIGHT"):SetText("No increase is shown across counter resets or client builds")
end
function I.Show(origin)
    if not w then
        w=CreateFrame("Frame","ForeverIRSWindow",UIParent,"ButtonFrameTemplate");I.window=w
        w:SetSize(W,H);w:SetFrameStrata("DIALOG");w:SetToplevel(true);w:SetClampedToScreen(true)
        w:SetTitle("Ironforge Revenue Service");w:SetPortraitToAsset("Interface\\AddOns\\ForeverIRS\\Assets\\Portrait")
        if w.CloseButton then w.CloseButton:SetScript("OnClick",function()w:Hide()end) end
        w:SetMovable(true);w:EnableMouse(true);w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart",function()w:StartMoving()end)
        w:SetScript("OnDragStop",function()
            w:StopMovingOrSizing();local point,_,relative,x,y=w:GetPoint()
            I.db.position={point=point,relative=relative,x=x,y=y}
        end)
        w:HookScript("OnHide",function()I.cancel(nil);if I.reportWindow then I.reportWindow:Hide() end end)
        tinsert(UISpecialFrames,"ForeverIRSWindow")
        ui={groups={},cards={},professions={},activityProfessions={},saved={},tabs={}}
        -- Header beside the portrait.
        ui.name=text(w,"GameFontHighlightLarge",62,-26,W-300,18)
        ui.identity=text(w,"GameFontHighlightSmall",62,-45,W-300,12)
        ui.age=text(w,"GameFontHighlightSmall",W-224,-27,214,14,"RIGHT")
        ui.auto=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");ui.auto:SetSize(22,22)
        ui.auto:SetPoint("TOPLEFT",w,"TOPLEFT",W-134,-40)
        ui.auto:SetScript("OnClick",function(self)I.db.autoInspect=self:GetChecked() and true or false end)
        text(w,"GameFontNormalSmall",W-110,-40,100,22):SetText("Open with Inspect")
        makeLedger()
        -- Footer inside the inset, above the button bar.
        local footer=CreateFrame("Frame",nil,w);footer:SetPoint("TOPLEFT",w,"TOPLEFT",0,0);footer:SetSize(W,H)
        ui.status=text(footer,"GameFontHighlightSmall",14,-(H-60),W-28,14)
        text(footer,"GameFontDisableSmall",14,-(H-44),W-28,12):SetText("Figures may be inaccurate or incomplete; for reference only, not proof of misconduct.  ·  "..MISSING.." not reported (not zero)")
        -- Button bar: subject on the left, record actions on the right.
        local me=button(w,"My character",104,function()I.audit("player")end);me:SetPoint("BOTTOMLEFT",w,"BOTTOMLEFT",6,4)
        local target=button(w,"Target",80,function()I.audit("target")end);target:SetPoint("LEFT",me,"RIGHT",2,0)
        ui.refreshButton=button(w,"Refresh",80,function()I.Refresh()end);ui.refreshButton:SetPoint("LEFT",target,"RIGHT",2,0)
        ui.saveButton=button(w,"Save snapshot",112,function()
            if not I.snapshot then I.update("Load a character's statistics first.")
            elseif I.save(I.snapshot) then I.update(I.sessionOnly and "Saved for this session only; stored history needs a newer addon." or "Snapshot saved locally.")
            else I.update("This capture is already saved. Refresh to request a new observation.") end
        end)
        ui.saveButton:SetPoint("BOTTOMRIGHT",w,"BOTTOMRIGHT",-6,4)
        ui.copyButton=button(w,"Copy report",104,openReport);ui.copyButton:SetPoint("RIGHT",ui.saveButton,"LEFT",-2,0)
        makeDirectory()
        for index,name in ipairs(TABS) do
            local tab=CreateFrame("Button","ForeverIRSWindowTab"..index,w,"PanelTabButtonTemplate")
            tab:SetID(index);tab:SetText(name);tab:SetScript("OnClick",function()selectTab(index)end)
            if index==1 then tab:SetPoint("TOPLEFT",w,"BOTTOMLEFT",11,2)
            else tab:SetPoint("TOPLEFT",ui.tabs[index-1],"TOPRIGHT",3,0) end
            PanelTemplates_TabResize(tab,0);ui.tabs[index]=tab
        end
        PanelTemplates_SetNumTabs(w,#TABS)
    end
    I.FitWindows()
    w:ClearAllPoints()
    local pos=I.db.position
    if type(pos)=="table" and type(pos.point)=="string" and type(pos.relative)=="string" and type(pos.x)=="number" and type(pos.y)=="number" then
        local ok=pcall(w.SetPoint,w,pos.point,UIParent,pos.relative,pos.x,pos.y);if not ok then w:SetPoint("CENTER") end
    elseif origin=="inspect" and InspectFrame and InspectFrame:IsShown() then w:SetPoint("TOPLEFT",InspectFrame,"TOPRIGHT",12,0)
    else w:SetPoint("CENTER") end
    w:Show();I.Render()
end
