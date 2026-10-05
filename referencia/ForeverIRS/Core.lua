local ADDON, I = ...
ForeverIRS = I
local frame=CreateFrame("Frame")
I.events=frame
I.nextRequest=0
I.externalUntil=0
I.serial=0
local function now() return GetTime() end
function I.build()
    local version,build=GetBuildInfo()
    return tostring(version or "unknown").."."..tostring(build or "unknown")
end
function I.supported()
    local version=GetBuildInfo()
    return type(version)=="string" and version:match("^1%.60%.")~=nil
end
function I.installAchievementGuard()
    local comparison=AchievementFrameComparison
    if not I.supported() or not comparison or I.achievementGuardFrame==comparison then return end
    -- Blizzard subscribes on load even while hidden. An unrelated inspection
    -- then sends the normal "summary" category into a numeric-category API.
    -- Keep its scripts intact; only its readiness subscription follows visibility.
    local function sync(self)
        if self:IsVisible() then self:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
        else self:UnregisterEvent("INSPECT_ACHIEVEMENT_READY") end
    end
    comparison:HookScript("OnShow",sync)
    comparison:HookScript("OnHide",sync)
    I.achievementGuardFrame=comparison
    sync(comparison)
end
function I.say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd17aForever IRS:|r "..message)
end
function I.update(message)
    if message then I.status=message end
    if I.Render then I.Render() end
end
function I.release()
    if I.ownsComparison then
        I.ownsComparison=false
        if type(ClearAchievementComparisonUnit)=="function" then
            I.internal=true;pcall(ClearAchievementComparisonUnit);I.internal=false
        end
    end
end
function I.cancel(message,release)
    I.pending=nil;I.serial=I.serial+1
    if release~=false then I.release() end
    if message then I.update(message) end
end
function I.subject(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local guid=UnitGUID(unit);if not guid then return nil end
    local name,realm=UnitFullName(unit)
    local class=UnitClass(unit)
    return {guid=guid,name=name or "Unknown",realm=realm or GetRealmName() or "",class=class or "",
        level=UnitLevel(unit),guild=GetGuildInfo(unit)}
end
function I.finish(snapshot)
    I.pending=nil;I.snapshot=snapshot;I.release()
    if snapshot.available>0 or snapshot.wallet~=nil then
        I.save(snapshot)
        I.update((I.sessionOnly and "Session only; saved history needs a newer addon" or "Snapshot saved locally")
            .." · "..snapshot.available.." / "..#I.fields.." counters available")
    else I.update("The client returned no readable statistics. Try Refresh; /irs status shows API availability.") end
end
function I.audit(unit,origin)
    if not I.db then I.initialize() end
    I.installAchievementGuard()
    I.directoryMode=false;I.savedView=false
    if I.pending and I.pending.unit==unit and I.pending.guid==UnitGUID(unit) then
        if I.Show then I.Show(I.origin) end
        I.update("Still waiting for character statistics · "..math.floor(now()-I.pending.started).."s");return
    end
    I.cancel(nil)
    I.origin=origin or "command";I.unit=unit;I.snapshot=nil;I.subjectInfo=I.subject(unit);I.historyMode=false;I.activityMode=false
    if I.Show then I.Show(origin) end
    if not I.supported() then I.update("This version supports WoW Forever (1.60.x). Other clients are not verified.");return end
    if not I.subjectInfo then I.update("Select a nearby player, then click Target. Use My character to view yourself.");return end
    if InCombatLockdown() then I.update("Leave combat, then click Refresh to read statistics.");return end
    if UnitIsUnit(unit,"player") then I.finish(I.read(I.subjectInfo,true));return end
    if type(SetAchievementComparisonUnit)~="function" or type(GetComparisonStatistic)~="function" or not I.comparisonHooks then
        I.update("This client does not expose the comparison API required to read another player's statistics.");return
    end
    if type(CanInspect)~="function" or not CanInspect(unit,false) then I.update("This player is not inspectable right now. Move closer and click Refresh.");return end
    if AchievementFrame and AchievementFrame:IsShown() and AchievementFrame.isComparison then
        I.update("Close the achievement comparison window before requesting an IRS snapshot.");return
    end
    local wait=math.max(I.nextRequest,I.externalUntil)-now()
    if wait>0 then I.update("Inspection cooldown · click Refresh in "..math.ceil(wait).."s.");return end
    I.nextRequest=now()+5
    I.pending={guid=I.subjectInfo.guid,unit=unit,subject=I.subjectInfo,started=now(),deadline=now()+15}
    I.ownsComparison=true;I.internal=true
    local ok,result=pcall(SetAchievementComparisonUnit,unit)
    I.internal=false
    if not ok or result==false then I.cancel("Statistics request was unavailable. Try again when this player is nearby.");return end
    -- A successful Lua call is not proof that the server accepted the request.
    if I.pending then I.update("Waiting for character statistics…") end
end
function I.OpenDirectory()
    if not I.db then I.initialize() end
    I.cancel(nil);I.origin="directory";I.directoryMode=true;I.historyMode=false;I.activityMode=false
    if I.reportWindow then I.reportWindow:Hide() end
    I.status="Latest saved capture per character · missing figures sort last · click a row to open its ledger."
    I.Show("directory")
end
function I.OpenSaved(guid)
    local history=I.history(guid);local snapshot=history[#history]
    if not snapshot then I.update("No saved snapshot exists for this character.");return false end
    I.cancel(nil);I.origin="saved";I.unit=nil;I.snapshot=snapshot;I.subjectInfo=nil
    if I.reportWindow then I.reportWindow:Hide() end
    I.directoryMode=false;I.savedView=true;I.historyMode=false;I.activityMode=false;I.historyPage=0
    I.status="Saved snapshot · click History for earlier captures. Refresh requires this same character nearby."
    I.Show("saved");return true
end
function I.Refresh()
    if I.directoryMode then I.Render();return end
    if I.savedView and I.snapshot then
        for _,unit in ipairs({"player","target"}) do
            if UnitGUID(unit)==I.snapshot.guid then I.audit(unit);return end
        end
        I.update("Target this saved character and keep them nearby before refreshing. This capture has not changed.")
        return
    end
    I.audit(I.unit or "player",I.origin)
end
function I.installComparisonHooks()
    if I.comparisonHooks or type(hooksecurefunc)~="function" or type(SetAchievementComparisonUnit)~="function" or type(ClearAchievementComparisonUnit)~="function" then return end
    local function displaced()
        if I.internal then return end
        I.ownsComparison=false;I.externalUntil=now()+5
        if I.pending then I.cancel("Another addon changed the comparison request. Click Refresh to try again.",false) end
    end
    if not I.setHook then I.setHook=pcall(hooksecurefunc,"SetAchievementComparisonUnit",displaced) end
    if not I.clearHook then I.clearHook=pcall(hooksecurefunc,"ClearAchievementComparisonUnit",displaced) end
    I.comparisonHooks=I.setHook and I.clearHook
end
function I.inspectHook()
    if not InspectFrame or I.hookedInspect or InCombatLockdown() then return end
    I.hookedInspect=true
    InspectFrame:HookScript("OnShow",function(self)
        if I.db and I.db.autoInspect and self.unit then I.audit(self.unit,"inspect") end
    end)
    InspectFrame:HookScript("OnHide",function()
        if I.origin=="inspect" then I.cancel(nil);if I.window then I.window:Hide() end end
    end)
    local b=CreateFrame("Button",nil,InspectFrame,"UIPanelButtonTemplate")
    b:SetSize(68,22);b:SetPoint("BOTTOMRIGHT",InspectFrame,"BOTTOMRIGHT",-18,-29);b:SetText("IRS")
    b:SetScript("OnClick",function()if InspectFrame.unit then I.audit(InspectFrame.unit,"inspect") end end)
    I.inspectButton=b
end
function I.diagnostics()
    I.say("Addon "..I.VERSION.." · client "..I.build().." · data definitions "..I.DATA_BUILD)
    for _,name in ipairs({"GetStatistic","GetComparisonStatistic","SetAchievementComparisonUnit","ClearAchievementComparisonUnit"}) do I.say(name..": "..type(_G[name])) end
    I.say(I.pending and "Waiting for "..I.text(I.pending.subject.name).." · "..math.floor(now()-I.pending.started).."s" or I.status or "No request yet.")
end
function I.command(text)
    text=(text or ""):lower():match("^%s*(.-)%s*$")
    if text=="me" or text=="self" then I.audit("player")
    elseif text=="" then I.audit(UnitExists("target") and UnitIsPlayer("target") and "target" or "player")
    elseif text=="target" then I.audit("target")
    elseif text=="refresh" then I.Refresh()
    elseif text=="history" or text=="list" then I.OpenDirectory()
    elseif text=="status" then I.diagnostics()
    elseif text=="close" then if I.window then I.window:Hide() end
    elseif text=="auto on" or text=="auto off" then I.db.autoInspect=text=="auto on";I.say("Open beside Inspect: "..(I.db.autoInspect and "on" or "off"))
    elseif text=="reset" then I.db.position=nil;if I.window then I.window:ClearAllPoints();I.window:SetPoint("CENTER") end
    elseif text:match("^scale") then
        local value=text:match("^scale%s*(.-)$")
        if value=="reset" then I.db.scale=nil
        elseif I.validScale(tonumber(value)) then I.db.scale=tonumber(value)
        elseif value~="" then I.say("Choose a window scale from 0.6 to 1.6, or /irs scale reset.");return end
        if I.FitWindows then I.FitWindows() end
        I.say("Window scale: "..string.format("%.2f",I.db.scale or I.DEFAULT_SCALE)..(I.db.scale and "" or " (default)"))
    else I.say("/irs [target|me|history|refresh|status|close] · /irs auto on|off · /irs scale 0.6-1.6|reset · /irs reset (window position)") end
end
frame:SetScript("OnEvent",function(_,event,arg)
    if event=="ADDON_LOADED" then
        if arg==ADDON then
            I.initialize();I.installComparisonHooks()
            SLASH_FOREVERIRS1="/irs";SLASH_FOREVERIRS2="/foreverirs";SlashCmdList.FOREVERIRS=I.command
        end
        I.installAchievementGuard();I.inspectHook()
    elseif event=="PLAYER_LOGIN" or event=="PLAYER_REGEN_ENABLED" then I.installComparisonHooks();I.installAchievementGuard();I.inspectHook()
    elseif event=="INSPECT_ACHIEVEMENT_READY" then
        local p=I.pending
        if not p or p.guid~=arg then return end
        if now()>p.deadline then I.cancel("Statistics response arrived too late. Click Refresh to request a new snapshot.");return end
        if UnitGUID(p.unit)~=p.guid then I.cancel("The selected player changed. Click Target to inspect your current selection.");return end
        if InCombatLockdown() then I.cancel("Combat interrupted the request. Leave combat and click Refresh.");return end
        I.finish(I.read(p.subject,false))
    elseif event=="PLAYER_TARGET_CHANGED" then
        if I.pending and I.pending.unit=="target" and UnitGUID("target")~=I.pending.guid then I.cancel("Target changed. Click Target for a new snapshot.") end
    elseif event=="PLAYER_LOGOUT" then I.cancel(nil) end
    if (event=="UI_SCALE_CHANGED" or event=="DISPLAY_SIZE_CHANGED") and I.FitWindows then I.FitWindows() end
end)
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGIN","PLAYER_REGEN_ENABLED","INSPECT_ACHIEVEMENT_READY","PLAYER_TARGET_CHANGED","PLAYER_LOGOUT","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do frame:RegisterEvent(event) end
local tick=0
frame:SetScript("OnUpdate",function(_,elapsed)
    tick=tick+elapsed;if tick<1 then return end;tick=0
    if I.pending then
        if now()>=I.pending.deadline then I.cancel("No reply after 15s. Move closer and click Refresh; no automatic retry was sent.")
        else I.update("Waiting for character statistics · "..math.floor(now()-I.pending.started).."s") end
    elseif I.window and I.window:IsShown() and I.RefreshAge then I.RefreshAge() end
end)
