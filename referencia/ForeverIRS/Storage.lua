local _, I = ...
-- Older releases must not strip the newly recorded activity counters.
local SCHEMA=3
I.directoryColumns={name=true,level=true,peak=true,acquired=true,lastSeen=true,count=true}
function I.validScale(n)
    return type(n)=="number" and n>=.6 and n<=1.6
end
local function short(value,limit,fallback)
    if type(value)~="string" or #value>limit then return fallback end
    return value:gsub("[%c]"," ")
end
local function timestamp(value)
    local n=I.number(value)
    if n and n>=1 and n<=4102444800 and n%1==0 then return n end
end
function I.cleanSnapshot(raw,guid)
    if type(raw)~="table" or type(raw.values)~="table" or not timestamp(raw.at) then return nil end
    local s={guid=guid,name=short(raw.name,128,"Unknown"),realm=short(raw.realm,128,""),
        class=short(raw.class,64,""),guild=short(raw.guild,256),level=I.number(raw.level),
        at=raw.at,build=short(raw.build,64,"unknown"),own=raw.own==true,values={},unavailable={},available=0}
    if s.level and (s.level>1000 or s.level%1~=0) then s.level=nil end
    if s.own then s.wallet=I.number(raw.wallet) end
    for _,field in ipairs(I.fields) do
        local key=field[1];local e=raw.values[key]
        if type(e)=="table" then
            local n=I.number(e.number)
            if n~=nil then s.values[key]={number=n}
            elseif type(e.display)=="string" and #e.display<=400 then
                -- Decode the old icon-only entries without changing observation time.
                s.values[key]=I.entry(e.display:gsub("||","|"),field[4])
            end
        end
        if s.values[key] then s.available=s.available+1
        elseif type(raw.unavailable)=="table" and I.reasons[raw.unavailable[key]] then
            s.unavailable[key]=raw.unavailable[key]
        end
    end
    if s.available>0 or s.wallet~=nil then return s end
end
function I.initialize()
    if I.db then return end
    local old=type(ForeverIRSDB)=="table" and ForeverIRSDB or {}
    I.db={version=SCHEMA,autoInspect=type(old.autoInspect)~="boolean" or old.autoInspect,characters={},directorySort={key="peak",descending=true}}
    if type(old.version)=="number" and old.version>SCHEMA then
        -- An older addon must not rewrite a newer on-disk schema.
        I.sessionOnly=true;return
    end
    if I.validScale(old.scale) then I.db.scale=old.scale end
    local sort=old.directorySort
    if type(sort)=="table" and I.directoryColumns[sort.key] and type(sort.descending)=="boolean" then
        I.db.directorySort={key=sort.key,descending=sort.descending}
    end
    local anchors={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
    local p=old.position
    if type(p)=="table" and anchors[p.point] and anchors[p.relative] and type(p.x)=="number" and type(p.y)=="number"
        and p.x==p.x and p.y==p.y and math.abs(p.x)<=10000 and math.abs(p.y)<=10000 then
        I.db.position={point=p.point,relative=p.relative,x=p.x,y=p.y}
    end
    if type(old.characters)=="table" then
        for guid,e in pairs(old.characters) do
            if type(guid)=="string" and #guid<=128 and guid:match("^Player%-%w[%w%-]*$") and type(e)=="table" and type(e.snapshots)=="table" then
                local list={}
                for _,raw in pairs(e.snapshots) do
                    local s=I.cleanSnapshot(raw,guid);if s then list[#list+1]=s end
                end
                table.sort(list,function(a,b)return a.at<b.at or a.at==b.at and a.build<b.build end)
                local unique={}
                for _,s in ipairs(list) do
                    local last=unique[#unique]
                    if not last or last.at~=s.at or last.build~=s.build then unique[#unique+1]=s end
                end
                while #unique>20 do table.remove(unique,1) end
                local last=unique[#unique]
                if last then I.db.characters[guid]={snapshots=unique,name=last.name,lastSeen=last.at,
                    firstSeen=math.min(timestamp(e.firstSeen) or unique[1].at,unique[1].at)} end
            end
        end
    end
    ForeverIRSDB=I.db
end
function I.history(guid)
    local entry=I.db and I.db.characters[guid]
    return entry and entry.snapshots or {}
end
function I.save(snapshot)
    if not snapshot or (snapshot.available==0 and snapshot.wallet==nil) then return false end
    local entry=I.db.characters[snapshot.guid]
    if not entry then entry={firstSeen=snapshot.at,snapshots={}};I.db.characters[snapshot.guid]=entry end
    local last=entry.snapshots[#entry.snapshots]
    if last and last.at==snapshot.at and last.build==snapshot.build then return false end
    entry.name=snapshot.name;entry.lastSeen=snapshot.at
    entry.snapshots[#entry.snapshots+1]=snapshot
    while #entry.snapshots>20 do table.remove(entry.snapshots,1) end
    return true
end
function I.sortDirectory(key)
    if not I.directoryColumns[key] then return end
    local sort=I.db.directorySort
    if sort.key==key then sort.descending=not sort.descending
    else sort.key=key;sort.descending=key~="name" end
    I.directoryPage=0
end
function I.directoryRows(query,key,descending)
    local sort=I.db.directorySort
    key=I.directoryColumns[key] and key or sort.key
    if descending==nil then descending=sort.descending end
    query=type(query)=="string" and query:lower():match("^%s*(.-)%s*$") or ""
    local rows,total={},0
    for guid,entry in pairs(I.db.characters) do
        local latest=entry.snapshots[#entry.snapshots]
        if latest then
            total=total+1
            local searchable=table.concat({latest.name,latest.realm,latest.guild or "",latest.class}," "):lower()
            if query=="" or searchable:find(query,1,true) then
                rows[#rows+1]={guid=guid,snapshot=latest,count=#entry.snapshots,lastSeen=latest.at,
                    name=(latest.name.." "..latest.realm):lower(),level=latest.level,
                    peak=I.numeric(latest,"peak"),acquired=I.numeric(latest,"acquired")}
            end
        end
    end
    table.sort(rows,function(a,b)
        local av,bv=a[key],b[key]
        -- Missing figures stay last in both directions. Never substitute zero,
        -- and never mix an older value into the latest snapshot's row.
        if av==nil and bv~=nil then return false end
        if bv==nil and av~=nil then return true end
        if av~=bv then
            if descending then return av>bv else return av<bv end
        end
        if a.name~=b.name then return a.name<b.name end
        return a.guid<b.guid
    end)
    return rows,total
end
