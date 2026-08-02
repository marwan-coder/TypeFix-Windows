; Keyboard_Remapper_Pro_v1.6
; إضافة: خيار "دائماً كمسؤول" في واجهة الإعدادات

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ================== الإعدادات الافتراضية ==================
global AppName := "Keyboard Remapper"
global ConfigFile := A_ScriptDir "\settings.ini"
global IsPaused := false
global CurrentHotkey := ""
global SoundEnabled := false
global StartWithWindows := true
global RunAsAdminSetting := false ; متغير جديد للإعداد

; تعريف الخريطة الافتراضية
global enToAr := Map(
    "q", "ض", "w", "ص", "e", "ث", "r", "ق", "t", "ف", "y", "غ", 
    "u", "ع", "i", "ه", "o", "خ", "p", "ح", "[", "ج", "]", "د", 
    "a", "ش", "s", "س", "d", "ي", "f", "ب", "g", "ل", "h", "ا", 
    "j", "ت", "k", "ن", "l", "م", ";", "ك", "'", "ط", "z", "ئ", 
    "x", "ء", "c", "ؤ", "v", "ر", "b", "لا", "n", "ى", "m", "ة", 
    ",", "و", ".", "ز", "/", "ظ", Chr(96), "ذ", "(", ")", ")", "(", "?", "؟",
    "<", "،", ">", "."
)
global arToEn := Map()

; ================== تهيئة البرنامج ==================
BuildReverseMap()
LoadSettings()

; التحقق: إذا كان الإعداد مفعلاً والسكربت لا يعمل كمسؤول، أعد التشغيل كمسؤول
CheckAdminOnStartup()

SetupTrayMenu()
SetTrayIcon()
RegisterHotkey()

return

; ================== دوال الإعداد ==================

BuildReverseMap() {
    global arToEn, enToAr
    arToEn := Map()
    for k, v in enToAr
        arToEn[v] := k
}

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
    A_TrayMenu.Add("Run as Administrator", RunAsAdmin) ; تشغيل يدوي لمرة واحدة
    A_TrayMenu.Add()
    A_TrayMenu.Add("Settings", ShowSettingsGUI)
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
    global CurrentHotkey
    if (CurrentHotkey != "")
        Hotkey(CurrentHotkey, ReplaceSelectedText, "Off")
    
    hk := IniRead(ConfigFile, "Settings", "Hotkey", "#+a")
    
    try Hotkey(hk, ReplaceSelectedText, "On")
    catch {
        MsgBox("Invalid Hotkey: " hk ". Reverting to default Win+Shift+A.")
        hk := "#+a"
        Hotkey(hk, ReplaceSelectedText, "On")
    }
    CurrentHotkey := hk
}

; ================== واجهة الإعدادات (GUI) ==================

ShowSettingsGUI(*) {
    global CurrentHotkey, SoundEnabled, StartWithWindows, RunAsAdminSetting
    
    sg := Gui("+Owner", "Settings - " AppName)
    sg.SetFont("s10")
    
    tab := sg.AddTab3("w400 h320", ["General", "Key Mappings"]) ; زيادة بسيطة في الارتفاع
    
    tab.UseTab(1)
    
    sg.Add("Text", "x20 y50", "Toggle Shortcut:")
    edHotkey := sg.Add("Edit", "x150 y45 w150", CurrentHotkey)
    sg.Add("Text", "x305 y50", "(e.g. #+a)")
    
    chkSound := sg.Add("CheckBox", "x20 y90", "Enable Sound Feedback")
    chkSound.Value := SoundEnabled
    
    chkStartup := sg.Add("CheckBox", "x20 y120", "Run at Windows Startup")
    chkStartup.Value := StartWithWindows
    
    ; إضافة الخيار الجديد هنا
    chkAdmin := sg.Add("CheckBox", "x20 y150", "Always Run as Administrator")
    chkAdmin.Value := RunAsAdminSetting
    
    sg.Add("Button", "x150 y270 w100 default", "Save").OnEvent("Click", SaveSettings)
    
    tab.UseTab(2)
    
    sg.Add("Text", "x20 y50", "Double click a row to edit.")
    
    lv := sg.Add("ListView", "x20 y80 w360 h180", ["English", "Arabic"])
    lv.ModifyCol(1, 150)
    lv.ModifyCol(2, 150)
    
    global enToAr
    for k, v in enToAr
        lv.Add("", k, v)
    
    lv.OnEvent("DoubleClick", EditKeyMap)
    
    btnReset := sg.Add("Button", "x280 y270 w100", "Reset to Default")
    btnReset.OnEvent("Click", ResetMappings)
    
    sg.Show()
    
    SaveSettings(*) {
        global CurrentHotkey, SoundEnabled, StartWithWindows, enToAr, arToEn, RunAsAdminSetting
        
        newHk := edHotkey.Value
        SoundEnabled := chkSound.Value
        StartWithWindows := chkStartup.Value
        
        ; حفظ القيمة الجديدة
        NewAdminSetting := chkAdmin.Value
        
        IniWrite(newHk, ConfigFile, "Settings", "Hotkey")
        IniWrite(SoundEnabled, ConfigFile, "Settings", "SoundEnabled")
        IniWrite(StartWithWindows, ConfigFile, "Settings", "StartWithWindows")
        IniWrite(NewAdminSetting, ConfigFile, "Settings", "RunAsAdmin")
        
        Loop LV.GetCount() {
            eng := LV.GetText(A_Index, 1)
            arb := LV.GetText(A_Index, 2)
            IniWrite(arb, ConfigFile, "Mappings", eng)
        }
        
        if (newHk != CurrentHotkey)
            RegisterHotkey()
            
        ManageStartup(StartWithWindows)
        
        LoadSettings() 
        
        MsgBox("Settings Saved!")
        
        ; إذا تم تفعيل خيار المسؤول ولم يكن البرنامج يعمل كمسؤول حالياً، أعد التشغيل
        if (NewAdminSetting && !A_IsAdmin) {
            try {
                Run("*RunAs `"" A_ScriptFullPath "`"")
                ExitApp()
            }
        }
        
        sg.Destroy()
    }
    
    EditKeyMap(LV, RowNum) {
        eng := LV.GetText(RowNum, 1)
        arb := LV.GetText(RowNum, 2)
        
        eg := Gui("+Owner" sg.Hwnd, "Edit Key")
        eg.Add("Text",, "English Key:")
        eE := eg.Add("Edit", "w100", eng)
        eg.Add("Text",, "Arabic Key:")
        eA := eg.Add("Edit", "w100", arb)
        eg.Add("Button", "default", "OK").OnEvent("Click", (*) => (LV.Modify(RowNum, "", eE.Value, eA.Value), eg.Destroy()))
        eg.Show()
    }
    
    ResetMappings(*) {
        Loop LV.GetCount()
            LV.Delete()
            
        defaultMap := Map(
            "q", "ض", "w", "ص", "e", "ث", "r", "ق", "t", "ف", "y", "غ", 
            "u", "ع", "i", "ه", "o", "خ", "p", "ح", "[", "ج", "]", "د", 
            "a", "ش", "s", "س", "d", "ي", "f", "ب", "g", "ل", "h", "ا", 
            "j", "ت", "k", "ن", "l", "م", ";", "ك", "'", "ط", "z", "ئ", 
            "x", "ء", "c", "ؤ", "v", "ر", "b", "لا", "n", "ى", "m", "ة", 
            ",", "و", ".", "ز", "/", "ظ", Chr(96), "ذ", "(", ")", ")", "(", "?", "؟",
            "<", "،", ">", "."
        )
        
        for k, v in defaultMap
            LV.Add("", k, v)
            
        MsgBox("List reset to default. Click Save to apply.")
    }
}

; ================== دوال النظام ==================

LoadSettings() {
    global ConfigFile, SoundEnabled, StartWithWindows, CurrentHotkey, enToAr, arToEn, RunAsAdminSetting
    
    if !FileExist(ConfigFile) {
        IniWrite("#+a", ConfigFile, "Settings", "Hotkey")
        IniWrite("0", ConfigFile, "Settings", "SoundEnabled")
        IniWrite("1", ConfigFile, "Settings", "StartWithWindows")
        IniWrite("0", ConfigFile, "Settings", "RunAsAdmin") ; قيمة افتراضية
        for k, v in enToAr
            IniWrite(v, ConfigFile, "Mappings", k)
    }
    
    CurrentHotkey := IniRead(ConfigFile, "Settings", "Hotkey", "#+a")
    SoundEnabled := IniRead(ConfigFile, "Settings", "SoundEnabled", "0") = "1" ? true : false
    StartWithWindows := IniRead(ConfigFile, "Settings", "StartWithWindows", "1") = "1" ? true : false
    RunAsAdminSetting := IniRead(ConfigFile, "Settings", "RunAsAdmin", "0") = "1" ? true : false
    
    keys := ["q","w","e","r","t","y","u","i","o","p","[","]","a","s","d","f","g","h","j","k","l",";","'","z","x","c","v","b","n","m",",",".","/",Chr(96),"(",")","?","<",">"]
    
    for index, key in keys {
        val := IniRead(ConfigFile, "Mappings", key, "")
        if (val != "")
            enToAr[key] := val
    }
    
    BuildReverseMap()
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
    MsgBox(AppName "`nVersion 1.6`n`nDeveloped with AutoHotkey v2. `nmarwan1@duck.com")
}

; ================== دالة التحويل الأساسية ==================
ReplaceSelectedText(*) {
    global IsPaused, enToAr, arToEn, SoundEnabled
    
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

    translated := ""
    capsOn := GetKeyState("CapsLock", "T")
    targetLangID := 0 

    i := 1
    len := StrLen(original)

    while i <= len {
        char := SubStr(original, i, 1)
        nextChar := (i < len) ? SubStr(original, i + 1, 1) : ""

        if (char = "ل" && nextChar = "ا") {
            newChar := capsOn ? "B" : "b"
            translated .= newChar
            targetLangID := 0x0409
            i += 2
            continue
        }

        if arToEn.Has(char) {
            newChar := arToEn[char]
            if capsOn
                newChar := StrUpper(newChar)
            translated .= newChar
            targetLangID := 0x0409
            i += 1
            continue
        }

        lchar := StrLower(char)
        if enToAr.Has(lchar) {
            newChar := enToAr[lchar]
            if (char != lchar && capsOn)
                newChar := StrUpper(newChar)
            translated .= newChar
            targetLangID := 0x0401
            i += 1
            continue
        }

        translated .= char
        i += 1
    }

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
    PostMessage(0x50, 0, hkl,, "A")
}