local _, ns = ...

local ArenaDebuffs = {}
ns.ArenaDebuffs = ArenaDebuffs

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

local function GetOptions()
  local settings = ns.GetSettings("arenaDebuffs")
  return {
    filter = "HARMFUL",
    categories = ns.GetEnabledCategories({ "dots", "utility" }),
    onlyPlayer = settings.onlyPlayer,
    iconSize = settings.iconSize,
    maxIcons = settings.maxIcons,
    maxScan = 40,
    point = "TOPRIGHT",
    relativePoint = "TOPRIGHT",
    growth = "LEFT",
    x = -1,
    y = 1,
  }
end

local function GetArenaFrame(index)
  return _G["ArenaEnemyFrame" .. index] or _G["ArenaEnemyFrame" .. index .. "UnitFrame"] or _G["CompactArenaFrameMember" .. index]
end

local function StyleArenaAuras(unitFrame)
  if not unitFrame or ns.Frames.IsForbidden(unitFrame) then
    return
  end

  local settings = ns.GetSettings("arenaDebuffs")
  if not settings.enabled then
    ns.Frames.Clear("arenaDebuffs", unitFrame)
    return
  end

  local size = settings.iconSize
  local maxIcons = settings.maxIcons
  local spacing = 0
  local anchor = unitFrame.healthBar or unitFrame
  local auraFrame = unitFrame.AurasFrame or unitFrame

  ns.Frames.Clear("arenaDebuffs", unitFrame)

  pcall(auraFrame.SetAlpha, auraFrame, 1)
  pcall(auraFrame.Show, auraFrame)
  pcall(auraFrame.ClearAllPoints, auraFrame)
  pcall(auraFrame.SetPoint, auraFrame, "TOPRIGHT", anchor, "TOPRIGHT", -1, 1)
  pcall(auraFrame.SetSize, auraFrame, maxIcons * size, size)
  pcall(auraFrame.SetFrameLevel, auraFrame, (type(unitFrame.GetFrameLevel) == "function" and unitFrame:GetFrameLevel() or 0) + 100)
  pcall(auraFrame.SetFrameStrata, auraFrame, "HIGH")

  local buttons = { seen = {} }
  AddAuraButtonTable(buttons, unitFrame.buffFrames)
  AddAuraButtonTable(buttons, unitFrame.debuffFrames)
  AddAuraButtonTable(buttons, unitFrame.auraFrames)
  AddAuraButtonTable(buttons, auraFrame.buffFrames)
  AddAuraButtonTable(buttons, auraFrame.debuffFrames)
  AddAuraButtonTable(buttons, auraFrame.auraFrames)
  CollectAuraButtons(auraFrame, buttons, 1)

  local styled = 0
  for _, child in ipairs(buttons) do
    local okShown, shown = false, false
    if child and type(child.IsShown) == "function" then
      okShown, shown = pcall(child.IsShown, child)
    end

    if child and okShown and shown == true then
      styled = styled + 1
      ConfigureAuraButton(child, size)
      pcall(child.ClearAllPoints, child)
      pcall(child.SetPoint, child, "TOPRIGHT", auraFrame, "TOPRIGHT", -((styled - 1) * (size + spacing)), 0)

      if styled > maxIcons then
        pcall(child.Hide, child)
      end
    end
  end
end

local function ScheduleStyleArena(unitFrame)
  StyleArenaAuras(unitFrame)
  C_Timer.After(0, function()
    StyleArenaAuras(unitFrame)
  end)
  C_Timer.After(0.05, function()
    StyleArenaAuras(unitFrame)
  end)
  C_Timer.After(0.15, function()
    StyleArenaAuras(unitFrame)
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
    return
  end

  ScheduleStyleArena(unitFrame)
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
    AppendLine(lines, "  harmful", auraIndex, "name=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "name") or "nil"), "spellId=", ns.Auras.SafeText(ns.Auras.SafeField(aura, "spellId") or "nil"), "icon=", tostring(ns.Auras.HasIcon(aura)), "duration=", tostring(ns.Auras.HasDuration(aura)), "player=", tostring(ns.Auras.IsPlayerAura(aura)), "deny=", tostring(ns.Auras.IsDenylisted(aura)), "restrictedFallback=", tostring(options.allowRestrictedPlayerAura and ns.Auras.IsPlayerAura(aura)), "match=", tostring(ns.Auras.Matches(aura, options)))
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
    end
  end

  DescribeUnitAuras(lines, "target")
  DescribeUnitAuras(lines, "focus")
  DescribeUnitAuras(lines, "mouseover")

  error(DebugOutput(lines), 0)
end

ns.RegisterModule("arenaDebuffs", ArenaDebuffs)
