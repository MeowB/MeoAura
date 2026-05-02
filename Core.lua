local ADDON_NAME, ns = ...

ns.name = "MeoAura"
ns.displayName = "Meo Aura"
ns.modules = {}

MeoAura = ns

local addonFrame = CreateFrame("Frame")
ns.frame = addonFrame

local DEFAULTS = {
  categories = {
    hots = true,
    dots = true,
    externals = true,
    utility = true,
  },
  raidHots = {
    enabled = true,
    iconSize = 24,
    maxIcons = 5,
    cooldownText = false,
  },
  arenaDebuffs = {
    enabled = false,
    iconSize = 24,
    maxIcons = 5,
    onlyPlayer = true,
    cooldownText = false,
  },
  nameplateDebuffs = {
    enabled = false,
    iconSize = 24,
    maxIcons = 8,
    onlyPlayer = true,
    cooldownText = false,
  },
}

local function CopyDefaults(source, target)
  for key, value in pairs(source) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      CopyDefaults(value, target[key])
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

function ns.GetSettings(moduleKey)
  return MeoAuraDB and MeoAuraDB[moduleKey] or DEFAULTS[moduleKey]
end

function ns.GetCategories()
  return MeoAuraDB and MeoAuraDB.categories or DEFAULTS.categories
end

function ns.GetEnabledCategories(categoryList)
  local settings = ns.GetCategories()
  local enabled = {}

  for _, category in ipairs(categoryList) do
    if settings[category] then
      enabled[#enabled + 1] = category
    end
  end

  return enabled
end

function ns.RegisterModule(moduleKey, module)
  ns.modules[moduleKey] = module
end

function ns.RegisterEvent(event)
  addonFrame:RegisterEvent(event)
end

function ns.ApplySettings()
  for _, module in pairs(ns.modules) do
    if type(module.ApplySettings) == "function" then
      module:ApplySettings()
    end
  end
end

local function Dispatch(event, ...)
  for _, module in pairs(ns.modules) do
    local handler = module[event]
    if type(handler) == "function" then
      handler(module, ...)
    end
  end
end

local function SetModuleEnabled(moduleKey, enabled)
  local settings = ns.GetSettings(moduleKey)
  if settings then
    settings.enabled = enabled
  end
  ns.ApplySettings()
end

local function SetModuleIconSize(moduleKey, size)
  local settings = ns.GetSettings(moduleKey)
  if not settings or not size then
    return false
  end

  settings.iconSize = math.max(12, math.min(64, size))
  ns.ApplySettings()
  return true
end

local function SetModuleIconCount(moduleKey, count)
  local settings = ns.GetSettings(moduleKey)
  if not settings or not count then
    return false
  end

  settings.maxIcons = math.max(1, math.min(20, count))
  ns.ApplySettings()
  return true
end

local function SetModuleCooldownText(moduleKey, enabled)
  local settings = ns.GetSettings(moduleKey)
  if not settings then
    return false
  end

  settings.cooldownText = enabled
  ns.ApplySettings()
  return true
end

function ns.PrintSettings()
  print(ns.displayName .. " Settings")
  print("  categories: hots=" .. tostring(ns.GetCategories().hots) .. ", dots=" .. tostring(ns.GetCategories().dots) .. ", externals=" .. tostring(ns.GetCategories().externals) .. ", utility=" .. tostring(ns.GetCategories().utility))
  print("  raid hots: " .. tostring(ns.GetSettings("raidHots").enabled) .. ", size " .. tostring(ns.GetSettings("raidHots").iconSize) .. ", count " .. tostring(ns.GetSettings("raidHots").maxIcons) .. ", cooldown text " .. tostring(ns.GetSettings("raidHots").cooldownText))
  print("  arena debuffs: " .. tostring(ns.GetSettings("arenaDebuffs").enabled) .. ", size " .. tostring(ns.GetSettings("arenaDebuffs").iconSize) .. ", count " .. tostring(ns.GetSettings("arenaDebuffs").maxIcons) .. ", cooldown text " .. tostring(ns.GetSettings("arenaDebuffs").cooldownText))
  print("  nameplate debuffs: " .. tostring(ns.GetSettings("nameplateDebuffs").enabled) .. ", size " .. tostring(ns.GetSettings("nameplateDebuffs").iconSize) .. ", count " .. tostring(ns.GetSettings("nameplateDebuffs").maxIcons) .. ", cooldown text " .. tostring(ns.GetSettings("nameplateDebuffs").cooldownText))
end

local function HandleSlash(input)
  local command, rest = string.match(string.lower(input or ""), "^(%S*)%s*(.-)$")

  if command == "debug" then
    if rest == "nameplate" or rest == "plates" then
      if ns.NameplateDebuffs and ns.NameplateDebuffs.Debug then
        ns.NameplateDebuffs:Debug()
      end
      return
    elseif rest == "arena" then
      if ns.ArenaDebuffs and ns.ArenaDebuffs.Debug then
        ns.ArenaDebuffs:Debug()
      end
      return
    elseif ns.RaidHots and ns.RaidHots.Debug then
      ns.RaidHots:Debug()
      return
    end
  elseif command == "raid" then
    local size = tonumber(string.match(rest, "^size%s+(%d+)$"))
    if size then
      SetModuleIconSize("raidHots", size)
    elseif rest == "text on" then
      SetModuleCooldownText("raidHots", true)
    elseif rest == "text off" then
      SetModuleCooldownText("raidHots", false)
    else
      SetModuleEnabled("raidHots", rest ~= "off")
    end
  elseif command == "arena" then
    local size = tonumber(string.match(rest, "^size%s+(%d+)$"))
    if size then
      SetModuleIconSize("arenaDebuffs", size)
    elseif rest == "text on" then
      SetModuleCooldownText("arenaDebuffs", true)
    elseif rest == "text off" then
      SetModuleCooldownText("arenaDebuffs", false)
    else
      SetModuleEnabled("arenaDebuffs", rest == "on")
    end
  elseif command == "nameplate" or command == "plates" then
    local size = tonumber(string.match(rest, "^size%s+(%d+)$"))
    local count = tonumber(string.match(rest, "^count%s+(%d+)$"))
    if size then
      SetModuleIconSize("nameplateDebuffs", size)
    elseif count then
      SetModuleIconCount("nameplateDebuffs", count)
    elseif rest == "text on" then
      SetModuleCooldownText("nameplateDebuffs", true)
    elseif rest == "text off" then
      SetModuleCooldownText("nameplateDebuffs", false)
    elseif rest == "test" then
      if ns.NameplateDebuffs and ns.NameplateDebuffs.ShowTestIcons then
        ns.NameplateDebuffs:ShowTestIcons()
      end
    elseif rest == "all" then
      ns.GetSettings("nameplateDebuffs").onlyPlayer = false
      ns.ApplySettings()
    elseif rest == "player" then
      ns.GetSettings("nameplateDebuffs").onlyPlayer = true
      ns.ApplySettings()
    else
      SetModuleEnabled("nameplateDebuffs", rest == "on")
    end
  elseif command == "status" then
    ns.PrintSettings()
    return
  elseif command == "category" then
    local category, state = string.match(rest, "^(%S+)%s+(%S+)$")
    if category and ns.GetCategories()[category] ~= nil then
      ns.GetCategories()[category] = state ~= "off"
      ns.ApplySettings()
    end
  else
    if ns.Config and ns.Config.Open then
      ns.Config:Open()
    end
    return
  end
end

local function OnLogin()
  MeoAuraDB = MeoAuraDB or {}
  CopyDefaults(DEFAULTS, MeoAuraDB)

  if ns.Config and ns.Config.Create then
    ns.Config:Create()
  end

  for _, module in pairs(ns.modules) do
    if type(module.OnLogin) == "function" then
      module:OnLogin()
    end
  end

  ns.ApplySettings()
  print("MeoAura loaded")
end

addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    OnLogin()
  else
    Dispatch(event, ...)
  end
end)

SLASH_MEOAURA1 = "/meoaura"
SLASH_MEOAURA2 = "/meo"
SLASH_MEOAURA3 = "/mrh"
SlashCmdList["MEOAURA"] = HandleSlash
