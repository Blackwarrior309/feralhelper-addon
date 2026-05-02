-- ============================================================
-- FeralHelper.lua - Hauptlogik
-- ============================================================

FeralHelper = FeralHelper or {}
local FH = FeralHelper

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
local SPELL_REBIRTH     = GetSpellInfo(20484) or "Wiedergeburt"
local SPELL_BEARFORM    = GetSpellInfo(9634)  or "Terrorbärengestalt"
local SPELL_ENRAGE      = GetSpellInfo(5229)  or "Wutanfall"
local SPELL_SCHWERTGARN = GetSpellInfo(55776) or "Schwertwallgarn"

-- icd = Internal Cooldown in Sekunden (fuer synthetischen CD nach Proc-Ende)
local _TRINKET_PROC_IDS = {
    [50351] = { icd=45, spells={ 71887 } }, [50352] = { icd=45, spells={ 71887 } },  -- Death's Verdict (N)
    [50353] = { icd=45, spells={ 71888 } }, [50354] = { icd=45, spells={ 71888 } },  -- Death's Verdict (H)
    [50343] = { icd=45, spells={ 71901 } }, [50344] = { icd=45, spells={ 71901 } },  -- Whispering Fanged Skull (N)
    [50346] = { icd=45, spells={ 71900 } }, [50347] = { icd=45, spells={ 71900 } },  -- Whispering Fanged Skull (H)
    [50733] = { icd=45, spells={ 71879 } }, [50734] = { icd=45, spells={ 71880 } },  -- Needle-Encrusted Scorpion
    [45931] = { icd=45, spells={ 75171 } },                                           -- Mjolnir Runestone
    [46130] = { icd=45, spells={ 60229 } }, [47115] = { icd=45, spells={ 60229 } },  -- Darkmoon Card: Greatness
    [50363] = { icd=105, spells={ 71485, 71486, 71484, 71491, 71488 } },              -- Deathbringer's Will (N)
    [50364] = { icd=105, spells={ 71485, 71486, 71484, 71491, 71488 } },              -- Deathbringer's Will (H)
    [54590] = { icd=45, spells={ 75473 }, extra={ "Durchbohrendes Zwielicht" } },       -- Sharpened Twilight Scale (N)
    [54718] = { icd=45, spells={ 75466 }, extra={ "Durchbohrendes Zwielicht" } },       -- Sharpened Twilight Scale (H)
    [50355] = { icd=45, spells={ 71873 } }, [71396] = { icd=45, spells={ 71873 } },   -- Herkumlkriegsabzeichen
    [47214] = { icd=43, spells={ 67671 } }, [67671] = { icd=43, spells={ 67671 } },   -- Banner des Sieges
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
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
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
            if InCombatLockdown() then
                local target = FeralHelperDB.hysteriaTarget
                if target and target ~= "" and FeralHelperDB.hysteriaWhisperOnCdExpire ~= false then
                    SendChatMessage(FeralHelperDB.whisperText, "WHISPER", nil, target)
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff33ff99FeralHelper:|r Hysteria CD abgelaufen - Whisper an " .. target)
                end
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
        if btn == "LeftButton" and IsShiftKeyDown() then
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
            local target = FeralHelperDB.hysteriaTarget
            if target and target ~= "" then
                if FeralHelperDB.hysteriaWhisperOnClick ~= false then
                    SendChatMessage(FeralHelperDB.whisperText, "WHISPER", nil, target)
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff33ff99FeralHelper:|r Whisper an |cffffff00" .. target .. "|r gesendet.")
                end
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
        if IsShiftKeyDown() then self:StartMoving() end
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
        if btn == "LeftButton" and IsShiftKeyDown() then
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
    cdTracker = CreateMovableFrame("FeralHelperCDTracker", 560, 60,
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
    local _, _, rebirthIcon     = GetSpellInfo(20484)
    local _, _, schwertgarnIcon  = GetSpellInfo(55776)
    local _, _, bersEnchIcon     = GetSpellInfo(59620)
    local _, _, bearFormIcon     = GetSpellInfo(9634)

    -- clickTarget/clickText: Felder aus DB fuer Whisper beim Klick
    local entries = {
        { key="barkskin",    tex=barkskinIcon,   label="Baumrinde",    type="spell",      spell=SPELL_BARKSKIN },
        { key="berserk",     tex=berserkIcon,    label="Berserk",      type="spell",      spell=SPELL_BERSERK },
        { key="tigersfury",  tex=tigersIcon,     label="Tigerwut",     type="spell",      spell=SPELL_TIGERSFURY },
        { key="survinst",    tex=survInstIcon,   label="UeberInst",    type="spell",      spell=SPELL_SURVINST, selfCast=true },
        { key="innervate",   tex=innervateIcon,  label="Anregen",      type="spell",      spell=SPELL_INNERVATE,
          clickText="Ich wirke Anregen auf dich!", friendlyAliveOnly=true, requireInRange=true },
        { key="rebirth",     tex=rebirthIcon,    label="Wiedergeburt", type="spell",      spell=SPELL_REBIRTH,
          clickText="Ich wirke Wiedergeburt auf dich!", deadOnly=true, noWhisper=true, sayOutOfRange=true },
        { key="trinket1",    tex="Interface\\Icons\\INV_Misc_QuestionMark", label="Trinket 1", type="item-slot", slot=SLOT_TRINKET1 },
        { key="trinket2",    tex="Interface\\Icons\\INV_Misc_QuestionMark", label="Trinket 2", type="item-slot", slot=SLOT_TRINKET2 },
        { key="hands", tex=hyperspeedIcon, label="Hyperspeed", type="item-slot", slot=SLOT_HANDS, noAutoIcon=true,
          procSpell=GetSpellInfo(SPELLID_HYPERSPEED) },
        { key="feet",  tex=nitroIcon,      label="Nitro",       type="item-slot", slot=SLOT_FEET,  noAutoIcon=true,
          procSpell=GetSpellInfo(SPELLID_NITRO) },
        { key="schwertgarn", tex=schwertgarnIcon or "Interface\\Icons\\Trade_Tailoring",
          label="Schwertwallgarn", type="aura", spellId=55776, spell=SPELL_SCHWERTGARN,
          hideWhenInactive=true },
        { key="bersench", tex=bersEnchIcon or "Interface\\Icons\\Spell_Nature_Strength",
          label="Berserk VZ",  type="aura", spell=GetSpellInfo(59620), spellId=59620, hideWhenInactive=true },
        { key="panic", tex=bearFormIcon or "Interface\\Icons\\Ability_Racial_BearForm",
          label="Panik", type="panic",
          macrotext="/cast [noform:1] " .. SPELL_BEARFORM
                 .. "\n/stopmacro [noform:1]"
                 .. "\n/cast " .. SPELL_ENRAGE
                 .. "\n/cast " .. SPELL_SURVINST
                 .. "\n/cast " .. SPELL_BARKSKIN },
    }

    for i, e in ipairs(entries) do
        local icon = CreateCDIcon(cdTracker, e.tex or "Interface\\Icons\\INV_Misc_QuestionMark", e.label)
        icon:SetPoint("LEFT", cdTracker, "LEFT", (i - 1) * 42 + 4, 8)
        icon.entry = e
        cdIcons[e.key] = icon
        if e.hideWhenInactive then icon:Hide() end

        -- Panik-Knopf: 1 Klick aus Bärengestalt = alles sofort
        -- aus Katze/Kaster: 1. Klick -> Bär+Baumrinde, 2. Klick -> Wutanfall+ÜberInst
        if e.type == "panic" then
            local btn = CreateFrame("Button", nil, icon, "SecureActionButtonTemplate")
            btn:SetAllPoints(icon)
            btn:RegisterForClicks("AnyDown", "AnyUp")
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext",
                "/cast [noform:1] " .. SPELL_BEARFORM ..
                "\n/cast " .. SPELL_BARKSKIN ..
                "\n/cast [form:1] " .. SPELL_ENRAGE ..
                "\n/cast [form:1] " .. SPELL_SURVINST)
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
                    if inRange == 0 then
                        if ent.sayOutOfRange and FeralHelperDB.outOfRangeToSay ~= false then
                            SendChatMessage(target .. " nicht in Reichweite", "SAY")
                        end
                        return
                    end
                end
                if not ent.noWhisper and FeralHelperDB.innervateWhisperEnabled ~= false then
                    local text = (ent.key == "innervate" and FeralHelperDB.innervateWhisper)
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

        for _, icon in pairs(cdIcons) do
            local ent = icon.entry

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
                    icon:Show()
                    icon:SetAlpha(1.0)
                    icon.timer:SetText(math.floor(expTime - GetTime()))
                    icon.border:SetVertexColor(0, 1, 0.2)
                    icon.border:SetAlpha(0.6 + 0.4 * math.sin(cdTime * 6))
                    icon.border:Show()
                else
                    if ent.hideWhenInactive then
                        icon:Hide()
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
        end
    end)

    RestoreFramePosition(cdTracker)
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
    m(y .. "───────────────────────────────" .. r)
    m(p .. " Elemente:")
    m("  " .. y .. "Hysteria-Frame" .. r   .. w .. "  Zeigt Buff-Dauer, 180s CD, sendet Whisper bei Kampfstart" .. r)
    m("                   " .. w .. "Shift+Drag zum Verschieben. Klick = Whisper sofort senden." .. r)
    m("  " .. y .. "HoP-Button" .. r       .. w .. "      Erscheint wenn Hand des Schutzes aktiv -> klicken entfernt Buff" .. r)
    m("  " .. y .. "Freizaubern" .. r      .. w .. "     Erscheint wenn Klarsicht-Proc aktiv (Shift+Drag)" .. r)
    m("  " .. y .. "CD-Leiste" .. r        .. w .. "       Baumrinde / Berserk / Tigerwut / Überlebensinstinkte" .. r)
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

local function SendHysteriaWhisper()
    local target = FeralHelperDB.hysteriaTarget
    local text   = FeralHelperDB.whisperText
    if target and target ~= "" and text and text ~= "" then
        SendChatMessage(text, "WHISPER", nil, target)
    end
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

    if event == "ADDON_LOADED" and arg1 == "FeralHelper" then
        FeralHelperDB = FeralHelperDB or {}
        for k, v in pairs(FH.defaults) do
            if FeralHelperDB[k] == nil then
                FeralHelperDB[k] = (type(v) == "table") and {} or v
            end
        end

    elseif event == "PLAYER_LOGIN" then
        BuildTrinketProcNames()
        CreateHysteriaFrame()
        CreateHoPButton()
        CreateVZFrame()
        CreateCDTracker()
        if FeralHelperDB.firstRun then
            FeralHelperDB.firstRun = false
            ShowSetupGuide()
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99FeralHelper|r geladen. "
                .. "|cffffff00/fh|r = Einstellungen, "
                .. "|cffffff00/fh reset|r = Positionen zuruecksetzen.")
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- 3s nach Kampfbeginn Whisper senden
        ScheduleAfter(3, function()
            if not InCombatLockdown() then return end
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
            if FeralHelperDB.hysteriaWhisperOnCombat == false then return end
            SendHysteriaWhisper()
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ff99FeralHelper:|r Whisper an " .. target .. " gesendet.")
        end)

    elseif event == "UNIT_AURA" and arg1 == "player" then
        if hopButton then UpdateHoPButton() end
        if vzFrame then
            local _, _, _, vzExp = GetAuraInfo("player", SPELL_CLEARCAST, "HELPFUL")
            if vzExp then vzFrame:Show() else vzFrame:Hide() end
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
           and destName == UnitName("player")
           and spellName == SPELL_HYSTERIA then
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
    msg = msg and msg:lower() or ""
    if msg == "reset" then
        FeralHelperDB.framePositions = {}
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Positionen zurueckgesetzt. /reload")
    else
        FH:CreateConfigFrame()
    end
end
