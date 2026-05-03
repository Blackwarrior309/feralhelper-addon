-- ============================================================
-- FeralHelper.lua - Hauptlogik
-- ============================================================

FeralHelper = FeralHelper or {}
local FH = FeralHelper
local addonActive = false

local function IsDruidPlayer()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

local function DisableForNonDruid(frame)
    addonActive = false
    FH.disabled = true
    if frame then
        frame:UnregisterAllEvents()
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper|r deaktiviert: Spieler ist kein Druide.")
    end
end

-- ============================================================
-- Spell-Namen via GetSpellInfo (holt lokalisierten Namen
-- direkt aus dem Client, egal ob DE/EN/etc.)
-- ============================================================
local SPELL_HYSTERIA    = GetSpellInfo(49016) or "Hysteria"
local SPELL_HOP         = GetSpellInfo(1022)  or "Hand des Schutzes"
local SPELL_BARKSKIN    = GetSpellInfo(22812) or "Baumrinde"
local SPELL_TIGERSFURY  = GetSpellInfo(5217)  or "Tigerwut"
local SPELL_BERSERK     = GetSpellInfo(50334) or "Berserker"
local SPELL_CLEARCAST   = GetSpellInfo(16870) or "Klarsicht"
local SPELL_INNERVATE   = GetSpellInfo(29166) or "Anregen"
local SPELL_SURVINST    = GetSpellInfo(61336) or "Ueberlebensinstinkte"
local SPELL_FRENZIEDREG = GetSpellInfo(22842) or "Rasende Regeneration"
local SPELL_REBIRTH     = GetSpellInfo(20484) or "Wiedergeburt"
local SPELL_BEARFORM    = GetSpellInfo(9634)  or "Terrorbärengestalt"
local SPELL_ENRAGE      = GetSpellInfo(5229)  or "Wutanfall"
local SPELL_SCHWERTGARN = GetSpellInfo(55776) or "Schwertwallgarn"

-- Katzenrotation
local SPELL_SAVAGEROAR   = GetSpellInfo(52610) or "Raubtierbrüllen"
local SPELL_RIP          = GetSpellInfo(49800) or "Zerreißen"
local SPELLID_SAVAGEROAR = 52610
local SPELLID_RIP        = 49800
local ROARRIP_WINDOW     = 8   -- beide müssen innerhalb N Sekunden ablaufen
local ROARRIP_DELTA      = 3   -- gleichzeitig = Differenz < N Sekunden
local RIP_RECAST_THRESH  = 5   -- "jetzt casten" wenn TF aktiv + Rip <= N Sekunden

function FH:GetWhisperText(dbKey)
    local text = FeralHelperDB and FeralHelperDB[dbKey]
    if text and text:match("%S") then
        return text
    end
    return self.defaults and self.defaults[dbKey] or ""
end

local function IsInBearForm()
    return GetShapeshiftForm() == 1
end

local catFormSlot = nil
local function IsInCatForm()
    if not catFormSlot then
        for i = 1, GetNumShapeshiftForms() do
            local icon = GetShapeshiftFormInfo(i)
            if icon and icon:lower():find("catform") then
                catFormSlot = i
                break
            end
        end
        if not catFormSlot then catFormSlot = 3 end  -- Fallback: Cat ist normalerweise Slot 3
    end
    return GetShapeshiftForm() == catFormSlot
end

-- Eigenes Rip auf Ziel suchen (HARMFUL|PLAYER Filter unsicher in 3.3.5a)
local function GetOwnRipOnTarget()
    local playerName = UnitName("player")
    for i = 1, 40 do
        local n, _, _, _, _, duration, expTime, unitCaster = UnitAura("target", i, "HARMFUL")
        if not n then break end
        if n == SPELL_RIP and (unitCaster == "player" or unitCaster == playerName) then
            return expTime
        end
    end
    return nil
end

-- icd = Internal Cooldown in Sekunden (fuer synthetischen CD nach Proc-Ende)
local _TRINKET_PROC_IDS = {
    [50351] = { icd=45, spells={ 71887 } }, [50352] = { icd=45, spells={ 71887 } },  -- Death's Verdict (N)
    [50353] = { icd=45, spells={ 71888, 71601, 71644 } }, [50354] = { icd=45, spells={ 71888 } },  -- Death's Verdict (H) / DFO fallback
    [50343] = { icd=45, spells={ 71901, 71401, 71541 } }, [50344] = { icd=45, spells={ 71901, 71578 } },  -- Whispering Fanged Skull (N) / Organ fallback
    [50346] = { icd=45, spells={ 71900 } }, [50347] = { icd=45, spells={ 71900 } },  -- Whispering Fanged Skull (H)
    [50733] = { icd=45, spells={ 71879 } }, [50734] = { icd=45, spells={ 71880 } },  -- Needle-Encrusted Scorpion
    [45931] = { icd=45, spells={ 75171 } },                                           -- Mjolnir Runestone
    [46130] = { icd=45, spells={ 60229 } }, [47115] = { icd=45, spells={ 60229, 67703, 67708 } },  -- Darkmoon Card: Greatness / Death's Verdict fallback
    [50363] = { icd=105, spells={ 71485, 71486, 71484, 71491, 71488, 71487, 71492, 71556, 71557, 71558, 71559, 71560, 71561 } }, -- Deathbringer's Will (N)
    [50364] = { icd=105, spells={ 71485, 71486, 71484, 71491, 71488 } },              -- Deathbringer's Will (H)
    [54590] = { icd=45, spells={ 75473, 75456 }, extra={ "Durchbohrendes Zwielicht" } }, -- Sharpened Twilight Scale (N)
    [54718] = { icd=45, spells={ 75466 }, extra={ "Durchbohrendes Zwielicht" } },       -- Sharpened Twilight Scale (H)
    [50355] = { icd=45, spells={ 71873 } }, [71396] = { icd=45, spells={ 71873 } },   -- Herkumlkriegsabzeichen
    [47214] = { icd=43, spells={ 67671 } }, [67671] = { icd=43, spells={ 67671 } },   -- Banner des Sieges

    -- Additive WotLK proc fallbacks. Bestehende Zuordnungen oben bleiben unveraendert.
    [50362] = { icd=105, spells={ 71484, 71485, 71486, 71487, 71491, 71492, 71556, 71557, 71558, 71559, 71560, 71561 } }, -- Deathbringer's Will
    [50342] = { icd=45,  spells={ 71401, 71541 } }, -- Whispering Fanged Skull
    [50348] = { icd=45,  spells={ 71601, 71644 } }, -- Dislodged Foreign Object
    [50360] = { icd=100, spells={ 71605, 71636 } }, -- Phylactery of the Nameless Lich
    [50365] = { icd=100, spells={ 71605, 71636 } }, -- Phylactery of the Nameless Lich
    [47303] = { icd=45,  spells={ 67703, 67708 } }, -- Death's Choice
    [47464] = { icd=45,  spells={ 67772, 67773 } }, -- Death's Choice
    [47131] = { icd=45,  spells={ 67772, 67773 } }, -- Death's Verdict
    [54569] = { icd=45,  spells={ 75458, 75456 }, extra={ "Durchbohrendes Zwielicht" } }, -- Sharpened Twilight Scale
    [54572] = { icd=50,  spells={ 75466, 75473 } }, -- Charred Twilight Scale
    [54588] = { icd=50,  spells={ 75466, 75473 } }, -- Charred Twilight Scale
    [50341] = { icd=45,  spells={ 71578 } }, -- Unidentifiable Organ
    [54571] = { icd=45,  spells={ 75477 } }, -- Petrified Twilight Scale
    [54591] = { icd=45,  spells={ 75480 } }, -- Petrified Twilight Scale

    -- Ashen Band (ICC Ruf-Ringe) icd=60
    [50401] = { icd=60, spells={ 72412 } }, -- Endless Might AGI 10N
    [50402] = { icd=60, spells={ 72412 } }, -- Endless Might AGI 10H
    [52571] = { icd=60, spells={ 72412 } }, -- Endless Might STR 25N
    [52572] = { icd=60, spells={ 72412 } }, -- Endless Might STR 25H
    [50397] = { icd=60, spells={ 72416 } }, -- Endless Vengeance SP 10N
    [50398] = { icd=60, spells={ 72416 } }, -- Endless Vengeance SP 10H
    [50399] = { icd=60, spells={ 72418 } }, -- Endless Courage Heal 10N
    [50400] = { icd=60, spells={ 72418 } }, -- Endless Courage Heal 10H
    [50403] = { icd=60, spells={ 72414 } }, -- Endless Resolve Tank 10N
    [50404] = { icd=60, spells={ 72414 } }, -- Endless Resolve Tank 10H

    -- Ergaenzt aus TrinketCDsDB (icd=0 = kein Syn-CD nach Proc-Ende)
    [47059] = { icd=0, spells={ 67750 } }, -- Solace of the Defeated (H)
    [47041] = { icd=0, spells={ 67696 } }, -- Solace of the Defeated (N)
    [47432] = { icd=0, spells={ 67750 } }, -- Solace of the Fallen (H)
    [47271] = { icd=0, spells={ 67696 } }, -- Solace of the Fallen (N)
    [47188] = { icd=0, spells={ 67759 } }, -- Reign of the Unliving (H)
    [47182] = { icd=0, spells={ 67713 } }, -- Reign of the Unliving (N)
    [47477] = { icd=0, spells={ 67759 } }, -- Reign of the Dead (H)
    [47316] = { icd=0, spells={ 67713 } }, -- Reign of the Dead (N)
    [50345] = { icd=0, spells={ 71572 } }, -- Muradin's Spyglass (H)
    [50340] = { icd=0, spells={ 71570 } }, -- Muradin's Spyglass (N)
    [50706] = { icd=0, spells={ 71432 } }, -- Tiny Abomination in a Jar (H)
    [37111] = { icd=0, spells={ 60515 } }, -- Soul Preserver
    [40430] = { icd=0, spells={ 60525 } }, -- Majestic Dragon Figurine
    [40431] = { icd=0, spells={ 60314 } }, -- Fury of the Five Flights
    [40432] = { icd=0, spells={ 60486 } }, -- Illustration of the Dragon Soul
    [42989] = { icd=0, spells={ 60196 } }, -- Darkmoon Card: Berserker!
    [45308] = { icd=0, spells={ 65006 } }, -- Eye of the Broodmother
    [38072] = { icd=0, spells={ 54842 } }, -- Thunder Capacitor
    [32496] = { icd=0, spells={ 37656 } }, -- Memento of Tyrande
    [28727] = { icd=0, spells={ 35095 } }, -- Pendant of the Violet Eye
    [28785] = { icd=0, spells={ 37658 } }, -- The Lightning Capacitor
    [31856] = { icd=0, spells={ 39439 } }, -- Darkmoon Card: Crusade
    [31857] = { icd=0, spells={ 39443 } }, -- Darkmoon Card: Wrath
}
-- itemId -> { icd=N, names={...} }  – auf PLAYER_LOGIN befuellt
local TRINKET_PROCS = {}
local function BuildTrinketProcNames()
    for itemId, data in pairs(_TRINKET_PROC_IDS) do
        local names = {}
        for _, sid in ipairs(data.spells) do
            local n = GetSpellInfo(sid)
            if n then names[#names + 1] = n end
        end
        for _, n in ipairs(data.extra or {}) do
            names[#names + 1] = n
        end
        TRINKET_PROCS[itemId] = { icd=data.icd, names=names }
    end
end

-- Merkt sich ob Ueberlebensinstinkte gerade aktiv sind (fuer /say-Detection)
local survInstExpiry = nil

-- Icon-Pfade fuer Ingi-Tinker (per SpellID - egal was auf Slot liegt)
local SPELLID_HYPERSPEED = 54758
local SPELLID_NITRO      = 54861

-- Inventar-Slots
local SLOT_HANDS    = 10
local SLOT_FEET     = 8
local SLOT_TRINKET1 = 13
local SLOT_TRINKET2 = 14
local SLOT_BACK     = 15

local HYSTERIA_CD = 180

local function CanMove()
    return not (FeralHelperDB and FeralHelperDB.framesLocked)
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================

-- Sucht Aura per Name, gibt icon, count, duration, expirationTime zurueck
local function GetAuraInfo(unit, name, filter)
    for i = 1, 40 do
        local n, _, icon, count, _, duration, expirationTime = UnitAura(unit, i, filter)
        if not n then return nil end
        if n == name then
            return icon, count, duration, expirationTime
        end
    end
    return nil
end

-- Sucht Aura per Spell-ID (11. Rueckgabewert von UnitAura in 3.3.5a)
local function GetAuraInfoById(unit, spellId, filter)
    for i = 1, 40 do
        local n, _, icon, count, _, duration, expirationTime, _, _, _, sid = UnitAura(unit, i, filter)
        if not n then return nil end
        if sid == spellId then
            return icon, count, duration, expirationTime
        end
    end
    return nil
end

-- Verschiebbarer Frame, speichert Position bei Drop
local function CreateMovableFrame(name, w, h, defaultPoint)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(self) if CanMove() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        FeralHelperDB.framePositions[name] = { point, relPoint, x, y }
    end)
    f:ClearAllPoints()
    if defaultPoint then
        f:SetPoint(unpack(defaultPoint))
    else
        f:SetPoint("CENTER")
    end
    return f
end

local function RestoreFramePosition(frame)
    local pos = FeralHelperDB.framePositions[frame:GetName()]
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

-- ============================================================
-- 1) HYSTERIA - Icon + Countdown + Whisper
-- ============================================================

local SendHysteriaWhisper
local hysteriaFrame
local function CreateHysteriaFrame()
    hysteriaFrame = CreateMovableFrame("FeralHelperHysteriaFrame", 64, 90,
        { "CENTER", UIParent, "CENTER", -200, 0 })

    -- Icon (Hysteria-Spell-Icon vom Client)
    local _, _, hyIcon = GetSpellInfo(49016)
    local icon = hysteriaFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOP", hysteriaFrame, "TOP", 0, 0)
    icon:SetSize(64, 64)
    icon:SetTexture(hyIcon or "Interface\\Icons\\Spell_Shadow_UnholyFrenzy")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hysteriaFrame.icon = icon

    -- Cooldown-Wisch-Overlay (fuer CD-Phasenvisualisierung)
    local cd = CreateFrame("Cooldown", nil, hysteriaFrame, "CooldownFrameTemplate")
    cd:SetPoint("TOP", hysteriaFrame, "TOP", 0, 0)
    cd:SetSize(64, 64)
    hysteriaFrame.cd = cd

    -- Leuchtender Rand ueber dem Icon (ADD-Blendmode = leuchtet auf Texturen)
    -- Ankerpunkte direkt am Icon -> immer korrekte Groesse
    local border = hysteriaFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -14,  14)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  14, -14)
    hysteriaFrame.border = border

    -- Timer-Text auf dem Icon (CD-Sekunden oder Buff-Restdauer)
    local timer = hysteriaFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    hysteriaFrame.timer = timer

    -- Status-Text unter Icon: "Hysteria / BEREIT / AKTIV"
    local statusText = hysteriaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", hysteriaFrame, "TOP", 0, -68)
    statusText:SetText("Hysteria")
    hysteriaFrame.statusText = statusText

    -- OnUpdate: prueft Buff-Status + CD-Status jeden Frame
    hysteriaFrame:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed

        -- Zustand 1: Buff gerade aktiv (Hysteria laeuft auf mir)
        local _, _, _, buffExp = GetAuraInfo("player", SPELL_HYSTERIA, "HELPFUL")
        if buffExp then
            local rem = math.floor(buffExp - GetTime())
            self.timer:SetText(rem > 0 and rem or "")
            self.timer:SetTextColor(0.2, 1, 0.2)
            self.statusText:SetText("AKTIV")
            self.statusText:SetTextColor(0.2, 1, 0.2)
            -- Gruen pulsieren
            self.border:SetVertexColor(0, 1, 0.2)
            self.border:SetAlpha(0.6 + 0.4 * math.sin(self.t * 6))
            self.border:Show()
            return
        end

        -- Zustand 2: CD laeuft (nach Hysteria-Ende 180s warten)
        if self.endTime and self.endTime > GetTime() then
            local remaining = self.endTime - GetTime()
            self.timer:SetText(math.floor(remaining))
            self.timer:SetTextColor(1, 1, 0)
            self.statusText:SetText("CD")
            self.statusText:SetTextColor(0.6, 0.6, 0.6)
            self.border:Hide()
            return
        end

        -- Zustand 3: CD abgelaufen / noch nie benutzt = BEREIT
        -- Wenn endTime gerade abgelaufen ist -> Whisper senden
        if self.endTime ~= nil then
            self.endTime = nil
            if FeralHelperDB.hysteriaWhisperOnCdExpire ~= false and SendHysteriaWhisper and SendHysteriaWhisper() then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff33ff99FeralHelper:|r Hysteria CD abgelaufen - Whisper gesendet.")
            end
        end

        self.timer:SetText("")
        self.statusText:SetText("BEREIT")
        self.statusText:SetTextColor(1, 0.85, 0)
        -- Gold pulsieren
        self.border:SetVertexColor(1, 0.85, 0)
        self.border:SetAlpha(0.4 + 0.4 * math.sin(self.t * 2.5))
        self.border:Show()
        -- Cooldown-Wisch zuruecksetzen wenn bereit
        CooldownFrame_SetTimer(self.cd, 0, 0, 0)
    end)

    -- Verschieben nur mit Shift+Drag (sonst wuerde normaler Klick = drag)
    -- CreateMovableFrame hat schon RegisterForDrag gesetzt, Scripts ueberschreiben:
    hysteriaFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and CanMove() then
            self:StartMoving()
            self.isDragging = true
        end
    end)
    hysteriaFrame:SetScript("OnMouseUp", function(self, btn)
        if self.isDragging then
            self:StopMovingOrSizing()
            self.isDragging = false
            local point, _, relPoint, x, y = self:GetPoint()
            FeralHelperDB.framePositions[self:GetName()] = { point, relPoint, x, y }
        elseif btn == "LeftButton" then
            -- Buff gerade aktiv?
            local _, _, _, buffExp = GetAuraInfo("player", SPELL_HYSTERIA, "HELPFUL")
            if buffExp then
                local rem = math.floor(buffExp - GetTime())
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff33ff99FeralHelper:|r Hysteria laeuft noch |cffffff00" .. rem .. "s|r")
                return
            end
            -- CD laeuft noch?
            if self.endTime and self.endTime > GetTime() then
                local rem = math.floor(self.endTime - GetTime())
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff33ff99FeralHelper:|r Hysteria CD noch |cffffff00" .. rem .. "s|r")
                return
            end
            -- Bereit -> Whisper senden
            if FeralHelperDB.hysteriaWhisperOnClick == false then
                return
            end
            local target = FeralHelperDB.hysteriaTarget
            if target and target ~= "" then
                SendChatMessage(FH:GetWhisperText("whisperText"), "WHISPER", nil, target)
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff33ff99FeralHelper:|r Whisper an |cffffff00" .. target .. "|r gesendet.")
            else
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffff3333FeralHelper:|r Kein Ziel gesetzt. /feralhelper")
            end
        end
    end)

    RestoreFramePosition(hysteriaFrame)
end

local function StartHysteriaCooldown()
    if not hysteriaFrame then return end
    local now = GetTime()
    hysteriaFrame.endTime = now + HYSTERIA_CD
    CooldownFrame_SetTimer(hysteriaFrame.cd, now, HYSTERIA_CD, 1)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cff33ff99FeralHelper:|r Hysteria erhalten - 180s Cooldown laeuft.")
end

-- ============================================================
-- 2) HAND DES SCHUTZES - Button + Entfernen
-- ============================================================

local hopButton
local function CreateHoPButton()
    hopButton = CreateFrame("Button", "FeralHelperHoPButton", UIParent,
        "SecureActionButtonTemplate")
    hopButton:SetSize(96, 96)
    hopButton:SetMovable(true)
    hopButton:RegisterForDrag("LeftButton")
    hopButton:SetClampedToScreen(true)
    hopButton:ClearAllPoints()
    hopButton:SetPoint("CENTER", UIParent, "CENTER", 0, 100)

    local _, _, hopIcon = GetSpellInfo(1022)
    local tex = hopButton:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(hopIcon or "Interface\\Icons\\Spell_Holy_SealOfProtection")
    hopButton.icon = tex

    local border = hopButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetVertexColor(1, 0, 0)
    border:SetPoint("TOPLEFT", -10, 10)
    border:SetPoint("BOTTOMRIGHT", 10, -10)
    hopButton.border = border

    local label = hopButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOP", hopButton, "BOTTOM", 0, -4)
    label:SetTextColor(1, 0.2, 0.2)
    label:SetText("HoP entfernen!")

    -- Shift+Drag zum Verschieben (normaler Klick = cancelaura)
    hopButton:SetScript("OnDragStart", function(self)
        if CanMove() then self:StartMoving() end
    end)
    hopButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        FeralHelperDB.framePositions["FeralHelperHoPButton"] = { point, relPoint, x, y }
    end)

    -- type=macro mit /cancelaura (type=cancelaura buggy in 3.3.5a)
    hopButton:RegisterForClicks("AnyUp")
    hopButton:SetAttribute("type", "macro")
    hopButton:SetAttribute("macrotext", "/cancelaura " .. SPELL_HOP)

    hopButton:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        self.border:SetAlpha(0.5 + 0.5 * math.sin(self.t * 4))
    end)

    hopButton:Hide()
    RestoreFramePosition(hopButton)
end

local function UpdateHoPButton()
    local _, _, _, expTime = GetAuraInfo("player", SPELL_HOP, "HELPFUL")
    if expTime then
        hopButton:Show()
    else
        hopButton:Hide()
    end
end

-- ============================================================
-- 2b) FREIZAUBERN (VZ-Proc) - frei bewegliches Frame
-- ============================================================

local vzFrame
local function CreateVZFrame()
    vzFrame = CreateMovableFrame("FeralHelperVZFrame", 64, 90,
        { "CENTER", UIParent, "CENTER", 0, 0 })

    local _, _, vzIcon = GetSpellInfo(16870)
    local icon = vzFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOP", vzFrame, "TOP", 0, 0)
    icon:SetSize(64, 64)
    icon:SetTexture(vzIcon or "Interface\\Icons\\Spell_Shadow_ManaBurn")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    vzFrame.icon = icon

    local border = vzFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -14,  14)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  14, -14)
    vzFrame.border = border

    local timer = vzFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    vzFrame.timer = timer

    local statusText = vzFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", vzFrame, "TOP", 0, -68)
    statusText:SetText("Freizaubern")
    vzFrame.statusText = statusText

    -- OnUpdate: nur Animation wenn Frame bereits sichtbar
    vzFrame:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        local _, _, _, buffExp = GetAuraInfo("player", SPELL_CLEARCAST, "HELPFUL")
        if buffExp then
            local rem = buffExp > 0 and math.floor(buffExp - GetTime()) or 0
            self.timer:SetText(rem > 0 and rem or "")
            self.border:SetVertexColor(0.4, 1, 0.2)
            self.border:SetAlpha(0.6 + 0.4 * math.sin(self.t * 6))
            self.border:Show()
        end
    end)

    vzFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and CanMove() then
            self:StartMoving()
            self.isDragging = true
        end
    end)
    vzFrame:SetScript("OnMouseUp", function(self)
        if self.isDragging then
            self:StopMovingOrSizing()
            self.isDragging = false
            local point, _, relPoint, x, y = self:GetPoint()
            FeralHelperDB.framePositions[self:GetName()] = { point, relPoint, x, y }
        end
    end)

    vzFrame:Hide()
    RestoreFramePosition(vzFrame)
end

-- ============================================================
-- 2c) ROAR+RIP GLEICHZEITIG-WARNUNG
-- ============================================================

local roarRipFrame
local function CreateRoarRipFrame()
    roarRipFrame = CreateMovableFrame("FeralHelperRoarRipFrame", 130, 90,
        { "CENTER", UIParent, "CENTER", 200, 100 })

    local _, _, roarIcon = GetSpellInfo(SPELLID_SAVAGEROAR)
    local iconRoar = roarRipFrame:CreateTexture(nil, "ARTWORK")
    iconRoar:SetPoint("TOPLEFT", roarRipFrame, "TOPLEFT", 8, -4)
    iconRoar:SetSize(48, 48)
    iconRoar:SetTexture(roarIcon or "Interface\\Icons\\Ability_Druid_PrimalAgression")
    iconRoar:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    roarRipFrame.iconRoar = iconRoar

    local _, _, ripIcon = GetSpellInfo(SPELLID_RIP)
    local iconRip = roarRipFrame:CreateTexture(nil, "ARTWORK")
    iconRip:SetPoint("TOPRIGHT", roarRipFrame, "TOPRIGHT", -8, -4)
    iconRip:SetSize(48, 48)
    iconRip:SetTexture(ripIcon or "Interface\\Icons\\Ability_GhoulFrenzy")
    iconRip:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    roarRipFrame.iconRip = iconRip

    local borderRoar = roarRipFrame:CreateTexture(nil, "OVERLAY")
    borderRoar:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    borderRoar:SetBlendMode("ADD")
    borderRoar:SetPoint("TOPLEFT",     iconRoar, "TOPLEFT",     -14,  14)
    borderRoar:SetPoint("BOTTOMRIGHT", iconRoar, "BOTTOMRIGHT",  14, -14)
    borderRoar:Hide()
    roarRipFrame.borderRoar = borderRoar

    local borderRip = roarRipFrame:CreateTexture(nil, "OVERLAY")
    borderRip:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    borderRip:SetBlendMode("ADD")
    borderRip:SetPoint("TOPLEFT",     iconRip, "TOPLEFT",     -14,  14)
    borderRip:SetPoint("BOTTOMRIGHT", iconRip, "BOTTOMRIGHT",  14, -14)
    borderRip:Hide()
    roarRipFrame.borderRip = borderRip

    local timerRoar = roarRipFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    timerRoar:SetPoint("TOP", iconRoar, "BOTTOM", 0, -2)
    roarRipFrame.timerRoar = timerRoar

    local timerRip = roarRipFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    timerRip:SetPoint("TOP", iconRip, "BOTTOM", 0, -2)
    roarRipFrame.timerRip = timerRip

    local warnText = roarRipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warnText:SetPoint("BOTTOM", roarRipFrame, "BOTTOM", 0, 4)
    warnText:SetText("GLEICHZEITIG!")
    warnText:SetTextColor(1, 0.2, 0)
    roarRipFrame.warnText = warnText

    local elapsed = 0
    roarRipFrame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        self.t = (self.t or 0) + e

        if not IsInCatForm() then self:Hide(); return end

        local now = GetTime()
        local _, _, _, roarExp = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
        local ripExp = GetOwnRipOnTarget()

        if not roarExp or not ripExp then self:Hide(); return end

        local roarRem = roarExp - now
        local ripRem  = ripExp  - now

        if roarRem > ROARRIP_WINDOW or ripRem > ROARRIP_WINDOW then self:Hide(); return end
        if math.abs(roarRem - ripRem) >= ROARRIP_DELTA then self:Hide(); return end
        if FeralHelperDB.showRoarRipWarning == false then self:Hide(); return end

        self:Show()

        local function urgencyColor(rem)
            if rem < 3 then return 1, 0.1, 0.1
            elseif rem < 6 then return 1, 0.5, 0
            else return 1, 1, 0 end
        end
        local rr, rg, rb = urgencyColor(roarRem)
        local pr, pg, pb = urgencyColor(ripRem)
        self.timerRoar:SetText(math.max(0, math.floor(roarRem)))
        self.timerRip:SetText(math.max(0, math.floor(ripRem)))
        self.timerRoar:SetTextColor(rr, rg, rb)
        self.timerRip:SetTextColor(pr, pg, pb)

        local pulse = 0.6 + 0.4 * math.sin(self.t * 6)
        self.borderRoar:SetVertexColor(1, 0.3, 0)
        self.borderRoar:SetAlpha(pulse)
        self.borderRoar:Show()
        self.borderRip:SetVertexColor(1, 0.3, 0)
        self.borderRip:SetAlpha(pulse)
        self.borderRip:Show()
    end)

    roarRipFrame:Hide()
    RestoreFramePosition(roarRipFrame)
end

-- ============================================================
-- 2d) RIP SNAPSHOT ANZEIGE
-- ============================================================

local ripSnapshotFrame
local function CreateRipSnapshotFrame()
    ripSnapshotFrame = CreateMovableFrame("FeralHelperRipSnapshotFrame", 110, 80,
        { "CENTER", UIParent, "CENTER", 200, 0 })

    local _, _, ripIcon = GetSpellInfo(SPELLID_RIP)
    local iconRip = ripSnapshotFrame:CreateTexture(nil, "ARTWORK")
    iconRip:SetPoint("LEFT", ripSnapshotFrame, "LEFT", 8, 4)
    iconRip:SetSize(48, 48)
    iconRip:SetTexture(ripIcon or "Interface\\Icons\\Ability_GhoulFrenzy")
    iconRip:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ripSnapshotFrame.iconRip = iconRip

    local _, _, tfIcon = GetSpellInfo(5217)
    local iconTF = ripSnapshotFrame:CreateTexture(nil, "ARTWORK")
    iconTF:SetPoint("BOTTOMRIGHT", iconRip, "BOTTOMRIGHT", 8, -8)
    iconTF:SetSize(28, 28)
    iconTF:SetTexture(tfIcon or "Interface\\Icons\\Ability_Druid_CatFormAttack")
    iconTF:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconTF:SetAlpha(0.2)
    ripSnapshotFrame.iconTF = iconTF

    local border = ripSnapshotFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("TOPLEFT",     iconRip, "TOPLEFT",     -14,  14)
    border:SetPoint("BOTTOMRIGHT", iconRip, "BOTTOMRIGHT",  14, -14)
    border:Hide()
    ripSnapshotFrame.border = border

    local timerRip = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    timerRip:SetPoint("CENTER", iconRip, "CENTER", 0, 0)
    ripSnapshotFrame.timerRip = timerRip

    local stateLabel = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stateLabel:SetPoint("LEFT", iconRip, "RIGHT", 6, 4)
    stateLabel:SetJustifyH("LEFT")
    ripSnapshotFrame.stateLabel = stateLabel

    local tfLabel = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tfLabel:SetPoint("LEFT", iconRip, "RIGHT", 6, -12)
    tfLabel:SetJustifyH("LEFT")
    tfLabel:SetTextColor(0.8, 1, 0.2)
    ripSnapshotFrame.tfLabel = tfLabel

    local elapsed = 0
    ripSnapshotFrame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        self.t = (self.t or 0) + e

        if not IsInCatForm() then self:Hide(); return end

        local now = GetTime()
        local ripExp = GetOwnRipOnTarget()
        if not ripExp then self:Hide(); return end
        if FeralHelperDB.showRipSnapshot == false then self:Hide(); return end

        self:Show()

        local ripRem = math.max(0, ripExp - now)
        self.timerRip:SetText(math.floor(ripRem))

        local _, _, _, tfExp = GetAuraInfoById("player", 5217, "HELPFUL")
        local tfActive = tfExp ~= nil
        local tfRem = tfActive and math.max(0, tfExp - now) or 0

        self.iconTF:SetAlpha(tfActive and 1.0 or 0.2)
        self.tfLabel:SetText(tfActive and ("TF: " .. math.floor(tfRem) .. "s") or "")

        if tfActive and ripRem <= RIP_RECAST_THRESH then
            self.stateLabel:SetText("JETZT!")
            self.stateLabel:SetTextColor(1, 0.1, 0.1)
            self.timerRip:SetTextColor(1, 0.1, 0.1)
            self.border:SetVertexColor(1, 0.3, 0)
            self.border:SetAlpha(0.6 + 0.4 * math.sin(self.t * 6))
            self.border:Show()
        elseif tfActive then
            self.stateLabel:SetText("TF-aktiv")
            self.stateLabel:SetTextColor(0.2, 1, 0.2)
            self.timerRip:SetTextColor(0.2, 1, 0.2)
            self.border:SetVertexColor(0, 1, 0.2)
            self.border:SetAlpha(0.4 + 0.4 * math.sin(self.t * 2.5))
            self.border:Show()
        elseif ripRem <= RIP_RECAST_THRESH then
            self.stateLabel:SetText("ABLAUF")
            self.stateLabel:SetTextColor(1, 0.5, 0)
            self.timerRip:SetTextColor(1, 0.5, 0)
            self.border:SetVertexColor(1, 0.5, 0)
            self.border:SetAlpha(0.5 + 0.4 * math.sin(self.t * 4))
            self.border:Show()
        else
            self.stateLabel:SetText("Rip")
            self.stateLabel:SetTextColor(1, 0.7, 0.2)
            self.timerRip:SetTextColor(1, 0.7, 0.2)
            self.border:Hide()
        end
    end)

    ripSnapshotFrame:Hide()
    RestoreFramePosition(ripSnapshotFrame)
end

-- ============================================================
-- 3) COOLDOWN-TRACKER
-- ============================================================

local cdTracker
local cdIcons = {}

local function CreateCDIcon(parent, texture, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 40)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(texture)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    f.cd = cd

    -- Leuchtender Rand fuer aktive Procs / Buffs
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("TOPLEFT",     f, "TOPLEFT",     -20,  20)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  20, -20)
    border:Hide()
    f.border = border

    local timer = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    timer:SetPoint("CENTER")
    timer:SetTextColor(1, 1, 0)
    f.timer = timer

    f:SetAlpha(0.4)
    return f
end

local function CreateCDTracker()
    cdTracker = CreateMovableFrame("FeralHelperCDTracker", 650, 60,
        { "CENTER", UIParent, "CENTER", 0, -150 })

    local bg = cdTracker:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.3)

    -- Icons per SpellID laden (lokalisiert, korrekte Icons)
    local _, _, hyperspeedIcon  = GetSpellInfo(SPELLID_HYPERSPEED)
    local _, _, nitroIcon       = GetSpellInfo(SPELLID_NITRO)
    local _, _, barkskinIcon    = GetSpellInfo(22812)
    local _, _, berserkIcon     = GetSpellInfo(50334)
    local _, _, tigersIcon      = GetSpellInfo(5217)
    local _, _, clearcastIcon   = GetSpellInfo(16870)
    local _, _, innervateIcon   = GetSpellInfo(29166)
    local _, _, survInstIcon    = GetSpellInfo(61336)
    local _, _, frenziedIcon    = GetSpellInfo(22842)
    local _, _, rebirthIcon     = GetSpellInfo(20484)
    local _, _, schwertgarnIcon  = GetSpellInfo(55776)
    local _, _, bersEnchIcon     = GetSpellInfo(59620)
    local _, _, bearFormIcon     = GetSpellInfo(9634)
    local _, _, lightwaveIcon    = GetSpellInfo(55637)
    local _, _, blackmagicIcon   = GetSpellInfo(59626)
    local _, _, mongooseIcon     = GetSpellInfo(28093)
    local _, _, bloodDrainIcon   = GetSpellInfo(64568)
    local _, _, executionerIcon  = GetSpellInfo(42976)
    local _, _, crusaderIcon     = GetSpellInfo(20007)

    local weaponProcs = {
        { spellId=55776, icd=55, label="Schwertwallgarn" },
        { spellId=59626, icd=35, label="Black Magic" },
        { spellId=59620, icd=0,  label="Berserker" },
        { spellId=28093, icd=0,  label="Mongoose" },
        { spellId=64568, icd=0,  label="BlutAbzug" },
        { spellId=42976, icd=0,  label="Vollstrecker" },
        { spellId=20007, icd=0,  label="Kreuzritter" },
    }
    for _, p in ipairs(weaponProcs) do
        local _, _, t = GetSpellInfo(p.spellId)
        p.tex = t
    end

    -- clickTarget/clickText: Felder aus DB fuer Whisper beim Klick
    local entries = {
        { key="barkskin",    tex=barkskinIcon,   label="Baumrinde",    type="spell",      spell=SPELL_BARKSKIN },
        { key="berserk",     tex=berserkIcon,    label="Berserk",      type="spell",      spell=SPELL_BERSERK,     selfCast=true },
        { key="tigersfury",  tex=tigersIcon,     label="Tigerwut",     type="spell",      spell=SPELL_TIGERSFURY,  selfCast=true, hideInBear=true, slotIndex=3 },
        { key="frenziedreg", tex=frenziedIcon,   label="RasReg",       type="spell",      spell=SPELL_FRENZIEDREG, selfCast=true, bearOnly=true, slotIndex=3 },
        { key="survinst",    tex=survInstIcon,   label="UeberInst",    type="spell",      spell=SPELL_SURVINST, selfCast=true },
        { key="innervate",   tex=innervateIcon,  label="Anregen",      type="spell",      spell=SPELL_INNERVATE,
          clickText="Ich wirke Anregen auf dich!", friendlyAliveOnly=true, requireInRange=true },
        { key="rebirth",     tex=rebirthIcon,    label="Wiedergeburt", type="spell",      spell=SPELL_REBIRTH,
          clickText="Ich wirke Wiedergeburt auf dich!", deadOnly=true, noWhisper=true, sayOutOfRange=true },
        { key="trinket1",    tex="Interface\\Icons\\INV_Misc_QuestionMark", label="Trinket 1", type="item-slot", slot=SLOT_TRINKET1 },
        { key="trinket2",    tex="Interface\\Icons\\INV_Misc_QuestionMark", label="Trinket 2", type="item-slot", slot=SLOT_TRINKET2 },
        { key="hands", tex=hyperspeedIcon, label="Hyperspeed", type="item-slot", slot=SLOT_HANDS, noAutoIcon=true,
          procSpell=GetSpellInfo(SPELLID_HYPERSPEED), clickUseSlot=SLOT_HANDS },
        { key="feet",  tex=nitroIcon,      label="Nitro",       type="item-slot", slot=SLOT_FEET,  noAutoIcon=true,
          procSpell=GetSpellInfo(SPELLID_NITRO), clickUseSlot=SLOT_FEET },
        { key="weaponvz",   tex="Interface\\Icons\\INV_Weapon_ShortBlade_30",
          label="Waffe VZ", type="weapon-enchant", procs=weaponProcs, hideWhenInactive=true },
        { key="lightweave", tex=lightwaveIcon or "Interface\\Icons\\Trade_Tailoring",
          label="Lightweave", type="aura", spellId=55637, icd=60, hideWhenInactive=true },
        { key="ring1", tex="Interface\\Icons\\INV_Misc_QuestionMark",
          label="Ring 1", type="item-slot", slot=11, procOnly=true },
        { key="ring2", tex="Interface\\Icons\\INV_Misc_QuestionMark",
          label="Ring 2", type="item-slot", slot=12, procOnly=true },
        { key="panic", tex=bearFormIcon or "Interface\\Icons\\Ability_Racial_BearForm",
          label="Panik", type="panic",
          macrotext="/cast [noform:1] " .. SPELL_BEARFORM
                 .. "\n/cancelaura " .. SPELL_HYSTERIA
                 .. "\n/cast " .. SPELL_BARKSKIN
                 .. "\n/cast [form:1] " .. SPELL_ENRAGE
                 .. "\n/cast [form:1] " .. SPELL_SURVINST },
    }

    local visualIndex = 0
    for i, e in ipairs(entries) do
        local icon = CreateCDIcon(cdTracker, e.tex or "Interface\\Icons\\INV_Misc_QuestionMark", e.label)
        local slotIndex = e.slotIndex
        if slotIndex then
            visualIndex = math.max(visualIndex, slotIndex)
        else
            visualIndex = visualIndex + 1
            slotIndex = visualIndex
        end
        icon:SetPoint("LEFT", cdTracker, "LEFT", (slotIndex - 1) * 42 + 4, 8)
        icon.entry = e
        cdIcons[e.key] = icon
        if e.hideWhenInactive or e.bearOnly then icon:Hide() end

        -- Panik-Knopf: 1 Klick aus Bärengestalt = alles sofort
        -- aus Katze/Kaster: 1. Klick -> Bär+Baumrinde, 2. Klick -> Wutanfall+ÜberInst
        if e.type == "panic" then
            local btn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
            btn:SetAllPoints(icon)
            btn:RegisterForClicks("AnyDown", "AnyUp")
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext",
                "/cast [noform:1] " .. SPELL_BEARFORM ..
                "\n/cancelaura " .. SPELL_HYSTERIA ..
                "\n/cast " .. SPELL_BARKSKIN ..
                "\n/cast [form:1] " .. SPELL_ENRAGE ..
                "\n/cast [form:1] " .. SPELL_SURVINST)
        end

        -- Ingi-Tinker: Klick benutzt Item im jeweiligen Slot (/use slot)
        if e.clickUseSlot then
            local ent = e
            local secBtn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
            secBtn:SetAllPoints(icon)
            secBtn:RegisterForClicks("AnyUp")
            secBtn:SetAttribute("type", "macro")
            secBtn:SetAttribute("macrotext", "/use " .. ent.clickUseSlot)
        end

        -- Ueberlebensinstinkte: SecureActionButton zum Selbst-Casten
        if e.selfCast then
            local ent = e
            local secBtn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
            secBtn:SetAllPoints(icon)
            secBtn:RegisterForClicks("AnyUp")
            secBtn:SetAttribute("type",  "spell")
            secBtn:SetAttribute("spell", ent.spell)
            -- kein unit -> castet auf sich selbst (Self-Buff)
        end

        -- Anregen + Wiedergeburt: SecureActionButton als unsichtbare Overlay-Schicht.
        -- Nur SecureActionButton darf Spells im Kampf casten (protected action).
        -- PostClick ist "insecure" und darf SendChatMessage aufrufen.
        if e.clickText then
            local ent = e  -- lokale Kopie fuer Closure
            local secBtn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
            secBtn:SetAllPoints(icon)
            secBtn:RegisterForClicks("AnyUp")
            if ent.deadOnly then
                -- Nur casten wenn Ziel tot ([@target,dead])
                secBtn:SetAttribute("type", "macro")
                secBtn:SetAttribute("macrotext", "/cast [@target,dead] " .. ent.spell)
            elseif ent.friendlyAliveOnly then
                -- Nur casten wenn Ziel lebt und freundlich
                secBtn:SetAttribute("type", "macro")
                secBtn:SetAttribute("macrotext", "/cast [@target,nodead,help] " .. ent.spell)
            else
                secBtn:SetAttribute("type",  "spell")
                secBtn:SetAttribute("spell", ent.spell)
                secBtn:SetAttribute("unit",  "target")
            end

            -- CD-Status VOR dem Klick merken (OnMouseDown kommt vor SecureAction)
            secBtn:SetScript("OnMouseDown", function(self)
                local s, d = GetSpellCooldown(ent.spell)
                if s and d and d > 1.5 then
                    self.preClickOnCd  = true
                    self.preClickRem   = math.max(0, math.floor(d - (GetTime() - s)))
                else
                    self.preClickOnCd  = false
                    self.preClickRem   = 0
                end
            end)

            -- PostClick: Checks und optional Whisper/Sagen
            secBtn:SetScript("PostClick", function(self)
                if self.preClickOnCd then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff33ff99FeralHelper:|r " .. ent.spell
                        .. " CD noch |cffffff00" .. self.preClickRem .. "s|r")
                    if FeralHelperDB.cdToSay then
                        SendChatMessage(ent.label .. " CD: " .. self.preClickRem .. "s", "SAY")
                    end
                    return
                end
                local target = UnitName("target")
                if not target or target == "Unknown" then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cffff3333FeralHelper:|r Kein Ziel ausgewaehlt!")
                    return
                end
                if ent.deadOnly and not UnitIsDead("target") then
                    return
                end
                if ent.friendlyAliveOnly then
                    if UnitIsDead("target") then return end
                    if not UnitIsFriend("player", "target") then return end
                end
                if ent.sayOutOfRange or ent.requireInRange then
                    local inRange = IsSpellInRange(ent.spell, "target")
                    if inRange ~= 1 then
                        if ent.sayOutOfRange and FeralHelperDB.outOfRangeToSay ~= false then
                            SendChatMessage(target .. " nicht in Reichweite", "SAY")
                        end
                        return
                    end
                end
                if not ent.noWhisper and FeralHelperDB.innervateWhisperEnabled ~= false then
                    local text = (ent.key == "innervate" and FH:GetWhisperText("innervateWhisper"))
                                 or ent.clickText
                    SendChatMessage(text, "WHISPER", nil, target)
                end
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff33ff99FeralHelper:|r |cffffff00" .. ent.spell
                    .. "|r gewirkt auf |cffffff00" .. target .. "|r")
            end)
        end
    end

    local elapsed = 0
    local cdTime  = 0
    cdTracker:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        cdTime  = cdTime  + e
        if elapsed < 0.1 then return end
        elapsed = 0

        for _, icon in pairs(cdIcons) do repeat
            local ent = icon.entry

            if FH.iconTestMode then
                icon:Show()
                icon:SetAlpha(1.0)
                icon.timer:SetText("42")
                icon.border:SetVertexColor(0, 1, 0.2)
                icon.border:SetAlpha(0.8)
                icon.border:Show()
                CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                break
            end

            local isBear = IsInBearForm()

            if ent.hideInBear and isBear then
                icon:Hide()
                icon.timer:SetText("")
                icon.border:Hide()
                CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                break
            elseif ent.bearOnly and not isBear then
                icon:Hide()
                icon.timer:SetText("")
                icon.border:Hide()
                CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                break
            elseif ent.hideInBear or ent.bearOnly then
                icon:Show()
            end

            if ent.type == "spell" then
                local start, dur, enabled = GetSpellCooldown(ent.spell)
                if start and dur and dur > 1.5 then
                    icon:SetAlpha(0.4)
                    icon.timer:SetText(math.floor(dur - (GetTime() - start)))
                    CooldownFrame_SetTimer(icon.cd, start, dur, enabled)
                    icon.border:Hide()
                else
                    icon:SetAlpha(1.0)
                    icon.timer:SetText("")
                    CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                    icon.border:Hide()
                end

            elseif ent.type == "item-slot" then
                -- Icon dynamisch vom Item holen (nicht bei Ingi-Tinkern)
                if not ent.noAutoIcon then
                    local itemTex = GetInventoryItemTexture("player", ent.slot)
                    if itemTex then icon.icon:SetTexture(itemTex) end
                end

                -- Proc-Buff prüfen
                local procActive = false
                local itemId = GetInventoryItemID("player", ent.slot)
                local procData = itemId and TRINKET_PROCS[itemId]
                if ent.procOnly and not procData then
                    icon:Hide()
                    break
                end
                if procData then
                    -- Name-basiert
                    for _, buffName in ipairs(procData.names) do
                        local _, _, _, exp = GetAuraInfo("player", buffName, "HELPFUL")
                        if exp then procActive = true; break end
                    end
                    -- ID-basiert als Fallback (falls GetSpellInfo Namen nicht aufgeloest hat)
                    if not procActive then
                        local rawData = _TRINKET_PROC_IDS[itemId]
                        if rawData then
                            for _, sid in ipairs(rawData.spells) do
                                local _, _, _, exp = GetAuraInfoById("player", sid, "HELPFUL")
                                if exp then procActive = true; break end
                            end
                        end
                    end
                end
                if ent.procSpell and not procActive then
                    local _, _, _, exp = GetAuraInfo("player", ent.procSpell, "HELPFUL")
                    if exp then procActive = true end
                end

                -- Proc-Übergang aktiv→inaktiv: synthetischen ICD starten
                -- falls GetInventoryItemCooldown keinen CD liefert (passive ICDs)
                if procActive then
                    icon.procWasActive = true
                else
                    if icon.procWasActive then
                        icon.procWasActive = false
                        local s, d = GetInventoryItemCooldown("player", ent.slot)
                        if not (s and d and d > 1.5) then
                            local icd = (procData and procData.icd) or 45
                            icon.synthCDEnd = GetTime() + icd
                        end
                    end
                end

                local start, dur, enabled = GetInventoryItemCooldown("player", ent.slot)
                local realCD = start and dur and dur > 1.5
                local synthCD = icon.synthCDEnd and icon.synthCDEnd > GetTime()

                if procActive then
                    icon:SetAlpha(1.0)
                    icon.border:SetVertexColor(0, 1, 0.2)
                    icon.border:SetAlpha(0.6 + 0.4 * math.sin(cdTime * 6))
                    icon.border:Show()
                    if realCD then
                        CooldownFrame_SetTimer(icon.cd, start, dur, enabled)
                        icon.timer:SetText(math.floor(start + dur - GetTime()))
                    else
                        CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                        icon.timer:SetText("")
                    end
                elseif realCD then
                    icon:SetAlpha(0.4)
                    icon.timer:SetText(math.floor(start + dur - GetTime()))
                    CooldownFrame_SetTimer(icon.cd, start, dur, enabled)
                    icon.border:Hide()
                    icon.synthCDEnd = nil
                elseif synthCD then
                    icon:SetAlpha(0.4)
                    icon.timer:SetText(math.floor(icon.synthCDEnd - GetTime()))
                    CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                    icon.border:Hide()
                else
                    icon:SetAlpha(1.0)
                    icon.timer:SetText("")
                    CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                    icon.border:Hide()
                end

            elseif ent.type == "panic" then
                icon:SetAlpha(1.0)
                icon.timer:SetText("")
                icon.border:SetVertexColor(1, 0.1, 0.1)
                icon.border:SetAlpha(0.4 + 0.4 * math.sin(cdTime * 3))
                icon.border:Show()

            elseif ent.type == "aura" then
                local expTime
                -- SpellID-basiert zuerst
                if ent.spellId then
                    local _, _, _, exp = GetAuraInfoById("player", ent.spellId, "HELPFUL")
                    expTime = exp
                end
                -- Name-basiert als Fallback
                if not expTime and ent.spell then
                    local _, _, _, exp = GetAuraInfo("player", ent.spell, "HELPFUL")
                    expTime = exp
                end
                -- Zusaetzliche Name-Varianten (extraSpells)
                if not expTime and ent.extraSpells then
                    for _, n in ipairs(ent.extraSpells) do
                        if n then
                            local _, _, _, exp = GetAuraInfo("player", n, "HELPFUL")
                            if exp then expTime = exp; break end
                        end
                    end
                end
                if expTime then
                    icon.auraWasActive = true
                    icon.synthCDEnd = nil
                    icon:Show()
                    icon:SetAlpha(1.0)
                    icon.timer:SetText(math.floor(expTime - GetTime()))
                    icon.border:SetVertexColor(0, 1, 0.2)
                    icon.border:SetAlpha(0.6 + 0.4 * math.sin(cdTime * 6))
                    icon.border:Show()
                else
                    if icon.auraWasActive then
                        icon.auraWasActive = false
                        if ent.icd and ent.icd > 0 then
                            icon.synthCDEnd = GetTime() + ent.icd
                        end
                    end
                    local synthCD = icon.synthCDEnd and icon.synthCDEnd > GetTime()
                    if synthCD then
                        icon:Show()
                        icon:SetAlpha(0.4)
                        icon.timer:SetText(math.floor(icon.synthCDEnd - GetTime()))
                        icon.border:Hide()
                    elseif ent.hideWhenInactive then
                        icon:Hide()
                        icon.synthCDEnd = nil
                    else
                        icon:SetAlpha(0.4)
                        icon.timer:SetText("")
                        icon.border:Hide()
                    end
                end
            elseif ent.type == "weapon-enchant" then
                local activeProc = nil
                for _, p in ipairs(ent.procs) do
                    local _, _, _, exp = GetAuraInfoById("player", p.spellId, "HELPFUL")
                    if exp then activeProc = { exp=exp, icd=p.icd, tex=p.tex }; break end
                end
                if activeProc then
                    if activeProc.tex then icon.icon:SetTexture(activeProc.tex) end
                    icon.weProcActive = true
                    icon.weActiveIcd  = activeProc.icd
                    icon.synthCDEnd   = nil
                    icon:Show()
                    icon:SetAlpha(1.0)
                    icon.timer:SetText(math.floor(activeProc.exp - GetTime()))
                    icon.border:SetVertexColor(0, 1, 0.2)
                    icon.border:SetAlpha(0.6 + 0.4 * math.sin(cdTime * 6))
                    icon.border:Show()
                else
                    if icon.weProcActive then
                        icon.weProcActive = false
                        if icon.weActiveIcd and icon.weActiveIcd > 0 then
                            icon.synthCDEnd = GetTime() + icon.weActiveIcd
                        end
                        icon.weActiveIcd = nil
                    end
                    local synthCD = icon.synthCDEnd and icon.synthCDEnd > GetTime()
                    if synthCD then
                        icon:Show()
                        icon:SetAlpha(0.4)
                        icon.timer:SetText(math.floor(icon.synthCDEnd - GetTime()))
                        icon.border:Hide()
                    elseif ent.hideWhenInactive then
                        icon:Hide()
                        icon.synthCDEnd = nil
                    else
                        icon:SetAlpha(0.4)
                        icon.timer:SetText("")
                        icon.border:Hide()
                    end
                end
            end

            -- Ueberlebensinstinkte: Countdown in /say wenn <=3.5s Restdauer
            if ent.key == "survinst" then
                local _, _, _, expTime = GetAuraInfo("player", SPELL_SURVINST, "HELPFUL")
                if expTime then
                    icon.survGoneFrames = 0
                    local rem      = expTime - GetTime()
                    local remFloor = math.floor(rem)
                    -- rem > 0.2 verhindert Mehrfach-Feuer durch Latenz am Buff-Ende
                    if rem > 0.2 and rem <= 3.5 and remFloor ~= icon.lastCountdown then
                        icon.lastCountdown = remFloor
                        if FeralHelperDB.survInstCountdownSay ~= false then
                            SendChatMessage("läuft aus in " .. remFloor, "SAY")
                        end
                    end
                else
                    -- erst nach 5 frames ohne Buff als wirklich weg werten (Latenzsschutz)
                    icon.survGoneFrames = (icon.survGoneFrames or 0) + 1
                    if icon.survGoneFrames >= 5 then
                        icon.lastCountdown  = nil
                        icon.survGoneFrames = 0
                    end
                end
            end
        until true end
    end)

    RestoreFramePosition(cdTracker)
end

-- ============================================================
-- Frames sperren / Sichtbarkeit
-- ============================================================

function FH:SetLocked(locked)
    if self.configFrame and self.configFrame.lockBtn then
        self.configFrame.lockBtn:SetText(locked and "Frames entsperren" or "Frames sperren")
    end
end

function FH:ApplyVisibility()
    if hysteriaFrame then
        if FeralHelperDB.showHysteriaFrame == false then
            hysteriaFrame:Hide()
        else
            hysteriaFrame:Show()
        end
    end
    if vzFrame then
        if FeralHelperDB.showVZFrame == false then
            vzFrame:Hide()
        else
            local _, _, _, vzExp = GetAuraInfo("player", SPELL_CLEARCAST, "HELPFUL")
            if vzExp then vzFrame:Show() else vzFrame:Hide() end
        end
    end
    if cdTracker then
        if FeralHelperDB.showCDTracker == false then
            cdTracker:Hide()
        else
            cdTracker:Show()
        end
    end
    if roarRipFrame and FeralHelperDB.showRoarRipWarning == false then
        roarRipFrame:Hide()
    end
    if ripSnapshotFrame and FeralHelperDB.showRipSnapshot == false then
        ripSnapshotFrame:Hide()
    end
end

-- ============================================================
-- Minimap-Button
-- ============================================================

local minimapButton
local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "FeralHelperMinimapButton", Minimap)
    minimapButton:SetSize(22, 22)
    minimapButton:SetFrameLevel(8)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local _, _, iconTex = GetSpellInfo(50334)
    minimapButton:SetNormalTexture(iconTex or "Interface\\Icons\\Ability_Druid_Berserk")
    minimapButton:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)
    minimapButton:SetPushedTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function UpdatePos(angle)
        local rad = math.rad(angle)
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * 80, math.sin(rad) * 80)
    end

    UpdatePos(FeralHelperDB.minimapAngle or 220)

    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            FeralHelperDB.minimapAngle = angle
            UpdatePos(angle)
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            FeralHelper:CreateConfigFrame()
        elseif btn == "RightButton" then
            FeralHelperDB.framesLocked = not FeralHelperDB.framesLocked
            FH:SetLocked(FeralHelperDB.framesLocked)
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99FeralHelper:|r Frames "
                .. (FeralHelperDB.framesLocked and "|cffff3333gesperrt|r" or "|cff33ff99entsperrt|r"))
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33ff99FeralHelper|r")
        GameTooltip:AddLine("Links: Einstellungen", 1, 1, 1)
        GameTooltip:AddLine("Rechts: Frames sperren/entsperren", 1, 1, 1)
        GameTooltip:AddLine("Ziehen: Position anpassen", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- ============================================================
-- 4) Setup-Guide (einmalig beim ersten Login)
-- ============================================================

local function ShowSetupGuide()
    local c  = "|cff33ff99"   -- grün
    local y  = "|cffffff00"   -- gelb
    local w  = "|cffffffff"   -- weiß
    local r  = "|r"
    local p  = c .. "FeralHelper" .. r
    local function m(t) DEFAULT_CHAT_FRAME:AddMessage(t) end

    m(p .. " - Ersteinrichtung")
    m(y .. "───────────────────────────────" .. r)
    m(p .. " Befehle:")
    m("  " .. y .. "/fh" .. r            .. w .. "          -> Einstellungen (Hysteria-Ziel, Whisper-Text)" .. r)
    m("  " .. y .. "/fh reset" .. r      .. w .. "    -> Fenster-Positionen zurücksetzen (dann /reload)" .. r)
    m("  " .. y .. "Minimap-Icon" .. r   .. w .. "   Links: /fh | Rechts: Frames sperren | Ziehen: Position" .. r)
    m(y .. "───────────────────────────────" .. r)
    m(p .. " Elemente:")
    m("  " .. y .. "Hysteria-Frame" .. r   .. w .. "  Zeigt Buff-Dauer, 180s CD, sendet Whisper bei Kampfstart" .. r)
    m("                   " .. w .. "Shift+Drag zum Verschieben. Klick = Whisper sofort senden." .. r)
    m("  " .. y .. "HoP-Button" .. r       .. w .. "      Erscheint wenn Hand des Schutzes aktiv -> klicken entfernt Buff" .. r)
    m("  " .. y .. "Freizaubern" .. r      .. w .. "     Erscheint wenn Klarsicht-Proc aktiv (Shift+Drag)" .. r)
    m("  " .. y .. "CD-Leiste" .. r        .. w .. "       Baumrinde / Berserk / Tigerwut bzw. Rasende Regeneration / Überlebensinstinkte" .. r)
    m("                   " .. w .. "Anregen / Wiedergeburt (Klick -> wirkt auf Ziel + Whisper)" .. r)
    m("                   " .. w .. "Trinket 1+2 (Proc grün / ICD gedimmt) / Handschuhe / Schuhe" .. r)
    m("                   " .. w .. "Schwertwallgarn + Berserker-VZ (nur sichtbar wenn aktiv)" .. r)
    m("  " .. y .. "Panik-Knopf" .. r     .. w .. "     1x klicken: Terrorbärengestalt + Baumrinde sofort," .. r)
    m("                   " .. w .. "dann Wutanfall + Überlebensinstinkte nach 0.4s" .. r)
    m(y .. "───────────────────────────────" .. r)
    m(p .. w .. " Einstellungen unter " .. r .. y .. "/fh" .. r .. w .. " öffnen und Hysteria-Ziel setzen." .. r)
end

-- ============================================================
-- 4) Events
-- ============================================================

local main = CreateFrame("Frame")
main:RegisterEvent("ADDON_LOADED")
main:RegisterEvent("PLAYER_LOGIN")
main:RegisterEvent("PLAYER_REGEN_DISABLED")
main:RegisterEvent("UNIT_AURA")
main:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

SendHysteriaWhisper = function()
    local target = FeralHelperDB.hysteriaTarget
    if target and target ~= "" then
        SendChatMessage(FH:GetWhisperText("whisperText"), "WHISPER", nil, target)
        return true
    end
    return false
end

local delayFrame = CreateFrame("Frame")
local function ScheduleAfter(seconds, fn)
    local t = 0
    delayFrame:SetScript("OnUpdate", function(self, e)
        t = t + e
        if t >= seconds then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

main:SetScript("OnEvent", function(self, event, arg1, ...)
    -- arg1 = erstes Event-Argument, "..." = alle weiteren

    if event == "ADDON_LOADED" and arg1 == "feralhelper-addon-master" then
        FeralHelperDB = FeralHelperDB or {}
        for k, v in pairs(FH.defaults) do
            if FeralHelperDB[k] == nil then
                FeralHelperDB[k] = (type(v) == "table") and {} or v
            end
        end
        if FH.RegisterInterfaceOptions then
            FH:RegisterInterfaceOptions()
        end

    elseif event == "PLAYER_LOGIN" then
        if not IsDruidPlayer() then
            DisableForNonDruid(self)
            return
        end
        addonActive = true
        FH.disabled = nil
        BuildTrinketProcNames()
        CreateHysteriaFrame()
        CreateHoPButton()
        CreateVZFrame()
        CreateCDTracker()
        CreateRoarRipFrame()
        CreateRipSnapshotFrame()
        CreateMinimapButton()
        FH:ApplyVisibility()
        if FeralHelperDB.firstRun then
            FeralHelperDB.firstRun = false
            ShowSetupGuide()
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99FeralHelper|r geladen. "
                .. "|cffffff00/fh|r = Einstellungen, "
                .. "|cffffff00/fh reset|r = Positionen zuruecksetzen. "
                .. "Minimap-Icon Rechtsklick = Frames sperren/entsperren.")
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- 3s nach Kampfbeginn Whisper senden
        ScheduleAfter(3, function()
            if not InCombatLockdown() then return end
            if FeralHelperDB.hysteriaWhisperOnCombat == false then return end
            local target = FeralHelperDB.hysteriaTarget
            if not target or target == "" then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffff3333FeralHelper:|r Kein Boesartigkeits-Spieler gesetzt! /feralhelper")
                return
            end
            -- Nur whispern wenn Hysteria nicht gerade laeuft
            if hysteriaFrame.endTime and hysteriaFrame.endTime > GetTime() then
                return
            end
            SendHysteriaWhisper()
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99FeralHelper:|r Whisper an " .. target .. " gesendet.")
        end)

    elseif event == "UNIT_AURA" and arg1 == "player" then
        if hopButton then UpdateHoPButton() end
        if vzFrame then
            local _, _, _, vzExp = GetAuraInfo("player", SPELL_CLEARCAST, "HELPFUL")
            if vzExp and FeralHelperDB.showVZFrame ~= false then vzFrame:Show() else vzFrame:Hide() end
        end

        -- Ueberlebensinstinkte: wenn Buff neu erscheint -> /say
        local _, _, _, siExp = GetAuraInfo("player", SPELL_SURVINST, "HELPFUL")
        if siExp and not survInstExpiry and FeralHelperDB.survInstActiveSay ~= false then
            SendChatMessage("Überlebensinstinkte aktiv!", "SAY")
        end
        survInstExpiry = siExp

        -- Hand des Schutzes: wenn Buff entfernt wird (durch Klick) -> /say
        local hopActive = GetAuraInfo("player", SPELL_HOP, "HELPFUL")
        if not hopActive and FH.hopWasActive and FeralHelperDB.hopRemovedSay ~= false then
            SendChatMessage("Hand des Schutzes entfernt!", "SAY")
        end
        FH.hopWasActive = hopActive and true or false

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- WICHTIG: arg1 = timestamp, "..." beginnt bei subevent
        -- (nicht nochmal timestamp aus "..." entpacken - das war der Bug)
        local subevent, _, srcName, _,
              destGUID, destName, _, spellId, spellName = ...

        if subevent == "SPELL_AURA_APPLIED"
           and destGUID == UnitGUID("player")
           and (spellId == 49016 or spellName == SPELL_HYSTERIA) then
            StartHysteriaCooldown()
        end
    end
end)

-- ============================================================
-- 5) Slash-Commands
-- ============================================================
SLASH_FERALHELPER1 = "/feralhelper"
SLASH_FERALHELPER2 = "/fh"
SlashCmdList["FERALHELPER"] = function(msg)
    if not addonActive then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper|r ist nur für Druiden aktiv.")
        return
    end
    msg = msg and msg:lower() or ""
    if msg == "reset" then
        FeralHelperDB.framePositions = {}
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Positionen zurueckgesetzt. /reload")
    elseif msg == "icons" then
        FH.iconTestMode = not FH.iconTestMode
        if cdTracker then cdTracker:Show() end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Icon-Test "
            .. (FH.iconTestMode and "|cff33ff99AN|r" or "|cffff3333AUS|r")
            .. " - nochmal |cffffff00/fh icons|r zum Ausschalten.")
    elseif msg == "test" then
        -- Zwingt beide Katzen-Frames sichtbar (Positions-Test)
        if roarRipFrame then
            roarRipFrame:ClearAllPoints()
            roarRipFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
            roarRipFrame:Show()
            roarRipFrame.timerRoar:SetText("5")
            roarRipFrame.timerRip:SetText("4")
            roarRipFrame.borderRoar:SetVertexColor(1, 0.3, 0)
            roarRipFrame.borderRoar:SetAlpha(0.8)
            roarRipFrame.borderRoar:Show()
            roarRipFrame.borderRip:SetVertexColor(1, 0.3, 0)
            roarRipFrame.borderRip:SetAlpha(0.8)
            roarRipFrame.borderRip:Show()
        end
        if ripSnapshotFrame then
            ripSnapshotFrame:ClearAllPoints()
            ripSnapshotFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            ripSnapshotFrame:Show()
            ripSnapshotFrame.timerRip:SetText("12")
            ripSnapshotFrame.stateLabel:SetText("TF-aktiv")
            ripSnapshotFrame.stateLabel:SetTextColor(0.2, 1, 0.2)
            ripSnapshotFrame.timerRip:SetTextColor(0.2, 1, 0.2)
            ripSnapshotFrame.iconTF:SetAlpha(1.0)
            ripSnapshotFrame.tfLabel:SetText("TF: 8s")
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Test-Frames angezeigt. "
            .. "Sichtbar? Dann ist Position das Problem -> |cffffff00/fh reset|r")
    elseif msg == "debug" then
        local m = DEFAULT_CHAT_FRAME
        local y = "|cffffff00"; local r = "|r"; local g = "|cff33ff99"
        m:AddMessage(g .. "FeralHelper Debug:" .. r)
        m:AddMessage("  Katzenform: " .. y .. tostring(IsInCatForm()) .. r
            .. "  (Slot: " .. y .. tostring(GetShapeshiftForm()) .. r
            .. ", CatSlot: " .. y .. tostring(catFormSlot) .. r .. ")")
        local _, _, _, roarExp = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
        m:AddMessage("  Savage Roar (" .. SPELL_SAVAGEROAR .. "): "
            .. y .. (roarExp and math.floor(roarExp - GetTime()) .. "s" or "NICHT AKTIV") .. r)
        local ripExp = GetOwnRipOnTarget()
        m:AddMessage("  Rip (" .. SPELL_RIP .. ") auf Ziel: "
            .. y .. (ripExp and math.floor(ripExp - GetTime()) .. "s" or "NICHT AKTIV") .. r)
        local _, _, _, tfExp = GetAuraInfo("player", SPELL_TIGERSFURY, "HELPFUL")
        m:AddMessage("  Tiger's Fury: "
            .. y .. (tfExp and math.floor(tfExp - GetTime()) .. "s" or "NICHT AKTIV") .. r)
        m:AddMessage("  showRoarRipWarning: " .. y .. tostring(FeralHelperDB.showRoarRipWarning) .. r)
        m:AddMessage("  showRipSnapshot: " .. y .. tostring(FeralHelperDB.showRipSnapshot) .. r)
    else
        FH:CreateConfigFrame()
    end
end
