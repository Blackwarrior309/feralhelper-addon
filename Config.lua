-- ============================================================
-- Config.lua - Konfigurations-Fenster
-- ============================================================

FeralHelper = FeralHelper or {}

FeralHelper.defaults = {
    hysteriaTarget           = "",
    whisperText              = "Bitte gib Boesartigkeit!",
    innervateWhisper         = "Ich wirke Anregen auf dich!",
    -- Chat-Toggles
    hysteriaWhisperOnCombat  = false,
    hysteriaWhisperOnCdExpire = false,
    hysteriaWhisperOnClick   = true,
    innervateWhisperEnabled  = true,
    cdToSay                  = false,
    outOfRangeToSay          = false,
    survInstActiveSay        = false,
    survInstCountdownSay     = false,
    hopRemovedSay            = false,
    -- Sonstiges
    framePositions           = {},
    firstRun                 = true,
    -- Frames
    framesLocked             = false,
    showPositionFrames       = false,
    showHysteriaFrame        = true,
    showVZFrame              = true,
    showCDTracker            = true,
    showRoarRipWarning       = false,
    showRipSnapshot          = false,
    showPullAssistant        = false,
    pullTrainerEnabled       = false,
    showRotationHelper       = true,
    pullMaxWait              = 8,
    minimapAngle             = 220,
}

local function MakeCheckbox(parent, labelText, yOffset, dbKey, xOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", xOffset or 30, yOffset)
    cb.dbKey = dbKey
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetText(labelText)
    cb:SetScript("OnClick", function(self)
        FeralHelperDB[self.dbKey] = self:GetChecked() and true or false
    end)
    return cb
end

local function SaveCheckboxStates(frame)
    if not FeralHelperDB or not frame or not frame.checkboxes then return end
    for _, cb in ipairs(frame.checkboxes) do
        FeralHelperDB[cb.dbKey] = cb:GetChecked() and true or false
    end
end

local function LoadConfigFrameValues(frame)
    if not FeralHelperDB or not frame then return end
    if frame.editBox then
        frame.editBox:SetText(FeralHelperDB.hysteriaTarget or "")
    end
    if frame.editText then
        frame.editText:SetText(FeralHelperDB.whisperText or "")
    end
    if frame.editInnervate then
        frame.editInnervate:SetText(FeralHelperDB.innervateWhisper or "Ich wirke Anregen auf dich!")
    end
    if frame.checkboxes then
        for _, cb in ipairs(frame.checkboxes) do
            cb:SetChecked(FeralHelperDB[cb.dbKey])
        end
    end
    if frame.lockBtn then
        frame.lockBtn:SetText(FeralHelperDB.framesLocked and "Frames entsperren" or "Frames sperren")
    end
end

function FeralHelper:ApplyDefaultSettings(keepPositions)
    FeralHelperDB = FeralHelperDB or {}
    local savedPositions = FeralHelperDB.framePositions
    for k, v in pairs(self.defaults or {}) do
        if type(v) == "table" then
            FeralHelperDB[k] = {}
        else
            FeralHelperDB[k] = v
        end
    end
    if keepPositions and savedPositions then
        FeralHelperDB.framePositions = savedPositions
    end
    if self.configFrame then
        LoadConfigFrameValues(self.configFrame)
    end
    if self.interfaceOptionsFrame then
        LoadConfigFrameValues(self.interfaceOptionsFrame)
    end
    if self.ApplyVisibility then
        self:ApplyVisibility()
    end
    if self.SetLocked then
        self:SetLocked(FeralHelperDB.framesLocked)
    end
end

local function MakeSectionLabel(parent, labelText, yOffset, xOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", xOffset or 18, yOffset)
    lbl:SetTextColor(0.9, 0.8, 0.4)
    lbl:SetText(labelText)
    return lbl
end

local function MakeHelpText(parent, text, yOffset, xOffset, width)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lbl:SetPoint("TOPLEFT", xOffset or 30, yOffset)
    lbl:SetWidth(width or 350)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(text)
    return lbl
end

function FeralHelper:CreateConfigFrame(noShow)
    if self.configFrame then
        if not noShow then
            self.configFrame:Show()
        end
        return
    end

    local f = CreateFrame("Frame", "FeralHelperConfigFrame", UIParent)
    f.name = "FeralHelper"
    f:SetSize(620, 650)
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
    eb2:SetSize(400, 24)
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
    eb3:SetSize(400, 24)
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
    sep:SetSize(580, 1)
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
    MakeSectionLabel(f, "-- Anregen / Wiedergeburt --", -220, 318)
    cbs[4]  = MakeCheckbox(f, "Anregen: Whisper beim Cast",              -236, "innervateWhisperEnabled", 330)
    cbs[5]  = MakeCheckbox(f, "Anregen/Wiedergeburt: CD im /sagen",      -258, "cdToSay", 330)
    cbs[6]  = MakeCheckbox(f, "Wiedergeburt: nicht in Reichweite /sagen",-280, "outOfRangeToSay", 330)

    -- Ueberlebensinstinkte / Hand des Schutzes
    MakeSectionLabel(f, "-- Ueberlebensinstinkte / Hand des Schutzes --", -318)
    cbs[7]  = MakeCheckbox(f, "Ueberlebensinstinkte: aktiv im /sagen",     -336, "survInstActiveSay")
    cbs[8]  = MakeCheckbox(f, "Ueberlebensinstinkte: Countdown im /sagen", -358, "survInstCountdownSay")
    cbs[9]  = MakeCheckbox(f, "Hand des Schutzes: entfernt im /sagen",     -380, "hopRemovedSay")

    -- Sichtbarkeit
    MakeSectionLabel(f, "-- Frames anzeigen --", -318, 318)
    local visCbs = {
        MakeCheckbox(f, "Hysteria-Frame",  -336, "showHysteriaFrame", 330),
        MakeCheckbox(f, "Clearcast-Frame", -358, "showVZFrame", 330),
        MakeCheckbox(f, "CD-Leiste",       -380, "showCDTracker", 330),
    }
    for _, cb in ipairs(visCbs) do
        cb:SetScript("OnClick", function(self)
            FeralHelperDB[self.dbKey] = self:GetChecked() and true or false
            if FeralHelper.ApplyVisibility then FeralHelper:ApplyVisibility() end
        end)
        cbs[#cbs + 1] = cb
    end

    -- Katzenrotation
    MakeSectionLabel(f, "-- Katzenrotation --", -418)
    MakeHelpText(f, "Experimentell: Pull-Assist ist ein separates Modul fuer Start-Rota, Snapshot-Fenster und Training.", -436, 30, 560)
    local catCbs = {
        MakeCheckbox(f, "Roar+Rip Warnung",   -470, "showRoarRipWarning"),
        MakeCheckbox(f, "Rip-Snapshot/Pull-Modus", -492, "showRipSnapshot"),
        MakeCheckbox(f, "Pull-Assist Modul", -470, "showPullAssistant", 330),
        MakeCheckbox(f, "Pull-Rota Burst Trainer", -492, "pullTrainerEnabled", 330),
        MakeCheckbox(f, "Live Rotation Helper", -514, "showRotationHelper"),
    }
    for _, cb in ipairs(catCbs) do
        cb:SetScript("OnClick", function(self)
            FeralHelperDB[self.dbKey] = self:GetChecked() and true or false
            if FeralHelper.ApplyVisibility then FeralHelper:ApplyVisibility() end
        end)
        cbs[#cbs + 1] = cb
    end

    -- Frames sperren
    MakeSectionLabel(f, "-- Frames --", -514)
    local lockBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    lockBtn:SetSize(170, 26)
    lockBtn:SetPoint("TOPLEFT", 30, -530)
    lockBtn:SetScript("OnClick", function()
        FeralHelperDB.framesLocked = not FeralHelperDB.framesLocked
        lockBtn:SetText(FeralHelperDB.framesLocked and "Frames entsperren" or "Frames sperren")
        if FeralHelper.SetLocked then FeralHelper:SetLocked(FeralHelperDB.framesLocked) end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Frames "
            .. (FeralHelperDB.framesLocked and "|cffff3333gesperrt|r" or "|cff33ff99entsperrt|r"))
    end)
    f.lockBtn = lockBtn

    local showFramesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    showFramesBtn:SetSize(170, 26)
    showFramesBtn:SetPoint("TOPLEFT", 210, -530)
    showFramesBtn:SetText("Frames anzeigen")
    showFramesBtn:SetScript("OnClick", function()
        if FeralHelperDB then
            FeralHelperDB.showHysteriaFrame = true
            FeralHelperDB.showVZFrame = true
            FeralHelperDB.showCDTracker = true
            FeralHelperDB.showRoarRipWarning = true
            FeralHelperDB.showRipSnapshot = true
            FeralHelperDB.showPullAssistant = true
            FeralHelperDB.showRotationHelper = true
        end
        if FeralHelper.ShowPositionFrames then
            FeralHelper:ShowPositionFrames()
        elseif FeralHelper.ApplyVisibility then
            FeralHelper:ApplyVisibility()
        end
        LoadConfigFrameValues(f)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Alle Positions-Frames eingeblendet.")
    end)
    f.showFramesBtn = showFramesBtn

    local defaultsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    defaultsBtn:SetSize(150, 26)
    defaultsBtn:SetPoint("TOPLEFT", 390, -530)
    defaultsBtn:SetText("Standard laden")
    defaultsBtn:SetScript("OnClick", function()
        FeralHelper:ApplyDefaultSettings(true)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Standard-Einstellungen geladen. Positionen bleiben erhalten.")
    end)
    f.defaultsBtn = defaultsBtn

    local moveModeCb = MakeCheckbox(f, "Alle Fenster anzeigen und verschiebbar machen", -568, "showPositionFrames")
    moveModeCb:SetScript("OnClick", function(self)
        FeralHelperDB.showPositionFrames = self:GetChecked() and true or false
        if FeralHelper.SetPositionMode then
            FeralHelper:SetPositionMode(FeralHelperDB.showPositionFrames)
        elseif FeralHelper.ApplyVisibility then
            FeralHelper:ApplyVisibility()
        end
    end)
    cbs[#cbs + 1] = moveModeCb

    -- ---- Test-Whisper ----
    local testBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    testBtn:SetSize(230, 28)
    testBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    testBtn:SetText("Test-Whisper (Boesartigkeit) senden")
    testBtn:SetScript("OnClick", function()
        local target = FeralHelperDB.hysteriaTarget
        if not target or target == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333FeralHelper:|r Kein Ziel gesetzt!")
            return
        end
        SendChatMessage(FeralHelper:GetWhisperText("whisperText"), "WHISPER", nil, target)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Test an |cffffff00" .. target .. "|r gesendet.")
    end)

    f.editBox       = eb1
    f.editText      = eb2
    f.editInnervate = eb3
    f.checkboxes    = cbs

    f:SetScript("OnShow", LoadConfigFrameValues)
    f:SetScript("OnHide", SaveCheckboxStates)
    LoadConfigFrameValues(f)

    self.configFrame = f
    if noShow then
        f:Hide()
    else
        f:Show()
    end
end

function FeralHelper:CreateInterfaceOptionsPanel()
    if self.interfaceOptionsFrame then return self.interfaceOptionsFrame end

    local panel = CreateFrame("Frame", "FeralHelperInterfaceOptionsPanel", UIParent)
    panel.name = "FeralHelper"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FeralHelper")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Addon-Einstellungen")

    local scroll = CreateFrame("ScrollFrame", "FeralHelperInterfaceOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -50)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 850)
    scroll:SetScrollChild(content)

    local function SaveTexts()
        if not FeralHelperDB then return end
        FeralHelperDB.hysteriaTarget = panel.editBox:GetText()
        FeralHelperDB.whisperText = panel.editText:GetText()
        FeralHelperDB.innervateWhisper = panel.editInnervate:GetText()
    end

    local function RefreshFrames()
        LoadConfigFrameValues(panel)
        if FeralHelper.configFrame then
            LoadConfigFrameValues(FeralHelper.configFrame)
        end
    end

    local lbl1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl1:SetPoint("TOPLEFT", 18, -10)
    lbl1:SetText("Boesartigkeits-Spieler (genauer Name):")

    local eb1 = CreateFrame("EditBox", "FeralHelperOptionsTargetEditBox", content, "InputBoxTemplate")
    eb1:SetSize(190, 24)
    eb1:SetPoint("TOPLEFT", 22, -30)
    eb1:SetAutoFocus(false)
    eb1:SetMaxLetters(24)
    eb1:SetScript("OnEnterPressed", function(self)
        FeralHelperDB.hysteriaTarget = self:GetText()
        self:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Ziel = |cffffff00" .. FeralHelperDB.hysteriaTarget)
    end)
    eb1:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save1 = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    save1:SetSize(70, 24)
    save1:SetPoint("LEFT", eb1, "RIGHT", 6, 0)
    save1:SetText("Speichern")
    save1:SetScript("OnClick", function()
        FeralHelperDB.hysteriaTarget = eb1:GetText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Ziel gespeichert: |cffffff00" .. FeralHelperDB.hysteriaTarget)
    end)

    local targetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    targetBtn:SetSize(60, 24)
    targetBtn:SetPoint("LEFT", save1, "RIGHT", 6, 0)
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

    local lbl2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl2:SetPoint("TOPLEFT", 18, -64)
    lbl2:SetText("Boesartigkeits-Whisper-Text:")

    local eb2 = CreateFrame("EditBox", "FeralHelperOptionsWhisperEditBox", content, "InputBoxTemplate")
    eb2:SetSize(280, 24)
    eb2:SetPoint("TOPLEFT", 22, -84)
    eb2:SetAutoFocus(false)
    eb2:SetMaxLetters(120)
    eb2:SetScript("OnEnterPressed", function(self)
        FeralHelperDB.whisperText = self:GetText()
        self:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Whisper-Text gespeichert.")
    end)
    eb2:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save2 = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    save2:SetSize(70, 24)
    save2:SetPoint("LEFT", eb2, "RIGHT", 6, 0)
    save2:SetText("Speichern")
    save2:SetScript("OnClick", function()
        FeralHelperDB.whisperText = eb2:GetText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Whisper-Text gespeichert.")
    end)

    local lbl3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl3:SetPoint("TOPLEFT", 18, -118)
    lbl3:SetText("Anregen-Whisper-Text:")

    local eb3 = CreateFrame("EditBox", "FeralHelperOptionsInnervateEditBox", content, "InputBoxTemplate")
    eb3:SetSize(280, 24)
    eb3:SetPoint("TOPLEFT", 22, -138)
    eb3:SetAutoFocus(false)
    eb3:SetMaxLetters(120)
    eb3:SetScript("OnEnterPressed", function(self)
        FeralHelperDB.innervateWhisper = self:GetText()
        self:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Anregen-Text gespeichert.")
    end)
    eb3:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local save3 = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    save3:SetSize(70, 24)
    save3:SetPoint("LEFT", eb3, "RIGHT", 6, 0)
    save3:SetText("Speichern")
    save3:SetScript("OnClick", function()
        FeralHelperDB.innervateWhisper = eb3:GetText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Anregen-Text gespeichert.")
    end)

    local sep = content:CreateTexture(nil, "ARTWORK")
    sep:SetSize(470, 1)
    sep:SetPoint("TOPLEFT", 14, -176)
    sep:SetTexture(0.4, 0.4, 0.4)
    sep:SetAlpha(0.8)

    local cbs = {}
    MakeSectionLabel(content, "-- Boesartigkeit (Hysteria) --", -190)
    cbs[1] = MakeCheckbox(content, "Whisper bei Kampfbeginn", -208, "hysteriaWhisperOnCombat")
    cbs[2] = MakeCheckbox(content, "Whisper wenn Hysteria-CD ablaeuft", -230, "hysteriaWhisperOnCdExpire")
    cbs[3] = MakeCheckbox(content, "Whisper bei Klick (Hysteria-Frame)", -252, "hysteriaWhisperOnClick")

    MakeSectionLabel(content, "-- Anregen / Wiedergeburt --", -282)
    cbs[4] = MakeCheckbox(content, "Anregen: Whisper beim Cast", -300, "innervateWhisperEnabled")
    cbs[5] = MakeCheckbox(content, "Anregen/Wiedergeburt: CD im /sagen", -322, "cdToSay")
    cbs[6] = MakeCheckbox(content, "Wiedergeburt: nicht in Reichweite /sagen", -344, "outOfRangeToSay")

    MakeSectionLabel(content, "-- Ueberlebensinstinkte / Hand des Schutzes --", -374)
    cbs[7] = MakeCheckbox(content, "Ueberlebensinstinkte: aktiv im /sagen", -392, "survInstActiveSay")
    cbs[8] = MakeCheckbox(content, "Ueberlebensinstinkte: Countdown im /sagen", -414, "survInstCountdownSay")
    cbs[9] = MakeCheckbox(content, "Hand des Schutzes: entfernt im /sagen", -436, "hopRemovedSay")

    MakeSectionLabel(content, "-- Frames anzeigen --", -468)
    local visCbs = {
        MakeCheckbox(content, "Hysteria-Frame", -486, "showHysteriaFrame"),
        MakeCheckbox(content, "Clearcast-Frame", -508, "showVZFrame"),
        MakeCheckbox(content, "CD-Leiste", -530, "showCDTracker"),
    }
    for _, cb in ipairs(visCbs) do
        cb:SetScript("OnClick", function(self)
            FeralHelperDB[self.dbKey] = self:GetChecked() and true or false
            if FeralHelper.ApplyVisibility then FeralHelper:ApplyVisibility() end
        end)
        cbs[#cbs + 1] = cb
    end

    MakeSectionLabel(content, "-- Katzenrotation --", -560)
    MakeHelpText(content, "Experimentell: Pull-Assist ist ein separates Modul fuer Start-Rota, Snapshot-Fenster und Training.", -578)
    local catCbs = {
        MakeCheckbox(content, "Roar+Rip Warnung", -614, "showRoarRipWarning"),
        MakeCheckbox(content, "Rip-Snapshot/Pull-Modus", -636, "showRipSnapshot"),
        MakeCheckbox(content, "Pull-Assist Modul", -658, "showPullAssistant"),
        MakeCheckbox(content, "Pull-Rota Burst Trainer", -680, "pullTrainerEnabled"),
        MakeCheckbox(content, "Live Rotation Helper", -702, "showRotationHelper"),
    }
    for _, cb in ipairs(catCbs) do
        cb:SetScript("OnClick", function(self)
            FeralHelperDB[self.dbKey] = self:GetChecked() and true or false
            if FeralHelper.ApplyVisibility then FeralHelper:ApplyVisibility() end
        end)
        cbs[#cbs + 1] = cb
    end

    MakeSectionLabel(content, "-- Frames --", -712)
    local lockBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    lockBtn:SetSize(200, 26)
    lockBtn:SetPoint("TOPLEFT", 30, -730)
    lockBtn:SetScript("OnClick", function()
        FeralHelperDB.framesLocked = not FeralHelperDB.framesLocked
        lockBtn:SetText(FeralHelperDB.framesLocked and "Frames entsperren" or "Frames sperren")
        if FeralHelper.SetLocked then FeralHelper:SetLocked(FeralHelperDB.framesLocked) end
        if FeralHelper.configFrame and FeralHelper.configFrame.lockBtn then
            FeralHelper.configFrame.lockBtn:SetText(lockBtn:GetText())
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff33ff99FeralHelper:|r Frames "
            .. (FeralHelperDB.framesLocked and "|cffff3333gesperrt|r" or "|cff33ff99entsperrt|r"))
    end)

    local defaultsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    defaultsBtn:SetSize(150, 26)
    defaultsBtn:SetPoint("TOPLEFT", 250, -730)
    defaultsBtn:SetText("Standard laden")
    defaultsBtn:SetScript("OnClick", function()
        FeralHelper:ApplyDefaultSettings(true)
        RefreshFrames()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Standard-Einstellungen geladen. Positionen bleiben erhalten.")
    end)

    local showFramesBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    showFramesBtn:SetSize(200, 26)
    showFramesBtn:SetPoint("TOPLEFT", 30, -762)
    showFramesBtn:SetText("Frames anzeigen")
    showFramesBtn:SetScript("OnClick", function()
        if FeralHelperDB then
            FeralHelperDB.showHysteriaFrame = true
            FeralHelperDB.showVZFrame = true
            FeralHelperDB.showCDTracker = true
            FeralHelperDB.showRoarRipWarning = true
            FeralHelperDB.showRipSnapshot = true
            FeralHelperDB.showPullAssistant = true
            FeralHelperDB.showRotationHelper = true
        end
        if FeralHelper.ShowPositionFrames then
            FeralHelper:ShowPositionFrames()
        elseif FeralHelper.ApplyVisibility then
            FeralHelper:ApplyVisibility()
        end
        RefreshFrames()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Alle Positions-Frames eingeblendet.")
    end)

    local testBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testBtn:SetSize(220, 28)
    testBtn:SetPoint("TOPLEFT", 250, -762)
    testBtn:SetText("Test-Whisper senden")
    testBtn:SetScript("OnClick", function()
        local target = FeralHelperDB.hysteriaTarget
        if not target or target == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333FeralHelper:|r Kein Ziel gesetzt!")
            return
        end
        SendChatMessage(FeralHelper:GetWhisperText("whisperText"), "WHISPER", nil, target)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeralHelper:|r Test an |cffffff00" .. target .. "|r gesendet.")
    end)

    local moveModeCb = MakeCheckbox(content, "Alle Fenster anzeigen und verschiebbar machen", -800, "showPositionFrames")
    moveModeCb:SetScript("OnClick", function(self)
        FeralHelperDB.showPositionFrames = self:GetChecked() and true or false
        if FeralHelper.SetPositionMode then
            FeralHelper:SetPositionMode(FeralHelperDB.showPositionFrames)
        elseif FeralHelper.ApplyVisibility then
            FeralHelper:ApplyVisibility()
        end
    end)
    cbs[#cbs + 1] = moveModeCb

    panel.editBox = eb1
    panel.editText = eb2
    panel.editInnervate = eb3
    panel.checkboxes = cbs
    panel.lockBtn = lockBtn

    panel.okay = function()
        SaveTexts()
        SaveCheckboxStates(panel)
    end
    panel.default = function()
        FeralHelper:ApplyDefaultSettings(true)
        RefreshFrames()
    end
    panel.refresh = function()
        LoadConfigFrameValues(panel)
    end
    panel:SetScript("OnShow", LoadConfigFrameValues)
    panel:SetScript("OnHide", function(self)
        SaveTexts()
        SaveCheckboxStates(self)
    end)

    self.interfaceOptionsFrame = panel
    LoadConfigFrameValues(panel)
    return panel
end

function FeralHelper:RegisterInterfaceOptions()
    if self.interfaceOptionsRegistered then return end
    local panel = self:CreateInterfaceOptionsPanel()
    if InterfaceOptions_AddCategory and panel then
        InterfaceOptions_AddCategory(panel)
        self.interfaceOptionsRegistered = true
    end
end
