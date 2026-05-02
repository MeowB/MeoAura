local _, ns = ...

local NameplateDebuffs = {}
ns.NameplateDebuffs = NameplateDebuffs

local unitsByFrame = setmetatable({}, { __mode = "k" })
local framesByUnit = {}
local compactAuraHooked = false

local function GetOptions()
  local settings = ns.GetSettings("nameplateDebuffs")
  return {
    filter = "HARMFUL",
    categories = ns.GetEnabledCategories({ "dots", "utility" }),
    onlyPlayer = settings.onlyPlayer,
    iconSize = settings.iconSize,
    maxIcons = settings.maxIcons,
    maxScan = 40,
    requireDuration = false,
    preferLegacy = true,
    point = "BOTTOMLEFT",
    relativePoint = "TOPLEFT",
    growth = "RIGHT",
    x = 0,
    y = 2,
    backingAlpha = 0.75,
    anchorFrame = function(unitFrame)
      return unitFrame.healthBar or unitFrame
    end,
  }
end

local function GetFriendlyHotOptions()
  local settings = ns.GetSettings("nameplateDebuffs")
  return {
    filter = "HELPFUL",
    categories = ns.GetEnabledCategories({ "hots", "externals", "utility" }),
    onlyPlayer = true,
    requirePlayerSource = true,
    requirePlayerGUID = true,
    iconSize = settings.iconSize,
    maxIcons = settings.maxIcons,
    maxScan = 40,
    preferLegacy = true,
    point = "BOTTOMLEFT",
    relativePoint = "TOPLEFT",
    growth = "RIGHT",
    x = 0,
    y = 2,
    backingAlpha = 0.75,
    anchorFrame = function(unitFrame)
      return unitFrame.healthBar or unitFrame
    end,
  }
end

local function GetNamePlateUnitFrame(unit)
  if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
    return nil
  end

  local namePlate = C_NamePlate.GetNamePlateForUnit(unit)
  if not namePlate then
    return nil
  end

  return namePlate.UnitFrame or namePlate
end

local function FindUnitForNamePlate(namePlate, unitFrame)
  local unit = unitsByFrame[unitFrame] or ns.Frames.GetUnit(unitFrame) or ns.Frames.GetUnit(namePlate)
  if unit then
    return unit
  end

  unit = namePlate and namePlate.namePlateUnitToken
  if unit then
    return unit
  end

  if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
    return nil
  end

  for index = 1, 40 do
    local token = "nameplate" .. index
    if C_NamePlate.GetNamePlateForUnit(token) == namePlate then
      return token
    end
  end
end

local function SetBlizzardAurasShown(unitFrame, shown)
  local auraFrame = unitFrame and unitFrame.AurasFrame
  if not auraFrame then
    return
  end

  if shown then
    auraFrame:SetAlpha(1)
    auraFrame:Show()
  else
    auraFrame:SetAlpha(0)
    auraFrame:Hide()
  end
end

local function ConfigureAuraButton(button, size)
  if not button or type(button.SetSize) ~= "function" then
    return
  end

  pcall(button.SetSize, button, size, size)
  pcall(button.SetScale, button, 1)

  local icon = button.icon or button.Icon
  if icon and type(icon.SetAllPoints) == "function" then
    pcall(icon.ClearAllPoints, icon)
    pcall(icon.SetAllPoints, icon, button)
  end

  local cooldown = button.cooldown or button.Cooldown
  if cooldown and type(cooldown.SetAllPoints) == "function" then
    pcall(cooldown.SetAllPoints, cooldown, button)
    pcall(cooldown.Show, cooldown)
  end

  local count = button.count or button.Count
  if count and type(count.SetPoint) == "function" then
    pcall(count.ClearAllPoints, count)
    pcall(count.SetPoint, count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
  end
end

local function IsCooldownFrame(frame)
  if not frame or type(frame.GetObjectType) ~= "function" then
    return false
  end

  local ok, objectType = pcall(frame.GetObjectType, frame)
  return ok and objectType == "Cooldown"
end

local function HasAuraIcon(button)
  if not button or IsCooldownFrame(button) then
    return false
  end

  if button.icon or button.Icon or button.texture or button.Texture then
    return true
  end

  if type(button.GetRegions) ~= "function" then
    return false
  end

  local regions = { button:GetRegions() }
  for _, region in ipairs(regions) do
    if region and type(region.GetObjectType) == "function" then
      local ok, objectType = pcall(region.GetObjectType, region)
      if ok and objectType == "Texture" then
        return true
      end
    end
  end

  return false
end

local function AddAuraButton(buttons, seen, button)
  if not HasAuraIcon(button) or seen[button] then
    return
  end

  seen[button] = true
  buttons[#buttons + 1] = button
end

local function CollectAuraButtons(frame, buttons, depth)
  if not frame or depth > 5 then
    return
  end

  if type(frame.GetChildren) ~= "function" then
    return
  end

  local children = { frame:GetChildren() }
  for _, child in ipairs(children) do
    if child and type(child.IsShown) == "function" then
      AddAuraButton(buttons, buttons.seen, child)
      CollectAuraButtons(child, buttons, depth + 1)
    end
  end
end

local function AddAuraButtonTable(buttons, source)
  if type(source) ~= "table" then
    return
  end

  for _, button in pairs(source) do
    if type(button) == "table" and type(button.IsShown) == "function" then
      AddAuraButton(buttons, buttons.seen, button)
    end
  end
end

local function AddKnownAuraButtons(unitFrame, auraFrame, buttons)
  AddAuraButtonTable(buttons, auraFrame and auraFrame.buffFrames)
  AddAuraButtonTable(buttons, auraFrame and auraFrame.debuffFrames)
  AddAuraButtonTable(buttons, auraFrame and auraFrame.auraFrames)
  AddAuraButtonTable(buttons, unitFrame and unitFrame.buffFrames)
  AddAuraButtonTable(buttons, unitFrame and unitFrame.debuffFrames)
  AddAuraButtonTable(buttons, unitFrame and unitFrame.auraFrames)
end

local function StyleBlizzardAuras(unitFrame)
  local auraFrame = unitFrame and unitFrame.AurasFrame
  if not auraFrame or ns.Frames.IsForbidden(unitFrame) then
    return
  end

  local settings = ns.GetSettings("nameplateDebuffs")
  if not settings.enabled then
    SetBlizzardAurasShown(unitFrame, true)
    return
  end

  local size = settings.iconSize
  local maxIcons = settings.maxIcons
  local spacing = 0
  local anchor = unitFrame.healthBar or unitFrame

  ns.Frames.Clear("nameplateDebuffs", unitFrame)

  unitFrame.auraSize = size
  unitFrame.maxBuffs = maxIcons
  unitFrame.maxDebuffs = maxIcons
  if type(unitFrame.optionTable) == "table" then
    unitFrame.optionTable.auraSize = size
    unitFrame.optionTable.buffSize = size
    unitFrame.optionTable.debuffSize = size
    unitFrame.optionTable.maxBuffs = maxIcons
    unitFrame.optionTable.maxDebuffs = maxIcons
  end
  auraFrame.auraSize = size
  auraFrame.buffSize = size
  auraFrame.debuffSize = size
  auraFrame.maxBuffs = maxIcons
  auraFrame.maxDebuffs = maxIcons

  pcall(auraFrame.SetAlpha, auraFrame, 1)
  pcall(auraFrame.Show, auraFrame)
  pcall(auraFrame.ClearAllPoints, auraFrame)
  pcall(auraFrame.SetPoint, auraFrame, "BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
  pcall(auraFrame.SetSize, auraFrame, maxIcons * size + math.max(0, maxIcons - 1) * spacing, size)
  pcall(auraFrame.SetFrameLevel, auraFrame, (type(unitFrame.GetFrameLevel) == "function" and unitFrame:GetFrameLevel() or 0) + 100)
  pcall(auraFrame.SetFrameStrata, auraFrame, "HIGH")

  local children = { seen = {} }
  AddKnownAuraButtons(unitFrame, auraFrame, children)
  CollectAuraButtons(auraFrame, children, 1)

  local styled = 0
  for _, child in ipairs(children) do
    if child and type(child.IsShown) == "function" and child:IsShown() then
      styled = styled + 1
      ConfigureAuraButton(child, size)
      pcall(child.ClearAllPoints, child)
      pcall(child.SetPoint, child, "BOTTOMLEFT", auraFrame, "BOTTOMLEFT", (styled - 1) * (size + spacing), 0)

      if styled > maxIcons then
        pcall(child.Hide, child)
      end
    end
  end
end

local function ScheduleStyle(unitFrame)
  StyleBlizzardAuras(unitFrame)
  C_Timer.After(0, function()
    StyleBlizzardAuras(unitFrame)
  end)
  C_Timer.After(0.05, function()
    StyleBlizzardAuras(unitFrame)
  end)
  C_Timer.After(0.15, function()
    StyleBlizzardAuras(unitFrame)
  end)
end

function NameplateDebuffs:UpdateUnit(unit)
  if not unit or not string.match(unit, "^nameplate%d+$") then
    return
  end

  local unitFrame = GetNamePlateUnitFrame(unit)
  if not unitFrame then
    return
  end

  unitsByFrame[unitFrame] = unit
  framesByUnit[unit] = unitFrame

  if not ns.GetSettings("nameplateDebuffs").enabled then
    ns.Frames.Clear("nameplateDebuffs", unitFrame)
    SetBlizzardAurasShown(unitFrame, true)
    return
  end

  if UnitCanAttack and UnitCanAttack("player", unit) then
    if #ns.GetEnabledCategories({ "dots", "utility" }) > 0 then
      ScheduleStyle(unitFrame)
    else
      ns.Frames.Clear("nameplateDebuffs", unitFrame)
      SetBlizzardAurasShown(unitFrame, true)
    end
  else
    if #ns.GetEnabledCategories({ "hots", "externals", "utility" }) > 0 then
      SetBlizzardAurasShown(unitFrame, false)
      ns.Frames.RenderAuras("nameplateDebuffs", unitFrame, unit, GetFriendlyHotOptions())
    else
      ns.Frames.Clear("nameplateDebuffs", unitFrame)
      SetBlizzardAurasShown(unitFrame, true)
    end
  end
end

function NameplateDebuffs:ClearUnit(unit)
  local unitFrame = GetNamePlateUnitFrame(unit) or framesByUnit[unit]
  if unitFrame then
    ns.Frames.Clear("nameplateDebuffs", unitFrame)
    SetBlizzardAurasShown(unitFrame, true)
    unitsByFrame[unitFrame] = nil
  end
  framesByUnit[unit] = nil
end

function NameplateDebuffs:OnLogin()
  ns.RegisterEvent("NAME_PLATE_UNIT_ADDED")
  ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  ns.RegisterEvent("UNIT_AURA")

  if not compactAuraHooked and type(CompactUnitFrame_UpdateAuras) == "function" then
    compactAuraHooked = true
    hooksecurefunc("CompactUnitFrame_UpdateAuras", function(unitFrame)
      if unitFrame and unitFrame.namePlateFrame then
        ScheduleStyle(unitFrame)
      end
    end)
  end
end

function NameplateDebuffs:ApplySettings()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then
    return
  end

  for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
    local unitFrame = namePlate.UnitFrame or namePlate
    local unit = FindUnitForNamePlate(namePlate, unitFrame)
    if unit then
      self:UpdateUnit(unit)
    elseif not ns.GetSettings("nameplateDebuffs").enabled then
      ns.Frames.Clear("nameplateDebuffs", unitFrame)
      SetBlizzardAurasShown(unitFrame, true)
    elseif unitFrame then
      ScheduleStyle(unitFrame)
    end
  end
end

function NameplateDebuffs:ShowTestIcons()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then
    return
  end

  for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
    local unitFrame = namePlate.UnitFrame or namePlate
    ns.Frames.RenderTestIcon("nameplateDebuffs", unitFrame, GetOptions())
  end
end

function NameplateDebuffs:NAME_PLATE_UNIT_ADDED(unit)
  self:UpdateUnit(unit)
end

function NameplateDebuffs:NAME_PLATE_UNIT_REMOVED(unit)
  self:ClearUnit(unit)
end

function NameplateDebuffs:UNIT_AURA(unit)
  self:UpdateUnit(unit)
end

local function DebugText(value)
  local ok, text = pcall(function()
    return "" .. value
  end)

  if ok and type(text) == "string" and pcall(table.concat, { text }, "") then
    return text
  end

  return "restricted"
end

local function AppendLine(lines, ...)
  local line = ""
  for index = 1, select("#", ...) do
    if index > 1 then
      line = line .. " "
    end
    line = line .. DebugText(select(index, ...))
  end

  lines[#lines + 1] = line
end

local function DebugOutput(lines)
  local safeLines = {}
  for index, line in ipairs(lines) do
    safeLines[index] = DebugText(line)
  end

  return table.concat(safeLines, "\n")
end

function NameplateDebuffs:Debug()
  self:ApplySettings()

  local settings = ns.GetSettings("nameplateDebuffs")
  local lines = {
    ns.displayName .. " nameplate debug",
    "enabled: " .. tostring(settings.enabled),
    "iconSize: " .. tostring(settings.iconSize),
    "maxIcons: " .. tostring(settings.maxIcons),
    "onlyPlayer: " .. tostring(settings.onlyPlayer),
    "C_NamePlate: " .. tostring(type(C_NamePlate)),
    "GetNamePlates: " .. tostring(C_NamePlate and type(C_NamePlate.GetNamePlates)),
    "GetNamePlateForUnit: " .. tostring(C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)),
  }

  if not C_NamePlate or not C_NamePlate.GetNamePlates then
    error(DebugOutput(lines), 0)
    return
  end

  local namePlates = C_NamePlate.GetNamePlates()
  AppendLine(lines, "visible nameplates:", namePlates and #namePlates or 0)

  for _, token in ipairs({ "target", "mouseover" }) do
    AppendLine(lines, "== unit", token, "==")
    AppendLine(lines, "UnitExists:", tostring(UnitExists(token)))
    if UnitExists(token) then
      AppendLine(lines, "UnitCanAttack:", tostring(UnitCanAttack and UnitCanAttack("player", token)))
      local seen = 0
      for auraIndex = 1, 10 do
        local aura = ns.Auras.Read(token, auraIndex, "HARMFUL", GetOptions())
        if not aura then
          break
        end

        seen = seen + 1
        local options = GetOptions()
        AppendLine(lines, "  debuff", auraIndex, "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"), "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"), "icon=", tostring(ns.Auras.HasIcon(aura)), "duration=", tostring(ns.Auras.HasDuration(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "deny=", tostring(ns.Auras.IsDenylisted(aura)), "restrictedFallback=", tostring(options.allowRestrictedPlayerAura and ns.Auras.IsPlayerAura(aura)), "match=", tostring(ns.Auras.Matches(aura, options)))
      end
      AppendLine(lines, "harmful scanned:", seen)

      local helpfulSeen = 0
      local helpfulMatched = 0
      for auraIndex = 1, 10 do
        local aura = ns.Auras.Read(token, auraIndex, "HELPFUL", GetFriendlyHotOptions())
        if not aura then
          break
        end

        helpfulSeen = helpfulSeen + 1
        if ns.Auras.Matches(aura, GetFriendlyHotOptions()) then
          helpfulMatched = helpfulMatched + 1
        end
        AppendLine(lines, "  helpful", auraIndex, "tracked=", tostring(ns.Auras.IsTrackedHot(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "match=", tostring(ns.Auras.Matches(aura, GetFriendlyHotOptions())))
      end
      AppendLine(lines, "helpful scanned:", helpfulSeen, "hot matched:", helpfulMatched)
    end
  end

  for plateIndex, namePlate in ipairs(namePlates or {}) do
    local unitFrame = namePlate.UnitFrame or namePlate
    local unit = FindUnitForNamePlate(namePlate, unitFrame)

    AppendLine(lines, "== plate", plateIndex, "==")
    AppendLine(lines, "namePlate:", ns.Frames.SafeName(namePlate))
    AppendLine(lines, "unitFrame:", ns.Frames.SafeName(unitFrame))
    AppendLine(lines, "unit:", unit or "nil")
    AppendLine(lines, "forbidden:", tostring(ns.Frames.IsForbidden(unitFrame)))
    if unitFrame and unitFrame.AurasFrame then
      local buttons = { seen = {} }
      AddKnownAuraButtons(unitFrame, unitFrame.AurasFrame, buttons)
      CollectAuraButtons(unitFrame.AurasFrame, buttons, 1)
      AppendLine(lines, "auraFrame:", ns.Frames.SafeName(unitFrame.AurasFrame), "buttons found:", #buttons)
    else
      AppendLine(lines, "auraFrame: nil")
    end

    if unit then
      AppendLine(lines, "UnitExists:", tostring(UnitExists(unit)))
      AppendLine(lines, "UnitCanAttack:", tostring(UnitCanAttack and UnitCanAttack("player", unit)))

      local seen = 0
      local matched = 0
      for auraIndex = 1, 10 do
        local aura = ns.Auras.Read(unit, auraIndex, "HARMFUL", GetOptions())
        if not aura then
          break
        end

        seen = seen + 1
        if ns.Auras.Matches(aura, GetOptions()) then
          matched = matched + 1
        end

        local options = GetOptions()
        AppendLine(lines, "  debuff", auraIndex, "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"), "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"), "icon=", tostring(ns.Auras.HasIcon(aura)), "duration=", tostring(ns.Auras.HasDuration(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "deny=", tostring(ns.Auras.IsDenylisted(aura)), "restrictedFallback=", tostring(options.allowRestrictedPlayerAura and ns.Auras.IsPlayerAura(aura)), "match=", tostring(ns.Auras.Matches(aura, options)))
      end

      AppendLine(lines, "harmful scanned:", seen, "matched:", matched)

      local helpfulSeen = 0
      local helpfulMatched = 0
      for auraIndex = 1, 10 do
        local aura = ns.Auras.Read(unit, auraIndex, "HELPFUL", GetFriendlyHotOptions())
        if not aura then
          break
        end

        helpfulSeen = helpfulSeen + 1
        if ns.Auras.Matches(aura, GetFriendlyHotOptions()) then
          helpfulMatched = helpfulMatched + 1
        end
        AppendLine(lines, "  helpful", auraIndex, "tracked=", tostring(ns.Auras.IsTrackedHot(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "match=", tostring(ns.Auras.Matches(aura, GetFriendlyHotOptions())))
      end
      AppendLine(lines, "helpful scanned:", helpfulSeen, "hot matched:", helpfulMatched)
    end
  end

  error(DebugOutput(lines), 0)
end

ns.RegisterModule("nameplateDebuffs", NameplateDebuffs)
