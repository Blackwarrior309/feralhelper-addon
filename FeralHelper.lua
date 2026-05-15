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
local SPELL_TRICKS       = GetSpellInfo(57933) or "Tricks of the Trade"
local SPELL_MANGLE_CAT   = GetSpellInfo(33876) or "Mangle"
local SPELL_MANGLE_BEAR  = GetSpellInfo(33878) or SPELL_MANGLE_CAT
local SPELL_TRAUMA       = GetSpellInfo(46857) or "Trauma"
local SPELLID_SAVAGEROAR = 52610
local SPELLID_RIP        = 49800
local ROARRIP_WINDOW     = 8   -- beide müssen innerhalb N Sekunden ablaufen
local ROARRIP_DELTA      = 3   -- gleichzeitig = Differenz < N Sekunden
local RIP_RECAST_THRESH  = 5   -- "jetzt casten" wenn TF aktiv + Rip <= N Sekunden
local PULL_MODE_WINDOW   = 18  -- Pull-Anzeige maximal N Sekunden nach Kampfbeginn
local PULL_PROC_WAIT     = 8   -- so lange auf fruehe Procs warten, danach Rip empfehlen
local PULL_TRAIN_WINDOW  = 20  -- Trainer bewertet die ersten Sekunden nach Pull

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

-- icd = Internal Cooldown in Sekunden (startet beim Proc)
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

    -- Ergaenzt aus TrinketCDsDB (icd=0 = kein synthetischer CD)
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

-- Rip-Snapshot: gespeicherte Buff-Konstellation zum Cast-Zeitpunkt
local ripSnapshot = nil
local cdIcons = {}

-- Icon-Pfade fuer Ingi-Tinker (per SpellID - egal was auf Slot liegt)
local SPELLID_HYPERSPEED = 54758
local SPELLID_NITRO      = 54861

-- Inventar-Slots
local SLOT_HANDS    = 10
local SLOT_FEET     = 8
local SLOT_HEAD     = 1
local SLOT_SHOULDER = 3
local SLOT_CHEST    = 5
local SLOT_LEGS     = 7
local SLOT_TRINKET1 = 13
local SLOT_TRINKET2 = 14
local SLOT_BACK     = 15

local HYSTERIA_CD = 180
local movableFrames = {}

local FERAL_T10_ITEM_IDS = {
    -- Lasherweave Battlegear 251
    [50824] = true, [50825] = true, [50826] = true, [50827] = true, [50828] = true,
    -- Sanctified Lasherweave Battlegear 264
    [51140] = true, [51141] = true, [51142] = true, [51143] = true, [51144] = true,
    -- Sanctified Lasherweave Battlegear 277
    [51295] = true, [51296] = true, [51297] = true, [51298] = true, [51299] = true,
    -- Manche 3.3.5a-Datenbanken/Server listen die 277er unter diesen IDs.
    [51697] = true, [51698] = true, [51699] = true, [51700] = true, [51701] = true,
}

local FERAL_T10_SLOTS = { SLOT_HEAD, SLOT_SHOULDER, SLOT_CHEST, SLOT_HANDS, SLOT_LEGS }

local function CanMove()
    return not InCombatLockdown()
        and FeralHelperDB
        and FeralHelperDB.showPositionFrames == true
        and not FeralHelperDB.framesLocked
end

local function PositionModeActive()
    return FeralHelperDB and FeralHelperDB.showPositionFrames == true
end

local function HasFeralT104p()
    local pieces = 0
    for _, slot in ipairs(FERAL_T10_SLOTS) do
        local itemId = GetInventoryItemID("player", slot)
        if itemId and FERAL_T10_ITEM_IDS[itemId] then
            pieces = pieces + 1
        end
    end
    return pieces >= 4
end

local function GetFeralT10PieceCount()
    local pieces = 0
    for _, slot in ipairs(FERAL_T10_SLOTS) do
        local itemId = GetInventoryItemID("player", slot)
        if itemId and FERAL_T10_ITEM_IDS[itemId] then
            pieces = pieces + 1
        end
    end
    return pieces
end

local function GetFeralT10DebugText()
    local parts = {}
    for _, slot in ipairs(FERAL_T10_SLOTS) do
        local itemId = GetInventoryItemID("player", slot)
        parts[#parts + 1] = tostring(slot) .. "=" .. tostring(itemId or "-")
    end
    return table.concat(parts, " ")
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

local function GetAuraInfoAny(unit, names, filter)
    for _, name in ipairs(names) do
        local icon, count, duration, expirationTime = GetAuraInfo(unit, name, filter)
        if icon then
            return icon, count, duration, expirationTime
        end
    end
    return nil
end

local BLEED_DAMAGE_DEBUFFS = {
    SPELL_MANGLE_CAT,
    SPELL_MANGLE_BEAR,
    SPELL_TRAUMA,
    "Mangle",
    "Trauma",
}

local function TargetHasBleedDamageDebuff()
    if not UnitExists("target") then return false end
    return GetAuraInfoAny("target", BLEED_DAMAGE_DEBUFFS, "HARMFUL") ~= nil
end

local function GetPlayerAttackPowerTotal()
    local base, pos, neg = UnitAttackPower("player")
    return (base or 0) + (pos or 0) + (neg or 0)
end

local function GetInventorySlotCooldownRemaining(slot)
    local start, dur = GetInventoryItemCooldown("player", slot)
    if start and dur and dur > 1.5 then
        return math.max(0, start + dur - GetTime())
    end
    return 0
end

local function GetSyntheticSlotCooldownRemaining(slot)
    local key
    if slot == SLOT_TRINKET1 then
        key = "trinket1"
    elseif slot == SLOT_TRINKET2 then
        key = "trinket2"
    end
    local icon = key and cdIcons and cdIcons[key]
    if icon and icon.synthCDEnd and icon.synthCDEnd > GetTime() then
        return icon.synthCDEnd - GetTime()
    end
    return 0
end

local function GetTrackedSlotProc(slot)
    local itemId = GetInventoryItemID("player", slot)
    if not itemId then
        return { equipped=false, known=false, active=false, ready=false, rem=0, cd=0 }
    end

    local procData = TRINKET_PROCS[itemId]
    local active, rem = false, 0
    if procData then
        for _, buffName in ipairs(procData.names) do
            local _, _, _, exp = GetAuraInfo("player", buffName, "HELPFUL")
            if exp then
                active = true
                rem = math.max(0, exp - GetTime())
                break
            end
        end
        if not active then
            local rawData = _TRINKET_PROC_IDS[itemId]
            if rawData then
                for _, sid in ipairs(rawData.spells) do
                    local _, _, _, exp = GetAuraInfoById("player", sid, "HELPFUL")
                    if exp then
                        active = true
                        rem = math.max(0, exp - GetTime())
                        break
                    end
                end
            end
        end
    end

    local cd = math.max(GetInventorySlotCooldownRemaining(slot), GetSyntheticSlotCooldownRemaining(slot))
    return {
        equipped = true,
        known    = procData ~= nil,
        active   = active,
        ready    = cd <= 0,
        rem      = rem,
        cd       = cd,
    }
end

local function PullStartReady()
    local t1 = GetTrackedSlotProc(SLOT_TRINKET1)
    local t2 = GetTrackedSlotProc(SLOT_TRINKET2)
    return t1.ready and t2.ready
end

local function CaptureRipSnapshot()
    local _, _, _, tfExp   = GetAuraInfoById("player", 5217, "HELPFUL")
    local _, _, _, roarExp = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
    local _, _, _, hystExp = GetAuraInfoById("player", 49016, "HELPFUL")
    local _, _, _, totExp  = GetAuraInfo("player", SPELL_TRICKS, "HELPFUL")
    local trinket1         = GetTrackedSlotProc(SLOT_TRINKET1)
    local trinket2         = GetTrackedSlotProc(SLOT_TRINKET2)

    return {
        tfActive       = tfExp   ~= nil,
        roarActive     = roarExp ~= nil,
        hysteriaActive = hystExp ~= nil,
        totActive      = totExp  ~= nil,
        mangleActive   = TargetHasBleedDamageDebuff(),
        trinket1Active = trinket1.active,
        trinket2Active = trinket2.active,
        ap             = GetPlayerAttackPowerTotal(),
        capturedAt     = GetTime(),
    }
end

-- Verschiebbarer Frame, speichert Position bei Drop
local function CreateMovableFrame(name, w, h, defaultPoint)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetMovable(true)
    f:EnableMouse(PositionModeActive())
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
    movableFrames[name] = f
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
    hysteriaFrame:EnableMouse(true)

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
            if FeralHelperDB then FeralHelperDB.hysteriaEndTime = nil end
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

    -- OnDragStart feuert nur wenn Maus sich wirklich bewegt (nicht bei einfachem Klick).
    -- CreateMovableFrame hat bereits RegisterForDrag gesetzt.
    hysteriaFrame:SetScript("OnDragStart", function(self)
        if CanMove() then
            self:StartMoving()
            self.isDragging = true
        end
    end)
    hysteriaFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        FeralHelperDB.framePositions[self:GetName()] = { point, relPoint, x, y }
    end)
    hysteriaFrame:SetScript("OnMouseUp", function(self, btn)
        if self.isDragging then
            self.isDragging = false
            return
        end
        if btn == "LeftButton" then
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

    -- CD nach Reload wiederherstellen
    if FeralHelperDB and FeralHelperDB.hysteriaEndTime and FeralHelperDB.hysteriaEndTime > GetTime() then
        hysteriaFrame.endTime = FeralHelperDB.hysteriaEndTime
        local startTime = FeralHelperDB.hysteriaEndTime - HYSTERIA_CD
        CooldownFrame_SetTimer(hysteriaFrame.cd, startTime, HYSTERIA_CD, 1)
    end
end

local function StartHysteriaCooldown()
    if not hysteriaFrame then return end
    local now = GetTime()
    hysteriaFrame.endTime = now + HYSTERIA_CD
    if FeralHelperDB then FeralHelperDB.hysteriaEndTime = hysteriaFrame.endTime end
    CooldownFrame_SetTimer(hysteriaFrame.cd, now, HYSTERIA_CD, 1)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cff33ff99FeralHelper:|r Hysteria erhalten - 180s Cooldown laeuft.")
end

-- ============================================================
-- 2) HAND DES SCHUTZES - Button + Entfernen
-- ============================================================

local hopWrapper, hopButton, hopDragHandle
local UpdateHoPButton
local function CreateHoPButton()
    -- Nicht-sicherer Container fuer Position/Optik.
    -- Name "FeralHelperHoPButton" bleibt fuer RestoreFramePosition/Positionsspeicherung.
    hopWrapper = CreateFrame("Frame", "FeralHelperHoPButton", UIParent)
    hopWrapper:SetSize(96, 96)
    hopWrapper:SetMovable(true)
    hopWrapper:EnableMouse(PositionModeActive())
    hopWrapper:RegisterForDrag("LeftButton")
    hopWrapper:SetClampedToScreen(true)
    hopWrapper:ClearAllPoints()
    hopWrapper:SetPoint("CENTER", UIParent, "CENTER", 0, 100)

    -- Sicherer Action-Button als Kind des Wrappers (erbt Sichtbarkeit vom Wrapper).
    -- Ein SecureActionButton darf /cancelaura auch im Kampf ausfuehren,
    -- auch wenn sein Eltern-Frame kein Secure-Frame ist.
    hopButton = CreateFrame("Button", nil, hopWrapper, "SecureActionButtonTemplate")
    hopButton:SetAllPoints(hopWrapper)
    hopButton:EnableMouse(true)

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

    local label = hopWrapper:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOP", hopWrapper, "BOTTOM", 0, -4)
    label:SetTextColor(1, 0.2, 0.2)
    label:SetText("HoP entfernen!")

    hopDragHandle = CreateFrame("Frame", nil, hopWrapper)
    hopDragHandle:SetSize(130, 24)
    hopDragHandle:SetPoint("TOP", hopWrapper, "BOTTOM", 0, -2)
    hopDragHandle:EnableMouse(PositionModeActive())
    hopDragHandle:RegisterForDrag("LeftButton")
    hopDragHandle:SetScript("OnDragStart", function()
        if CanMove() and hopWrapper then
            hopWrapper:StartMoving()
        end
    end)
    hopDragHandle:SetScript("OnDragStop", function()
        if hopWrapper then
            hopWrapper:StopMovingOrSizing()
            local point, _, relPoint, x, y = hopWrapper:GetPoint()
            FeralHelperDB.framePositions[hopWrapper:GetName()] = { point, relPoint, x, y }
        end
    end)

    -- Drag auf Wrapper (nicht-sicher, kein Combat-Lockdown-Problem)
    hopWrapper:SetScript("OnDragStart", function(self)
        if CanMove() then self:StartMoving() end
    end)
    hopWrapper:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        FeralHelperDB.framePositions[self:GetName()] = { point, relPoint, x, y }
    end)

    -- type=macro mit /cancelaura (type=cancelaura buggy in 3.3.5a)
    hopButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hopButton:SetAttribute("type", "macro")
    hopButton:SetAttribute("type1", "macro")
    hopButton:SetAttribute("type2", "macro")
    hopButton:SetAttribute("macrotext", "/cancelaura " .. SPELL_HOP)
    hopButton:SetAttribute("macrotext1", "/cancelaura " .. SPELL_HOP)
    hopButton:SetAttribute("macrotext2", "/cancelaura " .. SPELL_HOP)

    hopButton:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        self.border:SetAlpha(0.5 + 0.5 * math.sin(self.t * 4))
    end)

    RestoreFramePosition(hopWrapper)
    UpdateHoPButton()
end

function UpdateHoPButton()
    if not hopWrapper then return end
    -- Der Button enthaelt einen SecureActionButton. Show/Hide ist im Kampf
    -- blockiert, wenn Hand des Schutzes erst dann aktiv wird. Deshalb bleibt
    -- der Klickbereich geladen und wir schalten nur die Sichtbarkeit per Alpha.
    -- GetAuraInfo (namensbasiert) verwenden, da UnitAura Spell-ID (Pos.11) auf
    -- diesem Server moeglicherweise nicht zuverlaessig zurueckgegeben wird.
    local _, _, _, expTime = GetAuraInfo("player", SPELL_HOP, "HELPFUL")
    if expTime then
        hopWrapper:EnableMouse(true)
        hopWrapper:SetAlpha(1)
        hopButton:EnableMouse(true)
    else
        hopWrapper:EnableMouse(PositionModeActive())
        hopWrapper:SetAlpha(PositionModeActive() and 1 or 0)
        hopButton:EnableMouse(true)
    end
    if hopDragHandle then
        hopDragHandle:EnableMouse(CanMove())
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

        if FH.positionPreviewUntil and FH.positionPreviewUntil > GetTime() then
            self:Show()
            self.timerRoar:SetText("5")
            self.timerRip:SetText("4")
            self.timerRoar:SetTextColor(1, 0.5, 0)
            self.timerRip:SetTextColor(1, 0.5, 0)
            self.borderRoar:SetVertexColor(1, 0.3, 0)
            self.borderRoar:SetAlpha(0.8)
            self.borderRoar:Show()
            self.borderRip:SetVertexColor(1, 0.3, 0)
            self.borderRip:SetAlpha(0.8)
            self.borderRip:Show()
            return
        end

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
    ripSnapshotFrame = CreateMovableFrame("FeralHelperRipSnapshotFrame", 210, 135,
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

    local snapLabel = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapLabel:SetPoint("BOTTOM", ripSnapshotFrame, "BOTTOM", 0, 4)
    snapLabel:SetJustifyH("CENTER")
    ripSnapshotFrame.snapLabel = snapLabel

    local reasonLabel = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reasonLabel:SetPoint("BOTTOM", snapLabel, "TOP", 0, 2)
    reasonLabel:SetJustifyH("CENTER")
    reasonLabel:SetTextColor(0.8, 0.8, 0.8)
    ripSnapshotFrame.reasonLabel = reasonLabel

    local snapStatsLabel = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapStatsLabel:SetPoint("TOPLEFT", iconRip, "BOTTOMLEFT", 0, -6)
    snapStatsLabel:SetJustifyH("LEFT")
    snapStatsLabel:SetTextColor(0.6, 0.6, 0.6)
    ripSnapshotFrame.snapStatsLabel = snapStatsLabel

    local curStatsLabel = ripSnapshotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    curStatsLabel:SetPoint("TOPLEFT", snapStatsLabel, "BOTTOMLEFT", 0, -2)
    curStatsLabel:SetJustifyH("LEFT")
    ripSnapshotFrame.curStatsLabel = curStatsLabel

    local elapsed = 0
    ripSnapshotFrame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        self.t = (self.t or 0) + e

        if FH.ripTestMode then return end  -- Test-Modus: OnUpdate nicht überschreiben

        if FH.positionPreviewUntil and FH.positionPreviewUntil > GetTime() then
            self:Show()
            self.timerRip:SetText("12")
            self.timerRip:SetTextColor(0.2, 1, 0.2)
            self.stateLabel:SetText("Vorschau")
            self.stateLabel:SetTextColor(0.2, 1, 0.2)
            self.iconTF:SetAlpha(1.0)
            self.tfLabel:SetText("TF: 8s")
            self.reasonLabel:SetText("TF Trinket AP+500")
            self.snapStatsLabel:SetText("S TF-SR+H-T-M+ 4500")
            self.curStatsLabel:SetText("C TF+SR+H-T-M+ 5000 |cff00cc00+500|r")
            self.snapLabel:SetText("NEU RIP: 8s")
            self.snapLabel:SetTextColor(1, 0.85, 0)
            self.border:SetVertexColor(0, 1, 0.2)
            self.border:SetAlpha(0.6)
            self.border:Show()
            return
        end

        local now = GetTime()
        local ripExp = GetOwnRipOnTarget()
        if not ripExp then
            ripSnapshot    = nil
            self.prevRipExp = nil
            if FeralHelperDB.showRipSnapshot ~= false
               and self.combatPreviewActive
               and InCombatLockdown() then
                local _, _, _, tfExp   = GetAuraInfoById("player", 5217, "HELPFUL")
                local _, _, _, roarExp = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
                local _, _, _, hystExp = GetAuraInfoById("player", 49016, "HELPFUL")
                local _, _, _, totExp  = GetAuraInfo("player", SPELL_TRICKS, "HELPFUL")
                local curAP            = GetPlayerAttackPowerTotal()
                local tfActive         = tfExp   ~= nil
                local roarActive       = roarExp ~= nil
                local hysteriaActive   = hystExp ~= nil
                local totActive        = totExp  ~= nil
                local curMangle        = TargetHasBleedDamageDebuff()
                local tfRem            = tfActive and math.max(0, tfExp - now) or 0
                local t1               = GetTrackedSlotProc(SLOT_TRINKET1)
                local t2               = GetTrackedSlotProc(SLOT_TRINKET2)
                local pullElapsed      = self.pullStartTime and (now - self.pullStartTime) or 0
                local pullMode         = self.pullModeActive
                                      and self.pullStartTime
                                      and pullElapsed <= PULL_MODE_WINDOW
                local pullProcActive   = t1.active or t2.active
                local ripRecommended   = pullMode
                                      and (pullProcActive
                                           or tfActive
                                           or hysteriaActive
                                           or totActive
                                           or pullElapsed >= PULL_PROC_WAIT)
                local bestUntil = math.huge
                if t1.active and t1.rem and t1.rem > 0 then bestUntil = math.min(bestUntil, t1.rem) end
                if t2.active and t2.rem and t2.rem > 0 then bestUntil = math.min(bestUntil, t2.rem) end
                if tfActive and tfExp then bestUntil = math.min(bestUntil, tfExp - now) end
                if hysteriaActive and hystExp then bestUntil = math.min(bestUntil, hystExp - now) end
                if totActive and totExp then bestUntil = math.min(bestUntil, totExp - now) end
                if roarActive and roarExp then bestUntil = math.min(bestUntil, roarExp - now) end
                if bestUntil == math.huge then bestUntil = nil end
                local function boolStr(b)
                    return b and "|cff00cc00+|r" or "|cffff4444-|r"
                end
                local function slotStr(label, info)
                    if not info.equipped then
                        return label .. "|cff888888leer|r"
                    elseif info.active then
                        return label .. "|cff00cc00P" .. math.floor(info.rem) .. "|r"
                    elseif info.cd and info.cd > 0 then
                        return label .. "|cffff4444CD" .. math.floor(info.cd) .. "|r"
                    elseif info.known then
                        return label .. "|cffffff00ready|r"
                    else
                        return label .. "|cff888888?|r"
                    end
                end

                self:Show()
                if ripRecommended and bestUntil then
                    self.timerRip:SetText(math.max(0, math.floor(bestUntil)))
                else
                    self.timerRip:SetText(ripRecommended and "!" or "-")
                end
                self.timerRip:SetTextColor(ripRecommended and 1 or 0.8, ripRecommended and 0.15 or 0.8, ripRecommended and 0.05 or 0.8)
                self.stateLabel:SetText(ripRecommended and "RIP!" or (pullMode and "PULL" or "Kampf"))
                self.stateLabel:SetTextColor(ripRecommended and 1 or 1, ripRecommended and 0.15 or 0.85, ripRecommended and 0.05 or 0)
                self.iconTF:SetAlpha(tfActive and 1.0 or 0.2)
                self.tfLabel:SetText(tfActive and ("TF: " .. math.floor(tfRem) .. "s") or "")
                self.snapStatsLabel:SetText(
                    slotStr("T1 ", t1) .. " " .. slotStr("T2 ", t2))
                self.curStatsLabel:SetText(
                    "TF" .. boolStr(tfActive) ..
                    " SR" .. boolStr(roarActive) ..
                    " H" .. boolStr(hysteriaActive) ..
                    " T" .. boolStr(totActive) ..
                    " M" .. boolStr(curMangle) ..
                    " " .. curAP)
                self.reasonLabel:SetText("")
                if ripRecommended then
                    if bestUntil then
                        self.snapLabel:SetText("RIP snapshot: " .. math.max(0, math.floor(bestUntil)) .. "s")
                    else
                        self.snapLabel:SetText("RIP snapshot")
                    end
                    self.snapLabel:SetTextColor(1, 0.25, 0.05)
                    self.border:SetVertexColor(1, 0.25, 0.05)
                    self.border:SetAlpha(0.65 + 0.35 * math.sin(self.t * 7))
                elseif pullMode then
                    self.snapLabel:SetText("warte auf fruehe Procs")
                    self.snapLabel:SetTextColor(1, 0.85, 0)
                    self.border:SetVertexColor(1, 0.85, 0)
                    self.border:SetAlpha(0.35 + 0.25 * math.sin(self.t * 3))
                else
                    self.snapLabel:SetText("warte auf Rip")
                    self.snapLabel:SetTextColor(0.8, 0.8, 0.8)
                    self.border:SetVertexColor(1, 0.85, 0)
                    self.border:SetAlpha(0.35 + 0.25 * math.sin(self.t * 3))
                end
                self.border:Show()
                return
            end
            if FeralHelperDB.showRipSnapshot == false then self:Hide(); return end
            -- Idle-Zustand: kein Rip auf Ziel, aktuelle Buffs anzeigen
            self:Show()
            local _, _, _, tfExp2   = GetAuraInfoById("player", 5217, "HELPFUL")
            local _, _, _, roarExp2 = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
            local _, _, _, hystExp2 = GetAuraInfoById("player", 49016, "HELPFUL")
            local _, _, _, totExp2  = GetAuraInfo("player", SPELL_TRICKS, "HELPFUL")
            local tfA   = tfExp2   ~= nil
            local roarA = roarExp2 ~= nil
            local hystA = hystExp2 ~= nil
            local totA  = totExp2  ~= nil
            local mA    = TargetHasBleedDamageDebuff()
            local ap    = GetPlayerAttackPowerTotal()
            local function bs(b) return b and "|cff00cc00+|r" or "|cffff4444-|r" end
            self.timerRip:SetText("-")
            self.timerRip:SetTextColor(0.5, 0.5, 0.5)
            self.stateLabel:SetText("kein Rip")
            self.stateLabel:SetTextColor(0.5, 0.5, 0.5)
            self.iconTF:SetAlpha(tfA and 1.0 or 0.2)
            self.tfLabel:SetText(tfA and ("TF: " .. math.floor(math.max(0, tfExp2 - now)) .. "s") or "")
            self.snapStatsLabel:SetText("")
            self.curStatsLabel:SetText(
                "TF" .. bs(tfA) ..
                " SR" .. bs(roarA) ..
                " H"  .. bs(hystA) ..
                " T"  .. bs(totA) ..
                " M"  .. bs(mA) ..
                " " .. ap)
            self.snapLabel:SetText("")
            self.reasonLabel:SetText("")
            self.border:Hide()
            return
        end
        if FeralHelperDB.showRipSnapshot == false then self:Hide(); return end
        self.pullModeActive = nil

        -- Neuen Rip-Cast erkennen: expiry springt deutlich nach oben
        if not self.prevRipExp or ripExp > self.prevRipExp + 5 then
            if not ripSnapshot or not ripSnapshot.capturedAt or now - ripSnapshot.capturedAt > 1 then
                ripSnapshot = CaptureRipSnapshot()
            end
        end
        self.prevRipExp = ripExp

        self:Show()

        local ripRem = math.max(0, ripExp - now)
        self.timerRip:SetText(math.floor(ripRem))

        -- Aktuelle Buff-Werte (immer berechnen, für Anzeige + Vergleich)
        local _, _, _, tfExp   = GetAuraInfoById("player", 5217, "HELPFUL")
        local _, _, _, roarExp = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
        local _, _, _, hystExp = GetAuraInfoById("player", 49016, "HELPFUL")
        local _, _, _, totExp  = GetAuraInfo("player", SPELL_TRICKS, "HELPFUL")
        local curAP            = GetPlayerAttackPowerTotal()
        local tfActive         = tfExp   ~= nil
        local roarActive       = roarExp ~= nil
        local hysteriaActive   = hystExp ~= nil
        local totActive        = totExp  ~= nil
        local curMangle        = TargetHasBleedDamageDebuff()
        local curTrinket1      = GetTrackedSlotProc(SLOT_TRINKET1)
        local curTrinket2      = GetTrackedSlotProc(SLOT_TRINKET2)
        local tfRem = tfActive and math.max(0, tfExp - now) or 0

        self.iconTF:SetAlpha(tfActive and 1.0 or 0.2)
        self.tfLabel:SetText(tfActive and ("TF: " .. math.floor(tfRem) .. "s") or "")

        -- Stats-Anzeige: Snap vs. Cur
        local function boolStr(b)
            return b and "|cff00cc00+|r" or "|cffff4444-|r"
        end
        if ripSnapshot then
            local apDiff = curAP - ripSnapshot.ap
            local apDiffStr = ""
            if apDiff > 0 then
                apDiffStr = " |cff00cc00+" .. apDiff .. "|r"
            elseif apDiff < 0 then
                apDiffStr = " |cffff4444" .. apDiff .. "|r"
            end
            self.snapStatsLabel:SetText(
                "S TF" .. boolStr(ripSnapshot.tfActive) ..
                "SR" .. boolStr(ripSnapshot.roarActive) ..
                "H" .. boolStr(ripSnapshot.hysteriaActive) ..
                "T" .. boolStr(ripSnapshot.totActive) ..
                "M" .. boolStr(ripSnapshot.mangleActive) ..
                " " .. ripSnapshot.ap)
            self.curStatsLabel:SetText(
                "C TF" .. boolStr(tfActive) ..
                "SR" .. boolStr(roarActive) ..
                "H" .. boolStr(hysteriaActive) ..
                "T" .. boolStr(totActive) ..
                "M" .. boolStr(curMangle) ..
                " " .. curAP .. apDiffStr)
        else
            self.snapStatsLabel:SetText("|cff888888kein Snapshot|r")
            self.curStatsLabel:SetText(
                "TF" .. boolStr(tfActive) ..
                " SR" .. boolStr(roarActive) ..
                " H" .. boolStr(hysteriaActive) ..
                " T" .. boolStr(totActive) ..
                " M" .. boolStr(curMangle) ..
                " " .. curAP)
        end

        -- Snapshot-Vergleich: Wäre Recast jetzt besser?
        local snapBetter   = false
        local advantageSec = nil
        local snapshotWindowSec = nil
        self.snapLabel:SetText("")
        self.reasonLabel:SetText("")

        if ripSnapshot then
            local tfBetter      = tfActive      and not ripSnapshot.tfActive
            local roarBetter    = roarActive    and not ripSnapshot.roarActive
            local hystBetter    = hysteriaActive and not ripSnapshot.hysteriaActive
            local totBetter     = totActive     and not ripSnapshot.totActive
            local mangleBetter  = curMangle     and not ripSnapshot.mangleActive
            local apBetter      = curAP > ripSnapshot.ap + 300
            local trinketBetter = (curTrinket1.active and not ripSnapshot.trinket1Active)
                               or (curTrinket2.active and not ripSnapshot.trinket2Active)
            local reasons = {}
            if tfBetter then reasons[#reasons + 1] = "TF" end
            if roarBetter then reasons[#reasons + 1] = "SR" end
            if hystBetter then reasons[#reasons + 1] = "Hysteria" end
            if totBetter then reasons[#reasons + 1] = "Tricks" end
            if mangleBetter then reasons[#reasons + 1] = "Mangle" end
            if trinketBetter then reasons[#reasons + 1] = "Trinket" end
            if apBetter then reasons[#reasons + 1] = "AP+" .. (curAP - ripSnapshot.ap) end
            if #reasons > 0 then
                self.reasonLabel:SetText(table.concat(reasons, " "))
            end

            if tfBetter or roarBetter or hystBetter or totBetter or mangleBetter or apBetter or trinketBetter then
                snapBetter = true
                local advRem = math.huge
                if tfBetter   and tfExp   then advRem = math.min(advRem, tfExp - now)   end
                if roarBetter and roarExp then advRem = math.min(advRem, roarExp - now) end
                if hystBetter and hystExp then advRem = math.min(advRem, hystExp - now) end
                if totBetter  and totExp  then advRem = math.min(advRem, totExp - now)  end
                if apBetter or trinketBetter then
                    if curTrinket1.active and curTrinket1.rem and curTrinket1.rem > 0 then
                        advRem = math.min(advRem, curTrinket1.rem)
                    end
                    if curTrinket2.active and curTrinket2.rem and curTrinket2.rem > 0 then
                        advRem = math.min(advRem, curTrinket2.rem)
                    end
                end
                if advRem < math.huge then
                    snapshotWindowSec = math.max(0, math.floor(advRem))
                    advantageSec = snapshotWindowSec
                end
            end
        end

        if snapBetter then
            if ripRem <= RIP_RECAST_THRESH then
                if snapshotWindowSec then
                    self.snapLabel:SetText("\226\134\145 JETZT: " .. snapshotWindowSec .. "s")
                else
                    self.snapLabel:SetText("\226\134\145 JETZT CASTEN!")
                end
                self.snapLabel:SetTextColor(1, 0.3, 0)
            elseif advantageSec then
                self.snapLabel:SetText("\226\134\145 NEU RIP: " .. advantageSec .. "s")
                self.snapLabel:SetTextColor(1, 0.85, 0)
            else
                self.snapLabel:SetText("\226\134\145 NEU RIP (AP)")
                self.snapLabel:SetTextColor(1, 0.85, 0)
            end
        end

        if snapBetter and ripRem <= RIP_RECAST_THRESH then
            self.stateLabel:SetText("JETZT!")
            self.stateLabel:SetTextColor(1, 0.1, 0.1)
            if snapshotWindowSec then
                self.timerRip:SetText(snapshotWindowSec)
            end
            self.timerRip:SetTextColor(1, 0.1, 0.1)
            self.border:SetVertexColor(1, 0.3, 0)
            self.border:SetAlpha(0.6 + 0.4 * math.sin(self.t * 6))
            self.border:Show()
        elseif tfActive and ripRem <= RIP_RECAST_THRESH then
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
-- 2e) PULL-ASSIST MODUL + BURST TRAINER
-- ============================================================

local pullFrame
local pullState = {}

local function PullAssistantEnabled()
    return FeralHelperDB and FeralHelperDB.showPullAssistant == true
end

local function PullTrainerEnabled()
    return FeralHelperDB and FeralHelperDB.pullTrainerEnabled == true
end

local function GetPullMaxWait()
    local wait = tonumber(FeralHelperDB and FeralHelperDB.pullMaxWait) or PULL_PROC_WAIT
    if wait < 3 then wait = 3 end
    if wait > 12 then wait = 12 end
    return wait
end

local function SpellReady(spellName)
    local start, dur = GetSpellCooldown(spellName)
    return not (start and dur and dur > 1.5), start and dur and math.max(0, start + dur - GetTime()) or 0
end

local function GetPullFacts()
    local now = GetTime()
    local _, _, _, srExp   = GetAuraInfo("player", SPELL_SAVAGEROAR, "HELPFUL")
    local _, _, _, tfExp   = GetAuraInfoById("player", 5217, "HELPFUL")
    local _, _, _, hystExp = GetAuraInfoById("player", 49016, "HELPFUL")
    local _, _, _, totExp  = GetAuraInfo("player", SPELL_TRICKS, "HELPFUL")
    local tfReady, tfCd    = SpellReady(SPELL_TIGERSFURY)
    local berserkReady     = SpellReady(SPELL_BERSERK)
    local t1               = GetTrackedSlotProc(SLOT_TRINKET1)
    local t2               = GetTrackedSlotProc(SLOT_TRINKET2)
    local facts = {
        now          = now,
        inCat        = IsInCatForm(),
        target       = UnitExists("target"),
        sr           = srExp ~= nil,
        srRem        = srExp and math.max(0, srExp - now) or 0,
        mangle       = TargetHasBleedDamageDebuff(),
        tf           = tfExp ~= nil,
        tfRem        = tfExp and math.max(0, tfExp - now) or 0,
        tfReady      = tfReady,
        tfCd         = tfCd,
        berserkReady = berserkReady,
        hysteria     = hystExp ~= nil,
        tricks       = totExp ~= nil,
        t1           = t1,
        t2           = t2,
        anyProc      = t1.active or t2.active,
        ap           = GetPlayerAttackPowerTotal(),
        ripExp       = GetOwnRipOnTarget(),
    }

    facts.score = 0
    if facts.sr then facts.score = facts.score + 20 end
    if facts.mangle then facts.score = facts.score + 20 end
    if facts.tf then facts.score = facts.score + 20 end
    if facts.t1.active then facts.score = facts.score + 15 end
    if facts.t2.active then facts.score = facts.score + 15 end
    if facts.hysteria then facts.score = facts.score + 10 end
    if facts.tricks then facts.score = facts.score + 10 end
    if facts.score > 100 then facts.score = 100 end
    return facts
end

local function PullReasonText(facts)
    local reasons = {}
    if facts.tf then reasons[#reasons + 1] = "TF" end
    if facts.t1.active or facts.t2.active then reasons[#reasons + 1] = "Trinket" end
    if facts.hysteria then reasons[#reasons + 1] = "Hysteria" end
    if facts.tricks then reasons[#reasons + 1] = "Tricks" end
    if #reasons == 0 then return "kein Burst aktiv" end
    return table.concat(reasons, " ")
end

local function PullNextStep(facts, elapsed)
    if not facts.inCat then return "Katzenform" end
    if not facts.target then return "Ziel waehlen" end
    if not facts.mangle then return "Mangle/Trauma setzen" end
    if not facts.sr then return "Savage Roar aufbauen" end
    if facts.tfReady and not facts.tf then return "Tigerwut nutzen" end
    if not facts.anyProc and elapsed < GetPullMaxWait() then return "kurz auf Procs warten" end
    return "Rip setzen"
end

local function PullShouldRip(facts, elapsed)
    if not facts.inCat or not facts.target or not facts.sr or not facts.mangle then
        return false
    end
    return facts.tf or facts.anyProc or elapsed >= GetPullMaxWait()
end

local function StartPullAttempt()
    if not (PullAssistantEnabled() or PullTrainerEnabled()) then return end
    local facts = GetPullFacts()
    pullState = {
        active       = true,
        startTime    = GetTime(),
        startedInCat = facts.inCat,
        t1Ready      = facts.t1.ready,
        t2Ready      = facts.t2.ready,
        tfReady      = facts.tfReady,
        firstRip     = nil,
        casts        = {},
        reported     = false,
    }
    if pullFrame and PullAssistantEnabled() then pullFrame:Show() end
end

local function FinishPullEvaluation(force)
    if not PullTrainerEnabled() or not pullState.active or pullState.reported then return end
    local rip = pullState.firstRip
    if not rip then
        if force then
            pullState.reported = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper Pull-Trainer:|r |cffff3333kein erster Rip im Pull-Fenster erkannt.|r")
        end
        return
    end
    pullState.reported = true

    local issues = {}
    if not pullState.startedInCat then issues[#issues + 1] = "Pull nicht in Katzenform gestartet" end
    if not rip.facts.mangle then issues[#issues + 1] = "Rip ohne Mangle/Trauma gesetzt" end
    if not rip.facts.sr then issues[#issues + 1] = "Rip ohne Savage Roar gesetzt" end
    if pullState.tfReady and not rip.facts.tf then issues[#issues + 1] = "Tigerwut war bereit, aber beim Rip nicht aktiv" end
    if (pullState.t1Ready or pullState.t2Ready) and not rip.facts.anyProc and rip.elapsed < GetPullMaxWait() then
        issues[#issues + 1] = "Trinket-Procs nicht abgewartet"
    end
    if rip.elapsed > GetPullMaxWait() + 3 then issues[#issues + 1] = "Erster Rip sehr spaet" end

    local color = rip.score >= 80 and "|cff00ff00" or (rip.score >= 60 and "|cffffff00" or "|cffff3333")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper Pull-Trainer:|r Score "
        .. color .. rip.score .. "/100|r nach " .. math.floor(rip.elapsed * 10) / 10 .. "s")
    DEFAULT_CHAT_FRAME:AddMessage("  Snapshot: " .. PullReasonText(rip.facts))
    if #issues == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00Sauberer Pull: keine groben Fehler erkannt.|r")
    else
        for _, issue in ipairs(issues) do
            DEFAULT_CHAT_FRAME:AddMessage("  |cffff3333- " .. issue .. "|r")
        end
    end
end

local function RecordPullCast(spellId, spellName)
    if not pullState.active then return end
    local elapsed = GetTime() - pullState.startTime
    if elapsed > PULL_TRAIN_WINDOW then return end
    pullState.casts[#pullState.casts + 1] = { t = elapsed, id = spellId, name = spellName }
    if spellId == SPELLID_RIP and not pullState.firstRip then
        local facts = GetPullFacts()
        pullState.firstRip = { elapsed = elapsed, facts = facts, score = facts.score }
        FinishPullEvaluation()
    end
end

local function CreatePullAssistantFrame()
    pullFrame = CreateMovableFrame("FeralHelperPullAssistantFrame", 210, 88,
        { "CENTER", UIParent, "CENTER", -220, 0 })

    local bg = pullFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.35)

    local title = pullFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", pullFrame, "TOP", 0, -6)
    pullFrame.title = title

    local nextText = pullFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    pullFrame.nextText = nextText

    local detail = pullFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail:SetPoint("TOP", nextText, "BOTTOM", 0, -4)
    detail:SetWidth(190)
    detail:SetJustifyH("CENTER")
    pullFrame.detail = detail

    local score = pullFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    score:SetPoint("BOTTOM", pullFrame, "BOTTOM", 0, 6)
    pullFrame.score = score

    local elapsed = 0
    pullFrame:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        if not PullAssistantEnabled() then self:Hide(); return end

        local inCombat = InCombatLockdown()
        local facts = GetPullFacts()
        local pullElapsed = pullState.active and pullState.startTime and (GetTime() - pullState.startTime) or 0
        local shouldRip = inCombat and not facts.ripExp and PullShouldRip(facts, pullElapsed)
        local state = "PREP"
        if inCombat and not facts.ripExp then
            state = shouldRip and "RIP NOW" or "WAIT"
        elseif inCombat and facts.ripExp then
            state = "SNAPSHOT OK"
        end

        self:Show()
        self.title:SetText(state)
        if state == "RIP NOW" then
            self.title:SetTextColor(1, 0.15, 0.05)
        elseif state == "WAIT" then
            self.title:SetTextColor(1, 0.85, 0)
        elseif state == "SNAPSHOT OK" then
            self.title:SetTextColor(0.2, 1, 0.2)
        else
            self.title:SetTextColor(0.6, 0.9, 1)
        end
        self.nextText:SetText(PullNextStep(facts, pullElapsed))
        self.detail:SetText(
            "SR" .. (facts.sr and "+" or "-")
            .. " M" .. (facts.mangle and "+" or "-")
            .. " TF" .. (facts.tf and "+" or (facts.tfReady and " ready" or "-"))
            .. " T1" .. (facts.t1.active and "P" or (facts.t1.ready and "R" or "CD"))
            .. " T2" .. (facts.t2.active and "P" or (facts.t2.ready and "R" or "CD")))
        self.score:SetText(facts.score .. "/100")
        self.score:SetTextColor(facts.score >= 80 and 0.2 or 1, facts.score >= 60 and 1 or 0.2, 0.2)
    end)

    pullFrame:Hide()
    RestoreFramePosition(pullFrame)
end

-- ============================================================
-- 3) COOLDOWN-TRACKER
-- ============================================================

local cdTracker
local panicButton
local panicMacroNeedsUpdate

local function BuildPanicMacro()
    local macro = "/cast [noform:1] " .. SPELL_BEARFORM
        .. "\n/cancelaura " .. SPELL_HYSTERIA
        .. "\n/cast " .. SPELL_BARKSKIN
    if HasFeralT104p() then
        macro = macro .. "\n/cast [form:1] " .. SPELL_ENRAGE
    end
    return macro .. "\n/cast [form:1] " .. SPELL_SURVINST
end

local function UpdatePanicButtonMacro()
    if not panicButton then return end
    if InCombatLockdown() then
        panicMacroNeedsUpdate = true
        return
    end
    panicMacroNeedsUpdate = nil
    panicButton:SetAttribute("macrotext", BuildPanicMacro())
    panicButton.hasT10 = HasFeralT104p()
    if panicButton.ownerIcon then
        panicButton.ownerIcon.t10Label:SetText(panicButton.hasT10 and "T10" or "")
    end
end

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

    local cloakProcs = {
        { spellId=55637, icd=60, label="Lightweave" },
        { spellId=55776, icd=55, label="Schwertwallgarn" },
    }
    for _, p in ipairs(cloakProcs) do
        local _, _, t = GetSpellInfo(p.spellId)
        p.tex = t
    end

    local weaponProcs = {
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
          procSpell=GetSpellInfo(SPELLID_HYPERSPEED), clickUseSlot=SLOT_HANDS, ingiEnchantId=3604 },
        { key="feet",  tex=nitroIcon,      label="Nitro",       type="item-slot", slot=SLOT_FEET,  noAutoIcon=true,
          procSpell=GetSpellInfo(SPELLID_NITRO), clickUseSlot=SLOT_FEET, ingiEnchantId=3606 },
        { key="cloakvz", tex="Interface\\Icons\\INV_Misc_Parachute",
          label="Mantel VZ", type="weapon-enchant", procs=cloakProcs, hideWhenInactive=true,
          ingiEnchantId=3860, ingiSlot=SLOT_BACK, clickUseSlot=SLOT_BACK },
        { key="weaponvz", tex="Interface\\Icons\\INV_Weapon_ShortBlade_30",
          label="Waffe VZ", type="weapon-enchant", procs=weaponProcs, hideWhenInactive=true },
        { key="ring1", tex="Interface\\Icons\\INV_Misc_QuestionMark",
          label="Ring 1", type="item-slot", slot=11, procOnly=true },
        { key="ring2", tex="Interface\\Icons\\INV_Misc_QuestionMark",
          label="Ring 2", type="item-slot", slot=12, procOnly=true },
        { key="panic", tex=bearFormIcon or "Interface\\Icons\\Ability_Racial_BearForm",
          label="Panik", type="panic",
          macrotext=BuildPanicMacro() },
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
            btn.ownerIcon = icon
            icon.t10Label = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            icon.t10Label:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
            icon.t10Label:SetTextColor(0.2, 1, 0.2)
            icon.t10Label:SetText("")
            local function ShowPanicTooltip()
                GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cff33ff99Panik-Knopf|r")
                GameTooltip:AddLine("Baer, Hysteria entfernen, Baumrinde, Ueberlebensinstinkte", 1, 1, 1)
                if HasFeralT104p() then
                    GameTooltip:AddLine("Feral T10 4er erkannt: Wutanfall aktiv", 0.2, 1, 0.2)
                else
                    GameTooltip:AddLine("Feral T10 4er fehlt: Wutanfall wird ausgelassen", 1, 0.35, 0.2)
                end
                GameTooltip:AddLine("T10-Teile: " .. GetFeralT10PieceCount() .. "/4", 1, 0.85, 0)
                GameTooltip:Show()
            end
            local function HidePanicTooltip()
                GameTooltip:Hide()
            end
            icon:SetScript("OnEnter", ShowPanicTooltip)
            icon:SetScript("OnLeave", HidePanicTooltip)
            btn:SetScript("OnEnter", ShowPanicTooltip)
            btn:SetScript("OnLeave", HidePanicTooltip)
            panicButton = btn
            UpdatePanicButtonMacro()
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
                -- Ingi-Enchant Pflicht: Icon nur zeigen wenn VZ auf Item
                if ent.ingiEnchantId then
                    local link = GetInventoryItemLink("player", ent.slot)
                    local eId  = link and tonumber(link:match("item:%d+:(%d+)"))
                    if eId ~= ent.ingiEnchantId then
                        icon:Hide()
                        CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                        break
                    end
                end
                -- Icon dynamisch vom Item holen (nicht bei Ingi-Tinkern)
                if not ent.noAutoIcon then
                    local itemTex = GetInventoryItemTexture("player", ent.slot)
                    if itemTex then icon.icon:SetTexture(itemTex) end
                end

                -- Proc-Buff prüfen
                local procActive = false
                local procExp = nil
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
                        if exp then procActive = true; procExp = exp; break end
                    end
                    -- ID-basiert als Fallback (falls GetSpellInfo Namen nicht aufgeloest hat)
                    if not procActive then
                        local rawData = _TRINKET_PROC_IDS[itemId]
                        if rawData then
                            for _, sid in ipairs(rawData.spells) do
                                local _, _, _, exp = GetAuraInfoById("player", sid, "HELPFUL")
                                if exp then procActive = true; procExp = exp; break end
                            end
                        end
                    end
                end
                if ent.procSpell and not procActive then
                    local _, _, _, exp = GetAuraInfo("player", ent.procSpell, "HELPFUL")
                    if exp then procActive = true; procExp = exp end
                end

                -- Proc-Uebergang inaktiv -> aktiv: synthetischen ICD starten
                -- Passive Trinket-ICDs laufen ab Proc-Start, nicht erst ab Buff-Ende.
                if procActive then
                    if not icon.procWasActive then
                        local s, d = GetInventoryItemCooldown("player", ent.slot)
                        if not (s and d and d > 1.5) then
                            local icd = (procData and procData.icd) or 45
                            if icd and icd > 0 then
                                icon.synthCDEnd = GetTime() + icd
                            else
                                icon.synthCDEnd = nil
                            end
                        end
                    end
                    icon.procWasActive = true
                else
                    icon.procWasActive = false
                end

                local start, dur, enabled = GetInventoryItemCooldown("player", ent.slot)
                local realCD = start and dur and dur > 1.5
                local synthCD = icon.synthCDEnd and icon.synthCDEnd > GetTime()

                if procActive then
                    icon:SetAlpha(1.0)
                    icon.border:SetVertexColor(0, 1, 0.2)
                    icon.border:SetAlpha(0.6 + 0.4 * math.sin(cdTime * 6))
                    icon.border:Show()
                    CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                    if procExp then
                        icon.timer:SetText(math.floor(math.max(0, procExp - GetTime())))
                    else
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
                -- Ingi-Enchant Modus: dauerhaft sichtbar + CD-Anzeige
                local ingiActive = false
                if ent.ingiEnchantId and ent.ingiSlot then
                    local link = GetInventoryItemLink("player", ent.ingiSlot)
                    local eId  = link and tonumber(link:match("item:%d+:(%d+)"))
                    ingiActive = (eId == ent.ingiEnchantId)
                end
                if ingiActive then
                    local tex = GetInventoryItemTexture("player", ent.ingiSlot)
                    if tex then icon.icon:SetTexture(tex) end
                    icon.weProcActive = false
                    icon.synthCDEnd   = nil
                    icon:Show()
                    icon.border:Hide()
                    local start, dur, enabled = GetInventoryItemCooldown("player", ent.ingiSlot)
                    if start and dur and dur > 1.5 then
                        icon:SetAlpha(0.4)
                        icon.timer:SetText(math.floor(start + dur - GetTime()))
                        CooldownFrame_SetTimer(icon.cd, start, dur, enabled)
                    else
                        icon:SetAlpha(1.0)
                        icon.timer:SetText("")
                        CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
                    end
                else
                    -- Kein Ingi-Enchant: Proc-Erkennung (Schneider-VZ etc.)
                    CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
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
    if self.interfaceOptionsFrame and self.interfaceOptionsFrame.lockBtn then
        self.interfaceOptionsFrame.lockBtn:SetText(locked and "Frames entsperren" or "Frames sperren")
    end
    if FeralHelperDB then
        FeralHelperDB.showPositionFrames = not locked
    end
    if self.SetPositionMode then
        self:SetPositionMode(FeralHelperDB and FeralHelperDB.showPositionFrames == true)
    end
end

function FH:SetPositionMode(enabled)
    if not FeralHelperDB then return end
    FeralHelperDB.showPositionFrames = enabled and true or false
    if FeralHelperDB.showPositionFrames then
        FeralHelperDB.framesLocked = false
    end
    if self.configFrame and self.configFrame.lockBtn then
        self.configFrame.lockBtn:SetText(FeralHelperDB.framesLocked and "Frames entsperren" or "Frames sperren")
    end
    if self.interfaceOptionsFrame and self.interfaceOptionsFrame.lockBtn then
        self.interfaceOptionsFrame.lockBtn:SetText(FeralHelperDB.framesLocked and "Frames entsperren" or "Frames sperren")
    end

    local mouseEnabled = FeralHelperDB.showPositionFrames == true and FeralHelperDB.framesLocked ~= true
    for _, frame in pairs(movableFrames) do
        frame:EnableMouse(mouseEnabled)
    end
    -- Hysteria frame braucht immer Mouse fuer Klick-Whisper
    if hysteriaFrame then
        hysteriaFrame:EnableMouse(true)
    end

    if hopWrapper then
        local _, _, _, hopExp = GetAuraInfo("player", SPELL_HOP, "HELPFUL")
        hopWrapper:EnableMouse(hopExp ~= nil or mouseEnabled)
        if FeralHelperDB.showPositionFrames then
            hopWrapper:SetAlpha(1)
        end
    end
    if hopDragHandle then
        hopDragHandle:EnableMouse(mouseEnabled)
    end
    if hopButton then
        hopButton:EnableMouse(true)
    end

    if FeralHelperDB.showPositionFrames then
        if hysteriaFrame then hysteriaFrame:Show() end
        if vzFrame then
            vzFrame:Show()
            if vzFrame.timer then vzFrame.timer:SetText("8") end
        end
        if cdTracker then cdTracker:Show() end
        if roarRipFrame then roarRipFrame:Show() end
        if ripSnapshotFrame then ripSnapshotFrame:Show() end
        if pullFrame then pullFrame:Show() end
    else
        if UpdateHoPButton then UpdateHoPButton() end
        self:ApplyVisibility()
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
    if ripSnapshotFrame then
        if FeralHelperDB.showRipSnapshot == false then
            ripSnapshotFrame:Hide()
        else
            ripSnapshotFrame:Show()
        end
    end
    if pullFrame then
        if FeralHelperDB.showPullAssistant == true then
            pullFrame:Show()
        else
            pullFrame:Hide()
        end
    end
end

function FH:ShowPositionFrames()
    self:SetPositionMode(true)
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
    m("                   " .. w .. "Wutanfall nur mit Feral T10 4er, danach Ueberlebensinstinkte" .. r)
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
main:RegisterEvent("PLAYER_REGEN_ENABLED")
main:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
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
        CreatePullAssistantFrame()
        CreateMinimapButton()
        UpdatePanicButtonMacro()
        FH:ApplyVisibility()
        FH:SetPositionMode(FeralHelperDB.showPositionFrames == true)
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
        StartPullAttempt()
        if ripSnapshotFrame and FeralHelperDB.showRipSnapshot ~= false then
            ripSnapshotFrame.combatPreviewActive = true
            ripSnapshotFrame.pullStartTime = GetTime()
            ripSnapshotFrame.pullModeActive = PullStartReady()
            ripSnapshotFrame:Show()
        end

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

    elseif event == "PLAYER_REGEN_ENABLED" then
        if ripSnapshotFrame then
            ripSnapshotFrame.combatPreviewActive = nil
            ripSnapshotFrame.pullStartTime = nil
            ripSnapshotFrame.pullModeActive = nil
        end
        if panicMacroNeedsUpdate then
            UpdatePanicButtonMacro()
        end
        if pullState.active and not pullState.reported and PullTrainerEnabled() then
            FinishPullEvaluation(true)
        end
        pullState.active = nil

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdatePanicButtonMacro()

    elseif event == "UNIT_AURA" and arg1 == "player" then
        if hopWrapper then UpdateHoPButton() end
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
        -- 3.3.5a: arg1 ist timestamp, danach kommt subevent, hideCaster, ...
        local subevent, _, srcGUID, srcName, _,
              _, destGUID, destName, _, _, spellId, spellName = ...

        if subevent == "SPELL_AURA_APPLIED"
           and destGUID == UnitGUID("player")
           and (spellId == 49016 or spellName == SPELL_HYSTERIA) then
            StartHysteriaCooldown()
        end

        if subevent == "SPELL_CAST_SUCCESS"
           and srcGUID == UnitGUID("player")
           and spellId == SPELLID_RIP then
            ripSnapshot = CaptureRipSnapshot()
        end

        if subevent == "SPELL_CAST_SUCCESS"
           and srcGUID == UnitGUID("player") then
            RecordPullCast(spellId, spellName)
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
    elseif msg == "defaults" or msg == "standard" then
        if FH.ApplyDefaultSettings then
            FH:ApplyDefaultSettings(true)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Standard-Einstellungen geladen. Positionen bleiben erhalten.")
        end
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
        FH.ripTestMode = not FH.ripTestMode
        if ripSnapshotFrame then
            if FH.ripTestMode then
                ripSnapshotFrame:ClearAllPoints()
                ripSnapshotFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                ripSnapshotFrame:Show()
                ripSnapshotFrame.timerRip:SetText("12")
                ripSnapshotFrame.timerRip:SetTextColor(0.2, 1, 0.2)
                ripSnapshotFrame.stateLabel:SetText("TF-aktiv")
                ripSnapshotFrame.stateLabel:SetTextColor(0.2, 1, 0.2)
                ripSnapshotFrame.iconTF:SetAlpha(1.0)
                ripSnapshotFrame.tfLabel:SetText("TF: 8s")
                ripSnapshotFrame.reasonLabel:SetText("TF Trinket AP+680")
                ripSnapshotFrame.snapStatsLabel:SetText(
                    "S TF|cff00cc00+|rSR|cffff4444-|rH|cffff4444-|rT|cffff4444-|rM|cff00cc00+|r 4520")
                ripSnapshotFrame.curStatsLabel:SetText(
                    "C TF|cff00cc00+|rSR|cff00cc00+|rH|cffff4444-|rT|cffff4444-|rM|cff00cc00+|r 5200 |cff00cc00+680|r")
                ripSnapshotFrame.snapLabel:SetText("\226\134\145 NEU RIP: 8s")
                ripSnapshotFrame.snapLabel:SetTextColor(1, 0.85, 0)
                ripSnapshotFrame.border:SetVertexColor(0, 1, 0.2)
                ripSnapshotFrame.border:SetAlpha(0.6)
                ripSnapshotFrame.border:Show()
            else
                ripSnapshotFrame:Hide()
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Rip-Snapshot Test " .. (FH.ripTestMode and "|cff00ff00AN|r" or "|cffff4444AUS|r")
            .. " — sichtbar? Position OK. Sonst |cffffff00/fh reset|r")
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
        m:AddMessage("  Feral T10: " .. y .. GetFeralT10PieceCount() .. "/4" .. r
            .. "  Wutanfall im Panik-Macro: " .. y .. tostring(HasFeralT104p()) .. r)
        m:AddMessage("  T10 Slots: " .. y .. GetFeralT10DebugText() .. r)
        m:AddMessage("  showRoarRipWarning: " .. y .. tostring(FeralHelperDB.showRoarRipWarning) .. r)
        m:AddMessage("  showRipSnapshot: " .. y .. tostring(FeralHelperDB.showRipSnapshot) .. r)
    elseif msg == "pull" then
        local m = DEFAULT_CHAT_FRAME
        local y = "|cffffff00"; local r = "|r"; local g = "|cff33ff99"
        local facts = GetPullFacts()
        local elapsed = pullState.active and pullState.startTime and (GetTime() - pullState.startTime) or 0
        m:AddMessage(g .. "FeralHelper Pull:" .. r)
        m:AddMessage("  Modul: " .. y .. tostring(PullAssistantEnabled()) .. r
            .. "  Trainer: " .. y .. tostring(PullTrainerEnabled()) .. r
            .. "  MaxWait: " .. y .. GetPullMaxWait() .. "s" .. r)
        m:AddMessage("  Score: " .. y .. facts.score .. "/100" .. r
            .. "  Next: " .. y .. PullNextStep(facts, elapsed) .. r)
        m:AddMessage("  SR: " .. y .. tostring(facts.sr) .. r
            .. "  Mangle: " .. y .. tostring(facts.mangle) .. r
            .. "  TF: " .. y .. tostring(facts.tf) .. r
            .. "  TF ready: " .. y .. tostring(facts.tfReady) .. r)
        m:AddMessage("  T1: " .. y .. (facts.t1.active and "PROC" or (facts.t1.ready and "ready" or ("CD " .. math.floor(facts.t1.cd or 0)))) .. r
            .. "  T2: " .. y .. (facts.t2.active and "PROC" or (facts.t2.ready and "ready" or ("CD " .. math.floor(facts.t2.cd or 0)))) .. r)
        if pullState.firstRip then
            m:AddMessage("  Letzter erster Rip: " .. y .. pullState.firstRip.score .. "/100 nach "
                .. math.floor(pullState.firstRip.elapsed * 10) / 10 .. "s" .. r)
        end
    else
        FH:CreateConfigFrame()
    end
end
