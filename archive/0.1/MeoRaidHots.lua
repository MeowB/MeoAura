local ADDON_NAME = ...

local HOT_SIZE = 21
local HOT_SPACING = 0
local MAX_HOTS = 5
local MAX_AURAS_TO_SCAN = 40
local MAX_AURAS_TO_CHECK = 12

local HOTS = {
  -- Druid
  ["Rejuvenation"] = true,
  ["Germination"] = true,
  ["Rejuvenation (Germination)"] = true,
  ["Regrowth"] = true,
  ["Lifebloom"] = true,
  ["Wild Growth"] = true,

  -- Monk
  ["Renewing Mist"] = true,
  ["Enveloping Mist"] = true,
  ["Essence Font"] = true,

  -- Priest
  ["Renew"] = true,
  ["Prayer of Mending"] = true,

  -- Shaman
  ["Riptide"] = true,
  ["Earthliving"] = true,

  -- Evoker
  ["Reversion"] = true,
  ["Dream Breath"] = true,
  ["Echo"] = true,
}

local HOT_SPELL_IDS = {
  -- Druid
  [774] = true, -- Rejuvenation
  [8936] = true, -- Regrowth
  [33763] = true, -- Lifebloom
  [48438] = true, -- Wild Growth
  [155777] = true, -- Rejuvenation (Germination)

  -- Monk
  [119611] = true, -- Renewing Mist
  [124682] = true, -- Enveloping Mist
  [191840] = true, -- Essence Font

  -- Priest
  [139] = true, -- Renew
  [33076] = true, -- Prayer of Mending

  -- Shaman
  [61295] = true, -- Riptide
  [51945] = true, -- Earthliving

  -- Evoker
  [366155] = true, -- Reversion
  [355941] = true, -- Dream Breath
  [364343] = true, -- Echo
}

local FRAME_PREFIXES = {
  CompactPartyFrameMember = true,
  CompactRaidFrame = true,
}

local addonFrame = CreateFrame("Frame")
local hotButtonsByFrame = setmetatable({}, { __mode = "k" })
local backingsByFrame = setmetatable({}, { __mode = "k" })
local updateQueued = false

local function SafeFrameName(value)
  if type(value) ~= "table" or type(value.GetName) ~= "function" then
    return "no name"
  end

  local ok, name = pcall(value.GetName, value)
  if ok and name then
    return name
  end

  return "no name"
end

local function IsCompactGroupFrame(unitFrame)
  if not unitFrame or type(unitFrame.GetName) ~= "function" then
    return false
  end

  local name = SafeFrameName(unitFrame)
  if name == "no name" then
    return false
  end

  for prefix in pairs(FRAME_PREFIXES) do
    if name:match("^" .. prefix .. "%d+$") then
      return true
    end
  end

  return false
end

local function GetFrameUnit(unitFrame)
  return unitFrame and (unitFrame.displayedUnit or unitFrame.unit)
end

local function SafeAuraField(aura, field)
  if type(aura) ~= "table" then
    return nil
  end

  local ok, value = pcall(function()
    return aura[field]
  end)

  if ok then
    return value
  end

  return nil
end

local function SafeText(value)
  local ok, text = pcall(tostring, value)
  if ok then
    return text
  end

  return "restricted"
end

local function IsPlayerAura(aura)
  local fromPlayer = SafeAuraField(aura, "isFromPlayerOrPlayerPet")
  if fromPlayer == true then
    return true
  end

  local source = SafeAuraField(aura, "sourceUnit") or SafeAuraField(aura, "source")
  local ok, isPlayer = pcall(function()
    return source == "player" or source == "pet" or source == "vehicle"
  end)

  return ok and isPlayer
end

local function AuraHasDuration(aura)
  local duration = SafeAuraField(aura, "duration")
  local expirationTime = SafeAuraField(aura, "expirationTime")
  local ok, hasDuration = pcall(function()
    return type(duration) == "number" and duration > 0 and type(expirationTime) == "number"
  end)

  return ok and hasDuration
end

local function GetAuraIcon(aura)
  return SafeAuraField(aura, "icon") or SafeAuraField(aura, "iconFileID") or SafeAuraField(aura, "texture")
end

local function IsTrackedHot(aura)
  local name = SafeAuraField(aura, "name")
  local spellId = SafeAuraField(aura, "spellId")
  local ok, tracked = pcall(function()
    return (type(name) == "string" and HOTS[name] == true) or HOT_SPELL_IDS[spellId] == true
  end)

  return ok and tracked
end

local function ReadHelpfulAura(unit, index)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    return C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
  end

  if UnitBuff then
    local name, icon, applications, _, duration, expirationTime, source = UnitBuff(unit, index)
    if name then
      return {
        name = name,
        icon = icon,
        applications = applications,
        duration = duration,
        expirationTime = expirationTime,
        sourceUnit = source,
      }
    end
  end
end

local function RaiseHotButton(unitFrame, button)
  local parentLevel = type(unitFrame.GetFrameLevel) == "function" and unitFrame:GetFrameLevel() or 0
  local healthBar = unitFrame.healthBar
  local healthBarLevel = healthBar and type(healthBar.GetFrameLevel) == "function" and healthBar:GetFrameLevel() or 0

  button:SetFrameLevel(math.max(parentLevel, healthBarLevel) + 100)

  if type(button.SetFrameStrata) == "function" then
    button:SetFrameStrata("HIGH")
  end
end

local function EnsureBacking(unitFrame)
  local backing = backingsByFrame[unitFrame]
  if backing then
    return backing
  end

  local anchor = unitFrame.healthBar or unitFrame
  backing = CreateFrame("Frame", nil, unitFrame)
  backing:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
  backing:SetSize(MAX_HOTS * HOT_SIZE + (MAX_HOTS - 1) * HOT_SPACING + 2, HOT_SIZE + 2)
  backing:SetFrameLevel((type(unitFrame.GetFrameLevel) == "function" and unitFrame:GetFrameLevel() or 0) + 90)
  backing:SetFrameStrata("HIGH")

  backing.texture = backing:CreateTexture(nil, "BACKGROUND")
  backing.texture:SetAllPoints(backing)
  backing.texture:SetColorTexture(0, 0, 0, 0.85)

  backingsByFrame[unitFrame] = backing
  return backing
end

local function CreateHotButton(unitFrame, index)
  local anchor = unitFrame.healthBar or unitFrame
  local button = CreateFrame("Frame", nil, unitFrame)
  button:SetSize(HOT_SIZE, HOT_SIZE)
  RaiseHotButton(unitFrame, button)

  button.icon = button:CreateTexture(nil, "OVERLAY")
  button.icon:SetAllPoints(button)
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  button.cooldown:SetAllPoints(button)
  button.cooldown:SetDrawEdge(false)
  if type(button.cooldown.SetHideCountdownNumbers) == "function" then
    button.cooldown:SetHideCountdownNumbers(true)
  end
  button.cooldown:SetReverse(true)

  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)

  button:SetPoint(
    "BOTTOMRIGHT",
    anchor,
    "BOTTOMRIGHT",
    -1 - (index - 1) * (HOT_SIZE + HOT_SPACING),
    1
  )

  return button
end

local function EnsureHotButtons(unitFrame)
  local buttons = hotButtonsByFrame[unitFrame]
  if buttons then
    return buttons
  end

  buttons = {}
  hotButtonsByFrame[unitFrame] = buttons

  for index = 1, MAX_HOTS do
    buttons[index] = CreateHotButton(unitFrame, index)
  end

  return buttons
end

local function ClearHotButtons(unitFrame)
  local buttons = hotButtonsByFrame[unitFrame]
  local backing = backingsByFrame[unitFrame]
  if backing then
    backing:Hide()
  end

  if not buttons then
    return
  end

  for _, button in ipairs(buttons) do
    button:Hide()
  end
end

local function UpdateFrameHots(unitFrame)
  if not IsCompactGroupFrame(unitFrame) then
    return
  end

  local unit = GetFrameUnit(unitFrame)
  if not unit or not UnitExists(unit) then
    ClearHotButtons(unitFrame)
    return
  end

  local buttons = EnsureHotButtons(unitFrame)
  local backing = EnsureBacking(unitFrame)

  local hotIndex = 1
  for auraIndex = 1, MAX_AURAS_TO_SCAN do
    local aura = ReadHelpfulAura(unit, auraIndex)
    if not aura then
      break
    end

    if IsTrackedHot(aura) and IsPlayerAura(aura) and AuraHasDuration(aura) and GetAuraIcon(aura) then
      local button = buttons[hotIndex]
      local okTexture = pcall(button.icon.SetTexture, button.icon, GetAuraIcon(aura))

      if okTexture then
        RaiseHotButton(unitFrame, button)

        local duration = SafeAuraField(aura, "duration")
        local expirationTime = SafeAuraField(aura, "expirationTime")
        button.cooldown:SetCooldown(expirationTime - duration, duration)

        local applications = SafeAuraField(aura, "applications") or SafeAuraField(aura, "count") or 0
        local ok, hasStacks = pcall(function()
          return applications and applications > 1
        end)

        if ok and hasStacks then
          button.count:SetText(SafeText(applications))
        else
          button.count:SetText("")
        end

        button:Show()
        hotIndex = hotIndex + 1

        if hotIndex > MAX_HOTS then
          break
        end
      end
    end
  end

  for index = hotIndex, MAX_HOTS do
    buttons[index]:Hide()
  end

  if hotIndex > 1 then
    backing:SetWidth((hotIndex - 1) * HOT_SIZE + (hotIndex - 2) * HOT_SPACING + 2)
    backing:Show()
  else
    backing:Hide()
  end
end

local function ForEachCompactFrame(callback)
  for index = 1, 5 do
    callback(_G["CompactPartyFrameMember" .. index])
  end

  for index = 1, 40 do
    callback(_G["CompactRaidFrame" .. index])
  end
end

local function WatchFrame(unitFrame)
  if not IsCompactGroupFrame(unitFrame) then
    return
  end

  UpdateFrameHots(unitFrame)
end

local function UpdateAllFrames()
  ForEachCompactFrame(WatchFrame)
  ForEachCompactFrame(UpdateFrameHots)
end

local function QueueUpdateAllFrames()
  if updateQueued then
    return
  end

  updateQueued = true
  C_Timer.After(0, function()
    updateQueued = false
    UpdateAllFrames()
  end)
end

local function HookCompactFrames()
  addonFrame:UnregisterEvent("PLAYER_LOGIN")

  if type(CompactUnitFrame_UpdateAuras) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateAuras", UpdateFrameHots)
  end

  if type(CompactUnitFrame_UpdateAll) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateAll", UpdateFrameHots)
  end

  if type(CompactUnitFrame_SetUnit) == "function" then
    hooksecurefunc("CompactUnitFrame_SetUnit", UpdateFrameHots)
  end

  UpdateAllFrames()
end

local function AppendLine(lines, ...)
  local parts = {}
  for index = 1, select("#", ...) do
    parts[index] = tostring(select(index, ...))
  end

  lines[#lines + 1] = table.concat(parts, " ")
end

local function DescribeAuraFrame(lines, label, auraFrame)
  if not auraFrame then
    AppendLine(lines, "  ", label, "nil")
    return
  end

  local width = type(auraFrame.GetWidth) == "function" and auraFrame:GetWidth() or "?"
  local height = type(auraFrame.GetHeight) == "function" and auraFrame:GetHeight() or "?"
  local shown = type(auraFrame.IsShown) == "function" and tostring(auraFrame:IsShown()) or "?"
  AppendLine(lines, "  ", label, SafeFrameName(auraFrame), "size=" .. tostring(width) .. "x" .. tostring(height), "shown=" .. shown)
end

local function DumpFrame(lines, frameName)
  local unitFrame = _G[frameName]
  if not unitFrame then
    AppendLine(lines, frameName, "not found")
    return
  end

  AppendLine(lines, "==", frameName, "==")
  AppendLine(lines, "name:", SafeFrameName(unitFrame))
  AppendLine(lines, "unit:", unitFrame.unit or "nil")
  AppendLine(lines, "displayedUnit:", unitFrame.displayedUnit or "nil")
  AppendLine(lines, "auraSize:", unitFrame.auraSize or "nil")
  AppendLine(lines, "optionTable.auraSize:", type(unitFrame.optionTable) == "table" and unitFrame.optionTable.auraSize or "nil")
  AppendLine(lines, "maxBuffs:", unitFrame.maxBuffs or "nil")
  AppendLine(lines, "buffFrames:", type(unitFrame.buffFrames))
  AppendLine(lines, "overlay:", type(hotButtonsByFrame[unitFrame]))

  if hotButtonsByFrame[unitFrame] then
    for index, button in ipairs(hotButtonsByFrame[unitFrame]) do
      DescribeAuraFrame(lines, "Overlay" .. index .. ":", button)
    end
  end

  for index = 1, MAX_AURAS_TO_CHECK do
    DescribeAuraFrame(lines, "Buff" .. index .. ":", _G[frameName .. "Buff" .. index])
  end

  local unit = GetFrameUnit(unitFrame)
  if unit and UnitExists(unit) then
    AppendLine(lines, "auras on", unit .. ":")
    for auraIndex = 1, MAX_AURAS_TO_SCAN do
      local aura = ReadHelpfulAura(unit, auraIndex)
      if not aura then
        break
      end

      AppendLine(lines, "  aura", auraIndex, SafeText(SafeAuraField(aura, "name") or "nil"), "tracked=" .. SafeText(IsTrackedHot(aura)), "source=" .. SafeText(SafeAuraField(aura, "sourceUnit") or SafeAuraField(aura, "source")), "duration=" .. SafeText(SafeAuraField(aura, "duration")), "expiration=" .. SafeText(SafeAuraField(aura, "expirationTime")), "icon=" .. SafeText(GetAuraIcon(aura)))
    end
  end
end

addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
addonFrame:RegisterEvent("UNIT_AURA")
addonFrame:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_LOGIN" then
    HookCompactFrames()
  elseif event == "UNIT_AURA" then
    ForEachCompactFrame(function(unitFrame)
      if unit == GetFrameUnit(unitFrame) then
        UpdateFrameHots(unitFrame)
      end
    end)
  else
    QueueUpdateAllFrames()
  end
end)

SLASH_MEORAIDHOTS1 = "/mrh"
SlashCmdList["MEORAIDHOTS"] = function()
  UpdateAllFrames()

  local lines = {
    ADDON_NAME .. " debug",
    "HOT_SIZE: " .. HOT_SIZE,
    "MAX_HOTS: " .. MAX_HOTS,
  }

  DumpFrame(lines, "CompactPartyFrameMember1")
  DumpFrame(lines, "CompactPartyFrameMember2")
  DumpFrame(lines, "CompactRaidFrame1")

  error(table.concat(lines, "\n"), 0)
end

print(ADDON_NAME .. " loaded. Type /mrh")
