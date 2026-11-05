; Floats - floating buttons for your apps.  Needs AutoHotkey v2 (free): https://www.autohotkey.com/download/
;
;   - Every button floats above all windows. Click it: bring that app to the front (opens it if it is
;     not running). Click again while the app is in front: minimise it.
;   - Grouped (the default): the buttons hide behind one Floats button and fan out in a circle around it
;     when you point at it (more rings for many buttons). The button of the app you are using stays out,
;     so one click minimises that app.
;     A button can also be kept on its own, outside the group.
;   - Drag a button anywhere; it remembers the spot. Hover over it to see its name.
;   - Drop a file, folder or shortcut on any button: it becomes a new button.
;   - Drag a button to the bin that appears at the bottom of the screen: it is removed from Floats (the
;     app or file itself is not touched), with Undo. Drag one fan button onto another: they swap places.
;   - Right-click a button (or the tray icon) for: edit, add, manage buttons, start with Windows, exit.
;   - "Manage buttons" adds and removes buttons: pick an installed app, a program, shortcut, file,
;     folder, web address or an already open window, and choose an icon, colour, size and shortcut key.
;   - Starts with Windows (switch it off in the manager or the right-click menu).
;   - Run Floats.ahk again, or "Floats" in the Start menu, to open the manager.
;   - Settings: %AppData%\Floats\floats.ini
;
; It only switches windows and starts programs. It never reads or sends anything from them.

#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent
SetTitleMatchMode 2
CoordMode "Mouse", "Screen"

; --- Command line: --startup (start silently), --data=<folder> (separate settings, for testing) ------
ARG_STARTUP := false, ARG_DATA := "", ARG_PARENT := 0, ARG_LINE := ""
for a in A_Args {
    if (a = "--startup")
        ARG_STARTUP := true
    else if (SubStr(a, 1, 7) = "--data=")
        ARG_DATA := SubStr(a, 8)
    else if (SubStr(a, 1, 9) = "--parent=") {
        ARG_PARENT := Integer(SubStr(a, 10))
        continue
    }
    ARG_LINE .= ' "' a '"'
}

; Restart with "UI Access" (AutoHotkey64_UIA.exe, part of the normal AutoHotkey install). That puts the
; buttons in a layer above every always-on-top window - a full-screen viewer can't cover them - and lets
; the shortcut keys work even when a program running as administrator is in front.
if !A_IsCompiled && !InStr(A_AhkPath, "_UIA") {
    uia := RegExReplace(A_AhkPath, "i)\.exe$", "_UIA.exe")
    if FileExist(uia) {
        try {                                 ; if Windows refuses it, carry on without UI Access
            Run('"' uia '" "' A_ScriptFullPath '"' ARG_LINE ' --parent=' A_ScriptHwnd)
            ExitApp
        }
    }
}

; Already running? Then just ask that copy to open the manager.
WM_SHOW_MANAGER := DllCall("RegisterWindowMessage", "Str", "Floats.ShowManager", "UInt")
DetectHiddenWindows(true)
for hwnd in WinGetList(A_ScriptFullPath " - AutoHotkey ahk_class AutoHotkey") {
    if (hwnd != A_ScriptHwnd && hwnd != ARG_PARENT) {
        if !ARG_STARTUP
            try PostMessage(WM_SHOW_MANAGER, 0, 0, , hwnd)
        ExitApp
    }
}
DetectHiddenWindows(false)

; --- Settings ----------------------------------------------------------------------------------------
DATA_DIR    := ARG_DATA != "" ? ARG_DATA : A_AppData "\Floats"
INI         := DATA_DIR "\floats.ini"
ICON_DIR    := DATA_DIR "\icons"
SHORTCUT_DIR := DATA_DIR "\shortcuts"   ; copies of dropped shortcuts, so a button outlives the original
APP_ICON    := DATA_DIR "\floats.ico"
STARTUP_LNK := A_Startup "\Floats.lnk"
MENU_LNK    := A_Programs "\Floats.lnk"
TEST_MODE   := (ARG_DATA != "")
FIELDS      := ["Name", "AppName", "Opens", "Arguments", "Window", "AutoWindow", "Icon", "IconFill", "Color", "Size"
              , "Hotkey", "ClickHides", "AppWindow", "Show", "Separate", "X", "Y"]
PALETTE     := ["FFFFFF", "1E293B", "0F2A3D", "2563EB", "0891B2", "0D9488", "16A34A", "D97706", "DC2626"
              , "DB2777", "7C3AED", "none"]
DPI         := A_ScreenDPI / 96
; -----------------------------------------------------------------------------------------------------

FLOATS := []          ; the buttons, in manager order
BYHWND := Map()       ; button window -> its float (or the hub)
HOTKEYS := Map()      ; registered shortcut keys
RAISED := 0           ; app window held above full-screen programs while it is in front
MGR := 0              ; the manager window, while open
EDITOR := 0           ; the add/edit window, while open
GROUP_ON := 1         ; buttons hide behind one hub button
HUB := {X: "", Y: "", F: 0, Reach: 0}   ; the hub's spot, the hub itself while there is one, how far its fan reaches
GROUPED := []         ; buttons in the group
EXPANDED := false     ; group popped out?
ACTIVE_F := 0         ; grouped button whose app is in front: it stays out
GROUP_SEEN := 0       ; last time the mouse was over the popped-out group
MENU_OPEN := false
DRAGGING := 0         ; the button being dragged
BIN := 0              ; the bin that shows while a button is dragged
TOAST := 0            ; the message at the bottom of the screen, while it shows

DirCreate(ICON_DIR)
if !FileExist(APP_ICON)
    try MakeAppIcon(APP_ICON)
try TraySetIcon(APP_ICON, , true)
A_IconTip := "Floats"

if FileExist(INI) {
    LoadConfig()
} else {                                       ; first start
    if !TEST_MODE {
        SetStartup(true)
        try FileCreateShortcut(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, MENU_LNK, A_ScriptDir
            , A_IsCompiled ? "" : '"' A_ScriptFullPath '"', "Manage your floating app buttons", APP_ICON)
    }
    SaveConfig()
}

BuildTrayMenu()
BuildButtons()
OnMessage(0x201, OnButtonDown)                 ; WM_LBUTTONDOWN: click or drag
OnMessage(0x205, OnButtonRightUp)              ; WM_RBUTTONUP: menu
OnMessage(0x7E, (*) => SetTimer(BuildButtons, -2000))   ; WM_DISPLAYCHANGE: screens changed
OnMessage(WM_SHOW_MANAGER, (*) => (SetTimer(ShowManager, -1), 0))
try DllCall("ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", WM_SHOW_MANAGER, "UInt", 1, "Ptr", 0)
OnExit(AtExit)
SetTimer(KeepOnTop, 500)
SetTimer(HoverWatch, 100)
SetTimer(WatchActive, 250)
SetTimer(UpdateAppNames, 5000)
if !ARG_STARTUP
    ShowManager()
return


; =====================================================================================================
;  Settings file
; =====================================================================================================
NewFloat() {
    return {Name: "", AppName: "", Opens: "", Arguments: "", Window: "", AutoWindow: "", Icon: "", IconFill: 0
          , Color: "FFFFFF", Size: 56, Hotkey: "", ClickHides: 1, AppWindow: 1, Show: 1, Separate: 0, X: "", Y: ""
          , Gui: 0, R: 0, Learned: 0, Busy: false, Mode: "", Vis: false, CX: "", CY: "", A: 255
          , TX: "", TY: "", TA: 255}           ; CX/CY/A: where it is now (and how visible), TX/TY/TA: where it is going
}

LoadConfig() {
    global FLOATS := [], GROUP_ON
    try secs := IniRead(INI)
    catch
        return
    GROUP_ON := IniRead(INI, "App", "Group", 1) ? 1 : 0
    for k in ["X", "Y"]
        HUB.%k% := IsInteger(v := IniRead(INI, "App", "Hub" k, "")) ? Integer(v) : ""
    for sec in StrSplit(secs, "`n", "`r") {
        if !RegExMatch(sec, "i)^Float\d+$")
            continue
        f := NewFloat(), def := NewFloat()
        for k in FIELDS {
            v := IniRead(INI, sec, k, Chr(1))
            if (v != Chr(1))
                f.%k% := v
        }
        for k in ["IconFill", "Size", "ClickHides", "AppWindow", "Show", "Separate"]
            f.%k% := IsInteger(f.%k%) ? Integer(f.%k%) : def.%k%
        for k in ["X", "Y"]
            f.%k% := IsInteger(f.%k%) ? Integer(f.%k%) : ""
        f.Size := Min(160, Max(24, f.Size))
        f.IconFill := (f.IconFill >= 0 && f.IconFill <= 2) ? f.IconFill : 0
        f.Color := (f.Color = "none") ? "none" : StrUpper(f.Color)
        FLOATS.Push(f)
    }
}

SaveConfig() {
    txt := "; Floats settings. Easiest to change with the Floats manager (run Floats.ahk).`r`n[App]`r`nVersion=1`r`n"
        . "Group=" GROUP_ON "`r`nHubX=" HUB.X "`r`nHubY=" HUB.Y "`r`n"
    for i, f in FLOATS {
        txt .= "`r`n[Float" i "]`r`n"
        for k in FIELDS {
            v := RegExReplace(String(f.%k%), "[\r\n]+", " ")
            if RegExMatch(v, "^[`"']")         ; Windows strips quotes around ini values: protect them
                v := '"' v '"'
            txt .= k "=" v "`r`n"
        }
    }
    try {
        fo := FileOpen(INI ".tmp", "w", "UTF-16")
        fo.Write(txt), fo.Close()
        FileMove(INI ".tmp", INI, 1)
    } catch as e {
        TrayTip("Couldn't save the settings: " e.Message, "Floats", 3)
    }
}

; =====================================================================================================
;  The floating buttons
; =====================================================================================================
; Button modes: "solo" (on its own, at its own spot), "hub" (the Floats button the group hides behind),
; "group" (pops out of the hub), "hub-solo" (the only grouped button: shown by itself at the hub's spot).
BuildButtons(*) {
    global GROUPED, EXPANDED, ACTIVE_F
    Critical("On")
    DestroyButtons()
    GROUPED := [], EXPANDED := false, ACTIVE_F := 0
    solo := [], taken := [], todo := []
    for f in FLOATS {
        f.Mode := "", f.Vis := false
        if !f.Show
            continue
        f.R := RenderButton(f, Round(f.Size * DPI), true)
        if (GROUP_ON && !f.Separate)
            GROUPED.Push(f), f.Mode := "group"
        else
            solo.Push(f), f.Mode := "solo"
    }
    atHub := 0
    if (GROUPED.Length = 1) {
        atHub := GROUPED.Pop(), atHub.Mode := "hub-solo"
    } else if (GROUPED.Length > 1) {
        atHub := NewFloat(), atHub.Name := "Floats", atHub.Icon := "*floats", atHub.IconFill := 2, atHub.Mode := "hub"
        atHub.R := RenderButton(atHub, Round(56 * DPI), true)
    }
    HUB.F := (atHub && atHub.Mode = "hub") ? atHub : 0
    if atHub {
        W := atHub.R.w
        if (HUB.X != "" && HUB.Y != "" && OnSomeScreen(HUB.X + W // 2, HUB.Y + W // 2))
            taken.Push([HUB.X, HUB.Y, W])
        else
            HUB.X := ""
    }
    for f in solo {
        W := f.R.w
        if (f.X != "" && f.Y != "" && OnSomeScreen(f.X + W // 2, f.Y + W // 2))
            taken.Push([f.X, f.Y, W])
        else
            todo.Push(f)
    }
    if (atHub && HUB.X = "") {                  ; new spots: lowest free spot, bottom-right upwards
        p := FreeSpot(atHub.R.w, taken)
        HUB.X := p.x, HUB.Y := p.y
        taken.Push([p.x, p.y, atHub.R.w])
    }
    for f in todo {
        p := FreeSpot(f.R.w, taken)
        f.X := p.x, f.Y := p.y
        taken.Push([p.x, p.y, f.R.w])
    }
    for f in solo
        MakeButtonWindow(f, f.X, f.Y)
    if atHub
        MakeButtonWindow(atHub, HUB.X, HUB.Y)
    for f in GROUPED
        MakeButtonWindow(f)                     ; hidden until it pops out
    WatchActive(true)
    RegisterHotkeys()
    Critical("Off")
}

MakeButtonWindow(f, x := "", y := "") {
    ; WS_EX_LAYERED (smooth round button with shadow) + WS_EX_NOACTIVATE (clicking it never takes the
    ; focus away from the window you are working in, so "is the app in front?" is answered right).
    ; WS_EX_ACCEPTFILES: a file or shortcut dropped on any button is added as a new button.
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080010", "Floats: " f.Name)
    g.OnEvent("DropFiles", OnButtonDrop)
    for m in [0x233, 0x4A, 0x49]                ; UI Access blocks drops from Explorer unless these are let through
        DllCall("ChangeWindowMessageFilterEx", "Ptr", g.Hwnd, "UInt", m, "UInt", 1, "Ptr", 0)
    f.Gui := g
    BYHWND[g.Hwnd] := f
    if (x != "") {
        g.Show("x" x " y" y " w" f.R.w " h" f.R.w " NA")
        ULW(g.Hwnd, f.R, 255, x, y)
        f.Vis := true, f.CX := x, f.CY := y
    }
}

DestroyButtons() {
    global BYHWND
    for hwnd, f in BYHWND {
        try f.Gui.Destroy()
        FreeRender(f.R)
        f.Gui := 0, f.R := 0, f.Vis := false
    }
    BYHWND := Map()
    HUB.F := 0
}

; --- The group --------------------------------------------------------------------------------------
; The grouped buttons pop out in a fan around the hub, opening away from the screen edges: half a circle
; at the side of the screen, a quarter in a corner, a full circle out in the open. Every button has its
; own spot, the same each time, nearest ring first in manager order. A full ring continues in a bigger
; ring around it. While the fan is closed, the button of the app in front stays out, straight above or
; below the hub; when the fan opens it glides to its own spot with the others, and back when it closes.
Expand() {
    global EXPANDED, GROUP_SEEN
    if (EXPANDED || !HUB.F)
        return
    EXPANDED := true, GROUP_SEEN := A_TickCount
    LayoutGroup()
}

Collapse(*) {
    global EXPANDED
    if !EXPANDED
        return
    EXPANDED := false
    LayoutGroup()
}

LayoutGroup() {                                 ; send each grouped button out to its spot, or back into the hub
    if !HUB.F
        return
    slots := GroupSlots()
    hw := HUB.F.R.w, cx := HUB.X + hw / 2, cy := HUB.Y + hw / 2, shown := false
    for i, f in GROUPED {
        W := f.R.w
        if (EXPANDED || f = ACTIVE_F) {
            p := EXPANDED ? slots[i] : ActiveSpot(f)
            f.TX := Round(p.x - W / 2), f.TY := Round(p.y - W / 2), f.TA := 255
            if !f.Vis {                         ; it comes out of the hub, fading in
                f.CX := cx - W / 2, f.CY := cy - W / 2, f.A := 0
                ULW(f.Gui.Hwnd, f.R, 0, Round(f.CX), Round(f.CY))
                f.Gui.Show("x" Round(f.CX) " y" Round(f.CY) " w" W " h" W " NA")
                f.Vis := true, shown := true
            }
        } else if f.Vis {                       ; back into the hub, fading out
            f.TX := Round(cx - W / 2), f.TY := Round(cy - W / 2), f.TA := 0
        }
    }
    if shown                                    ; the hub stays on top, so they slide out from under it
        DllCall("SetWindowPos", "Ptr", HUB.F.Gui.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    SetTimer(Animate, 15)
}

Animate() {                                     ; each tick, the moving buttons glide part of the way (ease-out)
    busy := false
    for f in GROUPED {
        if (f = DRAGGING || !f.Vis || !f.Gui || f.TX = "" || (f.CX = f.TX && f.CY = f.TY && f.A = f.TA))
            continue
        dx := f.TX - f.CX, dy := f.TY - f.CY, da := f.TA - f.A
        if (Abs(dx) < 1 && Abs(dy) < 1 && Abs(da) < 6)
            f.CX := f.TX, f.CY := f.TY, f.A := f.TA
        else
            f.CX += dx * 0.4, f.CY += dy * 0.4, f.A += da * 0.4, busy := true
        if (f.TA = 0 && f.A = 0)
            f.Gui.Hide(), f.Vis := false
        else
            ULW(f.Gui.Hwnd, f.R, Round(f.A), Round(f.CX), Round(f.CY))
    }
    if !busy
        SetTimer(Animate, 0)
}

ScreenArea(px, py) {                            ; the usable part of the screen that point is on
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
        if (px >= ml && px < mr && py >= mt && py < mb)
            return {l: ml, t: mt, r: mr, b: mb}
    }
    return {l: 0, t: 0, r: A_ScreenWidth, b: A_ScreenHeight}
}

ActiveSpot(f) {                                 ; fan closed: the centre of the spot for the app in front's button,
    hw := HUB.F.R.w, cx := HUB.X + hw / 2, cy := HUB.Y + hw / 2   ; straight above the hub (below it in the top half)
    W := f.R.w, area := ScreenArea(cx, cy), away := hw / 2 + W / 2 + Round(5 * DPI)
    return {x: Max(area.l + W / 2, Min(area.r - W / 2, cx))
          , y: cy > (area.t + area.b) / 2 ? cy - away : cy + away}
}

GroupSlots() {                                  ; the centre of each grouped button's spot, in manager order
    hw := HUB.F.R.w, cx := HUB.X + hw / 2, cy := HUB.Y + hw / 2
    area := ScreenArea(cx, cy)
    bw := 0                                    ; widest button (with its shadow)
    for f in GROUPED
        bw := Max(bw, f.R.w)
    half := bw / 2, gap := Round(5 * DPI), deg := 0.017453292519943295
    mx := (area.l + area.r) / 2, my := (area.t + area.b) / 2   ; out in the open, the fan faces the middle of the screen
    toMid := (Abs(mx - cx) + Abs(my - cy) < bw) ? 180 : Atan2(my - cy, mx - cx) / deg
    out := [], left := GROUPED.Length, rad := hw / 2 + half + gap, rings := 0
    while (left > 0 && rings < 12) {
        rings++
        rr := RingRoom(cx, cy, rad, half, bw + gap, area)
        if (rr.cap < left) {                    ; would a slightly wider ring hold them all? (neater than one more ring)
            r2 := rad
            while ((r2 += Round(3 * DPI)) <= rad * 1.35)
                if ((t := RingRoom(cx, cy, r2, half, bw + gap, area)).cap >= left) {
                    rad := r2, rr := t
                    break
                }
        }
        if !rr.cap {                            ; no room on this ring at all: try a bigger one
            rad += bw + gap
            continue
        }
        full := rr.full, span := rr.span, need := rr.need, cap := rr.cap, mid := full ? toMid : rr.mid
        n := Min(left, cap)
        ; all round (a full ring, or a first ring of 4 or more): evenly, clockwise from the top like a clock.
        ; Otherwise a fan, a little apart, centred on the open side (or towards the middle of the screen).
        even := full && (n = cap || (out.Length = 0 && n > 3))
        if even
            s := 360 / n, mid := 270 + (n - 1) * s / 2
        else if full
            s := Min(need * 1.12, 360 / n)
        else
            s := (n > 1) ? Min(need * 1.12, span / (n - 1)) : 0
        ring := []
        Loop n {
            a := (mid + (A_Index - (n + 1) / 2) * s) * deg
            ring.Push({x: cx + rad * Cos(a), y: cy + rad * Sin(a)})
        }
        upDown := Abs(Sin(mid * deg)) > Abs(Cos(mid * deg))   ; a fan reads top first (or left first)
        if (!even && n > 1 && (upDown ? ring[1].x > ring[n].x : ring[1].y > ring[n].y))
            Loop n // 2
                t := ring[A_Index], ring[A_Index] := ring[n + 1 - A_Index], ring[n + 1 - A_Index] := t
        for p in ring
            out.Push(p)
        HUB.Reach := rad + half
        left -= n, rad += bw + gap
    }
    while (out.Length < GROUPED.Length)         ; more buttons than the screen can hold: they share the hub's spot
        out.Push({x: cx, y: cy})
    return out
}

; Where on a ring of radius rad around cx,cy buttons fit on the screen: the widest open stretch of
; directions (mid and span in degrees, or full = all round), how many buttons it holds (cap), and the
; angle between neighbours (need) so that they are chord apart.
RingRoom(cx, cy, rad, half, chord, area) {
    deg := 0.017453292519943295, room := [], full := true
    Loop 360 {                                  ; room[d + 1]: does a button fit at d degrees?
        a := (A_Index - 1) * deg, x := cx + rad * Cos(a), y := cy + rad * Sin(a)
        room.Push(fits := (x - half >= area.l && x + half <= area.r && y - half >= area.t && y + half <= area.b))
        if !fits
            full := false
    }
    need := 2 * ASin(Min(1, chord / (2 * rad))) / deg
    if full
        return {full: true, span: 360, mid: 0, need: need, cap: Floor(360 / need)}
    z := 0                                      ; start just after a blocked direction, so no stretch wraps
    for i, v in room
        if !v {
            z := i - 1
            break
        }
    streak := 0, streakAt := 0, best := 0, bestAt := 0
    Loop 360 {
        if room[Mod(z + A_Index, 360) + 1] {
            if (streak = 0)
                streakAt := z + A_Index
            if (++streak > best)
                best := streak, bestAt := streakAt
        } else
            streak := 0
    }
    if !best
        return {full: false, span: 0, mid: 0, need: need, cap: 0}
    return {full: false, span: best - 1, mid: bestAt + (best - 1) / 2, need: need, cap: Floor((best - 1) / need) + 1}
}

Atan2(y, x) => DllCall("msvcrt\atan2", "Double", y, "Double", x, "Cdecl Double")

InGroupArea(mx, my) {                           ; mouse over (or between) the hub and its popped-out buttons
    if !HUB.F
        return false
    hw := HUB.F.R.w, dx := mx - (HUB.X + hw / 2), dy := my - (HUB.Y + hw / 2)
    return Sqrt(dx * dx + dy * dy) <= HUB.Reach + Round(14 * DPI)
}

; Four times a second: which grouped button's app is in front? That one stays out next to the hub.
WatchActive(force := false) {
    global ACTIVE_F
    static last := 0
    a := WinExist("A")
    if (a = last && !force)
        return
    last := a
    owner := 0
    if a
        for f in GROUPED
            if OwnsWindow(f, a) {
                owner := f
                break
            }
    if (owner != ACTIVE_F || force) {
        ACTIVE_F := owner
        if !EXPANDED                            ; (while popped out nothing moves; it settles on closing)
            LayoutGroup()
    }
}

OwnsWindow(f, h) {
    if !IsAppWindow(h)
        return false
    if (f.Window != "")
        return RuleMatches(f.Window, h)
    if (f.Learned = h)
        return true
    if ((exe := DerivedExe(f)) != "") {
        try {
            if (WinGetProcessName(h) = exe)
                return true
        }
    }
    return f.AutoWindow != "" && RuleMatches(f.AutoWindow, h)
}

RuleMatches(rule, h) {
    for part in StrSplit(rule, "||") {
        if ((part := Trim(part)) = "")
            continue
        try {
            if WinExist(part " ahk_id " h)
                return true
        }
    }
    return false
}

SetGrouping(on) {
    global GROUP_ON := on ? 1 : 0
    SaveConfig(), BuildButtons(), RefreshManager()
    UpdateChecks()
}

SetSeparate(f, on) {
    f.Separate := on ? 1 : 0
    if (on && f.Vis && f.Mode = "group")        ; stay where it is now
        f.X := Round(f.CX), f.Y := Round(f.CY)
    SaveConfig(), BuildButtons(), RefreshManager()
}

RegisterHotkeys() {
    global HOTKEYS
    for k in HOTKEYS
        try Hotkey(k, "Off")
    HOTKEYS := Map()
    HOTKEYS.CaseSense := "Off"
    for f in FLOATS {
        if (f.Hotkey = "" || HOTKEYS.Has(f.Hotkey))
            continue
        try {
            Hotkey(f.Hotkey, ToggleFloat.Bind(f), "On")
            HOTKEYS[f.Hotkey] := f
        }
    }
}

; Twice a second: put the buttons back on top (some full-screen programs push themselves above every
; always-on-top window), and once you switch away from an app we held above them, stop holding it there.
KeepOnTop() {
    for hwnd in BYHWND
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    if HUB.F                                    ; last, so it is the top one
        DllCall("SetWindowPos", "Ptr", HUB.F.Gui.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    if (DRAGGING && DRAGGING.Gui)               ; ... unless a button is in your hand
        DllCall("SetWindowPos", "Ptr", DRAGGING.Gui.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    if (RAISED && !WinActive(RAISED))
        Unraise()
}

; Ten times a second: pop the group out while the mouse is on the hub, tuck it back in a moment after
; the mouse leaves, and show a button's name after a short hover.
HoverWatch() {
    global GROUP_SEEN
    static hov := 0, since := 0, shown := false
    MouseGetPos(&mx, &my, &win)
    over := (win && BYHWND.Has(win)) ? BYHWND[win] : 0
    down := GetKeyState("LButton", "P")
    if HUB.F {
        if (over = HUB.F && !EXPANDED && !down)
            Expand()
        if EXPANDED {
            if (MENU_OPEN || DRAGGING || (over && over.Mode != "solo") || InGroupArea(mx, my))
                GROUP_SEEN := A_TickCount
            else if (A_TickCount - GROUP_SEEN > 450)
                Collapse()
        }
    }
    if (over && over.Mode != "hub" && !down) {
        if (win != hov) {
            hov := win, since := A_TickCount
            if shown
                ToolTip(, , , 20), shown := false
        } else if (!shown && A_TickCount - since > (over.Mode = "group" ? 300 : 600)) {
            ToolTip(over.Name (over.Hotkey != "" ? "   (" HotkeyText(over.Hotkey) ")" : ""), , , 20)
            shown := true
        }
    } else if hov {
        hov := 0
        if shown
            ToolTip(, , , 20), shown := false
    }
}

OnButtonDown(wParam, lParam, msg, hwnd) {
    global ACTIVE_F
    if !BYHWND.Has(hwnd)
        return
    f := BYHWND[hwnd]
    ToolTip(, , , 20)
    if DragButton(f, hwnd)                      ; it was dragged, not clicked
        return 0
    if (f.Mode = "hub") {                       ; a click pops the group out
        Expand()
        return 0
    }
    Flash(f)
    if (f.Mode = "group") {
        ACTIVE_F := f                           ; its app is coming to the front: it stays out as the rest tuck in
        SetTimer(Collapse, -160)
    }
    SetTimer(ToggleFloat.Bind(f), -1)           ; own thread: other buttons stay clickable meanwhile
    return 0
}

; The button follows the mouse until it is let go. Returns false if it never really moved (a click).
; A real button shows the bin while it is dragged. Where it is let go decides what happens:
;   on the bin: removed from Floats      in the fan, on another button: the two swap places
;   anywhere else: a button from the fan slides back to its spot; any other button stays there
DragButton(f, hwnd) {
    global DRAGGING, GROUP_SEEN
    MouseGetPos(&mx0, &my0)
    WinGetPos(&x0, &y0, , , hwnd)
    W := f.R.w, dragged := false, onBin := false, swapWith := 0, slots := 0, x := x0, y := y0
    DllCall("SetCapture", "Ptr", hwnd)
    while (GetKeyState("LButton", "P") && BYHWND.Has(hwnd)) {
        MouseGetPos(&mx, &my)
        if !dragged {
            if (Abs(mx - mx0) < 6 && Abs(my - my0) < 6) {
                Sleep(10)
                continue
            }
            dragged := true, DRAGGING := f
            if (f.Mode = "group") {             ; the fan opens (or stays open): it has places to swap with
                Expand()
                slots := GroupSlots()
            }
        }
        x := x0 + mx - mx0, y := y0 + my - my0
        ULW(hwnd, f.R, 255, x, y)
        f.CX := x, f.CY := y, f.A := 255
        if (f.Mode != "hub")
            onBin := BinUpdate(x + W / 2, y + W / 2, hwnd)
        if slots {
            over := onBin ? 0 : SwapTarget(f, slots, x + W / 2, y + W / 2)
            if (over != swapWith) {             ; show the swap: the other button slides to this one's spot
                swapWith := over
                LayoutGroup()
                if swapWith {
                    for i, o in GROUPED
                        if (o = f)
                            home := slots[i]
                    swapWith.TX := Round(home.x - swapWith.R.w / 2), swapWith.TY := Round(home.y - swapWith.R.w / 2)
                }
            }
        }
        Sleep(10)
    }
    DllCall("ReleaseCapture")
    if !dragged
        return false
    DRAGGING := 0, GROUP_SEEN := A_TickCount
    BinHide()
    if !BYHWND.Has(hwnd)                        ; the buttons were rebuilt meanwhile (screens changed)
        return true
    if (onBin && RemoveFloat(f))
        return true
    if (f.Mode = "group") {
        if swapWith {
            SwapInList(FLOATS, f, swapWith), SwapInList(GROUPED, f, swapWith)
            SaveConfig(), RefreshManager()
        }
        LayoutGroup()                           ; everything glides to its spot
    } else if onBin {                           ; (it couldn't be removed) back to where it was
        ULW(hwnd, f.R, 255, x0, y0)
    } else {
        if (f.Mode = "solo")
            f.X := x, f.Y := y
        else                                    ; the hub, or the only grouped button at the hub's spot
            HUB.X := x, HUB.Y := y
        SaveConfig()
        if (f.Mode = "hub")                     ; the group follows the hub
            LayoutGroup()
    }
    return true
}

SwapTarget(f, slots, cx, cy) {                  ; the other fan button whose spot the dragged button is over
    for i, o in GROUPED {
        dx := slots[i].x - cx, dy := slots[i].y - cy
        if (o != f && Sqrt(dx * dx + dy * dy) < o.R.w / 2)
            return o
    }
    return 0
}

SwapInList(list, a, b) {
    ia := 0, ib := 0
    for i, o in list {
        if (o = a)
            ia := i
        else if (o = b)
            ib := i
    }
    if (ia && ib)
        list[ia] := b, list[ib] := a
}

; The bin: at the bottom centre of the screen the mouse is on, only while a button is dragged. It doesn't
; take clicks (the mouse goes straight through). Returns true when the dragged button is over it.
BinUpdate(cx, cy, dragHwnd) {
    global BIN
    if !BIN {
        C := Round(180 * DPI)
        g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080020", "Floats: bin")
        BIN := {Gui: g, C: C, Cold: RenderBin(C, false), Hot: RenderBin(C, true), Vis: false, A: 0, IsHot: false, X: "", Y: ""}
    }
    MouseGetPos(&mx, &my)
    area := ScreenArea(mx, my)
    x := (area.l + area.r - BIN.C) // 2, y := area.b - Round(147 * DPI)
    dx := x + BIN.C / 2 - cx, dy := y + 60 * DPI - cy
    hot := Sqrt(dx * dx + dy * dy) <= 80 * DPI
    if !BIN.Vis {
        ULW(BIN.Gui.Hwnd, BIN.Cold, 0, x, y)
        BIN.Gui.Show("x" x " y" y " w" BIN.C " h" BIN.C " NA")
        DllCall("SetWindowPos", "Ptr", dragHwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        BIN.Vis := true, BIN.A := 0, BIN.X := ""
    }
    if (BIN.A < 255 || hot != BIN.IsHot || x != BIN.X || y != BIN.Y) {   ; fades in; turns red and grows when it's a hit
        BIN.A := Min(255, BIN.A + 64), BIN.IsHot := hot, BIN.X := x, BIN.Y := y
        ULW(BIN.Gui.Hwnd, hot ? BIN.Hot : BIN.Cold, BIN.A, x, y)
    }
    return hot
}

BinHide() {
    if (BIN && BIN.Vis)
        BIN.Gui.Hide(), BIN.Vis := false
}

; A small message at the bottom of the screen for a few seconds, with Undo if there is something to undo.
; done runs when the message ends without Undo.
ShowToast(text, undo := 0, done := 0) {
    global TOAST
    EndToast()
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000", "Floats: message")
    g.BackColor := "1E293B", g.MarginX := Round(18 * DPI), g.MarginY := Round(11 * DPI)
    g.SetFont("s10 cFFFFFF", "Segoe UI")
    g.Add("Text", "0x80", text)                 ; SS_NOPREFIX: an & in a name is just an &
    if undo {
        g.SetFont("s10 bold c7DD3FC")
        g.Add("Text", "x+" Round(16 * DPI) " yp", "Undo").OnEvent("Click", ToastUndo)
    }
    g.Show("Hide")
    g.GetPos(, , &W, &H)
    MouseGetPos(&mx, &my)
    area := ScreenArea(mx, my), c := Round(16 * DPI)
    WinSetRegion("0-0 w" W " h" H " r" c "-" c, g)
    g.Show("x" (area.l + area.r - W) // 2 " y" area.b - H - Round(20 * DPI) " NA")
    TOAST := {Gui: g, Undo: undo, Done: done}
    SetTimer(EndToast, -6000)
}

EndToast(*) {
    global TOAST
    if !TOAST
        return
    t := TOAST, TOAST := 0
    SetTimer(EndToast, 0)
    t.Gui.Destroy()
    if t.Done
        t.Done()
}

ToastUndo(*) {
    global TOAST
    if !TOAST
        return
    t := TOAST, TOAST := 0
    SetTimer(EndToast, 0)
    t.Gui.Destroy()
    t.Undo()
}

ShortName(name) => StrLen(name) > 40 ? SubStr(name, 1, 38) "…" : name

; Takes the button off Floats (the app or file itself is never touched). Undo brings it back.
RemoveFloat(f) {
    if EDITOR {                                 ; it might be the button being edited
        ShowToast("Close the edit window first")
        return false
    }
    row := 0
    for i, o in FLOATS
        if (o = f)
            row := i
    if !row
        return false
    FLOATS.RemoveAt(row)
    SaveConfig(), BuildButtons(), RefreshManager(Min(row, FLOATS.Length))
    ShowToast('Removed "' ShortName(f.Name) '" from Floats', PutBack, (*) => ForgetShortcut(f))
    return true

    PutBack(*) {
        FLOATS.InsertAt(Min(row, FLOATS.Length + 1), f)
        SaveConfig(), BuildButtons(), RefreshManager(row)
    }
}

ForgetShortcut(f) {                             ; a removed button's copy of a dropped shortcut isn't needed any more
    if (InStr(f.Opens, SHORTCUT_DIR "\") != 1)
        return
    for o in FLOATS
        if (o.Opens = f.Opens)
            return
    try FileDelete(f.Opens)
}

; Files, folders or shortcuts dropped on a button: each becomes a new button (at the end of the list).
OnButtonDrop(g, ctrl, files, x, y) {
    SetTimer(AddDropped.Bind(files), -1)        ; own thread: adding rebuilds the window this came from
}

AddDropped(files) {
    added := [], known := [], changed := false
    for path in files {
        f := FloatOpening(path)
        opens := path
        if (!f && path ~= "i)\.(lnk|url)$") {   ; a shortcut: keep a copy, so deleting the original doesn't break it
            opens := KeepShortcut(path)
            f := FloatOpening(opens)
        }
        if f {                                  ; already in Floats (shown again if it was hidden)
            changed := changed || !f.Show
            f.Show := 1, known.Push(f)
            continue
        }
        f := NewFloat(), f.Opens := opens, f.Name := GuessName(path)
        FLOATS.Push(f), added.Push(f), changed := true
    }
    if changed
        SaveConfig(), BuildButtons(), RefreshManager()
    if added.Length {
        ShowToast(added.Length = 1 ? 'Added "' ShortName(added[1].Name) '"' : "Added " added.Length " buttons", TakeBack)
    } else if known.Length {
        ShowToast(known.Length = 1 ? '"' ShortName(known[1].Name) '" is already in Floats' : "These are already in Floats")
        for f in known
            Flash(f)
    }
    return

    TakeBack(*) {
        for f in added {
            for i, o in FLOATS
                if (o = f) {
                    FLOATS.RemoveAt(i)
                    break
                }
            ForgetShortcut(f)
        }
        SaveConfig(), BuildButtons(), RefreshManager()
    }
}

FloatOpening(path) {                            ; the button that already opens this, if any
    for f in FLOATS
        if (f.Opens = path)
            return f
    return 0
}

KeepShortcut(path) {                            ; a copy in Floats' own folder; returns its path
    SplitPath(path, , , &ext, &base)
    dest := SHORTCUT_DIR "\" base "." ext, n := 1
    try {
        DirCreate(SHORTCUT_DIR)
        while FileExist(dest) && FileGetSize(dest) != FileGetSize(path)
            dest := SHORTCUT_DIR "\" base "-" (++n) "." ext
        FileCopy(path, dest, 1)
        return dest
    }
    return path                                 ; couldn't copy: use the original
}

OnButtonRightUp(wParam, lParam, msg, hwnd) {
    global MENU_OPEN, GROUP_SEEN
    if !BYHWND.Has(hwnd)
        return
    f := BYHWND[hwnd]
    ToolTip(, , , 20)
    MENU_OPEN := true
    (f.Mode = "hub" ? HubMenu() : ButtonMenu(f)).Show()
    MENU_OPEN := false, GROUP_SEEN := A_TickCount
    return 0
}

Flash(f) {                                      ; brief dim so a click is visibly felt
    if !f.Gui
        return
    h := f.Gui.Hwnd, r := f.R
    ULW(h, r, 150)
    SetTimer(() => (BYHWND.Has(h) && f.R = r) ? ULW(h, r, 255) : 0, -120)
}

FreeSpot(W, taken) {                           ; lowest free spot in the right-hand column(s)
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
    edge := Round(12 * DPI), step := Round(4 * DPI)
    Loop 10 {
        x := r - edge - W - (A_Index - 1) * W
        y := b - edge - W
        while (y >= t) {
            hit := 0
            for a in taken
                if (x < a[1] + a[3] && a[1] < x + W && y < a[2] + a[3] && a[2] < y + W) {
                    hit := a
                    break
                }
            if !hit
                return {x: x, y: y}
            y := Min(y - step, hit[2] - W)      ; jump just above the button in the way
        }
    }
    return {x: r - edge - W, y: b - edge - W}
}

OnSomeScreen(px, py) {                          ; a saved spot on a screen that is no longer there -> new spot
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (px >= l && px < r && py >= t && py < b)
            return true
    }
    return false
}

ResetPositions(*) {
    for f in FLOATS
        f.X := "", f.Y := ""
    HUB.X := "", HUB.Y := ""
    BuildButtons()
    SaveConfig()
}

HideFloat(f) {
    f.Show := 0
    SaveConfig(), BuildButtons(), RefreshManager()
    TrayTip("The " f.Name " button is hidden. Tick it in Manage buttons to show it again.", "Floats", 1)
}


; =====================================================================================================
;  Menus and start with Windows
; =====================================================================================================
ButtonMenu(f) {
    m := Menu()
    name := StrReplace(f.Name, "&", "&&")
    m.Add("Open / hide " name, (*) => ToggleFloat(f))
    m.Default := "Open / hide " name
    m.Add()
    m.Add("Edit this button…", (*) => EditFloat(f))
    m.Add("Hide this button", (*) => HideFloat(f))
    m.Add("Remove from Floats", (*) => RemoveFloat(f))
    if GROUP_ON {
        m.Add("Keep this button on its own", (*) => SetSeparate(f, !f.Separate))
        if f.Separate
            m.Check("Keep this button on its own")
    }
    m.Add()
    AddCommonItems(m)
    return m
}

HubMenu() {
    m := Menu()
    m.Add("Show the buttons", (*) => Expand())
    m.Default := "Show the buttons"
    m.Add()
    AddCommonItems(m)
    return m
}

AddCommonItems(m) {
    m.Add("Add a button…", (*) => EditFloat(0))
    m.Add("Manage buttons…", (*) => ShowManager())
    m.Add()
    m.Add("Group buttons behind one button", (*) => SetGrouping(!GROUP_ON))
    if GROUP_ON
        m.Check("Group buttons behind one button")
    m.Add("Start with Windows", (*) => SetStartup(!FileExist(STARTUP_LNK)))
    if FileExist(STARTUP_LNK)
        m.Check("Start with Windows")
    m.Add("Reset button positions", ResetPositions)
    m.Add()
    m.Add("Exit Floats", (*) => ExitApp())
}

BuildTrayMenu() {
    tm := A_TrayMenu
    tm.Delete()
    tm.Add("Manage buttons…", (*) => ShowManager())
    tm.Add("Add a button…", (*) => EditFloat(0))
    tm.Add()
    tm.Add("Group buttons behind one button", (*) => SetGrouping(!GROUP_ON))
    tm.Add("Start with Windows", (*) => SetStartup(!FileExist(STARTUP_LNK)))
    tm.Add("Reset button positions", ResetPositions)
    tm.Add()
    tm.Add("Exit", (*) => ExitApp())
    tm.Default := "Manage buttons…"
    tm.ClickCount := 1
    UpdateChecks()
}

SetStartup(on) {
    try {
        if on
            FileCreateShortcut(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, STARTUP_LNK, A_ScriptDir
                , (A_IsCompiled ? "" : '"' A_ScriptFullPath '" ') "--startup", "Floating app buttons", APP_ICON)
        else if FileExist(STARTUP_LNK)
            FileDelete(STARTUP_LNK)
    }
    UpdateChecks()
}

UpdateChecks() {
    on := FileExist(STARTUP_LNK) != ""
    try on ? A_TrayMenu.Check("Start with Windows") : A_TrayMenu.Uncheck("Start with Windows")
    try GROUP_ON ? A_TrayMenu.Check("Group buttons behind one button") : A_TrayMenu.Uncheck("Group buttons behind one button")
    if MGR
        MGR.startup.Value := on, MGR.group.Value := GROUP_ON
}

AtExit(*) {
    if RAISED
        Unraise()
    return 0
}


; =====================================================================================================
;  Bringing the app forward / opening it
; =====================================================================================================
ToggleFloat(f, *) {
    if f.Busy                                   ; still opening from the last click
        return
    if (h := FindAppWindow(f)) {
        f.Learned := h
        if (WinActive(h) && f.ClickHides)
            HideWin(h)
        else
            ShowWin(h)
        return
    }
    before := WinExist("A")
    if !Launch(f)
        return
    f.Busy := true
    try {
        start := A_TickCount
        while (A_TickCount - start < 20000) {   ; up to 20 s for its window to appear
            Sleep(200)
            if (h := FindAppWindow(f)) {
                f.Learned := h
                ShowWin(h)
                return
            }
            ; No window rule: the window that comes to the front is the app's. Remember it for next time.
            if (f.Window = "" && (a := WinExist("A")) && a != before && IsAppWindow(a)) {
                f.Learned := a
                Remember(f, a)
                ShowWin(a)
                return
            }
        }
    } finally {
        f.Busy := false
    }
}

FindAppWindow(f) {
    if (f.Window != "")
        return MatchWindow(f.Window)
    if (f.Learned && DllCall("IsWindow", "Ptr", f.Learned) && IsAppWindow(f.Learned))
        return f.Learned
    if ((exe := DerivedExe(f)) != "" && (h := MatchWindow("ahk_exe " exe)))
        return h
    if (f.AutoWindow != "")
        return MatchWindow(f.AutoWindow)
    return 0
}

MatchWindow(rule) {                             ; "rule || other rule": first real window that matches
    for part in StrSplit(rule, "||") {
        if ((part := Trim(part)) = "")
            continue
        try list := WinGetList(part)
        catch
            continue
        for h in list
            if IsAppWindow(h)
                return h
    }
    return 0
}

IsAppWindow(h) {                                ; a normal window you would see in the taskbar
    static myPid := ProcessExist()
    if !DllCall("IsWindowVisible", "Ptr", h)
        return false
    try {
        if (WinGetPID(h) = myPid || WinGetTitle(h) = "")
            return false
        if (WinGetClass(h) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd|Windows\.UI\.Core\.CoreWindow)$")
            return false
        ex := WinGetExStyle(h)
    } catch
        return false
    if ((ex & 0x80) && !(ex & 0x40000))         ; tool window
        return false
    if (DllCall("GetWindow", "Ptr", h, "UInt", 4, "Ptr") && !(ex & 0x40000))   ; owned pop-up
        return false
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", h, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
    return !cloaked
}

DerivedExe(f) {                                 ; the program whose windows belong to this button, if known
    t := f.Opens, args := f.Arguments
    if (InStr(t, "shell:AppsFolder\") = 1)
        t := SubStr(t, 18)
    else if (t ~= "i)\.lnk$") {
        try FileGetShortcut(t, &target, , &args)
        catch
            return ""
        t := target
    }
    if !RegExMatch(t, "i)([^\\/]+\.exe)$", &m)
        return ""
    if RegExMatch(args, "i)--processStart[= ]+`"?([^`"\s]+\.exe)", &m2)   ; Discord, Slack, ... launchers
        return m2[1]
    if (m[1] ~= "i)^(chrome_proxy|msedge_proxy|pwahelper|update|cmd|powershell|pwsh|wscript|cscript|rundll32|mshta|explorer)\.exe$")
        return ""
    if (args ~= "i)--app")                      ; a browser showing a web app: can't tell its windows apart
        return ""
    return m[1]
}

IsHostExe(exe) {                                ; programs that show many different apps or documents
    return exe ~= "i)^(chrome|msedge|firefox|brave|opera|vivaldi|iexplore|ApplicationFrameHost|explorer|javaw?|pythonw?|WindowsTerminal|conhost|mmc|rundll32|dllhost)\.exe$"
}

Remember(f, h) {
    try {
        exe := WinGetProcessName(h), title := WinGetTitle(h)
    } catch
        return
    f.AutoWindow := IsHostExe(exe) ? title " ahk_exe " exe : "ahk_exe " exe
    SaveConfig()
}

ShowWin(h) {
    global RAISED
    try {
        if (WinGetMinMax(h) = -1)
            WinRestore(h)
        if (RAISED && RAISED != h)
            Unraise()
        if !(WinGetExStyle(h) & 0x8) {          ; above a full-screen viewer while you look at it
            WinSetAlwaysOnTop(1, h)
            RAISED := h
        }
        WinActivate(h)
    }
}

HideWin(h) {
    if (RAISED = h)
        Unraise()
    try WinMinimize(h)
}

Unraise() {
    global RAISED
    try WinSetAlwaysOnTop(0, RAISED)
    RAISED := 0
}

Launch(f) {
    t := f.Opens, args := f.Arguments
    try {
        if IsWeb(t) {
            if (f.AppWindow && (b := FindBrowser()) != "")
                Run('"' b '" --app=' t)
            else
                Run(t)
        } else if (InStr(t, "shell:") = 1) {
            Run('explorer.exe "' t '"')
        } else if IsUri(t) {
            Run(t)
        } else {
            if !FileExist(t)
                throw Error("Can't find " t)
            SplitPath(t, , &dir)
            Run('"' t '"' (args != "" ? " " args : ""), DirExist(t) ? "" : dir)
        }
        return true
    } catch as e {
        MsgBox("Couldn't open " f.Name ".`n`n" e.Message, "Floats", "Icon! 0x40000")
        return false
    }
}

FindBrowser() {                                 ; for web addresses shown as an app window
    for p in [EnvGet("ProgramFiles") "\Google\Chrome\Application\chrome.exe"
            , EnvGet("ProgramFiles(x86)") "\Google\Chrome\Application\chrome.exe"
            , EnvGet("LocalAppData") "\Google\Chrome\Application\chrome.exe"
            , EnvGet("ProgramFiles(x86)") "\Microsoft\Edge\Application\msedge.exe"
            , EnvGet("ProgramFiles") "\Microsoft\Edge\Application\msedge.exe"]
        if FileExist(p)
            return p
    return ""
}

IsWeb(t) => (t ~= "i)^https?://")
IsUri(t) => (t ~= "i)^[a-z][a-z0-9+.-]+:") && !(t ~= "i)^[a-z]:")

GuessName(t) {
    if IsWeb(t)
        return RegExMatch(t, "i)^https?://(?:www\.)?([^/:?#]+)", &m) ? m[1] : t
    if (InStr(t, "shell:") = 1)
        return "App"
    SplitPath(RTrim(t, "\"), , , , &noExt)
    return noExt != "" ? noExt : t
}

; Web apps rename themselves when their site changes, and Windows apps can too. A button named after its app
; follows the new name; a name you typed yourself stays. AppName is what the app was called when last checked.
UpdateAppNames() {
    if (DRAGGING || EXPANDED || EDITOR || MENU_OPEN) {
        SetTimer(UpdateAppNames, 5000)          ; in use right now: look again soon
        return
    }
    SetTimer(UpdateAppNames, 600000)            ; every 10 minutes after the first look
    changed := false, renamed := false
    for f in FLOATS {
        if ((now := AppNameOf(f)) == "" || now == f.AppName)
            continue
        if (f.Name == f.AppName)
            FollowApp(f, now), renamed := true
        f.AppName := now, changed := true
    }
    if changed
        SaveConfig()
    if renamed
        BuildButtons(), RefreshManager()
}

AppIdOf(f) {                                    ; this button's app in Windows' app list; "" if it has none
    if (InStr(f.Opens, "shell:AppsFolder\") = 1)
        return SubStr(f.Opens, 18)
    if (f.Opens ~= "i)\.lnk$") {
        SplitPath(f.Opens, &leaf, &dir)
        try return ComObject("Shell.Application").NameSpace(dir).ParseName(leaf).ExtendedProperty("System.AppUserModel.ID")
    }
    return ""
}

AppNameOf(f) {                                  ; what Windows calls this button's app now; "" if it can't tell
    if ((id := AppIdOf(f)) != "")
        try return ComObject("Shell.Application").NameSpace("shell:AppsFolder").ParseName(id).Name
    return ""
}

FollowApp(f, name) {
    if RegExMatch(f.AutoWindow, "^(.+?)( ahk_exe .+)$", &m)   ; the window's title has most likely changed too
        f.AutoWindow := StrReplace(m[1], f.Name, name) m[2]
    if (InStr(f.Opens, SHORTCUT_DIR "\") = 1) { ; our copy of the shortcut: the manager shows its file name
        old := f.Opens
        SplitPath(old, , &dir, &ext)
        dest := dir "\" RegExReplace(name, '[<>:"/\\|?*]+', "-") "." ext
        if !FileExist(dest) {
            try {
                FileMove(old, dest)
                for o in FLOATS
                    if (o.Opens = old)
                        o.Opens := dest
            }
        }
    }
    f.Name := name
}

HotkeyText(hk) {                                ; "^!d" -> "Ctrl+Alt+D"
    if (hk = "")
        return ""
    names := Map("^", "Ctrl+", "!", "Alt+", "+", "Shift+", "#", "Win+"), out := ""
    while (StrLen(hk) > 1 && names.Has(c := SubStr(hk, 1, 1)))
        out .= names[c], hk := SubStr(hk, 2)
    return out StrUpper(SubStr(hk, 1, 1)) SubStr(hk, 2)
}


; =====================================================================================================
;  Manager window
; =====================================================================================================
ShowManager(*) {
    global MGR
    if MGR {
        MGR.gui.Show()
        try WinActivate(MGR.gui.Hwnd)
        return
    }
    g := Gui("-MaximizeBox", "Floats")
    g.BackColor := "FFFFFF"
    g.MarginX := 20, g.MarginY := 16
    g.SetFont("s15 w600", "Segoe UI")
    g.Add("Text", "xm", "Floating buttons")
    g.SetFont("s10 w400 c5F6B7A")
    g.Add("Text", "xm y+4 w580", "Click a button to bring its app to the front, click again to minimise. Right-click it "
        . "for options. Drop a file or shortcut on a button to add it; drag a button to the bin to remove it.")
    g.SetFont("s10 cDefault")
    lv := g.Add("ListView", "xm y+14 w580 h266 -Multi Checked NoSortHdr LV0x10000", ["Button", "Opens", "Shortcut", "Shows"])
    bAdd := g.Add("Button", "xm y+10 w110", "&Add…")
    bEdit := g.Add("Button", "x+8 w90", "&Edit…")
    bDel := g.Add("Button", "x+8 w90", "&Remove")
    bUp := g.Add("Button", "x+20 w40", "▲")
    bDown := g.Add("Button", "x+6 w40", "▼")
    g.SetFont("s9 c6B7280")
    g.Add("Text", "xm y+8 w580", "Tick a button to show it, untick to hide it. Double-click to edit.")
    g.SetFont("s10 cDefault")
    g.Add("Text", "xm y+12 w580 h1 BackgroundE5E7EB")
    cg := g.Add("Checkbox", "xm y+14 Checked" GROUP_ON, "Group the buttons behind one Floats button")
    g.SetFont("s9 c6B7280")
    g.Add("Text", "xm+20 y+2 w450", "They pop out when you point at it. The button of the app you are using stays out, "
        . "so one click minimises it. To keep a button always visible, edit it and tick ‘Keep on its own’.")
    g.SetFont("s10 cDefault")
    cb := g.Add("Checkbox", "xm y+12", "Start Floats when Windows starts")
    cb.Value := FileExist(STARTUP_LNK) != ""
    bClose := g.Add("Button", "xm+490 yp-5 w90 Default", "Close")

    lv.OnEvent("DoubleClick", (ctl, row) => row ? EditFloat(FLOATS[row]) : 0)
    lv.OnEvent("ItemCheck", MgrItemCheck)
    bAdd.OnEvent("Click", (*) => EditFloat(0))
    bEdit.OnEvent("Click", (*) => (r := MGR.lv.GetNext()) ? EditFloat(FLOATS[r]) : 0)
    bDel.OnEvent("Click", MgrRemove)
    bUp.OnEvent("Click", (*) => MgrMove(-1))
    bDown.OnEvent("Click", (*) => MgrMove(1))
    cb.OnEvent("Click", (c, *) => SetStartup(c.Value))
    cg.OnEvent("Click", (c, *) => SetGrouping(c.Value))
    bClose.OnEvent("Click", MgrClose)
    g.OnEvent("Close", MgrClose)
    g.OnEvent("Escape", MgrClose)
    MGR := {gui: g, lv: lv, startup: cb, group: cg, filling: false}
    RefreshManager(FLOATS.Length ? 1 : 0)
    g.Show()
    try WinActivate(g.Hwnd)
}

MgrClose(*) {
    global MGR
    if MGR {
        MGR.gui.Destroy()
        MGR := 0
    }
}

RefreshManager(sel := 0) {
    if !MGR
        return
    lv := MGR.lv
    if !sel
        sel := lv.GetNext()
    MGR.filling := true
    lv.Opt("-Redraw")
    lv.Delete()
    px := Round(32 * DPI)                       ; the buttons themselves as row icons
    il := DllCall("comctl32\ImageList_Create", "Int", px, "Int", px, "UInt", 0x20, "Int", FLOATS.Length + 1, "Int", 4, "Ptr")
    for f in FLOATS {
        hIcon := RenderToIcon(RenderButton(f, px, false))
        DllCall("comctl32\ImageList_ReplaceIcon", "Ptr", il, "Int", -1, "Ptr", hIcon)
        DllCall("DestroyIcon", "Ptr", hIcon)
    }
    if (old := SendMessage(0x1003, 1, il, lv))  ; LVM_SETIMAGELIST, small icons
        DllCall("comctl32\ImageList_Destroy", "Ptr", old)
    for i, f in FLOATS
        lv.Add("Icon" i (f.Show ? " Check" : ""), f.Name, InStr(f.Opens, "shell:AppsFolder\") = 1 ? "Windows app" : f.Opens
            , HotkeyText(f.Hotkey), !f.Show ? "hidden" : (GROUP_ON && !f.Separate) ? "in group" : "on its own")
    lv.ModifyCol(1, 165), lv.ModifyCol(2, 210), lv.ModifyCol(3, 105), lv.ModifyCol(4, 76)
    if (sel && sel <= FLOATS.Length)
        lv.Modify(sel, "Select Focus Vis")
    lv.Opt("+Redraw")
    MGR.filling := false
}

MgrItemCheck(lv, row, *) {
    if (!MGR || MGR.filling || row < 1 || row > FLOATS.Length)
        return
    checked := (lv.GetNext(row - 1, "Checked") = row)   ; the box as it is now (events can arrive late)
    if (FLOATS[row].Show = checked)
        return
    FLOATS[row].Show := checked
    SaveConfig()
    BuildButtons()
    lv.Modify(row, "Col4", !checked ? "hidden" : (GROUP_ON && !FLOATS[row].Separate) ? "in group" : "on its own")
}

MgrRemove(*) {
    if (row := MGR.lv.GetNext())
        RemoveFloat(FLOATS[row])
}

MgrMove(d) {
    if !(row := MGR.lv.GetNext())
        return
    to := row + d
    if (to < 1 || to > FLOATS.Length)
        return
    FLOATS.InsertAt(to, FLOATS.RemoveAt(row))
    SaveConfig(), RefreshManager(to)
}


; =====================================================================================================
;  Add / edit a button
; =====================================================================================================
EditFloat(orig := 0, *) {
    global EDITOR
    if EDITOR {
        try WinActivate(EDITOR)
        return
    }
    isNew := !IsObject(orig)
    f := NewFloat()
    if !isNew
        for k in FIELDS
            f.%k% := orig.%k%
    state := {color: f.Color, autoName: isNew ? "" : Chr(1)}
    owner := MGR ? MGR.gui : 0
    g := Gui((owner ? "+Owner" owner.Hwnd " " : "") "-MinimizeBox -MaximizeBox", isNew ? "Add a button" : "Edit button")
    gh := g.Hwnd
    g.BackColor := "FFFFFF"
    g.MarginX := 20, g.MarginY := 16
    g.SetFont("s10", "Segoe UI")
    AddLabel(text, opt := "y+14") => g.Add("Text", "xm w84 " opt, text)
    AddHint(text) {
        g.SetFont("s9 c6B7280")
        h := g.Add("Text", "xm+94 y+3 w520", text)
        g.SetFont("s10 cDefault")
        return h
    }

    AddLabel("Opens", "y19")
    eOpens := g.Add("Edit", "x+10 yp-3 w300", f.Opens)
    bApps := g.Add("Button", "x+8 yp-1 w64", "Apps…")
    bFile := g.Add("Button", "x+4 w64", "File…")
    bFolder := g.Add("Button", "x+4 w64", "Folder…")
    AddHint("An installed app, a program, shortcut, file or folder, or a web address (https://…).")
    AddLabel("Name")
    eName := g.Add("Edit", "x+10 yp-3 w300", f.Name)
    AddLabel("Window")
    eWin := g.Add("Edit", "x+10 yp-3 w300", f.Window)
    bPick := g.Add("Button", "x+8 yp-1 w64", "Pick…")
    AddHint("Optional: which window to bring forward. Leave blank and Floats finds it by itself.")
    AddLabel("Arguments")
    eArgs := g.Add("Edit", "x+10 yp-3 w300", f.Arguments)
    AddHint("Optional: extra command-line options for a program.")
    cHide := g.Add("Checkbox", "xm+94 y+12 Checked" f.ClickHides, "Clicking again minimises the window")
    cApp := g.Add("Checkbox", "xm+94 y+6 Checked" f.AppWindow, "Open web addresses in their own app window (Chrome or Edge)")
    cSep := g.Add("Checkbox", "xm+94 y+6 Checked" f.Separate, "Keep on its own: always visible, not hidden in the group")
    g.Add("Text", "xm y+14 w614 h1 BackgroundE5E7EB")

    lIcon := AddLabel("Icon", "y+16 Section")
    eIcon := g.Add("Edit", "x+10 yp-3 w220", f.Icon)
    bIcon := g.Add("Button", "x+8 yp-1 w76", "Choose…")
    bIconDef := g.Add("Button", "x+4 w64", "Default")
    AddHint("Blank = the app's own icon. Or a picture: PNG, JPG, ICO…")
    AddLabel("Shape", "y+12")
    dShape := g.Add("DropDownList", "x+10 yp-3 w300 AltSubmit Choose" (f.IconFill + 1)
        , ["Automatic: square logos are cropped round", "Always crop the logo round", "Keep the logo's own shape"])
    AddLabel("Colour", "y+16")
    sw := Map(), sw.CaseSense := "Off"
    for i, c in PALETTE {
        s := g.Add("Text", (i = 1 ? "x+10 yp-2" : "x+3") " w22 h22 Center 0x200 Background" (c = "none" ? "FFFFFF" : c)
            . ((c = "FFFFFF" || c = "none") ? " Border" : ""), c = "none" ? "×" : "")
        s.OnEvent("Click", PickColor.Bind(c))
        sw[c] := s
    }
    bMore := g.Add("Button", "x+8 yp-1 w64 h25", "More…")
    AddLabel("Size", "xm y+16")
    eSize := g.Add("Edit", "x+10 yp-3 w60 Number", f.Size)
    g.Add("UpDown", "Range24-160", f.Size)
    g.Add("Text", "x+6 yp+3", "px")
    AddLabel("Shortcut", "xm y+16")
    hk := g.Add("Hotkey", "x+10 yp-3 w170 Limit1", f.Hotkey)
    bHkClear := g.Add("Button", "x+8 yp-1 w64", "Clear")
    hHk := AddHint("Optional: a key combination that works like clicking the button.")
    pv := g.Add("Text", "xs+490 ys w124 h124 0x20E")          ; SS_BITMAP | SS_CENTERIMAGE
    g.SetFont("s9 c6B7280")
    g.Add("Text", "xs+490 y+0 w124 Center", "Preview")
    g.SetFont("s10 cDefault")
    hHk.GetPos(, &hy, , &hh), pv.GetPos(, &py, , &ph)
    sepY := Max(hy + hh, py + ph + 20) + 14
    g.Add("Text", "xm y" sepY " w614 h1 BackgroundE5E7EB")
    bSave := g.Add("Button", "xm+426 y+14 w90 Default", "Save")
    bCancel := g.Add("Button", "x+8 w90", "Cancel")
    marker := g.Add("Text", "x0 y0 w22 h3 Background2563EB")   ; underlines the chosen colour

    SendMessage(0x1501, 1, StrPtr("e.g. C:\Program Files\App\app.exe  or  https://example.com"), eOpens)
    SendMessage(0x1501, 1, StrPtr(f.AutoWindow != "" ? "Automatic (found: " f.AutoWindow ")" : "Automatic"), eWin)
    SendMessage(0x1501, 1, StrPtr("The app's own icon"), eIcon)

    for c in [eOpens, eName, eIcon, eSize]
        c.OnEvent("Change", UpdatePreview)
    dShape.OnEvent("Change", UpdatePreview)
    bApps.OnEvent("Click", DoApps)
    bFile.OnEvent("Click", DoFile)
    bFolder.OnEvent("Click", DoFolder)
    bPick.OnEvent("Click", DoPick)
    bIcon.OnEvent("Click", DoIcon)
    bIconDef.OnEvent("Click", (*) => (eIcon.Value := "", dShape.Choose(1), UpdatePreview()))
    bMore.OnEvent("Click", DoMoreColor)
    bHkClear.OnEvent("Click", (*) => hk.Value := "")
    bSave.OnEvent("Click", DoSave)
    bCancel.OnEvent("Click", Close)
    g.OnEvent("Close", Close)
    g.OnEvent("Escape", Close)

    MarkSwatch()
    DoPreview()
    EDITOR := g.Hwnd
    Suspend(true)                               ; so shortcut keys can be typed into the Shortcut box
    if isNew
        eOpens.Focus()
    RunModal(g, owner)
    Suspend(false)
    return

    ; --- helpers (they share the variables above) ---
    SetOpens(opens, name := "") {
        eOpens.Value := opens
        if (name != "" && (Trim(eName.Value) = "" || eName.Value = state.autoName))
            eName.Value := name, state.autoName := name
        UpdatePreview()
    }
    DoApps(*) {
        if (a := PickApp(g))
            SetOpens(a.opens, a.name), eWin.Value := ""
    }
    DoFile(*) {
        g.Opt("+OwnDialogs")
        if ((p := FileSelect(35, , "Choose a program, shortcut or file")) != "")
            SetOpens(p, GuessName(p)), eWin.Value := ""
    }
    DoFolder(*) {
        g.Opt("+OwnDialogs")
        if ((p := DirSelect(, 1, "Choose a folder")) != "")
            SetOpens(p, GuessName(p)), eWin.Value := ""
    }
    DoPick(*) {
        if !(w := PickWindow(g))
            return
        eWin.Value := w.rule
        if (Trim(eOpens.Value) = "" && w.path != "" && !IsHostExe(w.exe))
            SetOpens(w.path, GuessName(w.path))
        else if (Trim(eName.Value) = "")
            eName.Value := w.title
    }
    DoIcon(*) {
        g.Opt("+OwnDialogs")
        p := FileSelect(3, , "Choose an icon or picture", "Pictures and icons (*.png; *.jpg; *.jpeg; *.bmp; *.gif; *.ico; *.exe; *.dll)")
        if (p != "") {
            eIcon.Value := p
            UpdatePreview()
        }
    }
    PickColor(c, *) {
        state.color := c
        MarkSwatch(), UpdatePreview()
    }
    DoMoreColor(*) {
        if ((c := ChooseColorDlg(g.Hwnd, state.color)) != "")
            PickColor(c)
    }
    MarkSwatch() {
        if sw.Has(state.color) {
            sw[state.color].GetPos(&x, &y, &w, &h)
            marker.Move(x, y + h + 2)
            marker.Visible := true
        } else
            marker.Visible := false
    }
    UpdatePreview(*) => SetTimer(DoPreview, -150)
    DoPreview() {
        if !DllCall("IsWindow", "Ptr", gh)
            return
        t := Collect()
        r := RenderButton(t, Round(t.Size * DPI), true)
        hbm := OnBackground(r, Round(124 * DPI), 0xFFFFFF)
        FreeRender(r)
        old := SendMessage(0x172, 0, hbm, pv)   ; STM_SETIMAGE
        if (old && old != hbm)
            DllCall("DeleteObject", "Ptr", old)
        if (SendMessage(0x173, 0, 0, pv) != hbm)   ; the control kept a copy
            DllCall("DeleteObject", "Ptr", hbm)
    }
    Collect() {
        t := NewFloat()
        for k in FIELDS
            t.%k% := f.%k%
        t.Name := Trim(eName.Value), t.Opens := Trim(eOpens.Value), t.Arguments := Trim(eArgs.Value)
        t.Window := Trim(eWin.Value), t.ClickHides := cHide.Value, t.AppWindow := cApp.Value, t.Separate := cSep.Value
        t.Icon := Trim(eIcon.Value, " `t`""), t.IconFill := dShape.Value - 1, t.Color := state.color
        t.Size := IsInteger(eSize.Value) ? Min(160, Max(24, Integer(eSize.Value))) : 56
        t.Hotkey := hk.Value
        return t
    }
    DoSave(*) {
        g.Opt("+OwnDialogs")
        t := Collect()
        t.Opens := Trim(t.Opens, " `t`"")
        if (t.Opens = "") {
            MsgBox("Choose what this button opens.", "Floats", "Icon!")
            eOpens.Focus()
            return
        }
        if (t.Opens ~= "i)^www\.")
            t.Opens := "https://" t.Opens
        if !(IsWeb(t.Opens) || IsUri(t.Opens) || FileExist(t.Opens))
            if (MsgBox("Can't find:`n" t.Opens "`n`nSave anyway?", "Floats", "YesNo Icon!") != "Yes")
                return
        if (t.Name = "")
            t.Name := GuessName(t.Opens)
        if (t.Hotkey != "") {
            for o in FLOATS
                if (o != orig && o.Hotkey = t.Hotkey) {
                    MsgBox(HotkeyText(t.Hotkey) " is already used by the " o.Name " button.", "Floats", "Icon!")
                    return
                }
            try Hotkey(t.Hotkey, (*) => 0, "Off")
            catch {
                MsgBox(HotkeyText(t.Hotkey) " can't be used as a shortcut.", "Floats", "Icon!")
                return
            }
        }
        if (t.Icon = "" && IsWeb(t.Opens)) {    ; a website: try its own icon
            ToolTip("Getting the website's icon…")
            if ((p := FetchSiteIcon(t.Opens)) != "")
                t.Icon := p
            ToolTip()
        }
        if (t.Icon != "" && FileExist(t.Icon) && InStr(t.Icon, ICON_DIR "\") != 1 && t.Icon ~= "i)\.(png|jpe?g|bmp|gif|ico)$") {
            SplitPath(t.Icon, , , &ext, &base)  ; keep a copy, so the picture can't go missing
            dest := ICON_DIR "\" base "." ext, n := 1
            while FileExist(dest) && FileGetSize(dest) != FileGetSize(t.Icon)
                dest := ICON_DIR "\" base "-" (++n) "." ext
            try FileCopy(t.Icon, dest, 1), t.Icon := dest
        }
        if (t.Opens != f.Opens || t.Window != f.Window || t.Arguments != f.Arguments)
            t.AutoWindow := ""
        if (t.Opens != f.Opens)
            t.AppName := ""                     ; a different app: its name is looked up afresh
        target := isNew ? NewFloat() : orig
        for k in FIELDS
            target.%k% := t.%k%
        target.Learned := 0
        if isNew
            FLOATS.Push(target)
        Close()
        SaveConfig(), BuildButtons()
        for i, o in FLOATS
            if (o = target)
                RefreshManager(i)
    }
    Close(*) {
        global EDITOR
        try DllCall("DeleteObject", "Ptr", SendMessage(0x173, 0, 0, pv))
        g.Destroy()
        EDITOR := 0
    }
}

RunModal(g, owner) {                            ; show g and wait until it is closed
    if owner
        owner.Opt("+Disabled")
    g.Show()
    WinWaitClose(g.Hwnd)
    if owner {
        owner.Opt("-Disabled")
        try WinActivate(owner.Hwnd)
    }
}

; Choose from the installed apps (the Start menu's "All apps" list, including Store apps).
PickApp(owner) {
    res := {v: 0}, apps := [], shown := [], rowOf := Map(), next := {i: 1}
    try {
        for it in ComObject("Shell.Application").NameSpace("shell:AppsFolder").Items()
            apps.Push({name: it.Name, path: it.Path, icon: -1})
    }
    s := ""
    for i, a in apps
        s .= StrReplace(a.name, "`t", " ") "`t" i "`n"
    sorted := []
    for line in StrSplit(Sort(RTrim(s, "`n")), "`n")
        if (line != "")
            sorted.Push(apps[Integer(SubStr(line, InStr(line, "`t", , -1) + 1))])
    apps := sorted

    g := Gui("+Owner" owner.Hwnd " -MinimizeBox", "Choose an app")
    g.BackColor := "FFFFFF"
    g.MarginX := 16, g.MarginY := 14
    g.SetFont("s10", "Segoe UI")
    g.Add("Text", "xm y17", "Search")
    q := g.Add("Edit", "x+10 yp-3 w380")
    lv := g.Add("ListView", "xm y+10 w440 r15 -Multi -Hdr +0x40", ["App"])   ; LVS_SHAREIMAGELISTS
    lvHwnd := lv.Hwnd
    SendMessage(0x1003, 1, SysImageList(), lv)
    bOK := g.Add("Button", "xm+256 y+12 w90 Default", "OK")
    bCancel := g.Add("Button", "x+8 w90", "Cancel")
    SendMessage(0x1501, 1, StrPtr("Type part of the app's name"), q)

    Fill(*) {
        lv.Opt("-Redraw"), lv.Delete(), shown.Length := 0, rowOf.Clear()
        term := Trim(q.Value)
        for a in apps
            if (term = "" || InStr(a.name, term)) {
                shown.Push(a), rowOf[a] := shown.Length
                lv.Add(a.icon >= 0 ? "Icon" (a.icon + 1) : "Icon9999", a.name)
            }
        if shown.Length
            lv.Modify(1, "Select Focus")
        lv.Opt("+Redraw")
    }
    LoadIcons() {                               ; icons a few at a time, so the window opens at once
        n := 0
        while (next.i <= apps.Length && n < 25) {
            if !DllCall("IsWindow", "Ptr", lvHwnd) {   ; picker closed meanwhile
                SetTimer(LoadIcons, 0)
                return
            }
            a := apps[next.i++], n++
            a.icon := SysIconIndex(PathOf(a))
            if rowOf.Has(a)
                try lv.Modify(rowOf[a], "Icon" (a.icon + 1))
        }
        if (next.i > apps.Length)
            SetTimer(LoadIcons, 0)
    }
    PathOf(a) => (a.path ~= "^[A-Za-z]:\\") ? a.path : "shell:AppsFolder\" a.path
    Choose(*) {
        if !(row := lv.GetNext())
            return
        a := shown[row]
        res.v := {name: a.name, opens: (a.path ~= "^[A-Za-z]:\\" && FileExist(a.path)) ? a.path : "shell:AppsFolder\" a.path}
        g.Destroy()
    }
    q.OnEvent("Change", Fill)
    lv.OnEvent("DoubleClick", Choose)
    bOK.OnEvent("Click", Choose)
    bCancel.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    Fill()
    SetTimer(LoadIcons, 20)
    RunModal(g, owner)
    SetTimer(LoadIcons, 0)
    return res.v
}

; Choose one of the windows that are open now.
PickWindow(owner) {
    res := {v: 0}, wins := []
    g := Gui("+Owner" owner.Hwnd " -MinimizeBox", "Pick a window")
    g.BackColor := "FFFFFF"
    g.MarginX := 16, g.MarginY := 14
    g.SetFont("s10", "Segoe UI")
    g.Add("Text", "w560", "Choose the app's window. Not listed? Open the app, then press Refresh.")
    lv := g.Add("ListView", "w560 r12 -Multi", ["Window", "Program"])
    bOK := g.Add("Button", "xm+278 y+12 w90 Default", "OK")
    bRefresh := g.Add("Button", "x+8 w90", "Refresh")
    bCancel := g.Add("Button", "x+8 w90", "Cancel")

    Fill(*) {
        lv.Delete(), wins.Length := 0
        for h in WinGetList() {
            if !IsAppWindow(h)
                continue
            try {
                title := WinGetTitle(h), exe := WinGetProcessName(h)
                path := ""
                try path := WinGetProcessPath(h)
            } catch
                continue
            wins.Push({title: title, exe: exe, path: path})
            lv.Add(, title, exe)
        }
        lv.ModifyCol(1, 400), lv.ModifyCol(2, 140)
    }
    Choose(*) {
        if !(row := lv.GetNext())
            return
        w := wins[row]
        w.rule := (IsHostExe(w.exe) ? w.title " ahk_exe " : "ahk_exe ") w.exe
        res.v := w
        g.Destroy()
    }
    lv.OnEvent("DoubleClick", Choose)
    bOK.OnEvent("Click", Choose)
    bRefresh.OnEvent("Click", Fill)
    bCancel.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    Fill()
    RunModal(g, owner)
    return res.v
}

ChooseColorDlg(hwndOwner, init) {               ; Windows' colour picker; returns "RRGGBB" or ""
    static custom := Buffer(64, 0xFF)
    rgb := (init ~= "i)^[0-9a-f]{6}$") ? Integer("0x" init) : 0xFFFFFF
    cc := Buffer(A_PtrSize = 8 ? 72 : 36, 0)
    NumPut("UInt", cc.Size, cc, 0)
    NumPut("Ptr", hwndOwner, cc, A_PtrSize)
    NumPut("UInt", Bgr(rgb), cc, 3 * A_PtrSize)
    NumPut("Ptr", custom.Ptr, cc, 4 * A_PtrSize)
    NumPut("UInt", 0x3, cc, 5 * A_PtrSize)      ; CC_RGBINIT | CC_FULLOPEN
    if !DllCall("comdlg32\ChooseColorW", "Ptr", cc)
        return ""
    return Format("{:06X}", Bgr(NumGet(cc, 3 * A_PtrSize, "UInt")))
}

Bgr(c) => ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)

FetchSiteIcon(url) {                            ; the site's own icon, saved in the icons folder
    if !RegExMatch(url, "i)^(https?://([^/?#:]+)[^/?#]*)", &m)
        return ""
    for cand in ["/apple-touch-icon.png", "/favicon.ico"] {
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.Open("GET", m[1] cand, false)
            req.SetTimeouts(3000, 3000, 3000, 4000)
            req.Send()
            if (req.Status != 200)
                continue
            body := req.ResponseBody
            size := body.MaxIndex() + 1
            p := NumGet(ComObjValue(body), 8 + A_PtrSize, "Ptr")
            sig := NumGet(p, 0, "UInt")
            if (size < 64 || !(sig = 0x474E5089 || sig = 0x00010000))   ; PNG or ICO only
                continue
            file := ICON_DIR "\" RegExReplace(m[2], "[^\w.-]") (sig = 0x474E5089 ? ".png" : ".ico")
            fo := FileOpen(file, "w"), fo.RawWrite(p, size), fo.Close()
            return file
        }
    }
    return ""
}

SysImageList() {                                ; Windows' shared list of small icons
    sfi := Buffer(A_PtrSize + 688, 0)
    return DllCall("shell32\SHGetFileInfoW", "WStr", "C:\", "UInt", 0, "Ptr", sfi, "UInt", sfi.Size, "UInt", 0x4001, "Ptr")
}

SysIconIndex(path) {
    pidl := 0
    if (DllCall("shell32\SHParseDisplayName", "WStr", path, "Ptr", 0, "Ptr*", &pidl, "UInt", 0, "Ptr", 0) || !pidl)
        return -1
    sfi := Buffer(A_PtrSize + 688, 0)
    DllCall("shell32\SHGetFileInfoW", "Ptr", pidl, "UInt", 0, "Ptr", sfi, "UInt", sfi.Size, "UInt", 0x4009, "Ptr")
    DllCall("ole32\CoTaskMemFree", "Ptr", pidl)
    return NumGet(sfi, A_PtrSize, "Int")
}


; =====================================================================================================
;  Drawing (GDI+): smooth round buttons with a soft shadow
; =====================================================================================================
Gdip() {
    static token := 0
    if !token {
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(24, 0), NumPut("UInt", 1, si)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
    }
}

NewDIB(w, h, &bits := 0) {                      ; 32-bit top-down bitmap
    bi := Buffer(40, 0)
    NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, bi)
    bits := 0
    return DllCall("CreateDIBSection", "Ptr", 0, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
}

; Draws f's button, size x size pixels (plus a margin for the shadow). Returns the drawing.
RenderButton(f, size, shadow := false) {
    Gdip()
    noBg := (f.Color = "none")
    src := (f.Icon = "*floats") ? {type: "floats"} : IconSource(f), logo := 0
    if (src.type ~= "image|shell" && f.IconFill != 2) { ; IconFill: 0 = crop square logos round, 1 = always, 2 = never
        logo := LogoCanvas(src, Max(64, Min(256, size * 2)))
        if (logo && f.IconFill = 0 && !logo.square)
            logo := FreeLogo(logo)
    }
    circle := !noBg || logo                     ; a full circle (not just a free-standing icon)
    m := (shadow && circle) ? Max(2, Round(size / 12)) : 0
    W := size + 2 * m
    hbm := NewDIB(W, W, &bits)
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    obm := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
    bg := noBg ? 0xFFFFFF : ColorNum(f.Color)
    isz := Round(size * 0.6), img := 0, ico := 0
    if (!logo && src.type = "image")
        img := LoadPicture2(src.path)
    else if (!logo && src.type = "shell")
        ico := ShellIconBitmap(src.path, isz)

    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 2)
    Loop m                                      ; soft shadow: faint rings, a little lower
        k := m - A_Index + 1, FillEllipse(g, 0x12000000, m - k, m - k + m / 3, size + 2 * k, size + 2 * k)
    FillEllipse(g, noBg ? 0x01000000 : 0xFF000000 | bg, m, m, size, size)
    if logo {
        FillWithLogo(g, logo, m, size)
        FreeLogo(logo)
    } else if img {
        DrawPicture(g, img, m, size)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
    } else if (src.type = "floats") {           ; the hub: Floats' own logo, drawn sharp at any size
        DrawBubbles(g, m + size * 0.2, m + size * 0.2, size * 0.6, 0xFF000000 | bg)
    } else if !ico {
        DrawInitials(g, f.Name != "" ? f.Name : GuessName(f.Opens), m, size, noBg ? 0xFFFFFF : bg)
    }
    if circle {                                 ; hairline edge, so light buttons stand out
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0x24000000, "Float", 1, "Int", 2, "Ptr*", &pen := 0)
        DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen, "Float", m + 0.5, "Float", m + 0.5, "Float", size - 1, "Float", size - 1)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    if ico {
        BlendBitmap(hdc, ico, m + (size - isz) // 2, m + (size - isz) // 2, isz)
        DllCall("DeleteObject", "Ptr", ico)
    }
    return {hdc: hdc, hbm: hbm, obm: obm, bits: bits, w: W}
}

FreeRender(r) {
    if !IsObject(r)
        return
    DllCall("SelectObject", "Ptr", r.hdc, "Ptr", r.obm)
    DllCall("DeleteObject", "Ptr", r.hbm)
    DllCall("DeleteDC", "Ptr", r.hdc)
}

ULW(hwnd, r, alpha := 255, x := "", y := "") {  ; show a drawing on a layered window
    sz := Buffer(8), NumPut("Int", r.w, "Int", r.w, sz)
    src := Buffer(8, 0), pt := 0, blend := alpha << 16 | 1 << 24   ; BLENDFUNCTION: per-pixel alpha
    if (x != "")
        pt := Buffer(8), NumPut("Int", x, "Int", y, pt)
    DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", pt, "Ptr", sz, "Ptr", r.hdc, "Ptr", src
        , "UInt", 0, "UInt*", &blend, "UInt", 2)
}

IconSource(f) {
    if (f.Icon != "" && FileExist(f.Icon))
        return {type: (f.Icon ~= "i)\.(png|jpe?g|bmp|gif|tiff?)$") ? "image" : "shell", path: f.Icon}
    if (f.Opens = "" || (IsUri(f.Opens) && InStr(f.Opens, "shell:") != 1))
        return {type: "none"}
    if (f.Opens ~= "i)\.lnk$") {                ; a web app replaces its icon file when it's renamed, and our copy of
        try {                                   ; its shortcut still points at the old one: use the app's own entry
            FileGetShortcut(f.Opens, , , , , &icon)
            if (icon != "" && !FileExist(icon) && AppNameOf(f) != "")
                return {type: "shell", path: "shell:AppsFolder\" AppIdOf(f)}
        }
    }
    return {type: "shell", path: f.Opens}
}

ColorNum(hex) => (hex ~= "i)^[0-9a-f]{6}$") ? Integer("0x" hex) : 0x1E293B

FillEllipse(g, argb, x, y, w, h) {
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", br, "Float", x, "Float", y, "Float", w, "Float", h)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
}

FillRect(g, argb, x, y, w, h) {
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    DllCall("gdiplus\GdipFillRectangle", "Ptr", g, "Ptr", br, "Float", x, "Float", y, "Float", w, "Float", h)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
}

; The bin, on a see-through square C x C: a round button with a bin on it and a label underneath, so it's
; clear that only the button goes. hot = a button is over it: red and bigger.
RenderBin(C, hot) {
    Gdip()
    hbm := NewDIB(C, C, &bits)
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    obm := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 2)
    s := (hot ? 40 : 32) * DPI, cx := C / 2, cy := 60 * DPI
    bg := hot ? 0xFFDC2626 : 0xFF1E293B, ink := 0xFFFFFFFF
    m := Round(s / 6)
    Loop m                                      ; soft shadow
        k := m - A_Index + 1, FillEllipse(g, 0x12000000, cx - s - k, cy - s - k + m / 3, 2 * (s + k), 2 * (s + k))
    FillEllipse(g, bg, cx - s, cy - s, 2 * s, 2 * s)
    FillRect(g, ink, cx - 0.16 * s, cy - 0.48 * s, 0.32 * s, 0.14 * s)   ; handle
    FillRect(g, ink, cx - 0.46 * s, cy - 0.36 * s, 0.92 * s, 0.12 * s)   ; lid
    pts := Buffer(32)                           ; body: narrower at the bottom
    NumPut("Float", cx - 0.37 * s, "Float", cy - 0.17 * s, "Float", cx + 0.37 * s, "Float", cy - 0.17 * s
        , "Float", cx + 0.29 * s, "Float", cy + 0.54 * s, "Float", cx - 0.29 * s, "Float", cy + 0.54 * s, pts)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", ink, "Ptr*", &br := 0)
    DllCall("gdiplus\GdipFillPolygon", "Ptr", g, "Ptr", br, "Ptr", pts, "Int", 4, "Int", 0)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    for rib in [-0.17, 0, 0.17]                 ; ribs on the body
        FillRect(g, bg, cx + (rib - 0.035) * s, cy - 0.05 * s, 0.07 * s, 0.47 * s)

    pw := 148 * DPI, ph := 26 * DPI, py := 122 * DPI - ph / 2   ; the label, on a pill
    FillEllipse(g, 0xFF1E293B, cx - pw / 2, py, ph, ph)
    FillEllipse(g, 0xFF1E293B, cx + pw / 2 - ph, py, ph, ph)
    FillRect(g, 0xFF1E293B, cx - pw / 2 + ph / 2, py, pw - ph, ph)
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fam := 0)
    DllCall("gdiplus\GdipCreateFont", "Ptr", fam, "Float", 12.5 * DPI, "Int", 0, "Int", 2, "Ptr*", &font := 0)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x5000, "Int", 0, "Ptr*", &fmt := 0)
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", ink, "Ptr*", &br := 0)
    rc := Buffer(16), NumPut("Float", cx - pw / 2, "Float", py, "Float", pw, "Float", ph, rc)
    DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", "Remove from Floats", "Int", -1, "Ptr", font, "Ptr", rc, "Ptr", fmt, "Ptr", br)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fam)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    return {hdc: hdc, hbm: hbm, obm: obm, bits: bits, w: C}
}

LoadPicture2(path) {
    img := 0
    if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &img)
        return 0
    return img
}

DrawPicture(g, img, m, size) {                  ; a picture in the middle of the button, in its own shape
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", img, "UInt*", &iw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", img, "UInt*", &ih := 0)
    if (!iw || !ih)
        return
    isz := size * 0.62, sc := Min(isz / iw, isz / ih), dw := iw * sc, dh := ih * sc
    DllCall("gdiplus\GdipDrawImageRect", "Ptr", g, "Ptr", img, "Float", m + (size - dw) / 2, "Float", m + (size - dh) / 2, "Float", dw, "Float", dh)
}

; The logo (a picture, or the app's own icon) drawn into an s x s square, with the box it really covers
; (transparent edges left out). square = it fills that box, like a tile, so it can be cropped round.
LogoCanvas(src, s) {
    img := 0, hbm := 0
    if (src.type = "image")
        img := LoadPicture2(src.path)
    else if (src.type = "shell" && (hbm := ShellIconBitmap(src.path, s)))
        img := DibImage(hbm)
    if !img {
        if hbm
            DllCall("DeleteObject", "Ptr", hbm)
        return 0
    }
    buf := Buffer(s * s * 4, 0)
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", s, "Int", s, "Int", s * 4, "Int", 0xE200B, "Ptr", buf, "Ptr*", &bmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 2)
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", img, "UInt*", &iw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", img, "UInt*", &ih := 0)
    if (iw && ih) {
        sc := Min(s / iw, s / ih), dw := iw * sc, dh := ih * sc
        DllCall("gdiplus\GdipDrawImageRect", "Ptr", g, "Ptr", img, "Float", (s - dw) / 2, "Float", (s - dh) / 2, "Float", dw, "Float", dh)
    }
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
    if hbm
        DllCall("DeleteObject", "Ptr", hbm)

    st := Max(1, s // 96), n := Ceil(s / st), x1 := s, y1 := s, x2 := -1, y2 := -1
    Loop n {                                     ; the box the visible pixels cover
        y := (A_Index - 1) * st, row := y * s * 4
        Loop n {
            x := (A_Index - 1) * st
            if (NumGet(buf, row + x * 4 + 3, "UChar") > 24) {
                if (x < x1)
                    x1 := x
                if (x > x2)
                    x2 := x
                if (y < y1)
                    y1 := y
                y2 := y
            }
        }
    }
    if (x2 < 0) {                                ; nothing visible
        DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
        return 0
    }
    w := x2 - x1 + 1, h := y2 - y1 + 1
    square := (w >= 0.8 * h && h >= 0.8 * w)     ; about as wide as tall, and solid near all four corners
    for p in [[0.1, 0.1], [0.9, 0.1], [0.1, 0.9], [0.9, 0.9]]
        if (square && NumGet(buf, ((y1 + Round(p[2] * (h - 1))) * s + x1 + Round(p[1] * (w - 1))) * 4 + 3, "UChar") < 160)
            square := false
    return {bmp: bmp, buf: buf, x: x1, y: y1, w: w, h: h, square: square}
}

FreeLogo(logo) {
    DllCall("gdiplus\GdipDisposeImage", "Ptr", logo.bmp)
    return 0
}

FillWithLogo(g, logo, m, size) {                ; the logo cropped round, filling the whole button
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", size, "Int", size, "Int", 0, "Int", 0xE200B, "Ptr", 0, "Ptr*", &tmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", tmp, "Ptr*", &g2 := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g2, "Int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g2, "Int", 2)
    sc := (size + 1) / Min(logo.w, logo.h), dw := logo.w * sc, dh := logo.h * sc
    DllCall("gdiplus\GdipDrawImageRectRect", "Ptr", g2, "Ptr", logo.bmp, "Float", (size - dw) / 2, "Float", (size - dh) / 2
        , "Float", dw, "Float", dh, "Float", logo.x, "Float", logo.y, "Float", logo.w, "Float", logo.h, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g2)
    DllCall("gdiplus\GdipCreateTexture", "Ptr", tmp, "Int", 4, "Ptr*", &tb := 0)
    DllCall("gdiplus\GdipTranslateTextureTransform", "Ptr", tb, "Float", m, "Float", m, "Int", 0)
    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", tb, "Float", m, "Float", m, "Float", size, "Float", size)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", tb)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", tmp)
}

DibImage(hbm) {                                 ; a GDI+ view of a 32-bit DIB's pixels (dispose it before the DIB)
    ds := Buffer(A_PtrSize = 8 ? 104 : 84, 0)
    if !DllCall("GetObject", "Ptr", hbm, "Int", ds.Size, "Ptr", ds)
        return 0
    w := NumGet(ds, 4, "Int"), h := NumGet(ds, 8, "Int"), stride := NumGet(ds, 12, "Int")
    bpp := NumGet(ds, 18, "UShort"), p := NumGet(ds, A_PtrSize = 8 ? 24 : 20, "Ptr")
    upward := NumGet(ds, A_PtrSize = 8 ? 40 : 32, "Int") > 0   ; bottom row first
    if (bpp != 32 || !p || w < 1 || h < 1)
        return 0
    fmt := 0x22009                               ; an old icon without transparency: opaque
    Loop w * h
        if NumGet(p, (A_Index - 1) * 4 + 3, "UChar") {
            fmt := 0xE200B                       ; premultiplied alpha
            break
        }
    img := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", upward ? -stride : stride, "Int", fmt
        , "Ptr", upward ? p + (h - 1) * stride : p, "Ptr*", &img)
    return img
}

DrawInitials(g, name, m, size, bg) {            ; no icon: one or two letters
    words := []
    for w in StrSplit(Trim(name), [" ", "-", "_", "."])
        if (w != "")
            words.Push(w)
    t := !words.Length ? "?" : StrUpper(SubStr(words[1], 1, 1) (words.Length > 1 ? SubStr(words[2], 1, 1) : ""))
    lum := ((bg >> 16) & 255) * 299 + ((bg >> 8) & 255) * 587 + (bg & 255) * 114
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fam := 0)
    DllCall("gdiplus\GdipCreateFont", "Ptr", fam, "Float", size * (StrLen(t) > 1 ? 0.36 : 0.44), "Int", 1, "Int", 2, "Ptr*", &font := 0)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x5000, "Int", 0, "Ptr*", &fmt := 0)
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", lum > 160000 ? 0xFF1F2937 : 0xFFFFFFFF, "Ptr*", &br := 0)
    rc := Buffer(16), NumPut("Float", m, "Float", m + size * 0.02, "Float", size, "Float", size, rc)
    DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", t, "Int", -1, "Ptr", font, "Ptr", rc, "Ptr", fmt, "Ptr", br)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fam)
}

ShellIconBitmap(path, px) {                     ; the icon Explorer shows for a file, folder, shortcut or app
    static IID := 0
    if !IID {
        IID := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{BCC18B79-BA16-442F-80C4-8A59C30C463B}", "Ptr", IID)   ; IShellItemImageFactory
    }
    fac := 0
    if (DllCall("shell32\SHCreateItemFromParsingName", "WStr", path, "Ptr", 0, "Ptr", IID, "Ptr*", &fac) || !fac)
        return 0
    hbm := 0
    try ComCall(3, fac, "Int64", (px & 0xFFFFFFFF) | (px << 32), "Int", 0x4, "Ptr*", &hbm)   ; GetImage, icon only
    ObjRelease(fac)
    return hbm
}

BlendBitmap(hdc, src, x, y, size) {             ; draw a 32-bit bitmap (with transparency) centred in a square
    bm := Buffer(32, 0)
    if !DllCall("GetObject", "Ptr", src, "Int", A_PtrSize = 8 ? 32 : 24, "Ptr", bm)
        return
    w := NumGet(bm, 4, "Int"), h := Abs(NumGet(bm, 8, "Int")), bpp := NumGet(bm, 18, "UShort")
    p := NumGet(bm, A_PtrSize = 8 ? 24 : 20, "Ptr")
    blend := 0x01FF0000                          ; AC_SRC_ALPHA, fully opaque
    if (bpp = 32 && p) {                         ; an old icon without transparency: draw it as it is
        hasAlpha := false
        Loop w * h
            if NumGet(p, (A_Index - 1) * 4 + 3, "UChar") {
                hasAlpha := true
                break
            }
        if !hasAlpha
            blend := 0x00FF0000
    } else
        blend := 0x00FF0000
    sdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
    o := DllCall("SelectObject", "Ptr", sdc, "Ptr", src, "Ptr")
    sc := Min(size / w, size / h), dw := Round(w * sc), dh := Round(h * sc)
    DllCall("gdi32\GdiAlphaBlend", "Ptr", hdc, "Int", x + (size - dw) // 2, "Int", y + (size - dh) // 2, "Int", dw, "Int", dh
        , "Ptr", sdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "UInt", blend)
    DllCall("SelectObject", "Ptr", sdc, "Ptr", o)
    DllCall("DeleteDC", "Ptr", sdc)
}

RenderToIcon(r) {                               ; a drawing -> icon handle (frees the drawing)
    DllCall("SelectObject", "Ptr", r.hdc, "Ptr", r.obm)
    Loop r.w * r.w {                             ; icons want straight (not premultiplied) alpha
        o := (A_Index - 1) << 2, px := NumGet(r.bits, o, "UInt"), a := px >> 24
        if (a && a < 255)
            NumPut("UInt", (a << 24) | (Min(255, ((px >> 16) & 255) * 255 // a) << 16)
                | (Min(255, ((px >> 8) & 255) * 255 // a) << 8) | Min(255, (px & 255) * 255 // a), r.bits, o)
    }
    maskBits := Buffer(((r.w + 15) // 16) * 2 * r.w, 0)
    mask := DllCall("CreateBitmap", "Int", r.w, "Int", r.w, "UInt", 1, "UInt", 1, "Ptr", maskBits, "Ptr")
    ii := Buffer(A_PtrSize = 8 ? 32 : 20, 0)
    NumPut("UInt", 1, ii, 0)
    NumPut("Ptr", mask, ii, A_PtrSize = 8 ? 16 : 12)
    NumPut("Ptr", r.hbm, ii, A_PtrSize = 8 ? 24 : 16)
    hIcon := DllCall("CreateIconIndirect", "Ptr", ii, "Ptr")
    DllCall("DeleteObject", "Ptr", mask)
    DllCall("DeleteObject", "Ptr", r.hbm)
    DllCall("DeleteDC", "Ptr", r.hdc)
    return hIcon
}

OnBackground(r, box, rgb) {                     ; a drawing centred on a solid square (for the preview)
    hbm := NewDIB(box, box)
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    obm := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0xFF000000 | rgb)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    off := (box - r.w) // 2
    DllCall("gdi32\GdiAlphaBlend", "Ptr", hdc, "Int", off, "Int", off, "Int", r.w, "Int", r.w
        , "Ptr", r.hdc, "Int", 0, "Int", 0, "Int", r.w, "Int", r.w, "UInt", 0x01FF0000)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", obm)
    DllCall("DeleteDC", "Ptr", hdc)
    return hbm
}

DrawBubbles(g, x, y, s, gap := 0) {             ; Floats' logo in an s x s box: two floating bubbles
    FillEllipse(g, 0xFF2563EB, x + s * 0.02, y + s * 0.30, s * 0.68, s * 0.68)
    if !gap                                     ; the gap around the small one: cut out, or painted in gap's colour
        DllCall("gdiplus\GdipSetCompositingMode", "Ptr", g, "Int", 1)
    FillEllipse(g, gap, x + s * 0.36, y - s * 0.02, s * 0.66, s * 0.66)
    if !gap
        DllCall("gdiplus\GdipSetCompositingMode", "Ptr", g, "Int", 0)
    FillEllipse(g, 0xFF14B8A6, x + s * 0.42, y + s * 0.04, s * 0.54, s * 0.54)
}

MakeAppIcon(path) {                             ; Floats' own icon: two floating bubbles
    Gdip()
    pngs := []
    for s in [256, 48, 32, 16] {
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", s, "Int", s, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &g := 0)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 2)
        DrawBubbles(g, 0, 0, s)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
        clsid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)   ; PNG
        tmp := A_Temp "\floats-icon-" s ".png"
        DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bmp, "WStr", tmp, "Ptr", clsid, "Ptr", 0)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
        pngs.Push([s, FileRead(tmp, "RAW")])
        FileDelete(tmp)
    }
    total := 6 + 16 * pngs.Length
    for p in pngs
        total += p[2].Size
    buf := Buffer(total, 0)
    NumPut("UShort", 0, "UShort", 1, "UShort", pngs.Length, buf)
    off := 6 + 16 * pngs.Length
    for i, p in pngs {
        d := p[1] >= 256 ? 0 : p[1]
        NumPut("UChar", d, "UChar", d, "UChar", 0, "UChar", 0, "UShort", 1, "UShort", 32, "UInt", p[2].Size, "UInt", off, buf, 6 + 16 * (i - 1))
        DllCall("RtlMoveMemory", "Ptr", buf.Ptr + off, "Ptr", p[2], "UPtr", p[2].Size)
        off += p[2].Size
    }
    fo := FileOpen(path, "w"), fo.RawWrite(buf), fo.Close()
}
