; ============================================================================
;  Fisch Macro Ultimate
;  Created by TopGuy42
;  Website: https://fischmacroultimate.netlify.app/
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

; --- Global initialization (Constants.ahk) ---

MAJOR_VER       := "v1"
FULL_VER        := "v1.2"
ROBLOX_VER      := "version-bf6344c9c23446bf"
ROBLOX_INSTANCE := "RobloxPlayerBeta.exe"
H_PROCESS       := 0
RBLX_PID        := 0
RBLX_BASE       := 0
OFFSETS         := Map()
OFFSETS_PATH    := A_ScriptDir "\settings\offsets.json"
OFFSETS_ROBLOX_VERSION := ""
VERSION_CHECK_COOLDOWN_MS := 60000
_LastVersionCheckAt       := 0
REMOTE_OFFSETS_CACHE_TTL_MS := 60000
_LastRemoteFetchAt          := 0
_LastRemoteFetchResult      := ""

g_CachedDataModel      := 0
g_CachedLocalPlayer    := 0
g_CachedPlayerGui      := 0
g_CachedWorkspaceRoot  := 0
g_CachedWorldConfig    := 0
g_CachedHotbarGui      := 0

APPDATA_DIR   := EnvGet("APPDATA") "\Fisch Macro Ultimate\Macro"
CONFIGS_DIR   := APPDATA_DIR "\configs"
SETTINGS_PATH := APPDATA_DIR "\settings.json"
UPDATE_VERSION_URL := "https://raw.githubusercontent.com/Topguy42/FischMacroUltimate/main/version.txt"
UPDATE_DOWNLOAD_URL := "https://raw.githubusercontent.com/Topguy42/FischMacroUltimate/refs/heads/main/FischMacroUltimate.ahk"
UPDATE_CHECK_TTL_SEC := 3600

ROD           := ""
SETTINGS        := LoadSettings()

ENV             := SETTINGS["env"]
HOTKEYS         := SETTINGS["hotkeys"]
MAIN            := SETTINGS["main"]
MAIN["auto_appraise_enabled"] := 0
APPEARANCE      := SETTINGS["appearance"]

MigrateAllConfigs()



global Macro := CreateFishingMacro()
global Controller := FishingController()


HotkeyManager.RegisterAll(SETTINGS)

try {
    Initialize()
} catch as err {
    MsgBox(err.Message, "Startup Error")
    ExitApp(1)
}

newVer := CheckForFMUUpdate()
if (newVer != "") {
    if (ShowUpdateAvailableGui(FULL_VER, newVer))
        DownloadAndInstallFMUUpdate(newVer)
    else
        GetGui()
} else {
    GetGui()
}

Initialize() {
    global RBLX_PID, RBLX_BASE, ROD, Macro

    EnsureAppDataDirs()

    if (rbxPid := GetRobloxPID()) {
        CheckRobloxVersionMismatch(rbxPid)

        if !EnsureRobloxReady(false, true)
            MsgBox("Roblox was detected, but Macro could not attach. The app will still open. Use Fix Roblox or start the macro again after Roblox is ready.", "Roblox Attachment")
    }

    SetTimer(MacroLoop, MAIN["update_rate"])
}



[:: Reload()


GetGui() {
    global FULL_VER, ROBLOX_VER, RBLX_BASE, RBLX_PID, ENV, ROD, APPEARANCE
    global StatusText, PowerText, ProgressText, CaughtText, LostText, SuccessRateText, RobloxStatusCtrl

    Accent     := APPEARANCE["accent_color"]
    BgColor    := APPEARANCE["bg_color"]
    TextColor  := APPEARANCE["text_color"]
    BorderColor := APPEARANCE["border_color"]
    SubColor   := DimHex(TextColor, 0.6)

    Border.DefaultColor := "0x" BorderColor

    button.DefaultTextColor := "0x" TextColor
    button.DefaultBg := "0x" Accent
    
    Accent := APPEARANCE["accent_color"]
    
    DCLogoPath := A_ScriptDir "\images\DiscordLogo.png"

    mg := Gui("AlwaysOnTop +Border")
    mg.BackColor := "0x" BgColor
    mg.Title := "Fisch Macro Ultimate | " FULL_VER
    mg.SetFont(, "Segoe UI")

    ; App icon: the black logo in the title bar (small icon) so it stays visible on
    ; the light Windows title bar, and the normal white logo in the taskbar / Alt-Tab
    ; switcher (big icon). Per-window small vs big icons require WM_SETICON. The Gui
    ; isn't shown yet here, so DetectHiddenWindows must be on for ahk_id to find it.
    TitleIconPath := A_ScriptDir "\images\LogoBlack.png"
    TaskIconPath  := A_ScriptDir "\images\Logo.png"
    prevDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    if FileExist(TitleIconPath)
        SendMessage(0x0080, 0, LoadHQIcon(TitleIconPath, 16), , "ahk_id " mg.Hwnd)  ; WM_SETICON, ICON_SMALL
    if FileExist(TaskIconPath)
        SendMessage(0x0080, 1, LoadHQIcon(TaskIconPath, 32), , "ahk_id " mg.Hwnd)   ; WM_SETICON, ICON_BIG
    DetectHiddenWindows(prevDHW)

    RobloxStatusCtrl := mg.AddText("x295 y3 w200 h15 c" TextColor, GetRobloxStatusText())
    RobloxStatusCtrl.SetFont("s9 bold")

    MainTab := mg.AddTab3("x0 y0 w400 h630 c" Accent, ["Home", "Appraisal", "Settings", "Changelog", "Credits"])
    MainTab.SetFont("bold")

    MainTab.UseTab(1)
    mg.AddGroupBox("x10 y30 w380 h225 c" TextColor, "Adjustments").SetFont("s9 bold")

    mg.AddText("x20 y50 w150 h20 c" TextColor, "Update rate").SetFont("s10")
    UpdateRateHelp := mg.AddText("x140 y51 w50 h20 c" Accent, "what?")
    UpdateRateHelp.SetFont("underline")
    UpdateRateHelp.OnEvent("Click", (*) => InfoPopup.Show("Update Rate", "Controls how often the macro updates its balancing decisions in milliseconds. Lower values react faster but can click too often. Higher values feel smoother but may respond more slowly."))
        UpdateRate := mg.AddEdit("x250 y50 w40 h20", MAIN["update_rate"])
    mg.AddText("x300 y50 w85 h20 c" TextColor, "1 - 35").SetFont("s9")

    mg.AddText("x20 y75 w150 h20 c" TextColor, "Prediction Strength").SetFont("s10")
    PredictionStrengthHelp := mg.AddText("x140 y76 w50 h20 c" Accent, "what?")
    PredictionStrengthHelp.SetFont("underline")
    PredictionStrengthHelp.OnEvent("Click", (*) => InfoPopup.Show("Prediction Strength", "Controls how far ahead the macro predicts the player bar's movement. Higher values look further ahead and react earlier. Lower values feel more direct but can lag behind fast changes."))
        PredictionStrength := mg.AddEdit("x250 y75 w40 h20", Format("{:.1f}", MAIN["prediction_strength"]))
    mg.AddText("x300 y75 w85 h20 c" TextColor, "1.0 - 20.0").SetFont("s9")

    mg.AddText("x20 y100 w150 h20 c" TextColor, "Neutral duty cycle").SetFont("s10")
    NDCycleHelp := mg.AddText("x140 y101 w50 h20 c" Accent, "what?")
    NDCycleHelp.SetFont("underline")
    NDCycleHelp.OnEvent("Click", (*) => InfoPopup.Show("Neutral duty cycle", "Sets the base hold-versus-release bias while balancing. Higher values hold more often. Lower values release more often."))
        NDCycle := mg.AddEdit("x250 y100 w40 h20", Format("{:.1f}", MAIN["neutral_duty_cycle"]))
    mg.AddText("x300 y100 w85 h20 c" TextColor, "0.20 - 0.60").SetFont("s9")
        
            mg.AddText("x20 y125 w150 h20 c" TextColor, "Close threshold").SetFont("s10")
    CloseThresholdHelp := mg.AddText("x140 y126 w50 h20 c" Accent, "what?")
    CloseThresholdHelp.SetFont("underline")
    CloseThresholdHelp.OnEvent("Click", (*) => InfoPopup.Show("Close Threshold", "How close the fish and player bar positions must be before the macro switches into fine balancing. Lower values require tighter alignment. Higher values start balancing sooner."))
        CloseThreshold := mg.AddEdit("x250 y125 w40 h20", Format("{:.2f}", MAIN["close_threshold"]))
    mg.AddText("x300 y125 w85 h20 c" TextColor, "0.01 - 0.10").SetFont("s9")

    mg.AddText("x20 y150 w150 h20 c" TextColor, "Velocity Damping").SetFont("s10")
    VelocityDampingHelp := mg.AddText("x140 y151 w50 h20 c" Accent, "what?")
    VelocityDampingHelp.SetFont("underline")
    VelocityDampingHelp.OnEvent("Click", (*) => InfoPopup.Show("Velocity Damping", "How fast the player bar can be moving before the macro stops fine balancing and switches back to stronger correction. Lower values react sooner. Higher values keep floating longer."))
        VelocityDamping := mg.AddEdit("x250 y150 w40 h20", MAIN["velocity_damping"])
    mg.AddText("x300 y150 w85 h20 c" TextColor, "10 - 60").SetFont("s9")

    mg.AddText("x20 y175 w150 h20 c" TextColor, "Proportional gain").SetFont("s10")
    ProportionalGainHelp := mg.AddText("x140 y176 w50 h20 c" Accent, "what?")
    ProportionalGainHelp.SetFont("underline")
    ProportionalGainHelp.OnEvent("Click", (*) => InfoPopup.Show("Proportional Gain", "How strongly the macro reacts to position error. Higher values correct harder. Lower values feel softer but can drift more."))
        ProportionalGain := mg.AddEdit("x250 y175 w40 h20", Format("{:.2f}", MAIN["proportional_gain"]))
    mg.AddText("x300 y175 w85 h20 c" TextColor, "0.10 - 1.50").SetFont("s9")

    mg.AddText("x20 y200 w150 h20 c" TextColor, "Derivative gain").SetFont("s10")
    DerivativeGainHelp := mg.AddText("x140 y201 w50 h20 c" Accent, "what?")
    DerivativeGainHelp.SetFont("underline")
    DerivativeGainHelp.OnEvent("Click", (*) => InfoPopup.Show("Derivative Gain", "How strongly the macro reacts to movement speed. Higher values damp swaying more. Too high can make the control feel twitchy."))
        DerivativeGain := mg.AddEdit("x250 y200 w40 h20", Format("{:.2f}", MAIN["derivative_gain"]))
    mg.AddText("x300 y200 w85 h20 c" TextColor, "0.00 - 1.00").SetFont("s9")

    mg.AddText("x20 y225 w150 h20 c" TextColor, "Edge boundary").SetFont("s10")
    EdgeBoundaryHelp := mg.AddText("x140 y226 w50 h20 c" Accent, "what?")
    EdgeBoundaryHelp.SetFont("underline")
    EdgeBoundaryHelp.OnEvent("Click", (*) => InfoPopup.Show("Edge Boundary", "How close the bar can get to either edge before the macro stops balancing and forces recovery. Higher values play safer. Lower values allow more edge tolerance."))
        EdgeBoundary := mg.AddEdit("x250 y225 w40 h20", Format("{:.2f}", MAIN["edge_boundary"]))
    mg.AddText("x300 y225 w85 h20 c" TextColor, "0.02 - 0.30").SetFont("s9")

    UpdateRate.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("update_rate", UpdateRate, 1, 35, true, 0))
    PredictionStrength.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("prediction_strength", PredictionStrength, 1.0, 20.0, false, 1))
        CloseThreshold.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("close_threshold", CloseThreshold, 0.01, 0.10, false, 2))
    NDCycle.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("neutral_duty_cycle", NDCycle, 0.20, 0.60, false, 2))
    VelocityDamping.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("velocity_damping", VelocityDamping, 10.0, 60.0, true, 0))
    ProportionalGain.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("proportional_gain", ProportionalGain, 0.10, 1.50, false, 2))
    DerivativeGain.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("derivative_gain", DerivativeGain, 0.00, 1.00, false, 2))
    EdgeBoundary.OnEvent("LoseFocus", (*) => ValidateAndSaveMain("edge_boundary", EdgeBoundary, 0.02, 0.30, false, 2))

    mg.AddGroupBox("x10 y260 w380 h130 c" TextColor, "Main").SetFont("s9 bold")

    mg.AddText("x20 y285 w150 h20 c" TextColor, "Rod Equipped").SetFont("s10")
    global RodEquipped := mg.AddText("x140 y285 w150 h100 c" TextColor, GetRodDisplayText())
    RodEquipped.SetFont("s10")
    CheckEquippedBtn := mg.AddText("x300 y287 w50 h20 c" Accent, "Check")
    CheckEquippedBtn.SetFont("underline")
    CheckEquippedBtn.OnEvent("Click", (*) => UpdateEquippedRod())

    StatusText := mg.AddText("x20 y320 w150 h20 c" TextColor, "Status: ---")
    StatusText.SetFont("s10")

    PowerText := mg.AddText("x20 y340 w150 h20 c" TextColor, "Power: ---")
    PowerText.SetFont("s10")

    ProgressText := mg.AddText("x20 y360 w150 h20 c" TextColor, "Progress: ---")
    ProgressText.SetFont("s10")

    CaughtText := mg.AddText("x220 y320 w150 h20 c" TextColor, "Caught: 0")
    CaughtText.SetFont("s10")

    LostText := mg.AddText("x220 y340 w150 h20 c" TextColor, "Lost: 0")
    LostText.SetFont("s10")

    SuccessRateText := mg.AddText("x220 y360 w160 h20 c" TextColor, "Success Rate: 0.0%")
    SuccessRateText.SetFont("s10")

    mg.AddGroupBox("x10 y395 w380 h90 c" TextColor, "Info").SetFont("s9 bold")

    mg.AddText("x20 y410 w150 h20 c" TextColor, "Start Macro: " HOTKEYS["start_macro"]).SetFont("s10")
    mg.AddText("x20 y430 w150 h20 c" TextColor, "Fix Roblox: " HOTKEYS["fix_roblox"]).SetFont("s10")
    mg.AddText("x20 y450 w150 h20 c" TextColor, "Reload: " HOTKEYS["reload"]).SetFont("s10")
    ChangeHotkeysBtn := mg.AddText("x320 y433 w65 h20 c" Accent, "Change 🡒")
    ChangeHotkeysBtn.SetFont("s10 underline")
    ChangeHotkeysBtn.OnEvent("Click", (*) => MainTab.Choose(3))

    mg.AddGroupBox("x10 y490 w380 h50 c" TextColor, "Config").SetFont("s9 bold")

    configList := ListConfigs()
    ddlItems := configList.Length > 0 ? configList : ["No configs"]
    ConfigDDL := mg.AddDDL("x20 y510 w160 h200", ddlItems)
    lastConfig := SETTINGS.Has("last_config") ? SETTINGS["last_config"] : ""
    if (lastConfig != "" && configList.Length > 0) {
        try ControlChooseString(lastConfig, ConfigDDL)
        catch
            ConfigDDL.Choose(1)
    } else {
        ConfigDDL.Choose(1)
    }

    LoadConfigBtn := button(mg, "Load", 190, 510, {
        w: 42,
        h: 22,
        bg: BgColor
    })
    LoadConfigBtn.OnEvent("Click", (*) => OnLoadConfig(ConfigDDL))

    SaveConfigBtn := button(mg, "Save", 237, 510, {
        w: 42,
        h: 22,
        bg: BgColor
    })
    SaveConfigBtn.OnEvent("Click", (*) => OnSaveConfig(ConfigDDL))

    NewConfigBtn := button(mg, "New", 284, 510, {
        w: 42,
        h: 22,
        bg: BgColor
    })
    NewConfigBtn.OnEvent("Click", (*) => OnNewConfig(ConfigDDL))

    DeleteConfigBtn := button(mg, "Del", 331, 510, {
        w: 42,
        h: 22,
        bg: BgColor
    })
    DeleteConfigBtn.OnEvent("Click", (*) => OnDeleteConfig(ConfigDDL))
    
    OpenConfigsBtn := mg.AddText("x20 y550 w150 h20 c" Accent, "Open Configs folder")
    OpenConfigsBtn.SetFont("underline")
    OpenConfigsBtn.OnEvent("Click", (*) => Run("explorer.exe `"" CONFIGS_DIR "`""))

    OpenAdvSettingsBtn := mg.AddText("x225 y550 w150 h20 c" Accent, "Open Advanced Settings")
    OpenAdvSettingsBtn.SetFont("s10 underline")
    OpenAdvSettingsBtn.OnEvent("Click", (*) => GetAdvSettingsGui())

    MainTab.UseTab(2)
    mg.AddGroupBox("x10 y30 w380 h205 c" TextColor, "Settings").SetFont("s9 bold")

    AutoAppraise := mg.AddCheckbox("x20 y48 w20 h20")
    AutoAppraise.Value := MAIN["auto_appraise_enabled"]
    mg.AddText("x40 y50 w340 h20 c" TextColor, "Master Switch").SetFont("s9")
    MasterSwitchHelp := mg.AddText("x340 y50 w40 h20 c" Accent, "What?")
    MasterSwitchHelp.SetFont("underline")
    MasterSwitchHelp.OnEvent("Click", (*) => InfoPopup.Show("Master Switch", "When the master switch is off, starting the macro will begin fishing. When it is on, starting the macro will attempt to appraise."))
    Border(mg, 20, 71, 360, 1)

    mg.AddText("x20 y86 w100 h20 c" TextColor, "Mutation").SetFont("s10")
    mutationItems := ["Mythical", "Abyssal", "Glossy", "Electric", "Negative", "Amber", "Fossilized", "Silver", "Darkened", "Scorched", "Albino", "Lunar", "Mosaic", "Translucent", "Shiny", "Big", "Midas", "Hexed", "Frozen", "Sparkling"]
    savedMutation := Trim(MAIN["auto_appraise_mutation"])
    mutationFound := false
    for item in mutationItems {
        if (item = savedMutation) {
            mutationFound := true
            break
        }
    }
    if (!mutationFound && savedMutation != "")
        mutationItems.Push(savedMutation)
    AutoAppraiseMutation := mg.AddDDL("x260 y85 w120 h100", mutationItems)
    try ControlChooseString(savedMutation, AutoAppraiseMutation)
    catch
        AutoAppraiseMutation.Choose(1)
    
    AddMutationButton := mg.AddText("x230 y85 h20 w20 cWhite Center +0x200 +Border +Background0x171717", "+")
    AddMutationButton.SetFont("bold")
    AddMutationButton.OnEvent("Click", AddMutationClicked)

    AutoAppraiseMutationHelp := mg.AddText("x135 y88 h20 c" Accent, "What?")
    AutoAppraiseMutationHelp.SetFont("underline")
    AutoAppraiseMutationHelp.OnEvent("Click", (*) => InfoPopup.Show("Mutation", "Pick your desired mutation, which the macro will get"))
        
        mg.AddText("x20 y113 w100 h20 c" TextColor, "Appraise Delay").SetFont("s10")
    AppraiseDelay := mg.AddEdit("x260 y113 w120 h20", MAIN["appraise_delay_ms"])
        
        AppraiseDelayHelp := mg.AddText("x135 y114 h20 c" Accent, "What?")
    AppraiseDelayHelp.SetFont("underline")
    AppraiseDelayHelp.OnEvent("Click", (*) => InfoPopup.Show("Appraise Delay", "How quickly the macro attempts to check and appraise the held fish. Higher values slow down the appraiser but reduce the chance of the macro breaking."))

    mg.AddText("x20 y141 w100 h20 c" TextColor, "Click Point").SetFont("s10")
    AppraiseClickX := mg.AddEdit("x210 y139 w70 h20 ReadOnly", MAIN["auto_appraise_click_x"])
    AppraiseClickY := mg.AddEdit("x310 y139 w70 h20 ReadOnly", MAIN["auto_appraise_click_y"])
    mg.AddText("x190 y141 w15 h20 c" TextColor, "X").SetFont("s9")
    mg.AddText("x290 y141 w15 h20 c" TextColor, "Y").SetFont("s9")

    PickAppraisePointBtn := button(mg, "Pick Click Point", 20, 168, { w: 170, h: 25, bg: BgColor })
    ClearAppraisePointBtn := button(mg, "Clear Point", 200, 168, { w: 170, h: 25, bg: BgColor })

    global AppraiseStatusText := mg.AddText("x20 y203 w360 h30 c" TextColor, "Status: Ready.")

    mg.AddGroupBox("x10 y245 w380 h160 c" TextColor, "Guide").SetFont("s9 bold")
    mg.AddText("x20 y265 w360 h20 c" SubColor, "Webhook enabled: you'll be notified when appraising finishes.").SetFont("s9")
    mg.AddText("x20 y290 w360 h20 c" SubColor, "Hold the fish you want appraised before starting.").SetFont("s9")
    mg.AddText("x20 y320 w360 h30 c" SubColor, "Set the click point on the appraiser dialogue option, then start appraising.").SetFont("s9")
    mg.AddText("x20 y355 w360 h20 c" SubColor, HOTKEYS["start_macro"] ": Start Appraising").SetFont("s9")
    mg.AddText("x20 y380 w360 h20 c" SubColor, HOTKEYS["stop_appraise"] ": Stop Appraising").SetFont("s9")

    AutoAppraise.OnEvent("Click", SaveAutoAppraiseEnabled)
    AutoAppraiseMutation.OnEvent("Change", SaveAutoAppraiseMutation)
        AppraiseDelay.OnEvent("LoseFocus", SaveAppraiseDelay)
    PickAppraisePointBtn.OnEvent("Click", BeginPickAppraisePoint)
    ClearAppraisePointBtn.OnEvent("Click", ClearAppraisePoint)

    MainTab.UseTab(3)

    AccessabilityHeader:= mg.AddText("x10 y30 w400 h40 c" TextColor, "Accessability")
    AccessabilityHeader.SetFont("s15")
    border(mg, 10, 65, 380, 1)

    StartMacroKey := mg.AddHotkey("x10 y75 w30 h20", SETTINGS["hotkeys"]["start_macro"])
    StartMacroKey.OnEvent("Change", (ctrl, *) => UpdateHotkey("start_macro", ctrl))
    mg.AddText("x50 y74 w100 h20 c" TextColor, "Start Macro").SetFont("s11")
    mg.AddText("x50 y93 w250 h20 c646464", "Change the hotkey with which you start the macro.")

    StopAppraiseKey := mg.AddHotkey("x10 y123 w30 h20", SETTINGS["hotkeys"].Has("stop_appraise") ? SETTINGS["hotkeys"]["stop_appraise"] : "F2")
    StopAppraiseKey.OnEvent("Change", (ctrl, *) => UpdateHotkey("stop_appraise", ctrl))
    mg.AddText("x50 y122 w150 h20 c" TextColor, "Stop Appraising").SetFont("s11")
    mg.AddText("x50 y141 w250 h20 c646464", "Stops an active appraise cycle.")

    FixRbxKey := mg.AddHotkey("x10 y175 w30 h20", SETTINGS["hotkeys"]["fix_roblox"])
    FixRbxKey.OnEvent("Change", (ctrl, *) => UpdateHotkey("fix_roblox", ctrl))
    mg.AddText("x50 y174 w100 h20 c" TextColor, "Fix Roblox").SetFont("s11")
    mg.AddText("x50 y194 w250 h20 c646464", "Do this if Macro cant read your rod")
    FixRbxHelpBtn := mg.AddText("x125 y177 w100 h20 c" Accent, "Learn More")
    FixRbxHelpBtn.SetFont("s9 underline")
    FixRbxHelpBtn.OnEvent("Click", (*) => InfoPopup.Show("Fix Roblox", "Re-attaches Macro to the running Roblox process and reloads memory offsets. Also checks whether the running Roblox version matches the latest release — if they differ, offsets may be out of date and the macro could behave incorrectly."))

    ReloadKey := mg.AddHotkey("x10 y225 w30 h20", SETTINGS["hotkeys"]["reload"])
    ReloadKey.OnEvent("Change", (ctrl, *) => UpdateHotkey("reload", ctrl))
    mg.AddText("x50 y224 w100 h20 c" TextColor, "Reload").SetFont("s11")
    mg.AddText("x50 y243 w250 h20 c646464", "Change the hotkey with which you reload the macro.")

    AppearanceHeader := mg.AddText("x10 y275 w400 h40 c" TextColor, "Appearance")
    AppearanceHeader.SetFont("s15")
    border(mg, 10, 310, 380, 1)

    mg.AddText("x10 y317 w80 h20 c" TextColor, "Theme").SetFont("s10")
    builtInThemes := GetBuiltInThemes()
    themeNames := []
    for name, _ in builtInThemes
        themeNames.Push(name)
    themeNames.Push("Custom")

    ThemeDDL := mg.AddDDL("x260 y315 w110 h200", themeNames)
    lastTheme := SETTINGS.Has("last_theme") ? SETTINGS["last_theme"] : "Custom"
    if (lastTheme != "") {
        try ControlChooseString(lastTheme, ThemeDDL)
        catch
            ThemeDDL.Choose(themeNames.Length)
    } else {
        ThemeDDL.Choose(themeNames.Length)
    }

    mg.AddText("x10 y347 w100 h20 c" TextColor, "Accent color").SetFont("s10")
    AccentInput := mg.AddEdit("x260 y346 w80 h20", APPEARANCE["accent_color"])
    AccentSwatch := mg.AddText("x350 y346 w20 h20 +Border Background" APPEARANCE["accent_color"], "")

    mg.AddText("x10 y374 w100 h20 c" TextColor, "Background").SetFont("s10")
    BgInput := mg.AddEdit("x260 y373 w80 h20", APPEARANCE["bg_color"])
    BgSwatch := mg.AddText("x350 y373 w20 h20 +Border Background" APPEARANCE["bg_color"], "")

    mg.AddText("x10 y401 w100 h20 c" TextColor, "Text color").SetFont("s10")
    TextInput := mg.AddEdit("x260 y400 w80 h20", APPEARANCE["text_color"])
    TextSwatch := mg.AddText("x350 y400 w20 h20 +Border Background" APPEARANCE["text_color"], "")

    mg.AddText("x10 y428 w100 h20 c" TextColor, "Border color").SetFont("s10")
    BorderInput := mg.AddEdit("x260 y427 w80 h20", APPEARANCE["border_color"])
    BorderSwatch := mg.AddText("x350 y427 w20 h20 +Border Background" APPEARANCE["border_color"], "")
    appearanceFields := [
        {key: "accent_color", ctrl: AccentInput, swatch: AccentSwatch, label: "Accent color"},
        {key: "bg_color", ctrl: BgInput, swatch: BgSwatch, label: "Background"},
        {key: "text_color", ctrl: TextInput, swatch: TextSwatch, label: "Text color"},
        {key: "border_color", ctrl: BorderInput, swatch: BorderSwatch, label: "Border color"}
    ]

    ThemeDDL.OnEvent("Change", (*) => ApplyThemePreset(ThemeDDL, builtInThemes, appearanceFields))

    ApplyAppearanceBtn := button(mg, "Apply", 290, 457, {
        w: 80,
        h: 25,
        bg: Accent
    })
    ApplyAppearanceBtn.OnEvent("Click", (*) => ApplyAppearanceChanges(appearanceFields, ThemeDDL))

    OpenSettingsBtn := mg.AddText("x330 y27 w80 h16 c" Accent, "Open folder")
    OpenSettingsBtn.SetFont("underline")
    OpenSettingsBtn.OnEvent("Click", (*) => Run("explorer.exe `"" APPDATA_DIR "`""))

    mg.AddText("x10 y460 w240 h20 c" SubColor, "Press Apply to save and reload.")


    MainTab.UseTab(4)
        mg.AddText("x10 y30 w300 h100 c" TextColor, "Version " FULL_VER).SetFont("s15 bold italic")
        mg.AddText("x260 y33 w150 h50 c" TextColor, "June 15, 2026").SetFont("s12 bold")

    ChangelogText := "• Updated for latest Roblox version`n• Improved macro stability and performance`n• General bug fixes"

        mg.AddText("x15 y65 w370 h510 c" TextColor, ChangelogText).SetFont("s10")

    MainTab.UseTab(5)
    OMLogoPath := A_ScriptDir "\images\Logo.png"
    mg.AddPicture("x10 y30 w35 h30", "HBITMAP:*" LoadHQBitmap(OMLogoPath, 35, 30))
    mg.AddText("x55 y30 w300 h40 c" TextColor " BackgroundTrans", "Fisch Macro Ultimate").SetFont("s15 bold")
    mg.AddText("x15 y70 w300 h40 c" TextColor " BackgroundTrans", "Created by TopGuy42").SetFont("s10")

    LegalNotice := "Fisch Macro Ultimate`n`nCreated by TopGuy42`n`nhttps://fischmacroultimate.netlify.app/"





    mg.AddText("x15 y150 w378 h20 c" TextColor " BackgroundTrans", "License && Legal Notice").SetFont("s10 bold")
    mg.AddText("x15 y172 w378 h345 c" SubColor " BackgroundTrans", LegalNotice).SetFont("s8")





    CreditsWebLink := mg.AddText("x10 y552 w200 h20 c" Accent, "Official Website")
    CreditsWebLink.SetFont("underline")
    CreditsWebLink.OnEvent("Click", (*) => Run("https://fischmacroultimate.netlify.app/"))





    mg.AddText("x10 y578 w380 h20 c" SubColor, "© 2026 TopGuy42 · Fisch Macro Ultimate").SetFont("s8")

    mg.Show("w400 h630 Center")
    UpdateRobloxUiState()
    UpdateMacroStatus("OFF", "---", "---")
        MainTab.OnEvent("Change", ResizeGuiTab)
    MainTab.Choose(1)
        ResizeGuiTab(MainTab)
    lastAllowedTab := MainTab.Value

    if (SETTINGS.Has("just_updated") && SETTINGS["just_updated"]) {
        SETTINGS["just_updated"] := false
        SaveSettingsFile()
        MainTab.Choose(4)
                ResizeGuiTab(MainTab)
    }

    mg.OnEvent("Close", (*) => ExitApp())

    AddMutationClicked(*) {
        newMutation := Trim(GetAddMutationDialog())
        if (newMutation = "")
            return

        AutoAppraiseMutation.Add([newMutation])
        ControlChooseString(newMutation, AutoAppraiseMutation)
        SaveAutoAppraiseMutation(AutoAppraiseMutation)
    }

    SaveAutoAppraiseEnabled(ctrl, *) {
        global MAIN

        MAIN["auto_appraise_enabled"] := ctrl.Value ? 1 : 0
    }
        
        SaveAppraiseDelay(ctrl, *) {
        global MAIN, SETTINGS

        value := Trim(ctrl.Value)

        if !RegExMatch(value, "^\d+$") {
                ctrl.Value := MAIN["appraise_delay_ms"]
                MsgBox("Appraise Delay must be a valid number", "Invalid Appraise Delay")
                return
        }

        value := Integer(value)

        if (value < 0) {
                ctrl.Value := MAIN["appraise_delay_ms"]
                MsgBox("Appraise Delay cannot be a negative.", "Invalid Appraise Delay")
                return
        }

        MAIN["appraise_delay_ms"] := value
        SETTINGS["main"]["appraise_delay_ms"] := value
        ctrl.Value := value

        SaveSettingsFile()
}

    SaveAutoAppraiseMutation(ctrl, *) {
        global MAIN, SETTINGS

        selected := Trim(ctrl.Text)
        if (selected = "")
            return

        MAIN["auto_appraise_mutation"] := selected
        SETTINGS["main"]["auto_appraise_mutation"] := selected
        SaveSettingsFile()
    }

    BeginPickAppraisePoint(*) {
        PickAppraisePointBtn.Enabled := false
        SetAppraiseStatus("Waiting for right-click...")
        CoordMode("Mouse", "Screen")
        Hotkey("RButton", CaptureAppraisePoint, "On")
        Hotkey("Esc", CancelPickAppraisePoint, "On")
    }

    CaptureAppraisePoint(*) {
        ; Hotkey callbacks start with their own coordinate defaults.
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        StopPickAppraisePoint()
        SaveAppraiseClickPoint(x, y)
        SetAppraiseStatus("Click point saved: " x ", " y ".")
    }

    CancelPickAppraisePoint(*) {
        StopPickAppraisePoint()
        SetAppraiseStatus("Click point pick cancelled.")
    }

    StopPickAppraisePoint() {
        Hotkey("RButton", "Off")
        Hotkey("Esc", "Off")
        PickAppraisePointBtn.Enabled := true
        UpdateAppraiseControls()
    }

    SaveAppraiseClickPoint(x, y) {
        global MAIN, SETTINGS

        x := Round(x + 0)
        y := Round(y + 0)
        MAIN["auto_appraise_click_x"] := x
        MAIN["auto_appraise_click_y"] := y
        SETTINGS["main"]["auto_appraise_click_x"] := x
        SETTINGS["main"]["auto_appraise_click_y"] := y
        AppraiseClickX.Value := x
        AppraiseClickY.Value := y
        SaveSettingsFile()
        UpdateAppraiseControls()
    }

    ClearAppraisePoint(*) {
        global MAIN, SETTINGS

        MAIN["auto_appraise_click_x"] := ""
        MAIN["auto_appraise_click_y"] := ""
        SETTINGS["main"]["auto_appraise_click_x"] := ""
        SETTINGS["main"]["auto_appraise_click_y"] := ""
        AppraiseClickX.Value := ""
        AppraiseClickY.Value := ""
        SaveSettingsFile()
        UpdateAppraiseControls()
        SetAppraiseStatus("Click point cleared.")
    }

    UpdateAppraiseControls() {
    }
        
        ResizeGuiTab(ctrl, *){
                switch ctrl.Value{
                        case 1: ; home
                                w := 400, h := 575
                        case 2: ; appraisal
                                w := 400, h := 420
                        case 3: ; Settings
                                w := 400, h := 620
                        case 4: ; Changelog
                                w := 400, h := 620
                        case 5: ; Credits
                                w := 400, h := 620
                }
                MainTab.Move(0, 0, w, h)
                mg.Show ("w" w " h" h)
        }
}

GetRobloxStatusText() {
    global RBLX_PID
    return "PID: " (RBLX_PID ? RBLX_PID : "---")
}

GetRodDisplayText() {
    global ROD
    return (ROD != "" ? ROD : "---")
}

UpdateRobloxUiState() {
    global RobloxStatusCtrl, RodEquipped

    if IsSet(RobloxStatusCtrl) && RobloxStatusCtrl
        RobloxStatusCtrl.Value := GetRobloxStatusText()

    if IsSet(RodEquipped) && RodEquipped
        RodEquipped.Text := GetRodDisplayText()
}

ApplyThemePreset(ddl, themes, appearanceFields) {
    global SETTINGS, APPEARANCE
    themeName := ddl.Text

    if (themeName = "Custom") {
        customTheme := SETTINGS.Has("custom_theme") ? SETTINGS["custom_theme"] : APPEARANCE
        for field in appearanceFields {
            if (customTheme.Has(field.key)) {
                field.ctrl.Value := customTheme[field.key]
                field.swatch.Opt("Background" customTheme[field.key])
            }
        }
        return
    }

    if (!themes.Has(themeName))
        return

    theme := themes[themeName]

    for field in appearanceFields {
        if (theme.Has(field.key)) {
            field.ctrl.Value := theme[field.key]
            field.swatch.Opt("Background" theme[field.key])
        }
    }
}

; Returns an HBITMAP of `path` resized to w*h logical px using GDI+
; HighQualityBicubic interpolation. Supersamples by the screen DPI factor so it
; stays sharp on hi-DPI displays. The "HBITMAP:*" prefix lets the Picture control
; take ownership and free it.
LoadHQBitmap(path, w, h) {
    dpi := A_ScreenDPI / 96
    w := Round(w * dpi), h := Round(h * dpi)

    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si, 0)                                   ; GdiplusVersion = 1
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)

    DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &src := 0)
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0
          , "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst := 0)      ; 32bppARGB
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)  ; HighQualityBicubic
    DllCall("gdiplus\GdipSetSmoothingMode",     "Ptr", g, "Int", 4)  ; AntiAlias
    DllCall("gdiplus\GdipSetPixelOffsetMode",   "Ptr", g, "Int", 2)  ; HighQuality
    DllCall("gdiplus\GdipDrawImageRectI", "Ptr", g, "Ptr", src
          , "Int", 0, "Int", 0, "Int", w, "Int", h)
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", dst, "Ptr*", &hbm := 0, "UInt", 0)

    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", src)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
    return hbm
}

; Returns an HICON of `path` scaled to fit a square `size`x`size` canvas with the
; aspect ratio preserved and transparent padding, using GDI+ HighQualityBicubic.
; Used as the window/taskbar icon via WM_SETICON; Windows frees it on exit/reload.
LoadHQIcon(path, size) {
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si, 0)                                   ; GdiplusVersion = 1
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)

    DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &src := 0)
    DllCall("gdiplus\GdipGetImageWidth",  "Ptr", src, "UInt*", &srcW := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &srcH := 0)

    ; Fit within the square, preserving aspect ratio, centered.
    scale := Min(size / srcW, size / srcH)
    dw := Round(srcW * scale), dh := Round(srcH * scale)
    dx := (size - dw) // 2, dy := (size - dh) // 2

    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", size, "Int", size, "Int", 0
          , "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst := 0)      ; 32bppARGB
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)  ; HighQualityBicubic
    DllCall("gdiplus\GdipSetSmoothingMode",     "Ptr", g, "Int", 4)  ; AntiAlias
    DllCall("gdiplus\GdipSetPixelOffsetMode",   "Ptr", g, "Int", 2)  ; HighQuality
    DllCall("gdiplus\GdipDrawImageRectI", "Ptr", g, "Ptr", src
          , "Int", dx, "Int", dy, "Int", dw, "Int", dh)
    DllCall("gdiplus\GdipCreateHICONFromBitmap", "Ptr", dst, "Ptr*", &hicon := 0)

    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", src)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
    return hicon
}

ApplyAppearanceChanges(appearanceFields, themeDDL := "") {
    global SETTINGS, APPEARANCE

    pendingColors := Map()
    hasChanges := false

    for field in appearanceFields {
        raw := StrUpper(Trim(field.ctrl.Value))

        if !RegExMatch(raw, "^[0-9A-F]{6}$") {
            field.ctrl.Value := APPEARANCE[field.key]
            field.ctrl.Focus()
            MsgBox("Please enter a valid 6-character hex color for " field.label " (e.g. FF0000).", "Invalid Color")
            return
        }

        pendingColors[field.key] := raw
        hasChanges := hasChanges || (raw != APPEARANCE[field.key])
    }

    for field in appearanceFields {
        color := pendingColors[field.key]
        field.ctrl.Value := color
        field.swatch.Opt("Background" color)
    }

    if !hasChanges
        return

    for key, color in pendingColors {
        APPEARANCE[key] := color
        SETTINGS["appearance"][key] := color
    }

    if (themeDDL != "") {
        SETTINGS["last_theme"] := themeDDL.Text
        if (themeDDL.Text = "Custom") {
            for key, color in pendingColors
                SETTINGS["custom_theme"][key] := color
        }
    }

    SaveSettingsFile()
    ReloadMacro()
}

UpdateEquippedRod() {
    global ROD, RodEquipped

    if !EnsureRobloxReady(true, true)
        return

    ROD := GetHotbarRodName()
    UpdateRobloxUiState()
}

UpdateMacroStatus(status := "", power := "", progress := "") {
    global StatusText, PowerText, ProgressText, CaughtText, LostText, SuccessRateText, Macro

    if IsSet(StatusText) && StatusText
        StatusText.Value := "Status: " (status = "" ? "---" : status)

    if IsSet(PowerText) && PowerText
        PowerText.Value := "Power: " (power = "" ? "---" : power)

    if IsSet(ProgressText) && ProgressText
        ProgressText.Value := "Progress: " (progress = "" ? "---" : progress)

    if IsSet(Macro) {
        caught := Macro.fishCaughtCount
        lost := Macro.fishLostCount
        total := caught + lost
        successRate := total > 0 ? (caught / total) * 100.0 : 0.0

        if IsSet(CaughtText) && CaughtText
            CaughtText.Value := "Caught: " caught

        if IsSet(LostText) && LostText
            LostText.Value := "Lost: " lost

        if IsSet(SuccessRateText) && SuccessRateText
            SuccessRateText.Value := "Success Rate: " Format("{:.1f}", successRate) "%"
    }
}

UpdateHotkey(name, ctrl) {
    global SETTINGS

    newKey := ctrl.Value
    oldKey := SETTINGS["hotkeys"][name]

    if (newKey = oldKey)
        return

    if (newKey != "") {
        actionNames := Map(
            "start_macro", "Start Macro",
            "stop_appraise", "Stop Appraising",
            "fix_roblox", "Fix Roblox",
            "reload", "Reload"
        )

        for actionName, assignedKey in SETTINGS["hotkeys"] {
            if (actionName != name && assignedKey = newKey) {
                ctrl.Value := oldKey
                MsgBox(
                    newKey " is already assigned to " actionNames[actionName] ". Please choose a different key.",
                    "Hotkey Conflict"
                )
                return
            }
        }
    }

    callback := (name = "start_macro")   ? (*) => StartMacro()
              : (name = "stop_appraise") ? (*) => StopAppraisingHotkey()
              : (name = "fix_roblox")   ? (*) => FixRoblox()
              :                           (*) => ReloadMacro()

    HotkeyManager.ChangeHotkey(oldKey, newKey, callback)
    SETTINGS["hotkeys"][name] := newKey

    SaveSettingsFile()
    TrayTip("Saved Hotkey locally.", "Settings", "Mute")
}

OnLoadConfig(ddl) {
    if (ddl.Text = "No configs")
        return

    LoadConfig(ddl.Text)
}

OnSaveConfig(ddl) {
    if (ddl.Text = "No configs")
        return

    SaveConfig(ddl.Text)
    ShowConfigSavedDialog(ddl.Text)
}

OnNewConfig(ddl) {
    name := Trim(ShowConfigNameInput())

    if (name = "")
        return

    if (ddl.Text != "No configs") {
        existingConfigs := ListConfigs()
        for cfg in existingConfigs {
            if (cfg = name) {
                ShowConfigAlert("Duplicate Name", "A config named '" name "' already exists.")
                return
            }
        }
    }

    SaveConfig(name, true)

    if (ddl.Text = "No configs") {
        ddl.Delete()
        ddl.Add([name])
    } else {
        ddl.Add([name])
    }

    ControlChooseString(name, ddl)
}

OnDeleteConfig(ddl) {
    if (ddl.Text = "No configs")
        return

    name := ddl.Text

    if (!ShowConfigConfirmDialog(name))
        return

    DeleteConfig(name)

    ddl.Delete()
    remaining := ListConfigs()

    if (remaining.Length = 0) {
        ddl.Add(["No configs"])
        ddl.Choose(1)
    } else {
        ddl.Add(remaining)
        ddl.Choose(1)
    }
}

DimHex(hex, factor) {
    r := Round(Integer("0x" SubStr(hex, 1, 2)) * factor)
    g := Round(Integer("0x" SubStr(hex, 3, 2)) * factor)
    b := Round(Integer("0x" SubStr(hex, 5, 2)) * factor)
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}


class Border {
    static DefaultColor := "0xFFFFFF"

    __New(gui, x, y, w, h, color := "") {
        color := (color != "") ? color : Border.DefaultColor

        this.ctrl := gui.Add("Text",
            "x" x " y" y
            " w" w " h" h
            " +Background" color, "")
    }
}


class button {
    static DefaultW           := 150
    static DefaultH           := 145
    static DefaultBg          := "0x303030"
    static DefaultBorderColor := "0x303030"
    static DefaultBorderSize  := 2
    static DefaultTextColor   := "0xFFFFFF"
    static DefaultFontSize    := 11
    static DefaultFont        := "Segoe UI"
    static DefaultBorder      := true

    __New(gui, text, x, y, options := {}) {
        w         := options.HasProp("w")         ? options.w         : button.DefaultW
        h         := options.HasProp("h")         ? options.h         : button.DefaultH
        bg        := options.HasProp("bg")        ? options.bg        : button.DefaultBg
        textColor := options.HasProp("textColor") ? options.textColor : button.DefaultTextColor
        fontSize  := options.HasProp("fontSize")  ? options.fontSize  : button.DefaultFontSize
        font      := options.HasProp("font")      ? options.font      : button.DefaultFont
        border    := options.HasProp("border")    ? options.border    : button.DefaultBorder

        borderFlag := border ? " +Border" : " -Border"

        gui.SetFont("s" fontSize " c" textColor, font)
        this.ctrl := gui.Add("Text",
            "x" x " y" y
            " w" w " h" h
            " +Background" bg
            borderFlag
            " +0x200 Center",
            text)
        gui.SetFont()
    }

    OnEvent(eventName, callback) {
        this.ctrl.OnEvent(eventName, callback)
    }

    Enabled {
        get => this.ctrl.Enabled
        set => this.ctrl.Enabled := Value
    }
}


class InfoPopup {
    static isOpen := false

    static Show(title, message) {
        global APPEARANCE

        if (this.isOpen)
            return

        this.isOpen := true

        Accent      := APPEARANCE["accent_color"]
        BgColor     := APPEARANCE["bg_color"]
        TextColor   := APPEARANCE["text_color"]
        BorderColor := APPEARANCE["border_color"]

        dlg := Gui("AlwaysOnTop +Border")
        dlg.Title := title
        dlg.BackColor := "0x" BgColor

        dlg.AddText("x10 y10 w380 h24 c" TextColor, title).SetFont("s11")
        Border(dlg, 10, 38, 380, 1, BorderColor)

        info := dlg.AddText("x10 y50 w380 h120 c" TextColor, message)
        info.SetFont("s10")

        understood := button(dlg, "Close", 290, 185, {
            w: 100,
            h: 30,
            fontSize: 12,
            bg: BgColor
        })
        understood.OnEvent("Click", (*) => this.Close(dlg))

        dlg.OnEvent("Close", (*) => this.Close(dlg))
        dlg.OnEvent("Escape", (*) => this.Close(dlg))

        dlg.Show("w400 h230")
    }

    static Close(dlg) {
        dlg.Destroy()
        this.isOpen := false
    }
}


#SingleInstance Force

GetAddMutationDialog()
{
    global APPEARANCE

    result := ""
    Accent := APPEARANCE["accent_color"]
    BgColor := APPEARANCE["bg_color"]
    TextColor := APPEARANCE["text_color"]
    BorderColor := APPEARANCE["border_color"]

    g := Gui("AlwaysOnTop +Border")
    g.BackColor := "0x" BgColor
    g.SetFont(, "Segoe UI")

    g.AddText("x40 y10 w400 h50 c" TextColor, "Add Mutation to DDL").SetFont("s15")
    g.AddPicture("x10 y12 w23 h23 Icon77", "imageres.dll")
    Border(g, 10, 45, 380, 1, BorderColor)

    g.AddText("x10 y63 w125 h20 c" TextColor, "Mutation Name").SetFont("s12")

    Mutation := g.AddEdit("x190 y60 w200 h30 Limit24 -VScroll vMutation")
    Mutation.SetFont("s11")

    addBtn := button(g, "Add", 190, 110, {
        h: 30,
        w: 95,
        bg: Accent,
        textColor: TextColor
    })

    cancelBtn := button(g, "Cancel", 295, 110, {
        h: 30,
        w: 95,
        bg: BgColor,
        textColor: TextColor
    })

    addBtn.OnEvent("Click", AddClicked)
    cancelBtn.OnEvent("Click", CancelClicked)
    g.OnEvent("Close", CancelClicked)
    g.OnEvent("Escape", CancelClicked)

    g.Show("h150 w400")
    Mutation.Focus()

    WinWaitClose(g.Hwnd)
    return result

    AddClicked(*)
    {
        form := g.Submit()
        result := form.Mutation
        g.Destroy()
    }

    CancelClicked(*)
    {
        result := ""
        g.Destroy()
    }
}


GetAdvSettingsGui() {
    global APPEARANCE, MAIN, SETTINGS
    static hwnd := 0

    if (hwnd && WinExist("ahk_id " hwnd)) {
        WinActivate("ahk_id " hwnd)
        return
    }

    Accent      := APPEARANCE["accent_color"]
    BgColor     := APPEARANCE["bg_color"]
    TextColor   := APPEARANCE["text_color"]

    GuiShowOpts := "w400 h420 x900 y100"

    mg := Gui("+AlwaysOnTop +Border")
    mg.BackColor := "0x" BgColor
    mg.Title := "Advanced Settings"
    mg.SetFont(, "Segoe UI")

    button.DefaultTextColor := "0x" TextColor
    button.DefaultBg := "0x" Accent

    MainTab := mg.AddTab3("x0 y0 w400 h420 c" Accent, ["Macro", "Auto Totem", "Webhook"])
    MainTab.SetFont("bold")

    MainTab.UseTab(1)
    mg.AddGroupBox("x10 y25 w380 h200 c" TextColor, "Casting").SetFont("s9 bold")

    mg.AddText("x20 y50 w100 h20 c" TextColor, "Cast Mode").SetFont("s10")
    CastMode := mg.AddDDL("x270 y50 w100", ["Perfect", "Short", "Custom"])
    CastModeHelp := mg.AddText("x190 y50 w50 h20 c" Accent, "What?")
    CastModeHelp.SetFont("underline")
    CastModeHelp.OnEvent("Click", (*) => InfoPopup.Show("Cast Mode", "Chooses the target power level where the macro releases the cast. Perfect uses a fixed high threshold for a full cast, Short uses a low threshold for a quick cast, and Custom uses your own Cast Power Threshold value."))

    mg.AddText("x20 y75 w150 h20 c" TextColor, "Cast Power Threshold").SetFont("s10")
    CastPowerThreshold := mg.AddEdit("x270 y75 w100 h20")
    CastPowerThresholdHelp := mg.AddText("x190 y75 w50 h20 c" Accent, "What?")
    CastPowerThresholdHelp.SetFont("underline")
    CastPowerThresholdHelp.OnEvent("Click", (*) => InfoPopup.Show("Cast Power Threshold", "Used only in Custom cast mode. The macro holds left click until the cast power bar reaches this percentage, then releases. Higher values cast farther, lower values cast sooner."))

    mg.AddText("x20 y100 w150 h20 c" TextColor, "Cast Timeout").SetFont("s10")
    CastTimeout := mg.AddEdit("x270 y100 w100 h20")
    CastTimeoutHelp := mg.AddText("x190 y100 w50 h20 c" Accent, "What?")
    CastTimeoutHelp.SetFont("underline")
    CastTimeoutHelp.OnEvent("Click", (*) => InfoPopup.Show("Cast Timeout", "How long the macro waits before giving up on a cast attempt. Minimum is 5 seconds. It is used while waiting for the cast bar to appear and also while waiting for the fishing UI to appear after release. If the timeout is hit, the macro either retries or stops based on Cast on Timeout."))

    mg.AddText("x20 y125 w150 h20 c" TextColor, "Cycle Start Delay").SetFont("s10")
    PreCastDelay := mg.AddEdit("x270 y125 w100 h20")
    PreCastDelayHelp := mg.AddText("x190 y125 w50 h20 c" Accent, "What?")
    PreCastDelayHelp.SetFont("underline")
    PreCastDelayHelp.OnEvent("Click", (*) => InfoPopup.Show("Cycle Start Delay", "Extra wait at the start of each cycle before the macro casts. Queued auto-totem use also waits this long before touching hotbar items."))

    mg.AddText("x20 y150 w150 h20 c" TextColor, "Post-Cast Delay").SetFont("s10")
    PostCastDelay := mg.AddEdit("x270 y150 w100 h20")
    PostCastDelayHelp := mg.AddText("x190 y150 w50 h20 c" Accent, "What?")
    PostCastDelayHelp.SetFont("underline")
    PostCastDelayHelp.OnEvent("Click", (*) => InfoPopup.Show("Post-Cast Delay", "Wait after releasing the cast before the macro starts the shake phase. Increase it if the game needs extra time between cast release and the hook or shake stage."))

    Border(mg, 20, 180, 350, 1)

    mg.AddText("x40 y193 w100 h20 c" TextColor, "Cast on Timeout").SetFont("s10")
    CastOnTimeout := mg.AddCheckbox("x20 y193 h20 w20")

    SaveCastBtn := button(mg, "Save", 270, 190, {w: 100, h: 23, bg: BgColor, fontSize: 10})

    mg.AddGroupBox("x10 y230 w380 h170 c" TextColor, "Fishing").SetFont("s9 bold")

    mg.AddText("x20 y255 w130 h20 c" TextColor, "Fishing Action Delay").SetFont("s10")
    FishingActionDelay := mg.AddEdit("x270 y255 w100 h20")
    FishingActionDelayHelp := mg.AddText("x190 y255 w50 h20 c" Accent, "What?")
    FishingActionDelayHelp.SetFont("underline")
    FishingActionDelayHelp.OnEvent("Click", (*) => InfoPopup.Show("Fishing Action Delay", "Minimum time between left-click down and up changes while balancing the fish bar. Increase it if rapid hold and release spam causes missed inputs or unstable tracking."))

    mg.AddText("x20 y280 w140 h20 c" TextColor, "Completion Threshold").SetFont("s10")
    CompletionThreshold := mg.AddEdit("x270 y280 w100 h20")
    CompletionThresholdHelp := mg.AddText("x190 y280 w50 h20 c" Accent, "What?")
    CompletionThresholdHelp.SetFont("underline")
    CompletionThresholdHelp.OnEvent("Click", (*) => InfoPopup.Show("Completion Threshold", "Progress percentage where the macro considers the catch complete and exits the fishing phase. Slightly below 100% can finish faster if the game visually reaches full before the bar is mathematically perfect."))

    mg.AddText("x20 y305 w130 h20 c" TextColor, "Shake Interval").SetFont("s10")
    ShakeInterval := mg.AddEdit("x270 y305 w100 h20")
    ShakeIntervalHelp := mg.AddText("x190 y305 w50 h20 c" Accent, "What?")
    ShakeIntervalHelp.SetFont("underline")
    ShakeIntervalHelp.OnEvent("Click", (*) => InfoPopup.Show("Shake Interval", "How often the macro sends Enter during the shake phase while waiting for the fishing UI to appear. Lower values shake more aggressively, higher values shake less often."))

    SaveFishBtn := button(mg, "Save", 270, 340, {w: 100, h: 23, bg: BgColor, fontSize: 10})

    MainTab.UseTab(2)
    mg.AddGroupBox("x10 y25 w380 h150 c" TextColor, "Settings").SetFont("s9 bold")

    mg.AddText("x20 y45 w80 h20 c" TextColor, "Totems").SetFont("s10")
    TotemDdl := mg.AddDropDownList("x270 y45 w100 h100")
    TotemDdlCheckBtn := mg.AddText("x190 y45 w60 h20 c" Accent, "Check")
    TotemDdlCheckBtn.SetFont("underline")
    TotemDdlCheckBtn.OnEvent("Click", (*) => RefreshTotemDdl("", true))

    mg.AddText("x20 y70 w80 h20 c" TextColor, "Use Mode").SetFont("s10")
    UseModeDdl := mg.AddDDL("x270 y70 w100 h100", ["On Expire", "Interval"])
    UseModeHelp := mg.AddText("x190 y70 w60 h20 c" Accent, "What?")
    UseModeHelp.SetFont("underline")
    UseModeDdl.Choose(1)

    mg.AddText("x20 y95 w80 h20 c" TextColor, "Inverval (sec)").SetFont("s10")
    TotemInterval := mg.AddEdit("x270 y95 w100 h20", "15")
    TotemIntervalHelp := mg.AddText("x190 y95 w60 h20 c" Accent, "What?")
    TotemIntervalHelp.SetFont("underline")

    Border(mg, 20, 125, 350, 1)

    AutoTotemEnabled := mg.AddCheckbox("x20 y140 h20 w20")
    mg.AddText("x40 y141 w60 h20 c" TextColor, "Enable").SetFont("s10")
        
        PublicServerEnabled := mg.AddCheckbox("x120 y140 h20 w20")
    mg.AddText("x140 y141 w100 h20 c" TextColor, "Public Server").SetFont("s10")

    SaveTotemBtn := button(mg, "Save", 270, 138, {w: 100, h: 23, bg: BgColor, fontSize: 10})

    MainTab.UseTab(3)
    mg.AddGroupBox("x10 y25 w380 h75 c" TextColor, "Settings").SetFont("s9 bold")

    WebhookUrlEdit := mg.AddEdit("x20 y45 w265 h20")
    TestWebhookBtn := button(mg, "Test", 300, 43, {w: 80, h: 21, bg: BgColor, fontSize: 10})

    WebhookEnabled := mg.AddCheckbox("x20 y72 h20 w20")
    mg.AddText("x40 y74 w60 h20 c" TextColor, "Enable").SetFont("s10")

    mg.AddText("x110 y74 w90 h20 c" TextColor, "Interval (min)").SetFont("s10")
    WebhookInterval := mg.AddEdit("x205 y75 w80 h20")

    SaveWebhookBtn := button(mg, "Save", 300, 73, {w: 80, h: 21, bg: BgColor, fontSize: 10})

    mg.AddGroupBox("x10 y110 w380 h125 c" TextColor, "Summary").SetFont("s9 bold")

    SummaryFishCb := mg.AddCheckbox("x20 y130 h20 w20")
    mg.AddText("x40 y131 w160 h20 c" TextColor, "Fish Caught/Lost").SetFont("s10")

    SummarySuccessRateCb := mg.AddCheckbox("x20 y155 h20 w20")
    mg.AddText("x40 y156 w160 h20 c" TextColor, "Success Rate").SetFont("s10")

    SummaryRodCb := mg.AddCheckbox("x20 y180 h20 w20")
    mg.AddText("x40 y181 w160 h20 c" TextColor, "Rod").SetFont("s10")

    SummaryConfigCb := mg.AddCheckbox("x20 y205 h20 w20")
    mg.AddText("x40 y206 w160 h20 c" TextColor, "Active Config").SetFont("s10")

    SummaryTotemStateCb := mg.AddCheckbox("x200 y130 h20 w20")
    mg.AddText("x220 y131 w160 h20 c" TextColor, "Auto Totem State").SetFont("s10")

    SummaryTotemPopsCb := mg.AddCheckbox("x200 y155 h20 w20")
    mg.AddText("x220 y156 w160 h20 c" TextColor, "Totems Popped").SetFont("s10")

    SummarySessionTimeCb := mg.AddCheckbox("x200 y180 h20 w20")
    mg.AddText("x220 y181 w160 h20 c" TextColor, "Session Runtime").SetFont("s10")

    SummaryCastTimeoutsCb := mg.AddCheckbox("x200 y205 h20 w20")
    mg.AddText("x220 y206 w160 h20 c" TextColor, "Cast Timeouts").SetFont("s10")

    mg.AddGroupBox("x10 y240 w380 h55 c" TextColor, "Alerts").SetFont("s9 bold")

    AlertTotemFailedCb := mg.AddCheckbox("x20 y262 h20 w20")
    mg.AddText("x40 y263 w200 h20 c" TextColor, "Auto Totem Failed").SetFont("s10")

    ApplyCastMode(showPopup := false, *) {
        switch CastMode.Text {
            case "Perfect":
                CastPowerThreshold.Value := "96%"
                CastPowerThreshold.Enabled := false
                if (showPopup)
                    InfoPopup.Show("Perfect Cast Warning", "Fisch has a weird bug which causes the ingame character to move a little with each cast if cast power is above 11%, using perfect cast mode overnight will cause you to fall into the water.")
            case "Short":
                CastPowerThreshold.Value := "10%"
                CastPowerThreshold.Enabled := false
            case "Custom":
                CastPowerThreshold.Value := MAIN["cast_power_custom"] "%"
                CastPowerThreshold.Enabled := true
        }
    }

    CastMode.OnEvent("Change", (*) => ApplyCastMode(true))

    ApplyUseMode(*) {
        TotemInterval.Enabled := (UseModeDdl.Value = 2)
    }

    UseModeDdl.OnEvent("Change", ApplyUseMode)

    LoadAdvFields() {
        switch MAIN["cast_mode"] {
            case "short":  CastMode.Choose(2)
            case "custom": CastMode.Choose(3)
            default:       CastMode.Choose(1)
        }
        ApplyCastMode()

        if (MAIN["cast_mode"] = "custom")
            CastPowerThreshold.Value := MAIN["cast_power_custom"] "%"

        CastTimeout.Value := MAIN["cast_timeout_ms"] / 1000
        PreCastDelay.Value := MAIN["pre_cast_delay_ms"]
        PostCastDelay.Value := MAIN["post_cast_delay_ms"]
        CastOnTimeout.Value := MAIN["cast_on_timeout"]

        FishingActionDelay.Value := MAIN["fishing_action_delay_ms"]
        CompletionThreshold.Value := Format("{:.1f}", MAIN["completion_threshold"]) "%"
        ShakeInterval.Value := MAIN["shake_interval_ms"]

        AutoTotemEnabled.Value := MAIN["auto_totem_enabled"]
                PublicServerEnabled.Value := MAIN["public_server_enabled"]
        UseModeDdl.Choose(MAIN["auto_totem_mode"] = "interval" ? 2 : 1)
        TotemInterval.Value := MAIN["auto_totem_interval_sec"]
        ApplyUseMode()

        WebhookUrlEdit.Value := MAIN["webhook_url"]
        WebhookEnabled.Value := MAIN["webhook_enabled"]
        WebhookInterval.Value := MAIN["webhook_summary_interval_min"]

        SummaryFishCb.Value := MAIN["webhook_summary_fish"]
        SummarySuccessRateCb.Value := MAIN["webhook_summary_success_rate"]
        SummaryRodCb.Value := MAIN["webhook_summary_rod"]
        SummaryConfigCb.Value := MAIN["webhook_summary_config"]
        SummaryTotemStateCb.Value := MAIN["webhook_summary_totem_state"]
        SummaryTotemPopsCb.Value := MAIN["webhook_summary_totem_pops"]
        SummarySessionTimeCb.Value := MAIN["webhook_summary_session_time"]
        SummaryCastTimeoutsCb.Value := MAIN["webhook_summary_cast_timeouts"]

        AlertTotemFailedCb.Value := MAIN["webhook_alert_totem_failed"]
    }

    LoadFallbackTotemDdl(preferredName := "") {
        fallbackName := preferredName != "" ? preferredName : MAIN["auto_totem_name"]
        if (fallbackName = "")
            fallbackName := "Aurora Totem"

        try TotemDdl.Delete()
        TotemDdl.Add([fallbackName])
        TotemDdl.Choose(1)
    }

    RefreshTotemDdl(preferredName := "", interactive := false) {
        currentName := preferredName != "" ? preferredName : TotemDdl.Text
        if (currentName = "No Totems found" || currentName = "")
            currentName := ""

        if !EnsureRobloxReady(interactive, true) {
            LoadFallbackTotemDdl(currentName)
            return
        }

        totems := GetHotbarTotems()

        try TotemDdl.Delete()

        if (totems.Length = 0) {
            TotemDdl.Add(["No Totems found"])
            TotemDdl.Choose(1)
            return
        }

        TotemDdl.Add(totems)

        if (currentName != "") {
            try ControlChooseString(currentName, TotemDdl)
            catch
                TotemDdl.Choose(1)
        } else {
            TotemDdl.Choose(1)
        }
    }

    SaveTotemSettings(*) {
        rawInterval := Trim(TotemInterval.Value)
        previousInterval := MAIN["auto_totem_interval_sec"]

        if !RegExMatch(rawInterval, "^\d+$") || (rawInterval + 0) < 1 {
            TotemInterval.Value := previousInterval
            MsgBox("Interval must be a whole number greater than 0.", "Invalid Value")
            return
        }

        selectedTotem := (TotemDdl.Text = "Aurora Totem") ? "Aurora Totem" : ""
        selectedMode := (UseModeDdl.Value = 2) ? "interval" : "expire"
        intervalSec := rawInterval + 0

        MAIN["auto_totem_enabled"] := AutoTotemEnabled.Value
        SETTINGS["main"]["auto_totem_enabled"] := AutoTotemEnabled.Value

                MAIN["public_server_enabled"] := PublicServerEnabled.Value
        SETTINGS["main"]["public_server_enabled"] := PublicServerEnabled.Value

        MAIN["auto_totem_name"] := selectedTotem
        SETTINGS["main"]["auto_totem_name"] := selectedTotem

        MAIN["auto_totem_mode"] := selectedMode
        SETTINGS["main"]["auto_totem_mode"] := selectedMode

        MAIN["auto_totem_interval_sec"] := intervalSec
        SETTINGS["main"]["auto_totem_interval_sec"] := intervalSec

        SaveSettingsFile()
        if (SETTINGS["last_config"] != "" && FileExist(CONFIGS_DIR "\" SETTINGS["last_config"] ".json"))
            SaveConfig(SETTINGS["last_config"])

        RefreshTotemDdl(selectedTotem)
        SaveTotemBtn.ctrl.Value := "Saved!"
        SetTimer(RevertTotemBtn, -1500)
    }

    SaveCastSettings(*) {
        modeMap := Map(1, "perfect", 2, "short", 3, "custom")
        MAIN["cast_mode"] := modeMap[CastMode.Value]
        SETTINGS["main"]["cast_mode"] := MAIN["cast_mode"]

        if (CastMode.Text = "Custom") {
            raw := RegExReplace(CastPowerThreshold.Value, "%")
            if (IsNumber(raw)) {
                v := Max(1.0, Min(100.0, raw + 0.0))
                MAIN["cast_power_custom"] := v
                SETTINGS["main"]["cast_power_custom"] := v
            }
        }

        raw := Trim(CastTimeout.Value)
        if (IsNumber(raw) && raw + 0 >= 0) {
            v := Max(GetMinCastTimeoutMs(), Round(raw * 1000))
            MAIN["cast_timeout_ms"] := v
            SETTINGS["main"]["cast_timeout_ms"] := v
        }

        for key, ctrl in Map(
            "pre_cast_delay_ms", PreCastDelay,
            "post_cast_delay_ms", PostCastDelay)
        {
            raw := Trim(ctrl.Value)
            if (IsInteger(raw) && raw + 0 >= 0) {
                MAIN[key] := raw + 0
                SETTINGS["main"][key] := raw + 0
            }
        }

        MAIN["cast_on_timeout"] := CastOnTimeout.Value
        SETTINGS["main"]["cast_on_timeout"] := CastOnTimeout.Value

        SaveSettingsFile()
        if (SETTINGS["last_config"] != "" && FileExist(CONFIGS_DIR "\" SETTINGS["last_config"] ".json"))
            SaveConfig(SETTINGS["last_config"])
        LoadAdvFields()
        SaveCastBtn.ctrl.Value := "Saved!"
        SetTimer(RevertCastBtn, -1500)
    }

    RevertCastBtn(*) {
        try SaveCastBtn.ctrl.Value := "Save"
    }

    SaveFishSettings(*) {
        for key, ctrl in Map(
            "fishing_action_delay_ms", FishingActionDelay,
            "shake_interval_ms", ShakeInterval)
        {
            raw := Trim(ctrl.Value)
            if (IsInteger(raw) && raw + 0 >= 0) {
                MAIN[key] := raw + 0
                SETTINGS["main"][key] := raw + 0
            }
        }

        raw := Trim(RegExReplace(CompletionThreshold.Value, "%"))
        if (IsNumber(raw)) {
            v := Max(0.0, Min(100.0, raw + 0.0))
            MAIN["completion_threshold"] := v
            SETTINGS["main"]["completion_threshold"] := v
        }

        SaveSettingsFile()
        if (SETTINGS["last_config"] != "" && FileExist(CONFIGS_DIR "\" SETTINGS["last_config"] ".json"))
            SaveConfig(SETTINGS["last_config"])
        LoadAdvFields()
        SaveFishBtn.ctrl.Value := "Saved!"
        SetTimer(RevertFishBtn, -1500)
    }

    RevertFishBtn(*) {
        try SaveFishBtn.ctrl.Value := "Save"
    }

    RevertTotemBtn(*) {
        try SaveTotemBtn.ctrl.Value := "Save"
    }

    SendTestWebhook(*) {
        url := Trim(WebhookUrlEdit.Value)
        if (url = "") {
            MsgBox("Enter a webhook URL first.", "Webhook")
            return
        }
        try {
            payload := '{"flags":32768,"components":[{"type":17,"accent_color":5763719,"components":[{"type":10,"content":"## Macro Webhook Test\nYour webhook is configured correctly."}]}]}'
            wr := ComObject("WinHttp.WinHttpRequest.5.1")
            wr.Open("POST", url "?with_components=true", false)
            wr.SetRequestHeader("Content-Type", "application/json")
            wr.Send(payload)
            status := wr.Status
            if (status < 200 || status >= 300)
                throw Error("HTTP " status ": " wr.ResponseText)
            TestWebhookBtn.ctrl.Value := "Sent!"
            SetTimer(RevertTestBtn, -1500)
        } catch as err {
            MsgBox("Failed to send: " err.Message, "Webhook Error")
        }
    }

    RevertTestBtn(*) {
        try TestWebhookBtn.ctrl.Value := "Test"
    }

    SaveWebhookSettings(*) {
        rawInterval := Trim(WebhookInterval.Value)
        if !RegExMatch(rawInterval, "^\d+$") || (rawInterval + 0) < 1 {
            WebhookInterval.Value := MAIN["webhook_summary_interval_min"]
            MsgBox("Interval must be a whole number greater than 0.", "Invalid Value")
            return
        }

        MAIN["webhook_url"] := Trim(WebhookUrlEdit.Value)
        SETTINGS["main"]["webhook_url"] := MAIN["webhook_url"]

        MAIN["webhook_enabled"] := WebhookEnabled.Value
        SETTINGS["main"]["webhook_enabled"] := WebhookEnabled.Value

        MAIN["webhook_summary_interval_min"] := rawInterval + 0
        SETTINGS["main"]["webhook_summary_interval_min"] := rawInterval + 0

        SaveSettingsFile()
        if (SETTINGS["last_config"] != "" && FileExist(CONFIGS_DIR "\" SETTINGS["last_config"] ".json"))
            SaveConfig(SETTINGS["last_config"])

        SaveWebhookBtn.ctrl.Value := "Saved!"
        SetTimer(RevertWebhookBtn, -1500)
    }

    RevertWebhookBtn(*) {
        try SaveWebhookBtn.ctrl.Value := "Save"
    }

    PersistWebhookFlag(key, value) {
        MAIN[key] := value
        SETTINGS["main"][key] := value
        SaveSettingsFile()
        if (SETTINGS["last_config"] != "" && FileExist(CONFIGS_DIR "\" SETTINGS["last_config"] ".json"))
            SaveConfig(SETTINGS["last_config"])
    }

    LoadAdvFields()
    RefreshTotemDdl(MAIN["auto_totem_name"])

    SaveCastBtn.OnEvent("Click", SaveCastSettings)
    SaveFishBtn.OnEvent("Click", SaveFishSettings)
    SaveTotemBtn.OnEvent("Click", SaveTotemSettings)
    TestWebhookBtn.OnEvent("Click", SendTestWebhook)
    SaveWebhookBtn.OnEvent("Click", SaveWebhookSettings)

    SummaryFishCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_fish", ctrl.Value))
    SummarySuccessRateCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_success_rate", ctrl.Value))
    SummaryRodCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_rod", ctrl.Value))
    SummaryConfigCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_config", ctrl.Value))
    SummaryTotemStateCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_totem_state", ctrl.Value))
    SummaryTotemPopsCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_totem_pops", ctrl.Value))
    SummarySessionTimeCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_session_time", ctrl.Value))
    SummaryCastTimeoutsCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_summary_cast_timeouts", ctrl.Value))
    AlertTotemFailedCb.OnEvent("Click", (ctrl, *) => PersistWebhookFlag("webhook_alert_totem_failed", ctrl.Value))

    mg.Show(GuiShowOpts)
    hwnd := mg.Hwnd
}



ShowConfigSavedDialog(configName) {
    global APPEARANCE

    Accent    := APPEARANCE["accent_color"]
    BgColor   := APPEARANCE["bg_color"]
    TextColor := APPEARANCE["text_color"]

    dlg := Gui("AlwaysOnTop +Border")
    dlg.Title := "Config Saved"
    dlg.BackColor := "0x" BgColor
    dlg.SetFont(, "Segoe UI")

    dlg.AddText("x40 y12 w300 h25 c" TextColor, "Config Saved").SetFont("s14 bold")
    dlg.AddPicture("x12 y14 w22 h22 Icon78", "imageres.dll")
    Border(dlg, 10, 42, 330, 1)

    dlg.AddText("x12 y55 w328 h30 c" TextColor, "Config '" configName "' has been saved successfully.").SetFont("s10")

    okBtn := button(dlg, "OK", 250, 100, {
        w: 90,
        h: 28,
        fontSize: 11
    })
    okBtn.OnEvent("Click", (*) => dlg.Destroy())

    dlg.OnEvent("Close", (*) => dlg.Destroy())
    dlg.OnEvent("Escape", (*) => dlg.Destroy())

    dlg.Show("w350 h140")
}

ShowConfigNameInput() {
    global APPEARANCE

    Accent    := APPEARANCE["accent_color"]
    BgColor   := APPEARANCE["bg_color"]
    TextColor := APPEARANCE["text_color"]

    result := ""

    dlg := Gui("AlwaysOnTop +Border")
    dlg.Title := "New Config"
    dlg.BackColor := "0x" BgColor
    dlg.SetFont(, "Segoe UI")

    dlg.AddText("x40 y12 w300 h25 c" TextColor, "New Config").SetFont("s14 bold")
    dlg.AddPicture("x12 y14 w22 h22 Icon77", "imageres.dll")
    Border(dlg, 10, 42, 380, 1)

    dlg.AddText("x12 y58 w150 h20 c" TextColor, "Config Name").SetFont("s11")
    nameInput := dlg.AddEdit("x170 y55 w220 h26 Limit32 -VScroll vConfigName")
    nameInput.SetFont("s11")

    saveBtn := button(dlg, "Save", 190, 100, {
        h: 28,
        w: 95,
        fontSize: 11
    })

    cancelBtn := button(dlg, "Cancel", 295, 100, {
        h: 28,
        w: 95,
        bg: BgColor,
        fontSize: 11
    })

    saveBtn.OnEvent("Click", SaveClicked)
    cancelBtn.OnEvent("Click", CancelClicked)
    dlg.OnEvent("Close", CancelClicked)
    dlg.OnEvent("Escape", CancelClicked)

    dlg.Show("h140 w400")
    nameInput.Focus()

    WinWaitClose(dlg.Hwnd)
    return result

    SaveClicked(*) {
        form := dlg.Submit()
        result := form.ConfigName
        dlg.Destroy()
    }

    CancelClicked(*) {
        result := ""
        dlg.Destroy()
    }
}

ShowConfigAlert(title, message) {
    global APPEARANCE

    Accent    := APPEARANCE["accent_color"]
    BgColor   := APPEARANCE["bg_color"]
    TextColor := APPEARANCE["text_color"]

    dlg := Gui("AlwaysOnTop +Border")
    dlg.Title := title
    dlg.BackColor := "0x" BgColor
    dlg.SetFont(, "Segoe UI")

    dlg.AddText("x40 y12 w300 h25 c" TextColor, title).SetFont("s14 bold")
    dlg.AddPicture("x12 y14 w22 h22 Icon84", "imageres.dll")
    Border(dlg, 10, 42, 330, 1)

    dlg.AddText("x12 y55 w328 h30 c" TextColor, message).SetFont("s10")

    okBtn := button(dlg, "OK", 250, 100, {
        w: 90,
        h: 28,
        fontSize: 11
    })
    okBtn.OnEvent("Click", (*) => dlg.Destroy())

    dlg.OnEvent("Close", (*) => dlg.Destroy())
    dlg.OnEvent("Escape", (*) => dlg.Destroy())

    dlg.Show("w350 h140")
}

ShowConfigConfirmDialog(configName) {
    global APPEARANCE

    Accent    := APPEARANCE["accent_color"]
    BgColor   := APPEARANCE["bg_color"]
    TextColor := APPEARANCE["text_color"]

    confirmed := false

    dlg := Gui("AlwaysOnTop +Border")
    dlg.Title := "Confirm Delete"
    dlg.BackColor := "0x" BgColor
    dlg.SetFont(, "Segoe UI")

    dlg.AddText("x40 y12 w310 h25 c" TextColor, "Delete Config").SetFont("s14 bold")
    dlg.AddPicture("x12 y14 w22 h22 Icon84", "imageres.dll")
    Border(dlg, 10, 42, 340, 1)

    dlg.AddText("x12 y55 w338 h30 c" TextColor, "Are you sure you want to delete '" configName "'?").SetFont("s10")

    deleteBtn := button(dlg, "Delete", 165, 100, {
        h: 28,
        w: 90,
        bg: "CC3333",
        fontSize: 11
    })

    cancelBtn := button(dlg, "Cancel", 265, 100, {
        h: 28,
        w: 90,
        bg: BgColor,
        fontSize: 11
    })

    deleteBtn.OnEvent("Click", ConfirmClicked)
    cancelBtn.OnEvent("Click", CancelClicked)
    dlg.OnEvent("Close", CancelClicked)
    dlg.OnEvent("Escape", CancelClicked)

    dlg.Show("w360 h140")

    WinWaitClose(dlg.Hwnd)
    return confirmed

    ConfirmClicked(*) {
        confirmed := true
        dlg.Destroy()
    }

    CancelClicked(*) {
        confirmed := false
        dlg.Destroy()
    }
}



/************************************************************************
 * @description: JSON格式字符串序列化和反序列化, 修改自[HotKeyIt/Yaml](https://github.com/HotKeyIt/Yaml)
 * 增加了对true/false/null类型的支持, 保留了数值的类型
 * @author thqby, HotKeyIt
 * @date 2025/12/22
 * @version 1.0.8
 ***********************************************************************/

class JSON {
        static null := ComValue(1, 0), true := ComValue(0xB, 1), false := ComValue(0xB, 0)

        /**
         * Converts a AutoHotkey Object Notation JSON string into an object.
         * @param text A valid JSON string.
         * @param keepbooltype convert true/false/null to JSON.true / JSON.false / JSON.null where it's true, otherwise 1 / 0 / ''
         * @param as_map object literals are converted to map, otherwise to object
         */
        static parse(text, keepbooltype := false, as_map := true) {
                keepbooltype ? (_true := this.true, _false := this.false, _null := this.null) : (_true := true, _false := false, _null := "")
                as_map ? (map_set := (maptype := Map).Prototype.Set) : (map_set := (obj, key, val) => obj.%key% := val, maptype := Object)
                NQ := "", LF := "", LP := 0, P := "", R := "", text := LTrim(text, " `t`r`n")
                if !text || !InStr('{[', SubStr(text, 1, 1))
                        throw Error("Malformed JSON - unrecognized character.", 0, SubStr(text, 1, 1))
                D := [C := (A := InStr(text, "[") = 1) ? [] : maptype()], text := LTrim(SubStr(text, 2), " `t`r`n"), L := 1, N := 0, V := K := "", J := C, !(Q := InStr(text, '"') != 1) ? text := SubStr(text, 2) : ""
                Loop Parse text, '"' {
                        Q := NQ ? 1 : !Q
                        NQ := Q && RegExMatch(A_LoopField, '(^|[^\\])(\\\\)*\\$')
                        if !Q {
                                if (t := Trim(A_LoopField, " `t`r`n")) = "," || (t = ":" && V := 1)
                                        continue
                                else if t && (InStr("{[]},:", SubStr(t, 1, 1)) || A && RegExMatch(t, "m)^(null|false|true|-?\d+(\.\d*)?([eE][-+]\d+)?)\s*[,}\]\r\n]")) {
                                        Loop Parse t {
                                                if N && N--
                                                        continue
                                                if InStr("`n`r `t", A_LoopField)
                                                        continue
                                                else if InStr("{[", A_LoopField) {
                                                        if !A && !V
                                                                throw Error("Malformed JSON - missing key.", 0, t)
                                                        C := A_LoopField = "[" ? [] : maptype(), A ? D[L].Push(C) : map_set(D[L], K, C), D.Has(++L) ? D[L] := C : D.Push(C), V := "", A := Type(C) = "Array"
                                                        continue
                                                } else if InStr("]}", A_LoopField) {
                                                        if !A && V
                                                                throw Error("Malformed JSON - missing value.", 0, t)
                                                        else if L = 0
                                                                throw Error("Malformed JSON - to many closing brackets.", 0, t)
                                                        else C := --L = 0 ? "" : D[L], A := Type(C) = "Array"
                                                } else if !(InStr(" `t`r,", A_LoopField) || (A_LoopField = ":" && V := 1)) {
                                                        if RegExMatch(SubStr(t, A_Index), "m)^(null|false|true|-?\d+(\.\d*)?([eE][-+]\d+)?)\s*[,}\]\r\n]", &R) && (N := R.Len(0) - 2, R := R.1, 1) {
                                                                if A
                                                                        C.Push(R = "null" ? _null : R = "true" ? _true : R = "false" ? _false : IsNumber(R) ? R + 0 : R)
                                                                else if V
                                                                        map_set(C, K, R = "null" ? _null : R = "true" ? _true : R = "false" ? _false : IsNumber(R) ? R + 0 : R), K := V := ""
                                                                else throw Error("Malformed JSON - missing key.", 0, t)
                                                        } else {
                                                                ; Added support for comments without '"'
                                                                if A_LoopField == '/' {
                                                                        nt := SubStr(t, A_Index + 1, 1), N := 0
                                                                        if nt == '/' {
                                                                                if nt := InStr(t, '`n', , A_Index + 2)
                                                                                        N := nt - A_Index - 1
                                                                        } else if nt == '*' {
                                                                                if nt := InStr(t, '*/', , A_Index + 2)
                                                                                        N := nt + 1 - A_Index
                                                                        } else nt := 0
                                                                        if N
                                                                                continue
                                                                }
                                                                throw Error("Malformed JSON - unrecognized character.", 0, A_LoopField " in " t)
                                                        }
                                                }
                                        }
                                } else if A || InStr(t, ':') > 1
                                        throw Error("Malformed JSON - unrecognized character.", 0, SubStr(t, 1, 1) " in " t)
                        } else if NQ && (P .= A_LoopField '"', 1)
                                continue
                        else if A
                                LF := P A_LoopField, C.Push(InStr(LF, "\") ? UC(LF) : LF), P := ""
                        else if V
                                LF := P A_LoopField, map_set(C, K, InStr(LF, "\") ? UC(LF) : LF), K := V := P := ""
                        else
                                LF := P A_LoopField, K := InStr(LF, "\") ? UC(LF) : LF, P := ""
                }
                return J
                UC(S, e := 1) {
                        static m := Map('"', '"', "a", "`a", "b", "`b", "t", "`t", "n", "`n", "v", "`v", "f", "`f", "r", "`r")
                        local v := ""
                        Loop Parse S, "\"
                                if !((e := !e) && A_LoopField = "" ? v .= "\" : !e ? (v .= A_LoopField, 1) : 0)
                                        v .= (t := m.Get(SubStr(A_LoopField, 1, 1), 0)) ? t SubStr(A_LoopField, 2) :
                                                (t := RegExMatch(A_LoopField, "i)^(u[\da-f]{4}|x[\da-f]{2})\K")) ?
                                                        Chr("0x" SubStr(A_LoopField, 2, t - 2)) SubStr(A_LoopField, t) : "\" A_LoopField,
                                                        e := A_LoopField = "" ? e : !e
                        return v
                }
        }

        /**
         * Converts a AutoHotkey Array/Map/Object to a Object Notation JSON string.
         * @param obj A AutoHotkey value, usually an object or array or map, to be converted.
         * @param expandlevel The level of JSON string need to expand, by default expand all.
         * @param space Adds indentation, white space, and line break characters to the return-value JSON text to make it easier to read.
         */
        static stringify(obj, expandlevel := unset, space := "  ") {
                expandlevel := IsSet(expandlevel) ? Abs(expandlevel) : 10000000
                return Trim(CO(obj, expandlevel))
                CO(O, J := 0, R := 0, Q := 0) {
                        static M1 := "{", M2 := "}", S1 := "[", S2 := "]", N := "`n", C := ",", S := "- ", E := "", K := ":"
                        if (OT := Type(O)) = "Array" {
                                D := !R ? S1 : ""
                                for key, value in O {
                                        F := (VT := Type(value)) = "Array" ? "S" : InStr("Map,Object", VT) ? "M" : E
                                        Z := VT = "Array" && value.Length = 0 ? "[]" : ((VT = "Map" && value.count = 0) || (VT = "Object" && ObjOwnPropCount(value) = 0)) ? "{}" : ""
                                        D .= (J > R ? "`n" CL(R + 2) : "") (F ? (%F%1 (Z ? "" : CO(value, J, R + 1, F)) %F%2) : ES(value)) (OT = "Array" && O.Length = A_Index ? E : C)
                                }
                        } else {
                                D := !R ? M1 : ""
                                for key, value in (OT := Type(O)) = "Map" ? (Y := 1, O) : (Y := 0, O.OwnProps()) {
                                        F := (VT := Type(value)) = "Array" ? "S" : InStr("Map,Object", VT) ? "M" : E
                                        Z := VT = "Array" && value.Length = 0 ? "[]" : ((VT = "Map" && value.count = 0) || (VT = "Object" && ObjOwnPropCount(value) = 0)) ? "{}" : ""
                                        D .= (J > R ? "`n" CL(R + 2) : "") (Q = "S" && A_Index = 1 ? M1 : E) ES(key) K (F ? (%F%1 (Z ? "" : CO(value, J, R + 1, F)) %F%2) : ES(value)) (Q = "S" && A_Index = (Y ? O.count : ObjOwnPropCount(O)) ? M2 : E) (J != 0 || R ? (A_Index = (Y ? O.count : ObjOwnPropCount(O)) ? E : C) : E)
                                        if J = 0 && !R
                                                D .= (A_Index < (Y ? O.count : ObjOwnPropCount(O)) ? C : E)
                                }
                        }
                        if J > R
                                D .= "`n" CL(R + 1)
                        if R = 0
                                D := RegExReplace(D, "^\R+") (OT = "Array" ? S2 : M2)
                        return D
                }
                ES(S) {
                        switch Type(S) {
                                case "Float":
                                        if (v := '', d := InStr(S, 'e'))
                                                v := SubStr(S, d), S := SubStr(S, 1, d - 1)
                                        if ((StrLen(S) > 17) && (d := RegExMatch(S, "(99999+|00000+)\d{0,3}$")))
                                                S := Round(S, Max(1, d - InStr(S, ".") - 1))
                                        return S v
                                case "Integer":
                                        return S
                                case "String":
                                        S := StrReplace(S, "\", "\\")
                                        S := StrReplace(S, "`t", "\t")
                                        S := StrReplace(S, "`r", "\r")
                                        S := StrReplace(S, "`n", "\n")
                                        S := StrReplace(S, "`b", "\b")
                                        S := StrReplace(S, "`f", "\f")
                                        S := StrReplace(S, "`v", "\v")
                                        S := StrReplace(S, '"', '\"')
                                        return '"' S '"'
                                default:
                                        return S == this.true ? "true" : S == this.false ? "false" : "null"
                        }
                }
                CL(i) {
                        Loop (s := "", space ? i - 1 : 0)
                                s .= space
                        return s
                }
        }
}

Class EmbedBuilder {
   __New() {
      this.embedObj := {}
   }
   /**
    * @method setTitle()
    * @param {string} title 
    */
   setTitle(title) {
      if !(title is String)
         throw Error("expected a string", , title)
      this.embedObj.title := title
   }
   /**
    * @method setDescription()
    * @param {string} description 
    */
   setDescription(description) {
      if !(description is String)
         throw Error("expected a string", , description)
      this.embedObj.description := description
   }
   /**
    * @method setURL()
    * @param {URL} URL 
    */
   setURL(URL) {
      if !(URL is String)
         throw Error("expected a string", , URL)
      if !(RegExMatch(URL, ":\/\/"))
         throw Error("expected an URL", , URL)
      this.embedObj.url := URL
   }
   /**
    * @method setColor()
    * @param {Hex | Decimal Integer} Color 
    */
   setColor(Color) {
      if !(Color is Integer)
         throw Error("expected an integer", , Color)
      this.embedObj.color := Color + 0
   }
   /**
    * @method setTimestamp()
    * @param {timestamp} timestamp "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
    * @default this.now()
    */
   setTimeStamp(timestamp:="") {
      if IsSet(timestamp)
         if !RegExMatch(timestamp, "i)\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
            throw Error("invalid timestamp", , timestamp)
      time := A_NowUTC
      this.embedObj.timestamp := timestamp || SubStr(time, 1,4) "-" SubStr(time,5,2) "-" SubStr(time,7,2) "T" SubStr(time,9,2) ":" SubStr(time,11,2) ":" SubStr(time,13,2) ".000Z"
   }
   /**
    * @method setAuthor()
    * @param {object} author
    * @property {string} name
    * @property {url} url
    * @property {url} icon_url
    */
   setAuthor(author) {
      if !(author is object)
         throw Error("Expected an object literal")
      for k, v in author.OwnProps()
         if !this.hasVal(["name", "icon_url", "url"], k)
            throw Error("Expected one of the following propertires: `"name`", `"icon_url`", `"url`"`nReceived: " k)
      this.embedObj.author := author
   }
   /**
    * @method addFields()
    * @param {array of objects} fields .addFields([{name:"name",value:"value"}])
    * @property {string} name
    * @property {string} value
    * @property {Boolean} inline
    */
   addFields(fields) {
      if !(fields is Array)
         throw Error("expected an array", , fields)
      for i in fields {
         if !(i is Object)
            throw Error("Expected an object literal")
         for k, v in i.OwnProps()
            if !this.hasVal(["name", "value", "inline"], k)
               throw Error("Expected one of the following propertires: `"name`", `"value`", `"inline`"`nReceived: " k)
      }
      if this.embedObj.HasProp("fields")
         this.embedObj.fields.push(fields)
      else this.embedObj.fields := fields
   }
   /**
    * @method setFooter()
    * @param {object} footer
    * @property {string} text
    * @property {url} icon_url
    */
   setFooter(footer) {
      if !(footer is object)
         throw Error("Expected an object literal")
      for k, v in footer.OwnProps()
         if !this.hasVal(["text", "icon_url"], k)
            throw Error("Expected one of the following propertires: `"text`", `"icon_url`"`nReceived: " k)
      this.embedObj.footer := footer
   }
   /**
    * @method setThumbnail()
    * @param {object} thumbnail
    * @property {url} url
    */
   setThumbnail(thumbnail) {
      if !IsObject(thumbnail)
         throw Error("expected an object", , thumbnail)
      if !RegExMatch(thumbnail.url, ":\/\/")
         throw Error("requires an url or attachment.attachmentName (attachment://filename.extension)", , thumbnail.url)
      this.embedObj.thumbnail := thumbnail
   }
   hasVal(obj, val) {
      for k, v in obj
         if v = val
            return k
      return 0
   }
   /**
    * @method setImage()
    * @param {object} image
    * @property {url} url 
    */
   setImage(image) {
      if !IsObject(image)
         throw Error("expected an object", , image)
      if !RegExMatch(image.url, ":\/\/")
         throw Error("requires an url or attachment.attachmentName (attachment://filename.extension)", , image.url)
      this.embedObj.image := image
   }
}
Class AttachmentBuilder {
   /**
    * new AttachmentBuilder()
    * @param File relative path to file
    */
   __New(File) {
      if !FileExist(File)
         throw Error("Filename <" File "> doesnt exist", , File)
      this.fileName := File
      this.attachmentName := "attachment://" File
   }
}

Class Discord {
   Class Webhook extends Discord {
      __New(webhookURL) {
         if !RegexMatch(webhookURL, "^https?:\/\/discord\.com\/api\/webhooks\/\d+\/[\w|-]+$")
            throw Error("invalid webhook url")
         this.webhookURL := webhookURL
      }
   }
   send(obj) {
      for k, v in obj.embeds
         obj.embeds[k] := v.embedObj
      FileArr := []
      payload := '{"content":' (obj.HasProp("content") ? '"' obj.content '"' : "null") (obj.HasProp("embeds") ? ',"embeds":' this.dump(obj.embeds) : "") '}'
      objParam := { payload_json: payload, files: obj.files }
      this.createFormData(&payload, &header, objParam)
      wr := ComObject("WinHttp.WinHttpRequest.5.1")
      wr.Open("POST", this.webhookURL, true)
      wr.SetRequestHeader("Content-Type", header)
      wr.send(payload)
      wr.WaitForResponse
      if !this.response := wr.ResponseText
         return 1
      return 0
   }
   /**
    * @author tmplinshi | converted and edited by ninju
    * @url https://gist.github.com/tmplinshi/59618b75447e20f1f6402ba89b0e99cd
    * @param {string} retData the payload
    * @param {string} contentType returns the header
    * @param {object} fields input object
    */
   CreateFormData(&retData, &contentType, fields)
   {
      static chars := "0|1|2|3|4|5|6|7|8|9|a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z"
      static CRLF := "`r`n"
      chars := Sort(chars, "D| Random")
      boundary := SubStr(StrReplace(chars, "|"), 1, 12)
      BoundaryLine := "------------------------------" . Boundary
      hData := DllCall("GlobalAlloc", "UInt", 0x2, "UPtr", 0, "Ptr")
      DllCall("ole32\CreateStreamOnHGlobal", "Ptr", hData, "Int", 0, "Ptr*", &pStream := 0, "UInt")

      len := 0, ptr := DllCall("GlobalAlloc", "UInt", 0x40, "UInt", 1, "Ptr")
      for k, v in fields.OwnProps() {
         If IsObject(v) {
            For i, file in v
            {
               str := BoundaryLine . CRLF
                  . 'Content-Disposition: form-data; name="' . file.fileName . '"; filename="' . file.fileName . '"' . CRLF
                  . "Content-Type: " . MimeType(file.fileName) . CRLF . CRLF
               StrPutUTF8(str, &ptr, &len)
               LoadFromFile(file.fileName, &ptr, &len)
               StrPutUTF8(CRLF, &ptr, &len)
            }
         } Else {
            str := BoundaryLine . CRLF
               . 'Content-Disposition: form-data; name="' . k '"' . CRLF . CRLF
               . v . CRLF
            StrPutUTF8(str, &ptr, &len)
         }
      }
      StrPutUTF8(str, &ptr, &len) {
         Local ReqSz := StrPut(str, "utf-8") - 1
         Len += ReqSz                                  ; GMEM_ZEROINIT|GMEM_MOVEABLE = 0x42
         Ptr := DllCall("GlobalReAlloc", "Ptr", Ptr, "UInt", len + 1, "UInt", 0x42)
         StrPut(str, Ptr + len - ReqSz, ReqSz, "utf-8")
      }

      LoadFromFile(Filename, &ptr, &len) {
         Local objFile := FileOpen(FileName, "r")
         Len += objFile.Length
         Ptr := DllCall("GlobalReAlloc", "Ptr", Ptr, "UInt", len, "UInt", 0x42)
         objFile.RawRead(Ptr + Len - objFile.length, objFile.length)
         objFile.Close()
      }
      MimeType(FileName) {
         i := FileOpen(FileName, "r")
         n := i.ReadUInt()
         Return (n = 0x474E5089) ? "image/png"
         : (n = 0x38464947) ? "image/gif"
            : (n & 0xFFFF = 0x4D42) ? "image/bmp"
               : (n & 0xFFFF = 0xD8FF) ? "image/jpeg"
                  : (n & 0xFFFF = 0x4949) ? "image/tiff"
                     : (n & 0xFFFF = 0x4D4D) ? "image/tiff"
                        : "application/octet-stream"
      }
      StrPutUTF8(BoundaryLine . "--" . CRLF, &ptr, &len)

      ; Create a bytearray and copy data in to it.
      retData := ComObjArray(0x11, Len) ; Create SAFEARRAY = VT_ARRAY|VT_UI1
      pvData := NumGet(ComObjValue(retData) + 8 + A_PtrSize, "uptr")
      DllCall("RtlMoveMemory", "Ptr", pvData, "Ptr", Ptr, "Ptr", Len)

      Ptr := DllCall("GlobalFree", "Ptr", Ptr, "Ptr")                   ; free global memory

      contentType := "multipart/form-data; boundary=----------------------------" . Boundary
   }
   dump(obj) {
      if !(obj is Object)
         return this.escapeStr(obj)
      out := ""
      if (obj is Array || obj is Map) {
         for k, v in obj {
            if (obj is Map)
               out .= this.escapeStr(k) ":"

            out .= this.dump(v) ","
         }

         if out != ""
            out := Trim(out, ",")

         return (obj is array) ? "[" . out . "]" : "{" . out . "}"
      }
      for k, v in obj.OwnProps() {
         out .= this.escapeStr(k) ":" this.dump(v) ","
      }
      if out != ""
         out := Trim(out, ",")
      return "{" out "}"
   }
   escapeStr(obj) => '"' StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(obj, "\", "\\"), "`t", "\t"), "`r", "\r"), "`n", "\n"), "`b", "\b"), "`f", "\f"), "/", "\/"), '"', '\"') '"'
}


;APPRAISE_FIXED_DELAY_MS := 100
APPRAISE_FIXED_RETRY_MS := 500
APPRAISE_SUBVALUES_MAX_RETRIES := 5

IsAutoAppraiseRuntimeEnabled() {
    global MAIN
    return MAIN.Has("auto_appraise_enabled") && MAIN["auto_appraise_enabled"] ? true : false
}

HasAutoAppraiseClickPoint() {
    global MAIN
    return MAIN.Has("auto_appraise_click_x")
        && MAIN.Has("auto_appraise_click_y")
        && Trim(MAIN["auto_appraise_click_x"]) != ""
        && Trim(MAIN["auto_appraise_click_y"]) != ""
        && IsNumber(MAIN["auto_appraise_click_x"])
        && IsNumber(MAIN["auto_appraise_click_y"])
}

ClearAppraiseRuntimeCache() {
    global Macro

    Macro.appraiseSubvaluesAddr := 0
    Macro.appraiseLastClickAt := 0
    Macro.appraiseWaitStartedAt := 0
    Macro.appraiseSubvaluesRetryCount := 0
    Macro.appraiseSubvaluesLastRetryAt := 0
    Macro.appraiseStartCoins := ""
    Macro.appraiseEndCoins := ""
    Macro.appraiseState := "IDLE"
    Macro.appraiseLastError := ""
}

StartAppraiseCycle() {
    global Macro, MAIN

    if (!IsAnythingEquipped()) {
        MsgBox("You have to have a fish selected when appraising.", "Appraisal")
        return false
    }

    if (!HasAutoAppraiseClickPoint()) {
        SetAppraiseStatus("Set a click point before appraising.")
        MsgBox("Set a click point in the Appraisal tab before starting.", "Appraisal")
        return false
    }

    desiredMutation := Trim(MAIN["auto_appraise_mutation"])
    if (desiredMutation = "") {
        SetAppraiseStatus("Choose a desired mutation.")
        MsgBox("Choose a desired mutation before starting.", "Appraisal")
        return false
    }

    ReleaseMouse(true)
    ClearAppraiseRuntimeCache()

    Macro.phase := "APPRAISE"
    Macro.appraiseState := "RESOLVING"
    Macro.cycleEnabled := true
    SetAppraiseStatus("Resolving fish info...")
    UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")

    try {
        subvaluesAddr := ResolveFishInfoSubvalues()
        if (!subvaluesAddr)
            throw Error("Could not find Workspace/<player>/fishinfo/Info/Subvalues. Hold the fish before appraising.")

        Macro.appraiseStartCoins := ReadCurrentAppraiseCoins()

        if (HasDesiredMutationInCachedSubvalues(desiredMutation)) {
            Macro.cycleEnabled := false
            Macro.phase := "DONE"
            Macro.appraiseState := "DONE"
            SetAppraiseStatus(desiredMutation " mutation was already present.")
            UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")
            return true
        }

        Macro.appraiseState := "CLICK_FIRST"
        SetAppraiseStatus("Ready.")
        UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")
        return true
    } catch as err {
        FailAppraiseCycle(err.Message)
        return false
    }
}

StopAppraiseCycle(nextPhase := "OFF", status := "Stopped.") {
    global Macro

    ReleaseMouse(true)
    Macro.cycleEnabled := false
    Macro.phase := nextPhase

    if (nextPhase = "OFF")
        ClearAppraiseRuntimeCache()
    else
        Macro.appraiseState := nextPhase

    SetAppraiseStatus(status)
    UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")
}

UpdateAppraisePhase() {
    global Macro, MAIN, APPRAISE_SUBVALUES_MAX_RETRIES, APPRAISE_FIXED_RETRY_MS

    switch Macro.appraiseState {
        case "CLICK_FIRST":
            SetAppraiseStatus("Clicking 1/2.")
            ClickAppraisePoint()
            Macro.appraiseLastClickAt := A_TickCount
            Macro.appraiseState := "CLICK_SECOND"

        case "CLICK_SECOND":
            if ((A_TickCount - Macro.appraiseLastClickAt) < MAIN["appraise_delay_ms"])
                return

            SetAppraiseStatus("Clicking 2/2.")
            ClickAppraisePoint()
                        Macro.appraiseLastClickAt := A_TickCount
                        Macro.appraiseWaitStartedAt := A_TickCount
                        Macro.appraiseSubvaluesLastRetryAt := A_TickCount
                        Macro.appraiseState := "WAIT_RESULT"

        case "WAIT_RESULT":
                
            desiredMutation := Trim(MAIN["auto_appraise_mutation"])
                        
            try {
                if (HasDesiredMutationInCachedSubvalues(desiredMutation)) {
                    CompleteAppraiseCycle("Found " desiredMutation ".")
                    return
                }
            } catch as err {
                if (InStr(err.Message, "Subvalues")) {
                    if (Macro.appraiseSubvaluesLastRetryAt
                        && (A_TickCount - Macro.appraiseSubvaluesLastRetryAt) < APPRAISE_FIXED_RETRY_MS) {
                        return
                    }

                    Macro.appraiseSubvaluesLastRetryAt := A_TickCount
                    Macro.appraiseSubvaluesRetryCount += 1

                    if (Macro.appraiseSubvaluesRetryCount <= APPRAISE_SUBVALUES_MAX_RETRIES) {
                        SetAppraiseStatus(
                            "Waiting for fish info/Subvalues... "
                            Macro.appraiseSubvaluesRetryCount
                            "/"
                            APPRAISE_SUBVALUES_MAX_RETRIES
                        )
                        return
                    }
                }

                FailAppraiseCycle(err.Message)
                return
            }
                        
                        Macro.appraiseSubvaluesRetryCount := 0
                        Macro.appraiseSubvaluesLastRetryAt := 0

            SetAppraiseStatus("Still looking for " desiredMutation ".")
            Macro.appraiseWaitStartedAt := A_TickCount
            Macro.appraiseState := "WAIT_RETRY"

        case "WAIT_RETRY":
            if ((A_TickCount - Macro.appraiseWaitStartedAt) < MAIN["appraise_delay_ms"])
                return

            SetAppraiseStatus("Retrying.")
            Macro.appraiseWaitStartedAt := 0
            Macro.appraiseState := "CLICK_FIRST"
    }
}

ResolveFishInfoSubvalues() {
    global Macro

    workspace := GetWorkspaceRoot()
    if (!workspace)
        return 0

    localPlayer := GetLocalPlayer()
    if (!localPlayer)
        return 0

    playerName := ReadInstanceName(localPlayer)
    if (playerName = "" || playerName = "<null>")
        return 0

    character := FindChildByName(workspace, playerName)
    if (!character)
        return 0

    fishInfo := FindChildByName(character, "fishinfo")
    if (!fishInfo)
        return 0

    info := FindChildByName(fishInfo, "Info")
    if (!info)
        return 0

    subvalues := FindChildByName(info, "Subvalues")
    if (subvalues)
        Macro.appraiseSubvaluesAddr := subvalues
    else
        Macro.appraiseSubvaluesAddr := 0

    return subvalues
}

ResolveFishInfoSubvaluesOnce() {
    return ResolveFishInfoSubvalues()
}

HasDesiredMutationInCachedSubvalues(desiredMutation) {
    subvaluesAddr := ResolveFishInfoSubvalues()

    if (!subvaluesAddr)
        throw Error("Could not find Workspace/<player>/fishinfo/Info/Subvalues. Hold or re-equip the fish before appraising.")

    desired := NormalizeAppraiseText(desiredMutation)
    if (desired = "")
        return false

    haystack := NormalizeAppraiseText(CollectSubvaluesText(subvaluesAddr))
    return InStr(haystack, desired) ? true : false
}

CollectSubvaluesText(subvaluesAddr) {
    textParts := []
    AppendAppraiseNodeText(textParts, subvaluesAddr)

    for childAddr in ReadChildren(subvaluesAddr) {
        AppendAppraiseNodeText(textParts, childAddr)

        for descendantAddr in ReadChildren(childAddr)
            AppendAppraiseNodeText(textParts, descendantAddr)
    }

    return JoinTextParts(textParts)
}

AppendAppraiseNodeText(textParts, instanceAddr) {
    try {
        className := ReadClassName(instanceAddr)
        if (!IsAppraiseTextCapable(className))
            return

        text := ReadGuiText(instanceAddr)
        if (text = "" && InStr(className, "Value"))
            text := ReadPropertyString(instanceAddr, ["Value"])

        text := Trim(text)
        if (text != "")
            textParts.Push(text)
    } catch {
    }
}

IsAppraiseTextCapable(className) {
    return InStr(className, "Text") || InStr(className, "Value")
}

NormalizeAppraiseText(text) {
    text := StrReplace(text, "`r", "`n")
    text := RegExReplace(text, "<[^>]+>")
    text := RegExReplace(text, "\s+", " ")
    return StrLower(Trim(text))
}

JoinTextParts(textParts) {
    out := ""
    for part in textParts {
        if (out != "")
            out .= " "
        out .= part
    }
    return out
}

GetCurrentAppraiseBonusAttributes() {
    bonusAttributes := []

    try {
        subvaluesAddr := ResolveFishInfoSubvalues()
        if (!subvaluesAddr)
            return bonusAttributes

        haystack := NormalizeAppraiseText(CollectSubvaluesText(subvaluesAddr))
        if (InStr(haystack, "shiny"))
            bonusAttributes.Push("Shiny")
        if (InStr(haystack, "sparkling"))
            bonusAttributes.Push("Sparkling")
    } catch {
    }

    return bonusAttributes
}

JoinAppraiseList(items) {
    out := ""
    for item in items {
        if (out != "")
            out .= ", "
        out .= item
    }
    return out
}

ReadCurrentAppraiseCoins() {
    playerGui := FindPlayerGui()
    if (!playerGui)
        return ""

    hud := FindChildByName(playerGui, "hud")
    if (!hud)
        return ""

    safezone := FindChildByName(hud, "safezone")
    if (!safezone)
        return ""

    coins := FindChildByName(safezone, "coins")
    if (!coins)
        return ""

    return ParseAppraiseCoinsText(ReadGuiText(coins))
}

ParseAppraiseCoinsText(text) {
    digits := RegExReplace(text, "\D")
    if (digits = "")
        return ""

    return digits + 0
}

FormatAppraiseCoins(value) {
    value := Round(value + 0)
    sign := value < 0 ? "-" : ""
    digits := "" Abs(value)
    out := ""

    while (StrLen(digits) > 3) {
        out := "," SubStr(digits, StrLen(digits) - 2, 3) out
        digits := SubStr(digits, 1, StrLen(digits) - 3)
    }

    return sign digits out
}

ClickAppraisePoint() {
    global MAIN

    ReliableScreenClick(
        Round(MAIN["auto_appraise_click_x"] + 0),
        Round(MAIN["auto_appraise_click_y"] + 0)
    )
}

ReliableScreenClick(x, y, wigglePixels := 3, stepDelayMs := 15) {
    previousMode := A_CoordModeMouse
    CoordMode("Mouse", "Screen")

    x := Round(x + 0)
    y := Round(y + 0)
    wigglePixels := Max(1, Round(wigglePixels + 0))
    stepDelayMs := Max(0, Round(stepDelayMs + 0))

    try {
        MouseMove(x, y, 0)
        Sleep(stepDelayMs)
        MouseMove(x + wigglePixels, y, 0)
        Sleep(stepDelayMs)
        MouseMove(x - wigglePixels, y, 0)
        Sleep(stepDelayMs)
        MouseMove(x, y + wigglePixels, 0)
        Sleep(stepDelayMs)
        MouseMove(x, y - wigglePixels, 0)
        Sleep(stepDelayMs)
        MouseMove(x, y, 0)
        Sleep(stepDelayMs)
        Click()
    } finally {
        CoordMode("Mouse", previousMode)
    }
}

CompleteAppraiseCycle(status) {
    global Macro

    Macro.appraiseEndCoins := ReadCurrentAppraiseCoins()
    Macro.cycleEnabled := false
    Macro.appraiseState := "DONE"
    Macro.phase := "DONE"
    SetAppraiseStatus(status)
    SendAppraiseFinishedWebhook(true, status)
    UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")
}

FailAppraiseCycle(message) {
    global Macro

    Macro.appraiseEndCoins := ReadCurrentAppraiseCoins()
    Macro.cycleEnabled := false
    Macro.appraiseState := "FAILED"
    Macro.appraiseLastError := message
    Macro.phase := "FAILED"
    SetAppraiseStatus(message)
    SendAppraiseFinishedWebhook(false, message)
    UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")
}

SendAppraiseFinishedWebhook(success, message) {
    global Macro, MAIN

    desiredMutation := MAIN.Has("auto_appraise_mutation") ? Trim(MAIN["auto_appraise_mutation"]) : "---"

    lines := [
        "**Desired Mutation:** " (desiredMutation != "" ? desiredMutation : "---"),
        "**Result:** " message
    ]

    if (Macro.appraiseStartCoins != "" && Macro.appraiseEndCoins != "") {
        spent := Macro.appraiseStartCoins - Macro.appraiseEndCoins
        lines.Push("**C$ Spent:** " FormatAppraiseCoins(Max(0, spent)) " C$")
    }

    if (success) {
        bonusAttributes := GetCurrentAppraiseBonusAttributes()
        if (bonusAttributes.Length > 0)
            lines.Push("**Bonus Attributes:** " JoinAppraiseList(bonusAttributes))
    }

    title := success ? "Appraisal Finished" : "Appraisal Failed"
    SendInstantAlert(title, JoinLines(lines), GetWebhookAccentColor())
}

SetAppraiseStatus(message) {
    global AppraiseStatusText

    if (IsSet(AppraiseStatusText) && AppraiseStatusText)
        AppraiseStatusText.Value := "Status: " message
}


LoadSettings() {
    settingsPath := APPDATA_DIR "\settings.json"

    if (!FileExist(settingsPath)) {
        defaults := GetDefaultSettings()
        _WriteSettingsFile(settingsPath, defaults)
        return defaults
    }

    try {
        jsonData := FileRead(settingsPath)
        settings := JSON.parse(jsonData)
        changed := false

        if (!settings.Has("custom_theme")) {
            settings["custom_theme"] := settings["appearance"].Clone()
            changed := true
        }

        if (!settings.Has("last_migrated_version")) {
            settings["last_migrated_version"] := ""
            changed := true
        }

        defaultMain := GetDefaultSettings()["main"]
        for key, val in defaultMain {
            if (!settings["main"].Has(key)) {
                settings["main"][key] := val
                changed := true
            }
        }

        if (PruneObsoleteMainSettings(settings["main"]))
            changed := true

        if (NormalizeMainSettings(settings["main"]))
            changed := true

        if (settings.Has("hotkeys") && !settings["hotkeys"].Has("stop_appraise")) {
            fixKey    := settings["hotkeys"].Has("fix_roblox") ? settings["hotkeys"]["fix_roblox"] : "F3"
            reloadKey := settings["hotkeys"].Has("reload")     ? settings["hotkeys"]["reload"]     : "F4"
            if (fixKey = "F2") {
                settings["hotkeys"]["fix_roblox"] := "F3"
                if (reloadKey = "F3")
                    settings["hotkeys"]["reload"] := "F4"
            }
            settings["hotkeys"]["stop_appraise"] := "F2"
            changed := true
        }

        if (changed)
            _WriteSettingsFile(settingsPath, settings)

        return settings
    } catch as err {
        throw Error("Failed to load settings: " err.Message)
    }
}

GetDefaultSettings() {
    defaults := Map()

    defaults["appearance"] := Map(
        "accent_color", "5aa9ff",
        "bg_color", "0f1115",
        "border_color", "2a2f3a",
        "text_color", "f5f7fa"
    )

    defaults["env"] := "prod"

    defaults["hotkeys"] := Map(
        "start_macro", "F1",
        "stop_appraise", "F2",
        "fix_roblox", "F3",
        "reload", "F4"
    )

    defaults["main"] := Map(
                "close_threshold", 0.01,
        "derivative_gain", 0.55,
        "edge_boundary", 0.1,
        "neutral_duty_cycle", 0.5,
        "prediction_strength", 7.5,
        "proportional_gain", 0.42,
        "resilience", 0.0,
        "update_rate", 21,
        "velocity_damping", 38,
        "cast_mode", "short",
        "cast_power_custom", 96.0,
        "cast_timeout_ms", 15000,
        "pre_cast_delay_ms", 0,
        "post_cast_delay_ms", 150,
        "cast_on_timeout", 1,
        "fishing_action_delay_ms", 0,
        "completion_threshold", 99.7,
        "shake_interval_ms", 25,
        "auto_appraise_mutation", "Mythical",
                "appraise_delay_ms", 100,
        "auto_appraise_click_x", "",
        "auto_appraise_click_y", "",
        "auto_totem_enabled", 0,
                "public_server_enabled", 0,
        "auto_totem_name", "Aurora Totem",
        "auto_totem_mode", "expire",
        "auto_totem_interval_sec", 900,
        "webhook_url", "",
        "webhook_enabled", 0,
        "webhook_summary_interval_min", 30,
        "webhook_summary_fish", 1,
        "webhook_summary_success_rate", 1,
        "webhook_summary_rod", 1,
        "webhook_summary_config", 1,
        "webhook_summary_totem_state", 1,
        "webhook_summary_totem_pops", 1,
        "webhook_summary_session_time", 1,
        "webhook_summary_cast_timeouts", 1,
        "webhook_alert_totem_failed", 1
    )

    defaults["last_config"] := ""
    defaults["last_migrated_version"] := ""
    defaults["last_theme"] := "Default"
    defaults["custom_theme"] := Map(
        "accent_color", "5aa9ff",
        "bg_color", "0f1115",
        "text_color", "f5f7fa",
        "border_color", "2a2f3a"
    )


    return defaults
}

GetObsoleteMainSettings() {
    return [
        "fishing_end_grace_ms",
        "post_catch_delay_ms",
        "post_totem_delay_ms",
        "auto_appraise_max_cash",
        "auto_appraise_click_delay_ms",
        "auto_appraise_check_delay_ms",
        "auto_appraise_retry_delay_ms",
        "auto_appraise_enabled"
    ]
}

GetMinCastTimeoutMs() {
    return 5000
}

PruneObsoleteMainSettings(mainSettings) {
    changed := false

    for _, key in GetObsoleteMainSettings() {
        if (mainSettings.Has(key)) {
            mainSettings.Delete(key)
            changed := true
        }
    }

    return changed
}

NormalizeMainSettings(mainSettings) {
    changed := false

    if (mainSettings.Has("cast_timeout_ms") && IsNumber(mainSettings["cast_timeout_ms"])) {
        normalized := Max(GetMinCastTimeoutMs(), Round(mainSettings["cast_timeout_ms"] + 0))
        if (normalized != mainSettings["cast_timeout_ms"]) {
            mainSettings["cast_timeout_ms"] := normalized
            changed := true
        }
    }

    if (mainSettings.Has("auto_appraise_mutation")) {
        normalized := Trim(mainSettings["auto_appraise_mutation"])
        if (normalized = "")
            normalized := "Mythical"
        if (normalized != mainSettings["auto_appraise_mutation"]) {
            mainSettings["auto_appraise_mutation"] := normalized
            changed := true
        }
    }

    for _, key in ["auto_appraise_click_x", "auto_appraise_click_y"] {
        if (!mainSettings.Has(key))
            continue

        value := Trim(mainSettings[key])
        normalized := (value != "" && IsNumber(value)) ? Round(value + 0) : ""
        if (normalized != mainSettings[key]) {
            mainSettings[key] := normalized
            changed := true
        }
    }

    return changed
}

_WriteSettingsFile(path, data) {
    dir := RegExReplace(path, "\\[^\\]+$")
    if (!DirExist(dir))
        DirCreate(dir)

    try {
        file := FileOpen(path, "w")
        file.Write(JSON.stringify(data, 4))
        file.Close()
    } catch as err {
        throw Error("Failed to write settings file: " err.Message)
    }
}

GetBuiltInThemes() {
    themes := Map()

    themes["Default"] := Map(
        "accent_color", "5aa9ff",
        "bg_color", "0f1115",
        "text_color", "f5f7fa",
        "border_color", "2a2f3a"
    )

    themes["Crimson"] := Map(
        "accent_color", "ff4c4c",
        "bg_color", "1a0a0a",
        "text_color", "f5e6e6",
        "border_color", "3a1f1f"
    )

    themes["Emerald"] := Map(
        "accent_color", "3ddfa0",
        "bg_color", "0a1512",
        "text_color", "e6f5ef",
        "border_color", "1f3a2d"
    )

    themes["Amber"] := Map(
        "accent_color", "ffb347",
        "bg_color", "15120a",
        "text_color", "f5f0e6",
        "border_color", "3a331f"
    )

    themes["Lavender"] := Map(
        "accent_color", "b388ff",
        "bg_color", "120e18",
        "text_color", "ede6f5",
        "border_color", "2d1f3a"
    )

    themes["Arctic"] := Map(
        "accent_color", "88cfff",
        "bg_color", "e8edf2",
        "text_color", "1a1e24",
        "border_color", "c0c8d4"
    )

    themes["Slate"] := Map(
        "accent_color", "78909c",
        "bg_color", "1e272e",
        "text_color", "cfd8dc",
        "border_color", "37474f"
    )

    return themes
}


ClearMacroPhaseCache() {
    global Macro
    Macro.reelGuiAddr := 0
    Macro.reelBarAddr := 0
    Macro.fishAddr := 0
    Macro.playerbarAddr := 0
    Macro.progressBarAddr := 0
    Macro.powerBarAddr := 0
    Macro.appraiseSubvaluesAddr := 0
    Macro.appraiseState := "IDLE"
    Macro.appraiseLastClickAt := 0
    Macro.appraiseWaitStartedAt := 0
    Macro.appraiseStartCoins := ""
    Macro.appraiseEndCoins := ""
    Macro.appraiseLastError := ""
}

CreateFishingMacro() {
    return {
        phase: "OFF",
        powerPercent: "",
        progressPercent: "",
        isHolding: false,
        castThreshold: 96.0,
        castWaitTimeoutMs: 15000,
        fishingEndGraceMs: 100,
        castStartedAt: 0,
        castReleasedAt: 0,
        castBarSeen: false,
        fishingLostAt: 0,
        completionReached: false,
        outcomeResolved: false,
        fishCaughtCount: 0,
        fishLostCount: 0,
        castTimeoutCount: 0,
        totemPopCount: 0,
        shakingIntervalMs: 25,
        lastShakedAt: 0,
        lastActionAt: 0,
        ActivatedUiNav: false,
        cycleEnabled: false,
        totemState: "IDLE",
        totemRetryCount: 0,
        totemWaitStartedAt: 0,
        lastTotemSuccessAt: 0,
        lastTotemAttemptAt: 0,
        totemPending: false,
        totemBlockedUntilCatchEnd: false,
        totemNightCovered: false,
        totemNeedsRodReequip: false,
        totemNeedsSettleDelay: false,
        reelGuiAddr: 0,
        reelBarAddr: 0,
        fishAddr: 0,
        playerbarAddr: 0,
        progressBarAddr: 0,
        powerBarAddr: 0,
        appraiseSubvaluesAddr: 0,
        appraiseLastClickAt: 0,
        appraiseWaitStartedAt: 0,
        appraiseStartCoins: "",
        appraiseEndCoins: "",
        appraiseState: "IDLE",
        appraiseLastError: ""
    }
}

ResolveCastThreshold() {
    global MAIN
    switch MAIN["cast_mode"] {
        case "short":  return 28.0
        case "custom": return Max(1.0, Min(100.0, MAIN["cast_power_custom"] + 0.0))
        default:       return 96.0
    }
}

InitializeCastCycle() {
    global Macro, MAIN

    if (!Macro.ActivatedUiNav) {
        SendInput("\")
        Macro.ActivatedUiNav := true
        Sleep(50)
    }

    Macro.powerPercent := ""
    Macro.progressPercent := ""
    Macro.castStartedAt := A_TickCount
    Macro.castReleasedAt := 0
    Macro.castBarSeen := false
    Macro.fishingLostAt := 0
    Macro.completionReached := false
    Macro.outcomeResolved := false
    Macro.lastShakedAt := 0
    Macro.lastActionAt := 0
    Macro.powerBarAddr := 0
    Macro.castThreshold := ResolveCastThreshold()
    Macro.castWaitTimeoutMs := Max(GetMinCastTimeoutMs(), MAIN["cast_timeout_ms"] + 0)
    Macro.fishingEndGraceMs := 100
    Macro.shakingIntervalMs := MAIN["shake_interval_ms"]
    Macro.phase := "CASTING"

    UpdateMacroStatus("CASTING", "---", "---")
}

MacroLoop() {
    global Macro

    if (Macro.phase != "APPRAISE" && UpdateAutoTotem()) {
        UpdateMacroStatus(GetMacroDisplayStatus(), "---", "---")
        return
    }

    switch Macro.phase {
        case "CASTING":
            UpdateCastingPhase()
        case "CASTED":
            UpdateCastedPhase()
        case "SHAKE":
            UpdateShakePhase()
        case "FISHING":
            UpdateFishingPhase()
        case "TRANQUILITY":
            UpdateTranquilityPhase()
        case "DONE":
            if (Macro.cycleEnabled)
                StartMacroCycle()
            else
                StopMacroCycle("OFF")
        case "APPRAISE":
            UpdateAppraisePhase()
        case "OFF":
    }

    UpdateMacroStatus(
        GetMacroDisplayStatus(),
        (Macro.powerPercent = "" ? "---" : Macro.powerPercent "%"),
        (Macro.progressPercent = "" ? "---" : Macro.progressPercent "%")
    )

    if (Macro.phase != "OFF")
        SendSummaryWebhook()
}

StartMacroCycle() {
    global Macro, Controller, ROD, WebhookSession, Dreambreaker

    if (Macro.phase = "OFF") {
        Macro.totemNightCovered := false
        Macro.totemPending := false
        Macro.totemBlockedUntilCatchEnd := false

        if (WebhookSession.startedAt = 0) {
            WebhookSession.startedAt := A_TickCount
            WebhookSession.lastSummaryAt := A_TickCount
        }
    }

    if (IsTranquilityRodText(ROD))
        Controller := TranquilityController()
    else if (IsPinionRodText(ROD))
        Controller := PinionController()
    else
        Controller := FishingController()
        Dreambreaker := IsDreambreakerRodText(ROD)
    ReleaseMouse()
    Controller.Reset()
    InitializeCastCycle()
}

StopMacroCycle(nextPhase := "OFF") {
    global Macro, Controller

    finalProgress := Macro.progressPercent

    ReleaseMouse()
    Controller.Reset()

    Macro.powerPercent := ""
    Macro.castStartedAt := 0
    Macro.castReleasedAt := 0
    Macro.castBarSeen := false
    Macro.progressPercent := ""
    Macro.fishingLostAt := 0
    Macro.completionReached := false
    Macro.outcomeResolved := false
    Macro.lastShakedAt := 0
    Macro.lastActionAt := 0
    Macro.reelGuiAddr := 0
    Macro.reelBarAddr := 0
    Macro.fishAddr := 0
    Macro.playerbarAddr := 0
    Macro.progressBarAddr := 0
    if (nextPhase = "OFF")
        ClearAppraiseRuntimeCache()
    Macro.phase := nextPhase

    if (nextPhase = "DONE")
        Macro.totemBlockedUntilCatchEnd := false
    else if (nextPhase = "OFF") {
        if (Macro.totemState != "IDLE" && Macro.totemNeedsRodReequip)
            SelectHotbarSlot("1")
        ResetAutoTotemControl()
        Macro.totemNightCovered := false
    }

    UpdateMacroStatus(
        GetMacroDisplayStatus(),
        "---",
        (nextPhase = "DONE" && finalProgress != "" ? finalProgress "%" : "---")
    )
}

GetMacroDisplayStatus() {
    global Macro
    if (Macro.phase = "APPRAISE")
        return "APPRAISE " Macro.appraiseState
    return (Macro.totemState != "IDLE") ? Macro.totemState : Macro.phase
}

CancelTotem() {
    global Macro

    needsRodReequip := Macro.totemNeedsRodReequip

    ResetAutoTotemControl()

    Macro.lastTotemAttemptAt := A_TickCount
    Macro.totemBlockedUntilCatchEnd := true

    if (needsRodReequip)
        EnsureRodEquipped()
}


ResetAutoTotemControl() {
    global Macro

    Macro.totemState := "IDLE"
    Macro.totemRetryCount := 0
    Macro.totemWaitStartedAt := 0
    Macro.totemPending := false
    Macro.totemBlockedUntilCatchEnd := false
    Macro.totemNeedsRodReequip := false
    Macro.totemNeedsSettleDelay := false
}

IsAutoTotemRuntimeEnabled() {
    global MAIN
    return MAIN["auto_totem_enabled"] && (MAIN["auto_totem_name"] = "Aurora Totem")
}

IsPublicServerEnabled() {
    global MAIN
    return MAIN["public_server_enabled"]
}

GetAutoTotemIntervalMs() {
    global MAIN
    return Max(1, MAIN["auto_totem_interval_sec"] + 0) * 1000
}

GetCycleStartDelayMs() {
    global MAIN
    return Max(0, MAIN["pre_cast_delay_ms"] + 0)
}

IsAutoTotemBoundary() {
    global Macro
    return (Macro.phase = "CASTING" && !Macro.isHolding && !Macro.castBarSeen)
}

IsAutoTotemDue() {
    global MAIN, Macro

    if !IsAutoTotemRuntimeEnabled()
        return false

    if (MAIN["auto_totem_mode"] = "interval") {
        referenceAt := Macro.lastTotemSuccessAt
        if (Macro.lastTotemAttemptAt > referenceAt)
            referenceAt := Macro.lastTotemAttemptAt

        return (!referenceAt || (A_TickCount - referenceAt) >= GetAutoTotemIntervalMs())
    }

    if (Macro.totemNightCovered) {
        cycleText := StrLower(GetCurrentCycle())
        if (cycleText = "" || InStr(cycleText, "night"))
            return false

        Macro.totemNightCovered := false
    }

    return true
}

UpdateAutoTotem() {
    global Macro, Controller

    if !IsAutoTotemRuntimeEnabled() {
        if (Macro.totemState != "IDLE" || Macro.totemPending || Macro.totemBlockedUntilCatchEnd) {
            ReleaseMouse()
            Controller.Reset()
            if (Macro.totemState != "IDLE" && Macro.totemNeedsRodReequip)
                SelectHotbarSlot("1")
            ResetAutoTotemControl()
        }
        return false
    }
        
    if (IsPublicServerEnabled() && IsTotemBlocked()) {
        if (Macro.totemState != "IDLE" || Macro.totemPending)
            CancelTotem()

        return false
    }

    if (Macro.totemState != "IDLE") {
        Macro.powerPercent := ""
        Macro.progressPercent := ""
        ReleaseMouse()
        Controller.Reset()
        UpdateAutoTotemState()
        return true
    }

    if !Macro.cycleEnabled
        return false

    if (Macro.totemPending && IsAutoTotemBoundary()) {
        BeginAutoTotemWorkflow()
        return true
    }

    if (Macro.totemBlockedUntilCatchEnd)
        return false

    if (IsAutoTotemDue()) {
        if (IsAutoTotemBoundary()) {
            BeginAutoTotemWorkflow()
            return true
        }

        if !Macro.totemPending {
            if (Macro.phase != "OFF")
                Macro.totemNeedsSettleDelay := true
        }

        Macro.totemPending := true
    }

    return false
}

BeginAutoTotemWorkflow() {
    global Macro, Controller

    Macro.powerPercent := ""
    Macro.progressPercent := ""
    Macro.totemPending := false
    Macro.totemRetryCount := 0
    Macro.totemWaitStartedAt := 0
    Macro.lastTotemAttemptAt := A_TickCount
    Macro.totemNeedsRodReequip := false

    ReleaseMouse()
    Controller.Reset()
    if (Macro.totemNeedsSettleDelay) {
        Macro.totemState := "TOTEM_SETTLE"
        Macro.totemWaitStartedAt := A_TickCount
        return
    }

    RunAutoTotemWorkflowStep()
}

RunAutoTotemWorkflowStep() {
    global Macro
        
        if(IsPublicServerEnabled() && IsTotemBlocked()){
                CancelTotem()
                return
        }

    if (IsAuroraActive()) {
        CompleteAutoTotemWorkflow(true)
        return
    }

    if (IsNightCycle()) {
        if (!TryUseAutoTotemItem("Aurora Totem")) {
            CompleteAutoTotemWorkflow(false)
            return
        }

        Macro.totemState := "TOTEM_WAIT_AURORA"
        Macro.totemWaitStartedAt := A_TickCount
        return
    }
        
        if (!TryUseAutoTotemItem("Sundial Totem")) {
                CompleteAutoTotemWorkflow(false)
                return
        }

        Macro.totemState := "TOTEM_WAIT_NIGHT"
        Macro.totemWaitStartedAt := A_TickCount
}

UpdateAutoTotemState() {
    global Macro
        
        if(IsPublicServerEnabled() && IsTotemBlocked()){
                CancelTotem()
                return
        }

    if (IsAuroraActive()) {
        CompleteAutoTotemWorkflow(true)
        return
    }

    switch Macro.totemState {
        case "TOTEM_SETTLE":
            if ((A_TickCount - Macro.totemWaitStartedAt) < GetCycleStartDelayMs())
                return

            Macro.totemNeedsSettleDelay := false
            Macro.totemWaitStartedAt := 0
            RunAutoTotemWorkflowStep()
            return

                case "TOTEM_WAIT_NIGHT":
                        if (IsNightCycle()) {
                                Macro.totemRetryCount := 0

                                if (!TryUseAutoTotemItem("Aurora Totem")) {
                                        CompleteAutoTotemWorkflow(false)
                                        return
                                }

                                Macro.totemState := "TOTEM_WAIT_AURORA"
                                Macro.totemWaitStartedAt := A_TickCount
                                return
                        }

                        if ((A_TickCount - Macro.totemWaitStartedAt) < GetAutoTotemWaitMs())
                                return

                        if (Macro.totemRetryCount >= 1) {
                                CompleteAutoTotemWorkflow(false)
                                return
                        }

                        if (!TryUseAutoTotemItem("Sundial Totem")) {
                                CompleteAutoTotemWorkflow(false)
                                return
                        }

                        Macro.totemRetryCount += 1
                        Macro.totemWaitStartedAt := A_TickCount

        case "TOTEM_WAIT_AURORA":
            if ((A_TickCount - Macro.totemWaitStartedAt) < GetAutoTotemWaitMs())
                return

            if (Macro.totemRetryCount >= 1) {
                CompleteAutoTotemWorkflow(false)
                return
            }

            if (!TryUseAutoTotemItem("Aurora Totem")) {
                CompleteAutoTotemWorkflow(false)
                return
            }

            Macro.totemRetryCount += 1
            Macro.totemWaitStartedAt := A_TickCount
    }
}

TryUseAutoTotemItem(itemName) {
    global Macro

    if !TryUseHotbarItem(itemName)
        return false

    Macro.totemNeedsRodReequip := true
    return true
}

CompleteAutoTotemWorkflow(success := false) {
    global Macro, MAIN

    needsRodReequip := Macro.totemNeedsRodReequip

    if (success) {
        Macro.lastTotemSuccessAt := A_TickCount
        Macro.totemNightCovered := true
        Macro.totemPopCount += 1
    } else if (MAIN["webhook_alert_totem_failed"]) {
        SendInstantAlert("Auto Totem Failed", "The auto totem workflow could not complete successfully.")
    }

    ResetAutoTotemControl()

    if (needsRodReequip)
        EnsureRodEquipped()

    if (!success && MAIN["auto_totem_mode"] = "expire")
        Macro.totemBlockedUntilCatchEnd := true

    if (Macro.cycleEnabled && Macro.phase = "CASTING") {
        InitializeCastCycle()
    }
}

UpdateCastingPhase() {
    global Macro, MAIN

    Macro.progressPercent := ""

    cycleStartDelayMs := GetCycleStartDelayMs()
    if (cycleStartDelayMs > 0 && (A_TickCount - Macro.castStartedAt) < cycleStartDelayMs)
        return

    HoldMouse()

    if (!Macro.castStartedAt)
        Macro.castStartedAt := A_TickCount

    resolved := ResolvePowerBarPath()
    if (!resolved.bar) {
        Macro.powerPercent := "---"

                if ((A_TickCount - Macro.castStartedAt) >= Macro.castWaitTimeoutMs) {
                        Macro.castTimeoutCount += 1
                        ; This should solve the problem of the macro stopping if a nuke is caught
                        ; No im not making an actual fix
                        if MAIN["cast_on_timeout"] {
                                EnsureRodEquipped()
                                StartMacroCycle()
                        } else {
                                StopMacroCycle("OFF")
                        }
                }

        return
    }

    Macro.castBarSeen := true

    percent := ReadPowerBarPercent(resolved.bar)
    Macro.powerPercent := Format("{:.1f}", percent)

    if (percent >= Macro.castThreshold) {
        ReleaseMouse()
        Macro.castReleasedAt := A_TickCount
        Macro.phase := "CASTED"
        return
    }

    if ((A_TickCount - Macro.castStartedAt) >= Macro.castWaitTimeoutMs) {
        Macro.castTimeoutCount += 1
        MAIN["cast_on_timeout"] ? StartMacroCycle() : StopMacroCycle("OFF")
    }
}

UpdateCastedPhase() {
    global Macro, MAIN

    Macro.powerPercent := ""
    Macro.progressPercent := ""
    ReleaseMouse()

    if (!Macro.castReleasedAt)
        Macro.castReleasedAt := A_TickCount

    if ((A_TickCount - Macro.castReleasedAt) < MAIN["post_cast_delay_ms"])
        return

    Macro.lastShakedAt := 0
    Macro.phase := "SHAKE"
}

UpdateShakePhase() {
    global Macro, ROD

    Macro.powerPercent := ""
    Macro.progressPercent := ""
    ReleaseMouse()

    if (IsTranquilityRodText(ROD) && GetTranquilityLaneContainer()) {
        Macro.lastShakedAt := 0
        Macro.fishingLostAt := 0
        Macro.phase := "TRANQUILITY"
        return
    }

    if (HasActiveFishingContext()) {
        Macro.lastShakedAt := 0
        Macro.fishingLostAt := 0
        Macro.phase := "FISHING"
        return
    }

    if (!Macro.lastShakedAt || (A_TickCount - Macro.lastShakedAt) >= Macro.shakingIntervalMs) {
        SendInput("{Enter}")
        Macro.lastShakedAt := A_TickCount
    }

    if (Macro.castReleasedAt && (A_TickCount - Macro.castReleasedAt) >= Macro.castWaitTimeoutMs)
        StartMacroCycle()
}

UpdateFishingPhase() {
    global Macro, Controller, MAIN

    Macro.powerPercent := ""

    reelGuiVisible := IsReelGuiVisible()
    ctx := reelGuiVisible ? GetReelBarContext() : 0

    progress := GetFishingCompletionPercent()
    Macro.progressPercent := (progress = "" ? "" : Round(progress))

    if (progress != "" && progress >= (MAIN["completion_threshold"] + 0.0))
        Macro.completionReached := true

    if (Macro.completionReached) {
        ReleaseMouse(true)
        Controller.Reset()

        if (reelGuiVisible) {
            Macro.fishingLostAt := 0
            return
        }

        ctx := 0
    }

    if (ctx) {
        Macro.fishingLostAt := 0

        if (HasActiveFishingContext(ctx))
            Controller.Update(ctx)
        else
            ReleaseMouse()
        return
    }

    ReleaseMouse()
    Controller.Reset()

    if (!Macro.fishingLostAt)
        Macro.fishingLostAt := A_TickCount

    if ((A_TickCount - Macro.fishingLostAt) >= Macro.fishingEndGraceMs) {
        if (!Macro.outcomeResolved) {
            Macro.outcomeResolved := true
            if (Macro.completionReached)
                Macro.fishCaughtCount += 1
            else
                Macro.fishLostCount += 1
        }
        StopMacroCycle("DONE")
    }
}

UpdateTranquilityPhase() {
    global Macro, Controller, MAIN

    Macro.powerPercent := ""

    root := GetTranquilityRoot()
    progress := ReadTranquilityProgressPercent(root)
    Macro.progressPercent := (progress = "" ? "" : Round(progress))

    if (progress != "" && progress >= (MAIN["completion_threshold"] + 0.0))
        Macro.completionReached := true

    container := root ? GetTranquilityLaneContainer(root) : 0

    if (container) {
        Macro.fishingLostAt := 0
        Controller.Update()
        return
    }

    if (!Macro.fishingLostAt)
        Macro.fishingLostAt := A_TickCount

    if ((A_TickCount - Macro.fishingLostAt) >= Macro.fishingEndGraceMs) {
        if (!Macro.outcomeResolved) {
            Macro.outcomeResolved := true
            if (Macro.completionReached)
                Macro.fishCaughtCount += 1
            else
                Macro.fishLostCount += 1
        }
        StopMacroCycle("DONE")
    }
}

HoldMouse() {
    global Macro, MAIN

    if (Macro.isHolding)
        return

    delay := MAIN["fishing_action_delay_ms"] + 0
    if (Macro.phase = "FISHING" && delay > 0 && Macro.lastActionAt && (A_TickCount - Macro.lastActionAt) < delay)
        return

    Send("{LButton down}")
    Macro.isHolding := true
    Macro.lastActionAt := A_TickCount
}

ReleaseMouse(force := false) {
    global Macro, MAIN

    if (!Macro.isHolding)
        return

    delay := MAIN["fishing_action_delay_ms"] + 0
    if (!force && Macro.phase = "FISHING" && delay > 0 && Macro.lastActionAt && (A_TickCount - Macro.lastActionAt) < delay)
        return

    Send("{LButton up}")
    Macro.isHolding := false
    Macro.lastActionAt := A_TickCount
}

ReadFramePosition(frameAddr) {
    global OFFSETS

    base := OFFSETS["FramePositionX"] + 0
    scaleX := ReadFloat(frameAddr + base + 0x0)
    offsetX := ReadInt(frameAddr + base + 0x4)

    return {
        X: scaleX,
        XOffset: offsetX
    }
}

ReadFrameSize(frameAddr) {
    global OFFSETS

    base := OFFSETS["FrameSizeX"] + 0
    scaleX := ReadFloat(frameAddr + base + 0x0)
    offsetX := ReadInt(frameAddr + base + 0x4)

    return {
        X: scaleX,
        XOffset: offsetX
    }
}

GetReelGui() {
    playerGui := FindPlayerGui()
    if (!playerGui)
        return 0

    return FindChildByName(playerGui, "reel")
}

GetTranquilityGui() {
    playerGui := FindPlayerGui()
    if (!playerGui)
        return 0

    return FindChildByName(playerGui, "TranquilityRodRhythmGame")
}

GetTranquilityRoot(gui := 0) {
    gui := gui ? gui : GetTranquilityGui()
    return gui ? FindChildByName(gui, "RhythmGame") : 0
}

GetTranquilityLaneContainer(root := 0) {
    root := root ? root : GetTranquilityRoot()
    return root ? FindChildByName(root, "LaneContainer") : 0
}

GetTranquilityLane(index, container := 0) {
    container := container ? container : GetTranquilityLaneContainer()
    return container ? FindChildByName(container, "Lane" index) : 0
}

GetTranquilityHealthFill(root := 0) {
    root := root ? root : GetTranquilityRoot()
    if (!root)
        return 0

    healthBar := FindChildByName(root, "HealthBar")
    return healthBar ? FindChildByName(healthBar, "Fill") : 0
}

ReadTranquilityProgressPercent(root := 0) {
    fill := GetTranquilityHealthFill(root)
    if (!fill)
        return ""

    return ReadProgressBarPercent(fill)
}

ReadGuiObjectVisible(instanceAddr) {
    global OFFSETS

    if (!instanceAddr)
        return false

    className := ReadClassName(instanceAddr)
    if (className = "TextLabel" && OFFSETS.Has("TextLabelVisible"))
        return ReadByte(instanceAddr + (OFFSETS["TextLabelVisible"] + 0)) ? true : false

    if OFFSETS.Has("FrameVisible")
        return ReadByte(instanceAddr + (OFFSETS["FrameVisible"] + 0)) ? true : false

    return true
}

IsReasonableGuiScale(value) {
    return value > -5.0 && value < 5.0
}

GetTranquilityLaneKey(index, root := 0, lane := 0) {
    static fallbackKeys := Map(1, "A", 2, "S", 3, "D", 4, "F")

    root := root ? root : GetTranquilityRoot()
    label := root ? FindChildByName(root, "KeyLabel" index) : 0
    if (!label && lane)
        label := FindChildByName(lane, "KeyLabel")

    if (label) {
        keyText := Trim(ReadGuiText(label))
        if (StrLen(keyText) = 1)
            return StrUpper(keyText)
    }

    return fallbackKeys.Has(index) ? fallbackKeys[index] : ""
}

IsReelGuiVisible(reelGui := 0) {
    global OFFSETS

    if (!reelGui)
        reelGui := GetReelGui()
    if (!reelGui)
        return false

    if (!OFFSETS.Has("ScreenGuiEnabled"))
        return true

    return ReadByte(reelGui + (OFFSETS["ScreenGuiEnabled"] + 0)) ? true : false
}

GetReelBarContext() {
    global Macro

    reelGui := GetReelGui()
    if (!reelGui) {
        Macro.reelBarAddr := 0
        Macro.fishAddr := 0
        Macro.playerbarAddr := 0
        Macro.progressBarAddr := 0
        return 0
    }

    if (IsCachedAddrValid(Macro.reelBarAddr, "bar") && Macro.fishAddr && Macro.playerbarAddr) {
        return {
            bar: Macro.reelBarAddr,
            fish: Macro.fishAddr,
            playerbar: Macro.playerbarAddr
        }
    }

    Macro.reelBarAddr := 0
    Macro.fishAddr := 0
    Macro.playerbarAddr := 0

    barFrame := FindChildByName(reelGui, "bar")
    if (!barFrame)
        return 0

    fishAddr := FindChildByName(barFrame, "fish")
    playerbarAddr := FindChildByName(barFrame, "playerbar")

    Macro.reelBarAddr := barFrame
    Macro.fishAddr := fishAddr
    Macro.playerbarAddr := playerbarAddr

    return {
        bar: barFrame,
        fish: fishAddr,
        playerbar: playerbarAddr
    }
}

HasActiveFishingContext(ctx := "") {
    if (ctx = "")
        ctx := GetReelBarContext()
    return (ctx && ctx.fish && ctx.playerbar) ? true : false
}

GetReelProgressContext() {
    global Macro

    reelGui := GetReelGui()
    if (!reelGui) {
        Macro.progressBarAddr := 0
        return 0
    }

    if (IsCachedAddrValid(Macro.progressBarAddr, "bar") && IsCachedAddrValid(Macro.reelBarAddr, "bar")) {
        return {
            reel: reelGui,
            controlBar: Macro.reelBarAddr,
            progress: 0,
            progressBar: Macro.progressBarAddr
        }
    }

    Macro.progressBarAddr := 0

    controlBar := IsCachedAddrValid(Macro.reelBarAddr, "bar") ? Macro.reelBarAddr : FindChildByName(reelGui, "bar")
    if (!controlBar)
        return 0

    progressFrame := FindChildByName(controlBar, "progress")
    if (!progressFrame)
        return 0

    progressBar := FindChildByName(progressFrame, "bar")
    if (!progressBar)
        return 0

    Macro.progressBarAddr := progressBar

    return {
        reel: reelGui,
        controlBar: controlBar,
        progress: progressFrame,
        progressBar: progressBar
    }
}

ReadProgressBarPercent(frameAddr) {
    size := ReadFrameSize(frameAddr)
    return Max(0.0, Min(100.0, size.X * 100.0))
}

GetFishingCompletionPercent() {
    ctx := GetReelProgressContext()
    if (!ctx || !ctx.progressBar)
        return ""

    return ReadProgressBarPercent(ctx.progressBar)
}

IsFishingCompletionReached(threshold := 99.7) {
    percent := GetFishingCompletionPercent()
    return (percent != "" && percent >= threshold)
}

IsIndicatorSafe(ctx := "") {
    if (ctx = "")
        ctx := GetReelBarContext()
    if (!ctx || !ctx.playerbar || !ctx.fish)
        return ""

    playerbarPos := ReadFramePosition(ctx.playerbar)
    playerbarSize := ReadFrameSize(ctx.playerbar)
    fishPos := ReadFramePosition(ctx.fish)
    fishSize := ReadFrameSize(ctx.fish)

    fishCenter := fishPos.X + (fishSize.X / 2)

    halfWidth := playerbarSize.X / 2
    safeZoneLeft := playerbarPos.X - halfWidth
    safeZoneRight := playerbarPos.X + halfWidth

    return (fishCenter >= safeZoneLeft && fishCenter <= safeZoneRight)
}

ResolvePowerBarPath() {
    global Macro

    if (IsCachedAddrValid(Macro.powerBarAddr, "bar"))
        return { bar: Macro.powerBarAddr }

    Macro.powerBarAddr := 0

    workspace := GetWorkspaceRoot()
    if (!workspace)
        return { bar: 0 }

    localPlayer := GetLocalPlayer()
    if (!localPlayer)
        return { bar: 0 }

    playerName := ReadInstanceName(localPlayer)
    if (playerName = "" || playerName = "<null>")
        return { bar: 0 }

    character := FindChildByName(workspace, playerName)
    if (!character)
        return { bar: 0 }

    rootPart := FindChildByName(character, "HumanoidRootPart")
    if (!rootPart)
        return { bar: 0 }

    powerGui := FindChildByName(rootPart, "power")
    if (!powerGui)
        return { bar: 0 }

    bar := FindDescendantFrameByName(powerGui, "bar")
    if (!bar)
        return { bar: 0 }

    Macro.powerBarAddr := bar
    return { bar: bar }
}

ReadPowerBarPercent(instanceAddr) {
    global OFFSETS

    base := OFFSETS["FrameSizeX"] + 0
    scaleY := ReadFloat(instanceAddr + base + 0x8)
    percent := scaleY * 100.0

    return Max(0.0, Min(100.0, percent))
}

FindDescendantFrameByName(rootAddr, targetName) {
    queue := [rootAddr]
    index := 1

    while (index <= queue.Length) {
        current := queue[index]
        index += 1

        if (ReadInstanceName(current) = targetName && ReadClassName(current) = "Frame")
            return current

        for childPtr in ReadChildren(current)
            queue.Push(childPtr)
    }

    return 0
}

ReadNotePosition(frameAddr) {
    global OFFSETS
    base := OFFSETS["FramePositionX"] + 0
    return {
        sx: ReadFloat(frameAddr + base + 0x0),
        ox: ReadInt(frameAddr + base + 0x4),
        sy: ReadFloat(frameAddr + base + 0x8),
        oy: ReadInt(frameAddr + base + 0xC)
    }
}

GetNoteContainer() {
    global Macro

    if (IsCachedAddrValid(Macro.reelBarAddr, "bar"))
        return FindChildByName(Macro.reelBarAddr, "noteContainer")

    ctx := GetReelBarContext()
    if (!ctx || !ctx.bar)
        return 0
    return FindChildByName(ctx.bar, "noteContainer")
}

; Prefer the lowest note on the screen.
; It could have checked the Y relative to the bar itself, but this was a quick and dirty modification
GetActiveNoteTarget() {
        noteContainer := GetNoteContainer()
        if (!noteContainer)
                return ""

        best := ""
        bestY := -999999.0

        for noteName in ["note1", "note2"] {
                noteAddr := FindChildByName(noteContainer, noteName)
                if (!noteAddr)
                        continue
                pos := ReadNotePosition(noteAddr)
                if (pos.sy > 0.55 || pos.sy < -30)
                        continue
                
                ;it took me a bit to end up to this, mostly because i thought there was a better way on doing this (there probably was, but this was faster)
                if (pos.sy > bestY) {
                        bestY := pos.sy
                        best := { sx: pos.sx, sy: pos.sy }
                }
        }

    return best
}

class FishingController {
    Reset() {
        for _, propName in ["lastPlayerbarPos", "lastFishPos", "pwmAccumulator"] {
            if (this.HasOwnProp(propName))
                this.DeleteProp(propName)
        }
    }

    Update(ctx := "") {
        if (ctx = "")
            ctx := GetReelBarContext()

        isSafe := IsIndicatorSafe(ctx)
        if (isSafe = "") {
            this.Release()
            return
        }

        fishPos := this.GetFishPosition(ctx)
        playerbarPos := this.GetPlayerbarPosition(ctx)

        if (fishPos = "" || playerbarPos = "")
            return

        if (!this.HasOwnProp("lastPlayerbarPos"))
            this.lastPlayerbarPos := playerbarPos

        if (!this.HasOwnProp("lastFishPos"))
            this.lastFishPos := fishPos

        playerbarVelocity := playerbarPos - this.lastPlayerbarPos
        this.lastPlayerbarPos := playerbarPos

        fishVelocity := fishPos - this.lastFishPos
        this.lastFishPos := fishPos

        error := fishPos - playerbarPos

        edgeBoundary := MAIN["edge_boundary"]
        if (playerbarPos < edgeBoundary) {
            this.Hold()
            return
        }
        if (playerbarPos > 1 - edgeBoundary) {
            this.Release()
            return
        }

        predictionScale := MAIN["prediction_strength"]
        predicted := playerbarPos + (playerbarVelocity * predictionScale)
        predictedError := fishPos - predicted

        closeThreshold := MAIN["close_threshold"]
        sameSideAfterPrediction := (error * predictedError) > 0

        approachingTarget := (error * playerbarVelocity) > 0
        remainingDistance := Max(0.0, Abs(error) - closeThreshold)

        ; full stop fixing and start bleeding speed early
        brakeLookahead := Abs(playerbarVelocity) * 8
        needsPreSlow := approachingTarget && (brakeLookahead >= remainingDistance)

        ; hard fix only when far enough and not yet in the braking zone
        if (Abs(error) > closeThreshold && sameSideAfterPrediction && !needsPreSlow) {
            if (error > 0)
                this.Hold()
            else
                this.Release()
            return
        }

        neutralDuty := MAIN["neutral_duty_cycle"]

        if (needsPreSlow && brakeLookahead > 0) {
            brakeUrgency := 1.0 - Min(1.0, remainingDistance / brakeLookahead)

            if (error > 0) {
                targetDuty := neutralDuty * (1.0 - brakeUrgency)
            } else {
                targetDuty := neutralDuty + ((1.0 - neutralDuty) * brakeUrgency)
            }
        } else {
            ; Normal pwm balancing // fine tracking
            kP := MAIN["proportional_gain"]
            kD := MAIN["derivative_gain"]
            kV := MAIN["velocity_damping"]

            adjustment := (kP * error) + (kD * fishVelocity) - (kV * playerbarVelocity)
            targetDuty := Max(0.0, Min(1.0, neutralDuty + adjustment))
        }

        if (!this.HasOwnProp("pwmAccumulator"))
            this.pwmAccumulator := 0.0

        this.pwmAccumulator += targetDuty
        if (this.pwmAccumulator >= 1.0) {
            this.pwmAccumulator -= 1.0
            this.Hold()
        } else {
            this.Release()
        }
    }

    GetFishPosition(ctx := "") {
        if (ctx = "")
            ctx := GetReelBarContext()
        if (!ctx || !ctx.fish)
            return ""

        fishPos := ReadFramePosition(ctx.fish)
        fishSize := ReadFrameSize(ctx.fish)
        return fishPos.X + (fishSize.X / 2)
    }

    GetPlayerbarPosition(ctx := "") {
        if (ctx = "")
            ctx := GetReelBarContext()
        if (!ctx || !ctx.playerbar)
            return ""

        playerbarPos := ReadFramePosition(ctx.playerbar)
        return playerbarPos.X
    }

        ; now checks in StartMacroCycle if rod matches text, should prevent constant checking
        IsInverted(){
                global Dreambreaker
                
                if(!Dreambreaker)
                        return false
                
                progress := GetFishingCompletionPercent()
                if (progress = "")
                        return false
                
                return (progress + 0.0) >= 40.0
        }

    Hold() {
                if(this.IsInverted())
                        ReleaseMouse()
                else
                        HoldMouse()
    }

    Release() {
                if(this.IsInverted())
                        HoldMouse()
                else
                        ReleaseMouse()
    }
}

IsNoteInPlayerBar(x, ctx := "", padding := 0) {
        if (ctx = "")
                ctx := GetReelBarContext()

        if (!ctx || !ctx.playerbar)
                return false

        playerbarPos := ReadFramePosition(ctx.playerbar)
        playerbarSize := ReadFrameSize(ctx.playerbar)

        halfWidth := playerbarSize.X / 2

        return (
                x >= playerbarPos.X - halfWidth - padding
                && x <= playerbarPos.X + halfWidth + padding
        )
}

class PinionController extends FishingController {
        static NOTE_DEADZONE := -16.5
        
        notesCaught := 0
        noteCounted := false
        resonanceActive := false

    Reset() {
        super.Reset()
                this.notesCaught := 0
                this.noteCounted := false
                this.resonanceActive := false
    }

        GetBothTargets(fishX, noteX, halfWidth) {
                distance := Abs(noteX - fishX)
                fullWidth := halfWidth * 2
                
                if(distance > fullWidth)
                        return ""
                
                if (distance <= halfWidth)
                        return fishX
                
                return noteX > fishX ? noteX - halfWidth : noteX + halfWidth
        }
        
        GetNoteDeadzone(playerbarX, fishX, noteX) {
                playerToNoteDistance := Abs(noteX - playerbarX)
                fishToNoteDistance := Abs(noteX - fishX)
                
                dz := PinionController.NOTE_DEADZONE - (playerToNoteDistance * 30.0) - (fishToNoteDistance * 10.0)
                
                return Max(-22, Min(PinionController.NOTE_DEADZONE, dz))
        }
        
        UpdateNoteCount(note, ctx){
                if(!this.noteCounted && note.sy >= -0.8 && note.sy <= 0.53){
                        if(IsNoteInPlayerBar(note.sx, ctx, 0.1)){
                                this.noteCounted := true
                                this.notesCaught += 1
                        }else{
                                this.notesCaught := 0
                                this.resonanceActive := false
                                this.noteCounted := true
                        }
                }
                
                if(note.sy < -8)
                        this.noteCounted := false
                        
                if (this.notesCaught >= 7)
                        this.resonanceActive := true
        }
        
    GetFishPosition(ctx := "") {
        if (ctx = "")
            ctx := GetReelBarContext()
        fishX := super.GetFishPosition(ctx)
                if (!ctx || !ctx.playerbar)
                        return fishX
                playerbarSize := ReadFrameSize(ctx.playerbar)
                halfWidth := playerbarSize.X / 2
                
                playerbarX := this.GetPlayerbarPosition(ctx)
                if (playerbarX = "")
                        return fishX

        note := GetActiveNoteTarget()
        if (note = "")
            return fishX
                        
                if (this.resonanceActive)
                        return note.sx
                        
                this.UpdateNoteCount(note, ctx)
                        
                activeDeadzone := this.GetNoteDeadzone(playerbarX, fishX, note.sx)
                if (note.sy <= activeDeadzone)
                        return fishX
                
                bothCatch := this.GetBothTargets(fishX, note.sx, halfWidth)
                if (bothCatch != "")
                        return bothCatch

                return note.sx
    }
}

class TranquilityController {
    static HIT_Y_MIN := 0.78
    static HIT_Y_MAX := 0.90
    static KEY_COOLDOWN_MS := 30

    __New() {
        this.hitNotes := Map()
        this.lastKeySentAt := Map()
    }

    Reset() {
        ReleaseMouse(true)
        this.hitNotes := Map()
        this.lastKeySentAt := Map()
    }

    Update(ctx := "") {
        ReleaseMouse(true)

        root := GetTranquilityRoot()
        if (!root)
            return

        container := GetTranquilityLaneContainer(root)
        if (!container)
            return

        seenNotes := Map()

        Loop 4 {
            lane := GetTranquilityLane(A_Index, container)
            if (!lane || !ReadGuiObjectVisible(lane))
                continue

            key := GetTranquilityLaneKey(A_Index, root, lane)
            if (key = "")
                continue

            for noteAddr in ReadChildren(lane) {
                if (ReadInstanceName(noteAddr) != "Note" || ReadClassName(noteAddr) != "ImageLabel")
                    continue

                seenNotes[noteAddr] := true
                if (this.hitNotes.Has(noteAddr) || !ReadGuiObjectVisible(noteAddr))
                    continue

                pos := ReadNotePosition(noteAddr)
                if (!IsReasonableGuiScale(pos.sy))
                    continue

                if (pos.sy >= TranquilityController.HIT_Y_MIN && pos.sy <= TranquilityController.HIT_Y_MAX)
                    this.PressLaneKey(key, noteAddr)
            }
        }

        staleNotes := []
        for noteAddr, _ in this.hitNotes {
            if (!seenNotes.Has(noteAddr))
                staleNotes.Push(noteAddr)
        }

        for _, noteAddr in staleNotes
            this.hitNotes.Delete(noteAddr)
    }

    PressLaneKey(key, noteAddr) {
        now := A_TickCount
        lastSentAt := this.lastKeySentAt.Has(key) ? this.lastKeySentAt[key] : 0
        if (lastSentAt && (now - lastSentAt) < TranquilityController.KEY_COOLDOWN_MS)
            return false

        SendInput("{" key "}")
        this.lastKeySentAt[key] := now
        this.hitNotes[noteAddr] := now
        return true
    }
}



CheckRobloxVersionMismatch(pid) {
    global _LastVersionCheckAt, VERSION_CHECK_COOLDOWN_MS

    if (!pid)
        return

    if (_LastVersionCheckAt && (A_TickCount - _LastVersionCheckAt) < VERSION_CHECK_COOLDOWN_MS)
        return

    _LastVersionCheckAt := A_TickCount

    try {
        runningHash := GetRunningRobloxVersionHash(pid)
        latestHash := GetLatestRobloxVersionHash()

        if (runningHash != latestHash)
            MsgBox("Version mismatch detected.`n`nRunning: " runningHash "`nLatest:  " latestHash, "Version Warning")
    } catch as err {
        MsgBox("Version check failed: " err.Message "`n`nProceeding with re-attach.", "Version Warning")
    }
}

StartMacro() {
    global Macro

    if (Macro.cycleEnabled) {
        Macro.cycleEnabled := false
        if (Macro.phase = "APPRAISE")
            StopAppraiseCycle("OFF")
        else
            StopMacroCycle("OFF")
        return
    }

    if !EnsureRobloxReady(true, true)
        return

    UpdateRobloxUiState()

    if (IsAutoAppraiseRuntimeEnabled()) {
        if (Macro.phase = "OFF" || Macro.phase = "DONE" || Macro.phase = "FAILED")
            StartAppraiseCycle()
        return
    }

    if (!IsAnythingEquipped()) {
        SendInput("t")
        Sleep(200)
    }

    Macro.cycleEnabled := true

    if (Macro.phase = "OFF" || Macro.phase = "DONE" || Macro.phase = "FAILED")
        StartMacroCycle()
}

FixRoblox() {
    pid := GetRobloxPID()
    if (!pid) {
        ResetRobloxAttachmentState()
        ClearMacroPhaseCache()
        UpdateRobloxUiState()
        MsgBox("Roblox not found.")
        return
    }

    ClearMacroPhaseCache()

    CheckRobloxVersionMismatch(pid)

    try {
        AttachToRoblox(pid)
        UpdateRobloxUiState()
        MsgBox("Roblox attachment refreshed.")
    } catch as err {
        UpdateRobloxUiState()
        MsgBox(err.Message, "Roblox Attachment")
    }
}

ReloadMacro() {
    Reload()
}

StopAppraisingHotkey() {
    global Macro
    if (Macro.phase = "APPRAISE" && Macro.cycleEnabled)
        StopAppraiseCycle("OFF", "Stopped by hotkey.")
}

class HotkeyManager {
    static activeHotkeys := Map()

    static RegisterAll(settings) {
        hotkeys := settings["hotkeys"]
        this.Register(hotkeys["start_macro"], (*) => StartMacro())
        if (hotkeys.Has("stop_appraise") && hotkeys["stop_appraise"] != "")
            this.Register(hotkeys["stop_appraise"], (*) => StopAppraisingHotkey())
        this.Register(hotkeys["fix_roblox"], (*) => FixRoblox())
        this.Register(hotkeys["reload"], (*) => ReloadMacro())
    }

    static Register(key, callback) {
        if (key = "")
            return

        Hotkey(key, callback)
        this.activeHotkeys[key] := callback
    }

    static ChangeHotkey(oldKey, newKey, callback) {
        if (oldKey = newKey)
            return

        if (oldKey != "" && this.activeHotkeys.Has(oldKey)) {
            Hotkey(oldKey, "Off")
            this.activeHotkeys.Delete(oldKey)
        }

        this.Register(newKey, callback)
    }
}


LoadOffsets() {
    global OFFSETS_PATH

    if (!FileExist(OFFSETS_PATH)) {
        parsed := FetchRemoteOffsets()
        if (!parsed)
            throw Error("offsets.json not found at: " OFFSETS_PATH)
        ApplyParsedOffsets(parsed)
        BackupAndWriteOffsetsFile(parsed)
        return
    }

    try {
        jsonData := FileRead(OFFSETS_PATH)
    } catch as err {
        throw Error("Failed to read offsets.json: " err.Message)
    }

    try {
        parsed := JSON.parse(jsonData)
    } catch as err {
        throw Error("JSON parsing failed: " err.Message)
    }

    ApplyParsedOffsets(parsed)
}

ApplyParsedOffsets(parsed) {
    global OFFSETS, OFFSETS_ROBLOX_VERSION

    OFFSETS_ROBLOX_VERSION := (parsed.Has("Roblox Version")) ? parsed["Roblox Version"] : ""

    if (!parsed.Has("Offsets"))
        throw Error("'Offsets' section not found in offsets.json")

    nested := parsed["Offsets"]
    flat := Map()

    for _, triple in OffsetRenameMap() {
        category := triple[1], field := triple[2], legacy := triple[3]
        if (!nested.Has(category))
            continue
        cat := nested[category]
        if (!cat.Has(field))
            continue
        flat[legacy] := cat[field]
    }

    OFFSETS := flat

    if (!OFFSETS.Has("FakeDataModelPointer")) {
        throw Error("FakeDataModelPointer not found in offsets")
    }
}

TestOffsetsInMemory() {
    global g_CachedDataModel
    g_CachedDataModel := 0

    dataModel := ResolveDataModelViaFakeDataModel()
    if (!IsValidUserPointer(dataModel))
        dataModel := ResolveDataModelViaVisualEngine()

    if (!IsValidUserPointer(dataModel))
        return false

    try {
        if (ReadClassName(dataModel) != "DataModel")
            return false
    } catch {
        return false
    }

    foundWorkspace := false
    foundPlayers := false

    try {
        for childPtr in ReadChildren(dataModel) {
            cls := ReadClassName(childPtr)
            if (cls = "Workspace")
                foundWorkspace := true
            else if (cls = "Players")
                foundPlayers := true
            if (foundWorkspace && foundPlayers)
                break
        }
    } catch {
        return false
    }

    return foundWorkspace && foundPlayers
}

TestAndHealOffsets() {
    if (TestOffsetsInMemory())
        return true

    parsed := FetchRemoteOffsets()
    if (!parsed)
        throw Error("Offsets appear stale and remote update is unreachable. Please retry once online or update offsets.json manually.")

    try {
        ApplyParsedOffsets(parsed)
    } catch as err {
        throw Error("Remote offsets could not be applied: " err.Message)
    }

    if (!TestOffsetsInMemory())
        throw Error("Remote offsets did not match the running Roblox build.")

    BackupAndWriteOffsetsFile(parsed)
    return true
}

OffsetRenameMap() {
    static map := [
        ["FakeDataModel",  "Pointer",            "FakeDataModelPointer"],
        ["FakeDataModel",  "RealDataModel",      "FakeDataModelToDataModel"],
        ["VisualEngine",   "Pointer",            "VisualEnginePointer"],
        ["VisualEngine",   "FakeDataModel",      "VisualEngineToDataModel1"],
        ["FakeDataModel",  "RealDataModel",      "VisualEngineToDataModel2"],
        ["Player",         "LocalPlayer",        "LocalPlayer"],
        ["Instance",       "Name",               "Name"],
        ["Instance",       "ClassDescriptor",    "ClassDescriptor"],
        ["Instance",       "ClassName",          "ClassDescriptorToClassName"],
        ["Instance",       "ChildrenStart",      "Children"],
        ["Instance",       "Parent",             "Parent"],
        ["Misc",           "StringLength",       "StringLength"],
        ["Misc",           "Value",              "Value"],
        ["GuiObject",      "Text",               "TextLabelText"],
        ["GuiObject",      "Visible",            "TextLabelVisible"],
        ["GuiObject",      "Visible",            "FrameVisible"],
        ["GuiObject",      "ScreenGui_Enabled",  "ScreenGuiEnabled"],
        ["GuiObject",      "Position",           "FramePositionX"],
        ["GuiObject",      "Size",               "FrameSizeX"]
    ]
    return map
}

AreOffsetsLoaded() {
    global OFFSETS
    return (OFFSETS is Map) && OFFSETS.Count && OFFSETS.Has("FakeDataModelPointer")
}

ResetRobloxAttachmentState() {
    global H_PROCESS, RBLX_PID, RBLX_BASE, OFFSETS, ROD, Macro
    global g_CachedDataModel, g_CachedLocalPlayer, g_CachedPlayerGui
    global g_CachedWorkspaceRoot, g_CachedWorldConfig, g_CachedHotbarGui

    g_CachedDataModel := 0
    g_CachedLocalPlayer := 0
    g_CachedPlayerGui := 0
    g_CachedWorkspaceRoot := 0
    g_CachedWorldConfig := 0
    g_CachedHotbarGui := 0

    if (IsSet(Macro) && Macro) {
        Macro.appraiseSubvaluesAddr := 0
        Macro.appraiseLastClickAt := 0
        Macro.appraiseWaitStartedAt := 0
        Macro.appraiseStartCoins := ""
        Macro.appraiseEndCoins := ""
        Macro.appraiseState := "IDLE"
        Macro.appraiseLastError := ""
    }

    if (H_PROCESS)
        DllCall("CloseHandle", "Ptr", H_PROCESS)
    H_PROCESS := 0
    RBLX_PID := 0
    RBLX_BASE := 0
    OFFSETS := Map()
    ROD := ""
}

IsCachedAddrValid(addr, expectedName) {
    if (!addr)
        return false

    try {
        name := ReadInstanceName(addr)
    } catch {
        return false
    }

    return (name = expectedName)
}

IsRobloxAttached() {
    global H_PROCESS, RBLX_PID, RBLX_BASE

    currentPid := GetRobloxPID()
    return (currentPid && currentPid = RBLX_PID && H_PROCESS && RBLX_BASE) ? true : false
}

IsMemoryReady() {
    return IsRobloxAttached() && AreOffsetsLoaded()
}

AttachToRoblox(pid := 0) {
    global RBLX_PID, RBLX_BASE, ROD, H_PROCESS

    pid := pid ? pid : GetRobloxPID()
    if !pid
        throw Error("Roblox is not running.")

    ResetRobloxAttachmentState()
    RBLX_PID := pid

    try {
        RBLX_BASE := GetProcessBase(pid)
        if (!RBLX_BASE)
            throw Error("Failed to attach to Roblox.")

        LoadOffsets()
        TestAndHealOffsets()
        ROD := GetHotbarRodName()
        return true
    } catch as err {
        ResetRobloxAttachmentState()
        throw Error(err.Message)
    }
}

EnsureRobloxReady(showMessage := true, attemptAttach := true) {
    currentPid := GetRobloxPID()

    if !currentPid {
        ResetRobloxAttachmentState()
        UpdateRobloxUiState()
        if showMessage
            MsgBox("Roblox is not running. Open Roblox first to use this feature.", "Roblox Not Found")
        return false
    }

    if IsMemoryReady() {
        UpdateRobloxUiState()
        return true
    }

    if !attemptAttach {
        if showMessage
            MsgBox("Roblox is not attached. Open Roblox and try again, or press Fix Roblox.", "Roblox Not Attached")
        return false
    }

    try {
        AttachToRoblox(currentPid)
        UpdateRobloxUiState()
        return true
    } catch as err {
        UpdateRobloxUiState()
        if showMessage
            MsgBox(err.Message, "Roblox Attachment")
        return false
    }
}

GetDataModel() {
    global OFFSETS, H_PROCESS, RBLX_BASE, g_CachedDataModel

    if (g_CachedDataModel)
        return g_CachedDataModel

    if (!AreOffsetsLoaded() || !H_PROCESS || !RBLX_BASE)
        return 0

    dataModel := ResolveDataModelViaFakeDataModel()
    if (!IsValidUserPointer(dataModel))
        dataModel := ResolveDataModelViaVisualEngine()

    if (IsValidUserPointer(dataModel))
        g_CachedDataModel := dataModel

    return dataModel
}

ResolveDataModelViaFakeDataModel() {
    global OFFSETS, RBLX_BASE

    if (!OFFSETS.Has("FakeDataModelPointer") || !OFFSETS.Has("FakeDataModelToDataModel"))
        return 0

    fakeDataModel := ReadPointer(RBLX_BASE + (OFFSETS["FakeDataModelPointer"] + 0))
    if (!IsValidUserPointer(fakeDataModel))
        return 0

    return ReadPointer(fakeDataModel + (OFFSETS["FakeDataModelToDataModel"] + 0))
}

ResolveDataModelViaVisualEngine() {
    global OFFSETS, RBLX_BASE

    for _, key in ["VisualEnginePointer", "VisualEngineToDataModel1", "VisualEngineToDataModel2"] {
        if (!OFFSETS.Has(key))
            return 0
    }

    visualEngine := ReadPointer(RBLX_BASE + (OFFSETS["VisualEnginePointer"] + 0))
    if (!IsValidUserPointer(visualEngine))
        return 0

    fakeDataModel := ReadPointer(visualEngine + (OFFSETS["VisualEngineToDataModel1"] + 0))
    if (!IsValidUserPointer(fakeDataModel))
        return 0

    return ReadPointer(fakeDataModel + (OFFSETS["VisualEngineToDataModel2"] + 0))
}

IsValidUserPointer(val) {
    return val && val >= 0x10000 && val <= 0x00007FFFFFFFFFFF
}

GetPlayers() {
    dataModel := GetDataModel()
    
    if !dataModel
        return 0
    
    children := ReadChildren(dataModel)
    
    for childPtr in children {
        className := ReadClassName(childPtr)
        if (className = "Players")
            return childPtr
    }
    
    return 0
}

GetLocalPlayer() {
    global OFFSETS, g_CachedLocalPlayer

    if (g_CachedLocalPlayer)
        return g_CachedLocalPlayer

    players := GetPlayers()
    if !players
        return 0

    localPlayerOffset := OFFSETS["LocalPlayer"] + 0
    localPlayer := ReadPointer(players + (localPlayerOffset))

    if (localPlayer)
        g_CachedLocalPlayer := localPlayer

    return localPlayer
}

FindPlayerGui() {
    global g_CachedPlayerGui

    if (g_CachedPlayerGui)
        return g_CachedPlayerGui

    localPlayer := GetLocalPlayer()
    if (!localPlayer)
        return 0

    children := ReadChildren(localPlayer)

    for childPtr in children {
        className := ReadClassName(childPtr)
        if (className = "PlayerGui") {
            g_CachedPlayerGui := childPtr
            return childPtr
        }
    }

    return 0
}

GetWorkspaceRoot() {
    global g_CachedWorkspaceRoot

    if (g_CachedWorkspaceRoot)
        return g_CachedWorkspaceRoot

    dataModel := GetDataModel()
    if (!dataModel)
        return 0

    for childPtr in ReadChildren(dataModel) {
        name := ReadInstanceName(childPtr)
        className := ReadClassName(childPtr)
        if (name = "Workspace" || className = "Workspace") {
            g_CachedWorkspaceRoot := childPtr
            return childPtr
        }
    }

    return 0
}

ReadPropertyString(instanceAddr, offsetKeys) {
    global OFFSETS

    for _, key in offsetKeys {
        if !OFFSETS.Has(key)
            continue

        offset := OFFSETS[key] + 0

        ptrValue := ReadPointer(instanceAddr + offset)
        if ptrValue {
            text := ReadString(ptrValue)
            if (text != "")
                return text
        }

        directValue := ReadString(instanceAddr + offset)
        if (directValue != "")
            return directValue
    }

    return ""
}

ReadGuiText(instanceAddr) {
    return ReadPropertyString(instanceAddr, ["Text", "TextLabelText", "ContentText"])
}

GetCoreGui() {
    dataModel := GetDataModel()
    if !dataModel
        return 0

    return FindChildByName(dataModel, "CoreGui")
}

GetRobloxGui() {
    coreGui := GetCoreGui()
    if !coreGui
        return 0

    return FindChildByName(coreGui, "RobloxGui")
}

GetBackpackGui() {
    robloxGui := GetRobloxGui()
    if !robloxGui
        return 0

    return FindChildByName(robloxGui, "Backpack")
}

GetHotbarGui() {
    global g_CachedHotbarGui

    if (g_CachedHotbarGui)
        return g_CachedHotbarGui

    lp := GetLocalPlayer()
    if !lp
        return 0

    pg := FindChildByClass(lp, "PlayerGui")
    if !pg
        return 0

    bp := FindChildByName(pg, "backpack")
    if !bp
        return 0

    hotbar := FindChildByName(bp, "hotbar")
    if (hotbar)
        g_CachedHotbarGui := hotbar

    return hotbar
}

GetHotbarRodName() {
    hotbar := GetHotbarGui()
    if !hotbar
        return ""

    fallback := ""

    for slotPtr in ReadChildren(hotbar) {
        if (ReadClassName(slotPtr) != "ImageButton" || ReadInstanceName(slotPtr) != "ItemTemplate")
            continue

        nameInst := FindChildByName(slotPtr, "ItemName")
        if !nameInst
            continue

        toolText := ReadGuiText(nameInst)
        pureRodName := ExtractPureRodName(toolText)
        if (pureRodName != "")
            return pureRodName

        toolText := NormalizeRodDisplayText(toolText)
        if (toolText = "")
            continue

        if (fallback = "")
            fallback := toolText
    }

    return fallback
}

GetHotbarRodDisplayText() {
    hotbar := GetHotbarGui()
    if !hotbar
        return ""

    fallback := ""

    for slotPtr in ReadChildren(hotbar) {
        if (ReadClassName(slotPtr) != "ImageButton" || ReadInstanceName(slotPtr) != "ItemTemplate")
            continue

        nameInst := FindChildByName(slotPtr, "ItemName")
        if !nameInst
            continue

        toolText := NormalizeRodDisplayText(ReadGuiText(nameInst))
        if (toolText = "")
            continue

        if (ExtractPureRodName(toolText) != "" || IsPinionRodText(toolText) || IsTranquilityRodText(toolText))
            return toolText

        if (fallback = "")
            fallback := toolText
    }

    return fallback
}

GetKnownRodNames() {
    static rodNames := [
        "Pinion's Aria",
        "Tranquility Rod",
        "Rod Of The Eternal King",
        "Rod Of The Depths",
        "Rod Of Time",
        "Flimsy Rod",
        "Training Rod",
        "Plastic Rod",
        "Steady Rod",
        "Reinforced Rod",
        "Phoenix Rod",
        "Mythical Rod",
        "No-Life Rod",
        "Sunken Rod",
        "Trident Rod",
        "Kings Rod",
        "Wisdom Rod",
        "Toxinburst Rod",
        "The Lost Rod",
        "Riptide Rod",
        "Lucid Rod",
        "Celestial Rod",
        "Seasons Rod",
        "Krampus's Rod",
        "Precision Rod",
        "Resourceful Rod",
        "Toxic Spire Rod",
        "Gardenkeeper Rod",
        "Voyager Rod",
        "Vineweaver Rod"
    ]

    return rodNames
}

NormalizeRodDisplayText(text) {
    text := StrReplace(text, "`r", "`n")
    text := RegExReplace(text, "<[^>]+>")
    text := RegExReplace(text, "[ \t]+", " ")
    text := RegExReplace(text, "\n+", "`n")
    return Trim(text)
}

IsPinionRodText(text) {
    return InStr(StrLower(NormalizeRodDisplayText(text)), "pinion") ? true : false
}

HasPinionHotbarRod() {
    return IsPinionRodText(GetHotbarRodDisplayText())
}

IsTranquilityRodText(text) {
    return InStr(StrLower(NormalizeRodDisplayText(text)), "tranquility") ? true : false
}

HasTranquilityHotbarRod() {
    return IsTranquilityRodText(GetHotbarRodDisplayText())
}

IsDreambreakerRodText(text) {
    return InStr(StrLower(NormalizeRodDisplayText(text)), "dreambreaker") ? true : false
}

HasDreambreakerHotbarRod() {
    return IsDreambreakerRodText(GetHotbarRodDisplayText())
}


ExtractPureRodName(text) {
    cleanText := NormalizeRodDisplayText(text)
    if (cleanText = "")
        return ""

    for _, rodName in GetKnownRodNames() {
        if (InStr(cleanText, rodName))
            return rodName
    }

    for _, line in StrSplit(cleanText, "`n") {
        line := Trim(line)
        if (line = "")
            continue

        if (line = "Pinion's Aria" || RegExMatch(line, "i)\brod\b"))
            return line
    }

    return ""
}



FetchRemoteOffsets() {
    global _LastRemoteFetchAt, _LastRemoteFetchResult, REMOTE_OFFSETS_CACHE_TTL_MS

    if (_LastRemoteFetchAt && (A_TickCount - _LastRemoteFetchAt) < REMOTE_OFFSETS_CACHE_TTL_MS)
        return _LastRemoteFetchResult

    _LastRemoteFetchAt := A_TickCount
    _LastRemoteFetchResult := ""

    ; Embedded offsets — no remote fetch needed
    body := "{`"Source`":`"https://offsets.imtheo.lol`",`"Roblox Version`":`"version-8884371d30284041`",`"Dumper Version`":`"2.1.7`",`"Dumped With`":`"RbxDumperV2`",`"Dumped At`":`"21:03 16/06/2026`",`"Discord`":`"https://offsets.imtheo.lol/discord`",`"Total Offsets`":390,`"Offsets`":{`"PlayerConfigurer`":{`"Pointer`":0},`"TaskScheduler`":{`"Pointer`":135644776,`"JobStart`":200,`"JobEnd`":208,`"JobName`":24,`"MaxFPS`":176},`"VisualEngine`":{`"Pointer`":137274360,`"Dimensions`":2736,`"ViewMatrix`":336,`"RenderView`":3000,`"FakeDataModel`":2704},`"FakeDataModel`":{`"Pointer`":129824424,`"RealDataModel`":472},`"MouseService`":{`"SensitivityPointer`":775,`"InputObject`":264,`"InputObject2`":280,`"MousePosition`":236},`"ScriptContext`":{`"RequireBypass`":0},`"ModuleScript`":{`"IsCoreScript`":0,`"GUID`":232,`"Hash`":352,`"ByteCode`":336},`"RenderView`":{`"LightingValid`":336,`"SkyValid`":653,`"VisualEngine`":16,`"DeviceD3D11`":8},`"Instance`":{`"This`":8,`"Name`":176,`"ChildrenStart`":120,`"ChildrenEnd`":8,`"Parent`":112,`"ClassDescriptor`":24,`"ClassName`":8,`"ClassBase`":3264,`"AttributeContainer`":72,`"AttributeList`":24,`"AttributeToNext`":88,`"AttributeToValue`":24},`"Misc`":{`"StringLength`":16,`"Adornee`":264,`"Value`":208,`"AnimationId`":216},`"MeshContentProvider`":{`"Cache`":232,`"LRUCache`":32,`"MeshData`":64,`"ToMeshData`":64,`"AssetID`":16},`"MeshData`":{`"FaceEnd`":56,`"FaceStart`":48,`"VertexEnd`":8,`"VertexStart`":0},`"DataModel`":{`"PlaceId`":424,`"GameId`":416,`"CreatorId`":408,`"GameLoaded`":1656,`"JobId`":312,`"Workspace`":376,`"ScriptContext`":1088,`"PlaceVersion`":452,`"ServerIP`":1632,`"ToRenderView1`":480,`"ToRenderView2`":8,`"ToRenderView3`":40,`"PrimitiveCount`":1192},`"RunService`":{`"HeartbeatTask`":248,`"HeartbeatFPS`":184},`"RenderJob`":{`"RenderView`":464,`"FakeDataModel`":56,`"RealDataModel`":456},`"Workspace`":{`"World`":1024,`"ReadOnlyGravity`":2536,`"DistributedGameTime`":1224,`"CurrentCamera`":1192},`"World`":{`"Gravity`":528,`"worldStepsPerSec`":1664,`"FallenPartsDestroyHeight`":520,`"AirProperties`":536,`"Primitives`":648},`"AirProperties`":{`"AirDensity`":24,`"GlobalWind`":60},`"Terrain`":{`"GrassLength`":496,`"WaterReflectance`":504,`"WaterTransparency`":508,`"WaterWaveSize`":512,`"WaterWaveSpeed`":516,`"WaterColor`":480,`"MaterialColors`":1184},`"MaterialColors`":{`"Asphalt`":48,`"Basalt`":39,`"Brick`":15,`"Cobblestone`":51,`"Concrete`":12,`"CrackedLava`":45,`"Glacier`":27,`"Grass`":6,`"Ground`":42,`"Ice`":54,`"LeafyGrass`":57,`"Limestone`":63,`"Mud`":36,`"Pavement`":66,`"Rock`":24,`"Salt`":60,`"Sand`":18,`"Sandstone`":33,`"Slate`":9,`"Snow`":30,`"WoodPlanks`":21},`"Sound`":{`"SoundId`":224,`"RollOffMaxDistance`":312,`"RollOffMinDistance`":316,`"PlaybackSpeed`":308,`"Volume`":328,`"SoundGroup`":256,`"Looped`":341},`"SpawnLocation`":{`"AllowTeamChangeOnTouch`":496,`"Enabled`":497,`"Neutral`":498,`"ForcefieldDuration`":488,`"TeamColor`":492},`"SurfaceAppearance`":{`"AlphaMode`":672,`"Color`":648,`"ColorMap`":224,`"EmissiveMaskContent`":272,`"EmissiveStrength`":676,`"EmissiveTint`":660,`"MetalnessMap`":320,`"NormalMap`":368,`"RoughnessMap`":416},`"ParticleEmitter`":{`"Brightness`":564,`"LightEmission`":592,`"LightInfluence`":596,`"Texture`":472,`"ZOffset`":636,`"Lifetime`":524,`"Rate`":608,`"Rotation`":540,`"RotSpeed`":532,`"Speed`":548,`"SpreadAngle`":556,`"Acceleration`":504,`"Drag`":568,`"TimeScale`":628,`"VelocityInheritance`":632},`"Beam`":{`"Brightness`":408,`"LightEmission`":420,`"LightInfluence`":424,`"Texture`":344,`"TextureLength`":436,`"TextureSpeed`":444,`"ZOffset`":456,`"Attachment0`":376,`"Attachment1`":392,`"CurveSize0`":412,`"CurveSize1`":416,`"Width0`":448,`"Width1`":452},`"Player`":{`"LocalPlayer`":328,`"UserId`":760,`"DisplayName`":336,`"HealthDisplayDistance`":892,`"NameDisplayDistance`":908,`"ModelInstance`":976,`"Team`":720,`"TeamColor`":920,`"LocaleId`":304,`"AccountAge`":844,`"MinZoomDistance`":856,`"MaxZoomDistance`":852,`"CameraMode`":860,`"Mouse`":4488},`"Team`":{`"BrickColor`":208},`"Humanoid`":{`"Health`":404,`"MaxHealth`":436,`"Walkspeed`":476,`"WalkspeedCheck`":964,`"JumpPower`":432,`"JumpHeight`":428,`"HipHeight`":416,`"MaxSlopeAngle`":440,`"SeatPart`":288,`"HumanoidRootPart`":1152,`"CameraOffset`":320,`"HealthDisplayDistance`":408,`"NameDisplayDistance`":444,`"DisplayDistanceType`":396,`"HealthDisplayType`":412,`"NameOcclusion`":448,`"DisplayName`":208,`"MoveDirection`":344,`"RigType`":460,`"Jump`":486,`"Sit`":489,`"PlatformStand`":488,`"UseJumpPower`":492,`"AutomaticScalingEnabled`":482,`"BreakJointsOnDeath`":483,`"EvaluateStateMachine`":484,`"RequiresNeck`":489,`"AutoJumpEnabled`":480,`"AutoRotate`":481,`"IsWalking`":2335,`"MoveToPoint`":380,`"MoveToPart`":304,`"WalkTimer`":1040,`"HumanoidState`":2208,`"HumanoidStateID`":32,`"FloorMaterial`":400,`"TargetPoint`":356,`"PlatformStatePointer`":1079774289},`"Seat`":{`"Occupant`":536},`"VehicleSeat`":{`"MaxSpeed`":560,`"SteerFloat`":568,`"ThrottleFloat`":576,`"Torque`":580,`"TurnSpeed`":584},`"StatsItem`":{`"Value`":200},`"Tool`":{`"Tooltip`":1136,`"TextureId`":872,`"Grip`":1204,`"Enabled`":1217,`"CanBeDropped`":1216,`"ManualActivationOnly`":1218,`"RequiresHandle`":1219},`"Clothing`":{`"Template`":280,`"Color3`":312},`"CharacterMesh`":{`"BaseTextureId`":224,`"OverlayTextureId`":320,`"MeshId`":272,`"BodyPart`":352},`"Camera`":{`"Position`":284,`"Rotation`":248,`"CameraSubject`":232,`"FieldOfView`":352,`"ImagePlaneDepth`":752,`"CameraType`":344,`"Viewport`":684,`"ViewportSize`":744},`"BasePart`":{`"Primitive`":328,`"Transparency`":240,`"Color3`":404,`"Shape`":433,`"Massless`":247,`"CastShadow`":245,`"Locked`":246,`"Reflectance`":236},`"Primitive`":{`"Position`":236,`"Validate`":6,`"Owner`":520,`"Size`":440,`"Rotation`":200,`"Flags`":438,`"Material`":0,`"AssemblyLinearVelocity`":248,`"AssemblyAngularVelocity`":260},`"PrimitiveFlags`":{`"Anchored`":2,`"CanCollide`":8,`"CanTouch`":16,`"CanQuery`":32},`"MeshPart`":{`"MeshId`":760,`"Texture`":808},`"Model`":{`"PrimaryPart`":632,`"Scale`":356},`"SpecialMesh`":{`"Scale`":220,`"MeshId`":272},`"Attachment`":{`"Position`":220},`"Weld`":{`"Part0`":304,`"Part1`":320},`"WeldConstraint`":{`"Part0`":208,`"Part1`":224},`"UnionOperation`":{`"AssetId`":752},`"PlayerMouse`":{`"Workspace`":360,`"Icon`":224},`"GuiObject`":{`"ScreenGui_Enabled`":1220,`"Position`":1296,`"Size`":1328,`"Visible`":1453,`"Image`":2440,`"Text`":3488,`"RichText`":2896,`"BackgroundColor3`":1344,`"BorderColor3`":1356,`"TextColor3`":3664,`"LayoutOrder`":1408,`"ZIndex`":411,`"BackgroundTransparency`":1356,`"Rotation`":392},`"GuiBase2D`":{`"AbsoluteSize`":280,`"AbsolutePosition`":272,`"AbsoluteRotation`":392},`"UserInputService`":{`"WindowInputState`":728},`"WindowInputState`":{`"CurrentTextBox`":72,`"CapsLock`":64},`"Textures`":{`"Decal_Texture`":408,`"Texture_Texture`":408},`"Lighting`":{`"ClockTime`":448,`"Brightness`":296,`"EnvironmentDiffuseScale`":300,`"EnvironmentSpecularScale`":304,`"FogStart`":320,`"FogEnd`":316,`"FogColor`":260,`"Ambient`":224,`"OutdoorAmbient`":272,`"ColorShift_Top`":236,`"ColorShift_Bottom`":248,`"ExposureCompensation`":308,`"GeographicLatitude`":408,`"LightColor`":356,`"GradientTop`":344,`"LightDirection`":368,`"GradientBottom`":412,`"GlobalShadows`":336,`"MoonPosition`":396,`"SunPosition`":384,`"Source`":380,`"Sky`":480},`"Sky`":{`"SkyboxBk`":272,`"SkyboxDn`":320,`"SkyboxFt`":368,`"SkyboxLf`":416,`"SkyboxRt`":464,`"SkyboxUp`":512,`"SunAngularSize`":596,`"MoonAngularSize`":604,`"SunTextureId`":560,`"MoonTextureId`":224,`"SkyboxOrientation`":592,`"StarCount`":608},`"Atmosphere`":{`"Density`":232,`"Offset`":244,`"Color`":208,`"Decay`":220,`"Glare`":236,`"Haze`":240},`"BloomEffect`":{`"Intensity`":208,`"Size`":212,`"Threshold`":216,`"Enabled`":200},`"DepthOfFieldEffect`":{`"FocusDistance`":212,`"FarIntensity`":208,`"NearIntensity`":220,`"InFocusRadius`":216,`"Enabled`":200},`"SunRaysEffect`":{`"Intensity`":208,`"Spread`":212,`"Enabled`":200},`"ColorCorrectionEffect`":{`"Brightness`":220,`"Contrast`":224,`"TintColor`":208,`"Enabled`":200},`"ColorGradingEffect`":{`"TonemapperPreset`":208,`"Enabled`":200},`"BlurEffect`":{`"Size`":208,`"Enabled`":200},`"ProximityPrompt`":{`"ActionText`":200,`"ObjectText`":232,`"HoldDuration`":312,`"MaxActivationDistance`":320,`"KeyCode`":316,`"GamepadKeyCode`":308,`"Enabled`":334,`"RequiresLineOfSight`":335},`"ClickDetector`":{`"MaxActivationDistance`":256,`"MouseIcon`":224},`"DragDetector`":{`"ReferenceInstance`":520,`"MaxActivationDistance`":256,`"MaxDragAngle`":704,`"MaxDragTranslation`":644,`"MinDragAngle`":716,`"MinDragTranslation`":656,`"ActivatedCursorIcon`":472,`"CursorIcon`":224,`"MaxForce`":708,`"MaxTorque`":712,`"Responsiveness`":728},`"AnimationTrack`":{`"Animation`":208,`"Animator`":280,`"Speed`":228,`"TimePosition`":232,`"Looped`":245,`"IsPlaying`":2576},`"Animator`":{`"ActiveAnimations`":2184},`"LocalScript`":{`"GUID`":232,`"Hash`":440,`"ByteCode`":424},`"ByteCode`":{`"Size`":32,`"Pointer`":16},`"Script`":{`"GUID`":232,`"Hash`":440,`"ByteCode`":424}}}"

    try {
        parsed := JSON.parse(body)
    } catch {
        return ""
    }

    if !(parsed is Map) || !parsed.Has("Offsets")
        return ""

    _LastRemoteFetchResult := parsed
    return parsed
}
BackupAndWriteOffsetsFile(parsed) {
    global OFFSETS_PATH

    backupPath := OFFSETS_PATH ".bak"

    if (FileExist(OFFSETS_PATH)) {
        try {
            FileCopy(OFFSETS_PATH, backupPath, true)
        } catch {
        }
    }

    try {
        file := FileOpen(OFFSETS_PATH, "w")
        file.Write(JSON.stringify(parsed, 4))
        file.Close()
    } catch {
    }
}


GetRobloxPID() {
    global ROBLOX_INSTANCE
    return ProcessExist(ROBLOX_INSTANCE)
}

GetProcessBase(pid) {
    global H_PROCESS
    static PROCESS_QUERY_INFORMATION := 0x0400
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static PROCESS_VM_READ := 0x0010
    static LIST_MODULES_ALL := 0x03

    access := PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
    H_PROCESS := DllCall("OpenProcess", "UInt", access, "Int", false, "UInt", pid, "Ptr")

    if !H_PROCESS
        H_PROCESS := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, "Int", false, "UInt", pid, "Ptr")

    if !H_PROCESS
        throw Error("Failed to open process " pid " (Error: " A_LastError ")")

    hMods := Buffer(A_PtrSize * 1024)
    cbNeeded := 0

    enumResult := DllCall("psapi\EnumProcessModulesEx"
        , "Ptr", H_PROCESS
        , "Ptr", hMods.Ptr
        , "UInt", hMods.Size
        , "UInt*", &cbNeeded
        , "UInt", LIST_MODULES_ALL)

    if !enumResult {
        DllCall("CloseHandle", "Ptr", H_PROCESS)
        H_PROCESS := 0
        throw Error("Failed to enumerate modules for process " pid " (Error: " A_LastError ")")
    }

    return NumGet(hMods, 0, "UPtr")
}

GetRunningRobloxVersionHash(pid) {
    static PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    static MAX_PATH_CHARS := 1024

    hProc := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED_INFORMATION, "Int", 0, "UInt", pid, "Ptr")
    if !hProc
        throw Error("OpenProcess failed (pid=" pid ", error=" A_LastError ")")

    try {
        buf := Buffer(MAX_PATH_CHARS * 2, 0)  ; UTF-16: 2 bytes per char
        size := MAX_PATH_CHARS
        if !DllCall("QueryFullProcessImageNameW", "Ptr", hProc, "UInt", 0, "Ptr", buf.Ptr, "UInt*", &size)
            throw Error("QueryFullProcessImageNameW failed (error=" A_LastError ")")
    } finally {
        DllCall("CloseHandle", "Ptr", hProc)
    }

    exePath := StrGet(buf, size, "UTF-16")
    if RegExMatch(exePath, "(version-[a-f0-9]+)", &m)
        return m[1]

    throw Error("Version hash not found in path: " exePath)
}

GetLatestRobloxVersionHash() {
    static URL := "https://clientsettingscdn.roblox.com/v1/client-version/WindowsPlayer"

    req := CreateHttpRequest()
    req.Open("GET", URL, false)
    req.Send()

    if req.Status != 200
        throw Error("Version fetch failed: HTTP " req.Status)

    json := req.ResponseText
    if RegExMatch(json, '"clientVersionUpload"\s*:\s*"(version-[a-f0-9]+)"', &m)
        return m[1]

    throw Error("clientVersionUpload not found in response")
}


ReadPointer(address) {
    global H_PROCESS
    buf := Buffer(A_PtrSize, 0)

    success := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", address
        , "Ptr", buf.Ptr
        , "UPtr", A_PtrSize
        , "UPtr*", 0)

    if !success
        return 0

    return NumGet(buf, 0, "UPtr")
}

ReadInt(address) {
    global H_PROCESS
    buf := Buffer(4, 0)

    success := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", address
        , "Ptr", buf.Ptr
        , "UInt", 4
        , "UInt*", 0)

    if !success
        return 0

    return NumGet(buf, 0, "Int")
}

ReadByte(address) {
    global H_PROCESS
    buf := Buffer(1, 0)

    success := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", address
        , "Ptr", buf.Ptr
        , "UInt", 1
        , "UInt*", 0)

    if !success
        return 0

    return NumGet(buf, 0, "UChar")
}

ReadString(address) {
    global H_PROCESS, OFFSETS

    length := ReadInt(address + (OFFSETS["StringLength"] + 0))

    if (length <= 0 || length > 1000)
        return ""

    dataAddr := address

    if (length > 15)
        dataAddr := ReadPointer(address)

    if !dataAddr
        return ""

    buf := Buffer(length + 1, 0)

    success := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", dataAddr
        , "Ptr", buf.Ptr
        , "UPtr", length
        , "UPtr*", 0)

    if !success
        return ""

    return StrGet(buf, length, "UTF-8")
}

ReadInstanceName(instanceAddr) {
    global OFFSETS
    
    nameOffset := OFFSETS["Name"] + 0
    namePtr := ReadPointer(instanceAddr + nameOffset)
    
    if (!namePtr)
        return "<null>"
    
    return ReadString(namePtr)
}

ReadClassName(instanceAddr) {
    global OFFSETS
    
    classDescOffset := OFFSETS["ClassDescriptor"] + 0
    classDesc := ReadPointer(instanceAddr + classDescOffset)
    
    if (!classDesc)
        return "<unknown>"
    
    classNameOffset := OFFSETS["ClassDescriptorToClassName"] + 0
    classNamePtr := ReadPointer(classDesc + classNameOffset)
    
    if (!classNamePtr)
        return "<unknown>"
    
    return ReadString(classNamePtr)
}

ReadChildren(instanceAddr) {
    global OFFSETS

    children := []

    childrenOffset := OFFSETS["Children"] + 0
    listPtr := ReadPointer(instanceAddr + childrenOffset)

    if !listPtr
        return children

    arrayStart := ReadPointer(listPtr)
    arrayEnd := ReadPointer(listPtr + 8)

    if (!arrayStart || !arrayEnd || arrayEnd <= arrayStart)
        return children

    entrySize := 0x10
    numChildren := (arrayEnd - arrayStart) // entrySize

    if (numChildren < 0 || numChildren > 1000)
        return children

    currentAddr := arrayStart
    Loop numChildren {
        childPtr := ReadPointer(currentAddr)
        if childPtr
            children.Push(childPtr)
        currentAddr += entrySize
    }

    return children
}

ReadFloat(address) {
    global H_PROCESS
    
    buf := Buffer(4, 0)
    success := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", address
        , "Ptr", buf.Ptr
        , "UInt", 4
        , "UInt*", 0)
    
    if (!success)
        return 0.0
    
    return NumGet(buf, 0, "Float")
}

ReadDouble(address) {
    global H_PROCESS

    buf := Buffer(8, 0)
    success := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", address
        , "Ptr", buf.Ptr
        , "UInt", 8
        , "UInt*", 0)

    if (!success)
        return 0.0

    return NumGet(buf, 0, "Double")
}

FindChildByName(instanceAddr, name) {
    for childPtr in ReadChildren(instanceAddr) {
        if (ReadInstanceName(childPtr) = name)
            return childPtr
    }
    return 0
}

FindChildByClass(instanceAddr, className) {
    for childPtr in ReadChildren(instanceAddr) {
        if (ReadClassName(childPtr) = className)
            return childPtr
    }
    return 0
}

ReadParent(instanceAddr) {
    global OFFSETS
    return ReadPointer(instanceAddr + (OFFSETS["Parent"] + 0))
}

ReadBytes(address, size) {
    global H_PROCESS

    buf := Buffer(size, 0)

    ok := DllCall("ReadProcessMemory"
        , "Ptr", H_PROCESS
        , "Ptr", address
        , "Ptr", buf.Ptr
        , "UPtr", size
        , "UPtr*", 0)

    if !ok
        return 0

    return buf
}

BufferToHex(buf, size := 64) {
    out := ""
    count := Min(buf.Size, size)

    Loop count {
        b := NumGet(buf, A_Index - 1, "UChar")
        out .= Format("{:02X}", b)
        if (A_Index < count)
            out .= " "
    }

    return out
}

ReadCString(address, maxLen := 128, encoding := "UTF-8") {
    buf := ReadBytes(address, maxLen)
    if !buf
        return ""

    return StrGet(buf, maxLen, encoding)
}


EnsureAppDataDirs() {
    if (!DirExist(APPDATA_DIR))
        DirCreate(APPDATA_DIR)

    if (!DirExist(CONFIGS_DIR))
        DirCreate(CONFIGS_DIR)
}

SaveSettingsFile() {
    global SETTINGS

    try {
        file := FileOpen(APPDATA_DIR "\settings.json", "w")
        file.Write(JSON.stringify(SETTINGS, 4))
        file.Close()
    } catch as err {
        MsgBox("Failed to save settings: " err.Message, "Settings Error")
    }
}

FormatSettingValue(value, isInteger := false, decimals := 2) {
    if (isInteger)
        return Round(value)

    return Format("{:." decimals "f}", value)
}

ValidateAndSaveMain(key, ctrl, minValue, maxValue, isInteger := false, decimals := 2) {
    global SETTINGS, MAIN

    oldValue := MAIN[key]
    rawValue := Trim(ctrl.Value)

    if (rawValue = "") {
        ctrl.Value := FormatSettingValue(oldValue, isInteger, decimals)
        MsgBox("This field cannot be empty.", "Invalid Value")
        return
    }

    if !RegExMatch(rawValue, "^-?(?:\d+|\d*\.\d+)$") {
        ctrl.Value := FormatSettingValue(oldValue, isInteger, decimals)
        MsgBox("Please enter a valid number.", "Invalid Value")
        return
    }

    numericValue := rawValue + 0

    if (isInteger)
        numericValue := Round(numericValue)

    if (numericValue < minValue || numericValue > maxValue) {
        ctrl.Value := FormatSettingValue(oldValue, isInteger, decimals)
        MsgBox("Value must be between " minValue " and " maxValue ".", "Invalid Range")
        return
    }

    MAIN[key] := numericValue
    SETTINGS["main"][key] := numericValue

    ctrl.Value := FormatSettingValue(numericValue, isInteger, decimals)

    if (key = "update_rate")
        SetTimer(MacroLoop, MAIN["update_rate"])

    SaveSettingsFile()
}

ListConfigs() {
    configs := []

    if (!DirExist(CONFIGS_DIR))
        return configs

    Loop Files, CONFIGS_DIR "\*.json" {
        name := RegExReplace(A_LoopFileName, "\.json$")
        configs.Push(name)
    }

    return configs
}

SaveConfig(name, useDefaults := false) {
    global SETTINGS

    data := useDefaults ? GetDefaultSettings()["main"] : SETTINGS["main"].Clone()
    PruneObsoleteMainSettings(data)
    NormalizeMainSettings(data)

    try {
        file := FileOpen(CONFIGS_DIR "\" name ".json", "w")
        file.Write(JSON.stringify(data, 4))
        file.Close()
    } catch as err {
        MsgBox("Failed to save config: " err.Message, "Config Error")
    }
}

LoadConfig(name) {
    global SETTINGS, MAIN

    filePath := CONFIGS_DIR "\" name ".json"

    try {
        jsonData := FileRead(filePath)
        configMap := JSON.parse(jsonData)

        for key, value in configMap {
            SETTINGS["main"][key] := value
            MAIN[key] := value
        }

        configDirty := PruneObsoleteMainSettings(SETTINGS["main"])
        if (NormalizeMainSettings(SETTINGS["main"]))
            configDirty := true

        defaults := GetDefaultSettings()["main"]
        for key, defaultVal in defaults {
            if (!MAIN.Has(key)) {
                MAIN[key] := defaultVal
                SETTINGS["main"][key] := defaultVal
                configDirty := true
            }
        }

        if (configDirty)
            SaveConfig(name)

        SETTINGS["last_config"] := name
        SaveSettingsFile()
        ReloadMacro()
    } catch as err {
        MsgBox("Failed to load config: " err.Message, "Config Error")
    }
}

DeleteConfig(name) {
    global SETTINGS

    try {
        FileDelete(CONFIGS_DIR "\" name ".json")
        if (SETTINGS["last_config"] = name) {
            SETTINGS["last_config"] := ""
            SaveSettingsFile()
        }
    } catch as err {
        MsgBox("Failed to delete config: " err.Message, "Config Error")
    }
}

MigrateAllConfigs() {
    global SETTINGS, FULL_VER

    if (SETTINGS.Has("last_migrated_version") && SETTINGS["last_migrated_version"] = FULL_VER)
        return

    if (!DirExist(CONFIGS_DIR))
        return

    defaults := GetDefaultSettings()["main"]

    Loop Files, CONFIGS_DIR "\*.json" {
        try {
            jsonData := FileRead(A_LoopFileFullPath)
            configMap := JSON.parse(jsonData)
            changed := false

            if (PruneObsoleteMainSettings(configMap))
                changed := true
            if (NormalizeMainSettings(configMap))
                changed := true

            for key, defaultVal in defaults {
                if (!configMap.Has(key)) {
                    configMap[key] := defaultVal
                    changed := true
                }
            }

            if (changed) {
                file := FileOpen(A_LoopFileFullPath, "w")
                file.Write(JSON.stringify(configMap, 4))
                file.Close()
            }
        } catch {
        }
    }

    SETTINGS["last_migrated_version"] := FULL_VER
    SaveSettingsFile()
}


GetHotbarTotems() {
    totems := []
    seen := Map()
    hotbar := GetHotbarGui()

    if !hotbar
        return totems

    for itemAddr in ReadChildren(hotbar) {
        if (ReadClassName(itemAddr) != "ImageButton" || ReadInstanceName(itemAddr) != "ItemTemplate")
            continue

        toolName := ReadHotbarItemName(itemAddr)
        if !IsSupportedAutoTotem(toolName)
            continue

        if seen.Has(toolName)
            continue

        seen[toolName] := true
        totems.Push(toolName)
    }

    return totems
}

HasHotbarTotem(totemName) {
    return FindHotbarItemByName(totemName) ? true : false
}

GetHotbarItemSlotKey(itemName) {
    itemAddr := FindHotbarItemByName(itemName)
    if !itemAddr
        return ""

    return ReadHotbarItemSlotKey(itemAddr)
}

SelectHotbarSlot(slotKey) {
    if (slotKey = "")
        return false

    SendInput("{" slotKey "}")
    Sleep(75)
    return true
}

UseHotbarSlot(slotKey) {
    if !SelectHotbarSlot(slotKey)
        return false

    Click()
    Sleep(75)
    return true
}

UseEquippedHotbarItem() {
    Click()
    Sleep(75)
    return true
}

GetAutoTotemWaitMs() {
    return 30000
}

GetCharacterModel() {
    workspace := GetWorkspaceRoot()
    if !workspace
        return 0

    localPlayer := GetLocalPlayer()
    if !localPlayer
        return 0

    playerName := ReadInstanceName(localPlayer)
    if (playerName = "" || playerName = "<null>")
        return 0

    return FindChildByName(workspace, playerName)
}

GetEquippedToolName() {
    character := GetCharacterModel()
    if !character
        return ""

    for childAddr in ReadChildren(character) {
        if (ReadClassName(childAddr) = "Tool")
            return ReadInstanceName(childAddr)
    }

    return ""
}

IsAnythingEquipped() {
    character := GetCharacterModel()
    if !character
        return false

    for childAddr in ReadChildren(character) {
        if (ReadClassName(childAddr) = "Tool")
            return true
    }

    return false
}

IsRodEquipped() {
    equippedTool := GetEquippedToolName()
    if (equippedTool = "")
        return false

    rodName := GetHotbarRodName()
    if (rodName != "")
        return (equippedTool = rodName)

    return InStr(equippedTool, "Rod") ? true : false
}

EnsureRodEquipped() {
    if IsRodEquipped()
        return true

    return SelectHotbarSlot("1")
}

TryUseHotbarItem(itemName) {
    slotKey := GetHotbarItemSlotKey(itemName)
    if (slotKey = "")
        return false

    Loop 2 {
        equippedBefore := GetEquippedToolName()

        if (equippedBefore != itemName) {
            if !SelectHotbarSlot(slotKey)
                return false

            Sleep(175)
        }

        Click()
        Sleep(100)

        equippedAfter := GetEquippedToolName()

        if (equippedAfter = itemName || equippedBefore = itemName)
            return true

        Sleep(125)
    }

    return false
}

; ─────────────────────────────────────────────────────────────────────────
;  World state (weather / cycle) is read from the authoritative
;  ReplicatedStorage.world Configuration the game replicates. Since the weather
;  overhaul, weather is three coexisting layers: the base "weather", a buffing
;  "sovereign" child, and a "meteorological" (celestial, e.g. Aurora) child.
;  This replaces the old HUD-scraping, which broke when the HUD layout changed.
; ─────────────────────────────────────────────────────────────────────────

GetWorldConfig() {
    global g_CachedWorldConfig

    if (g_CachedWorldConfig)
        return g_CachedWorldConfig

    dataModel := GetDataModel()
    if (!dataModel)
        return 0

    replicatedStorage := FindChildByClass(dataModel, "ReplicatedStorage")
    if (!replicatedStorage)
        return 0

    world := FindChildByName(replicatedStorage, "world")
    if (world)
        g_CachedWorldConfig := world

    return world
}

; Read a StringValue's Value: inline std::string at +Value, falling back to a
; pointer-to-string if the inline read is empty.
ReadWorldStringValue(instanceAddr) {
    global OFFSETS

    if (!instanceAddr)
        return ""

    valueOffset := OFFSETS.Has("Value") ? (OFFSETS["Value"] + 0) : 0xd0

    embedded := ReadString(instanceAddr + valueOffset)
    if (embedded != "")
        return embedded

    ptr := ReadPointer(instanceAddr + valueOffset)
    if (ptr)
        return ReadString(ptr)

    return ""
}

; The game stores "None" for an inactive layer; surface that as empty.
NormalizeWorldNone(value) {
    trimmed := Trim(value)
    return (StrLower(trimmed) = "none") ? "" : trimmed
}

GetWorldWeatherInstance() {
    world := GetWorldConfig()
    if (!world)
        return 0

    return FindChildByName(world, "weather")
}

GetCurrentWeather() {
    return Trim(ReadWorldStringValue(GetWorldWeatherInstance()))
}


GetCurrentMeteorological() {
    weatherInst := GetWorldWeatherInstance()
    if (!weatherInst)
        return ""

    return NormalizeWorldNone(ReadWorldStringValue(FindChildByName(weatherInst, "meteorological")))
}

GetCurrentCycle() {
    world := GetWorldConfig()
    if (!world)
        return ""

    return Trim(ReadWorldStringValue(FindChildByName(world, "cycle")))
}

IsNightCycle() {
    return InStr(StrLower(GetCurrentCycle()), "night") ? true : false
}

IsAuroraActive() {
    if InStr(StrLower(GetCurrentMeteorological()), "aurora")
        return true

    return InStr(StrLower(GetCurrentWeather()), "aurora") ? true : false
}

IsTotemBlocked() {
        met := StrLower(GetCurrentMeteorological())
        weather := StrLower(GetCurrentWeather())

        return (
                InStr(met, "starfall")
                || InStr(weather, "starfall")
                || InStr(met, "rainbow")
                || InStr(weather, "rainbow")
        ) ? true : false
}

FindHotbarItemByName(itemName) {
    hotbar := GetHotbarGui()
    if !hotbar
        return 0

    for itemAddr in ReadChildren(hotbar) {
        if (ReadClassName(itemAddr) != "ImageButton" || ReadInstanceName(itemAddr) != "ItemTemplate")
            continue

        if (ReadHotbarItemName(itemAddr) = itemName)
            return itemAddr
    }

    return 0
}

ReadHotbarItemName(itemAddr) {
    nameInst := FindChildByName(itemAddr, "ItemName")
    if !nameInst
        return ""

    return NormalizeHotbarItemText(ReadGuiText(nameInst))
}

ReadHotbarItemSlotKey(itemAddr) {
    for childAddr in ReadChildren(itemAddr) {
        childClass := ReadClassName(childAddr)
        childName := ReadInstanceName(childAddr)

        if (childClass = "TextLabel" && childName = "TextLabel")
            return NormalizeHotbarItemText(ReadGuiText(childAddr))
    }

    return ""
}

NormalizeHotbarItemText(text) {
    if (text = "")
        return ""

    return Trim(RegExReplace(text, "<[^>]+>"))
}

IsSupportedAutoTotem(toolName) {
    return (toolName = "Aurora Totem")
}

FindDescendantByNameAndClass(rootAddr, targetName, targetClass := "") {
    queue := [rootAddr]
    index := 1

    while (index <= queue.Length) {
        current := queue[index]
        index += 1

        currentName := ReadInstanceName(current)
        currentClass := ReadClassName(current)

        if (currentName = targetName && (targetClass = "" || currentClass = targetClass))
            return current

        for childAddr in ReadChildren(current)
            queue.Push(childAddr)
    }

    return 0
}



; ============================================================================
;  Auto-Updater
; ============================================================================

IsValidFMUVersion(v) {
    return RegExMatch(v, "^v\d+\.\d+$") != 0
}

ParseFMUVersion(v) {
    if !IsValidFMUVersion(v)
        throw Error("Invalid version: " v)
    parts := StrSplit(SubStr(v, 2), ".")
    return [parts[1] + 0, parts[2] + 0]
}

; Returns 1 if left > right, -1 if left < right, 0 if equal
CompareFMUVersions(left, right) {
    l := ParseFMUVersion(left)
    r := ParseFMUVersion(right)
    Loop 2 {
        if (l[A_Index] > r[A_Index])
            return 1
        if (l[A_Index] < r[A_Index])
            return -1
    }
    return 0
}

FetchVersionUrl(url) {
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 15000, 15000)
    request.Open("GET", url, false)
    request.SetRequestHeader("User-Agent", "FischMacroUltimate/" FULL_VER)
    request.Send()
    if (request.Status != 200)
        throw Error("HTTP " request.Status)
    return request.ResponseText
}

ShowUpdateAvailableGui(currentVer, newVer) {
    global APPEARANCE

    result := false

    Accent      := APPEARANCE["accent_color"]
    BgColor     := APPEARANCE["bg_color"]
    TextColor   := APPEARANCE["text_color"]
    BorderColor := APPEARANCE["border_color"]

    dlg := Gui("AlwaysOnTop +Border")
    dlg.Title := "Update Available"
    dlg.BackColor := "0x" BgColor
    dlg.SetFont(, "Segoe UI")

    dlg.AddText("x10 y12 w380 h24 c" TextColor, "Update Available").SetFont("s13 bold")
    Border(dlg, 10, 40, 380, 1, BorderColor)

    dlg.AddText("x10 y52 w380 h20 c" TextColor, "A new version of Fisch Macro Ultimate is available!").SetFont("s10")

    dlg.AddText("x10 y82 w160 h20 c" TextColor, "Current version:").SetFont("s10")
    dlg.AddText("x175 y82 w210 h20 c" Accent, currentVer).SetFont("s10 bold")

    dlg.AddText("x10 y106 w160 h20 c" TextColor, "New version:").SetFont("s10")
    dlg.AddText("x175 y106 w210 h20 c" Accent, newVer).SetFont("s10 bold")

    Border(dlg, 10, 134, 380, 1, BorderColor)

    dlg.AddText("x10 y144 w380 h20 c" TextColor, "The macro will restart automatically after updating.").SetFont("s9")

    updateBtn := button(dlg, "Update Now", 195, 175, {
        w: 100,
        h: 28,
        bg: Accent,
        textColor: TextColor,
        fontSize: 10
    })
    laterBtn := button(dlg, "Later", 305, 175, {
        w: 75,
        h: 28,
        bg: BgColor,
        textColor: TextColor,
        fontSize: 10
    })

    updateBtn.OnEvent("Click", (*) => (result := true, dlg.Destroy()))
    laterBtn.OnEvent("Click",  (*) => dlg.Destroy())
    dlg.OnEvent("Close",       (*) => dlg.Destroy())
    dlg.OnEvent("Escape",      (*) => dlg.Destroy())

    dlg.Show("w400 h220 Center")
    WinWaitClose(dlg.Hwnd)
    return result
}

ShowUpdateErrorGui(message) {
    global APPEARANCE

    Accent      := APPEARANCE["accent_color"]
    BgColor     := APPEARANCE["bg_color"]
    TextColor   := APPEARANCE["text_color"]
    BorderColor := APPEARANCE["border_color"]

    dlg := Gui("AlwaysOnTop +Border")
    dlg.Title := "Update Error"
    dlg.BackColor := "0x" BgColor
    dlg.SetFont(, "Segoe UI")

    dlg.AddText("x10 y12 w380 h24 c" TextColor, "Update Error").SetFont("s13 bold")
    Border(dlg, 10, 40, 380, 1, BorderColor)

    errText := dlg.AddText("x10 y52 w380 h60 c" TextColor, message)
    errText.SetFont("s10")

    closeBtn := button(dlg, "OK", 300, 125, {
        w: 80,
        h: 28,
        bg: BgColor,
        textColor: TextColor,
        fontSize: 10
    })
    closeBtn.OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Close",      (*) => dlg.Destroy())
    dlg.OnEvent("Escape",     (*) => dlg.Destroy())

    dlg.Show("w400 h170 Center")
    WinWaitClose(dlg.Hwnd)
}

CheckForFMUUpdate() {
    global UPDATE_VERSION_URL, FULL_VER
    try {
        raw := FetchVersionUrl(UPDATE_VERSION_URL)
        remoteVer := Trim(raw, " `t`r`n")
        if !IsValidFMUVersion(remoteVer)
            return ""
        if (CompareFMUVersions(remoteVer, FULL_VER) <= 0)
            return ""
        return remoteVer
    } catch {
        return ""
    }
}

DownloadAndInstallFMUUpdate(newVersion) {
    global UPDATE_DOWNLOAD_URL, FULL_VER

    tempAhk  := A_Temp "\FischMacroUltimate_update.ahk"
    batchPath := A_Temp "\FischMacroUltimate_updater.bat"

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 60000, 60000)
        req.Open("GET", UPDATE_DOWNLOAD_URL, false)
        req.SetRequestHeader("User-Agent", "FischMacroUltimate/" FULL_VER)
        req.Send()

        if (req.Status != 200)
            throw Error("Download failed: HTTP " req.Status)

        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(req.ResponseBody)
        stream.Position := 0
        stream.SaveToFile(tempAhk, 2)
        stream.Close()
    } catch as err {
        ShowUpdateErrorGui("Could not download update:`n" err.Message)
        return false
    }

    currentScript := A_ScriptFullPath
    q := Chr(34)

    batchLines := (
        "@echo off`r`n"
        "timeout /t 2 /nobreak >nul`r`n"
        "copy /y " q tempAhk q " " q currentScript q "`r`n"
        "if errorlevel 1 goto fail`r`n"
        "start " q q " " q A_AhkPath q " " q currentScript q "`r`n"
        "del /f /q " q tempAhk q "`r`n"
        "del /f /q " q batchPath q "`r`n"
        "exit /b 0`r`n"
        ":fail`r`n"
        "echo Update copy failed. Please replace the script manually.`r`n"
        "pause`r`n"
    )

    try {
        f := FileOpen(batchPath, "w")
        f.Write(batchLines)
        f.Close()
    } catch as err {
        ShowUpdateErrorGui("Could not create update helper:`n" err.Message)
        return false
    }

    Run('"' A_ComSpec '" /c "' batchPath '"', , "Hide")
    ExitApp()
    return true
}

RunStartupUpdateCheck() {
    newVer := CheckForFMUUpdate()
    if (newVer = "")
        return

    if (ShowUpdateAvailableGui(FULL_VER, newVer))
        DownloadAndInstallFMUUpdate(newVer)
}


global WebhookSession := {
    startedAt: 0,
    lastSummaryAt: 0
}

SendWebhookPost(url, payload) {
    if (url = "")
        return 0

    try {
        wr := ComObject("WinHttp.WinHttpRequest.5.1")
        wr.Open("POST", url "?with_components=true", false)
        wr.SetRequestHeader("Content-Type", "application/json")
        wr.Send(payload)
        return wr.Status
    } catch {
        return 0
    }
}

GetWebhookAccentColor() {
    global APPEARANCE
    hex := APPEARANCE["accent_color"]
    try
        return Integer("0x" hex)
    catch
        return 0x5aa9ff
}

FormatSessionRuntime(ms) {
    if (ms < 0)
        ms := 0

    totalSeconds := ms // 1000
    hours := totalSeconds // 3600
    minutes := Mod(totalSeconds, 3600) // 60
    seconds := Mod(totalSeconds, 60)

    if (hours > 0)
        return Format("{}h {}m {}s", hours, minutes, seconds)
    if (minutes > 0)
        return Format("{}m {}s", minutes, seconds)
    return Format("{}s", seconds)
}

GetTotemStateText() {
    global MAIN
    if !MAIN["auto_totem_enabled"]
        return "Disabled"

    mode := MAIN["auto_totem_mode"]
    if (mode = "interval")
        return "Enabled (interval " MAIN["auto_totem_interval_sec"] "s)"
    return "Enabled (on expire)"
}

BuildSummaryPayload() {
    global Macro, MAIN, SETTINGS, ROD, WebhookSession

    runtimeMs := WebhookSession.startedAt ? (A_TickCount - WebhookSession.startedAt) : 0

    headerText := "## Macro Summary"
    if (MAIN["webhook_summary_session_time"])
        headerText .= "`n**Session runtime:** " FormatSessionRuntime(runtimeMs)

    statLines := []
    if (MAIN["webhook_summary_fish"]) {
        statLines.Push("**Caught:** " Macro.fishCaughtCount)
        statLines.Push("**Lost:** " Macro.fishLostCount)
    }
    if (MAIN["webhook_summary_success_rate"]) {
        total := Macro.fishCaughtCount + Macro.fishLostCount
        rate := total > 0 ? (Macro.fishCaughtCount / total) * 100.0 : 0.0
        statLines.Push("**Success Rate:** " Format("{:.1f}", rate) "%")
    }
    if (MAIN["webhook_summary_cast_timeouts"])
        statLines.Push("**Cast Timeouts:** " Macro.castTimeoutCount)
    if (MAIN["webhook_summary_totem_pops"])
        statLines.Push("**Totems Popped:** " Macro.totemPopCount)

    identityLines := []
    if (MAIN["webhook_summary_rod"])
        identityLines.Push("**Rod:** " (ROD != "" ? ROD : "---"))
    if (MAIN["webhook_summary_config"]) {
        cfg := SETTINGS.Has("last_config") ? SETTINGS["last_config"] : ""
        identityLines.Push("**Config:** " (cfg != "" ? cfg : "---"))
    }
    if (MAIN["webhook_summary_totem_state"])
        identityLines.Push("**Auto Totem:** " GetTotemStateText())

    innerComponents := []
    innerComponents.Push(Map("type", 10, "content", headerText))

    if (statLines.Length > 0) {
        innerComponents.Push(Map("type", 14))
        innerComponents.Push(Map("type", 10, "content", JoinLines(statLines)))
    }

    if (identityLines.Length > 0) {
        innerComponents.Push(Map("type", 14))
        innerComponents.Push(Map("type", 10, "content", JoinLines(identityLines)))
    }

    container := Map(
        "type", 17,
        "accent_color", GetWebhookAccentColor(),
        "components", innerComponents
    )

    payload := Map(
        "flags", 32768,
        "components", [container]
    )

    return JSON.stringify(payload)
}

JoinLines(lines) {
    out := ""
    for i, line in lines
        out .= (i = 1 ? "" : "`n") line
    return out
}

SendSummaryWebhook() {
    global MAIN, WebhookSession

    if !MAIN["webhook_enabled"]
        return

    url := MAIN["webhook_url"]
    if (url = "")
        return

    intervalMin := Max(1, MAIN["webhook_summary_interval_min"] + 0)
    intervalMs := intervalMin * 60 * 1000

    if (WebhookSession.lastSummaryAt && (A_TickCount - WebhookSession.lastSummaryAt) < intervalMs)
        return

    if (WebhookSession.startedAt = 0)
        return

    payload := BuildSummaryPayload()
    SendWebhookPost(url, payload)
    WebhookSession.lastSummaryAt := A_TickCount
}

SendInstantAlert(title, desc, color := "") {
    global MAIN

    if !MAIN["webhook_enabled"]
        return

    url := MAIN["webhook_url"]
    if (url = "")
        return

    content := "## " title
    if (desc != "")
        content .= "`n" desc

    if (color = "")
        color := GetWebhookAccentColor()

    container := Map(
        "type", 17,
        "accent_color", color,
        "components", [Map("type", 10, "content", content)]
    )

    payload := Map(
        "flags", 32768,
        "components", [container]
    )

    SendWebhookPost(url, JSON.stringify(payload))
}


; ---------------------------------------------------------------------------
; HTTP helpers (originally in Update.ahk)
; ---------------------------------------------------------------------------

CreateHttpRequest() {
    return ComObject("WinHttp.WinHttpRequest.5.1")
}

FetchTextUrl(url, userAgent := "") {
    req := CreateHttpRequest()
    if (userAgent != "")
        req.SetRequestHeader("User-Agent", userAgent)
    req.Open("GET", url, false)
    req.Send()
    if (req.Status != 200)
        throw Error("HTTP " req.Status " fetching " url)
    return req.ResponseText
}
