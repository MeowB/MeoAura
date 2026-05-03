local _, ns = ...

local Config = {}
ns.Config = Config

local panel

local MODULE_LABELS = {
  raidHots = "Raid HoTs",
  arenaDebuffs = "Arena debuffs",
  nameplateDebuffs = "Nameplate debuffs",
  nameplateHots = "Friendly nameplate HoTs",
}

local CATEGORY_LABELS = {
  hots = "HoTs",
  dots = "DoTs",
  externals = "External defensives",
  utility = "Utility buffs",
}

local SECTION_DESCRIPTIONS = {
  raid = "Show your tracked HoTs, externals, and utility buffs on Blizzard party and raid frames.",
  nameplates = "Tune enemy nameplate debuffs separately from your helpful buffs on friendly nameplates.",
  arena = "Experimental enemy arena aura display while the combat-log tracker is still being rebuilt.",
  categories = "Choose which tracked aura groups are eligible for the enabled modules.",
}

local function ControlName(moduleKey, suffix)
  return "MeoAura" .. moduleKey .. suffix
end

local function CreateSection(parent, title, description, x, y)
  local titleText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  titleText:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  titleText:SetText(title)

  local descriptionText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  descriptionText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
  descriptionText:SetWidth(300)
  descriptionText:SetJustifyH("LEFT")
  descriptionText:SetText(description)

  return titleText, descriptionText
end

local function CreateCheckbox(parent, moduleKey, x, y)
  local checkbox = CreateFrame("CheckButton", ControlName(moduleKey, "Enabled"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local label = _G[checkbox:GetName() .. "Text"] or checkbox.Text
  if label then
    label:SetText(MODULE_LABELS[moduleKey])
  end
  checkbox:SetScript("OnClick", function(self)
    ns.GetSettings(moduleKey).enabled = self:GetChecked()
    ns.ApplySettings()
  end)

  parent.controls[#parent.controls + 1] = function()
    checkbox:SetChecked(ns.GetSettings(moduleKey).enabled)
  end
end

local function CreateSlider(parent, moduleKey, x, y, label)
  local slider = CreateFrame("Slider", ControlName(moduleKey, "IconSize"), parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local minValue = moduleKey == "raidHots" and 22 or 12
  slider:SetMinMaxValues(minValue, 48)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(220)

  local text = _G[slider:GetName() .. "Text"] or slider.Text
  local low = _G[slider:GetName() .. "Low"] or slider.Low
  local high = _G[slider:GetName() .. "High"] or slider.High
  if text then
    text:SetText(label or MODULE_LABELS[moduleKey] .. " icon size")
  end
  if low then
    low:SetText(tostring(minValue))
  end
  if high then
    high:SetText("48")
  end
  slider:SetScript("OnValueChanged", function(self, value)
    ns.GetSettings(moduleKey).iconSize = math.floor(value + 0.5)
    ns.ApplySettings()
  end)

  parent.controls[#parent.controls + 1] = function()
    slider:SetValue(ns.GetSettings(moduleKey).iconSize)
  end
end

local function CreateCooldownTextCheckbox(parent, moduleKey, x, y)
  local checkbox = CreateFrame("CheckButton", ControlName(moduleKey, "CooldownText"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local label = _G[checkbox:GetName() .. "Text"] or checkbox.Text
  if label then
    label:SetText(MODULE_LABELS[moduleKey] .. " cooldown text")
  end
  checkbox:SetScript("OnClick", function(self)
    ns.GetSettings(moduleKey).cooldownText = self:GetChecked()
    ns.ApplySettings()
  end)

  parent.controls[#parent.controls + 1] = function()
    checkbox:SetChecked(ns.GetSettings(moduleKey).cooldownText)
  end
end

local function CreateTooltipsCheckbox(parent, moduleKey, x, y)
  local checkbox = CreateFrame("CheckButton", ControlName(moduleKey, "Tooltips"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local label = _G[checkbox:GetName() .. "Text"] or checkbox.Text
  if label then
    label:SetText(MODULE_LABELS[moduleKey] .. " tooltips")
  end
  checkbox:SetScript("OnClick", function(self)
    ns.GetSettings(moduleKey).tooltips = self:GetChecked()
    ns.ApplySettings()
  end)

  parent.controls[#parent.controls + 1] = function()
    checkbox:SetChecked(ns.GetSettings(moduleKey).tooltips)
  end
end

local function CreateCategoryCheckbox(parent, categoryKey, x, y)
  local checkbox = CreateFrame("CheckButton", ControlName("Category" .. categoryKey, "Enabled"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local label = _G[checkbox:GetName() .. "Text"] or checkbox.Text
  if label then
    label:SetText(CATEGORY_LABELS[categoryKey])
  end
  checkbox:SetScript("OnClick", function(self)
    ns.GetCategories()[categoryKey] = self:GetChecked()
    ns.ApplySettings()
  end)

  parent.controls[#parent.controls + 1] = function()
    checkbox:SetChecked(ns.GetCategories()[categoryKey])
  end
end

local function CreateSaveButton(parent)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -552)
  button:SetSize(160, 24)
  button:SetText("Apply Settings")
  button:SetScript("OnClick", function()
    ns.ApplySettings()
    if ns.PrintSettings then
      ns.PrintSettings()
    end
  end)
end

function Config:Create()
  if panel then
    return
  end

  panel = CreateFrame("Frame")
  panel.name = ns.displayName
  panel.controls = {}

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText(ns.displayName)

  CreateSection(panel, "Raid Frames", SECTION_DESCRIPTIONS.raid, 16, -52)
  CreateCheckbox(panel, "raidHots", 16, -100)
  CreateSlider(panel, "raidHots", 32, -136, "Raid frame icon size")
  CreateCooldownTextCheckbox(panel, "raidHots", 32, -170)
  CreateTooltipsCheckbox(panel, "raidHots", 32, -202)

  CreateSection(panel, "Nameplates", SECTION_DESCRIPTIONS.nameplates, 16, -246)
  CreateCheckbox(panel, "nameplateDebuffs", 16, -294)
  CreateSlider(panel, "nameplateDebuffs", 32, -330, "Enemy debuff icon size")
  CreateCooldownTextCheckbox(panel, "nameplateDebuffs", 32, -364)
  CreateCheckbox(panel, "nameplateHots", 16, -396)
  CreateSlider(panel, "nameplateHots", 32, -432, "Friendly buff icon size")

  CreateSection(panel, "Arena Frames", SECTION_DESCRIPTIONS.arena, 360, -52)
  CreateCheckbox(panel, "arenaDebuffs", 360, -100)
  CreateSlider(panel, "arenaDebuffs", 376, -136, "Arena debuff icon size")
  CreateCooldownTextCheckbox(panel, "arenaDebuffs", 376, -170)

  CreateSection(panel, "Aura Categories", SECTION_DESCRIPTIONS.categories, 360, -246)
  CreateCategoryCheckbox(panel, "hots", 360, -294)
  CreateCategoryCheckbox(panel, "dots", 360, -326)
  CreateCategoryCheckbox(panel, "externals", 360, -358)
  CreateCategoryCheckbox(panel, "utility", 360, -390)
  CreateSaveButton(panel)

  panel:SetScript("OnShow", function(self)
    for _, refresh in ipairs(self.controls) do
      refresh()
    end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, ns.displayName)
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category.ID
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function Config:Open()
  if not panel then
    self:Create()
  end

  if Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(ns.settingsCategoryID or ns.displayName)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end
