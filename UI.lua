local _, addon = ...
local Roulette = addon.Roulette
local TWO_PI = math.pi * 2
local gold = {1, 0.79, 0.31}
local muted = {0.59, 0.64, 0.66}
local backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1
}

local function label(parent, text, font, point, relative, relativePoint, x, y)
    local region = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    region:SetPoint(point, relative, relativePoint, x, y)
    region:SetText(text)
    return region
end

local function button(parent, text, width, onClick)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 28)
    control:SetText(text)
    control:SetScript("OnClick", onClick)
    return control
end

local function tooltip(control, text)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(text) == "function" and text(self) or text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function Roulette:ShowWindow()
    if not self.window then
        return
    end
    self.window:Show()
    self:Render()
end

function Roulette:HighlightWheel(index, turns)
    local window = self.window
    local count = #self.entries
    for nodeIndex, node in ipairs(window.nodes) do
        if nodeIndex <= count then
            if nodeIndex == index then
                node.fill:SetVertexColor(gold[1], gold[2], gold[3], 1)
                node.number:SetTextColor(0.08, 0.09, 0.1)
            else
                node.fill:SetVertexColor(0.16, 0.21, 0.22, 1)
                node.number:SetTextColor(0.86, 0.9, 0.89)
            end
        end
    end
    if index and self.entries[index] then
        window.current:SetText(self.entries[index].name:gsub("%-", "\n", 1))
    end
    local angle = math.pi / 2 - (turns or 0) * TWO_PI
    window.pointer:ClearAllPoints()
    window.pointer:SetPoint("CENTER", window.wheel, "CENTER", math.cos(angle) * 182, math.sin(angle) * 182)
end

function Roulette:AnimateWheel()
    if self.state ~= "spinning" or #self.entries == 0 then
        return
    end
    local progress = math.min(1, math.max(0, (GetTime() - self.spinStarted) / self.spinDuration))
    local turns = (5 + (self.winnerIndex - 1) / #self.entries) * (1 - (1 - progress) ^ 4)
    local index = math.floor(turns * #self.entries + 0.5) % #self.entries + 1
    self:HighlightWheel(index, turns)
end

function Roulette:Render()
    local window = self.window
    if not window then
        return
    end
    local signingUp = self.state == "signup"
    local spinning = self.state == "spinning"
    local active = signingUp or spinning
    local count = #self.entries
    window.allowHealers:SetChecked(PowerInfusionRouletteDB.allowHealers == true)
    window.allowTanks:SetChecked(PowerInfusionRouletteDB.allowTanks == true)
    window.count:SetText("PLAYERS  /  " .. count)
    if signingUp then
        window.status:SetText("SIGNUPS OPEN")
        window.clock:SetText(math.max(0, math.ceil(self.deadline - GetTime())) .. "s")
        window.result:SetText("Accepting entries")
    elseif spinning then
        window.status:SetText("ROULETTE IN MOTION")
        window.clock:SetText("")
        window.result:SetText("Choosing a PI target")
    elseif self.state == "finished" and self.winner then
        window.status:SetText("PI TARGET SELECTED")
        window.clock:SetText("")
        window.result:SetText("Winner")
    else
        window.status:SetText(self.state == "finished" and "NO ENTRIES" or "READY")
        window.clock:SetText("")
        window.result:SetText("Power Infusion")
    end
    window.start:SetText(active and "Start roulette" or "New round")
    window.start:SetEnabled(not spinning and (not signingUp or count > 0))
    window.cancel:SetEnabled(active)
    window.empty:SetShown(count == 0)
    window.scrollChild:SetHeight(math.max(1, count * 34))
    for index, entry in ipairs(self.entries) do
        local row = window.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, window.scrollChild)
            row:SetSize(250, 32)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 34)
            row.background = row:CreateTexture(nil, "BACKGROUND")
            row.background:SetAllPoints()
            row.background:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.035 or 0.065)
            row.number = label(row, index, "GameFontNormalSmall", "LEFT", row, "LEFT", 8, 0)
            row.name = label(row, "", "GameFontHighlightSmall", "LEFT", row, "LEFT", 34, 0)
            row.name:SetWidth(177)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.remove = CreateFrame("Button", nil, row)
            row.remove:SetSize(22, 22)
            row.remove:SetPoint("RIGHT", -4, 0)
            row.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            row.remove:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            row.remove:SetScript("OnClick", function(self)
                Roulette:Exclude(self:GetParent().guid)
            end)
            tooltip(row.remove, function(self)
                return "Exclude " .. self:GetParent().fullName .. " this round"
            end)
            row:EnableMouse(true)
            tooltip(row, function(self)
                return self.fullName
            end)
            window.rows[index] = row
        end
        row.guid = entry.guid
        row.fullName = entry.name
        row.name:SetText(entry.name)
        row.remove:SetShown(signingUp)
        row:Show()
    end
    for index = count + 1, #window.rows do
        window.rows[index]:Hide()
    end
    for index = 1, math.max(count, #window.nodes) do
        local node = window.nodes[index]
        if index <= count then
            if not node then
                node = CreateFrame("Frame", nil, window.wheel)
                node:SetSize(23, 23)
                node.fill = node:CreateTexture(nil, "BACKGROUND")
                node.fill:SetAllPoints()
                node.fill:SetColorTexture(1, 1, 1)
                local mask = node:CreateMaskTexture()
                mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
                    "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints()
                node.fill:AddMaskTexture(mask)
                node.number = label(node, index, "GameFontHighlightSmall", "CENTER", node, "CENTER", 0, 0)
                node:EnableMouse(true)
                tooltip(node, function(self)
                    return self.fullName
                end)
                window.nodes[index] = node
            end
            node.fullName = self.entries[index].name
            local angle = math.pi / 2 - (index - 1) / count * TWO_PI
            node:ClearAllPoints()
            node:SetPoint("CENTER", window.wheel, "CENTER", math.cos(angle) * 152, math.sin(angle) * 152)
            node:Show()
        elseif node then
            node:Hide()
        end
    end
    window.pointer:SetShown(count > 0)
    if spinning then
        self:AnimateWheel()
    elseif self.state == "finished" and self.winner then
        self:HighlightWheel(self.winnerIndex, (self.winnerIndex - 1) / count)
    else
        self:HighlightWheel(nil, 0)
        window.current:SetText(count > 0 and (count .. " contenders") or "No contenders")
    end
end

function Roulette:CreateWindow()
    if self.window then
        return
    end
    local window = CreateFrame("Frame", "PowerInfusionRouletteWindow", UIParent, "BackdropTemplate")
    self.window = window
    window:SetSize(790, 590)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    window:SetBackdrop(backdrop)
    window:SetBackdropColor(0.055, 0.075, 0.075, 0.98)
    window:SetBackdropBorderColor(0.36, 0.4, 0.37, 1)
    local function fit()
        window:SetScale(math.min(1, (UIParent:GetWidth() - 24) / 790, (UIParent:GetHeight() - 24) / 590))
    end
    fit()
    window:RegisterEvent("DISPLAY_SIZE_CHANGED")
    window:RegisterEvent("UI_SCALE_CHANGED")
    window:SetScript("OnEvent", fit)
    window:SetScript("OnUpdate", function()
        Roulette:AnimateWheel()
    end)
    table.insert(UISpecialFrames, "PowerInfusionRouletteWindow")

    local icon = window:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("TOPLEFT", 22, -20)
    icon:SetTexture(C_Spell.GetSpellTexture(10060) or 135939)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    label(window, "Power Infusion Roulette", "GameFontNormalLarge", "TOPLEFT", window, "TOPLEFT", 72, -21)
    window.status = label(window, "READY", "GameFontHighlightSmall", "TOPLEFT", window, "TOPLEFT", 73, -45)
    window.status:SetTextColor(muted[1], muted[2], muted[3])
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    tooltip(close, "Hide roulette (the round continues)")

    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 22, -77)
    rule:SetPoint("TOPRIGHT", -22, -77)
    rule:SetHeight(1)
    rule:SetColorTexture(0.3, 0.36, 0.33, 1)
    window.count = label(window, "PLAYERS  /  0", "GameFontNormal", "TOPLEFT", window, "TOPLEFT", 23, -98)
    window.clock = label(window, "", "GameFontNormalLarge", "TOPRIGHT", window, "TOPLEFT", 281, -94)
    window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    window.scroll:SetPoint("TOPLEFT", 22, -128)
    window.scroll:SetSize(254, 354)
    window.scrollChild = CreateFrame("Frame", nil, window.scroll)
    window.scrollChild:SetSize(250, 1)
    window.scroll:SetScrollChild(window.scrollChild)
    window.rows = {}
    window.empty = label(window, "No signups yet", "GameFontDisable", "TOPLEFT", window, "TOPLEFT", 30, -147)

    window.wheel = CreateFrame("Frame", nil, window)
    window.wheel:SetSize(408, 408)
    window.wheel:SetPoint("TOPRIGHT", -28, -91)
    window.nodes = {}
    for index = 1, 96 do
        local angle = (index - 1) / 96 * TWO_PI
        local nextAngle = index / 96 * TWO_PI
        local line = window.wheel:CreateLine(nil, "BACKGROUND")
        line:SetThickness(2)
        line:SetColorTexture(0.39, 0.46, 0.41, 0.9)
        line:SetStartPoint("CENTER", math.cos(angle) * 174, math.sin(angle) * 174)
        line:SetEndPoint("CENTER", math.cos(nextAngle) * 174, math.sin(nextAngle) * 174)
    end
    local centerIcon = window.wheel:CreateTexture(nil, "ARTWORK")
    centerIcon:SetSize(56, 56)
    centerIcon:SetPoint("CENTER", 0, 47)
    centerIcon:SetTexture(C_Spell.GetSpellTexture(10060) or 135939)
    centerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    window.result = label(window.wheel, "Power Infusion", "GameFontNormal", "CENTER", window.wheel, "CENTER", 0, -2)
    window.current = label(window.wheel, "No contenders", "GameFontHighlight", "TOP", window.result, "BOTTOM", 0, -12)
    window.current:SetWidth(210)
    window.current:SetHeight(58)
    window.current:SetJustifyV("TOP")
    window.pointer = CreateFrame("Frame", nil, window.wheel, "BackdropTemplate")
    window.pointer:SetSize(25, 25)
    window.pointer:SetFrameLevel(window.wheel:GetFrameLevel() + 4)
    window.pointer:SetBackdrop(backdrop)
    window.pointer:SetBackdropBorderColor(gold[1], gold[2], gold[3], 1)
    window.pointer.icon = window.pointer:CreateTexture(nil, "ARTWORK")
    window.pointer.icon:SetPoint("TOPLEFT", 2, -2)
    window.pointer.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    window.pointer.icon:SetTexture(C_Spell.GetSpellTexture(10060) or 135939)

    label(window, "Signup duration", "GameFontHighlightSmall", "BOTTOMLEFT", window, "BOTTOMLEFT", 24, 29)
    local timeout = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    timeout:SetSize(48, 24)
    timeout:SetPoint("BOTTOMLEFT", 141, 24)
    timeout:SetAutoFocus(false)
    timeout:SetNumeric(true)
    timeout:SetMaxLetters(3)
    timeout:SetText(PowerInfusionRouletteDB.timeout)
    timeout:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    local function applyTimeout()
        Roulette:SetTimeout(timeout:GetText())
        timeout:SetText(PowerInfusionRouletteDB.timeout)
        timeout:ClearFocus()
    end
    timeout:SetScript("OnEnterPressed", applyTimeout)
    tooltip(timeout, "5-300 seconds. Changes apply to the next round.")
    label(window, "sec", "GameFontHighlightSmall", "LEFT", timeout, "RIGHT", 7, 0)
    local apply = button(window, "Apply", 64, applyTimeout)
    apply:SetPoint("LEFT", timeout, "RIGHT", 36, 0)
    for _, setting in ipairs({{
        key = "allowHealers",
        text = "Allow healers to enter",
        x = 22
    }, {
        key = "allowTanks",
        text = "Allow tanks to enter",
        x = 192
    }}) do
        local option = setting.key
        local checkbox = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        checkbox:SetPoint("BOTTOMLEFT", setting.x, 62)
        label(checkbox, setting.text, "GameFontHighlightSmall", "LEFT", checkbox, "RIGHT", 2, 0)
        checkbox:SetScript("OnClick", function(self)
            PowerInfusionRouletteDB[option] = self:GetChecked() == true
            Roulette:Notify()
        end)
        tooltip(checkbox, "Uses assigned group roles. Changes apply to the next round.")
        window[option] = checkbox
    end
    window.cancel = button(window, "Cancel round", 120, function()
        Roulette:Cancel()
    end)
    window.start = button(window, "New round", 190, function()
        if Roulette.state == "signup" then
            Roulette:StartSpin()
        else
            Roulette:Begin()
        end
    end)
    window.start:SetPoint("BOTTOMRIGHT", -24, 22)
    window.cancel:SetPoint("RIGHT", window.start, "LEFT", -10, 0)
    self.OnChanged = self.Render
    self:Render()
    window:Hide()
end
