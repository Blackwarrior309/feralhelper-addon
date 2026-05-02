-- ============================================================
-- Config.lua - Konfigurations-Fenster
-- ============================================================

FeralHelper = FeralHelper or {}

FeralHelper.defaults = {
    hysteriaTarget           = "",
    whisperText              = "Bitte gib Boesartigkeit!",
    innervateWhisper         = "Ich wirke Anregen auf dich!",
    -- Chat-Toggles
    hysteriaWhisperOnCombat  = true,
    hysteriaWhisperOnCdExpire = true,
    hysteriaWhisperOnClick   = true,
    innervateWhisperEnabled  = true,
    cdToSay                  = false,
    outOfRangeToSay          = true,
    survInstActiveSay        = true,
    survInstCountdownSay     = true,
    hopRemovedSay            = true,
    -- Sonstiges
    framePositions           = {},
    firstRun                 = true,
}

local function MakeCheckbox(parent, labelText, yOffset, dbKey)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", 30, yOffset)
    cb.dbKey = dbKey
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetText(labelText)
    cb:SetScript("OnClick", function(self)
        FeralHelperDB[self.dbKey] = self:GetChecked() and true or false
    end)
    return cb
end

local function MakeSectionLabel(parent, labelText, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 18, yOffset)
    lbl:SetTextColor(0.9, 0.8, 0.4)
    lbl:SetText(labelText)
    return lbl
end

function FeralHelper:CreateConfigFrame()
    if self.configFrame then
        self.configFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "FeralHelperConfigFrame", UIParent)
    f:SetSize(410, 580)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("FeralHelper - Einstellungen")

    -- ---- Boesartigkeit Ziel ----
    local lbl1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl1:SetPoint("TOPLEFT", 25, -48)
    lbl1:SetText("Boesartigkeits-Spieler (genauer Name):")

    local eb1 = CreateFrame("EditBox", "FeralHelperEditBox", f, "InputBoxTemplate")
    eb1:SetSize(190, 24)
    eb1:SetPoint("TOPLEFT", 30, -68)
    eb1:SetAutoFocus(false)
    eb1:SetMaxLetters(24)
    eb1:SetScript("OnEnterPressed", function(self)
        FeralHelperDB.hysteriaTarget = self:GetText()
        self:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Ziel = |cffffff00" .. FeralHelperDB.hysteriaTarget)
    end)
    eb1:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save1 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    save1:SetSize(70, 24)
    save1:SetPoint("LEFT", eb1, "RIGHT", 4, 0)
    save1:SetText("Speichern")
    save1:SetScript("OnClick", function()
        FeralHelperDB.hysteriaTarget = eb1:GetText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Ziel gespeichert: |cffffff00" .. FeralHelperDB.hysteriaTarget)
    end)

    local targetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    targetBtn:SetSize(60, 24)
    targetBtn:SetPoint("LEFT", save1, "RIGHT", 4, 0)
    targetBtn:SetText("Target")
    targetBtn:SetScript("OnClick", function()
        local name = UnitName("target")
        if name and name ~= "Unknown" then
            eb1:SetText(name)
            FeralHelperDB.hysteriaTarget = name
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Ziel gesetzt: |cffffff00" .. name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333FeralHelper:|r Kein Ziel ausgewaehlt!")
        end
    end)

    -- ---- Hysteria Whisper-Text ----
    local lbl2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl2:SetPoint("TOPLEFT", 25, -102)
    lbl2:SetText("Boesartigkeits-Whisper-Text:")

    local eb2 = CreateFrame("EditBox", "FeralHelperEditText", f, "InputBoxTemplate")
    eb2:SetSize(240, 24)
    eb2:SetPoint("TOPLEFT", 30, -122)
    eb2:SetAutoFocus(false)
    eb2:SetMaxLetters(120)
    eb2:SetScript("OnEnterPressed", function(self)
        FeralHelperDB.whisperText = self:GetText()
        self:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Whisper-Text gespeichert.")
    end)
    eb2:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save2 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    save2:SetSize(70, 24)
    save2:SetPoint("LEFT", eb2, "RIGHT", 4, 0)
    save2:SetText("Speichern")
    save2:SetScript("OnClick", function()
        FeralHelperDB.whisperText = eb2:GetText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Whisper-Text gespeichert.")
    end)

    -- ---- Anregen Whisper-Text ----
    local lbl3 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl3:SetPoint("TOPLEFT", 25, -156)
    lbl3:SetText("Anregen-Whisper-Text:")

    local eb3 = CreateFrame("EditBox", "FeralHelperInnervateText", f, "InputBoxTemplate")
    eb3:SetSize(240, 24)
    eb3:SetPoint("TOPLEFT", 30, -176)
    eb3:SetAutoFocus(false)
    eb3:SetMaxLetters(120)
    eb3:SetScript("OnEnterPressed", function(self)
        FeralHelperDB.innervateWhisper = self:GetText()
        self:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Anregen-Text gespeichert.")
    end)
    eb3:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save3 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    save3:SetSize(70, 24)
    save3:SetPoint("LEFT", eb3, "RIGHT", 4, 0)
    save3:SetText("Speichern")
    save3:SetScript("OnClick", function()
        FeralHelperDB.innervateWhisper = eb3:GetText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Anregen-Text gespeichert.")
    end)

    -- Trennlinie
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetSize(370, 1)
    sep:SetPoint("TOPLEFT", 20, -210)
    sep:SetTexture(0.4, 0.4, 0.4)
    sep:SetAlpha(0.8)

    -- ============================================================
    -- Checkboxen
    -- ============================================================

    -- Boesartigkeit (Hysteria)
    MakeSectionLabel(f, "-- Boesartigkeit (Hysteria) --", -220)
    local cbs = {}
    cbs[1]  = MakeCheckbox(f, "Whisper bei Kampfbeginn",           -236, "hysteriaWhisperOnCombat")
    cbs[2]  = MakeCheckbox(f, "Whisper wenn Hysteria-CD ablaeuft", -258, "hysteriaWhisperOnCdExpire")
    cbs[3]  = MakeCheckbox(f, "Whisper bei Klick (Hysteria-Frame)",-280, "hysteriaWhisperOnClick")

    -- Anregen / Wiedergeburt
    MakeSectionLabel(f, "-- Anregen / Wiedergeburt --", -308)
    cbs[4]  = MakeCheckbox(f, "Anregen: Whisper beim Cast",              -324, "innervateWhisperEnabled")
    cbs[5]  = MakeCheckbox(f, "Anregen/Wiedergeburt: CD im /sagen",      -346, "cdToSay")
    cbs[6]  = MakeCheckbox(f, "Wiedergeburt: nicht in Reichweite /sagen",-368, "outOfRangeToSay")

    -- Ueberlebensinstinkte / Hand des Schutzes
    MakeSectionLabel(f, "-- Ueberlebensinstinkte / Hand des Schutzes --", -396)
    cbs[7]  = MakeCheckbox(f, "Ueberlebensinstinkte: aktiv im /sagen",     -412, "survInstActiveSay")
    cbs[8]  = MakeCheckbox(f, "Ueberlebensinstinkte: Countdown im /sagen", -434, "survInstCountdownSay")
    cbs[9]  = MakeCheckbox(f, "Hand des Schutzes: entfernt im /sagen",     -456, "hopRemovedSay")

    -- ---- Test-Whisper ----
    local testBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    testBtn:SetSize(220, 28)
    testBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    testBtn:SetText("Test-Whisper (Boesartigkeit) senden")
    testBtn:SetScript("OnClick", function()
        local target = FeralHelperDB.hysteriaTarget
        if not target or target == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333FeralHelper:|r Kein Ziel gesetzt!")
            return
        end
        SendChatMessage(FeralHelperDB.whisperText, "WHISPER", nil, target)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Test an |cffffff00" .. target .. "|r gesendet.")
    end)

    f.editBox       = eb1
    f.editText      = eb2
    f.editInnervate = eb3
    f.checkboxes    = cbs

    f:SetScript("OnShow", function(self)
        self.editBox:SetText(FeralHelperDB.hysteriaTarget or "")
        self.editText:SetText(FeralHelperDB.whisperText or "")
        self.editInnervate:SetText(FeralHelperDB.innervateWhisper or "Ich wirke Anregen auf dich!")
        for _, cb in ipairs(self.checkboxes) do
            cb:SetChecked(FeralHelperDB[cb.dbKey])
        end
    end)

    self.configFrame = f
end
