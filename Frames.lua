local _, ns = ...

local Frames = {}
ns.Frames = Frames

local OVERLAYS = setmetatable({}, { __mode = "k" })
local BACKINGS = setmetatable({}, { __mode = "k" })

local FRAME_PREFIXES = {
  CompactPartyFrameMember = true,
  CompactRaidFrame = true,
}

function Frames.SafeName(value)
  if type(value) ~= "table" or type(value.GetName) ~= "function" then
    return "no name"
  end

  local ok, name = pcall(value.GetName, value)
  if ok and name then
    return name
  end

  return "no name"
end

function Frames.GetUnit(unitFrame)
  if not unitFrame then
    return nil
  end

  local ok, unit = pcall(function()
    return unitFrame.displayedUnit or unitFrame.unit
  end)

  if ok then
    return unit
  end
end

function Frames.IsForbidden(unitFrame)
  if not unitFrame or type(unitFrame.IsForbidden) ~= "function" then
    return false
  end

  local ok, forbidden = pcall(unitFrame.IsForbidden, unitFrame)
  return ok and forbidden == true
end

function Frames.IsCompactGroupFrame(unitFrame)
  if not unitFrame or type(unitFrame.GetName) ~= "function" then
    return false
  end

  local name = Frames.SafeName(unitFrame)
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

function Frames.ForEachCompactGroupFrame(callback)
  for index = 1, 5 do
    callback(_G["CompactPartyFrameMember" .. index])
  end

  for index = 1, 40 do
    callback(_G["CompactRaidFrame" .. index])
  end
end

local function Raise(unitFrame, button)
  local parentLevel = type(unitFrame.GetFrameLevel) == "function" and unitFrame:GetFrameLevel() or 0
  local healthBar = unitFrame.healthBar
  local healthBarLevel = healthBar and type(healthBar.GetFrameLevel) == "function" and healthBar:GetFrameLevel() or 0

  button:SetFrameLevel(math.max(parentLevel, healthBarLevel) + 100)

  if type(button.SetFrameStrata) == "function" then
    button:SetFrameStrata("HIGH")
  end

  if button.cooldown and type(button.cooldown.SetFrameLevel) == "function" then
    button.cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
  end
end

local function GetStore(store, moduleKey, unitFrame)
  local moduleStore = store[moduleKey]
  if not moduleStore then
    moduleStore = setmetatable({}, { __mode = "k" })
    store[moduleKey] = moduleStore
  end

  return moduleStore[unitFrame], moduleStore
end

local function EnsureBacking(moduleKey, unitFrame, config)
  local backing, store = GetStore(BACKINGS, moduleKey, unitFrame)
  local size = config.iconSize
  local anchor = config.anchorFrame and config.anchorFrame(unitFrame) or unitFrame.healthBar or unitFrame

  if not backing then
    backing = CreateFrame("Frame", nil, unitFrame)
    backing.texture = backing:CreateTexture(nil, "BACKGROUND")
    backing.texture:SetAllPoints(backing)
    store[unitFrame] = backing
  end

  backing:ClearAllPoints()
  backing:SetPoint(config.point or "BOTTOMRIGHT", anchor, config.relativePoint or config.point or "BOTTOMRIGHT", config.x or 0, config.y or 0)
  backing:SetSize(config.maxIcons * size + 2, size + 2)
  backing:SetFrameLevel((type(unitFrame.GetFrameLevel) == "function" and unitFrame:GetFrameLevel() or 0) + 90)
  backing:SetFrameStrata("HIGH")
  backing.texture:SetColorTexture(0, 0, 0, config.backingAlpha or 0.85)

  return backing
end

local function ConfigureButton(unitFrame, button, index, config)
  local size = config.iconSize
  local spacing = config.spacing or 0
  local anchor = config.anchorFrame and config.anchorFrame(unitFrame) or unitFrame.healthBar or unitFrame

  button:SetSize(size, size)
  Raise(unitFrame, button)

  local growth = config.growth or "LEFT"
  local xOffset = (config.x or 0)
  local yOffset = (config.y or 0)
  if growth == "LEFT" then
    xOffset = xOffset - (index - 1) * (size + spacing)
  elseif growth == "RIGHT" then
    xOffset = xOffset + (index - 1) * (size + spacing)
  end

  button:ClearAllPoints()
  button:SetPoint(config.point or "BOTTOMRIGHT", anchor, config.relativePoint or config.point or "BOTTOMRIGHT", xOffset, yOffset)

  if button.cooldown and type(button.cooldown.SetHideCountdownNumbers) == "function" then
    button.cooldown:SetHideCountdownNumbers(not config.cooldownText)
  end
end

local function CreateButton(moduleKey, unitFrame, index, config)
  local button = CreateFrame("Frame", nil, unitFrame)
  button.moduleKey = moduleKey

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints(button)
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  button.cooldown:SetAllPoints(button)
  if type(button.cooldown.SetDrawSwipe) == "function" then
    button.cooldown:SetDrawSwipe(true)
  end
  button.cooldown:SetDrawEdge(false)
  if type(button.cooldown.SetSwipeColor) == "function" then
    button.cooldown:SetSwipeColor(0, 0, 0, 0.65)
  end
  if type(button.cooldown.SetHideCountdownNumbers) == "function" then
    button.cooldown:SetHideCountdownNumbers(not config.cooldownText)
  end
  button.cooldown:SetReverse(true)

  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)

  ConfigureButton(unitFrame, button, index, config)
  return button
end

local function EnsureButtons(moduleKey, unitFrame, config)
  local buttons, store = GetStore(OVERLAYS, moduleKey, unitFrame)
  if not buttons then
    buttons = {}
    store[unitFrame] = buttons
  end

  for index = 1, config.maxIcons do
    if not buttons[index] then
      buttons[index] = CreateButton(moduleKey, unitFrame, index, config)
    else
      ConfigureButton(unitFrame, buttons[index], index, config)
    end
  end

  return buttons
end

function Frames.Clear(moduleKey, unitFrame)
  local buttons = GetStore(OVERLAYS, moduleKey, unitFrame)
  local backing = GetStore(BACKINGS, moduleKey, unitFrame)

  if backing then
    backing:Hide()
  end

  if buttons then
    for _, button in ipairs(buttons) do
      button:Hide()
    end
  end
end

function Frames.RenderAuras(moduleKey, unitFrame, unit, options)
  if not unitFrame or not unit or not UnitExists(unit) then
    Frames.Clear(moduleKey, unitFrame)
    return
  end

  if Frames.IsForbidden(unitFrame) then
    return
  end

  local config = {
    iconSize = options.iconSize or 21,
    maxIcons = options.maxIcons or 5,
    spacing = options.spacing or 0,
    point = options.point or "BOTTOMRIGHT",
    relativePoint = options.relativePoint,
    x = options.x or 0,
    y = options.y or 0,
    growth = options.growth or "LEFT",
    backingAlpha = options.backingAlpha,
    anchorFrame = options.anchorFrame,
    coverWidth = options.coverWidth,
    coverHeight = options.coverHeight,
    cooldownFallback = options.cooldownFallback,
    cooldownReplay = options.cooldownReplay,
    cooldownText = options.cooldownText,
  }

  local buttons = EnsureButtons(moduleKey, unitFrame, config)
  local backing = EnsureBacking(moduleKey, unitFrame, config)

  local auraIndex = 1
  local iconIndex = 1

  while auraIndex <= (options.maxScan or 40) and iconIndex <= config.maxIcons do
    local aura = ns.Auras.Read(unit, auraIndex, options.filter, options)
    if not aura then
      break
    end

    if ns.Auras.Matches(aura, options) then
      local button = buttons[iconIndex]
      local icon = ns.Auras.GetIcon(aura)
      local okTexture = pcall(button.icon.SetTexture, button.icon, icon)

      if okTexture then
        Raise(unitFrame, button)

        local okCooldown = pcall(function()
          local duration = ns.Auras.SafeField(aura, "duration")
          local expirationTime = ns.Auras.SafeField(aura, "expirationTime")
          if (type(duration) ~= "number" or type(expirationTime) ~= "number" or duration <= 0) and type(config.cooldownFallback) == "function" then
            local fallbackStart, fallbackDuration = config.cooldownFallback(unitFrame, iconIndex, aura)
            if type(fallbackStart) == "number" and type(fallbackDuration) == "number" and fallbackDuration > 0 then
              duration = fallbackDuration
              expirationTime = fallbackStart + fallbackDuration
            end
          end

          if type(duration) == "number" and type(expirationTime) == "number" and duration > 0 then
            button.cooldown:SetCooldown(expirationTime - duration, duration)
            button.cooldown:Show()
          elseif type(config.cooldownReplay) == "function" and config.cooldownReplay(unitFrame, iconIndex, aura, button.cooldown, unit) then
            button.cooldown:Show()
          else
            button.cooldown:Hide()
          end
        end)

        if not okCooldown then
          button.cooldown:Hide()
        end

        local okCount = pcall(function()
          local applications = ns.Auras.SafeField(aura, "applications") or ns.Auras.SafeField(aura, "count") or 0
          if applications and applications > 1 then
            button.count:SetText(ns.Auras.SafeText(applications))
          else
            button.count:SetText("")
          end
        end)

        if not okCount then
          button.count:SetText("")
        end

        button:Show()
        iconIndex = iconIndex + 1
      end
    end

    auraIndex = auraIndex + 1
  end

  for index = iconIndex, #buttons do
    if buttons[index] then
      buttons[index]:Hide()
    end
  end

  if iconIndex > 1 then
    local shown = iconIndex - 1
    local width = shown * config.iconSize + math.max(0, shown - 1) * config.spacing + 2
    backing:SetWidth(math.max(width, config.coverWidth or 0))
    backing:SetHeight(math.max(config.iconSize + 2, config.coverHeight or 0))
    backing:Show()
  else
    backing:Hide()
  end
end

function Frames.RenderTestIcon(moduleKey, unitFrame, options)
  if not unitFrame or Frames.IsForbidden(unitFrame) then
    return
  end

  local config = {
    iconSize = options.iconSize or 40,
    maxIcons = 1,
    spacing = options.spacing or 0,
    point = options.point or "BOTTOM",
    relativePoint = options.relativePoint or "TOP",
    x = options.x or 0,
    y = options.y or 2,
    growth = options.growth or "RIGHT",
    backingAlpha = options.backingAlpha,
    anchorFrame = options.anchorFrame,
  }

  local buttons = EnsureButtons(moduleKey, unitFrame, config)
  local backing = EnsureBacking(moduleKey, unitFrame, config)
  local button = buttons[1]

  Raise(unitFrame, button)
  button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  pcall(button.cooldown.SetCooldown, button.cooldown, 0, 0)
  button.count:SetText("T")
  button:Show()

  for index = 2, #buttons do
    if buttons[index] then
      buttons[index]:Hide()
    end
  end

  backing:SetWidth(config.iconSize + 2)
  backing:SetHeight(config.iconSize + 2)
  backing:Show()
end
