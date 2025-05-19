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
local isMoving = false; -- Flag to indicate if the frame is being moved

local ttdFrame = TimeToKill.TTD;
ttdFrame:SetFrameStrata("HIGH");
ttdFrame:SetWidth(100);
ttdFrame:SetHeight(50);

local function ApplyFramePosition()
    local position = TimeToKill.Position;
    local effectiveRelativeTo = nil; -- Variable to hold the actual frame object

    -- First, try to use the saved position if it exists
    if position and position.point and position.relativeTo then
        -- Check if the saved relative frame exists in the global environment
        if type(position.relativeTo) == "string" and _G[position.relativeTo] then
            effectiveRelativeTo = _G[position.relativeTo];
        end
    end

    -- If saved position is invalid or relative frame doesn't exist, use default
    if not effectiveRelativeTo then
        effectiveRelativeTo = _G[defaultPosition.relativeTo];
        position = defaultPosition; -- Use default position details
        -- Ensure TimeToKill.Position is initialized if it wasn't
        if not TimeToKill.Position then TimeToKill.Position = {} end
        -- Update TimeToKill.Position with default values for saving later
        TimeToKill.Position.point = defaultPosition.point;
        TimeToKill.Position.relativeTo = defaultPosition.relativeTo;
        TimeToKill.Position.relativePoint = defaultPosition.relativePoint;
        TimeToKill.Position.x = defaultPosition.x;
        TimeToKill.Position.y = defaultPosition.y;
    end

    -- Apply the position using the determined effectiveRelativeTo frame
    if effectiveRelativeTo then
        ttdFrame:SetPoint(
            position.point,
            effectiveRelativeTo,
            position.relativePoint,
            position.x,
            position.y
        );
    else
        -- Fallback if even the default relative frame doesn't exist (shouldn't happen with UIParent)
        ttdFrame:SetPoint(
            "CENTER", -- Fallback to center if all else fails
            UIParent,
            "CENTER",
            0,
            0
        );
         -- Also update saved position to this fallback
        if not TimeToKill.Position then TimeToKill.Position = {} end
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

ttdFrame:SetScript("OnMouseDown", function(self, button)
    if IsShiftKeyDown() then
        isMoving = true; -- Set the flag when moving starts
        ttdFrame:StartMoving();
    end
end);

ttdFrame:SetScript("OnMouseUp", function(self, button)
    ttdFrame:StopMovingOrSizing();
    isMoving = false; -- Clear the flag when moving stops

    if not TimeToKill.Position then TimeToKill.Position = {} end
    local point, relativeTo, relativePoint, x, y = ttdFrame:GetPoint();

    TimeToKill.Position.point = point;

    -- Ensure relativeTo is saved as a string name
    if type(relativeTo) == "table" and relativeTo.GetName then
         TimeToKill.Position.relativeTo = relativeTo:GetName();
         -- If GetName returns nil or empty, fallback to UIParent
         if not TimeToKill.Position.relativeTo or TimeToKill.Position.relativeTo == "" then
             TimeToKill.Position.relativeTo = "UIParent";
         end
    elseif type(relativeTo) == "string" then
         TimeToKill.Position.relativeTo = relativeTo;
          -- If the string is nil or empty, fallback to UIParent
         if not TimeToKill.Position.relativeTo or TimeToKill.Position.relativeTo == "" then
             TimeToKill.Position.relativeTo = "UIParent";
         end
    else
         -- If relativeTo is neither table nor string, fallback to UIParent
         TimeToKill.Position.relativeTo = "UIParent";
    end

    TimeToKill.Position.relativePoint = relativePoint;
    TimeToKill.Position.x = x;
    TimeToKill.Position.y = y;
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
    if UnitIsEnemy("player","target") or UnitReaction("player","target") == 4 then
        local targetName = UnitName("target");
        local EHealthPercent = UnitHealth("target")/UnitHealthMax("target")*100;
        if EHealthPercent == 100 then
            if targetName ~= 'Spore' and targetName ~= 'Fallout Slime' and targetName ~= 'Plagued Champion' then
                combatStart = GetTime();
            end
        end;
        if EHealthPercent then
            local maxHP     = UnitHealthMax("target");
            if targetName == 'Vaelastrasz the Corrupt' then
                maxHP = UnitHealthMax("target")*0.3;
            end;
            local curHP     = UnitHealth("target");
            local missingHP = maxHP - curHP;
            local seconds   = timeSinceLastUpdate - combatStart;
            if seconds > 0 and missingHP > 0 then
                remainingSeconds = (maxHP/(missingHP/seconds)-seconds)*0.90;
                if (remainingSeconds ~= remainingSeconds) or remainingSeconds < 0 then
                    textTimeTillDeath:SetText("-.--")
                else
                    textTimeTillDeath:SetText(string.format("%.2f",remainingSeconds));
                end
            else
                 textTimeTillDeath:SetText("-.--");
            end
        end
    else
         -- Optionally hide or clear if no valid enemy target
         -- TTD_Hide();
    end
end


function onUpdate(sinceLastUpdate)
    -- Only run the update logic if the frame is NOT being moved
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
        -- TimeToKill.Position is initialized in ApplyFramePosition if needed
        ApplyFramePosition();
        TTD_Hide();
    elseif event == "ADDON_LOADED" then
        if arg1 == "TimeToKill" then
             -- TimeToKill.Position is initialized in ApplyFramePosition if needed
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

-- Initial position application
ApplyFramePosition()
