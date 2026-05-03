local _, ns = ...

local RaidHots = {}
ns.RaidHots = RaidHots

local updateQueued = false
local MIN_RAID_ICON_SIZE = 22

local function GetOptions()
  local settings = ns.GetSettings("raidHots")
  return {
    filter = "HELPFUL",
    categories = ns.GetEnabledCategories({ "hots", "externals", "utility" }),
    onlyPlayer = true,
    requirePlayerSource = true,
    iconSize = math.max(settings.iconSize, MIN_RAID_ICON_SIZE),
    maxIcons = settings.maxIcons,
    maxScan = 40,
    cooldownText = settings.cooldownText,
    captureMouse = true,
    tooltips = settings.tooltips,
    point = "BOTTOMRIGHT",
    growth = "LEFT",
    x = -1,
    y = 1,
  }
end

function RaidHots:UpdateFrame(unitFrame)
  if not ns.GetSettings("raidHots").enabled then
    return
  end

  if not ns.Frames.IsCompactGroupFrame(unitFrame) then
    return
  end

  ns.Frames.RenderAuras("raidHots", unitFrame, ns.Frames.GetUnit(unitFrame), GetOptions())
end

function RaidHots:UpdateAll()
  ns.Frames.ForEachCompactGroupFrame(function(unitFrame)
    self:UpdateFrame(unitFrame)
  end)
end

function RaidHots:QueueUpdateAll()
  if updateQueued then
    return
  end

  updateQueued = true
  C_Timer.After(0, function()
    updateQueued = false
    self:UpdateAll()
  end)
end

function RaidHots:OnLogin()
  if not ns.GetSettings("raidHots").enabled then
    return
  end

  if type(CompactUnitFrame_UpdateAuras) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateAuras", function(unitFrame)
      self:UpdateFrame(unitFrame)
    end)
  end

  if type(CompactUnitFrame_UpdateAll) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateAll", function(unitFrame)
      self:UpdateFrame(unitFrame)
    end)
  end

  if type(CompactUnitFrame_SetUnit) == "function" then
    hooksecurefunc("CompactUnitFrame_SetUnit", function(unitFrame)
      self:UpdateFrame(unitFrame)
    end)
  end

  ns.RegisterEvent("raidHots", "GROUP_ROSTER_UPDATE")
  ns.RegisterEvent("raidHots", "UNIT_AURA")
  self:UpdateAll()
end

function RaidHots:ApplySettings()
  if not ns.GetSettings("raidHots").enabled then
    return
  end

  self:UpdateAll()
end

function RaidHots:GROUP_ROSTER_UPDATE()
  if not ns.GetSettings("raidHots").enabled then
    return
  end

  self:QueueUpdateAll()
end

function RaidHots:UNIT_AURA(unit)
  if not ns.GetSettings("raidHots").enabled then
    return
  end

  ns.Frames.ForEachCompactGroupFrame(function(unitFrame)
    if unit == ns.Frames.GetUnit(unitFrame) then
      self:UpdateFrame(unitFrame)
    end
  end)
end

local function AppendLine(lines, ...)
  local parts = {}
  for index = 1, select("#", ...) do
    parts[index] = tostring(select(index, ...))
  end

  lines[#lines + 1] = table.concat(parts, " ")
end

function RaidHots:Debug()
  self:UpdateAll()

  local settings = ns.GetSettings("raidHots")
  local lines = {
    ns.displayName .. " raid hots debug",
    "enabled: " .. tostring(settings.enabled),
    "iconSize: " .. tostring(settings.iconSize),
    "maxIcons: " .. tostring(settings.maxIcons),
    "tooltips: " .. tostring(settings.tooltips),
  }

  for _, frameName in ipairs({ "CompactPartyFrameMember1", "CompactPartyFrameMember2", "CompactRaidFrame1" }) do
    local unitFrame = _G[frameName]
    AppendLine(lines, "==", frameName, "==")
    if unitFrame then
      AppendLine(lines, "name:", ns.Frames.SafeName(unitFrame))
      AppendLine(lines, "unit:", unitFrame.unit or "nil")
      AppendLine(lines, "displayedUnit:", unitFrame.displayedUnit or "nil")
    else
      AppendLine(lines, "not found")
    end
  end

  error(table.concat(lines, "\n"), 0)
end

ns.RegisterModule("raidHots", RaidHots)
