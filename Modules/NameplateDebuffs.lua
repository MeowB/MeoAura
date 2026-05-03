local _, ns = ...

local NameplateDebuffs = {}
ns.NameplateDebuffs = NameplateDebuffs

local unitsByFrame = setmetatable({}, { __mode = "k" })
local framesByUnit = {}
local nativeCooldownsByFrame = setmetatable({}, { __mode = "k" })
local nativeCooldownsByUnit = {}
local lastNativeCooldownByUnit = {}
local lastNativeCooldownByFrame = setmetatable({}, { __mode = "k" })
local lastUnresolvedNativeCooldown
local replayedCooldownsByFrame = setmetatable({}, { __mode = "k" })
local replayedCooldownsByUnit = {}
local hookedNativeCooldowns = setmetatable({}, { __mode = "k" })
local nativeCooldownButtons = setmetatable({}, { __mode = "k" })
local nativeCooldownUnits = setmetatable({}, { __mode = "k" })
local compactAuraHooked = false
local cooldownFrameSetHooked = false
local cooldownMixinHooked = false
local ReplayNativeCooldown
local ScheduleStyle
local SetBlizzardAurasShown
local cooldownCaptureStats = {
  calls = 0,
  noParent = 0,
  noUnit = 0,
  nonNameplate = 0,
  stored = 0,
  storedExact = 0,
  refreshed = 0,
  discovered = 0,
  mapped = 0,
  unresolved = 0,
}

local function GetOptions()
  local settings = ns.GetSettings("nameplateDebuffs")
  return {
    filter = "HARMFUL",
    categories = ns.GetEnabledCategories({ "dots", "utility" }),
    onlyPlayer = settings.onlyPlayer,
    iconSize = settings.iconSize,
    maxIcons = settings.maxIcons,
    maxScan = 40,
    cooldownText = settings.cooldownText,
    requireDuration = false,
    preferLegacy = true,
    includeNameplateOnly = true,
    allowRestrictedAura = true,
    point = "BOTTOMLEFT",
    relativePoint = "TOPLEFT",
    growth = "RIGHT",
    x = 0,
    y = 2,
    backingAlpha = 0.75,
    cooldownReplay = ReplayNativeCooldown,
    anchorFrame = function(unitFrame)
      return unitFrame.healthBar or unitFrame
    end,
  }
end

local function GetFriendlyHotOptions()
  local debuffSettings = ns.GetSettings("nameplateDebuffs")
  local settings = ns.GetSettings("nameplateHots")
  return {
    filter = "HELPFUL",
    categories = ns.GetEnabledCategories({ "hots", "externals", "utility" }),
    onlyPlayer = true,
    requirePlayerSource = true,
    iconSize = settings.iconSize,
    maxIcons = debuffSettings.maxIcons,
    maxScan = 40,
    cooldownText = debuffSettings.cooldownText,
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

local function FriendlyNameplateHotsEnabled()
  local settings = ns.GetSettings("nameplateHots")
  return settings and settings.enabled == true and #ns.GetEnabledCategories({ "hots", "externals", "utility" }) > 0
end

local function NameplateModuleActive()
  return ns.GetSettings("nameplateDebuffs").enabled == true or FriendlyNameplateHotsEnabled()
end

local function RenderFriendlyNameplateAuras(unitFrame, unit)
  if FriendlyNameplateHotsEnabled() then
    SetBlizzardAurasShown(unitFrame, false)
    ns.Frames.RenderAuras("nameplateDebuffs", unitFrame, unit, GetFriendlyHotOptions())
  else
    ns.Frames.Clear("nameplateDebuffs", unitFrame)
    SetBlizzardAurasShown(unitFrame, true)
  end
end

local function GetNamePlateUnitFrame(unit)
  if type(unit) ~= "string" or not string.match(unit, "^nameplate%d+$") then
    return nil
  end

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

function SetBlizzardAurasShown(unitFrame, shown)
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

local function IsNativeDebuffButton(button)
  if type(button) ~= "table" then
    return false
  end

  local ok, isBuff = pcall(function()
    return button.isBuff
  end)
  return ok and isBuff ~= true
end

local function StyleNativeAuraButton(button, size)
  if type(button) ~= "table" then
    return
  end

  local scale = 1
  if type(size) == "number" and size > 0 then
    scale = size / 12
  end

  if type(button.SetScale) == "function" then
    pcall(button.SetScale, button, scale)
  end

  if type(button.SetFrameLevel) == "function" and type(button.GetParent) == "function" then
    local okParent, parent = pcall(button.GetParent, button)
    local parentLevel = okParent and type(parent) == "table" and type(parent.GetFrameLevel) == "function" and parent:GetFrameLevel() or 0
    pcall(button.SetFrameLevel, button, parentLevel + 10)
  end

  local cooldown = button.cooldown or button.Cooldown or button.CooldownFrame
  if cooldown and type(cooldown.SetHideCountdownNumbers) == "function" then
    pcall(cooldown.SetHideCountdownNumbers, cooldown, not ns.GetSettings("nameplateDebuffs").cooldownText)
  end
end

local function StyleNativeAuraButtons(unitFrame)
  local settings = ns.GetSettings("nameplateDebuffs")
  local auraFrame = unitFrame and unitFrame.AurasFrame
  if not auraFrame then
    return
  end

  local buttons = { seen = {} }
  AddKnownAuraButtons(unitFrame, auraFrame, buttons)
  CollectAuraButtons(auraFrame, buttons, 1)

  for _, button in ipairs(buttons) do
    if IsNativeDebuffButton(button) then
      StyleNativeAuraButton(button, settings.iconSize)
    end
  end

  SetBlizzardAurasShown(unitFrame, true)
end

local function GetCooldownFrame(button)
  if type(button) ~= "table" then
    return nil
  end

  return button.cooldown or button.Cooldown or button.CooldownFrame
end

local function StoreNativeCooldown(unitFrame, button, start, duration, unit)
  if type(button) ~= "table" then
    return
  end

  local stored = false
  if type(unitFrame) == "table" then
    lastNativeCooldownByFrame[unitFrame] = {
      hasCooldown = true,
      start = start,
      duration = duration,
    }
    stored = true
  end

  unit = unit or button.unitToken
  if type(unit) == "string" and string.match(unit, "^nameplate%d+$") then
    lastNativeCooldownByUnit[unit] = {
      hasCooldown = true,
      start = start,
      duration = duration,
    }
    stored = true
  end

  if stored then
    cooldownCaptureStats.stored = cooldownCaptureStats.stored + 1
  end

  local auraInstanceID = button.auraInstanceID
  if auraInstanceID == nil then
    return
  end

  if type(unitFrame) == "table" then
    local cooldowns = nativeCooldownsByFrame[unitFrame]
    if not cooldowns then
      cooldowns = {}
      nativeCooldownsByFrame[unitFrame] = cooldowns
    end

    cooldowns[auraInstanceID] = {
      hasCooldown = true,
      start = start,
      duration = duration,
    }
    cooldownCaptureStats.storedExact = cooldownCaptureStats.storedExact + 1
  end

  if type(unit) == "string" and string.match(unit, "^nameplate%d+$") then
    local cooldowns = nativeCooldownsByUnit[unit]
    if not cooldowns then
      cooldowns = {}
      nativeCooldownsByUnit[unit] = cooldowns
    end

    cooldowns[auraInstanceID] = {
      hasCooldown = true,
      start = start,
      duration = duration,
    }
    cooldownCaptureStats.storedExact = cooldownCaptureStats.storedExact + 1
  end
end

local function StoreNativeCooldownFromFrame(cooldown, start, duration)
  cooldownCaptureStats.calls = cooldownCaptureStats.calls + 1

  if type(cooldown) ~= "table" or type(cooldown.GetParent) ~= "function" then
    cooldownCaptureStats.noParent = cooldownCaptureStats.noParent + 1
    return
  end

  local okParent, button = pcall(cooldown.GetParent, cooldown)
  if not okParent or type(button) ~= "table" then
    button = nativeCooldownButtons[cooldown]
  end

  if type(button) ~= "table" then
    cooldownCaptureStats.noParent = cooldownCaptureStats.noParent + 1
    return
  end

  local unit = nativeCooldownUnits[cooldown] or button.unitToken
  if type(unit) ~= "string" and type(button.GetParent) == "function" then
    local frame = button
    for _ = 1, 4 do
      local okFrame, parent = pcall(frame.GetParent, frame)
      if not okFrame or type(parent) ~= "table" then
        break
      end

      unit = parent.unitToken
      if type(unit) == "string" then
        break
      end

      frame = parent
    end
  end

  if type(unit) ~= "string" then
    lastUnresolvedNativeCooldown = {
      hasCooldown = true,
      start = start,
      duration = duration,
    }
    cooldownCaptureStats.unresolved = cooldownCaptureStats.unresolved + 1
    cooldownCaptureStats.noUnit = cooldownCaptureStats.noUnit + 1
    return
  end

  if not string.match(unit, "^nameplate%d+$") then
    cooldownCaptureStats.nonNameplate = cooldownCaptureStats.nonNameplate + 1
    return
  end

  local unitFrame = framesByUnit[unit]
  if not unitFrame then
    unitFrame = GetNamePlateUnitFrame(unit)
    if unitFrame then
      framesByUnit[unit] = unitFrame
      unitsByFrame[unitFrame] = unit
    end
  end

  StoreNativeCooldown(unitFrame, button, start, duration, unit)

  if unitFrame and type(unit) == "string" and type(ScheduleStyle) == "function" and C_Timer and type(C_Timer.After) == "function" then
    cooldownCaptureStats.refreshed = cooldownCaptureStats.refreshed + 1
    C_Timer.After(0, function()
      ScheduleStyle(unitFrame, unit)
    end)
  end
end

local function HookCooldownFrameSet()
  if type(hooksecurefunc) ~= "function" then
    return
  end

  if not cooldownFrameSetHooked and type(CooldownFrame_Set) == "function" then
    local okHook = pcall(hooksecurefunc, "CooldownFrame_Set", function(cooldown, start, duration)
      StoreNativeCooldownFromFrame(cooldown, start, duration)
    end)
    cooldownFrameSetHooked = okHook == true
  end

  if not cooldownMixinHooked and type(CooldownFrameMixin) == "table" and type(CooldownFrameMixin.SetCooldown) == "function" then
    local okHook = pcall(hooksecurefunc, CooldownFrameMixin, "SetCooldown", function(cooldown, start, duration)
      StoreNativeCooldownFromFrame(cooldown, start, duration)
    end)
    cooldownMixinHooked = okHook == true
  end
end

local function HookNativeCooldowns(unitFrame)
  local auraFrame = unitFrame and unitFrame.AurasFrame
  if not auraFrame then
    return
  end

  local buttons = { seen = {} }
  AddKnownAuraButtons(unitFrame, auraFrame, buttons)
  CollectAuraButtons(auraFrame, buttons, 1)

  for _, button in ipairs(buttons) do
    local cooldown = GetCooldownFrame(button)
    if cooldown then
      cooldownCaptureStats.discovered = cooldownCaptureStats.discovered + 1
      nativeCooldownButtons[cooldown] = button
      nativeCooldownUnits[cooldown] = button.unitToken or unitsByFrame[unitFrame]
      if type(nativeCooldownUnits[cooldown]) == "string" and string.match(nativeCooldownUnits[cooldown], "^nameplate%d+$") then
        cooldownCaptureStats.mapped = cooldownCaptureStats.mapped + 1
      end
    end

    if cooldown and not hookedNativeCooldowns[cooldown] and type(hooksecurefunc) == "function" and type(cooldown.SetCooldown) == "function" then
      hookedNativeCooldowns[cooldown] = true
      hooksecurefunc(cooldown, "SetCooldown", function(_, start, duration)
        cooldownCaptureStats.calls = cooldownCaptureStats.calls + 1
        local unit = nativeCooldownUnits[cooldown] or button.unitToken or unitsByFrame[unitFrame]
        if type(unit) ~= "string" then
          cooldownCaptureStats.noUnit = cooldownCaptureStats.noUnit + 1
          return
        end

        if not string.match(unit, "^nameplate%d+$") then
          cooldownCaptureStats.nonNameplate = cooldownCaptureStats.nonNameplate + 1
          return
        end

        StoreNativeCooldown(unitFrame, button, start, duration, unit)
        if unitFrame and type(unit) == "string" and type(ScheduleStyle) == "function" and C_Timer and type(C_Timer.After) == "function" then
          cooldownCaptureStats.refreshed = cooldownCaptureStats.refreshed + 1
          C_Timer.After(0, function()
            ScheduleStyle(unitFrame, unit)
          end)
        end
      end)
    end
  end
end

function ReplayNativeCooldown(unitFrame, iconIndex, aura, cooldown, unit)
  if type(cooldown) ~= "table" or type(cooldown.SetCooldown) ~= "function" then
    return false
  end

  local auraInstanceID = ns.Auras.SafeField(aura, "auraInstanceID")
  local replayedCooldowns
  if type(unitFrame) == "table" then
    replayedCooldowns = replayedCooldownsByFrame[unitFrame]
    if not replayedCooldowns then
      replayedCooldowns = {}
      replayedCooldownsByFrame[unitFrame] = replayedCooldowns
    end
  end

  local cooldowns = nativeCooldownsByFrame[unitFrame]
  local native = cooldowns and cooldowns[auraInstanceID]
  if not native and type(unit) == "string" then
    cooldowns = nativeCooldownsByUnit[unit]
    native = cooldowns and cooldowns[auraInstanceID]
    replayedCooldowns = replayedCooldownsByUnit[unit]
    if not replayedCooldowns then
      replayedCooldowns = {}
      replayedCooldownsByUnit[unit] = replayedCooldowns
    end
  end
  if not native and type(unit) == "string" then
    native = lastNativeCooldownByUnit[unit]
  end
  if not native then
    native = lastNativeCooldownByFrame[unitFrame]
  end
  if not native then
    native = lastUnresolvedNativeCooldown
  end

  if native and native.hasCooldown then
    local ok = pcall(cooldown.SetCooldown, cooldown, native.start, native.duration)
    if replayedCooldowns then
      replayedCooldowns[auraInstanceID] = ok == true
    end
    return ok == true
  end

  if replayedCooldowns then
    replayedCooldowns[auraInstanceID] = false
  end
  return false
end

local function RenderNameplateAuras(unitFrame, unit)
  if not NameplateModuleActive() then
    return
  end

  if not unit then
    return
  end

  if UnitCanAttack and UnitCanAttack("player", unit) then
    if ns.GetSettings("nameplateDebuffs").enabled then
      ns.Frames.Clear("nameplateDebuffs", unitFrame)
      StyleNativeAuraButtons(unitFrame)
    end
  elseif UnitIsFriend and UnitIsFriend("player", unit) then
    RenderFriendlyNameplateAuras(unitFrame, unit)
  end
end

function ScheduleStyle(unitFrame, unit)
  unit = unit or unitsByFrame[unitFrame] or ns.Frames.GetUnit(unitFrame)

  RenderNameplateAuras(unitFrame, unit)
  C_Timer.After(0, function()
    RenderNameplateAuras(unitFrame, unit)
  end)
  C_Timer.After(0.05, function()
    RenderNameplateAuras(unitFrame, unit)
  end)
  C_Timer.After(0.15, function()
    RenderNameplateAuras(unitFrame, unit)
  end)
end

function NameplateDebuffs:UpdateUnit(unit)
  if not NameplateModuleActive() then
    return
  end

  if not unit or not string.match(unit, "^nameplate%d+$") then
    return
  end

  local unitFrame = GetNamePlateUnitFrame(unit)
  if not unitFrame then
    return
  end

  unitsByFrame[unitFrame] = unit
  framesByUnit[unit] = unitFrame

  if UnitCanAttack and UnitCanAttack("player", unit) then
    if ns.GetSettings("nameplateDebuffs").enabled then
      ScheduleStyle(unitFrame, unit)
    end
  elseif UnitIsFriend and UnitIsFriend("player", unit) then
    RenderFriendlyNameplateAuras(unitFrame, unit)
  end
end

function NameplateDebuffs:ClearUnit(unit)
  if not NameplateModuleActive() then
    framesByUnit[unit] = nil
    return
  end

  local unitFrame = GetNamePlateUnitFrame(unit) or framesByUnit[unit]
  if unitFrame then
    ns.Frames.Clear("nameplateDebuffs", unitFrame)
    SetBlizzardAurasShown(unitFrame, true)
    unitsByFrame[unitFrame] = nil
  end
  framesByUnit[unit] = nil
end

function NameplateDebuffs:OnLogin()
  if not NameplateModuleActive() then
    return
  end

  ns.RegisterEvent("nameplateDebuffs", "NAME_PLATE_UNIT_ADDED")
  ns.RegisterEvent("nameplateDebuffs", "NAME_PLATE_UNIT_REMOVED")
  ns.RegisterEvent("nameplateDebuffs", "UNIT_AURA")

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
  if not NameplateModuleActive() then
    return
  end

  if not C_NamePlate or not C_NamePlate.GetNamePlates then
    return
  end

  for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
    local unitFrame = namePlate.UnitFrame or namePlate
    local unit = FindUnitForNamePlate(namePlate, unitFrame)
    if unit then
      self:UpdateUnit(unit)
    elseif not ns.GetSettings("nameplateDebuffs").enabled and not FriendlyNameplateHotsEnabled() then
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

local function HasCapturedCooldown(unitFrame, aura, unit)
  local auraInstanceID = ns.Auras.SafeField(aura, "auraInstanceID")
  local cooldowns = nativeCooldownsByFrame[unitFrame]
  local native = cooldowns and cooldowns[auraInstanceID]
  if native and native.hasCooldown == true then
    return true
  end

  cooldowns = nativeCooldownsByUnit[unit]
  native = cooldowns and cooldowns[auraInstanceID]
  if native and native.hasCooldown == true then
    return true
  end

  native = lastNativeCooldownByUnit[unit] or lastNativeCooldownByFrame[unitFrame]
  if native and native.hasCooldown == true then
    return true
  end

  native = lastUnresolvedNativeCooldown
  return native and native.hasCooldown == true
end

local function HasReplayedCooldown(unitFrame, aura, unit)
  local auraInstanceID = ns.Auras.SafeField(aura, "auraInstanceID")
  local replayedCooldowns = replayedCooldownsByFrame[unitFrame]
  if replayedCooldowns and replayedCooldowns[auraInstanceID] == true then
    return true
  end

  replayedCooldowns = replayedCooldownsByUnit[unit]
  return replayedCooldowns and replayedCooldowns[auraInstanceID] == true
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
    "CooldownFrame_Set hook: " .. tostring(cooldownFrameSetHooked),
    "CooldownFrameMixin hook: " .. tostring(cooldownMixinHooked),
    "cooldown captures: calls=" .. tostring(cooldownCaptureStats.calls) .. " stored=" .. tostring(cooldownCaptureStats.stored) .. " exact=" .. tostring(cooldownCaptureStats.storedExact) .. " refreshed=" .. tostring(cooldownCaptureStats.refreshed) .. " unresolved=" .. tostring(cooldownCaptureStats.unresolved),
    "cooldown mapped: discovered=" .. tostring(cooldownCaptureStats.discovered) .. " mapped=" .. tostring(cooldownCaptureStats.mapped),
    "cooldown skips: noParent=" .. tostring(cooldownCaptureStats.noParent) .. " noUnit=" .. tostring(cooldownCaptureStats.noUnit) .. " nonNameplate=" .. tostring(cooldownCaptureStats.nonNameplate),
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
      AppendLine(lines, "UnitIsPlayer:", tostring(UnitIsPlayer and UnitIsPlayer(token)))
      AppendLine(lines, "UnitPlayerControlled:", tostring(UnitPlayerControlled and UnitPlayerControlled(token)))
      AppendLine(lines, "UnitCreatureType:", tostring(UnitCreatureType and UnitCreatureType(token)))
      AppendLine(lines, "UnitClassification:", tostring(UnitClassification and UnitClassification(token)))
      local seen = 0
      for auraIndex = 1, 10 do
        local aura = ns.Auras.Read(token, auraIndex, "HARMFUL", GetOptions())
        if not aura then
          break
        end

        seen = seen + 1
        local options = GetOptions()
        AppendLine(lines, "  debuff", auraIndex, "auraInstanceID=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "auraInstanceID") or "nil"), "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"), "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"), "icon=", tostring(ns.Auras.HasIcon(aura)), "duration=", tostring(ns.Auras.HasDuration(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "deny=", tostring(ns.Auras.IsDenylisted(aura)), "restrictedFallback=", tostring(options.allowRestrictedAura), "match=", tostring(ns.Auras.Matches(aura, options)))
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
      AppendLine(lines, "UnitIsPlayer:", tostring(UnitIsPlayer and UnitIsPlayer(unit)))
      AppendLine(lines, "UnitPlayerControlled:", tostring(UnitPlayerControlled and UnitPlayerControlled(unit)))
      AppendLine(lines, "UnitCreatureType:", tostring(UnitCreatureType and UnitCreatureType(unit)))
      AppendLine(lines, "UnitClassification:", tostring(UnitClassification and UnitClassification(unit)))

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
        AppendLine(lines, "  debuff", auraIndex, "auraInstanceID=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "auraInstanceID") or "nil"), "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"), "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"), "icon=", tostring(ns.Auras.HasIcon(aura)), "duration=", tostring(ns.Auras.HasDuration(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "capturedCooldown=", tostring(HasCapturedCooldown(unitFrame, aura, unit)), "replayedCooldown=", tostring(HasReplayedCooldown(unitFrame, aura, unit)), "deny=", tostring(ns.Auras.IsDenylisted(aura)), "restrictedFallback=", tostring(options.allowRestrictedAura), "match=", tostring(ns.Auras.Matches(aura, options)))
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
