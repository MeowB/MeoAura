local _, ns = ...

local ArenaDebuffs = {}
ns.ArenaDebuffs = ArenaDebuffs

local function GetOptions()
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
    allowRestrictedAura = true,
    point = "TOPRIGHT",
    relativePoint = "TOPRIGHT",
    growth = "LEFT",
    x = -1,
    y = 1,
    backingAlpha = 0.75,
    anchorFrame = function(unitFrame)
      return unitFrame.healthBar or unitFrame
    end,
  }
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
  if not ns.GetSettings("arenaDebuffs").enabled then
    ns.Frames.Clear("arenaDebuffs", unitFrame)
    SetBlizzardAurasShown(unitFrame, true)
    return
  end

  ns.Frames.Clear("arenaDebuffs", unitFrame)
  StyleArenaAuras(unitFrame)
end

local function ScheduleRenderArena(unitFrame, unit)
  RenderArenaAuras(unitFrame, unit)
  C_Timer.After(0, function()
    RenderArenaAuras(unitFrame, unit)
  end)
  C_Timer.After(0.05, function()
    RenderArenaAuras(unitFrame, unit)
  end)
  C_Timer.After(0.15, function()
    RenderArenaAuras(unitFrame, unit)
  end)
end

function ArenaDebuffs:UpdateUnit(unit)
  if not unit or not string.match(unit, "^arena%d+$") then
    return
  end

  local index = tonumber(string.match(unit, "^arena(%d+)$"))
  local unitFrame = index and GetArenaFrame(index)
  if not unitFrame then
    return
  end

  if not ns.GetSettings("arenaDebuffs").enabled then
    ns.Frames.Clear("arenaDebuffs", unitFrame)
    SetBlizzardAurasShown(unitFrame, true)
    return
  end

  ScheduleRenderArena(unitFrame, unit)
end

function ArenaDebuffs:UpdateAll()
  for index = 1, 5 do
    self:UpdateUnit("arena" .. index)
  end
end

function ArenaDebuffs:OnLogin()
  ns.RegisterEvent("ARENA_OPPONENT_UPDATE")
  ns.RegisterEvent("PLAYER_ENTERING_WORLD")
  ns.RegisterEvent("UNIT_AURA")
  self:UpdateAll()
end

function ArenaDebuffs:ApplySettings()
  self:UpdateAll()
end

function ArenaDebuffs:ARENA_OPPONENT_UPDATE(unit)
  self:UpdateUnit(unit)
end

function ArenaDebuffs:PLAYER_ENTERING_WORLD()
  self:UpdateAll()
end

function ArenaDebuffs:UNIT_AURA(unit)
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

function ArenaDebuffs:Debug()
  self:ApplySettings()

  local settings = ns.GetSettings("arenaDebuffs")
  local lines = {
    ns.displayName .. " arena debug",
    "enabled: " .. tostring(settings.enabled),
    "iconSize: " .. tostring(settings.iconSize),
    "maxIcons: " .. tostring(settings.maxIcons),
    "onlyPlayer: " .. tostring(settings.onlyPlayer),
    "dots category: " .. tostring(ns.GetCategories().dots),
    "utility category: " .. tostring(ns.GetCategories().utility),
  }

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
