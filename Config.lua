local _, ns = ...

local Config = {}
ns.Config = Config

local panel

local MODULE_LABELS = {
  raidHots = "Raid HoTs",
  arenaDebuffs = "Arena debuffs",
  nameplateDebuffs = "Nameplate debuffs",
}

local CATEGORY_LABELS = {
  hots = "HoTs",
  dots = "DoTs",
  externals = "External defensives",
  utility = "Utility buffs",
}

local function ControlName(moduleKey, suffix)
  return "MeoAura" .. moduleKey .. suffix
end

local function CreateCheckbox(parent, moduleKey, y)
  local checkbox = CreateFrame("CheckButton", ControlName(moduleKey, "Enabled"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
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

local function CreateSlider(parent, moduleKey, y)
  local slider = CreateFrame("Slider", ControlName(moduleKey, "IconSize"), parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 32, y)
  local minValue = moduleKey == "raidHots" and 22 or 12
  slider:SetMinMaxValues(minValue, 48)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(220)

  local text = _G[slider:GetName() .. "Text"] or slider.Text
  local low = _G[slider:GetName() .. "Low"] or slider.Low
  local high = _G[slider:GetName() .. "High"] or slider.High
  if text then
    text:SetText(MODULE_LABELS[moduleKey] .. " icon size")
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

local function CreateCooldownTextCheckbox(parent, moduleKey, y)
  local checkbox = CreateFrame("CheckButton", ControlName(moduleKey, "CooldownText"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 32, y)
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

local function CreateCategoryCheckbox(parent, categoryKey, y)
  local checkbox = CreateFrame("CheckButton", ControlName("Category" .. categoryKey, "Enabled"), parent, "InterfaceOptionsCheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 280, y)
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
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -382)
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

  CreateCheckbox(panel, "raidHots", -52)
  CreateSlider(panel, "raidHots", -88)
  CreateCooldownTextCheckbox(panel, "raidHots", -122)
  CreateCheckbox(panel, "arenaDebuffs", -158)
  CreateSlider(panel, "arenaDebuffs", -194)
  CreateCooldownTextCheckbox(panel, "arenaDebuffs", -228)
  CreateCheckbox(panel, "nameplateDebuffs", -264)
  CreateSlider(panel, "nameplateDebuffs", -300)
  CreateCooldownTextCheckbox(panel, "nameplateDebuffs", -334)

  local categoryTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  categoryTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 280, -52)
  categoryTitle:SetText("Aura Categories")

  CreateCategoryCheckbox(panel, "hots", -82)
  CreateCategoryCheckbox(panel, "dots", -114)
  CreateCategoryCheckbox(panel, "externals", -146)
  CreateCategoryCheckbox(panel, "utility", -178)
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
