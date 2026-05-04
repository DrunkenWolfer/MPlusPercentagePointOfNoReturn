local ADDON_NAME = ...
local ADDON_TITLE = "MPlusPercentagePointOfNoReturn"
local MAX_SUPPORTED_ENTRIES = 20
local DEFAULT_ENTRY_COUNT = 3
local OPTIONS_TEXT_WIDTH = 520
local OPTIONS_CONTENT_WIDTH = 560
local DUNGEON_DIFFICULTY_MYTHIC_KEYSTONE = 8
local MIN_DISPLAY_TEXT_WIDTH = 1
local DISPLAY_HORIZONTAL_PADDING = 0
local DISPLAY_VERTICAL_PADDING = 0
local DISPLAY_LINE_GAP = 1
local ENTRY_BLOCK_GAP = 10
local DISPLAY_LABEL_FONT_SIZE_REDUCTION = 0
local DISPLAY_TEXT_WIDTH_BUFFER = 0
local DISPLAY_TEXT_RENDER_WIDTH = 10000
local DISPLAY_LABEL_SHADOW_COLOR = { 0, 0, 0, 1 }
local DISPLAY_LABEL_SHADOW_OFFSET_X = 1
local DISPLAY_LABEL_SHADOW_OFFSET_Y = -1
local DEFAULT_FLOW_DIRECTION = "DOWN"
local unpack = unpack or table.unpack
local FLOW_DIRECTION_ORDER = { "DOWN", "UP", "LEFT", "RIGHT" }
local FLOW_DIRECTIONS = {
    DOWN = {
        label = "Down",
    },
    UP = {
        label = "Up",
    },
    LEFT = {
        label = "Left",
    },
    RIGHT = {
        label = "Right",
    },
}

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    entryCount = DEFAULT_ENTRY_COUNT,
    flowDirection = DEFAULT_FLOW_DIRECTION,
    currentPercentEnabled = false,
    currentPercentOptInConfirmed = false,
    currentPercentPoint = "CENTER",
    currentPercentRelativePoint = "CENTER",
    currentPercentX = 0,
    currentPercentY = 120,
    currentPercentScale = 1,
    scale = 1,
    testMode = false,
    debug = false,
    lastSelectedChallengeMapID = 0,
    instances = {},
}

local db
local displayFrame
local displayAnchorFrame
local currentPercentFrame
local rootCategory
local rootPanel
local rootStatusText
local challengeMapIDs = {}
local challengeMapInfoByID = {}

local LABEL_COLOR = { 1.0, 0.82, 0.18 }
local VALUE_COLOR = { 1.0, 1.0, 1.0 }
local ENEMY_FORCES_DESCRIPTION_PATTERNS = {
    "Enemy Forces",
    "enemy forces",
    "Fuerzas enemigas",
    "fuerzas enemigas",
    "Gegnerische Streitkr",
    "Streitkr",
}
local RefreshRootLayout
local ResolveCurrentChallengeMapID
local UpdateRootScrollBar
local SelectRootChallengeMapID
local StopDisplayDrag

local function CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local function Trim(text)
    if type(text) ~= "string" then
        return ""
    end

    return text:match("^%s*(.-)%s*$") or ""
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end

    return math.ceil(value - 0.5)
end

local function GetDisplayLabelFont()
    local fontPath, fontSize, fontFlags
    if GameFontNormalSmall and GameFontNormalSmall.GetFont then
        fontPath, fontSize, fontFlags = GameFontNormalSmall:GetFont()
    end

    fontPath = fontPath or STANDARD_TEXT_FONT
    fontSize = math.max(1, (tonumber(fontSize) or 12) - DISPLAY_LABEL_FONT_SIZE_REDUCTION)
    fontFlags = fontFlags or ""
    return fontPath, fontSize, fontFlags
end

local function ApplyDisplayLabelFont(target)
    if not target then
        return
    end

    local fontPath, fontSize, fontFlags = GetDisplayLabelFont()
    target:SetFont(fontPath, fontSize, fontFlags)
    target:SetShadowColor(unpack(DISPLAY_LABEL_SHADOW_COLOR))
    target:SetShadowOffset(DISPLAY_LABEL_SHADOW_OFFSET_X, DISPLAY_LABEL_SHADOW_OFFSET_Y)
end

local function ConfigureDisplayFontString(fontString)
    if not fontString then
        return
    end

    fontString:SetJustifyH("LEFT")
    fontString:SetJustifyV("TOP")
    fontString:SetWordWrap(false)
    if fontString.SetNonSpaceWrap then
        fontString:SetNonSpaceWrap(false)
    end
    if fontString.SetMaxLines then
        fontString:SetMaxLines(0)
    end
end

local function ClampEntryCount(value)
    value = math.floor(tonumber(value) or DEFAULT_ENTRY_COUNT)
    if value < 1 then
        return 1
    end

    if value > MAX_SUPPORTED_ENTRIES then
        return MAX_SUPPORTED_ENTRIES
    end

    return value
end

local function NormalizeFlowDirection(value)
    if type(value) == "string" then
        value = value:upper()
    end

    if FLOW_DIRECTIONS[value] then
        return value
    end

    return DEFAULT_FLOW_DIRECTION
end

local function GetConfiguredEntryCount()
    return ClampEntryCount(db and db.entryCount)
end

local function GetConfiguredFlowDirection()
    return NormalizeFlowDirection(db and db.flowDirection)
end

local function CreateEmptyEntries()
    local entries = {}
    for index = 1, MAX_SUPPORTED_ENTRIES do
        entries[index] = {
            label = "",
            value = "",
        }
    end
    return entries
end

local function EnsureDatabase()
    MPlusPercentagePointOfNoReturnDB = CopyDefaults(MPlusPercentagePointOfNoReturnDB, DEFAULTS)
    db = MPlusPercentagePointOfNoReturnDB

    db.entryCount = ClampEntryCount(db.entryCount)
    db.flowDirection = NormalizeFlowDirection(db.flowDirection)

    if db.currentPercentOptInConfirmed ~= true then
        db.currentPercentEnabled = false
    end
end

local function EnsureInstanceConfig(challengeMapID)
    if not db.instances[challengeMapID] then
        db.instances[challengeMapID] = {
            entries = CreateEmptyEntries(),
        }
    end

    local instanceConfig = db.instances[challengeMapID]
    if type(instanceConfig.entries) ~= "table" then
        instanceConfig.entries = CreateEmptyEntries()
    end

    for entryIndex = 1, MAX_SUPPORTED_ENTRIES do
        if type(instanceConfig.entries[entryIndex]) ~= "table" then
            instanceConfig.entries[entryIndex] = {}
        end

        if instanceConfig.entries[entryIndex].label == nil then
            instanceConfig.entries[entryIndex].label = ""
        end

        if instanceConfig.entries[entryIndex].value == nil then
            instanceConfig.entries[entryIndex].value = ""
        end
    end

    return instanceConfig
end

local function RefreshMapCache()
    wipe(challengeMapIDs)
    wipe(challengeMapInfoByID)

    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then
        return false
    end

    for _, challengeMapID in ipairs(maps) do
        local name = C_ChallengeMode.GetMapUIInfo(challengeMapID)
        if type(name) == "string" and name ~= "" then
            challengeMapInfoByID[challengeMapID] = {
                name = name,
            }

            challengeMapIDs[#challengeMapIDs + 1] = challengeMapID
        end
    end

    table.sort(challengeMapIDs, function(left, right)
        local leftName = challengeMapInfoByID[left] and challengeMapInfoByID[left].name or ""
        local rightName = challengeMapInfoByID[right] and challengeMapInfoByID[right].name or ""
        if leftName == rightName then
            return left < right
        end
        return leftName < rightName
    end)

    return #challengeMapIDs > 0
end

local function FormatPercentText(valueText)
    valueText = Trim(valueText)
    if valueText == "" then
        return ""
    end

    if valueText:sub(-1) == "%" then
        return valueText
    end

    return valueText .. "%"
end

local function NormalizeInstanceName(value)
    value = Trim(value)
    if value == "" then
        return ""
    end

    value = value:lower()
    value = value:gsub("[%s%p]+", "")
    return value
end

local function ResolveChallengeMapIDFromInstanceName(instanceName)
    instanceName = Trim(instanceName)
    if instanceName == "" then
        return nil
    end

    for challengeMapID, mapInfo in pairs(challengeMapInfoByID) do
        if mapInfo and mapInfo.name == instanceName then
            return challengeMapID
        end
    end

    local normalizedInstanceName = NormalizeInstanceName(instanceName)
    if normalizedInstanceName == "" then
        return nil
    end

    for challengeMapID, mapInfo in pairs(challengeMapInfoByID) do
        if mapInfo and NormalizeInstanceName(mapInfo.name) == normalizedInstanceName then
            return challengeMapID
        end
    end

    return nil
end

local function GetPartyInstanceDifficultyID()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then
        return nil
    end

    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID
end

local function CanResolveCurrentInstanceByName()
    local difficultyID = GetPartyInstanceDifficultyID()
    if not difficultyID then
        return false
    end

    if db and db.debug == true then
        return true
    end

    return difficultyID == DUNGEON_DIFFICULTY_MYTHIC_KEYSTONE
end

local function ResolveCurrentInstanceChallengeMapIDForOptions()
    local activeChallengeMapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() or 0
    if activeChallengeMapID and activeChallengeMapID > 0 and challengeMapInfoByID[activeChallengeMapID] then
        return activeChallengeMapID
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then
        return nil
    end

    local instanceName = GetInstanceInfo()
    local challengeMapID = ResolveChallengeMapIDFromInstanceName(instanceName)
    if challengeMapID then
        return challengeMapID
    end

    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local uiMapID = C_Map.GetBestMapForUnit("player")
        local mapInfo = uiMapID and C_Map.GetMapInfo(uiMapID)
        challengeMapID = mapInfo and ResolveChallengeMapIDFromInstanceName(mapInfo.name)
        if challengeMapID then
            return challengeMapID
        end
    end

    return nil
end

local function IsEnemyForcesCriteria(criteriaInfo)
    if type(criteriaInfo) ~= "table" or not criteriaInfo.isWeightedProgress then
        return false
    end

    local description = type(criteriaInfo.description) == "string" and criteriaInfo.description or ""
    for _, pattern in ipairs(ENEMY_FORCES_DESCRIPTION_PATTERNS) do
        if description:find(pattern, 1, true) then
            return true
        end
    end

    return false
end

local function ParseEnemyForcesCriteria(criteriaInfo)
    if type(criteriaInfo) ~= "table" then
        return 0, 0
    end

    local totalQuantity = tonumber(criteriaInfo.totalQuantity) or 0
    local quantityString = type(criteriaInfo.quantityString) == "string" and criteriaInfo.quantityString or nil
    if quantityString then
        local currentValue = quantityString:match("([%d%,%.]+)%s*/")
        if currentValue then
            return tonumber((currentValue:gsub(",", "."))) or 0, totalQuantity
        end

        if quantityString:find("%%", 1, true) then
            local percentText = quantityString:match("([%d%,%.]+)%s*%%")
            if percentText then
                local percentValue = tonumber((percentText:gsub(",", ".")))
                if percentValue then
                    return percentValue, 100
                end
            end
        end

        local firstValue = quantityString:match("[%d%,%.]+")
        if firstValue then
            return tonumber((firstValue:gsub(",", "."))) or 0, totalQuantity
        end
    end

    local quantity = tonumber(criteriaInfo.quantity)
    if quantity ~= nil and totalQuantity > 0 then
        return quantity, totalQuantity
    end

    return 0, totalQuantity
end

local function GetCurrentEnemyForcesInfo()
    if not (C_Scenario and C_Scenario.GetStepInfo and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then
        return 0, 0
    end

    local _, _, criteriaCount = C_Scenario.GetStepInfo()
    if not criteriaCount or criteriaCount <= 0 then
        return 0, 0
    end

    for criteriaIndex = 1, criteriaCount do
        local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
        if IsEnemyForcesCriteria(criteriaInfo) then
            return ParseEnemyForcesCriteria(criteriaInfo)
        end
    end

    local bestCurrent = 0
    local bestTotal = 0
    for criteriaIndex = 1, criteriaCount do
        local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
        if criteriaInfo and criteriaInfo.isWeightedProgress then
            local currentQuantity, totalQuantity = ParseEnemyForcesCriteria(criteriaInfo)
            if totalQuantity > bestTotal then
                bestTotal = totalQuantity
                bestCurrent = currentQuantity
            end
        end
    end

    return bestCurrent, bestTotal
end

local function BuildDisplayEntries(challengeMapID)
    local instanceConfig = db.instances[challengeMapID]
    if not instanceConfig or type(instanceConfig.entries) ~= "table" then
        return nil
    end

    local entries = {}
    for entryIndex = 1, GetConfiguredEntryCount() do
        local entry = instanceConfig.entries[entryIndex] or {}
        local label = Trim(entry.label)
        local value = FormatPercentText(entry.value)

        if label ~= "" or value ~= "" then
            entries[#entries + 1] = {
                label = label,
                value = value,
            }
        end
    end

    if #entries == 0 then
        return nil
    end

    return entries
end

local function ResolvePreviewChallengeMapID()
    local currentChallengeMapID = ResolveCurrentChallengeMapID()
    if currentChallengeMapID then
        return currentChallengeMapID
    end

    if rootPanel and rootPanel.selectedChallengeMapID and challengeMapInfoByID[rootPanel.selectedChallengeMapID] then
        return rootPanel.selectedChallengeMapID
    end

    return challengeMapIDs[1]
end

local function BuildPreviewDisplayEntries(challengeMapID)
    local entries = challengeMapID and BuildDisplayEntries(challengeMapID) or nil
    if entries then
        return entries
    end

    local mapName = challengeMapID and challengeMapInfoByID[challengeMapID] and challengeMapInfoByID[challengeMapID].name or "Test Mode"
    local previewEntries = {}
    local entryCount = GetConfiguredEntryCount()
    for entryIndex = 1, entryCount do
        local label
        if entryIndex == 1 then
            label = mapName
        elseif entryIndex == 2 then
            label = "Move display"
        elseif entryIndex == 3 then
            label = "Check direction"
        else
            label = string.format("Preview %d", entryIndex)
        end

        previewEntries[#previewEntries + 1] = {
            label = label,
            value = string.format("%d%%", math.min(99, 15 + (entryIndex * 15))),
        }
    end

    return previewEntries
end

ResolveCurrentChallengeMapID = function()
    local activeChallengeMapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() or 0
    if activeChallengeMapID and activeChallengeMapID > 0 then
        return activeChallengeMapID
    end

    if CanResolveCurrentInstanceByName() then
        local instanceName = GetInstanceInfo()
        local challengeMapID = ResolveChallengeMapIDFromInstanceName(instanceName)
        if challengeMapID then
            return challengeMapID
        end

        if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
            local uiMapID = C_Map.GetBestMapForUnit("player")
            local mapInfo = uiMapID and C_Map.GetMapInfo(uiMapID)
            challengeMapID = mapInfo and ResolveChallengeMapIDFromInstanceName(mapInfo.name)
            if challengeMapID then
                return challengeMapID
            end
        end
    end

    return nil
end

local function GetUIParentEffectiveScale()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    if type(scale) ~= "number" or scale <= 0 then
        return 1
    end

    return scale
end

local function GetRegionTopLeftOffsets(region)
    if not region then
        return nil, nil
    end

    local left = region:GetLeft()
    local top = region:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then
        return nil, nil
    end

    return left, top
end

local function GetCursorUIParentPosition()
    local cursorX, cursorY = GetCursorPosition()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then
        return nil, nil
    end

    local uiScale = GetUIParentEffectiveScale()
    return cursorX / uiScale, cursorY / uiScale
end

local function GetDisplayOriginScale()
    if not displayFrame then
        return 1
    end

    local frameScale = displayFrame:GetEffectiveScale() or 1
    if type(frameScale) ~= "number" or frameScale <= 0 then
        frameScale = 1
    end

    return frameScale / GetUIParentEffectiveScale()
end

local function IsUsingDisplayAnchorPosition()
    return displayAnchorFrame and db and db.displayOriginX ~= nil and db.displayOriginY ~= nil
end

local function GetDisplayAnchorOffsets()
    if not displayAnchorFrame then
        return nil, nil
    end

    return GetRegionTopLeftOffsets(displayAnchorFrame)
end

local function SetDisplayAnchorTopLeft(left, top)
    if not displayAnchorFrame then
        return
    end

    displayAnchorFrame:ClearAllPoints()
    displayAnchorFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function GetDisplayOriginOffsets()
    if IsUsingDisplayAnchorPosition() then
        local anchorLeft, anchorTop = GetDisplayAnchorOffsets()
        if type(anchorLeft) == "number" and type(anchorTop) == "number" then
            return anchorLeft, anchorTop
        end
    end

    if displayFrame and displayFrame.originHandle then
        local originLeft, originTop = GetRegionTopLeftOffsets(displayFrame.originHandle)
        if type(originLeft) == "number" and type(originTop) == "number" then
            return originLeft, originTop
        end
    end

    if not displayFrame then
        return nil, nil
    end

    local left, top = GetRegionTopLeftOffsets(displayFrame)
    if type(left) ~= "number" or type(top) ~= "number" then
        return nil, nil
    end

    local scale = GetDisplayOriginScale()
    return left + ((displayFrame.originOffsetX or 0) * scale), top - ((displayFrame.originOffsetY or 0) * scale)
end

local function ApplyDisplayPosition()
    if not displayFrame or not db then
        return
    end

    displayFrame:SetScale(db.scale or 1)

    if IsUsingDisplayAnchorPosition() then
        local scale = GetDisplayOriginScale()
        local originOffsetX = (displayFrame.originOffsetX or 0) * scale
        local originOffsetY = (displayFrame.originOffsetY or 0) * scale

        SetDisplayAnchorTopLeft(db.displayOriginX or 0, db.displayOriginY or 0)

        displayFrame:ClearAllPoints()
        displayFrame:SetPoint(
            "TOPLEFT",
            displayAnchorFrame,
            "TOPLEFT",
            -originOffsetX,
            originOffsetY
        )
        return
    end

    displayFrame:ClearAllPoints()
    displayFrame:SetPoint(
        db.point or DEFAULTS.point,
        UIParent,
        db.relativePoint or DEFAULTS.relativePoint,
        db.x or DEFAULTS.x,
        db.y or DEFAULTS.y
    )
end

local function ApplyCurrentPercentDisplayPosition()
    if not currentPercentFrame or not db then
        return
    end

    currentPercentFrame:ClearAllPoints()
    currentPercentFrame:SetScale(db.currentPercentScale or 1)
    currentPercentFrame:SetPoint(
        db.currentPercentPoint or DEFAULTS.currentPercentPoint,
        UIParent,
        db.currentPercentRelativePoint or DEFAULTS.currentPercentRelativePoint,
        db.currentPercentX or DEFAULTS.currentPercentX,
        db.currentPercentY or DEFAULTS.currentPercentY
    )
end

local function SaveDisplayPosition()
    if not displayFrame or not db then
        return
    end

    local originX, originY
    if IsUsingDisplayAnchorPosition() then
        originX, originY = GetDisplayAnchorOffsets()
    else
        originX, originY = GetDisplayOriginOffsets()
    end

    if type(originX) ~= "number" or type(originY) ~= "number" then
        return
    end

    db.displayOriginX = Round(originX)
    db.displayOriginY = Round(originY)
    db.point = "TOPLEFT"
    db.relativePoint = "BOTTOMLEFT"
    db.x = db.displayOriginX
    db.y = db.displayOriginY
end

local function SaveCurrentPercentDisplayPosition()
    if not currentPercentFrame or not db then
        return
    end

    local point, _, relativePoint, x, y = currentPercentFrame:GetPoint(1)
    db.currentPercentPoint = point or DEFAULTS.currentPercentPoint
    db.currentPercentRelativePoint = relativePoint or DEFAULTS.currentPercentRelativePoint
    db.currentPercentX = Round(x)
    db.currentPercentY = Round(y)
end

local function ResetDisplayPosition()
    db.displayOriginX = nil
    db.displayOriginY = nil
    db.point = DEFAULTS.point
    db.relativePoint = DEFAULTS.relativePoint
    db.x = DEFAULTS.x
    db.y = DEFAULTS.y
    ApplyDisplayPosition()
end

local function ResetCurrentPercentDisplayPosition()
    db.currentPercentPoint = DEFAULTS.currentPercentPoint
    db.currentPercentRelativePoint = DEFAULTS.currentPercentRelativePoint
    db.currentPercentX = DEFAULTS.currentPercentX
    db.currentPercentY = DEFAULTS.currentPercentY
    ApplyCurrentPercentDisplayPosition()
end

local function UpdateDisplayInteractivity()
    if not displayFrame or not db then
        return
    end

    local allowDragging = db.testMode == true
    displayFrame:EnableMouse(allowDragging)

    if not allowDragging then
        StopDisplayDrag(displayFrame.isDraggingOrigin == true)
    end
end

local function UpdateCurrentPercentDisplayInteractivity()
    if not currentPercentFrame or not db then
        return
    end

    local allowDragging = db.testMode == true and db.currentPercentEnabled == true
    currentPercentFrame:EnableMouse(allowDragging)

    if not allowDragging then
        currentPercentFrame:StopMovingOrSizing()
    end
end

local function UpdateDisplayDragPosition()
    if not displayFrame or not db or not displayFrame.isDraggingOrigin then
        return
    end

    local cursorX, cursorY = GetCursorUIParentPosition()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then
        return
    end

    local targetOriginX = cursorX - (displayFrame.dragCursorOffsetX or 0)
    local targetOriginY = cursorY + (displayFrame.dragCursorOffsetY or 0)

    SetDisplayAnchorTopLeft(targetOriginX, targetOriginY)

    local actualOriginX, actualOriginY = GetDisplayAnchorOffsets()
    db.displayOriginX = Round(actualOriginX or targetOriginX)
    db.displayOriginY = Round(actualOriginY or targetOriginY)
    db.point = "TOPLEFT"
    db.relativePoint = "BOTTOMLEFT"
    db.x = db.displayOriginX
    db.y = db.displayOriginY
end

local function StartDisplayDrag()
    if not displayFrame or not db or not db.testMode then
        return
    end

    local originX, originY = GetDisplayOriginOffsets()
    local cursorX, cursorY = GetCursorUIParentPosition()
    if type(originX) ~= "number" or type(originY) ~= "number" or type(cursorX) ~= "number" or type(cursorY) ~= "number" then
        return
    end

    if not IsUsingDisplayAnchorPosition() then
        db.displayOriginX = Round(originX)
        db.displayOriginY = Round(originY)
        db.point = "TOPLEFT"
        db.relativePoint = "BOTTOMLEFT"
        db.x = db.displayOriginX
        db.y = db.displayOriginY
        ApplyDisplayPosition()
        originX, originY = GetDisplayOriginOffsets()
        if type(originX) ~= "number" or type(originY) ~= "number" then
            return
        end
    end

    displayFrame.isDraggingOrigin = true
    displayFrame.dragCursorOffsetX = cursorX - originX
    displayFrame.dragCursorOffsetY = originY - cursorY
    displayFrame:SetScript("OnUpdate", UpdateDisplayDragPosition)
    UpdateDisplayDragPosition()
end

StopDisplayDrag = function(shouldSave)
    if not displayFrame then
        return
    end

    displayFrame.isDraggingOrigin = false
    displayFrame.dragCursorOffsetX = nil
    displayFrame.dragCursorOffsetY = nil
    displayFrame:SetScript("OnUpdate", nil)

    if shouldSave ~= false then
        SaveDisplayPosition()
    end
end

local function CreateDisplayFrame()
    if displayFrame then
        return
    end

    if not displayAnchorFrame then
        displayAnchorFrame = CreateFrame("Frame", ADDON_NAME .. "DisplayAnchorFrame", UIParent)
        displayAnchorFrame:SetSize(1, 1)
        displayAnchorFrame:EnableMouse(false)
        displayAnchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    displayFrame = CreateFrame("Frame", ADDON_NAME .. "DisplayFrame", UIParent)
    displayFrame:SetSize(MIN_DISPLAY_TEXT_WIDTH + (DISPLAY_HORIZONTAL_PADDING * 2), 60)
    displayFrame:SetClampedToScreen(true)
    displayFrame:SetMovable(true)
    displayFrame:EnableMouse(false)
    displayFrame:RegisterForDrag("LeftButton")
    displayFrame:SetFrameStrata("DIALOG")
    displayFrame:SetFrameLevel(200)

    displayFrame:SetScript("OnDragStart", function(self)
        if not db or not db.testMode then
            return
        end

        StartDisplayDrag()
    end)

    displayFrame:SetScript("OnDragStop", function(self)
        StopDisplayDrag(true)
    end)

    displayFrame.entryBlocks = {}
    for entryIndex = 1, MAX_SUPPORTED_ENTRIES do
        local entryBlock = {}

        entryBlock.label = displayFrame:CreateFontString(nil, "OVERLAY")
        entryBlock.label:SetWidth(DISPLAY_TEXT_RENDER_WIDTH)
        ConfigureDisplayFontString(entryBlock.label)
        ApplyDisplayLabelFont(entryBlock.label)
        entryBlock.label:SetTextColor(unpack(LABEL_COLOR))

        entryBlock.value = displayFrame:CreateFontString(nil, "OVERLAY")
        entryBlock.value:SetWidth(DISPLAY_TEXT_RENDER_WIDTH)
        ConfigureDisplayFontString(entryBlock.value)
        entryBlock.value:SetFontObject(GameFontHighlightLarge)
        entryBlock.value:SetTextColor(unpack(VALUE_COLOR))

        displayFrame.entryBlocks[entryIndex] = entryBlock
    end

    displayFrame.measureLine = displayFrame:CreateFontString(nil, "OVERLAY")
    ConfigureDisplayFontString(displayFrame.measureLine)
    displayFrame.measureLine:Hide()
    displayFrame.originHandle = CreateFrame("Frame", nil, displayFrame)
    displayFrame.originHandle:SetSize(1, 1)
    displayFrame.originHandle:EnableMouse(false)
    displayFrame.originOffsetX = 0
    displayFrame.originOffsetY = 0

    displayFrame:Hide()
end

local function CreateCurrentPercentDisplayFrame()
    if currentPercentFrame then
        return
    end

    currentPercentFrame = CreateFrame("Frame", ADDON_NAME .. "CurrentPercentFrame", UIParent)
    currentPercentFrame:SetSize(180, 54)
    currentPercentFrame:SetClampedToScreen(true)
    currentPercentFrame:SetMovable(true)
    currentPercentFrame:EnableMouse(false)
    currentPercentFrame:RegisterForDrag("LeftButton")
    currentPercentFrame:SetFrameStrata("DIALOG")
    currentPercentFrame:SetFrameLevel(210)

    currentPercentFrame:SetScript("OnDragStart", function(self)
        if not db or not db.testMode or not db.currentPercentEnabled then
            return
        end

        self:StartMoving()
    end)

    currentPercentFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveCurrentPercentDisplayPosition()
    end)

    currentPercentFrame.label = currentPercentFrame:CreateFontString(nil, "OVERLAY")
    currentPercentFrame.label:SetPoint("TOPLEFT", currentPercentFrame, "TOPLEFT", 0, 0)
    currentPercentFrame.label:SetPoint("TOPRIGHT", currentPercentFrame, "TOPRIGHT", 0, 0)
    currentPercentFrame.label:SetJustifyH("CENTER")
    currentPercentFrame.label:SetFontObject(GameFontNormalSmall)
    currentPercentFrame.label:SetTextColor(unpack(LABEL_COLOR))
    currentPercentFrame.label:SetText("Current Trash %")

    currentPercentFrame.text = currentPercentFrame:CreateFontString(nil, "OVERLAY")
    currentPercentFrame.text:SetPoint("TOP", currentPercentFrame.label, "BOTTOM", 0, -4)
    currentPercentFrame.text:SetFont(STANDARD_TEXT_FONT, 32, "OUTLINE")
    currentPercentFrame.text:SetTextColor(1, 1, 1, 1)
    currentPercentFrame.text:SetShadowColor(0, 0, 0, 1)
    currentPercentFrame.text:SetShadowOffset(1, -1)
    currentPercentFrame.text:SetText("")

    currentPercentFrame:Hide()
end

local function UpdateCurrentPercentDisplay(challengeMapID, isPreview)
    if not db or not currentPercentFrame then
        return
    end

    if db.currentPercentEnabled ~= true then
        currentPercentFrame:Hide()
        return
    end

    if isPreview then
        currentPercentFrame.text:SetTextColor(1, 1, 1, 1)
        currentPercentFrame.text:SetText("47.35%")
        currentPercentFrame:SetAlpha(0.95)
        currentPercentFrame:Show()
        return
    end

    if not challengeMapID then
        currentPercentFrame:Hide()
        return
    end

    local currentQuantity, totalQuantity = GetCurrentEnemyForcesInfo()
    if totalQuantity <= 0 then
        currentPercentFrame:Hide()
        return
    end

    local percent = (currentQuantity / totalQuantity) * 100
    currentPercentFrame.text:SetFormattedText("%.2f%%", percent)
    if percent >= 100 then
        currentPercentFrame.text:SetTextColor(0.2, 1, 0.2, 1)
    else
        currentPercentFrame.text:SetTextColor(1, 1, 1, 1)
    end
    currentPercentFrame:SetAlpha(1)
    currentPercentFrame:Show()
end

local function MeasureDisplayText(fontObject, text, width)
    if not displayFrame or not displayFrame.measureLine then
        return 0, 0
    end

    displayFrame.measureLine:SetFontObject(fontObject)
    displayFrame.measureLine:SetText(text or "")

    if width and width > 0 then
        displayFrame.measureLine:SetWordWrap(true)
        displayFrame.measureLine:SetWidth(width)
        return math.ceil(displayFrame.measureLine:GetStringWidth() or 0), math.ceil(displayFrame.measureLine:GetStringHeight() or 0)
    end

    displayFrame.measureLine:SetWordWrap(false)
    displayFrame.measureLine:SetWidth(1)
    return math.ceil(displayFrame.measureLine:GetStringWidth() or 0), math.ceil(displayFrame.measureLine:GetStringHeight() or 0)
end

local function MeasureDisplayLabelText(text, width)
    if not displayFrame or not displayFrame.measureLine then
        return 0, 0
    end

    local fontPath, fontSize, fontFlags = GetDisplayLabelFont()
    displayFrame.measureLine:SetFont(fontPath, fontSize, fontFlags)
    displayFrame.measureLine:SetText(text or "")

    if width and width > 0 then
        displayFrame.measureLine:SetWordWrap(true)
        displayFrame.measureLine:SetWidth(width)
        return math.ceil(displayFrame.measureLine:GetStringWidth() or 0), math.ceil(displayFrame.measureLine:GetStringHeight() or 0)
    end

    displayFrame.measureLine:SetWordWrap(false)
    displayFrame.measureLine:SetWidth(1)
    return math.ceil(displayFrame.measureLine:GetStringWidth() or 0), math.ceil(displayFrame.measureLine:GetStringHeight() or 0)
end

local function BuildEntryLayouts(entries)
    local direction = GetConfiguredFlowDirection()
    local layouts = {}
    local minLeft = 0
    local minTop = 0
    local maxRight = 0
    local maxBottom = 0

    for entryIndex, entryData in ipairs(entries) do
        local label = entryData.label or ""
        local value = entryData.value or ""
        local labelTextWidth = 0
        local valueTextWidth = 0

        if label ~= "" then
            labelTextWidth = select(1, MeasureDisplayLabelText(label))
        end

        if value ~= "" then
            valueTextWidth = select(1, MeasureDisplayText(GameFontHighlightLarge, value))
        end

        local labelWidth = label ~= "" and math.max(MIN_DISPLAY_TEXT_WIDTH, labelTextWidth + DISPLAY_TEXT_WIDTH_BUFFER) or MIN_DISPLAY_TEXT_WIDTH
        local valueWidth = value ~= "" and math.max(MIN_DISPLAY_TEXT_WIDTH, valueTextWidth + DISPLAY_TEXT_WIDTH_BUFFER) or MIN_DISPLAY_TEXT_WIDTH
        local blockWidth = math.max(MIN_DISPLAY_TEXT_WIDTH, labelWidth, valueWidth)
        local labelHeight = 0
        local valueHeight = 0

        if label ~= "" then
            _, labelHeight = MeasureDisplayLabelText(label, labelWidth)
        end

        if value ~= "" then
            _, valueHeight = MeasureDisplayText(GameFontHighlightLarge, value, valueWidth)
        end

        local blockHeight = 0
        if labelHeight > 0 then
            blockHeight = blockHeight + labelHeight
        end
        if valueHeight > 0 then
            if blockHeight > 0 then
                blockHeight = blockHeight + DISPLAY_LINE_GAP
            end
            blockHeight = blockHeight + valueHeight
        end
        blockHeight = math.max(blockHeight, 1)

        local left = 0
        local top = 0
        if entryIndex > 1 then
            local previousLayout = layouts[entryIndex - 1]
            if direction == "DOWN" then
                left = previousLayout.left
                top = previousLayout.top + previousLayout.height + ENTRY_BLOCK_GAP
            elseif direction == "UP" then
                left = previousLayout.left
                top = previousLayout.top - ENTRY_BLOCK_GAP - blockHeight
            elseif direction == "RIGHT" then
                left = previousLayout.left + previousLayout.width + ENTRY_BLOCK_GAP
                top = previousLayout.top
            elseif direction == "LEFT" then
                left = previousLayout.left - ENTRY_BLOCK_GAP - blockWidth
                top = previousLayout.top
            end
        end

        layouts[entryIndex] = {
            label = label,
            value = value,
            left = left,
            top = top,
            labelWidth = labelWidth,
            valueWidth = valueWidth,
            width = blockWidth,
            height = blockHeight,
        }

        minLeft = math.min(minLeft, left)
        minTop = math.min(minTop, top)
        maxRight = math.max(maxRight, left + blockWidth)
        maxBottom = math.max(maxBottom, top + blockHeight)
    end

    return layouts, (-minLeft) + DISPLAY_HORIZONTAL_PADDING, (-minTop) + DISPLAY_VERTICAL_PADDING, math.max(MIN_DISPLAY_TEXT_WIDTH + (DISPLAY_HORIZONTAL_PADDING * 2), (maxRight - minLeft) + (DISPLAY_HORIZONTAL_PADDING * 2)), math.max(1, (maxBottom - minTop) + (DISPLAY_VERTICAL_PADDING * 2))
end

local function EnsureDisplayOriginCoordinates()
    if not displayFrame or not db or (db.displayOriginX ~= nil and db.displayOriginY ~= nil) then
        return
    end

    local originX, originY = GetDisplayOriginOffsets()
    if type(originX) ~= "number" or type(originY) ~= "number" then
        return
    end

    db.displayOriginX = Round(originX)
    db.displayOriginY = Round(originY)
    db.point = "TOPLEFT"
    db.relativePoint = "BOTTOMLEFT"
    db.x = db.displayOriginX
    db.y = db.displayOriginY
    ApplyDisplayPosition()
end

local function UpdateDisplay()
    if not db or not displayFrame or not currentPercentFrame then
        return
    end

    UpdateDisplayInteractivity()
    UpdateCurrentPercentDisplayInteractivity()

    local challengeMapID
    local entries

    if db.testMode then
        challengeMapID = ResolvePreviewChallengeMapID()
        entries = BuildPreviewDisplayEntries(challengeMapID)
    else
        challengeMapID = ResolveCurrentChallengeMapID()
        if not challengeMapID then
            displayFrame:Hide()
            UpdateCurrentPercentDisplay(nil, false)
            return
        end

        entries = BuildDisplayEntries(challengeMapID)
        if not entries then
            displayFrame:Hide()
            UpdateCurrentPercentDisplay(challengeMapID, false)
            return
        end
    end

    local entryLayouts, originOffsetX, originOffsetY, frameWidth, frameHeight = BuildEntryLayouts(entries)
    displayFrame.originOffsetX = originOffsetX
    displayFrame.originOffsetY = originOffsetY
    displayFrame:SetWidth(frameWidth)
    displayFrame:SetHeight(frameHeight)
    displayFrame.originHandle:ClearAllPoints()
    displayFrame.originHandle:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", originOffsetX, -originOffsetY)

    for entryIndex, entryBlock in ipairs(displayFrame.entryBlocks) do
        local layout = entryLayouts[entryIndex]
        if layout then
            local blockLeft = originOffsetX + layout.left
            local blockTop = originOffsetY + layout.top

            if layout.label ~= "" then
                entryBlock.label:ClearAllPoints()
                entryBlock.label:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", blockLeft, -blockTop)
                entryBlock.label:SetWidth(DISPLAY_TEXT_RENDER_WIDTH)
                entryBlock.label:SetText(layout.label)
                ApplyDisplayLabelFont(entryBlock.label)
                entryBlock.label:SetTextColor(unpack(LABEL_COLOR))
                entryBlock.label:Show()
            else
                entryBlock.label:Hide()
                entryBlock.label:SetText("")
            end

            if layout.value ~= "" then
                entryBlock.value:ClearAllPoints()
                if layout.label ~= "" then
                    entryBlock.value:SetPoint("TOPLEFT", entryBlock.label, "BOTTOMLEFT", 0, -DISPLAY_LINE_GAP)
                else
                    entryBlock.value:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", blockLeft, -blockTop)
                end
                entryBlock.value:SetWidth(DISPLAY_TEXT_RENDER_WIDTH)
                entryBlock.value:SetText(layout.value)
                entryBlock.value:SetFontObject(GameFontHighlightLarge)
                entryBlock.value:SetTextColor(unpack(VALUE_COLOR))
                entryBlock.value:Show()
            else
                entryBlock.value:Hide()
                entryBlock.value:SetText("")
            end
        else
            entryBlock.label:Hide()
            entryBlock.label:SetText("")
            entryBlock.value:Hide()
            entryBlock.value:SetText("")
        end
    end

    displayFrame:SetAlpha(db.testMode and 0.95 or 1)
    displayFrame:Show()
    ApplyDisplayPosition()
    EnsureDisplayOriginCoordinates()
    UpdateCurrentPercentDisplay(challengeMapID, db.testMode == true)
end

local function QueueDelayedDisplayUpdates()
    if not (C_Timer and C_Timer.After) then
        return
    end

    for _, delay in ipairs({ 0, 0.5, 2.0 }) do
        C_Timer.After(delay, UpdateDisplay)
    end
end

local function UpdateRootStatusText()
    if not rootStatusText then
        return
    end

    if #challengeMapIDs == 0 then
        rootStatusText:SetText("The M+ instance list is still loading from the client. The dropdown will fill automatically once it is ready.")
        if RefreshRootLayout then
            RefreshRootLayout()
        end
        return
    end

    rootStatusText:SetText(string.format(
        "Loaded instances: %d. Pick an instance in the dropdown above and edit up to %d entry slots below.",
        #challengeMapIDs,
        GetConfiguredEntryCount()
    ))

    if RefreshRootLayout then
        RefreshRootLayout()
    end
end

local function SetControlEnabled(control, enabled)
    if not control then
        return
    end

    if enabled then
        if control.Enable then
            control:Enable()
        end
    elseif control.Disable then
        control:Disable()
    end
end

local function SetTestMode(enabled)
    if not db then
        EnsureDatabase()
    end

    db.testMode = enabled and true or false

    if rootPanel and rootPanel.testModeCheckbox then
        rootPanel.testModeCheckbox:SetChecked(db.testMode)
    end

    UpdateDisplay()
end

local function SetDebugMode(enabled)
    if not db then
        EnsureDatabase()
    end

    db.debug = enabled and true or false

    if rootPanel and rootPanel.debugCheckbox then
        rootPanel.debugCheckbox:SetChecked(db.debug)
    end

    UpdateDisplay()
end

local function ToggleTestMode()
    SetTestMode(not (db and db.testMode))
    print(string.format("%s: Display Test Mode %s.", ADDON_TITLE, db.testMode and "enabled" or "disabled"))
end

local function CreateTextBlock(parent, fontObject, text, width, anchorPoint, relativeTo, relativePoint, xOffset, yOffset)
    local block = parent:CreateFontString(nil, "ARTWORK", fontObject)
    if anchorPoint and relativeTo and relativePoint then
        block:SetPoint(anchorPoint, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
    end
    block:SetWidth(width)
    block:SetJustifyH("LEFT")
    block:SetJustifyV("TOP")
    block:SetWordWrap(true)
    block:SetText(text)
    return block
end

local function CreateLabeledEditBox(parent, labelText, maxLetters, anchorPoint, relativeTo, relativePoint, xOffset, yOffset)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if anchorPoint and relativeTo and relativePoint then
        label:SetPoint(anchorPoint, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
    end
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(320, 30)
    if anchorPoint and relativeTo and relativePoint then
        editBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    end
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(maxLetters)
    editBox:SetTextInsets(6, 6, 0, 0)
    editBox.label = label

    local okButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    okButton:SetSize(42, 22)
    okButton:SetPoint("LEFT", editBox, "RIGHT", 8, 0)
    okButton:SetText("OK")
    okButton.editBox = editBox
    okButton:Hide()
    editBox.okButton = okButton

    return editBox
end

local function UpdateEditBoxOkButton(editBox)
    if not editBox or not editBox.okButton then
        return
    end

    if not editBox:IsEnabled() then
        editBox.okButton:Hide()
        return
    end

    local savedText = editBox.savedText or ""
    local currentText = Trim(editBox:GetText())
    if currentText ~= savedText then
        editBox.okButton:Show()
    else
        editBox.okButton:Hide()
    end
end

local function SetEditBoxVisible(editBox, visible)
    if not editBox then
        return
    end

    if visible then
        editBox:Show()
        if editBox.label then
            editBox.label:Show()
        end
        UpdateEditBoxOkButton(editBox)
        return
    end

    editBox:Hide()
    editBox:ClearFocus()
    if editBox.label then
        editBox.label:Hide()
    end
    if editBox.okButton then
        editBox.okButton:Hide()
    end
end

local function GetPreferredRootChallengeMapID()
    if rootPanel and rootPanel.selectedChallengeMapID and challengeMapInfoByID[rootPanel.selectedChallengeMapID] then
        return rootPanel.selectedChallengeMapID
    end

    local storedChallengeMapID = db and tonumber(db.lastSelectedChallengeMapID) or nil
    if storedChallengeMapID and challengeMapInfoByID[storedChallengeMapID] then
        return storedChallengeMapID
    end

    local currentChallengeMapID = ResolveCurrentChallengeMapID()
    if currentChallengeMapID and challengeMapInfoByID[currentChallengeMapID] then
        return currentChallengeMapID
    end

    return challengeMapIDs[1]
end

local function RefreshFlowDirectionDropdown()
    if not rootPanel or not rootPanel.flowDirectionDropdown then
        return
    end

    UIDropDownMenu_Initialize(rootPanel.flowDirectionDropdown, function(_, level)
        if level ~= 1 then
            return
        end

        local currentDirection = GetConfiguredFlowDirection()
        for _, directionKey in ipairs(FLOW_DIRECTION_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = FLOW_DIRECTIONS[directionKey].label
            info.value = directionKey
            info.func = function(button)
                if not db then
                    EnsureDatabase()
                end

                db.flowDirection = NormalizeFlowDirection(button.value)
                UIDropDownMenu_SetSelectedValue(rootPanel.flowDirectionDropdown, db.flowDirection)
                UIDropDownMenu_SetText(rootPanel.flowDirectionDropdown, FLOW_DIRECTIONS[db.flowDirection].label)
                UpdateDisplay()
            end
            info.checked = currentDirection == directionKey
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local currentDirection = GetConfiguredFlowDirection()
    UIDropDownMenu_SetSelectedValue(rootPanel.flowDirectionDropdown, currentDirection)
    UIDropDownMenu_SetText(rootPanel.flowDirectionDropdown, FLOW_DIRECTIONS[currentDirection].label)
end

local function ClearRootEditBoxes(disableBoxes)
    if not rootPanel then
        return
    end

    local visibleEntryCount = GetConfiguredEntryCount()
    for entryIndex = 1, MAX_SUPPORTED_ENTRIES do
        local labelBox = rootPanel.labelBoxes[entryIndex]
        local valueBox = rootPanel.valueBoxes[entryIndex]
        local labelOkButton = labelBox.okButton
        local valueOkButton = valueBox.okButton
        local isVisible = entryIndex <= visibleEntryCount

        labelBox:ClearFocus()
        valueBox:ClearFocus()
        labelBox.savedText = ""
        valueBox.savedText = ""
        labelBox:SetText("")
        valueBox:SetText("")
        labelBox:HighlightText(0, 0)
        valueBox:HighlightText(0, 0)
        labelBox:SetCursorPosition(0)
        valueBox:SetCursorPosition(0)

        SetControlEnabled(labelBox, isVisible and not disableBoxes)
        SetControlEnabled(valueBox, isVisible and not disableBoxes)
        SetControlEnabled(labelOkButton, isVisible and not disableBoxes)
        SetControlEnabled(valueOkButton, isVisible and not disableBoxes)
        SetEditBoxVisible(labelBox, isVisible)
        SetEditBoxVisible(valueBox, isVisible)
    end
end

local function RenderRootEditBoxes(challengeMapID)
    if not rootPanel then
        return
    end

    local hasSelection = challengeMapID and challengeMapInfoByID[challengeMapID]
    if not hasSelection then
        ClearRootEditBoxes(true)
        return
    end

    local instanceConfig = EnsureInstanceConfig(challengeMapID)
    ClearRootEditBoxes(false)

    for entryIndex = 1, MAX_SUPPORTED_ENTRIES do
        local labelBox = rootPanel.labelBoxes[entryIndex]
        local valueBox = rootPanel.valueBoxes[entryIndex]
        local isVisible = entryIndex <= GetConfiguredEntryCount()
        local entry = instanceConfig.entries[entryIndex] or {}

        if isVisible then
            labelBox.savedText = entry.label or ""
            valueBox.savedText = entry.value or ""
            labelBox:SetText(entry.label or "")
            valueBox:SetText(entry.value or "")
            labelBox:HighlightText(0, 0)
            valueBox:HighlightText(0, 0)
            labelBox:SetCursorPosition(0)
            valueBox:SetCursorPosition(0)
            SetEditBoxVisible(labelBox, true)
            SetEditBoxVisible(valueBox, true)
            UpdateEditBoxOkButton(labelBox)
            UpdateEditBoxOkButton(valueBox)
        else
            SetEditBoxVisible(labelBox, false)
            SetEditBoxVisible(valueBox, false)
        end
    end
end

local function RefreshRootSelectionAndFields()
    if not rootPanel then
        return
    end

    local selectedChallengeMapID = rootPanel.selectedChallengeMapID or GetPreferredRootChallengeMapID()
    SelectRootChallengeMapID(selectedChallengeMapID)

    rootPanel.openRenderToken = (rootPanel.openRenderToken or 0) + 1
    local renderToken = rootPanel.openRenderToken

    ClearRootEditBoxes(not (selectedChallengeMapID and challengeMapInfoByID[selectedChallengeMapID]))

    local function RenderIfCurrent()
        if not rootPanel or not rootPanel:IsShown() or rootPanel.openRenderToken ~= renderToken then
            return
        end

        RenderRootEditBoxes(selectedChallengeMapID)
    end

    RenderIfCurrent()
    C_Timer.After(0, RenderIfCurrent)
    C_Timer.After(0.05, RenderIfCurrent)
    C_Timer.After(0.15, RenderIfCurrent)
end

SelectRootChallengeMapID = function(challengeMapID)
    if not rootPanel then
        return
    end

    if not challengeMapID or not challengeMapInfoByID[challengeMapID] then
        challengeMapID = GetPreferredRootChallengeMapID()
    end

    rootPanel.selectedChallengeMapID = challengeMapID
    if db then
        db.lastSelectedChallengeMapID = challengeMapID or 0
    end

    if rootPanel.instanceDropdown then
        if challengeMapID and challengeMapInfoByID[challengeMapID] then
            UIDropDownMenu_SetSelectedValue(rootPanel.instanceDropdown, challengeMapID)
            UIDropDownMenu_SetText(rootPanel.instanceDropdown, challengeMapInfoByID[challengeMapID].name)
        else
            UIDropDownMenu_SetSelectedValue(rootPanel.instanceDropdown, nil)
            UIDropDownMenu_SetText(rootPanel.instanceDropdown, "No M+ instance available")
        end
    end

    if rootPanel:IsShown() then
        RenderRootEditBoxes(challengeMapID)
    else
        ClearRootEditBoxes(not (challengeMapID and challengeMapInfoByID[challengeMapID]))
    end

    UpdateDisplay()
end

local function RefreshInstanceDropdown()
    if not rootPanel or not rootPanel.instanceDropdown then
        return
    end

    UIDropDownMenu_Initialize(rootPanel.instanceDropdown, function(_, level)
        if level ~= 1 then
            return
        end

        for _, challengeMapID in ipairs(challengeMapIDs) do
            local mapInfo = challengeMapInfoByID[challengeMapID]
            local info = UIDropDownMenu_CreateInfo()
            info.text = mapInfo.name
            info.value = challengeMapID
            info.func = function(button)
                SelectRootChallengeMapID(button.value)
            end
            info.checked = rootPanel.selectedChallengeMapID == challengeMapID
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    SelectRootChallengeMapID(rootPanel.selectedChallengeMapID)
end

local function SaveEditBoxValue(editBox)
    if not db or not editBox or not editBox.panel then
        return
    end

    local challengeMapID = editBox.panel.selectedChallengeMapID
    if not challengeMapID then
        return
    end

    local instanceConfig = EnsureInstanceConfig(challengeMapID)
    local entry = instanceConfig.entries[editBox.entryIndex]
    if not entry then
        return
    end

    entry[editBox.fieldKey] = Trim(editBox:GetText())
    editBox.savedText = entry[editBox.fieldKey]
    UpdateEditBoxOkButton(editBox)
    UpdateDisplay()
end

local function AttachRootEditBoxHandlers(editBox)
    if not editBox then
        return
    end

    editBox:SetScript("OnEnterPressed", function(self)
        SaveEditBoxValue(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", SaveEditBoxValue)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        RenderRootEditBoxes(self.panel and self.panel.selectedChallengeMapID)
    end)
    editBox:SetScript("OnTextChanged", function(self)
        UpdateEditBoxOkButton(self)
    end)

    if editBox.okButton then
        editBox.okButton:SetScript("OnClick", function(self)
            local targetEditBox = self.editBox
            if not targetEditBox then
                return
            end

            SaveEditBoxValue(targetEditBox)
            targetEditBox:ClearFocus()
        end)
    end
end

RefreshRootLayout = function()
    if not rootPanel or not rootPanel.content then
        return
    end

    local content = rootPanel.content
    local y = 16

    rootPanel.titleText:ClearAllPoints()
    rootPanel.titleText:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -y)
    y = y + math.max(24, rootPanel.titleText:GetStringHeight())

    rootPanel.introText:ClearAllPoints()
    rootPanel.introText:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 12))
    y = y + 12 + math.max(36, rootPanel.introText:GetStringHeight())

    rootStatusText:ClearAllPoints()
    rootStatusText:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 16))
    y = y + 16 + math.max(20, rootStatusText:GetStringHeight())

    rootPanel.dropdownLabel:ClearAllPoints()
    rootPanel.dropdownLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 24))
    y = y + 24 + math.max(16, rootPanel.dropdownLabel:GetStringHeight())

    rootPanel.instanceDropdown:ClearAllPoints()
    rootPanel.instanceDropdown:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 2))
    y = y + 38

    rootPanel.dropdownHelpText:ClearAllPoints()
    rootPanel.dropdownHelpText:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 12))
    y = y + 12 + math.max(18, rootPanel.dropdownHelpText:GetStringHeight())

    local leftColumnX = 12
    local rightColumnX = 292
    local helpTextXOffset = 20
    local helpTextWidth = 220
    local sliderXOffset = -2

    local checkboxRowHeight = 40
    local helpTextTopGap = 4

    local leftColumnY = y
    rootPanel.testModeCheckbox:ClearAllPoints()
    rootPanel.testModeCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX, -(leftColumnY + 20))
    leftColumnY = leftColumnY + checkboxRowHeight

    rootPanel.testModeHelpText:ClearAllPoints()
    rootPanel.testModeHelpText:SetWidth(helpTextWidth)
    rootPanel.testModeHelpText:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX + helpTextXOffset, -(leftColumnY + helpTextTopGap))
    leftColumnY = leftColumnY + helpTextTopGap + math.max(18, rootPanel.testModeHelpText:GetStringHeight())

    rootPanel.debugCheckbox:ClearAllPoints()
    rootPanel.debugCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX, -(leftColumnY + 20))
    leftColumnY = leftColumnY + checkboxRowHeight

    rootPanel.debugHelpText:ClearAllPoints()
    rootPanel.debugHelpText:SetWidth(helpTextWidth)
    rootPanel.debugHelpText:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX + helpTextXOffset, -(leftColumnY + helpTextTopGap))
    leftColumnY = leftColumnY + helpTextTopGap + math.max(18, rootPanel.debugHelpText:GetStringHeight())

    local rightColumnY = y
    rootPanel.currentPercentCheckbox:ClearAllPoints()
    rootPanel.currentPercentCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", rightColumnX, -(rightColumnY + 20))
    rightColumnY = rightColumnY + checkboxRowHeight

    rootPanel.currentPercentHelpText:ClearAllPoints()
    rootPanel.currentPercentHelpText:SetWidth(helpTextWidth)
    rootPanel.currentPercentHelpText:SetPoint("TOPLEFT", content, "TOPLEFT", rightColumnX + helpTextXOffset, -(rightColumnY + helpTextTopGap))
    rightColumnY = rightColumnY + helpTextTopGap + math.max(18, rootPanel.currentPercentHelpText:GetStringHeight())

    local sharedSliderY = math.max(leftColumnY, rightColumnY)

    rootPanel.scaleSlider:ClearAllPoints()
    rootPanel.scaleSlider:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX + sliderXOffset, -(sharedSliderY + 24))

    rootPanel.currentPercentScaleSlider:ClearAllPoints()
    rootPanel.currentPercentScaleSlider:SetPoint("TOPLEFT", content, "TOPLEFT", rightColumnX + sliderXOffset, -(sharedSliderY + 24))

    local entrySettingsY = sharedSliderY + 60

    rootPanel.entryCountSlider:ClearAllPoints()
    rootPanel.entryCountSlider:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX + sliderXOffset, -(entrySettingsY + 24))

    rootPanel.entryCountHelpText:ClearAllPoints()
    rootPanel.entryCountHelpText:SetWidth(helpTextWidth)
    rootPanel.entryCountHelpText:SetPoint("TOPLEFT", content, "TOPLEFT", leftColumnX + helpTextXOffset, -(entrySettingsY + 60))
    local leftSettingsBottomY = entrySettingsY + 60 + math.max(18, rootPanel.entryCountHelpText:GetStringHeight())

    rootPanel.flowDirectionLabel:ClearAllPoints()
    rootPanel.flowDirectionLabel:SetPoint("TOPLEFT", content, "TOPLEFT", rightColumnX, -(entrySettingsY + 18))
    local rightSettingsBottomY = entrySettingsY + 18 + math.max(16, rootPanel.flowDirectionLabel:GetStringHeight())

    rootPanel.flowDirectionDropdown:ClearAllPoints()
    rootPanel.flowDirectionDropdown:SetPoint("TOPLEFT", content, "TOPLEFT", rightColumnX - 16, -(entrySettingsY + 28))
    rightSettingsBottomY = entrySettingsY + 60

    rootPanel.flowDirectionHelpText:ClearAllPoints()
    rootPanel.flowDirectionHelpText:SetWidth(helpTextWidth)
    rootPanel.flowDirectionHelpText:SetPoint("TOPLEFT", content, "TOPLEFT", rightColumnX + helpTextXOffset, -(entrySettingsY + 68))
    rightSettingsBottomY = entrySettingsY + 68 + math.max(18, rootPanel.flowDirectionHelpText:GetStringHeight())

    y = math.max(leftSettingsBottomY, rightSettingsBottomY)

    for entryIndex = 1, GetConfiguredEntryCount() do
        local labelBox = rootPanel.labelBoxes[entryIndex]
        local valueBox = rootPanel.valueBoxes[entryIndex]

        labelBox.label:ClearAllPoints()
        labelBox.label:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 24))
        y = y + 24 + math.max(16, labelBox.label:GetStringHeight())

        labelBox:ClearAllPoints()
        labelBox:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 8))
        y = y + 8 + 30

        valueBox.label:ClearAllPoints()
        valueBox.label:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 22))
        y = y + 22 + math.max(16, valueBox.label:GetStringHeight())

        valueBox:ClearAllPoints()
        valueBox:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 8))
        y = y + 8 + 30
    end

    rootPanel.resetButton:ClearAllPoints()
    rootPanel.resetButton:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 24))
    y = y + 24 + 24

    rootPanel.currentPercentResetButton:ClearAllPoints()
    rootPanel.currentPercentResetButton:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 10))
    y = y + 10 + 24

    rootPanel.footerText:ClearAllPoints()
    rootPanel.footerText:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -(y + 12))
    y = y + 12 + math.max(18, rootPanel.footerText:GetStringHeight())

    content:SetHeight(math.max(y + 24, 900))

    if UpdateRootScrollBar then
        UpdateRootScrollBar()
    end
end

UpdateRootScrollBar = function()
    if not rootPanel or not rootPanel.scrollFrame or not rootPanel.scrollBar or not rootPanel.content then
        return
    end

    local viewHeight = rootPanel.scrollFrame:GetHeight() or 0
    local contentHeight = rootPanel.content:GetHeight() or 0
    local maxScroll = math.max(0, contentHeight - viewHeight)
    local currentValue = rootPanel.scrollBar:GetValue() or 0

    rootPanel.isUpdatingScrollBar = true
    rootPanel.scrollBar:SetMinMaxValues(0, maxScroll)
    rootPanel.scrollBar:SetValue(math.min(currentValue, maxScroll))
    rootPanel.isUpdatingScrollBar = false
    rootPanel.scrollFrame:SetVerticalScroll(rootPanel.scrollBar:GetValue())

    if rootPanel.scrollBar.ScrollUpButton then
        rootPanel.scrollBar.ScrollUpButton:SetEnabled(rootPanel.scrollBar:GetValue() > 0)
    end

    if rootPanel.scrollBar.ScrollDownButton then
        rootPanel.scrollBar.ScrollDownButton:SetEnabled(rootPanel.scrollBar:GetValue() < maxScroll)
    end
end

local function CreateRootOptionsPanel()
    if rootPanel or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    rootPanel = CreateFrame("Frame", ADDON_NAME .. "RootOptionsPanel", UIParent)
    rootPanel.name = ADDON_TITLE
    rootPanel.labelBoxes = {}
    rootPanel.valueBoxes = {}

    rootPanel.scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "RootScrollFrame", rootPanel)
    rootPanel.scrollFrame:SetPoint("TOPLEFT", rootPanel, "TOPLEFT", 8, -8)
    rootPanel.scrollFrame:SetPoint("BOTTOMRIGHT", rootPanel, "BOTTOMRIGHT", -34, 8)
    rootPanel.scrollFrame:EnableMouseWheel(true)
    rootPanel.scrollFrame:SetClipsChildren(true)

    rootPanel.scrollBar = CreateFrame("Slider", ADDON_NAME .. "RootScrollBar", rootPanel, "UIPanelScrollBarTemplate")
    rootPanel.scrollBar:SetPoint("TOPLEFT", rootPanel.scrollFrame, "TOPRIGHT", 4, -16)
    rootPanel.scrollBar:SetPoint("BOTTOMLEFT", rootPanel.scrollFrame, "BOTTOMRIGHT", 4, 16)
    rootPanel.scrollBar:SetScript("OnValueChanged", function(self, value)
        if rootPanel.isUpdatingScrollBar then
            return
        end

        rootPanel.scrollFrame:SetVerticalScroll(value)

        local minValue, maxValue = self:GetMinMaxValues()
        if self.ScrollUpButton then
            self.ScrollUpButton:SetEnabled(value > minValue)
        end

        if self.ScrollDownButton then
            self.ScrollDownButton:SetEnabled(value < maxValue)
        end
    end)
    rootPanel.scrollBar:SetMinMaxValues(0, 0)
    rootPanel.scrollBar:SetValueStep(40)
    rootPanel.scrollBar:SetObeyStepOnDrag(true)
    rootPanel.scrollBar:SetValue(0)
    rootPanel.scrollBar:SetWidth(16)

    if rootPanel.scrollBar.ScrollUpButton then
        rootPanel.scrollBar.ScrollUpButton:SetScript("OnClick", function()
            rootPanel.scrollBar:SetValue((rootPanel.scrollBar:GetValue() or 0) - 40)
        end)
    end

    if rootPanel.scrollBar.ScrollDownButton then
        rootPanel.scrollBar.ScrollDownButton:SetScript("OnClick", function()
            rootPanel.scrollBar:SetValue((rootPanel.scrollBar:GetValue() or 0) + 40)
        end)
    end

    rootPanel.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = rootPanel.scrollBar
        if not scrollBar then
            return
        end

        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local currentValue = scrollBar:GetValue()
        local nextValue = currentValue - (delta * 40)
        if nextValue < minValue then
            nextValue = minValue
        elseif nextValue > maxValue then
            nextValue = maxValue
        end

        scrollBar:SetValue(nextValue)
    end)
    rootPanel.scrollFrame:SetScript("OnSizeChanged", function()
        UpdateRootScrollBar()
    end)

    rootPanel.content = CreateFrame("Frame", ADDON_NAME .. "RootScrollContent", rootPanel.scrollFrame)
    rootPanel.content:SetPoint("TOPLEFT", rootPanel.scrollFrame, "TOPLEFT", 0, 0)
    rootPanel.content:SetSize(OPTIONS_CONTENT_WIDTH + 32, 900)
    rootPanel.scrollFrame:SetScrollChild(rootPanel.content)

    rootPanel.titleText = CreateTextBlock(
        rootPanel.content,
        "GameFontNormalLarge",
        ADDON_TITLE,
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.introText = CreateTextBlock(
        rootPanel.content,
        "GameFontHighlight",
        "This addon shows up to 20 freely labeled percentage entries per M+ instance, lets you choose how many are active, and controls whether extra entries expand down, up, left, or right from entry 1. In display test mode you can move both displays with the left mouse button.",
        OPTIONS_TEXT_WIDTH
    )

    rootStatusText = CreateTextBlock(
        rootPanel.content,
        "GameFontHighlight",
        "",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.dropdownLabel = rootPanel.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rootPanel.dropdownLabel:SetText("Instance")

    rootPanel.instanceDropdown = CreateFrame("Frame", ADDON_NAME .. "InstanceDropdown", rootPanel.content, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(rootPanel.instanceDropdown, 260)
    UIDropDownMenu_SetText(rootPanel.instanceDropdown, "Select instance")

    rootPanel.dropdownHelpText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "First choose the instance in the dropdown, then edit the entry slots below. Only filled entries are shown in the display.",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.testModeCheckbox = CreateFrame("CheckButton", nil, rootPanel.content, "ChatConfigCheckButtonTemplate")
    rootPanel.testModeCheckbox.Text:SetText("Display Test Mode")
    rootPanel.testModeCheckbox:SetScript("OnClick", function(self)
        SetTestMode(self:GetChecked())
    end)

    rootPanel.testModeHelpText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "In test mode both displays stay visible outside M+ and can be moved freely.",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.debugCheckbox = CreateFrame("CheckButton", nil, rootPanel.content, "ChatConfigCheckButtonTemplate")
    rootPanel.debugCheckbox.Text:SetText("Debug")
    rootPanel.debugCheckbox:SetScript("OnClick", function(self)
        SetDebugMode(self:GetChecked())
    end)

    rootPanel.debugHelpText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "When enabled, dungeon notes can appear in any dungeon difficulty. When disabled, they only appear in Mythic Keystone runs.",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.currentPercentCheckbox = CreateFrame("CheckButton", nil, rootPanel.content, "ChatConfigCheckButtonTemplate")
    rootPanel.currentPercentCheckbox.Text:SetText("Enable Current Trash % Display")
    rootPanel.currentPercentCheckbox:SetScript("OnClick", function(self)
        if not db then
            EnsureDatabase()
        end

        db.currentPercentEnabled = self:GetChecked() == true
        db.currentPercentOptInConfirmed = true
        UpdateDisplay()
    end)

    rootPanel.currentPercentHelpText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "Shows the exact current Enemy Forces percent as a separate movable white text display.",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.scaleSlider = CreateFrame("Slider", nil, rootPanel.content, "OptionsSliderTemplate")
    rootPanel.scaleSlider:SetWidth(220)
    rootPanel.scaleSlider:SetMinMaxValues(0.5, 5.0)
    rootPanel.scaleSlider:SetValueStep(0.1)
    rootPanel.scaleSlider:SetObeyStepOnDrag(true)
    rootPanel.scaleSlider.Low:SetText("0.5")
    rootPanel.scaleSlider.High:SetText("5.0")
    rootPanel.scaleSlider:SetScript("OnValueChanged", function(self, value)
        if not db then
            return
        end

        value = tonumber(string.format("%.1f", value)) or 1
        db.scale = value
        self.Text:SetText(string.format("Main Display Scale: %.1f", value))
        ApplyDisplayPosition()
        UpdateDisplay()
    end)

    rootPanel.currentPercentScaleSlider = CreateFrame("Slider", nil, rootPanel.content, "OptionsSliderTemplate")
    rootPanel.currentPercentScaleSlider:SetWidth(220)
    rootPanel.currentPercentScaleSlider:SetMinMaxValues(0.5, 5.0)
    rootPanel.currentPercentScaleSlider:SetValueStep(0.1)
    rootPanel.currentPercentScaleSlider:SetObeyStepOnDrag(true)
    rootPanel.currentPercentScaleSlider.Low:SetText("0.5")
    rootPanel.currentPercentScaleSlider.High:SetText("5.0")
    rootPanel.currentPercentScaleSlider:SetScript("OnValueChanged", function(self, value)
        if not db then
            return
        end

        value = tonumber(string.format("%.1f", value)) or 1
        db.currentPercentScale = value
        self.Text:SetText(string.format("Trash %% Scale: %.1f", value))
        ApplyCurrentPercentDisplayPosition()
        UpdateDisplay()
    end)

    rootPanel.entryCountSlider = CreateFrame("Slider", nil, rootPanel.content, "OptionsSliderTemplate")
    rootPanel.entryCountSlider:SetWidth(220)
    rootPanel.entryCountSlider:SetMinMaxValues(1, MAX_SUPPORTED_ENTRIES)
    rootPanel.entryCountSlider:SetValueStep(1)
    rootPanel.entryCountSlider:SetObeyStepOnDrag(true)
    rootPanel.entryCountSlider.Low:SetText("1")
    rootPanel.entryCountSlider.High:SetText(tostring(MAX_SUPPORTED_ENTRIES))
    rootPanel.entryCountSlider:SetScript("OnValueChanged", function(self, value)
        if not db then
            return
        end

        value = ClampEntryCount(value)
        db.entryCount = value
        self.Text:SetText(string.format("Shown Entries: %d", value))
        UpdateRootStatusText()
        RefreshRootSelectionAndFields()
        RefreshRootLayout()
        UpdateDisplay()
    end)

    rootPanel.entryCountHelpText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "Controls how many entry slots are visible here and used in the display.",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel.flowDirectionLabel = rootPanel.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rootPanel.flowDirectionLabel:SetText("Additional Entries Direction")

    rootPanel.flowDirectionDropdown = CreateFrame("Frame", ADDON_NAME .. "FlowDirectionDropdown", rootPanel.content, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(rootPanel.flowDirectionDropdown, 180)
    UIDropDownMenu_SetText(rootPanel.flowDirectionDropdown, FLOW_DIRECTIONS[DEFAULT_FLOW_DIRECTION].label)

    rootPanel.flowDirectionHelpText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "Entry 1 keeps the saved position. Entries 2 and higher expand in the selected direction.",
        OPTIONS_TEXT_WIDTH
    )

    for entryIndex = 1, MAX_SUPPORTED_ENTRIES do
        local labelBox = CreateLabeledEditBox(
            rootPanel.content,
            string.format("%d. Entry - Note Text", entryIndex),
            80
        )
        labelBox.panel = rootPanel
        labelBox.entryIndex = entryIndex
        labelBox.fieldKey = "label"

        local valueBox = CreateLabeledEditBox(
            rootPanel.content,
            string.format("%d. Entry - Percent Value", entryIndex),
            20
        )
        valueBox.panel = rootPanel
        valueBox.entryIndex = entryIndex
        valueBox.fieldKey = "value"

        AttachRootEditBoxHandlers(labelBox)
        AttachRootEditBoxHandlers(valueBox)

        rootPanel.labelBoxes[entryIndex] = labelBox
        rootPanel.valueBoxes[entryIndex] = valueBox
    end

    rootPanel.resetButton = CreateFrame("Button", nil, rootPanel.content, "UIPanelButtonTemplate")
    rootPanel.resetButton:SetSize(200, 24)
    rootPanel.resetButton:SetText("Reset Main Display Position")
    rootPanel.resetButton:SetScript("OnClick", function()
        ResetDisplayPosition()
        UpdateDisplay()
    end)

    rootPanel.currentPercentResetButton = CreateFrame("Button", nil, rootPanel.content, "UIPanelButtonTemplate")
    rootPanel.currentPercentResetButton:SetSize(200, 24)
    rootPanel.currentPercentResetButton:SetText("Reset Trash % Position")
    rootPanel.currentPercentResetButton:SetScript("OnClick", function()
        ResetCurrentPercentDisplayPosition()
        UpdateDisplay()
    end)

    rootPanel.footerText = CreateTextBlock(
        rootPanel.content,
        "GameFontDisableSmall",
        "Tip: values automatically get a % added in the display. Entry 1 stays anchored at the saved position while additional entries expand in the selected direction.",
        OPTIONS_TEXT_WIDTH
    )

    rootPanel:SetScript("OnShow", function()
        local currentOptionsChallengeMapID = ResolveCurrentInstanceChallengeMapIDForOptions()
        if currentOptionsChallengeMapID then
            rootPanel.selectedChallengeMapID = currentOptionsChallengeMapID
        end

        UpdateRootStatusText()
        RefreshInstanceDropdown()
        RefreshRootSelectionAndFields()
        rootPanel.testModeCheckbox:SetChecked(db and db.testMode == true)
        rootPanel.debugCheckbox:SetChecked(db and db.debug == true)
        rootPanel.currentPercentCheckbox:SetChecked(db == nil or db.currentPercentEnabled == true)
        rootPanel.scaleSlider:SetValue(db and db.scale or 1)
        rootPanel.scaleSlider.Text:SetText(string.format("Main Display Scale: %.1f", db and db.scale or 1))
        rootPanel.currentPercentScaleSlider:SetValue(db and db.currentPercentScale or 1)
        rootPanel.currentPercentScaleSlider.Text:SetText(string.format("Trash %% Scale: %.1f", db and db.currentPercentScale or 1))
        rootPanel.entryCountSlider:SetValue(GetConfiguredEntryCount())
        rootPanel.entryCountSlider.Text:SetText(string.format("Shown Entries: %d", GetConfiguredEntryCount()))
        RefreshFlowDirectionDropdown()
        RefreshRootLayout()
        UpdateRootScrollBar()
    end)

    rootCategory = Settings.RegisterCanvasLayoutCategory(rootPanel, ADDON_TITLE, ADDON_TITLE)
    Settings.RegisterAddOnCategory(rootCategory)
    UpdateRootStatusText()
    RefreshRootLayout()
end

local function EnsureDungeonOptionPanels()
    CreateRootOptionsPanel()
    if not rootCategory then
        return
    end

    RefreshInstanceDropdown()
    UpdateRootStatusText()
end

local function OpenOptions()
    if rootCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(rootCategory:GetID(), ADDON_TITLE)
    end
end

SLASH_MPLUSPERCENTAGEPOINTOFNORETURN1 = "/mppp"
SlashCmdList.MPLUSPERCENTAGEPOINTOFNORETURN = function()
    OpenOptions()
end

SLASH_MPLUSPERCENTAGEPOINTOFNORETURNTEST1 = "/mppptest"
SlashCmdList.MPLUSPERCENTAGEPOINTOFNORETURNTEST = function()
    ToggleTestMode()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("SCENARIO_UPDATE")
eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddonName = ...
        if loadedAddonName == ADDON_NAME then
            EnsureDatabase()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if not db then
            EnsureDatabase()
        end

        RefreshMapCache()
        CreateDisplayFrame()
        CreateCurrentPercentDisplayFrame()
        ApplyDisplayPosition()
        ApplyCurrentPercentDisplayPosition()
        EnsureDungeonOptionPanels()
        UpdateDisplay()
        QueueDelayedDisplayUpdates()
        return
    end

    if event == "CHALLENGE_MODE_MAPS_UPDATE" then
        RefreshMapCache()
        EnsureDungeonOptionPanels()
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START" then
        QueueDelayedDisplayUpdates()
    end

    UpdateDisplay()
end)
