local lastCheckTime = 0;
local checkInterval = 0.1;

if not TimeToKill then
    TimeToKill = {};
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
ttdFrame:EnableMouse(true);

local textTimeTillDeath = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textTimeTillDeath:SetFont("Fonts\\FRIZQT__.TTF", 99, "OUTLINE, MONOCHROME");
textTimeTillDeath:SetPoint("CENTER", 0, -20);

local textTimeTillDeathText = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText");
textTimeTillDeathText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE, MONOCHROME");
textTimeTillDeathText:SetPoint("CENTER", 0, 0);

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
        textTimeTillDeathText:SetText("Time Till Death:");
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
        ApplyFramePosition();
        TTD_Hide();
    elseif event == "ADDON_LOADED" then
        if arg1 == "TimeToKill" then
            ApplyFramePosition();
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStart = GetTime();
        inCombat = true;
        TTD_Show();
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false;
        combatStart = GetTime();
        TTD_Hide();
        textTimeTillDeathText:SetText("");
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

ApplyFramePosition()
