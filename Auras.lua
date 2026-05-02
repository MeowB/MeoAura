local _, ns = ...

local Auras = {}
ns.Auras = Auras

local TRACKED_AURAS = {
  hots = {
    names = {
      ["Rejuvenation"] = true,
      ["Germination"] = true,
      ["Rejuvenation (Germination)"] = true,
      ["Regrowth"] = true,
      ["Lifebloom"] = true,
      ["Wild Growth"] = true,
      ["Cenarion Ward"] = true,
      ["Renewing Mist"] = true,
      ["Enveloping Mist"] = true,
      ["Essence Font"] = true,
      ["Renew"] = true,
      ["Atonement"] = true,
      ["Prayer of Mending"] = true,
      ["Riptide"] = true,
      ["Earthliving"] = true,
      ["Reversion"] = true,
      ["Dream Breath"] = true,
      ["Echo"] = true,
    },
    spellIds = {
      [774] = true,
      [8936] = true,
      [33763] = true,
      [48438] = true,
      [155777] = true,
      [102351] = true,
      [119611] = true,
      [124682] = true,
      [191840] = true,
      [139] = true,
      [194384] = true,
      [33076] = true,
      [61295] = true,
      [51945] = true,
      [366155] = true,
      [355941] = true,
      [364343] = true,
    },
  },
  dots = {
    names = {
      ["Moonfire"] = true,
      ["Sunfire"] = true,
      ["Stellar Flare"] = true,
      ["Rip"] = true,
      ["Rake"] = true,
      ["Thrash"] = true,
      ["Shadow Word: Pain"] = true,
      ["Vampiric Touch"] = true,
      ["Devouring Plague"] = true,
      ["Purge the Wicked"] = true,
      ["Flame Shock"] = true,
      ["Corruption"] = true,
      ["Agony"] = true,
      ["Unstable Affliction"] = true,
      ["Immolate"] = true,
      ["Serpent Sting"] = true,
    },
    spellIds = {
      [164812] = true,
      [164815] = true,
      [202347] = true,
      [1079] = true,
      [155722] = true,
      [106830] = true,
      [589] = true,
      [34914] = true,
      [335467] = true,
      [204213] = true,
      [188389] = true,
      [172] = true,
      [980] = true,
      [316099] = true,
      [348] = true,
      [271788] = true,
    },
  },
  externals = {
    names = {
      ["Ironbark"] = true,
      ["Pain Suppression"] = true,
      ["Guardian Spirit"] = true,
      ["Blessing of Sacrifice"] = true,
      ["Blessing of Protection"] = true,
      ["Blessing of Spellwarding"] = true,
      ["Life Cocoon"] = true,
      ["Time Dilation"] = true,
      ["Blessing of Freedom"] = true,
    },
    spellIds = {
      [102342] = true,
      [33206] = true,
      [47788] = true,
      [6940] = true,
      [1022] = true,
      [204018] = true,
      [116849] = true,
      [357170] = true,
      [1044] = true,
    },
  },
  utility = {
    names = {
      ["Stampeding Roar"] = true,
      ["Tiger's Lust"] = true,
      ["Wind Rush Totem"] = true,
      ["Blessing of Freedom"] = true,
      ["Freedom of the Herd"] = true,
      ["Twin Guardian"] = true,
      ["Sphere of Despair"] = true,
    },
    spellIds = {
      [106898] = true,
      [116841] = true,
      [192082] = true,
      [1044] = true,
      [288790] = true,
      [370889] = true,
      [411038] = true,
      [411039] = true,
    },
  },
}

local DENYLISTED_AURAS = {
  names = {
    -- Persistent/passive class debuffs that are usually noise in aura tracking.
    ["Chaos Brand"] = true,
    ["Mystic Touch"] = true,
    ["Skyfury"] = true,
    ["Weakened Armor"] = true,
  },
  spellIds = {
    [1490] = true, -- Chaos Brand
    [8647] = true, -- Mystic Touch
    [113746] = true, -- Mystic Touch
    [462854] = true, -- Skyfury
  },
}

function Auras.SafeField(aura, field)
  if type(aura) ~= "table" then
    return nil
  end

  local ok, value = pcall(function()
    return aura[field]
  end)

  if ok then
    return value
  end
end

function Auras.SafeText(value)
  local ok, text = pcall(tostring, value)
  if ok then
    return text
  end

  return "restricted"
end

function Auras.IsPlayerAura(aura)
  if Auras.SafeField(aura, "isFromPlayerOrPlayerPet") == true then
    return true
  end

  return Auras.HasPlayerSource(aura)
end

function Auras.HasPlayerSource(aura)
  local source = Auras.SafeField(aura, "sourceUnit") or Auras.SafeField(aura, "source")
  local ok, isPlayer = pcall(function()
    return source == "player" or source == "pet" or source == "vehicle"
  end)

  return ok and isPlayer
end

function Auras.HasPlayerGUIDSource(aura)
  local sourceGUID = Auras.SafeField(aura, "sourceGUID")
  local playerGUID = UnitGUID and UnitGUID("player")
  if type(sourceGUID) == "string" and type(playerGUID) == "string" and sourceGUID == playerGUID then
    return true
  end

  return Auras.HasPlayerSource(aura) and sourceGUID == nil
end

function Auras.HasDuration(aura)
  local duration = Auras.SafeField(aura, "duration")
  local expirationTime = Auras.SafeField(aura, "expirationTime")
  local ok, hasDuration = pcall(function()
    return type(duration) == "number" and duration > 0 and type(expirationTime) == "number"
  end)

  return ok and hasDuration
end

function Auras.GetIcon(aura)
  return Auras.SafeField(aura, "icon") or Auras.SafeField(aura, "iconFileID") or Auras.SafeField(aura, "texture")
end

function Auras.HasIcon(aura)
  local ok, hasIcon = pcall(function()
    return Auras.GetIcon(aura) ~= nil
  end)

  return ok and hasIcon
end

local function IsTrackedByCategory(aura, category)
  local tracked = TRACKED_AURAS[category]
  if not tracked then
    return false
  end

  local name = Auras.SafeField(aura, "name")
  local spellId = Auras.SafeField(aura, "spellId")
  local ok, matched = pcall(function()
    return (type(name) == "string" and tracked.names[name] == true) or tracked.spellIds[spellId] == true
  end)

  return ok and matched
end

function Auras.IsDenylisted(aura)
  local name = Auras.SafeField(aura, "name")
  local spellId = Auras.SafeField(aura, "spellId")
  local ok, denied = pcall(function()
    return (type(name) == "string" and DENYLISTED_AURAS.names[name] == true) or DENYLISTED_AURAS.spellIds[spellId] == true
  end)

  return ok and denied
end

function Auras.IsTrackedAura(aura, categories)
  if type(categories) == "string" then
    return IsTrackedByCategory(aura, categories)
  end

  if type(categories) == "table" then
    for _, category in ipairs(categories) do
      if IsTrackedByCategory(aura, category) then
        return true
      end
    end
  end

  return false
end

function Auras.IsTrackedHot(aura)
  return Auras.IsTrackedAura(aura, "hots")
end

local function GetReadFilter(filter, options)
  local readFilter = filter

  if options and options.onlyPlayer then
    if filter == "HARMFUL" then
      readFilter = "HARMFUL|PLAYER"
    elseif filter == "HELPFUL" then
      readFilter = "HELPFUL|PLAYER"
    end
  end

  if options and options.includeNameplateOnly then
    readFilter = readFilter .. "|INCLUDE_NAME_PLATE_ONLY"
  end

  return readFilter
end

function Auras.ReadLegacy(unit, index, filter, options)
  local reader = filter == "HARMFUL" and UnitDebuff or UnitBuff
  if reader then
    local name, icon, applications, _, duration, expirationTime, source = reader(unit, index, GetReadFilter(filter, options))
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

local function ReadModern(unit, index, filter, options)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    return C_UnitAuras.GetAuraDataByIndex(unit, index, GetReadFilter(filter, options))
  end
end

local function CopyModernField(target, source, field)
  if Auras.SafeField(target, field) == nil then
    local value = Auras.SafeField(source, field)
    if value ~= nil then
      target[field] = value
    end
  end
end

local function MergeAuraData(primary, secondary)
  if type(primary) ~= "table" or type(secondary) ~= "table" then
    return primary
  end

  CopyModernField(primary, secondary, "name")
  CopyModernField(primary, secondary, "spellId")
  CopyModernField(primary, secondary, "duration")
  CopyModernField(primary, secondary, "expirationTime")
  CopyModernField(primary, secondary, "applications")
  CopyModernField(primary, secondary, "count")
  CopyModernField(primary, secondary, "sourceUnit")
  CopyModernField(primary, secondary, "source")
  CopyModernField(primary, secondary, "sourceGUID")
  CopyModernField(primary, secondary, "isFromPlayerOrPlayerPet")
  CopyModernField(primary, secondary, "auraInstanceID")

  return primary
end

function Auras.Read(unit, index, filter, options)
  if options and options.preferLegacy then
    local legacyAura = Auras.ReadLegacy(unit, index, filter, options)
    if legacyAura then
      return MergeAuraData(legacyAura, ReadModern(unit, index, filter, options))
    end
  end

  local aura = ReadModern(unit, index, filter, options)

  if aura and Auras.HasIcon(aura) then
    return aura
  end

  return Auras.ReadLegacy(unit, index, filter, options) or aura
end

function Auras.Matches(aura, options)
  if not Auras.GetIcon(aura) then
    return false
  end

  if Auras.IsDenylisted(aura) then
    return false
  end

  if options.requireDuration ~= false and not Auras.HasDuration(aura) then
    return false
  end

  if options.onlyPlayer and options.requirePlayerGUID and not Auras.HasPlayerGUIDSource(aura) then
    return false
  end

  if options.onlyPlayer and options.requirePlayerSource and not Auras.HasPlayerSource(aura) then
    return false
  end

  if options.onlyPlayer and not options.requirePlayerSource and not Auras.IsPlayerAura(aura) then
    return false
  end

  if options.categories then
    if Auras.IsTrackedAura(aura, options.categories) then
      return true
    end

    if options.allowRestrictedAura then
      return true
    end

    return false
  end

  if options.kind == "hot" then
    return Auras.IsTrackedHot(aura)
  end

  return true
end
