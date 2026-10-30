local now, priest, knowsPI, grouped, raid, instance = 0, true, true, true, false, false
local chatRestricted, outgoingRestricted = false, false
local roles = {}
local combat, characterMacros, accountMacro = false, {}, nil
local maxCharacterMacros = 30
C_Spell = {
    GetSpellName = function()
        return "Power Infusion"
    end,
    GetSpellTexture = function()
        return 135939
    end
}
function InCombatLockdown()
    return combat
end
function GetNumMacros()
    return accountMacro and 1 or 0, #characterMacros
end
function GetMacroInfo(index)
    local accountCount = accountMacro and 1 or 0
    local macro = index > accountCount and characterMacros[index - accountCount] or accountMacro
    if macro then
        return macro.name, 135939, macro.body
    end
end
function CreateMacro(name, icon, body, perCharacter)
    assert(not combat and perCharacter)
    if #characterMacros >= maxCharacterMacros then
        return 0
    end
    characterMacros[#characterMacros + 1] = {
        name = name,
        body = body
    }
    return (accountMacro and 1 or 0) + #characterMacros
end
function EditMacro(index, name, icon, body)
    local accountCount = accountMacro and 1 or 0
    assert(not combat and index > accountCount)
    characterMacros[index - accountCount].body = body
    return index
end
local messages, printed, frames = {}, {}, {}
local units = {
    player = {"Host", "Realm", "Player-1"},
    party1 = {"Alice", "Realm", "Player-2"},
    party2 = {"Bob", "OtherRealm", "Player-3"}
}
LE_PARTY_CATEGORY_INSTANCE = 2
SlashCmdList = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text)
        printed[#printed + 1] = text
    end
}
function GetTime()
    return now
end
function UnitClass()
    return "Class", priest and "PRIEST" or "MAGE"
end
C_SpellBook = {
    IsSpellKnown = function(spell)
        return knowsPI and spell == 10060
    end
}
function IsInGroup(category)
    return category and instance or (not category and grouped)
end
function IsInRaid()
    return raid
end
function GetNumGroupMembers()
    return 3
end
function GetNumSubgroupMembers()
    return 2
end
function GetNormalizedRealmName()
    return "Realm"
end
function UnitFullName(unit)
    if units[unit] then
        return units[unit][1], units[unit][2]
    end
end
function UnitGUID(unit)
    return units[unit] and units[unit][3]
end
function UnitGroupRolesAssigned(unit)
    return roles[UnitGUID(unit)] or "DAMAGER"
end
C_ChatInfo = {
    SendChatMessage = function(text, channel)
        assert(not chatRestricted)
        messages[#messages + 1] = {text, channel}
    end,
    InChatMessagingLockdown = function()
        return chatRestricted
    end,
    AreOutgoingAddonChatMessagesRestricted = function()
        return outgoingRestricted
    end
}
function CreateFrame()
    local frame = {
        scripts = {}
    }
    function frame:RegisterEvent()
    end
    function frame:SetScript(event, handler)
        self.scripts[event] = handler
    end
    frames[#frames + 1] = frame
    return frame
end

local addon = {}
assert(loadfile("Core.lua"))("PowerInfusionRoulette", addon)
local roulette = addon.Roulette
frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
local passed = 0
local function test(name, check)
    roulette.state = "idle"
    priest, knowsPI, grouped, raid, instance = true, true, true, false, false
    chatRestricted, outgoingRestricted = false, false
    units.party1 = {"Alice", "Realm", "Player-2"}
    now = 0
    messages = {}
    PowerInfusionRouletteDB.timeout = 30
    PowerInfusionRouletteDB.allowHealers = false
    PowerInfusionRouletteDB.allowTanks = false
    PowerInfusionRouletteDB.updatePIMacro = false
    PowerInfusionRouletteDB.piMacroExplained = nil
    PowerInfusionRouletteCharDB = {}
    combat, characterMacros, accountMacro = false, {}, nil
    roulette.pendingMacroBody = nil
    roles = {}
    check()
    passed = passed + 1
    print("PASS " .. name)
end
local function enter(name, message, event)
    roulette:Receive(event or "CHAT_MSG_PARTY", message or "big", name)
end

test("PI macro defaults off and settings and macro name survive login", function()
    PowerInfusionRouletteDB.updatePIMacro = nil
    frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
    assert(PowerInfusionRouletteDB.updatePIMacro == false)
    roulette:SetUpdatePIMacro(true)
    PowerInfusionRouletteDB.piMacroExplained = true
    local name = PowerInfusionRouletteCharDB.macroName
    frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
    assert(PowerInfusionRouletteDB.updatePIMacro and PowerInfusionRouletteDB.piMacroExplained)
    assert(PowerInfusionRouletteCharDB.macroName == name and #characterMacros == 1)
end)
test("PI macro creates on enable and updates only for a finalized winner", function()
    roulette:SetUpdatePIMacro(true)
    assert(characterMacros[1].body == "#showtooltip\n/cast Power Infusion")
    roulette:Begin()
    enter("Bob-OtherRealm")
    roulette:StartSpin()
    assert(characterMacros[1].body == "#showtooltip\n/cast Power Infusion")
    now = 6
    roulette:Tick()
    assert(#characterMacros == 1)
    assert(characterMacros[1].body == "#showtooltip\n/cast [@Bob-OtherRealm] Power Infusion")
    roulette:Begin()
    enter("Alice")
    roulette:StartSpin()
    now = 12
    roulette:Tick()
    assert(#characterMacros == 1 and characterMacros[1].body == "#showtooltip\n/cast [@Alice-Realm] Power Infusion")
end)
test("PI macro lookup survives shifted slots and recreates a missing macro", function()
    characterMacros[1] = {
        name = "Other",
        body = "unchanged"
    }
    roulette:SetUpdatePIMacro(true)
    local name = PowerInfusionRouletteCharDB.macroName
    table.remove(characterMacros, 1)
    roulette:UpdatePIMacro("Alice-Realm")
    assert(#characterMacros == 1 and characterMacros[1].name == name)
    characterMacros = {}
    roulette:UpdatePIMacro("Bob-OtherRealm")
    assert(#characterMacros == 1 and characterMacros[1].name == name)
    assert(characterMacros[1].body == "#showtooltip\n/cast [@Bob-OtherRealm] Power Infusion")
end)
test("PI macro avoids existing names and account macros", function()
    accountMacro = {
        name = "PI Roulette",
        body = "account unchanged"
    }
    characterMacros[1] = {
        name = "PI Roulette",
        body = "character unchanged"
    }
    roulette:SetUpdatePIMacro(true)
    assert(PowerInfusionRouletteCharDB.macroName == "PI Roulette 2")
    assert(characterMacros[1].body == "character unchanged" and accountMacro.body == "account unchanged")
    assert(#characterMacros == 2)
end)
test("PI macro defers combat writes and disabling cancels pending updates", function()
    combat = true
    roulette:SetUpdatePIMacro(true)
    roulette:UpdatePIMacro("Alice-Realm")
    assert(#characterMacros == 0)
    combat = false
    frames[1].scripts.OnEvent(frames[1], "PLAYER_REGEN_ENABLED")
    assert(characterMacros[1].body == "#showtooltip\n/cast [@Alice-Realm] Power Infusion")
    combat = true
    roulette:UpdatePIMacro("Bob-OtherRealm")
    roulette:SetUpdatePIMacro(false)
    combat = false
    frames[1].scripts.OnEvent(frames[1], "PLAYER_REGEN_ENABLED")
    assert(characterMacros[1].body == "#showtooltip\n/cast [@Alice-Realm] Power Infusion")
end)
test("PI macro reports full character slots without replacing other macros", function()
    for index = 1, maxCharacterMacros do
        characterMacros[index] = {
            name = "Other " .. index,
            body = "unchanged"
        }
    end
    roulette:SetUpdatePIMacro(true)
    assert(#characterMacros == maxCharacterMacros)
    assert(printed[#printed]:find("Free a character-specific macro slot", 1, true))
end)
test("disabled PI macro leaves completed rounds untouched", function()
    roulette:Begin()
    enter("Alice")
    roulette:StartSpin()
    now = 6
    roulette:Tick()
    assert(#characterMacros == 0)
end)

test("role settings default off and saved preferences survive login", function()
    PowerInfusionRouletteDB.allowHealers = nil
    PowerInfusionRouletteDB.allowTanks = nil
    frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
    assert(PowerInfusionRouletteDB.allowHealers == false and PowerInfusionRouletteDB.allowTanks == false)
    PowerInfusionRouletteDB.allowHealers = true
    frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
    assert(PowerInfusionRouletteDB.allowHealers == true and PowerInfusionRouletteDB.allowTanks == false)
end)
test("default role filter accepts DPS and rejects healers tanks and unknown roles", function()
    roulette:Begin()
    for _, role in ipairs({"HEALER", "TANK", "NONE"}) do
        roles["Player-2"] = role
        enter("Alice")
        assert(#roulette.entries == 0)
    end
    roles["Player-2"] = "DAMAGER"
    enter("Alice")
    assert(#roulette.entries == 1)
end)
test("role rejection explains each reason once per player per round", function()
    roles["Player-2"], roles["Player-3"], roles["Player-1"] = "HEALER", "TANK", "NONE"
    roulette:Begin()
    enter("Alice")
    enter("Bob-OtherRealm")
    enter("Host")
    assert(messages[2][1] == "Alice-Realm will NOT be participating this round: healers are disabled for this round.")
    assert(messages[3][1] == "Bob-OtherRealm will NOT be participating this round: tanks are disabled for this round.")
    assert(messages[4][1] == "Host-Realm will NOT be participating this round: no group role is assigned.")
    assert(messages[2][2] == "PARTY")
    local count = #messages
    enter("Alice", "BIG")
    enter("Bob-OtherRealm", "BiG")
    enter("Host")
    assert(#messages == count and #roulette.entries == 0)
    roles["Player-2"] = "DAMAGER"
    enter("Alice")
    assert(#roulette.entries == 1)
    roulette:Cancel()
    roulette:Begin()
    roles["Player-2"] = "HEALER"
    count = #messages
    enter("Alice")
    assert(#messages == count + 1)
end)
test("healer and tank settings are independent and apply next round", function()
    roles["Player-2"], roles["Player-3"] = "HEALER", "TANK"
    PowerInfusionRouletteDB.allowHealers = true
    roulette:Begin()
    enter("Alice")
    enter("Bob-OtherRealm")
    assert(#roulette.entries == 1 and roulette.entries[1].name == "Alice-Realm")
    PowerInfusionRouletteDB.allowHealers = false
    PowerInfusionRouletteDB.allowTanks = true
    enter("Bob-OtherRealm")
    assert(#roulette.entries == 1)
    roulette:Cancel()
    roulette:Begin()
    enter("Alice")
    enter("Bob-OtherRealm")
    assert(#roulette.entries == 1 and roulette.entries[1].name == "Bob-OtherRealm")
end)
test("role filters apply in raid and instance chat", function()
    roles["Player-1"] = "HEALER"
    raid = true
    roulette:Begin()
    enter("Host", "BIG", "CHAT_MSG_RAID")
    assert(#roulette.entries == 0)
    roulette:Cancel()
    instance = true
    PowerInfusionRouletteDB.allowHealers = true
    roulette:Begin()
    enter("Host", "BIG", "CHAT_MSG_INSTANCE_CHAT")
    assert(#roulette.entries == 1)
end)
test("role changes remove ineligible entries before selection", function()
    roulette:Begin()
    enter("Alice")
    enter("Bob-OtherRealm")
    roles["Player-2"] = "HEALER"
    frames[1].scripts.OnEvent(frames[1], "PLAYER_ROLES_ASSIGNED")
    assert(#roulette.entries == 1)
    assert(messages[#messages][1] ==
               "Alice-Realm will NOT be participating this round: healers are disabled for this round.")
    local count = #messages
    enter("Alice")
    assert(#messages == count)
    roles["Player-3"] = "TANK"
    assert(not roulette:StartSpin())
    assert(roulette.state == "finished" and #roulette.entries == 0)
end)
test("winner becoming ineligible cancels the spin", function()
    roulette:Begin()
    enter("Alice")
    roulette:StartSpin()
    roles["Player-2"] = "HEALER"
    frames[1].scripts.OnEvent(frames[1], "ROLE_CHANGED_INFORM")
    assert(roulette.state == "idle")
end)
test("Priest, learned spell, and group required", function()
    priest = false
    assert(not roulette:Begin())
    priest, knowsPI = true, false
    assert(not roulette:Begin())
    knowsPI, grouped = true, false
    assert(not roulette:Begin())
    assert(#messages == 0)
end)
test("party round announces entry instructions and configured deadline", function()
    PowerInfusionRouletteDB.timeout = 45
    assert(roulette:Begin())
    assert(#messages == 1 and messages[1][2] == "PARTY")
    assert(messages[1][1] == "Power Infusion Roulette: A new round has started! Type BIG in party" ..
               " chat to enter (case insensitive, one entry per player). Signups close in 45 seconds!")
    enter("Alice", "BIG", "CHAT_MSG_PARTY_LEADER")
    assert(#roulette.entries == 1)
end)
test("raid round announces and accepts entries in raid chat", function()
    raid = true
    units.raid1 = units.player
    units.raid2 = units.party1
    units.raid3 = units.party2
    assert(roulette:Begin())
    assert(#messages == 1 and messages[1][2] == "RAID")
    assert(messages[1][1]:find("Type BIG in raid chat to enter", 1, true))
    enter("Alice", "BIG", "CHAT_MSG_RAID")
    enter("Bob-OtherRealm", "bIg", "CHAT_MSG_RAID_LEADER")
    enter("Host", "big", "CHAT_MSG_PARTY")
    assert(#roulette.entries == 2)
    assert(roulette:StartSpin())
    now = 6
    roulette:Tick()
    assert(roulette.state == "finished")
    assert(messages[#messages][2] == "RAID")
    assert(messages[#messages][1] == roulette.winner.name .. " won this round!")
    units.raid1, units.raid2, units.raid3 = nil, nil, nil
end)
test("case insensitive exact keyword and GUID deduplication", function()
    assert(roulette:Begin())
    enter("Alice", " BiG ")
    enter("Alice-Realm", "BIG")
    enter("Bob-OtherRealm", "bIg")
    enter("Host", "bigger")
    enter("Stranger-Realm")
    assert(#roulette.entries == 2)
end)
test("exclusion blocks reentry until next round", function()
    roulette:Begin()
    enter("Alice")
    roulette:Exclude("Player-2")
    enter("Alice", "BIG")
    assert(#roulette.entries == 0)
    assert(messages[#messages][1] == "Alice-Realm will NOT be participating this round.")
    roulette:Cancel()
    roulette:Begin()
    enter("Alice")
    assert(#roulette.entries == 1)
end)
test("timeout spins once and announces exactly one winner", function()
    roulette:Begin()
    enter("Alice")
    enter("Bob-OtherRealm")
    now = 30
    roulette:Tick()
    assert(roulette.state == "spinning")
    local winner = roulette.winner
    enter("Host")
    roulette:Exclude(winner.guid)
    assert(#roulette.entries == 2)
    now = 36
    roulette:Tick()
    assert(roulette.state == "finished")
    assert(messages[#messages][1] == winner.name .. " won this round!")
    local count = #messages
    roulette:Tick()
    assert(#messages == count)
end)
test("manual spin and zero entry round", function()
    roulette:Begin()
    assert(not roulette:StartSpin())
    assert(roulette.state == "finished")
    roulette:Begin()
    enter("Alice")
    assert(roulette:StartSpin())
    assert(roulette.winner.name == "Alice-Realm")
end)
test("timeout settings persist and apply to next round", function()
    assert(roulette:SetTimeout("45"))
    roulette:Begin()
    assert(roulette.deadline == 45)
    assert(roulette:SetTimeout("10"))
    assert(roulette.deadline == 45)
    assert(not roulette:SetTimeout("0"))
    assert(not roulette:SetTimeout("301"))
    assert(not roulette:SetTimeout("hello"))
end)
test("departed players are removed and group departure cancels", function()
    roulette:Begin()
    enter("Alice")
    units.party1 = nil
    roulette:RefreshRoster()
    assert(#roulette.entries == 0)
    grouped = false
    roulette:RefreshRoster()
    assert(roulette.state == "idle")
end)
test("channel isolation and instance chat", function()
    instance = true
    roulette:Begin()
    assert(messages[1][2] == "INSTANCE_CHAT")
    assert(messages[1][1]:find("Type BIG in instance chat to enter", 1, true))
    enter("Alice")
    assert(#roulette.entries == 0)
    enter("Alice", "BIG", "CHAT_MSG_INSTANCE_CHAT_LEADER")
    assert(#roulette.entries == 1)
end)
test("entries received at the deadline cannot enter", function()
    roulette:Begin()
    enter("Alice")
    now = 30
    enter("Bob-OtherRealm")
    assert(roulette.state == "spinning" and #roulette.entries == 1)
end)
test("loss of Power Infusion cancels before spin", function()
    roulette:Begin()
    enter("Alice")
    knowsPI = false
    assert(not roulette:StartSpin())
    assert(roulette.state == "idle")
end)
test("selected player leaving cancels rather than declaring absent winner", function()
    roulette:Begin()
    enter("Alice")
    roulette:StartSpin()
    units.party1 = nil
    now = 36
    roulette:Tick()
    assert(roulette.state == "idle")
    assert(not messages[#messages][1]:find("won this round", 1, true))
end)
test("both slash commands are registered", function()
    assert(SLASH_POWERINFUSIONROULETTE1 == "/pir")
    assert(SLASH_POWERINFUSIONROULETTE2 == "/powerinfusion")
    SlashCmdList.POWERINFUSIONROULETTE("")
    assert(roulette.state == "signup")
    SlashCmdList.POWERINFUSIONROULETTE("cancel")
    assert(roulette.state == "idle")
end)

test("chat restrictions prevent hosting and cancel active rounds without sending", function()
    chatRestricted = true
    assert(not roulette:Begin())
    chatRestricted = false
    assert(roulette:Begin())
    enter("Alice")
    local count = #messages
    chatRestricted = true
    roulette:Tick()
    assert(roulette.state == "idle" and #messages == count)
end)

test("realm addon-message policy does not block ordinary party chat", function()
    outgoingRestricted = true
    assert(not roulette:IsChatRestricted())
    assert(roulette:Begin())
    assert(messages[1][2] == "PARTY")
    enter("Alice", "BIG")
    roulette:Tick()
    assert(roulette.state == "signup" and #roulette.entries == 1)
    assert(roulette:StartSpin())
    now = 6
    roulette:Tick()
    assert(roulette.state == "finished")
    assert(messages[#messages][1] == "Alice-Realm won this round!")
    assert(messages[#messages][2] == "PARTY")
end)

test("secret chat values are ignored", function()
    roulette:Begin()
    issecretvalue = function(value)
        return value == "Alice"
    end
    enter("Alice")
    assert(#roulette.entries == 0)
    issecretvalue = nil
    enter("Alice")
    assert(#roulette.entries == 1)
end)

local function mockRegion(parent)
    local region = {
        parent = parent,
        scripts = {},
        shown = true
    }
    for _, method in ipairs({"SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
                             "StartMoving", "StopMovingOrSizing", "SetBackdrop", "SetBackdropColor",
                             "SetBackdropBorderColor", "SetScale", "RegisterEvent", "SetNormalTexture",
                             "SetHighlightTexture", "SetAllPoints", "SetColorTexture", "SetVertexColor", "SetTextColor",
                             "SetJustifyH", "SetJustifyV", "SetWordWrap", "ClearAllPoints", "SetTexture", "SetTexCoord",
                             "AddMaskTexture", "SetThickness", "SetStartPoint", "SetEndPoint", "SetAutoFocus",
                             "SetNumeric", "SetMaxLetters", "ClearFocus", "SetFrameLevel"}) do
        region[method] = function()
        end
    end
    function region:SetSize(width, height)
        self.width, self.height = width, height
    end
    function region:SetWidth(width)
        self.width = width
    end
    function region:SetHeight(height)
        self.height = height
    end
    function region:GetWidth()
        return self.width
    end
    function region:GetHeight()
        return self.height
    end
    function region:SetPoint(...)
        self.point = {...}
    end
    function region:SetText(text)
        self.text = text
    end
    function region:GetText()
        return tostring(self.text)
    end
    function region:SetScript(event, handler)
        self.scripts[event] = handler
    end
    function region:GetParent()
        return self.parent
    end
    function region:GetFrameLevel()
        return 1
    end
    function region:SetEnabled(value)
        self.enabled = value
    end
    function region:SetChecked(value)
        self.checked = value
    end
    function region:GetChecked()
        return self.checked
    end
    function region:SetShown(value)
        self.shown = value
    end
    function region:Show()
        self.shown = true
    end
    function region:Hide()
        self.shown = false
    end
    function region:SetScrollChild(child)
        self.scrollChild = child
    end
    function region:CreateTexture()
        return mockRegion(self)
    end
    function region:CreateFontString()
        return mockRegion(self)
    end
    function region:CreateMaskTexture()
        return mockRegion(self)
    end
    function region:CreateLine()
        return mockRegion(self)
    end
    return region
end

test("native UI lifecycle, exclusion click, and final wheel landing", function()
    UIParent = mockRegion()
    UIParent:SetSize(1600, 900)
    UISpecialFrames = {}
    StaticPopupDialogs = {}
    CANCEL = "Cancel"
    GameTooltip = mockRegion()
    GameTooltip.SetOwner = function()
    end
    function GameTooltip:SetText(text, red, green, blue, alpha, wrap)
        assert(type(red) == "number" and type(green) == "number" and type(blue) == "number")
        assert(type(alpha) == "number" and alpha >= 0 and alpha <= 1)
        assert(wrap == true)
        self.text = text
    end
    local timeoutControl
    CreateFrame = function(frameType, _, parent)
        local control = mockRegion(parent)
        if frameType == "EditBox" then
            timeoutControl = control
        end
        return control
    end
    assert(loadfile("UI.lua"))("PowerInfusionRoulette", addon)
    roulette:CreateWindow()
    local window = roulette.window
    assert(not window.shown)
    assert(timeoutControl.point[1] == "BOTTOMLEFT" and timeoutControl.point[3] == 24)
    assert(window.start.point[1] == "BOTTOMRIGHT" and window.start.point[3] == 22)
    assert(window.cancel.point[1] == "RIGHT" and window.cancel.point[2] == window.start)
    assert(window.cancel.point[3] == "LEFT" and window.cancel.point[4] == -10 and window.cancel.point[5] == 0)
    assert(not window.allowHealers:GetChecked() and not window.allowTanks:GetChecked())
    window.allowHealers:SetChecked(true)
    window.allowHealers.scripts.OnClick(window.allowHealers)
    assert(PowerInfusionRouletteDB.allowHealers == true and PowerInfusionRouletteDB.allowTanks == false)
    window.allowTanks:SetChecked(true)
    window.allowTanks.scripts.OnClick(window.allowTanks)
    assert(PowerInfusionRouletteDB.allowTanks == true)
    timeoutControl.scripts.OnEnter(timeoutControl)
    assert(GameTooltip.text == "5-300 seconds. Changes apply to the next round.")
    assert(GameTooltip.shown)
    timeoutControl.scripts.OnLeave(timeoutControl)
    assert(not GameTooltip.shown)
    assert(roulette:Begin())
    assert(window.shown)
    assert(roulette.allowHealers and roulette.allowTanks)
    window.allowHealers:SetChecked(false)
    window.allowHealers.scripts.OnClick(window.allowHealers)
    assert(PowerInfusionRouletteDB.allowHealers == false and roulette.allowHealers == true)
    enter("Alice")
    enter("Bob-OtherRealm")
    assert(#window.rows == 2 and #window.nodes == 2)
    assert(window.start.enabled)
    local remove = window.rows[1].remove
    remove.scripts.OnEnter(remove)
    assert(GameTooltip.text == "Exclude Alice-Realm this round")
    remove.scripts.OnLeave(remove)
    remove.scripts.OnClick(remove)
    assert(#roulette.entries == 1 and roulette.blocked["Player-2"])
    assert(not window.rows[2].shown and not window.nodes[2].shown)
    assert(roulette:StartSpin())
    assert(not window.start.enabled)
    assert(not window.rows[1].remove.shown)
    now = 3
    roulette:AnimateWheel()
    assert(window.current.text == "Bob\nOtherRealm")
    now = 6
    roulette:Tick()
    assert(window.result.text == "Winner")
    assert(window.current.text == "Bob\nOtherRealm")
    assert(math.abs(window.pointer.point[4]) < 0.00001)
    assert(math.abs(window.pointer.point[5] - 182) < 0.00001)
end)

test("PI macro checkbox confirms first enable and remembers acceptance", function()
    local shown = 0
    StaticPopup_Show = function(key)
        assert(key == "POWERINFUSIONROULETTE_ENABLE_MACRO")
        shown = shown + 1
    end
    roulette:Render()
    local checkbox = roulette.window.updatePIMacro
    local dialog = StaticPopupDialogs.POWERINFUSIONROULETTE_ENABLE_MACRO
    assert(not checkbox:GetChecked())
    checkbox:SetChecked(true)
    checkbox.scripts.OnClick(checkbox)
    assert(shown == 1 and not checkbox:GetChecked() and #characterMacros == 0)
    dialog.OnCancel()
    assert(not PowerInfusionRouletteDB.updatePIMacro and not PowerInfusionRouletteDB.piMacroExplained)
    checkbox:SetChecked(true)
    checkbox.scripts.OnClick(checkbox)
    dialog.OnAccept()
    assert(shown == 2 and checkbox:GetChecked() and #characterMacros == 1)
    assert(PowerInfusionRouletteDB.updatePIMacro and PowerInfusionRouletteDB.piMacroExplained)
    checkbox:SetChecked(false)
    checkbox.scripts.OnClick(checkbox)
    assert(not PowerInfusionRouletteDB.updatePIMacro and #characterMacros == 1)
    checkbox:SetChecked(true)
    checkbox.scripts.OnClick(checkbox)
    assert(shown == 2 and PowerInfusionRouletteDB.updatePIMacro and #characterMacros == 1)
    checkbox.scripts.OnEnter(checkbox)
    assert(GameTooltip.text:find("character-specific", 1, true))
    checkbox.scripts.OnLeave(checkbox)
end)

test("40-player wheel lands on every possible winner and shrinks cleanly", function()
    roulette:Begin()
    for index = 1, 40 do
        roulette.entries[index] = {
            name = "Player" .. index .. "-Realm",
            guid = "Test-" .. index
        }
    end
    roulette:Render()
    assert(#roulette.window.rows == 40 and #roulette.window.nodes == 40)
    assert(roulette.window.scrollChild.height == 1360)
    roulette.state = "spinning"
    roulette.spinStarted, roulette.spinDuration = 0, 6
    now = 6
    for index = 1, 40 do
        roulette.winnerIndex = index
        roulette:AnimateWheel()
        assert(roulette.window.current.text == "Player" .. index .. "\nRealm")
    end
    roulette:Cancel()
    roulette:Begin()
    assert(not roulette.window.rows[40].shown and not roulette.window.nodes[40].shown)
    assert(not roulette.window.pointer.shown)
end)
print(passed .. " tests passed")
