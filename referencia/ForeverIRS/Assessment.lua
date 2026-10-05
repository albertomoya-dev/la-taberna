local _, I = ...
I.ASSESSMENT_NOTE = "Activity is not proof of human control or rule compliance. New characters, bank alts, specialists, missing counters and resets can all produce a sparse record."
I.professionKeys = {"firstAid","cooking","fishing","alchemy","blacksmithing","enchanting","leatherworking","mining","herbalism","skinning","tailoring","engineering"}
I.activityKeys = {"questCount","kills","dungeons","disenchanted","disenchantMaterials","fishCaught","honorableKills","flights","deaths"}

function I.professions(snapshot)
    local rows={}
    for _,key in ipairs(I.professionKeys) do
        rows[#rows+1]={key=key,label=I.byKey[key][3],highest=I.byKey[key][5]==true,n=I.numeric(snapshot,key)}
    end
    table.sort(rows,function(a,b)
        if a.n==nil and b.n~=nil then return false end
        if b.n==nil and a.n~=nil then return true end
        if a.n~=b.n then return a.n>b.n end
        return a.label<b.label
    end)
    return rows
end

-- Transparent, descriptive thresholds, not a trained legitimacy classifier.
-- Related counters are grouped: disenchant outputs and profession ranks never
-- count as independent activities within their own group. Wealth is excluded.
function I.assess(snapshot)
    local known,total,positive,meaningful=0,0,0,0
    local evidence={}
    local function number(key)
        local n=I.numeric(snapshot,key)
        total=total+1;if n~=nil then known=known+1 end
        return n
    end
    local quests,kills,dungeons=number("questCount"),number("kills"),number("dungeons")
    local pvp,de,materials,fish=number("honorableKills"),number("disenchanted"),number("disenchantMaterials"),number("fishCaught")
    local maxRank,rankKnown,rankPositive=0,0,0
    for _,key in ipairs(I.professionKeys) do
        local rank=number(key)
        if rank~=nil then rankKnown=rankKnown+1;maxRank=math.max(maxRank,rank) end
        if rank and rank>1 then rankPositive=rankPositive+1 end
    end
    local function atLeast(n,threshold) return n~=nil and n>=threshold end
    local function group(hasActivity,substantial)
        if hasActivity then positive=positive+1 end
        if substantial then meaningful=meaningful+1 end
    end
    group(atLeast(quests,1),atLeast(quests,10))
    group(atLeast(kills,1) or atLeast(pvp,1),atLeast(kills,50) or atLeast(pvp,5))
    group(atLeast(dungeons,1),atLeast(dungeons,2))
    group(rankPositive>0,maxRank>=50)
    group(atLeast(de,1) or atLeast(materials,1),atLeast(de,20))
    group(atLeast(fish,1),atLeast(fish,20))
    local adventure=atLeast(quests,10) or atLeast(kills,50) or atLeast(pvp,5) or atLeast(dungeons,2)
    local trade=atLeast(I.numeric(snapshot,"posted"),20) or atLeast(I.numeric(snapshot,"purchases"),20)
    local crafting=atLeast(de,20) or maxRank>=50
    local out={key="unknown",title="Not enough data",summary="A readable gameplay snapshot is needed before assessing activity.",tone="muted"}
    if meaningful>=3 and adventure then
        out.key="active";out.title="Consistent with active play";out.tone="positive"
        out.summary="Substantial activity across "..meaningful.." of 6 gameplay areas supports a played-character profile."
    elseif (crafting or trade) and not adventure then
        out.key="specialist";out.title="Crafting / trading profile";out.tone="neutral"
        out.summary="Crafting or market activity is visible; a specialist or bank alt could have this record."
    elseif positive>0 then
        out.key="some";out.title="Gameplay activity recorded";out.tone="neutral"
        out.summary="Activity appears in "..positive.." of 6 gameplay areas; there is limited evidence of broader play."
    elseif known>0 then
        out.key="limited";out.title="Little gameplay recorded";out.tone="muted"
        out.summary="Readable counters show little activity. A new character or bank alt can have this record."
    end
    for _,key in ipairs({"questCount","kills","dungeons","honorableKills","disenchanted","disenchantMaterials","fishCaught"}) do
        evidence[#evidence+1]=I.byKey[key][3]..": "..I.value(snapshot,key,true)
    end
    evidence[#evidence+1]="Professions: "..rankPositive.." with recorded ranks above 1; "..rankKnown.." / "..#I.professionKeys.." readable. Historical ranks can include unlearned professions."
    if trade then evidence[#evidence+1]="Market activity: "..I.value(snapshot,"posted",true).." auctions posted; "..I.value(snapshot,"purchases",true).." purchases." end
    out.coverage=known.." / "..total.." assessment counters readable · missing is not zero"
    out.known=known;out.total=total;out.positive=positive;out.meaningful=meaningful;out.evidence=evidence
    return out
end

I.ASSESSMENT_RULES = "Broad activity requires 3 of 6 areas: 10 quests; 50 creature kills or 5 honorable kills; 2 dungeon entries; a profession rank of 50; 20 disenchants; or 20 fish caught. At least one qualifying area must be questing, combat or dungeons. These are simple heuristics, not validated probabilities. Gold amounts never affect this assessment."
