local lastCheckTime = 0;
local checkInterval = 0.1;

if not TimeToKill then
    TimeToKill = {};
end

if not TimeToKill.Settings then
    TimeToKill.Settings = {};

    TimeToKill.Settings.isLocked = false;
    TimeToKill.Settings.isNameVisible = true;
    TimeToKill.Settings.combatHide = false;
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
local combatStart = GetTime();

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
        if not TimeToKill.Settings then TimeToKill.Settings = {} end
        if TimeToKill.Settings.isLocked == nil then TimeToKill.Settings.isLocked = false; end
        if TimeToKill.Settings.isNameVisible == nil then TimeToKill.Settings.isNameVisible = true; end
        if TimeToKill.Settings.combatHide == nil then TimeToKill.Settings.combatHide = false; end

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

            ApplyFramePosition();
            ApplyLockState();
            UpdateNameVisibility();
            ApplyCombatHideState();
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStart = GetTime();
        inCombat = true;
        ApplyCombatHideState();
        TTD_Show();
        UpdateNameVisibility();
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false;
        combatStart = GetTime();
        TTD_Hide();
        textTimeTillDeathText:SetText("");
        UpdateNameVisibility();
        ApplyCombatHideState();
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

    -- The rest of your function logic remains the same...
    if args[1] == nil or args[1] == "" then
        print("TimeToKill Usage:");
        print("|cFF33FF99/ttk lock|r - Locks the frame position and enables click-through.");
        print("|cFF33FF99/ttk unlock|r - Unlocks the frame position (Shift-drag to move).");
        print("|cFF33FF99/ttk name on|r - Shows the 'Time Till Death:' text.");
        print("|cFF33FF99/ttk name off|r - Hides the 'Time Till Death:' text.");
        print("|cFF33FF99/ttk combathide on|r - Hides frame and text when out of combat.");
        print("|cFF33FF99/ttk combathide off|r - Frame and text remain visible out of combat.");
        return;
    end

    local command = string.lower(args[1]);
    local option = args[2] and string.lower(args[2]) or nil;

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
            print("TimeToKill: Combat hide enabled. Frame will hide when out of combat.");
        elseif option == "off" then
            TimeToKill.Settings.combatHide = false;
            ApplyCombatHideState();
            print("TimeToKill: Combat hide disabled. Frame will remain visible.");
        else
            print("TimeToKill: Usage: /ttk combathide [on|off]");
        end
    else
        print("TimeToKill: Unknown command. Type /ttk for help.");
    end
end;
