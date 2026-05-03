local _, ns = ...

local ArenaDebuffs = {}
ns.ArenaDebuffs = ArenaDebuffs

local AURA_CACHE_TTL = 45
local auraCacheByGUID = {}
local preparedFrames = setmetatable({}, { __mode = "k" })
local updateAfterCombat = false
local traceLog = {}
local cacheStats = {
  seen = 0,
  tracked = 0,
  removed = 0,
  restrictedGUID = 0,
  ignoredSource = 0,
  ignoredAuraType = 0,
  ignoredSpell = 0,
}

local function Trace(message)
  traceLog[#traceLog + 1] = string.format("%.3f %s", GetTime and GetTime() or 0, tostring(message))
  if #traceLog > 30 then
    table.remove(traceLog, 1)
  end
end

local function GetOptions(skipLayout)
  local settings = ns.GetSettings("arenaDebuffs")
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
    allowRestrictedAura = false,
    point = "TOPRIGHT",
    relativePoint = "TOPRIGHT",
    growth = "LEFT",
    x = -1,
    y = 1,
    backingAlpha = 0.75,
    skipCreate = skipLayout,
    skipLayout = skipLayout,
    anchorFrame = function(unitFrame)
      return unitFrame.healthBar or unitFrame
    end,
  }
end

local function GetSpellIcon(spellId)
  if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
    local ok, icon = pcall(C_Spell.GetSpellTexture, spellId)
    if ok and icon then
      return icon
    end
  end

  if type(GetSpellTexture) == "function" then
    local ok, icon = pcall(GetSpellTexture, spellId)
    if ok and icon then
      return icon
    end
  end
end

local function SafeUnitGUID(unit)
  if not UnitGUID or type(unit) ~= "string" then
    return nil
  end

  local ok, guid = pcall(UnitGUID, unit)
  if ok and type(guid) == "string" then
    return guid
  end
end

local function GetPlayerSourceGUIDs()
  local guids = {}
  local playerGUID = SafeUnitGUID("player")
  local petGUID = SafeUnitGUID("pet")

  if type(playerGUID) == "string" then
    guids[playerGUID] = true
  end
  if type(petGUID) == "string" then
    guids[petGUID] = true
  end

  return guids
end

local function IsPlayerSource(sourceGUID)
  return GetPlayerSourceGUIDs()[sourceGUID] == true
end

local function SafeCacheGet(key)
  if type(key) ~= "string" then
    return nil
  end

  local ok, value = pcall(function()
    return auraCacheByGUID[key]
  end)

  if ok then
    return value
  end

  cacheStats.restrictedGUID = cacheStats.restrictedGUID + 1
end

local function SafeCacheSet(key, value)
  if type(key) ~= "string" then
    return false
  end

  local ok = pcall(function()
    auraCacheByGUID[key] = value
  end)

  if ok then
    return true
  end

  cacheStats.restrictedGUID = cacheStats.restrictedGUID + 1
  return false
end

local function GetCacheForGUID(destGUID)
  if type(destGUID) ~= "string" then
    return nil
  end

  local cache = SafeCacheGet(destGUID)
  if not cache then
    cache = {}
    if not SafeCacheSet(destGUID, cache) then
      return nil
    end
  end

  return cache
end

local function IsTrackedCombatAura(spellId, spellName)
  local aura = {
    spellId = spellId,
    name = spellName,
    icon = GetSpellIcon(spellId) or "Interface\\Icons\\INV_Misc_QuestionMark",
  }

  return ns.Auras.IsTrackedAura(aura, ns.GetEnabledCategories({ "dots", "utility" })) and not ns.Auras.IsDenylisted(aura)
end

local function StoreCombatAura(destGUID, spellId, spellName, applications, sourceGUID)
  local cache = GetCacheForGUID(destGUID)
  if not cache then
    return
  end

  cache[spellId] = {
    name = spellName,
    spellId = spellId,
    icon = GetSpellIcon(spellId) or "Interface\\Icons\\INV_Misc_QuestionMark",
    applications = applications or 0,
    sourceGUID = sourceGUID,
    appliedAt = GetTime and GetTime() or 0,
  }
  cacheStats.tracked = cacheStats.tracked + 1
  Trace("cache store " .. tostring(spellName) .. " " .. tostring(spellId))
end

local function ClearCache()
  auraCacheByGUID = {}
end

local function RemoveCombatAura(destGUID, spellId)
  local cache = SafeCacheGet(destGUID)
  if cache and cache[spellId] then
    cache[spellId] = nil
    cacheStats.removed = cacheStats.removed + 1
    Trace("cache remove " .. tostring(spellId))
  end
end

local function PruneCacheForGUID(destGUID)
  local cache = SafeCacheGet(destGUID)
  local now = GetTime and GetTime() or 0
  if not cache then
    return
  end

  for spellId, aura in pairs(cache) do
    local expirationTime = ns.Auras.SafeField(aura, "expirationTime")
    local appliedAt = ns.Auras.SafeField(aura, "appliedAt") or now
    if (type(expirationTime) == "number" and expirationTime > 0 and expirationTime <= now) or (expirationTime == nil and now - appliedAt > AURA_CACHE_TTL) then
      cache[spellId] = nil
    end
  end
end

local function EnrichCachedAuras(unit, cache)
  if type(unit) ~= "string" or not UnitExists(unit) then
    return
  end

  local scanOptions = {
    onlyPlayer = true,
    preferLegacy = true,
    requireDuration = false,
  }

  for auraIndex = 1, 40 do
    local aura = ns.Auras.Read(unit, auraIndex, "HARMFUL", scanOptions)
    if not aura then
      break
    end

    local spellId = ns.Auras.SafeField(aura, "spellId")
    local cached = cache[spellId]
    if cached then
      cached.icon = ns.Auras.GetIcon(aura) or cached.icon
      cached.duration = ns.Auras.SafeField(aura, "duration")
      cached.expirationTime = ns.Auras.SafeField(aura, "expirationTime")
      cached.applications = ns.Auras.SafeField(aura, "applications") or ns.Auras.SafeField(aura, "count") or cached.applications
      cached.auraInstanceID = ns.Auras.SafeField(aura, "auraInstanceID")
    end
  end
end

local function GetCachedAurasForUnit(unit)
  local destGUID = SafeUnitGUID(unit)
  if type(destGUID) ~= "string" then
    return {}
  end

  PruneCacheForGUID(destGUID)

  local cache = SafeCacheGet(destGUID)
  if not cache then
    return {}
  end

  EnrichCachedAuras(unit, cache)

  local auras = {}
  for _, aura in pairs(cache) do
    auras[#auras + 1] = aura
  end

  table.sort(auras, function(left, right)
    local leftExpiration = ns.Auras.SafeField(left, "expirationTime") or math.huge
    local rightExpiration = ns.Auras.SafeField(right, "expirationTime") or math.huge
    if leftExpiration == rightExpiration then
      return (ns.Auras.SafeField(left, "appliedAt") or 0) < (ns.Auras.SafeField(right, "appliedAt") or 0)
    end

    return leftExpiration < rightExpiration
  end)

  return auras
end

local function GetArenaFrame(index)
  return _G["ArenaEnemyFrame" .. index] or _G["ArenaEnemyFrame" .. index .. "UnitFrame"] or _G["CompactArenaFrameMember" .. index]
end

local function AddAuraContainer(containers, seen, frame)
  if frame and type(frame) == "table" and not seen[frame] then
    seen[frame] = true
    containers[#containers + 1] = frame
  end
end

local function GetAuraContainers(unitFrame)
  local containers = {}
  local seen = {}

  AddAuraContainer(containers, seen, unitFrame and unitFrame.AurasFrame)
  AddAuraContainer(containers, seen, unitFrame and unitFrame.BuffFrame)
  AddAuraContainer(containers, seen, unitFrame and unitFrame.DebuffFrame)
  AddAuraContainer(containers, seen, unitFrame and unitFrame.buffFrame)
  AddAuraContainer(containers, seen, unitFrame and unitFrame.debuffFrame)

  return containers
end

local function SetBlizzardAurasShown(unitFrame, shown)
  if not unitFrame or ns.Frames.IsForbidden(unitFrame) then
    return
  end

  for _, auraFrame in ipairs(GetAuraContainers(unitFrame)) do
    if shown then
      pcall(auraFrame.SetAlpha, auraFrame, 1)
      pcall(auraFrame.Show, auraFrame)
    else
      pcall(auraFrame.SetAlpha, auraFrame, 0)
      pcall(auraFrame.Hide, auraFrame)
    end
  end
end

local function AddAuraButton(buttons, seen, button)
  if type(button) ~= "table" or seen[button] then
    return
  end

  seen[button] = true
  buttons[#buttons + 1] = button
end

local function CollectAuraButtons(frame, buttons, depth)
  if not frame or depth > 5 or type(frame.GetChildren) ~= "function" then
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

local function AddKnownAuraButtons(unitFrame, auraFrame, buttons)
  if type(auraFrame) == "table" then
    for _, source in ipairs({ auraFrame.buffFrames, auraFrame.debuffFrames, auraFrame.auraFrames }) do
      if type(source) == "table" then
        for _, button in pairs(source) do
          AddAuraButton(buttons, buttons.seen, button)
        end
      end
    end
  end

  if type(unitFrame) == "table" then
    for _, source in ipairs({ unitFrame.buffFrames, unitFrame.debuffFrames, unitFrame.auraFrames }) do
      if type(source) == "table" then
        for _, button in pairs(source) do
          AddAuraButton(buttons, buttons.seen, button)
        end
      end
    end
  end
end

local function IsArenaDebuffButton(button)
  if type(button) ~= "table" then
    return false
  end

  local ok, isBuff = pcall(function()
    return button.isBuff
  end)
  if ok and isBuff == true then
    return false
  end

  local unitToken = ns.Auras.SafeField(button, "unitToken")
  local auraInstanceID = ns.Auras.SafeField(button, "auraInstanceID")
  local spellID = ns.Auras.SafeField(button, "spellID") or ns.Auras.SafeField(button, "spellId")
  local hasCooldown = ns.Auras.SafeField(button, "cooldown") or ns.Auras.SafeField(button, "Cooldown") or ns.Auras.SafeField(button, "CooldownFrame")
  local hasIcon = ns.Auras.SafeField(button, "Icon") or ns.Auras.SafeField(button, "icon")

  return type(unitToken) == "string" and type(hasCooldown) == "table" and hasIcon ~= nil
end

local function StyleArenaAuraButton(button, size, cooldownText)
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
    pcall(cooldown.SetHideCountdownNumbers, cooldown, not cooldownText)
  end
end

local function StyleArenaAuras(unitFrame)
  local settings = ns.GetSettings("arenaDebuffs")
  local auraFrame = unitFrame and unitFrame.AurasFrame
  if not auraFrame then
    return 0
  end

  local buttons = { seen = {} }
  AddKnownAuraButtons(unitFrame, auraFrame, buttons)
  CollectAuraButtons(auraFrame, buttons, 1)

  local styled = 0
  for _, button in ipairs(buttons) do
    if IsArenaDebuffButton(button) then
      StyleArenaAuraButton(button, settings.iconSize, settings.cooldownText)
      styled = styled + 1
    end
  end

  SetBlizzardAurasShown(unitFrame, true)
  return styled
end

local function RenderArenaAuras(unitFrame, unit)
  Trace("RenderArenaAuras disabled for cache test " .. tostring(unit))
end

local function ScheduleRenderArena(unitFrame, unit)
  Trace("ScheduleRenderArena disabled for cache test " .. tostring(unit))
end

function ArenaDebuffs:UpdateUnit(unit)
  Trace("UpdateUnit " .. tostring(unit))
end

function ArenaDebuffs:UpdateAll()
  Trace("UpdateAll disabled for cache test")
end

function ArenaDebuffs:OnLogin()
  Trace("OnLogin enabled=" .. tostring(ns.GetSettings("arenaDebuffs").enabled))
  if not ns.GetSettings("arenaDebuffs").enabled then
    Trace("OnLogin disabled")
    return
  end

  ns.RegisterEvent("arenaDebuffs", "COMBAT_LOG_EVENT_UNFILTERED")
  ns.RegisterEvent("arenaDebuffs", "PLAYER_ENTERING_WORLD")
end

function ArenaDebuffs:ApplySettings()
  Trace("ApplySettings")
end

function ArenaDebuffs:ARENA_OPPONENT_UPDATE(unit)
  Trace("ARENA_OPPONENT_UPDATE " .. tostring(unit))
  self:UpdateUnit(unit)
end

function ArenaDebuffs:PLAYER_ENTERING_WORLD()
  Trace("PLAYER_ENTERING_WORLD clear cache")
  ClearCache()
end

function ArenaDebuffs:PLAYER_REGEN_ENABLED()
  Trace("PLAYER_REGEN_ENABLED")
  if updateAfterCombat then
    updateAfterCombat = false
    self:UpdateAll()
  end
end

function ArenaDebuffs:UNIT_AURA(unit)
  Trace("UNIT_AURA " .. tostring(unit))
  self:UpdateUnit(unit)
end

function ArenaDebuffs:COMBAT_LOG_EVENT_UNFILTERED()
  if not CombatLogGetCurrentEventInfo then
    return
  end

  local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId, spellName, _, auraType, amount = CombatLogGetCurrentEventInfo()

  if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" and subevent ~= "SPELL_AURA_APPLIED_DOSE" and subevent ~= "SPELL_AURA_REMOVED" and subevent ~= "SPELL_AURA_REMOVED_DOSE" then
    return
  end

  cacheStats.seen = cacheStats.seen + 1
  Trace("CLEU " .. tostring(subevent) .. " " .. tostring(spellName) .. " " .. tostring(spellId))

  if auraType ~= "DEBUFF" then
    cacheStats.ignoredAuraType = cacheStats.ignoredAuraType + 1
    return
  end

  if not IsPlayerSource(sourceGUID) then
    cacheStats.ignoredSource = cacheStats.ignoredSource + 1
    return
  end

  if not IsTrackedCombatAura(spellId, spellName) then
    cacheStats.ignoredSpell = cacheStats.ignoredSpell + 1
    return
  end

  if subevent == "SPELL_AURA_REMOVED" then
    RemoveCombatAura(destGUID, spellId)
  else
    StoreCombatAura(destGUID, spellId, spellName, amount, sourceGUID)
  end

  self:UpdateAll()
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

local function DumpFrameInfo(lines, label, frame, depth)
  if depth > 3 then
    return
  end

  local indent = string.rep("  ", depth)
  AppendLine(lines, indent .. label .. ":")
  AppendLine(lines, indent .. "  name:", ns.Frames.SafeName(frame))
  AppendLine(lines, indent .. "  type:", type(frame))
  if type(frame) ~= "table" then
    return
  end

  local fields = {
    "isBuff",
    "layoutIndex",
    "auraInstanceID",
    "unitToken",
    "spellID",
    "spellId",
    "name",
  }

  for _, field in ipairs(fields) do
    local value = ns.Auras.SafeField(frame, field)
    if value ~= nil then
      AppendLine(lines, indent .. "  " .. field .. ":", ns.Auras.SafeText(value))
    end
  end

  local cooldown = ns.Auras.SafeField(frame, "cooldown") or ns.Auras.SafeField(frame, "Cooldown") or ns.Auras.SafeField(frame, "CooldownFrame")
  AppendLine(lines, indent .. "  hasCooldown:", tostring(cooldown ~= nil))
  AppendLine(lines, indent .. "  hasIcon:", tostring(ns.Auras.SafeField(frame, "Icon") ~= nil or ns.Auras.SafeField(frame, "icon") ~= nil))
  AppendLine(lines, indent .. "  cooldownType:", cooldown and type(cooldown) or "nil")

  if type(frame.GetChildren) ~= "function" then
    return
  end

  local children = { frame:GetChildren() }
  AppendLine(lines, indent .. "  children:", #children)
  for index, child in ipairs(children) do
    DumpFrameInfo(lines, "child " .. index, child, depth + 1)
  end
end

local function DescribeUnitAuras(lines, unit)
  AppendLine(lines, "== unit", unit, "==")
  AppendLine(lines, "UnitExists:", tostring(UnitExists(unit)))
  if not UnitExists(unit) then
    return
  end

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
    AppendLine(lines, "  harmful", auraIndex, "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"), "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"), "icon=", tostring(ns.Auras.HasIcon(aura)), "duration=", tostring(ns.Auras.HasDuration(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "deny=", tostring(ns.Auras.IsDenylisted(aura)), "restrictedFallback=", tostring(options.allowRestrictedAura), "match=", tostring(ns.Auras.Matches(aura, options)))
  end
  AppendLine(lines, "harmful scanned:", seen, "matched:", matched)
end

local function CountCachedAuras()
  local guidCount = 0
  local auraCount = 0

  for _, cache in pairs(auraCacheByGUID) do
    guidCount = guidCount + 1
    for _ in pairs(cache) do
      auraCount = auraCount + 1
    end
  end

  return guidCount, auraCount
end

local function DescribeCachedAuras(lines, unit)
  local destGUID = SafeUnitGUID(unit)
  AppendLine(lines, "cache GUID:", destGUID or "nil")
  if type(destGUID) ~= "string" then
    return
  end

  local auras = GetCachedAurasForUnit(unit)
  AppendLine(lines, "cached matched auras:", #auras)
  for index, aura in ipairs(auras) do
    AppendLine(
      lines,
      "  cached",
      index,
      "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"),
      "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"),
      "duration=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "duration") or "nil"),
      "expiration=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "expirationTime") or "nil"),
      "applications=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "applications") or "nil")
    )
  end
end

function ArenaDebuffs:Debug()
  self:ApplySettings()

  local settings = ns.GetSettings("arenaDebuffs")
  local cacheGUIDs, cachedAuras = CountCachedAuras()
  local lines = {
    ns.displayName .. " arena debug",
    "enabled: " .. tostring(settings.enabled),
    "iconSize: " .. tostring(settings.iconSize),
    "maxIcons: " .. tostring(settings.maxIcons),
    "onlyPlayer: " .. tostring(settings.onlyPlayer),
    "dots category: " .. tostring(ns.GetCategories().dots),
    "utility category: " .. tostring(ns.GetCategories().utility),
    "cache GUIDs: " .. tostring(cacheGUIDs),
    "cached auras: " .. tostring(cachedAuras),
    "combat log seen: " .. tostring(cacheStats.seen),
    "combat log tracked: " .. tostring(cacheStats.tracked),
    "combat log removed: " .. tostring(cacheStats.removed),
    "restricted GUID keys: " .. tostring(cacheStats.restrictedGUID),
    "combat log ignored source: " .. tostring(cacheStats.ignoredSource),
    "combat log ignored aura type: " .. tostring(cacheStats.ignoredAuraType),
    "combat log ignored spell: " .. tostring(cacheStats.ignoredSpell),
    "trace:",
  }

  for _, entry in ipairs(traceLog) do
    lines[#lines + 1] = "  " .. entry
  end

  for index = 1, 5 do
    local unit = "arena" .. index
    local frame = GetArenaFrame(index)
    AppendLine(lines, "== arena frame", index, "==")
    AppendLine(lines, "frame:", ns.Frames.SafeName(frame))
    AppendLine(lines, "frame type:", type(frame))
    AppendLine(lines, "unit:", unit)
    AppendLine(lines, "UnitExists:", tostring(UnitExists(unit)))
    if UnitExists(unit) then
      AppendLine(lines, "UnitCanAttack:", tostring(UnitCanAttack and UnitCanAttack("player", unit)))
      DescribeCachedAuras(lines, unit)
      DumpFrameInfo(lines, "frame tree", frame, 0)
      DumpFrameInfo(lines, "auras tree", frame and frame.AurasFrame, 0)
    end
  end

  DescribeUnitAuras(lines, "target")
  DescribeUnitAuras(lines, "focus")
  DescribeUnitAuras(lines, "mouseover")

  error(DebugOutput(lines), 0)
end

ns.RegisterModule("arenaDebuffs", ArenaDebuffs)
