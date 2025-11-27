local lastCheckTime = 0;
local checkInterval = 0.1;

-- Display smoothing factor (lower = smoother but slower to respond)
local DISPLAY_SMOOTHING = 0.15;

-- Thresholds and constants
local EXECUTE_THRESHOLD = 0.20;  -- 20% HP
local WARNING_THRESHOLD = 40;    -- Seconds
local SAMPLE_INTERVAL = 1.0;     -- Sample every 1 second

-- Test mode flag
local testMode = false;

-- SuperWoW detection
local isSuperWoW = SUPERWOW_VERSION ~= nil;
local hasGUIDSupport = false;
local hasCombatLogSupport = false;

-- ============================================================================
-- RLS ESTIMATOR (Recursive Least Squares with Forgetting Factor)
-- ============================================================================
local RLS = {}
RLS.name = "RLS"
RLS.lambda = 0.95           -- Forgetting factor (0.9-0.99 typical)
RLS.lambdaFast = 0.85       -- Faster adaptation after detected change
RLS.initialP = 1000000      -- Initial covariance (large = uncertain)
RLS.minSamples = 3
RLS.changeThreshold = 3.0   -- Std devs for change detection

function RLS:new()
    local obj = {
        theta = 0,               -- DPS estimate
        P = self.initialP,       -- Covariance (uncertainty)
        lastHP = nil,
        lastTime = nil,
        sampleCount = 0,
        currentLambda = self.lambda,
        residualMA = 0,          -- Moving average of residuals
        residualVar = 1000,      -- Variance of residuals
        adaptCountdown = 0       -- Countdown for fast adaptation mode
    }
    setmetatable(obj, {__index = self})
    return obj
end

function RLS:addSample(hp, maxHp, t)
    self.sampleCount = self.sampleCount + 1

    if not self.lastHP or not self.lastTime then
        self.lastHP = hp
        self.lastTime = t
        return
    end

    local dt = t - self.lastTime
    if dt < 0.01 then return end  -- Skip tiny intervals

    -- Compute observed DPS for this interval
    local dhp = self.lastHP - hp  -- Positive when HP decreasing
    local observedDPS = dhp / dt

    -- Skip if no meaningful damage (immunity, intermission, healing)
    if dhp < -100 then
        self.lastHP = hp
        self.lastTime = t
        return
    end

    -- Change detection: large residual indicates regime change
    local residual = observedDPS - self.theta
    local stdResidual = math.abs(residual) / math.sqrt(math.max(1, self.residualVar))

    if stdResidual > self.changeThreshold and self.sampleCount > 5 then
        -- Detected significant change - increase adaptation
        self.adaptCountdown = 10
        self.P = self.P * 10  -- Increase uncertainty
    end

    -- Use faster lambda during adaptation period
    local effectiveLambda = self.currentLambda
    if self.adaptCountdown > 0 then
        effectiveLambda = self.lambdaFast
        self.adaptCountdown = self.adaptCountdown - 1
    end

    -- RLS update equations
    local K = self.P / (effectiveLambda + self.P)
    self.theta = self.theta + K * residual
    self.P = (1 / effectiveLambda) * (self.P - K * self.P)

    -- Prevent numerical issues
    if self.P > self.initialP then self.P = self.initialP end
    if self.P < 0.001 then self.P = 0.001 end

    -- Update residual statistics (for change detection)
    local alpha = 0.1
    self.residualMA = (1 - alpha) * self.residualMA + alpha * residual
    self.residualVar = (1 - alpha) * self.residualVar + alpha * residual * residual

    -- Ensure DPS stays non-negative for TTK calculation
    if self.theta < 0 then self.theta = 0 end

    self.lastHP = hp
    self.lastTime = t
end

function RLS:getDPS()
    if self.sampleCount < self.minSamples then return 0 end
    return math.max(0, self.theta)
end

function RLS:getTTK()
    if self.sampleCount < self.minSamples then return -1 end
    if not self.lastHP then return -1 end

    local dps = self:getDPS()
    if dps <= 0 then return -1 end

    return self.lastHP / dps
end

function RLS:reset()
    self.theta = 0
    self.P = self.initialP
    self.lastHP = nil
    self.lastTime = nil
    self.sampleCount = 0
    self.currentLambda = self.lambda
    self.residualMA = 0
    self.residualVar = 1000
    self.adaptCountdown = 0
end

-- ============================================================================
-- ADDON INITIALIZATION
-- ============================================================================

if not TimeToKill then
    TimeToKill = {};
end

if not TimeToKill.Settings then
    TimeToKill.Settings = {};

    TimeToKill.Settings.isLocked = false;
    TimeToKill.Settings.isNameVisible = true;
    TimeToKill.Settings.combatHide = false;
    TimeToKill.Settings.minSampleTime = 2.0;    -- Minimum seconds before showing prediction
    TimeToKill.Settings.conservativeFactor = 0.95;  -- Multiply final result (0.9-1.0)
    TimeToKill.Settings.showExecute = true;     -- Show execute phase timer
    TimeToKill.Settings.showDPS = true;         -- Show DPS display
    TimeToKill.Settings.showHP = true;          -- Show HP display
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
local targetTracking = {};  -- [guid] = { rls = RLS instance, name, initialHP, firstSeen }
local currentTargetGUID = nil;
local lastTargetGUID = nil;

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

-- DPS display (below TTK)
local textDPS = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textDPS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE, MONOCHROME");
textDPS:SetPoint("CENTER", 0, -40);
textDPS:SetTextColor(0.7, 0.7, 1.0);  -- Light blue

-- TTE display (Time to Execute - below DPS)
local textTTE = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textTTE:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE, MONOCHROME");
textTTE:SetPoint("CENTER", 0, -54);
textTTE:SetTextColor(1.0, 0.9, 0.9);  -- Light red

-- HP display (top)
local textHP = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textHP:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE, MONOCHROME");
textHP:SetPoint("CENTER", 0, 15);
textHP:SetTextColor(0.8, 0.8, 0.8);  -- Light gray

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
    textDPS:SetText("");
    textTTE:SetText("");
    textHP:SetText("");
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

-- Smooth a value for display
local function SmoothValue(current, target, factor)
    if not current or current < 0 then return target end
    if not target or target < 0 then return current end
    return current + (target - current) * factor
end

-- Format HP with K/M suffixes
local function FormatHP(hp)
    if hp >= 1000000 then
        return string.format("%.1fM", hp / 1000000)
    elseif hp >= 1000 then
        return string.format("%.0fK", hp / 1000)
    else
        return string.format("%.0f", hp)
    end
end

-- Format DPS with K/M suffixes
local function FormatDPS(dps)
    if not dps or dps <= 0 then return "0" end
    if dps >= 1000000 then
        return string.format("%.2fM", dps / 1000000)
    elseif dps >= 1000 then
        return string.format("%.1fK", dps / 1000)
    end
    return string.format("%.0f", dps)
end

-- Get or create target tracking data
local function GetTargetData(guid)
    if not targetTracking[guid] then
        targetTracking[guid] = {
            rlsTTK = RLS:new(),      -- Time to Kill (HP -> 0)
            rlsTTE = RLS:new(),      -- Time to Execute (HP -> 20%)
            name = nil,
            firstSeen = GetTime(),
            initialHP = nil,
            initialMaxHP = nil,
            lastSampleTime = 0,      -- For throttling samples
            smoothTTK = nil,         -- Smoothed TTK display value
            smoothTTE = nil          -- Smoothed TTE display value
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
            if guid ~= currentTargetGUID and data.firstSeen < oldestTime then
                oldestTime = data.firstSeen;
                oldest = guid;
            end
        end

        if oldest then
            targetTracking[oldest] = nil;
        end
    end
end

-- Check if target should reset (resurrected/reset)
local function ShouldResetTarget(targetData, currentHP, maxHP)
    if not targetData.initialHP or not targetData.initialMaxHP then
        return false;
    end

    -- If HP increased significantly, target was healed/reset
    local rlsLastHP = targetData.rlsTTK.lastHP
    if rlsLastHP and currentHP > rlsLastHP + (maxHP * 0.15) then
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

local function TTDLogic()
    -- Check if valid target (test mode tracks any enemy, normal mode tracks enemies or neutral)
    local isValidTarget = false;
    if testMode then
        isValidTarget = UnitExists("target") and UnitCanAttack("player", "target");
    else
        isValidTarget = UnitIsEnemy("player", "target") or UnitReaction("player", "target") == 4;
    end

    if not isValidTarget then
        textTimeTillDeath:SetText("-.--");
        textDPS:SetText("");
        textTTE:SetText("");
        textHP:SetText("");
        currentTargetGUID = nil;
        return;
    end

    -- Get target GUID (SuperWoW-aware)
    local guid = GetTargetGUID();

    if not guid then
        textTimeTillDeath:SetText("-.--");
        textDPS:SetText("");
        textTTE:SetText("");
        textHP:SetText("");
        currentTargetGUID = nil;
        return;
    end

    local targetName = UnitName("target");
    local currentHP = UnitHealth("target");
    local maxHP = UnitHealthMax("target");

    if not maxHP or maxHP <= 0 or not currentHP then
        textTimeTillDeath:SetText("-.--");
        textDPS:SetText("");
        textTTE:SetText("");
        textHP:SetText("");
        return;
    end

    local hpPercent = (currentHP / maxHP) * 100;

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
        targetData.lastSampleTime = 0;
        targetData.smoothTTK = nil;
        targetData.smoothTTE = nil;
        targetData.rlsTTK:reset();
        targetData.rlsTTE:reset();
    end

    -- Display HP
    if TimeToKill.Settings.showHP then
        textHP:SetText(string.format("%s / %s", FormatHP(currentHP), FormatHP(maxHP)));
    else
        textHP:SetText("");
    end

    -- Throttle samples to SAMPLE_INTERVAL (1 second)
    if (currentTime - targetData.lastSampleTime) >= SAMPLE_INTERVAL then
        targetData.lastSampleTime = currentTime;

        -- Feed TTK estimator with actual HP
        targetData.rlsTTK:addSample(currentHP, maxHP, currentTime);

        -- Feed TTE estimator with HP relative to execute threshold
        local executeHP = maxHP * EXECUTE_THRESHOLD;
        local effectiveHP = currentHP - executeHP;
        if effectiveHP > 0 then
            targetData.rlsTTE:addSample(effectiveHP, maxHP - executeHP, currentTime);
        end
    end

    -- Calculate effective max HP for special bosses
    local effectiveMaxHP = GetEffectiveMaxHP(targetName, maxHP);

    -- Need minimum sample time before showing prediction
    local timeSinceFirstSeen = currentTime - targetData.firstSeen;
    if timeSinceFirstSeen < TimeToKill.Settings.minSampleTime then
        textTimeTillDeath:SetText("-.--");
        textDPS:SetText("");
        textTTE:SetText("");
        return;
    end

    -- Get TTK from RLS estimator
    local ttk = targetData.rlsTTK:getTTK();
    local dps = targetData.rlsTTK:getDPS();

    if ttk <= 0 or dps <= 0 then
        textTimeTillDeath:SetText("-.--");
        textDPS:SetText("");
        textTTE:SetText("");
        return;
    end

    -- Adjust for special boss mechanics
    if currentHP > effectiveMaxHP then
        if dps > 0 then
            ttk = (effectiveMaxHP / dps);
        end
    end

    -- Apply conservative factor to account for optimistic predictions
    local rawTTK = ttk * (1 / TimeToKill.Settings.conservativeFactor);

    -- Apply display smoothing to reduce jumpiness
    targetData.smoothTTK = SmoothValue(targetData.smoothTTK, rawTTK, DISPLAY_SMOOTHING);
    remainingSeconds = targetData.smoothTTK;

    -- Get TTE (Time to Execute) if above execute threshold
    if TimeToKill.Settings.showExecute then
        local tte = targetData.rlsTTE:getTTK();
        if tte and tte > 0 and hpPercent > (EXECUTE_THRESHOLD * 100) then
            targetData.smoothTTE = SmoothValue(targetData.smoothTTE, tte, DISPLAY_SMOOTHING);
            textTTE:SetText(string.format("Execute: %.0fs", targetData.smoothTTE));
        else
            textTTE:SetText("");
        end
    else
        textTTE:SetText("");
    end

    -- Display DPS
    if TimeToKill.Settings.showDPS then
        textDPS:SetText(string.format("%s dps", FormatDPS(dps)));
    else
        textDPS:SetText("");
    end

    -- Color coding based on HP% and TTK
    local execThresholdPct = EXECUTE_THRESHOLD * 100;
    if hpPercent <= execThresholdPct then
        -- In execute range - RED
        textTimeTillDeath:SetTextColor(0.8, 0.25, 0.25);
    elseif remainingSeconds and remainingSeconds <= WARNING_THRESHOLD then
        -- Warning threshold (40s or less) - YELLOW
        textTimeTillDeath:SetTextColor(0.8, 0.8, 0.2);
    elseif remainingSeconds and remainingSeconds <= 60 then
        -- Caution threshold (60s or less) - GREEN
        textTimeTillDeath:SetTextColor(0.2, 0.8, 0.2);
    else
        -- Normal - WHITE
        textTimeTillDeath:SetTextColor(1.0, 1.0, 1.0);
    end

    -- Sanity checks
    if remainingSeconds ~= remainingSeconds or remainingSeconds < 0 or remainingSeconds > 3600 then
        textTimeTillDeath:SetText("-.--");
    else
        textTimeTillDeath:SetText(string.format("%.0fs", remainingSeconds));
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
        if TimeToKill.Settings.minSampleTime == nil then TimeToKill.Settings.minSampleTime = 2.0; end
        if TimeToKill.Settings.conservativeFactor == nil then TimeToKill.Settings.conservativeFactor = 0.95; end
        if TimeToKill.Settings.showExecute == nil then TimeToKill.Settings.showExecute = true; end
        if TimeToKill.Settings.showDPS == nil then TimeToKill.Settings.showDPS = true; end
        if TimeToKill.Settings.showHP == nil then TimeToKill.Settings.showHP = true; end

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
            if TimeToKill.Settings.minSampleTime == nil then
                TimeToKill.Settings.minSampleTime = 2.0;
            end
            if TimeToKill.Settings.conservativeFactor == nil then
                TimeToKill.Settings.conservativeFactor = 0.95;
            end
            if TimeToKill.Settings.showExecute == nil then
                TimeToKill.Settings.showExecute = true;
            end
            if TimeToKill.Settings.showDPS == nil then
                TimeToKill.Settings.showDPS = true;
            end
            if TimeToKill.Settings.showHP == nil then
                TimeToKill.Settings.showHP = true;
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
    end
end);

TimeToKill.TTD:RegisterEvent("PLAYER_LOGIN");
TimeToKill.TTD:RegisterEvent("ADDON_LOADED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_ENABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_DISABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_DEAD");

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
        print("|cFF33FF99/ttk execute on|r - Show execute phase timer.");
        print("|cFF33FF99/ttk execute off|r - Hide execute phase timer.");
        print("|cFF33FF99/ttk dps on|r - Show DPS display.");
        print("|cFF33FF99/ttk dps off|r - Hide DPS display.");
        print("|cFF33FF99/ttk hp on|r - Show HP display.");
        print("|cFF33FF99/ttk hp off|r - Hide HP display.");
        print("|cFF33FF99/ttk conservative <0.9-1.0>|r - Conservative factor (default 0.95).");
        print("|cFF33FF99/ttk minsample <seconds>|r - Min sample time (default 2.0).");
        print("|cFF33FF99/ttk smooth <0.1-0.3>|r - Display smoothing (default 0.15).");
        print("|cFF33FF99/ttk test|r - Toggle test mode (track any enemy).");
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
    elseif command == "execute" then
        if option == "on" then
            TimeToKill.Settings.showExecute = true;
            print("TimeToKill: Execute phase timer enabled.");
        elseif option == "off" then
            TimeToKill.Settings.showExecute = false;
            textTTE:SetText("");
            print("TimeToKill: Execute phase timer disabled.");
        else
            print("TimeToKill: Usage: /ttk execute [on|off]");
        end
    elseif command == "dps" then
        if option == "on" then
            TimeToKill.Settings.showDPS = true;
            print("TimeToKill: DPS display enabled.");
        elseif option == "off" then
            TimeToKill.Settings.showDPS = false;
            textDPS:SetText("");
            print("TimeToKill: DPS display disabled.");
        else
            print("TimeToKill: Usage: /ttk dps [on|off]");
        end
    elseif command == "hp" then
        if option == "on" then
            TimeToKill.Settings.showHP = true;
            print("TimeToKill: HP display enabled.");
        elseif option == "off" then
            TimeToKill.Settings.showHP = false;
            textHP:SetText("");
            print("TimeToKill: HP display disabled.");
        else
            print("TimeToKill: Usage: /ttk hp [on|off]");
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
    elseif command == "smooth" then
        if option then
            local value = tonumber(option);
            if value and value >= 0.05 and value <= 0.5 then
                DISPLAY_SMOOTHING = value;
                print("TimeToKill: Display smoothing set to " .. value);
            else
                print("TimeToKill: Value must be between 0.05 and 0.5");
            end
        else
            print("TimeToKill: Current display smoothing: " .. DISPLAY_SMOOTHING);
        end
    elseif command == "test" then
        testMode = not testMode;
        if testMode then
            print("TimeToKill: Test mode |cFF00FF00ON|r - tracking any enemy in combat");
        else
            print("TimeToKill: Test mode |cFFFF0000OFF|r - normal tracking");
        end
    elseif command == "status" then
        print("=== TimeToKill Status ===");
        if isSuperWoW then
            print("SuperWoW: |cFF00FF00v" .. (SUPERWOW_VERSION or "?") .. "|r");
            print("GUID: " .. (hasGUIDSupport and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"));
        else
            print("SuperWoW: |cFFFF0000Not Detected|r");
        end
        print("Algorithm: RLS (Recursive Least Squares)");
        print("Test Mode: " .. (testMode and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"));
        print("Settings:");
        print("  Conservative Factor: " .. TimeToKill.Settings.conservativeFactor);
        print("  Min Sample Time: " .. TimeToKill.Settings.minSampleTime .. "s");
        print("  Display Smoothing: " .. DISPLAY_SMOOTHING);
        print("  Sample Interval: " .. SAMPLE_INTERVAL .. "s");
        print("  Execute Threshold: " .. (EXECUTE_THRESHOLD * 100) .. "%");
        print("  Warning Threshold: " .. WARNING_THRESHOLD .. "s");
        print("RLS Parameters:");
        print("  Lambda: " .. RLS.lambda .. " (normal) / " .. RLS.lambdaFast .. " (fast)");
        print("  Min Samples: " .. RLS.minSamples);
        local count = 0;
        for _ in pairs(targetTracking) do count = count + 1; end
        print("Tracked Targets: " .. count);
    elseif command == "debug" then
        if currentTargetGUID and targetTracking[currentTargetGUID] then
            local data = targetTracking[currentTargetGUID];
            local rlsTTK = data.rlsTTK;
            local rlsTTE = data.rlsTTE;
            print("=== TimeToKill Debug ===");
            print("Target: " .. (data.name or "Unknown"));
            print("GUID: " .. (hasGUIDSupport and currentTargetGUID or "(fallback)"));
            print("Combat time: " .. string.format("%.2f", GetTime() - data.firstSeen) .. "s");
            print("");
            print("TTK Estimator (Time to Kill):");
            print("  Samples: " .. rlsTTK.sampleCount);
            print("  DPS: " .. FormatDPS(rlsTTK:getDPS()));
            print("  TTK: " .. string.format("%.2f", rlsTTK:getTTK()) .. "s");
            print("  Covariance (P): " .. string.format("%.0f", rlsTTK.P));
            print("  Adapt Countdown: " .. rlsTTK.adaptCountdown);
            if rlsTTK.lastHP then
                print("  Last HP: " .. FormatHP(rlsTTK.lastHP));
            end
            print("");
            print("TTE Estimator (Time to Execute):");
            print("  Samples: " .. rlsTTE.sampleCount);
            print("  TTE: " .. string.format("%.2f", rlsTTE:getTTK()) .. "s");
            print("  Covariance (P): " .. string.format("%.0f", rlsTTE.P));
            print("  Adapt Countdown: " .. rlsTTE.adaptCountdown);
            print("");
            print("Display Values:");
            if data.smoothTTK then
                print("  Smooth TTK: " .. string.format("%.2f", data.smoothTTK) .. "s");
            end
            if data.smoothTTE then
                print("  Smooth TTE: " .. string.format("%.2f", data.smoothTTE) .. "s");
            end
        else
            print("TimeToKill: No target data available.");
        end
    else
        print("TimeToKill: Unknown command. Type /ttk for help.");
    end
end;
