; Keyboard_Remapper_Pro_v1.7
; New in 1.7:
;   - Mappings now live in "mappings.txt" (easy to edit by hand or from the Settings GUI)
;   - Multi-key sequences are supported (e.g. Arabic "لا" <-> English "b")
;   - One-way mappings (EN -> AR only, or AR -> EN only)
;   - Add / Edit / Delete buttons in the Key Mappings tab

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ================== Defaults ==================
global AppName := "Keyboard Remapper"
global BuildTag := "1.7-log1"   ; shown in the log so you can confirm which build is running
OnError(LogError)
Log("===== START build " BuildTag " =====")
Log("A_ScriptFullPath=" A_ScriptFullPath " | A_IsCompiled=" A_IsCompiled " | A_IsAdmin=" A_IsAdmin " | AHK=" A_AhkVersion)
global DataDir := PickDataDir()
Log("DataDir=" DataDir)
global ConfigFile := DataDir "\settings.ini"
global MappingsFile := DataDir "\mappings.txt"
global IsPaused := false
global CurrentHotkey := ""
global RegisteredHotkey := ""
global SoundEnabled := false
global StartWithWindows := true
global RunAsAdminSetting := false

; Mapping data
global Entries := []          ; array of {en, ar, dir}   dir = "both" | "en2ar" | "ar2en"
global enToAr := Map()
global arToEn := Map()
global MaxEnLen := 1
global MaxArLen := 1

; ================== Startup ==================
Log("ConfigFile=" ConfigFile " | exists/attrib=" FileExist(ConfigFile))
Log("MappingsFile=" MappingsFile " | exists/attrib=" FileExist(MappingsFile))
LoadSettings()
Log("Settings loaded")
LoadMappings()
Log("Mappings loaded: " Entries.Length " entries")
CheckAdminOnStartup()
SetupTrayMenu()
SetTrayIcon()
RegisterHotkey()

return

; ================== Data folder ==================

; Use the script folder if it is writable (portable setup),
; otherwise fall back to %AppData%\KeyboardRemapper
PickDataDir() {
    ; Test with IniWrite itself (the same call that failed), not just FileAppend
    testFile := A_ScriptDir "\write_test.tmp"
    try {
        IniWrite("1", testFile, "t", "t")
        FileDelete(testFile)
        Log("Write test OK: " A_ScriptDir)
        return A_ScriptDir
    } catch as err {
        Log("Write test FAILED in " A_ScriptDir " -> " err.Message " (A_LastError=" A_LastError ")")
    }
    try FileDelete(testFile)

    for dir in [A_AppData "\KeyboardRemapper", A_MyDocuments "\KeyboardRemapper", A_Temp "\KeyboardRemapper"] {
        try {
            DirCreate(dir)
            t := dir "\write_test.tmp"
            IniWrite("1", t, "t", "t")
            FileDelete(t)
            Log("Write test OK: " dir)
            return dir
        } catch as err {
            Log("Write test FAILED in " dir " -> " err.Message " (A_LastError=" A_LastError ")")
        }
    }
    MsgBox("No writable folder was found for settings.`nSettings will not be saved.`n`nLog: " LogPaths())
    return A_Temp
}

; ================== Logging ==================

LogPaths() {
    return A_ScriptDir "\KeyboardRemapper_log.txt`n" A_Temp "\KeyboardRemapper_log.txt"
}

; Writes to the log beside the script AND in %TEMP% (the temp copy always works)
Log(msg) {
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " msg "`n"
    for path in [A_ScriptDir "\KeyboardRemapper_log.txt", A_Temp "\KeyboardRemapper_log.txt"] {
        try FileAppend(line, path, "UTF-8")
    }
}

; Global error handler: log everything, show a message box, keep running
LogError(err, mode) {
    stack := ""
    try stack := err.Stack
    Log("ERROR (" mode "): " err.Message " | Extra: " err.Extra " | What: " err.What
        . " | File: " err.File " | Line: " err.Line " | A_LastError: " A_LastError "`n" stack)
    MsgBox("An error occurred and was logged.`n`n" err.Message "`n`nLog files:`n" LogPaths()
        . "`n`nPlease copy the log contents and send them.", "Keyboard Remapper - Error", 0x10)
    return 1   ; handled: don't show the default error dialog
}

; Never crash on a failed INI write; warn once instead
SafeIniWrite(value, file, section, key) {
    static warned := false
    try
        IniWrite(value, file, section, key)
    catch as err {
        Log("SafeIniWrite FAILED: file=" file " [" section "] " key " -> " err.Message
            . " | exists/attrib=" FileExist(file) " | A_LastError=" A_LastError)
        if !warned {
            warned := true
            MsgBox("Could not write settings to:`n" file "`n`n" err.Message
                . "`n`nTry moving the script to a normal folder (e.g. Documents).")
        }
    }
}

; ================== Default mappings ==================

DefaultEntries() {
    flat := [
        "q", "ض", "w", "ص", "e", "ث", "r", "ق", "t", "ف", "y", "غ",
        "u", "ع", "i", "ه", "o", "خ", "p", "ح", "[", "ج", "]", "د",
        "a", "ش", "s", "س", "d", "ي", "f", "ب", "g", "ل", "h", "ا",
        "j", "ت", "k", "ن", "l", "م", ";", "ك", "'", "ط", "z", "ئ",
        "x", "ء", "c", "ؤ", "v", "ر", "b", "لا", "n", "ى", "m", "ة",
        ",", "و", ".", "ز", "/", "ظ", Chr(96), "ذ", "(", ")", ")", "(", "?", "؟",
        "<", "،", ">", "."
    ]
    list := []
    i := 1
    while i < flat.Length {
        list.Push({en: flat[i], ar: flat[i + 1], dir: "both"})
        i += 2
    }
    return list
}

; ================== Mappings: load / save / build ==================

LoadMappings() {
    global Entries, MappingsFile

    if !FileExist(MappingsFile)
        SaveMappings(DefaultEntries())

    Entries := []
    section := ""

    for line in StrSplit(FileRead(MappingsFile, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 2) = "//")
            continue

        if RegExMatch(line, "i)^\[(both|en>ar|ar>en)\]$", &m) {
            section := StrLower(m[1])
            continue
        }

        if (section = "both")
            dir := "both"
        else if (section = "en>ar")
            dir := "en2ar"
        else if (section = "ar>en")
            dir := "ar2en"
        else
            continue

        pos := InStr(line, "=", , 2)   ; start at 2 so a mapping for "=" itself still works
        if !pos
            continue

        left := Trim(SubStr(line, 1, pos - 1))
        right := Trim(SubStr(line, pos + 1))
        if (left = "" || right = "")
            continue

        if (dir = "ar2en")
            Entries.Push({en: right, ar: left, dir: dir})   ; file format: arabic = english
        else
            Entries.Push({en: left, ar: right, dir: dir})   ; file format: english = arabic
    }

    BuildMaps()
}

SaveMappings(list) {
    global MappingsFile

    text := "// Keyboard Remapper mappings (UTF-8). One mapping per line: source = target`n"
          . "// Lines starting with // are comments. Sequences of several characters are allowed.`n"
          . "//`n"
          . "// [Both]   english = arabic     works in both directions`n"
          . "// [EN>AR]  english = arabic     only when converting English -> Arabic`n"
          . "// [AR>EN]  arabic  = english    only when converting Arabic -> English`n"
          . "// Examples:  [EN>AR]  sh = ش      [AR>EN]  لا = b`n`n"

    sections := [["both", "Both"], ["en2ar", "EN>AR"], ["ar2en", "AR>EN"]]
    for sec in sections {
        text .= "[" sec[2] "]`n"
        for e in list {
            if (e.dir != sec[1])
                continue
            if (sec[1] = "ar2en")
                text .= e.ar " = " e.en "`n"
            else
                text .= e.en " = " e.ar "`n"
        }
        text .= "`n"
    }

    try {
        try FileDelete(MappingsFile)
        FileAppend(text, MappingsFile, "UTF-8")
    } catch as err {
        MsgBox("Could not write mappings to:`n" MappingsFile "`n`n" err.Message)
    }
}

BuildMaps() {
    global Entries, enToAr, arToEn, MaxEnLen, MaxArLen

    enToAr := Map()
    enToAr.CaseSense := "Off"
    arToEn := Map()
    MaxEnLen := 1
    MaxArLen := 1

    for e in Entries {
        if (e.dir != "ar2en") {          ; English -> Arabic is allowed
            enToAr[e.en] := e.ar
            MaxEnLen := Max(MaxEnLen, StrLen(e.en))
        }
        if (e.dir != "en2ar") {          ; Arabic -> English is allowed
            arToEn[e.ar] := e.en
            MaxArLen := Max(MaxArLen, StrLen(e.ar))
        }
    }
}

ReloadMappings(*) {
    LoadMappings()
    MsgBox("Mappings reloaded from:`n" MappingsFile)
}

OpenMappingsFile(*) {
    global MappingsFile
    if !FileExist(MappingsFile)
        SaveMappings(DefaultEntries())
    Run('notepad.exe "' MappingsFile '"')
}

; ================== Setup functions ==================

CheckAdminOnStartup() {
    global RunAsAdminSetting
    if (RunAsAdminSetting && !A_IsAdmin) {
        try {
            Run("*RunAs `"" A_ScriptFullPath "`"")
            ExitApp()
        }
    }
}

SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Pause Script", TogglePause)
    A_TrayMenu.Add("Run as Administrator", RunAsAdmin)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Settings", ShowSettingsGUI)
    A_TrayMenu.Add("Edit Mappings File", OpenMappingsFile)
    A_TrayMenu.Add("Reload Mappings", ReloadMappings)
    A_TrayMenu.Add("Open Log", (*) => Run('notepad.exe "' A_Temp '\KeyboardRemapper_log.txt"'))
    A_TrayMenu.Add("About", ShowAbout)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
}

SetTrayIcon() {
    global IsPaused
    iconFile := IsPaused ? A_ScriptDir "\paused.ico" : A_ScriptDir "\active.ico"

    if FileExist(iconFile)
        TraySetIcon(iconFile)
    else {
        if (IsPaused)
            TraySetIcon("Shell32.dll", 100)
        else
            TraySetIcon("Shell32.dll", 14)
    }
}

RegisterHotkey() {
    global CurrentHotkey, RegisteredHotkey

    if (RegisteredHotkey != "") {
        try Hotkey(RegisteredHotkey, ReplaceSelectedText, "Off")
        RegisteredHotkey := ""
    }

    hk := IniRead(ConfigFile, "Settings", "Hotkey", "#+a")

    try Hotkey(hk, ReplaceSelectedText, "On")
    catch {
        MsgBox("Invalid Hotkey: " hk ". Reverting to default Win+Shift+A.")
        hk := "#+a"
        Hotkey(hk, ReplaceSelectedText, "On")
    }
    CurrentHotkey := hk
    RegisteredHotkey := hk
}

; ================== Settings GUI ==================

DirLabels() {
    return ["<->", "EN->AR", "AR->EN"]
}

DirToText(dir) {
    return dir = "en2ar" ? "EN->AR" : dir = "ar2en" ? "AR->EN" : "<->"
}

TextToDir(text) {
    return text = "EN->AR" ? "en2ar" : text = "AR->EN" ? "ar2en" : "both"
}

ShowSettingsGUI(*) {
    global CurrentHotkey, SoundEnabled, StartWithWindows, RunAsAdminSetting, Entries

    sg := Gui("+Owner", "Settings - " AppName)
    sg.SetFont("s10")

    tab := sg.AddTab3("w420 h360", ["General", "Key Mappings"])

    tab.UseTab(1)

    sg.Add("Text", "x20 y50", "Toggle Shortcut:")
    edHotkey := sg.Add("Edit", "x150 y45 w150", CurrentHotkey)
    sg.Add("Text", "x305 y50", "(e.g. #+a)")

    chkSound := sg.Add("CheckBox", "x20 y90", "Enable Sound Feedback")
    chkSound.Value := SoundEnabled

    chkStartup := sg.Add("CheckBox", "x20 y120", "Run at Windows Startup")
    chkStartup.Value := StartWithWindows

    chkAdmin := sg.Add("CheckBox", "x20 y150", "Always Run as Administrator")
    chkAdmin.Value := RunAsAdminSetting

    tab.UseTab(2)

    sg.Add("Text", "x20 y45", "Double-click a row to edit. Multi-key sequences are allowed.")

    lv := sg.Add("ListView", "x20 y70 w380 h210", ["English", "Arabic", "Direction"])
    lv.ModifyCol(1, 110)
    lv.ModifyCol(2, 110)
    lv.ModifyCol(3, 120)

    for e in Entries
        lv.Add("", e.en, e.ar, DirToText(e.dir))

    lv.OnEvent("DoubleClick", (ctrl, row) => ShowEntryDialog(sg, ctrl, row))

    sg.Add("Button", "x20 y290 w80", "Add").OnEvent("Click", (*) => ShowEntryDialog(sg, lv, 0))
    sg.Add("Button", "x110 y290 w80", "Delete").OnEvent("Click", DeleteRow)
    sg.Add("Button", "x250 y290 w150", "Reset to Default").OnEvent("Click", ResetMappings)

    tab.UseTab()   ; controls below belong to no tab
    sg.Add("Button", "x160 y375 w100 default", "Save").OnEvent("Click", SaveSettings)

    sg.Show()

    DeleteRow(*) {
        row := lv.GetNext()
        if row
            lv.Delete(row)
    }

    ResetMappings(*) {
        lv.Delete()
        for e in DefaultEntries()
            lv.Add("", e.en, e.ar, DirToText(e.dir))
        MsgBox("List reset to default. Click Save to apply.")
    }

    SaveSettings(*) {
        global CurrentHotkey, SoundEnabled, StartWithWindows, RunAsAdminSetting, Entries

        newHk := edHotkey.Value
        SoundEnabled := chkSound.Value
        StartWithWindows := chkStartup.Value
        NewAdminSetting := chkAdmin.Value

        SafeIniWrite(newHk, ConfigFile, "Settings", "Hotkey")
        SafeIniWrite(SoundEnabled, ConfigFile, "Settings", "SoundEnabled")
        SafeIniWrite(StartWithWindows, ConfigFile, "Settings", "StartWithWindows")
        SafeIniWrite(NewAdminSetting, ConfigFile, "Settings", "RunAsAdmin")

        ; Collect mappings from the list and save them to mappings.txt
        list := []
        Loop lv.GetCount() {
            list.Push({
                en: lv.GetText(A_Index, 1),
                ar: lv.GetText(A_Index, 2),
                dir: TextToDir(lv.GetText(A_Index, 3))
            })
        }
        Entries := list
        SaveMappings(Entries)
        BuildMaps()

        if (newHk != CurrentHotkey)
            RegisterHotkey()

        ManageStartup(StartWithWindows)
        LoadSettings()

        MsgBox("Settings Saved!")

        if (NewAdminSetting && !A_IsAdmin) {
            try {
                Run("*RunAs `"" A_ScriptFullPath "`"")
                ExitApp()
            }
        }

        sg.Destroy()
    }
}

; Add (row = 0) or edit (row > 0) a mapping row in the ListView
ShowEntryDialog(owner, lv, row := 0) {
    isEdit := row > 0
    en := isEdit ? lv.GetText(row, 1) : ""
    ar := isEdit ? lv.GetText(row, 2) : ""
    dirIdx := 1
    if isEdit {
        for i, label in DirLabels()
            if (label = lv.GetText(row, 3))
                dirIdx := i
    }

    eg := Gui("+Owner" owner.Hwnd, isEdit ? "Edit Mapping" : "Add Mapping")
    eg.SetFont("s10")
    eg.Add("Text", , "English key(s):")
    eE := eg.Add("Edit", "w240", en)
    eg.Add("Text", , "Arabic key(s):")
    eA := eg.Add("Edit", "w240", ar)
    eg.Add("Text", , "Direction:")
    ddl := eg.Add("DropDownList", "w240 Choose" dirIdx,
        ["<->  Both ways", "EN->AR  English to Arabic only", "AR->EN  Arabic to English only"])
    eg.Add("Button", "w100 default", "OK").OnEvent("Click", OnOK)
    eg.Show()

    OnOK(*) {
        if (eE.Value = "" || eA.Value = "") {
            MsgBox("Both fields are required.")
            return
        }
        label := DirLabels()[ddl.Value]
        if isEdit
            lv.Modify(row, "", eE.Value, eA.Value, label)
        else
            lv.Add("", eE.Value, eA.Value, label)
        eg.Destroy()
    }
}

; ================== System functions ==================

LoadSettings() {
    global ConfigFile, SoundEnabled, StartWithWindows, CurrentHotkey, RunAsAdminSetting

    if !FileExist(ConfigFile) {
        SafeIniWrite("#+a", ConfigFile, "Settings", "Hotkey")
        SafeIniWrite("0", ConfigFile, "Settings", "SoundEnabled")
        SafeIniWrite("1", ConfigFile, "Settings", "StartWithWindows")
        SafeIniWrite("0", ConfigFile, "Settings", "RunAsAdmin")
    }

    CurrentHotkey := IniRead(ConfigFile, "Settings", "Hotkey", "#+a")
    SoundEnabled := IniRead(ConfigFile, "Settings", "SoundEnabled", "0") = "1" ? true : false
    StartWithWindows := IniRead(ConfigFile, "Settings", "StartWithWindows", "1") = "1" ? true : false
    RunAsAdminSetting := IniRead(ConfigFile, "Settings", "RunAsAdmin", "0") = "1" ? true : false

    ManageStartup(StartWithWindows)
}

ManageStartup(enable) {
    ExePath := A_ScriptFullPath
    LinkFile := A_Startup "\KeyboardRemapper.lnk"

    if enable {
        if !FileExist(LinkFile)
            FileCreateShortcut(ExePath, LinkFile)
    } else {
        if FileExist(LinkFile)
            FileDelete(LinkFile)
    }
}

TogglePause(*) {
    global IsPaused
    IsPaused := !IsPaused
    SetTrayIcon()

    try {
        if (IsPaused)
            A_TrayMenu.Rename("Pause Script", "Resume Script")
        else
            A_TrayMenu.Rename("Resume Script", "Pause Script")
    }
}

RunAsAdmin(*) {
    try {
        if A_IsAdmin
            return

        Run("*RunAs `"" A_ScriptFullPath "`"")
        ExitApp()
    }
}

ShowAbout(*) {
    MsgBox(AppName "`nVersion 1.7`n`nSettings folder:`n" DataDir "`n`nDeveloped with AutoHotkey v2. `nmarwan1@duck.com")
}

; ================== Conversion ==================

; Longest-match lookup: tries the longest sequence first, down to a single character
FindLongest(map, text, pos, maxLen) {
    n := maxLen
    while n >= 1 {
        chunk := SubStr(text, pos, n)
        if map.Has(chunk)
            return {len: n, val: map[chunk]}
        n--
    }
    return ""
}

ConvertText(original, capsOn, &targetLangID) {
    global enToAr, arToEn, MaxEnLen, MaxArLen

    out := ""
    targetLangID := 0
    i := 1
    total := StrLen(original)

    while i <= total {
        remaining := total - i + 1

        ; Arabic -> English
        m := FindLongest(arToEn, original, i, Min(MaxArLen, remaining))
        if m {
            out .= capsOn ? StrUpper(m.val) : m.val
            targetLangID := 0x0409
            i += m.len
            continue
        }

        ; English -> Arabic
        m := FindLongest(enToAr, original, i, Min(MaxEnLen, remaining))
        if m {
            out .= m.val
            targetLangID := 0x0401
            i += m.len
            continue
        }

        out .= SubStr(original, i, 1)
        i += 1
    }

    return out
}

ReplaceSelectedText(*) {
    global IsPaused, SoundEnabled

    if IsPaused
        return

    clipSaved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")

    if !ClipWait(1) {
        A_Clipboard := clipSaved
        return
    }

    original := A_Clipboard
    if (original == "") {
        A_Clipboard := clipSaved
        return
    }

    capsOn := GetKeyState("CapsLock", "T")
    translated := ConvertText(original, capsOn, &targetLangID)

    A_Clipboard := translated
    Sleep 50
    Send("^v")
    Sleep 50

    if (targetLangID != 0)
        SetKeyboardLanguage(targetLangID)

    if SoundEnabled
        SoundBeep(750, 200)

    A_Clipboard := clipSaved
}

SetKeyboardLanguage(langID) {
    hkl := DllCall("LoadKeyboardLayout", "Str", Format("{:08x}", langID), "UInt", 1, "Ptr")
    PostMessage(0x50, 0, hkl, , "A")
}
