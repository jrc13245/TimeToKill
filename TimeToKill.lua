local lastCheckTime = 0;
local checkInterval = 0.1;

-- SuperWoW detection
local isSuperWoW = SUPERWOW_VERSION ~= nil;
local hasGUIDSupport = false;
local hasCombatLogSupport = false;

if not TimeToKill then
    TimeToKill = {};
end

if not TimeToKill.Settings then
    TimeToKill.Settings = {};

    TimeToKill.Settings.isLocked = false;
    TimeToKill.Settings.isNameVisible = true;
    TimeToKill.Settings.combatHide = false;
    TimeToKill.Settings.smoothingFactor = 0.3;  -- EMA smoothing (0.1-0.5, lower = more smoothing)
    TimeToKill.Settings.minSampleTime = 2.0;    -- Minimum seconds before showing prediction
    TimeToKill.Settings.conservativeFactor = 0.95;  -- Multiply final result (0.9-1.0)
    TimeToKill.Settings.useCombatLog = true;  -- Use RAW_COMBATLOG for damage tracking
    TimeToKill.Settings.burstThreshold = 3.0;    -- Ignore DPS spikes > 3x average
end

local defaultPosition = {
    point = "BOTTOMLEFT",
    relativeTo = "UIParent",
    relativePoint = "BOTTOMLEFT",
    x = math.floor(GetScreenWidth() * 0.465),
    y = math.floor(GetScreenHeight() * 0.11)
};

TimeToKill.TTD = CreateFrame("Frame", "TimeToKillFrame", UIParent);

local inCombat = false;
local remainingSeconds = 0;
local isMoving = false;

-- Per-target tracking
local targetTracking = {};
local currentTargetGUID = nil;
local lastTargetGUID = nil;

-- Combat log damage tracking (SuperWoW only)
local combatLogDamage = {};  -- [targetGUID] = { totalDamage, startTime, lastUpdate }

local ttdFrame = TimeToKill.TTD;
ttdFrame:SetFrameStrata("HIGH");
ttdFrame:SetWidth(100);
ttdFrame:SetHeight(50);

local textTimeTillDeath = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textTimeTillDeath:SetFont("Fonts\\FRIZQT__.TTF", 99, "OUTLINE, MONOCHROME");
textTimeTillDeath:SetPoint("CENTER", 0, -20);

local textTimeTillDeathText = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textTimeTillDeathText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE, MONOCHROME");
textTimeTillDeathText:SetPoint("CENTER", 0, 0);

-- SuperWoW capability detection
local function DetectSuperWoWCapabilities()
    if not isSuperWoW then
        return;
    end
    
    -- Test for GUID support in UnitExists
    local success, result = pcall(function()
        local exists, guid = UnitExists("player");
        if guid and type(guid) == "string" and string.len(guid) > 0 then
            return true;
        end
        return false;
    end);
    
    hasGUIDSupport = success and result;
    
    -- Combat log support is available if SuperWoW is present
    hasCombatLogSupport = true;
    
    if hasGUIDSupport then
        DEFAULT_CHAT_FRAME:AddMessage("TimeToKill: SuperWoW GUID support detected.");
    end
    if hasCombatLogSupport and TimeToKill.Settings.useCombatLog then
        DEFAULT_CHAT_FRAME:AddMessage("TimeToKill: SuperWoW combat log tracking enabled.");
    end
end

local function ApplyLockState()
    if TimeToKill.Settings.isLocked then
        ttdFrame:EnableMouse(false);
    else
        ttdFrame:EnableMouse(true);
    end
end

local function UpdateNameVisibility()
    if TimeToKill.Settings.isNameVisible then
        textTimeTillDeathText:Show();
    else
        textTimeTillDeathText:Hide();
    end
end

local function ApplyCombatHideState()
    if TimeToKill.Settings.combatHide then
        if inCombat then
            ttdFrame:Show();
        else
            ttdFrame:Hide();
        end
    else
        ttdFrame:Show();
    end
end

local function ApplyFramePosition()
    if not TimeToKill.Position then
        TimeToKill.Position = {};
    end

    local positionDetails = TimeToKill.Position;
    local effectiveRelativeTo = nil;
    local currentPositionConfig = {};

    if positionDetails.point and positionDetails.relativeTo and type(positionDetails.relativeTo) == "string" then
        local foundGlobalFrame = getglobal(positionDetails.relativeTo);
        if foundGlobalFrame and type(foundGlobalFrame) == "table" and foundGlobalFrame.SetPoint then
            effectiveRelativeTo = foundGlobalFrame;
            currentPositionConfig.point = positionDetails.point;
            currentPositionConfig.relativeTo = positionDetails.relativeTo;
            currentPositionConfig.relativePoint = positionDetails.relativePoint;
            currentPositionConfig.x = positionDetails.x;
            currentPositionConfig.y = positionDetails.y;
        end
    end

    if not effectiveRelativeTo then
        effectiveRelativeTo = getglobal(defaultPosition.relativeTo);

        if not (effectiveRelativeTo and type(effectiveRelativeTo) == "table" and effectiveRelativeTo.SetPoint) then
            effectiveRelativeTo = UIParent;

            currentPositionConfig.point = "CENTER";
            currentPositionConfig.relativeTo = "UIParent";
            currentPositionConfig.relativePoint = "CENTER";
            currentPositionConfig.x = 0;
            currentPositionConfig.y = 0;
        else
            currentPositionConfig.point = defaultPosition.point;
            currentPositionConfig.relativeTo = defaultPosition.relativeTo;
            currentPositionConfig.relativePoint = defaultPosition.relativePoint;
            currentPositionConfig.x = defaultPosition.x;
            currentPositionConfig.y = defaultPosition.y;
        end

        TimeToKill.Position.point = currentPositionConfig.point;
        TimeToKill.Position.relativeTo = currentPositionConfig.relativeTo;
        TimeToKill.Position.relativePoint = currentPositionConfig.relativePoint;
        TimeToKill.Position.x = currentPositionConfig.x;
        TimeToKill.Position.y = currentPositionConfig.y;
    end

    if effectiveRelativeTo and type(effectiveRelativeTo) == "table" and effectiveRelativeTo.SetPoint then
        ttdFrame:ClearAllPoints();
        ttdFrame:SetPoint(
            currentPositionConfig.point,
            effectiveRelativeTo,
            currentPositionConfig.relativePoint,
            currentPositionConfig.x,
            currentPositionConfig.y
        );
    else
        ttdFrame:ClearAllPoints();
        ttdFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);

        TimeToKill.Position.point = "CENTER";
        TimeToKill.Position.relativeTo = "UIParent";
        TimeToKill.Position.relativePoint = "CENTER";
        TimeToKill.Position.x = 0;
        TimeToKill.Position.y = 0;
    end
end

ttdFrame:Show();
ttdFrame:SetMovable(true);

ttdFrame:SetScript("OnMouseDown", function(_, button)
    if not ttdFrame or not ttdFrame.StartMoving then
        isMoving = false;
        return;
    end

    if IsShiftKeyDown() then
        isMoving = true;

        local success, err = pcall(ttdFrame.StartMoving, ttdFrame);
        if not success then
            isMoving = false;
        end
    end
end);

ttdFrame:SetScript("OnMouseUp", function(_, button)
    if not ttdFrame then
        isMoving = false;
        return;
    end

    if not ttdFrame.StopMovingOrSizing or not ttdFrame.GetLeft or not ttdFrame.GetBottom or not ttdFrame.GetName then
        isMoving = false;
        return;
    end

    local stopSuccess, stopError = pcall(ttdFrame.StopMovingOrSizing, ttdFrame);

    if not stopSuccess then
        isMoving = false;
        return;
    end

    isMoving = false;

    if not TimeToKill then
        return;
    end
    if not TimeToKill.Position then
        TimeToKill.Position = {};
    end

    local screenX, screenY
    local getLeftSuccess, getLeftVal = pcall(ttdFrame.GetLeft, ttdFrame);
    if not getLeftSuccess then
        return;
    end
    screenX = getLeftVal;

    local getBottomSuccess, getBottomVal = pcall(ttdFrame.GetBottom, ttdFrame);
    if not getBottomSuccess then
        return;
    end
    screenY = getBottomVal;

    TimeToKill.Position.point = "BOTTOMLEFT";
    TimeToKill.Position.relativeTo = "UIParent";
    TimeToKill.Position.relativePoint = "BOTTOMLEFT";
    TimeToKill.Position.x = screenX;
    TimeToKill.Position.y = screenY;
end);

local timeSinceLastUpdate = 0;

local function TTD_Show()
    if (inCombat) then
        if TimeToKill.Settings.isNameVisible then
             textTimeTillDeathText:SetText("Time Till Death:");
        else
             textTimeTillDeathText:SetText("");
        end
    end
end

local function TTD_Hide()
    textTimeTillDeath:SetText("-.--");
end

-- Get GUID for target (SuperWoW-aware)
local function GetTargetGUID()
    if hasGUIDSupport then
        local exists, guid = UnitExists("target");
        if exists and guid and type(guid) == "string" and string.len(guid) > 0 then
            return guid;
        end
    end
    
    -- Fallback to name-based identifier
    local name = UnitName("target");
    if name then
        -- For bosses (level -1), use name + maxHP to differentiate instances
        local level = UnitLevel("target");
        if level and level > 0 then
            return name .. "_L" .. level;
        elseif level and level == -1 then
            -- Boss - use name + health to differentiate
            local maxHP = UnitHealthMax("target");
            if maxHP and maxHP > 0 then
                return name .. "_B" .. maxHP;
            end
        end
        return name;
    end
    
    return nil;
end

-- Get or create target tracking data
local function GetTargetData(guid)
    if not targetTracking[guid] then
        targetTracking[guid] = {
            firstSeen = GetTime(),
            lastUpdate = GetTime(),
            initialHP = nil,
            initialMaxHP = nil,
            lastHP = nil,
            lastHPTime = nil,
            name = nil,
            -- Exponential moving average DPS
            emaDPS = nil,
            -- Simple average for comparison
            avgDPS = nil,
            totalDamageDone = 0,
            -- Burst detection
            maxDPS = 0,
            minDPS = 999999,
            -- Sample tracking
            sampleCount = 0
        };
    end
    return targetTracking[guid];
end

-- Clean up old target data (keep last 10 targets)
local function CleanupTargetData()
    local count = 0;
    for _ in pairs(targetTracking) do
        count = count + 1;
    end
    
    if count > 10 then
        local oldest = nil;
        local oldestTime = GetTime();
        
        for guid, data in pairs(targetTracking) do
            if guid ~= currentTargetGUID and data.lastUpdate < oldestTime then
                oldestTime = data.lastUpdate;
                oldest = guid;
            end
        end
        
        if oldest then
            targetTracking[oldest] = nil;
            if combatLogDamage[oldest] then
                combatLogDamage[oldest] = nil;
            end
        end
    end
end

-- Calculate instantaneous DPS from HP change
local function CalculateInstantDPS(targetData, currentHP, currentTime)
    if not targetData.lastHP or not targetData.lastHPTime then
        return nil;
    end
    
    local timeDiff = currentTime - targetData.lastHPTime;
    local hpDiff = targetData.lastHP - currentHP;
    
    if timeDiff <= 0 or hpDiff <= 0 then
        return nil;
    end
    
    return hpDiff / timeDiff;
end

-- Update DPS using exponential moving average
local function UpdateDPS(targetData, currentHP, currentTime)
    local instantDPS = CalculateInstantDPS(targetData, currentHP, currentTime);
    
    if not instantDPS or instantDPS <= 0 then
        -- Just update last HP for next calculation
        targetData.lastHP = currentHP;
        targetData.lastHPTime = currentTime;
        return false;
    end
    
    targetData.sampleCount = targetData.sampleCount + 1;
    
    -- Track min/max for burst detection
    if instantDPS > targetData.maxDPS then
        targetData.maxDPS = instantDPS;
    end
    if instantDPS < targetData.minDPS then
        targetData.minDPS = instantDPS;
    end
    
    -- Burst detection - ignore outliers
    if targetData.emaDPS and targetData.emaDPS > 0 then
        local ratio = instantDPS / targetData.emaDPS;
        if ratio > TimeToKill.Settings.burstThreshold or ratio < (1 / TimeToKill.Settings.burstThreshold) then
            -- This is a burst spike, don't update EMA but still track last HP
            targetData.lastHP = currentHP;
            targetData.lastHPTime = currentTime;
            return false;
        end
    end
    
    -- Update exponential moving average
    if not targetData.emaDPS then
        targetData.emaDPS = instantDPS;
        targetData.avgDPS = instantDPS;
    else
        local alpha = TimeToKill.Settings.smoothingFactor;
        targetData.emaDPS = (alpha * instantDPS) + ((1 - alpha) * targetData.emaDPS);
        
        -- Also track simple average for comparison
        targetData.avgDPS = ((targetData.avgDPS * (targetData.sampleCount - 1)) + instantDPS) / targetData.sampleCount;
    end
    
    -- Update last HP tracking
    targetData.lastHP = currentHP;
    targetData.lastHPTime = currentTime;
    targetData.lastUpdate = currentTime;
    
    return true;
end

-- Get DPS from combat log tracking (SuperWoW)
local function GetCombatLogDPS(guid, currentTime)
    if not hasCombatLogSupport or not TimeToKill.Settings.useCombatLog then
        return nil;
    end
    
    local logData = combatLogDamage[guid];
    if not logData or logData.totalDamage <= 0 or not logData.startTime then
        return nil;
    end
    
    local elapsed = currentTime - logData.startTime;
    if elapsed <= 0 then
        return nil;
    end
    
    return logData.totalDamage / elapsed;
end

-- Hybrid DPS calculation
local function GetBestDPS(targetData, guid, currentTime)
    local hpDPS = targetData.emaDPS;
    local logDPS = GetCombatLogDPS(guid, currentTime);
    
    -- If we have both, blend them
    if hpDPS and logDPS and hpDPS > 0 and logDPS > 0 then
        -- Weight combat log more heavily as it's more accurate
        return (hpDPS * 0.3) + (logDPS * 0.7);
    end
    
    -- Return whichever we have
    if logDPS and logDPS > 0 then
        return logDPS;
    end
    
    if hpDPS and hpDPS > 0 then
        return hpDPS;
    end
    
    return nil;
end

-- Check if target should reset (resurrected/reset)
local function ShouldResetTarget(targetData, currentHP, maxHP)
    if not targetData.initialHP or not targetData.initialMaxHP then
        return false;
    end
    
    -- If HP increased significantly, target was healed/reset
    if targetData.lastHP and currentHP > targetData.lastHP + (maxHP * 0.15) then
        return true;
    end
    
    -- If max HP changed, it's likely a different mob
    if maxHP ~= targetData.initialMaxHP then
        return true;
    end
    
    return false;
end

-- Special boss handling
local bosses = {
    ["Vaelastrasz the Corrupt"] = { effectiveHPPercent = 0.30 },  -- Dies at 30%
    -- Add more bosses here as needed
};

local function GetEffectiveMaxHP(targetName, maxHP)
    if bosses[targetName] then
        return maxHP * bosses[targetName].effectiveHPPercent;
    end
    return maxHP;
end

-- Parse combat log damage (SuperWoW RAW_COMBATLOG)
local function ParseCombatLogDamage(eventText)
    if not hasCombatLogSupport or not TimeToKill.Settings.useCombatLog or not currentTargetGUID then
        return;
    end
    
    -- Pattern 1: Direct damage - "hits/crits <targetGUID> for <damage>"
    -- Example: "0x0000000000581AB8's Swipe crits 0xF130003E6D269BEA for 287."
    local _, _, targetGUID, damage = string.find(eventText, " (0x%x+) for (%d+)");
    
    -- Pattern 2: DoT/suffer damage - "<targetGUID> suffers <damage>"
    -- Example: "0xF130003E6D269BE6 suffers 34 Physical damage from"
    if not targetGUID then
        _, _, targetGUID, damage = string.find(eventText, "^[^%s]+ [^%s]+ (0x%x+) suffers (%d+)");
    end
    
    if targetGUID and damage and targetGUID == currentTargetGUID then
        local dmgValue = tonumber(damage);
        if dmgValue and dmgValue > 0 then
            if not combatLogDamage[targetGUID] then
                combatLogDamage[targetGUID] = {
                    totalDamage = 0,
                    startTime = GetTime(),
                    lastUpdate = GetTime()
                };
            end
            
            combatLogDamage[targetGUID].totalDamage = combatLogDamage[targetGUID].totalDamage + dmgValue;
            combatLogDamage[targetGUID].lastUpdate = GetTime();
        end
    end
end

local function TTDLogic()
    if not (UnitIsEnemy("player", "target") or UnitReaction("player", "target") == 4) then
        textTimeTillDeath:SetText("-.--");
        currentTargetGUID = nil;
        return;
    end
    
    -- Get target GUID (SuperWoW-aware)
    local guid = GetTargetGUID();
    
    if not guid then
        textTimeTillDeath:SetText("-.--");
        currentTargetGUID = nil;
        return;
    end
    
    local targetName = UnitName("target");
    local currentHP = UnitHealth("target");
    local maxHP = UnitHealthMax("target");
    
    if not maxHP or maxHP <= 0 or not currentHP then
        textTimeTillDeath:SetText("-.--");
        return;
    end
    
    -- Detect target switch
    local targetChanged = (guid ~= currentTargetGUID);
    if targetChanged then
        lastTargetGUID = currentTargetGUID;
        currentTargetGUID = guid;
        CleanupTargetData();
    end
    
    local targetData = GetTargetData(guid);
    targetData.name = targetName;
    
    local currentTime = GetTime();
    
    -- Initialize or reset if needed
    if not targetData.initialHP or ShouldResetTarget(targetData, currentHP, maxHP) then
        targetData.initialHP = currentHP;
        targetData.initialMaxHP = maxHP;
        targetData.firstSeen = currentTime;
        targetData.lastHP = currentHP;
        targetData.lastHPTime = currentTime;
        targetData.lastUpdate = currentTime;
        targetData.emaDPS = nil;
        targetData.avgDPS = nil;
        targetData.maxDPS = 0;
        targetData.minDPS = 999999;
        targetData.sampleCount = 0;
        targetData.totalDamageDone = 0;
        
        -- Reset combat log tracking
        if combatLogDamage[guid] then
            combatLogDamage[guid] = {
                totalDamage = 0,
                startTime = currentTime,
                lastUpdate = currentTime
            };
        end
    end
    
    -- Update DPS calculation
    UpdateDPS(targetData, currentHP, currentTime);
    
    -- Calculate effective max HP for special bosses
    local effectiveMaxHP = GetEffectiveMaxHP(targetName, maxHP);
    
    -- Need minimum sample time before showing prediction
    local timeSinceFirstSeen = currentTime - targetData.firstSeen;
    if timeSinceFirstSeen < TimeToKill.Settings.minSampleTime then
        textTimeTillDeath:SetText("-.--");
        return;
    end
    
    -- Need at least 3 samples for reasonable accuracy
    if targetData.sampleCount < 3 then
        textTimeTillDeath:SetText("-.--");
        return;
    end
    
    -- Get best DPS estimate
    local dps = GetBestDPS(targetData, guid, currentTime);
    
    if not dps or dps <= 0 then
        textTimeTillDeath:SetText("-.--");
        return;
    end
    
    -- Calculate time to death
    local remainingHP = currentHP;
    if currentHP > effectiveMaxHP then
        remainingHP = effectiveMaxHP;
    end
    
    -- Apply conservative factor to account for optimistic predictions
    remainingSeconds = (remainingHP / dps) * (1 / TimeToKill.Settings.conservativeFactor);
    
    -- Sanity checks
    if remainingSeconds ~= remainingSeconds or remainingSeconds < 0 or remainingSeconds > 3600 then
        textTimeTillDeath:SetText("-.--");
    else
        textTimeTillDeath:SetText(string.format("%.2f", remainingSeconds));
    end
end

function onUpdate(sinceLastUpdate)
    if not isMoving then
        timeSinceLastUpdate = GetTime();

        if GetTime()-lastCheckTime >= checkInterval then
            if (lastCheckTime == 0) then
                lastCheckTime = GetTime();
            end

            TTDLogic();

            lastCheckTime = GetTime();
        end
    end
end
TimeToKill.TTD:SetScript("OnUpdate", function(self) if inCombat then onUpdate(timeSinceLastUpdate); end; end);

TimeToKill.TTD:SetScript("OnShow", function(self)
    timeSinceLastUpdate = 0;
end);

TimeToKill.TTD:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        if not TimeToKill.Settings then TimeToKill.Settings = {} end
        if TimeToKill.Settings.isLocked == nil then TimeToKill.Settings.isLocked = false; end
        if TimeToKill.Settings.isNameVisible == nil then TimeToKill.Settings.isNameVisible = true; end
        if TimeToKill.Settings.combatHide == nil then TimeToKill.Settings.combatHide = false; end
        if TimeToKill.Settings.smoothingFactor == nil then TimeToKill.Settings.smoothingFactor = 0.3; end
        if TimeToKill.Settings.minSampleTime == nil then TimeToKill.Settings.minSampleTime = 2.0; end
        if TimeToKill.Settings.conservativeFactor == nil then TimeToKill.Settings.conservativeFactor = 0.95; end
        if TimeToKill.Settings.useCombatLog == nil then TimeToKill.Settings.useCombatLog = true; end
        if TimeToKill.Settings.burstThreshold == nil then TimeToKill.Settings.burstThreshold = 3.0; end

        DetectSuperWoWCapabilities();
        
        ApplyFramePosition();
        ApplyLockState();
        UpdateNameVisibility();
        ApplyCombatHideState();
        if not inCombat then
            TTD_Hide();
        end
    elseif event == "ADDON_LOADED" then
        if arg1 == "TimeToKill" then
            if TimeToKill.Settings == nil then
                TimeToKill.Settings = {};
            end
            if TimeToKill.Settings.isLocked == nil then
                TimeToKill.Settings.isLocked = false;
            end
            if TimeToKill.Settings.isNameVisible == nil then
                TimeToKill.Settings.isNameVisible = true;
            end
            if TimeToKill.Settings.combatHide == nil then
                TimeToKill.Settings.combatHide = false;
            end
            if TimeToKill.Settings.smoothingFactor == nil then
                TimeToKill.Settings.smoothingFactor = 0.3;
            end
            if TimeToKill.Settings.minSampleTime == nil then
                TimeToKill.Settings.minSampleTime = 2.0;
            end
            if TimeToKill.Settings.conservativeFactor == nil then
                TimeToKill.Settings.conservativeFactor = 0.95;
            end
            if TimeToKill.Settings.useCombatLog == nil then
                TimeToKill.Settings.useCombatLog = true;
            end
            if TimeToKill.Settings.burstThreshold == nil then
                TimeToKill.Settings.burstThreshold = 3.0;
            end

            DetectSuperWoWCapabilities();
            
            ApplyFramePosition();
            ApplyLockState();
            UpdateNameVisibility();
            ApplyCombatHideState();
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true;
        ApplyCombatHideState();
        TTD_Show();
        UpdateNameVisibility();
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false;
        TTD_Hide();
        textTimeTillDeathText:SetText("");
        UpdateNameVisibility();
        ApplyCombatHideState();
        -- Don't clear target tracking immediately - keep for analysis
    elseif event == "PLAYER_DEAD" then
        inCombat = false;
        TTD_Hide();
        ApplyCombatHideState();
    elseif event == "RAW_COMBATLOG" then
        -- SuperWoW raw combat log event
        -- arg1: original event name
        -- arg2: event text with GUIDs
        if arg2 then
            ParseCombatLogDamage(arg2);
        end
    end
end);

TimeToKill.TTD:RegisterEvent("PLAYER_LOGIN");
TimeToKill.TTD:RegisterEvent("ADDON_LOADED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_ENABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_DISABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_DEAD");

-- Register SuperWoW events if available
if isSuperWoW then
    TimeToKill.TTD:RegisterEvent("RAW_COMBATLOG");
end

SLASH_TIMETOKILL1 = "/ttk";
SlashCmdList["TIMETOKILL"] = function(msg)
    local args = {};
    local i = 1;
    while true do
        local next_space = string.find(msg, " ", i);
        if not next_space then
            table.insert(args, string.sub(msg, i));
            break;
        end
        table.insert(args, string.sub(msg, i, next_space - 1));
        i = next_space + 1;
    end

    if args[1] == nil or args[1] == "" then
        print("TimeToKill Usage:");
        print("|cFF33FF99/ttk lock|r - Lock frame (click-through).");
        print("|cFF33FF99/ttk unlock|r - Unlock frame (Shift-drag to move).");
        print("|cFF33FF99/ttk name on|r - Show 'Time Till Death:' text.");
        print("|cFF33FF99/ttk name off|r - Hide 'Time Till Death:' text.");
        print("|cFF33FF99/ttk combathide on|r - Hide frame when out of combat.");
        print("|cFF33FF99/ttk combathide off|r - Keep frame visible.");
        print("|cFF33FF99/ttk smooth <0.1-0.5>|r - EMA smoothing (default 0.3).");
        print("|cFF33FF99/ttk conservative <0.9-1.0>|r - Conservative factor (default 0.95).");
        print("|cFF33FF99/ttk minsample <seconds>|r - Min sample time (default 2.0).");
        print("|cFF33FF99/ttk burst <multiplier>|r - Burst threshold (default 3.0).");
        if isSuperWoW then
            print("|cFF33FF99/ttk combatlog on|r - Enable combat log tracking.");
            print("|cFF33FF99/ttk combatlog off|r - Disable combat log tracking.");
        end
        print("|cFF33FF99/ttk debug|r - Show debug info.");
        print("|cFF33FF99/ttk status|r - Show addon status.");
        return;
    end

    local command = string.lower(args[1]);
    local option = args[2] and string.lower(args[2]) or nil;

    if command == "lock" then
        TimeToKill.Settings.isLocked = true;
        ApplyLockState();
        print("TimeToKill: Frame locked.");
    elseif command == "unlock" then
        TimeToKill.Settings.isLocked = false;
        ApplyLockState();
        print("TimeToKill: Frame unlocked. Shift-drag to move.");
    elseif command == "name" then
        if option == "on" then
            TimeToKill.Settings.isNameVisible = true;
            UpdateNameVisibility();
            if inCombat then TTD_Show(); end
            print("TimeToKill: Name text enabled.");
        elseif option == "off" then
            TimeToKill.Settings.isNameVisible = false;
            UpdateNameVisibility();
            print("TimeToKill: Name text disabled.");
        else
            print("TimeToKill: Usage: /ttk name [on|off]");
        end
    elseif command == "combathide" then
        if option == "on" then
            TimeToKill.Settings.combatHide = true;
            ApplyCombatHideState();
            print("TimeToKill: Combat hide enabled.");
        elseif option == "off" then
            TimeToKill.Settings.combatHide = false;
            ApplyCombatHideState();
            print("TimeToKill: Combat hide disabled.");
        else
            print("TimeToKill: Usage: /ttk combathide [on|off]");
        end
    elseif command == "smooth" then
        if option then
            local value = tonumber(option);
            if value and value >= 0.1 and value <= 0.5 then
                TimeToKill.Settings.smoothingFactor = value;
                print("TimeToKill: Smoothing factor set to " .. value);
            else
                print("TimeToKill: Value must be between 0.1 and 0.5");
            end
        else
            print("TimeToKill: Current smoothing: " .. TimeToKill.Settings.smoothingFactor);
        end
    elseif command == "conservative" then
        if option then
            local value = tonumber(option);
            if value and value >= 0.9 and value <= 1.0 then
                TimeToKill.Settings.conservativeFactor = value;
                print("TimeToKill: Conservative factor set to " .. value);
            else
                print("TimeToKill: Value must be between 0.9 and 1.0");
            end
        else
            print("TimeToKill: Current conservative factor: " .. TimeToKill.Settings.conservativeFactor);
        end
    elseif command == "minsample" then
        if option then
            local value = tonumber(option);
            if value and value >= 0.5 and value <= 10.0 then
                TimeToKill.Settings.minSampleTime = value;
                print("TimeToKill: Minimum sample time set to " .. value .. "s");
            else
                print("TimeToKill: Value must be between 0.5 and 10.0");
            end
        else
            print("TimeToKill: Current minimum sample time: " .. TimeToKill.Settings.minSampleTime .. "s");
        end
    elseif command == "burst" then
        if option then
            local value = tonumber(option);
            if value and value >= 1.5 and value <= 10.0 then
                TimeToKill.Settings.burstThreshold = value;
                print("TimeToKill: Burst threshold set to " .. value .. "x");
            else
                print("TimeToKill: Value must be between 1.5 and 10.0");
            end
        else
            print("TimeToKill: Current burst threshold: " .. TimeToKill.Settings.burstThreshold .. "x");
        end
    elseif command == "combatlog" then
        if not isSuperWoW then
            print("TimeToKill: Combat log tracking requires SuperWoW.");
            return;
        end
        if option == "on" then
            TimeToKill.Settings.useCombatLog = true;
            print("TimeToKill: Combat log tracking enabled.");
        elseif option == "off" then
            TimeToKill.Settings.useCombatLog = false;
            print("TimeToKill: Combat log tracking disabled.");
        else
            print("TimeToKill: Usage: /ttk combatlog [on|off]");
        end
    elseif command == "status" then
        print("=== TimeToKill Status ===");
        if isSuperWoW then
            print("SuperWoW: |cFF00FF00v" .. (SUPERWOW_VERSION or "?") .. "|r");
            print("GUID: " .. (hasGUIDSupport and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"));
            print("Combat Log: " .. (TimeToKill.Settings.useCombatLog and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"));
        else
            print("SuperWoW: |cFFFF0000Not Detected|r");
        end
        print("Settings:");
        print("  Smoothing: " .. TimeToKill.Settings.smoothingFactor);
        print("  Conservative: " .. TimeToKill.Settings.conservativeFactor);
        print("  Min Sample: " .. TimeToKill.Settings.minSampleTime .. "s");
        print("  Burst Threshold: " .. TimeToKill.Settings.burstThreshold .. "x");
        local count = 0;
        for _ in pairs(targetTracking) do count = count + 1; end
        print("  Tracked Targets: " .. count);
    elseif command == "debug" then
        if currentTargetGUID and targetTracking[currentTargetGUID] then
            local data = targetTracking[currentTargetGUID];
            print("=== TimeToKill Debug ===");
            print("Target: " .. (data.name or "Unknown"));
            print("GUID: " .. (hasGUIDSupport and currentTargetGUID or "(fallback)"));
            print("Combat time: " .. string.format("%.2f", GetTime() - data.firstSeen) .. "s");
            print("Samples: " .. data.sampleCount);
            if data.emaDPS then
                print("EMA DPS: " .. string.format("%.2f", data.emaDPS));
            end
            if data.avgDPS then
                print("Avg DPS: " .. string.format("%.2f", data.avgDPS));
            end
            print("Max DPS: " .. string.format("%.2f", data.maxDPS));
            print("Min DPS: " .. string.format("%.2f", data.minDPS));
            if hasCombatLogSupport and combatLogDamage[currentTargetGUID] then
                local logData = combatLogDamage[currentTargetGUID];
                print("Log Damage: " .. logData.totalDamage);
                local elapsed = GetTime() - logData.startTime;
                if elapsed > 0 and logData.totalDamage > 0 then
                    local logDPS = logData.totalDamage / elapsed;
                    print("Log DPS: " .. string.format("%.2f", logDPS));
                end
            end
        else
            print("TimeToKill: No target data available.");
        end
    else
        print("TimeToKill: Unknown command. Type /ttk for help.");
    end
end;
