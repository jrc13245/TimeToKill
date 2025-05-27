local lastCheckTime = 0;
local checkInterval = 0.1;

if not TimeToKill then
    TimeToKill = {};
end

-- Initialize TimeToKill.Settings for new saved variables
-- This will be properly initialized in ADDON_LOADED to ensure it's part of the saved table
if not TimeToKill.Settings then
    TimeToKill.Settings = {};
    -- Default values, will be overwritten by saved values if they exist
    TimeToKill.Settings.isLocked = false; 
    TimeToKill.Settings.isNameVisible = true;
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

-- NEW: Function to apply the lock state
local function ApplyLockState()
    if TimeToKill.Settings.isLocked then
        ttdFrame:EnableMouse(false); -- Makes frame click-through and non-interactive for movement
    else
        ttdFrame:EnableMouse(true);  -- Makes frame interactive for movement
    end
end

-- NEW: Function to update the visibility of the "Time Till Death:" name text
local function UpdateNameVisibility()
    if TimeToKill.Settings.isNameVisible then
        textTimeTillDeathText:Show();
    else
        textTimeTillDeathText:Hide();
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
-- ttdFrame:EnableMouse(true); -- This will be managed by ApplyLockState based on saved settings

ttdFrame:SetScript("OnMouseDown", function(_, button)
    -- If EnableMouse(false) is set (i.e., frame is locked), this script won't be triggered for drag attempts.
    if not ttdFrame or not ttdFrame.StartMoving then
        isMoving = false;
        return;
    end

    -- No need to check TimeToKill.Settings.isLocked here, as EnableMouse(false) prevents this event
    -- from leading to a drag when locked.

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
local combatStart = GetTime();

local function TTD_Show()
    if (inCombat) then
        -- The visibility of textTimeTillDeathText is handled by UpdateNameVisibility()
        -- This function just ensures the text content is correct.
        if TimeToKill.Settings.isNameVisible then 
             textTimeTillDeathText:SetText("Time Till Death:");
        else
             textTimeTillDeathText:SetText(""); -- Or ensure it's empty if hidden by preference
        end
    end
end

local function TTD_Hide()
    textTimeTillDeath:SetText("-.--");
    -- textTimeTillDeathText will be managed by UpdateNameVisibility and combat events
end

local function TTDLogic()
    if UnitIsEnemy("player", "target") or UnitReaction("player", "target") == 4 then
        local targetName = UnitName("target");
        local currentHP_target = UnitHealth("target");
        local maxHP_target = UnitHealthMax("target");

        if maxHP_target and maxHP_target > 0 then
            local EHealthPercent = (currentHP_target / maxHP_target) * 100;

            if EHealthPercent == 100 then
                if targetName and targetName ~= 'Spore' and targetName ~= 'Fallout Slime' and targetName ~= 'Plagued Champion' then
                    combatStart = GetTime();
                end
            end
            
            local effectiveMaxHP = maxHP_target;
            if targetName and targetName == 'Vaelastrasz the Corrupt' then
                effectiveMaxHP = maxHP_target * 0.3;
            end
            
            local missingHP = effectiveMaxHP - currentHP_target;
            local secondsInCombatSegment = timeSinceLastUpdate - combatStart;

            if secondsInCombatSegment > 0 and missingHP > 0 then
                local currentDPS = missingHP / secondsInCombatSegment;
                if currentDPS > 0 then
                    local estimatedTotalFightSeconds = effectiveMaxHP / currentDPS;
                    remainingSeconds = (estimatedTotalFightSeconds - secondsInCombatSegment) * 0.90;
                
                    if (remainingSeconds ~= remainingSeconds) or remainingSeconds < 0 then 
                        textTimeTillDeath:SetText("-.--");
                    else
                        textTimeTillDeath:SetText(string.format("%.2f", remainingSeconds));
                    end
                else
                    textTimeTillDeath:SetText("-.--");
                end
            else
                textTimeTillDeath:SetText("-.--");
            end
        else
            textTimeTillDeath:SetText("-.--");
        end
    else
        textTimeTillDeath:SetText("-.--"); 
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
        -- Ensure settings are loaded/initialized (ADDON_LOADED should handle primary init)
        if not TimeToKill.Settings then TimeToKill.Settings = {} end
        if TimeToKill.Settings.isLocked == nil then TimeToKill.Settings.isLocked = false; end
        if TimeToKill.Settings.isNameVisible == nil then TimeToKill.Settings.isNameVisible = true; end

        ApplyFramePosition();
        ApplyLockState();
        UpdateNameVisibility();
        TTD_Hide();
    elseif event == "ADDON_LOADED" then
        if arg1 == "TimeToKill" then
            -- Initialize TimeToKill.Settings if it doesn't exist (e.g., first run)
            -- This ensures it's part of the TimeToKill table saved by SavedVariables
            if TimeToKill.Settings == nil then
                TimeToKill.Settings = {};
            end
            -- Set defaults for new settings if they are not already saved
            if TimeToKill.Settings.isLocked == nil then
                TimeToKill.Settings.isLocked = false; -- Default to unlocked
            end
            if TimeToKill.Settings.isNameVisible == nil then
                TimeToKill.Settings.isNameVisible = true; -- Default to name visible
            end

            ApplyFramePosition();   -- Existing
            ApplyLockState();       -- New: Apply loaded/default lock state
            UpdateNameVisibility(); -- New: Apply loaded/default name visibility
        end
    elseif event == "PLAYER_REGEN_DISABLED" then -- Player enters combat
        combatStart = GetTime();
        inCombat = true;
        TTD_Show();
        UpdateNameVisibility(); -- Ensure name visibility is correct when showing
    elseif event == "PLAYER_REGEN_ENABLED" then -- Player leaves combat
        inCombat = false;
        combatStart = GetTime();
        TTD_Hide();
        textTimeTillDeathText:SetText(""); -- Clear name text when out of combat
        UpdateNameVisibility(); -- Ensure name visibility is correct (it might be hidden)
    elseif event == "PLAYER_DEAD" then
        inCombat = false;
        TTD_Hide();
    end
end);

TimeToKill.TTD:RegisterEvent("PLAYER_LOGIN");
TimeToKill.TTD:RegisterEvent("ADDON_LOADED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_ENABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_DISABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_DEAD");

-- NEW: Slash command handler
-- NEW: Slash command handler
SLASH_TIMETOKILL1 = "/ttk";
SlashCmdList["TIMETOKILL"] = function(msg)
    local args = {};
    for arg in string.gmatch(msg, "[^%s]+") do
        table.insert(args, string.lower(arg));
    end

    -- MODIFIED: Check if args table is empty without using #
    if args[1] == nil then
        print("TimeToKill Usage:");
        print("|cFF33FF99/ttk lock|r - Locks the frame position and enables click-through.");
        print("|cFF33FF99/ttk unlock|r - Unlocks the frame position (Shift-drag to move).");
        print("|cFF33FF99/ttk name on|r - Shows the 'Time Till Death:' text.");
        print("|cFF33FF99/ttk name off|r - Hides the 'Time Till Death:' text.");
        return;
    end

    local command = args[1];
    local option = args[2];

    if command == "lock" then
        TimeToKill.Settings.isLocked = true;
        ApplyLockState();
        print("TimeToKill: Frame locked. It is now click-through.");
    elseif command == "unlock" then
        TimeToKill.Settings.isLocked = false;
        ApplyLockState();
        print("TimeToKill: Frame unlocked. Shift-click and drag to move.");
    elseif command == "name" then
        if option == "on" then
            TimeToKill.Settings.isNameVisible = true;
            UpdateNameVisibility();
            -- If in combat, ensure the text is set correctly
            if inCombat then TTD_Show(); end
            print("TimeToKill: Name text enabled.");
        elseif option == "off" then
            TimeToKill.Settings.isNameVisible = false;
            UpdateNameVisibility();
            print("TimeToKill: Name text disabled.");
        else
            print("TimeToKill: Usage: /ttk name [on|off]");
        end
    else
        print("TimeToKill: Unknown command. Type /ttk for help.");
    end
end;