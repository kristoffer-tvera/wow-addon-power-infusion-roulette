local addonName, addon = ...
local Roulette = {}
addon.Roulette = Roulette

local POWER_INFUSION = 10060
local MIN_TIMEOUT, MAX_TIMEOUT = 5, 300
local SPIN_DURATION = 6
local chatChannels = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT"
}

Roulette.state = "idle"
Roulette.entries = {}
Roulette.blocked = {}

function Roulette:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd76aPower Infusion Roulette:|r " .. message)
end

function Roulette:Notify()
    if self.OnChanged then
        self:OnChanged()
    end
end

function Roulette:GetChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

function Roulette:IsChatRestricted()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

function Roulette:Announce(message)
    if self.channel and self.channel == self:GetChannel() then
        if self:IsChatRestricted() then
            self:Print("Group chat is restricted. " .. message)
            return
        end
        C_ChatInfo.SendChatMessage(message, self.channel)
    end
end

function Roulette:CanHost()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then
        return false, "Only a Priest can host a Power Infusion roulette."
    end
    if not C_SpellBook.IsSpellKnown(POWER_INFUSION) then
        return false, "You must know Power Infusion to host a roulette."
    end
    if self:IsChatRestricted() then
        return false, "Chat messaging is restricted. Start a round after restrictions end."
    end
    if not self:GetChannel() then
        return false, "Join a party or raid before starting a roulette."
    end
    return true
end

function Roulette:GetRoster()
    local roster = {}
    local function addUnit(unit)
        local name, realm = UnitFullName(unit)
        local guid = UnitGUID(unit)
        if not name or not guid then
            return
        end
        if not realm or realm == "" then
            realm = GetNormalizedRealmName()
        end
        local fullName = name .. "-" .. realm
        roster[fullName:lower()] = {
            name = fullName,
            guid = guid,
            role = UnitGroupRolesAssigned(unit)
        }
    end
    addUnit("player")
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            addUnit("raid" .. index)
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            addUnit("party" .. index)
        end
    end
    return roster
end

function Roulette:IsRoleAllowed(role)
    if issecretvalue and issecretvalue(role) then
        return false
    end
    return role == "DAMAGER" or (role == "HEALER" and self.allowHealers) or (role == "TANK" and self.allowTanks) or
               false
end

function Roulette:ExplainRoleRejection(member)
    if self.roleRejections[member.guid] then
        return
    end
    self.roleRejections[member.guid] = true
    local reason = "your group role could not be determined."
    if not (issecretvalue and issecretvalue(member.role)) then
        if member.role == "HEALER" then
            reason = "healers are disabled for this round."
        elseif member.role == "TANK" then
            reason = "tanks are disabled for this round."
        elseif member.role == "NONE" then
            reason = "no group role is assigned."
        end
    end
    self:Announce(member.name .. " will NOT be participating this round: " .. reason)
end

function Roulette:SetTimeout(value)
    local timeout = tonumber(value)
    if not timeout or timeout ~= timeout or timeout < MIN_TIMEOUT or timeout > MAX_TIMEOUT then
        self:Print("Timeout must be a number from 5 to 300 seconds.")
        return false
    end
    PowerInfusionRouletteDB.timeout = math.floor(timeout)
    self:Print("Signup timeout set to " .. PowerInfusionRouletteDB.timeout .. " seconds (next round).")
    self:Notify()
    return true
end

function Roulette:SetUpdatePIMacro(enabled)
    PowerInfusionRouletteDB.updatePIMacro = enabled == true
    if enabled then
        self:UpdatePIMacro(self.state == "finished" and self.winner and self.winner.name or nil)
    else
        self.pendingMacroBody = nil
    end
    self:Notify()
end

function Roulette:UpdatePIMacro(winnerName)
    if not PowerInfusionRouletteDB.updatePIMacro then
        return
    end
    self.pendingMacroBody = "#showtooltip\n/cast " .. (winnerName and ("[@" .. winnerName .. "] ") or "") ..
                                (C_Spell.GetSpellName(POWER_INFUSION) or "Power Infusion")
    self:ApplyPendingPIMacro()
end

function Roulette:ApplyPendingPIMacro()
    if not self.pendingMacroBody or not PowerInfusionRouletteDB.updatePIMacro or InCombatLockdown() then
        return
    end
    local _, characterCount = GetNumMacros()
    local names = {}
    local macroIndex
    for index = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + characterCount do
        local name = GetMacroInfo(index)
        names[name] = true
        if name == PowerInfusionRouletteCharDB.macroName then
            macroIndex = index
        end
    end
    if not PowerInfusionRouletteCharDB.macroName then
        local name, suffix = "PI Roulette", 1
        while names[name] do
            suffix = suffix + 1
            name = "PI Roulette " .. suffix
        end
        PowerInfusionRouletteCharDB.macroName = name
    end
    if macroIndex then
        EditMacro(macroIndex, nil, nil, self.pendingMacroBody)
    elseif characterCount < MAX_CHARACTER_MACROS then
        macroIndex = CreateMacro(PowerInfusionRouletteCharDB.macroName,
            C_Spell.GetSpellTexture(POWER_INFUSION) or 135939, self.pendingMacroBody, true)
    end
    if not macroIndex or macroIndex == 0 then
        self:Print("Could not create the PI macro. Free a character-specific macro slot, then re-enable Update PI Macro.")
    end
    self.pendingMacroBody = nil
end

function Roulette:Begin()
    if self.state == "signup" or self.state == "spinning" then
        self:Print("A round is already running.")
        if self.ShowWindow then
            self:ShowWindow()
        end
        return false
    end
    local allowed, reason = self:CanHost()
    if not allowed then
        self:Print(reason)
        return false
    end
    self.state = "signup"
    self.entries = {}
    self.blocked = {}
    self.roleRejections = {}
    self.winner = nil
    self.channel = self:GetChannel()
    self.allowHealers = PowerInfusionRouletteDB.allowHealers == true
    self.allowTanks = PowerInfusionRouletteDB.allowTanks == true
    self.deadline = GetTime() + PowerInfusionRouletteDB.timeout
    self.lastSecond = nil
    local chatName = self.channel == "RAID" and "raid" or self.channel == "PARTY" and "party" or "instance"
    self:Announce("Power Infusion Roulette: A new round has started! Type BIG in " .. chatName ..
                      " chat to enter (case insensitive, one entry per player). Signups close in " ..
                      PowerInfusionRouletteDB.timeout .. " seconds!")
    if self.ShowWindow then
        self:ShowWindow()
    end
    self:Notify()
    return true
end

function Roulette:Receive(event, message, sender)
    if self.state ~= "signup" or chatChannels[event] ~= self.channel then
        return
    end
    if (issecretvalue and (issecretvalue(message) or issecretvalue(sender))) then
        return
    end
    if type(message) ~= "string" or type(sender) ~= "string" then
        return
    end
    if GetTime() >= self.deadline then
        self:StartSpin()
        return
    end
    if not message:match("^%s*[bB][iI][gG]%s*$") then
        return
    end
    if not sender:find("-", 1, true) then
        sender = sender .. "-" .. GetNormalizedRealmName()
    end
    local member = self:GetRoster()[sender:lower()]
    if not member or self.blocked[member.guid] then
        return
    end
    if not self:IsRoleAllowed(member.role) then
        self:ExplainRoleRejection(member)
        return
    end
    for _, entry in ipairs(self.entries) do
        if entry.guid == member.guid then
            return
        end
    end
    self.entries[#self.entries + 1] = member
    self:Notify()
end

function Roulette:Exclude(guid)
    if self.state ~= "signup" then
        return
    end
    for index, entry in ipairs(self.entries) do
        if entry.guid == guid then
            self.blocked[guid] = true
            table.remove(self.entries, index)
            self:Announce(entry.name .. " will NOT be participating this round.")
            self:Notify()
            return
        end
    end
end

function Roulette:RefreshRoster()
    if self.state ~= "signup" and self.state ~= "spinning" then
        return
    end
    if self.channel ~= self:GetChannel() then
        self:Cancel("Group changed; the roulette was cancelled.")
        return
    end
    local present = {}
    for _, member in pairs(self:GetRoster()) do
        present[member.guid] = member
    end
    if self.state == "spinning" then
        if self.winner and not present[self.winner.guid] then
            self:Cancel("The selected player left the group; start a new round.")
        elseif self.winner and not self:IsRoleAllowed(present[self.winner.guid].role) then
            self:ExplainRoleRejection(present[self.winner.guid])
            self:Cancel("The selected player's role is no longer eligible; start a new round.")
        end
        return
    end
    for index = #self.entries, 1, -1 do
        local member = present[self.entries[index].guid]
        if not member or not self:IsRoleAllowed(member.role) then
            if member then
                self:ExplainRoleRejection(member)
            end
            table.remove(self.entries, index)
        end
    end
    self:Notify()
end

function Roulette:StartSpin()
    if self.state ~= "signup" then
        return false
    end
    local allowed, reason = self:CanHost()
    if not allowed then
        self:Cancel(reason)
        return false
    end
    self:RefreshRoster()
    if self.state ~= "signup" then
        return false
    end
    if #self.entries == 0 then
        self.state = "finished"
        self:Announce("No entries this round. Power Infusion roulette closed.")
        self:Notify()
        return false
    end
    self.winnerIndex = math.random(#self.entries)
    self.winner = self.entries[self.winnerIndex]
    self.spinStarted = GetTime()
    self.spinDuration = SPIN_DURATION
    self.state = "spinning"
    self:Announce("Signups closed. Spinning for " .. #self.entries .. " player(s)!")
    self:Notify()
    return true
end

function Roulette:Cancel(reason)
    if self.state ~= "signup" and self.state ~= "spinning" then
        return
    end
    self:Announce("Power Infusion roulette cancelled.")
    self.state = "idle"
    self.winner = nil
    if reason then
        self:Print(reason)
    end
    self:Notify()
end

function Roulette:Tick()
    if (self.state == "signup" or self.state == "spinning") and self:IsChatRestricted() then
        self:Cancel("Chat messaging became restricted; start a new round after restrictions end.")
        return
    end
    if self.state == "signup" then
        local remaining = math.max(0, math.ceil(self.deadline - GetTime()))
        if remaining == 0 then
            self:StartSpin()
        elseif remaining ~= self.lastSecond then
            self.lastSecond = remaining
            self:Notify()
        end
    elseif self.state == "spinning" and GetTime() >= self.spinStarted + self.spinDuration then
        local allowed, reason = self:CanHost()
        if not allowed then
            self:Cancel(reason)
            return
        end
        self:RefreshRoster()
        if self.state ~= "spinning" then
            return
        end
        self.state = "finished"
        self:Announce(self.winner.name .. " won this round!")
        self:Print(self.winner.name .. " won this round!")
        self:UpdatePIMacro(self.winner.name)
        self:Notify()
    end
end

function Roulette:Command(text)
    local command, argument = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        self:Begin()
    elseif command == "show" then
        if self.ShowWindow then
            self:ShowWindow()
        end
    elseif command == "timeout" then
        self:SetTimeout(argument)
    elseif command == "cancel" then
        self:Cancel()
    else
        self:Print("/pir - new round; /pir show; /pir timeout 30; /pir cancel")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if type(PowerInfusionRouletteDB) ~= "table" then
            PowerInfusionRouletteDB = {}
        end
        local timeout = tonumber(PowerInfusionRouletteDB.timeout)
        if not timeout or timeout ~= timeout or timeout < MIN_TIMEOUT or timeout > MAX_TIMEOUT then
            timeout = 30
        end
        PowerInfusionRouletteDB.timeout = math.floor(timeout)
        PowerInfusionRouletteDB.allowHealers = PowerInfusionRouletteDB.allowHealers == true
        PowerInfusionRouletteDB.allowTanks = PowerInfusionRouletteDB.allowTanks == true
        PowerInfusionRouletteDB.updatePIMacro = PowerInfusionRouletteDB.updatePIMacro == true
        if type(PowerInfusionRouletteCharDB) ~= "table" then
            PowerInfusionRouletteCharDB = {}
        end
        SLASH_POWERINFUSIONROULETTE1 = "/pir"
        SLASH_POWERINFUSIONROULETTE2 = "/powerinfusion"
        SlashCmdList.POWERINFUSIONROULETTE = function(text)
            Roulette:Command(text)
        end
        for chatEvent in pairs(chatChannels) do
            events:RegisterEvent(chatEvent)
        end
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        events:RegisterEvent("ROLE_CHANGED_INFORM")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        if Roulette.CreateWindow then
            Roulette:CreateWindow()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        Roulette:ApplyPendingPIMacro()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
        Roulette:RefreshRoster()
    else
        Roulette:Receive(event, ...)
    end
end)
events:SetScript("OnUpdate", function()
    Roulette:Tick()
end)
