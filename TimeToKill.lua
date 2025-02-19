local lastCheckTime = 0;
local checkInterval = 0.1;
if not TimeToKill then
	TimeToKill = {};
end;
TimeToKill.TTD = CreateFrame("Frame", nil, UIParent);

local inCombat = false;

local remainingSeconds = 0;

local ttdFrame = CreateFrame("Frame")
ttdFrame:SetFrameStrata("HIGH")
ttdFrame:SetWidth(100)
ttdFrame:SetHeight(50)
ttdFrame:SetPoint("CENTER", UIParent, "CENTER")
ttdFrame:SetPoint("BOTTOMLEFT", math.floor(GetScreenWidth()*.465), math.floor(GetScreenHeight()*.11));
ttdFrame:Show()
ttdFrame:SetMovable(true)
ttdFrame:EnableMouse(true)

local textTimeTillDeath = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
textTimeTillDeath:SetFont("Fonts\\FRIZQT__.TTF", 99, "OUTLINE, MONOCHROME")
textTimeTillDeath:SetPoint("CENTER", 0, -20)

local textTimeTillDeathText = ttdFrame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
textTimeTillDeathText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE, MONOCHROME")
textTimeTillDeathText:SetPoint("CENTER", 0, 0)

ttdFrame:SetScript("OnMouseDown", function(self, button)
	if IsShiftKeyDown() then
		ttdFrame:StartMoving()
	end
end)

ttdFrame:SetScript("OnMouseUp", function(self, button)
		ttdFrame:StopMovingOrSizing()
end)

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
			remainingSeconds = (maxHP/(missingHP/seconds)-seconds)*0.90;
			if (remainingSeconds ~= remainingSeconds) then
				textTimeTillDeath:SetText("-.--")
			else
				if (remainingSeconds) then
					textTimeTillDeath:SetText(string.format("%.2f",remainingSeconds));
				end
			end
		end
	end
end


function onUpdate(sinceLastUpdate)
	timeSinceLastUpdate = GetTime();

	if GetTime()-lastCheckTime >= checkInterval then
		if (lastCheckTime == 0) then
			lastCheckTime = GetTime();
		end
		
		TTDLogic();


		lastCheckTime = 0 
	end
end
TimeToKill.TTD:SetScript("OnUpdate", function(self) if inCombat then onUpdate(timeSinceLastUpdate); end; end);


TimeToKill.TTD:SetScript("OnShow", function(self)
	timeSinceLastUpdate = 0
end)


TimeToKill.TTD:SetScript("OnEvent", function()
	if event == "PLAYER_REGEN_DISABLED" then
		combatStart = GetTime();
		inCombat = true;
		TTD_Show();
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false;
		combatStart = GetTime();
		TTD_Hide();
		textTimeTillDeathText:SetText("");
	elseif event == "PLAYER_LOGIN" then
		TTD_Hide();
	elseif event == "PLAYER_DEAD" then
		inCombat = false;
		TTD_Hide();
	end
end);
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_ENABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_REGEN_DISABLED");
TimeToKill.TTD:RegisterEvent("PLAYER_LOGIN");
TimeToKill.TTD:RegisterEvent("PLAYER_DEAD");

