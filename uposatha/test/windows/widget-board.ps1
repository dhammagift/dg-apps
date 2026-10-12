# The Uposatha PWA widget on a real Windows 11 Widgets Board (a GitHub runner): installs the PWA into Edge by policy, opens the
# board (Win+W), tries to add the widget, and leaves a screenshot and the board's element tree after every step.
# A probe: it fails nothing; what it found is read from the artifact (owner, 2026-10-11: is there a way to test the Windows widget).
param([string]$Url = 'https://test.dhamma.gift/uposatha-calendar?app=1&source=pwa', [string]$Out = 'win-shots', [string]$Package = '', [int]$Only = -1, [string]$Size = '', [string]$Theme = '')
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Keys { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static void WinPlus(byte vk) { keybd_event(0x5B,0,0,UIntPtr.Zero); keybd_event(vk,0,0,UIntPtr.Zero); keybd_event(vk,0,2,UIntPtr.Zero); keybd_event(0x5B,0,2,UIntPtr.Zero); } }
'@
$script:n = 0
function Shot([string]$name) {
  $script:n++
  try {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save(('{0}\{1:d2}-{2}.png' -f $Out, $script:n, $name)); $g.Dispose(); $bmp.Dispose()
  } catch { Log "shot $name failed: $_" }
}
# Write-Host, not the pipeline: a function's output is its return value, and Tap returns a boolean
function Log([string]$s) { Add-Content "$Out\log.txt" $s; Write-Host $s }
$AE = [System.Windows.Automation.AutomationElement]; $TS = [System.Windows.Automation.TreeScope]; $Cond = [System.Windows.Automation.Condition]
# Every element on screen with a name: "<window> | <type> | <name>"
function Tree([string]$name) {
  $lines = @()
  try {
    foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) {
      $wn = $w.Current.Name; $lines += "WINDOW [$wn] class=$($w.Current.ClassName)"
      if ($w.Current.ClassName -notmatch 'Shell_TrayWnd|Progman|ConsoleWindowClass') {
        $all = $w.FindAll($TS::Descendants, $Cond::TrueCondition); $i = 0
        foreach ($e in $all) { $i++; if ($i -gt 900) { break }
          if ($e.Current.Name) { $lines += "  $($e.Current.ControlType.ProgrammaticName -replace 'ControlType\.','') | $($e.Current.Name)" } }
      }
    }
  } catch { $lines += "tree failed: $_" }
  $lines | Out-File ('{0}\tree-{1:d2}-{2}.txt' -f $Out, $script:n, $name) -Encoding utf8
}
# Clicks the first element whose name matches, in windows whose name matches
function Tap([string]$window, [string]$pattern) {
  try {
    foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) {
      if ($w.Current.Name -notmatch $window) { continue }
      foreach ($e in $w.FindAll($TS::Descendants, $Cond::TrueCondition)) {
        if ($e.Current.Name -match $pattern) {
          $p = $null
          if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke() }
          else { $r = $e.Current.BoundingRectangle; [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]($r.X + $r.Width / 2)), ([int]($r.Y + $r.Height / 2))
                 Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);' -Name M -Namespace W -ErrorAction SilentlyContinue
                 [W.M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); [W.M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero) }
          Log "tapped [$($e.Current.Name)] in [$($w.Current.Name)]"; return $true
        }
      }
    }
  } catch { Log "tap $pattern failed: $_" }
  Log "nothing to tap for /$pattern/ in /$window/"; return $false
}

# A fresh runner user has never finished Windows' first-run screens: "Choose privacy settings for your device" covers the whole
# screen (run 1: every screenshot was that page). Its window (class Shell_OOBEProxy) gives UI Automation nothing to press (run 2),
# so: first the processes that host it are stopped; if it is still there, its Next / Accept button is clicked where it stands
# (the bottom right of the page: 87 % across, 87 % down), a screenshot after every click.
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);' -Name M -Namespace W -ErrorAction SilentlyContinue
function ClickAt([double]$rx, [double]$ry) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]($b.Left + $b.Width * $rx)), ([int]($b.Top + $b.Height * $ry))
  Start-Sleep -Milliseconds 300
  [W.M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); [W.M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}
function FirstRunThere {
  foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) { if ($w.Current.ClassName -match 'OOBE|CloudExperience') { return $true } }
  return $false
}
function Dismiss {
  if (-not (FirstRunThere)) { Log 'first-run screens: none'; return }
  Get-Process | Where-Object { $_.ProcessName -match 'OOBE|CloudExperienceHost|WWAHost' } | ForEach-Object { Log "stopping $($_.ProcessName) ($($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep 4
  Shot 'first-run-after-stop'
  for ($i = 1; $i -le 8; $i++) {
    if (-not (FirstRunThere)) { Log "first-run screens: gone after $($i - 1) click(s)"; return }
    ClickAt 0.871 0.867
    Start-Sleep 4
    Shot "first-run-click-$i"
  }
  Log ('first-run screens: ' + $(if (FirstRunThere) { 'still there' } else { 'gone' }))
}

# 0. Windows in the dark theme, when asked (the board tells a widget its theme: $host.hostTheme)
if ($Theme -eq 'dark') {
  $t = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  New-Item -Force $t | Out-Null
  Set-ItemProperty $t -Name AppsUseLightTheme -Value 0 -Type DWord
  Set-ItemProperty $t -Name SystemUsesLightTheme -Value 0 -Type DWord
  Log 'Windows theme: dark'
}

# 1. What this machine is
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture | Format-List | Out-File "$Out\system.txt"
Get-AppxPackage | Where-Object { $_.Name -match 'WebExperience|Widget' } | Select-Object Name, Version | Format-Table -AutoSize | Out-File -Append "$Out\system.txt"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
"Edge: $edge $((Get-Item $edge -ErrorAction SilentlyContinue).VersionInfo.ProductVersion)" | Out-File -Append "$Out\system.txt"
Get-Content "$Out\system.txt"
Shot 'desktop'; Tree 'desktop'
Dismiss
Shot 'desktop-clear'

# 1b. What Microsoft's guide asks of a machine that shows a PWA's widgets before the app is in the Store: Developer Mode and the
# Windows App SDK runtime (run 4: the PWA was installed, the board's picker listed Microsoft's own widgets only)
$dev = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
New-Item -Force $dev | Out-Null
Set-ItemProperty $dev -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord
Set-ItemProperty $dev -Name AllowAllTrustedApps -Value 1 -Type DWord
Log 'Developer Mode: on'
$rt = Get-AppxPackage | Where-Object { $_.Name -match 'WindowsAppRuntime|WinAppRuntime' }
Log ("Windows App SDK runtime before: " + $(if ($rt) { ($rt | ForEach-Object { $_.Name + ' ' + $_.Version }) -join '; ' } else { 'none' }))
# Microsoft's guide names version 1.2 (run 6: with 1.6, 1.8 and 2.x there and Developer Mode on, the picker still had no PWA widget)
if (-not ($rt | Where-Object { $_.Name -match 'WindowsAppRuntime\.1\.2' })) {
  $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM') { 'arm64' } else { 'x64' }
  foreach ($u in @("https://aka.ms/windowsappsdk/1.2/latest/windowsappruntimeinstall-$arch.exe", "https://aka.ms/windowsappsdk/1.2/1.2.230313.1/windowsappruntimeinstall-$arch.exe")) {
    try {
      $exe = "$env:TEMP\windowsappruntimeinstall.exe"
      Invoke-WebRequest $u -OutFile $exe -UseBasicParsing
      $p = Start-Process $exe -ArgumentList '--quiet' -Wait -PassThru
      Log "Windows App SDK 1.2 runtime installer ($arch, $u): exit $($p.ExitCode)"
      if ($p.ExitCode -eq 0) { break }
    } catch { Log "Windows App SDK 1.2 runtime from $u : $_" }
  }
  $rt = Get-AppxPackage | Where-Object { $_.Name -match 'WindowsAppRuntime|WinAppRuntime' }
  Log ("Windows App SDK runtime after: " + $(if ($rt) { ($rt | ForEach-Object { $_.Name + ' ' + $_.Version }) -join '; ' } else { 'none' }))
}

# 2. The PWA, installed by policy when Edge starts
$k = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
New-Item -Force $k | Out-Null
Set-ItemProperty $k -Name HideFirstRunExperience -Value 1 -Type DWord
# With a package to install, nothing is installed from the browser: the same web app installed twice (by policy and as a package)
# is not what a Store user has, and run 13 drew nothing in the pinned widget, not even a card of one static line.
# Without a package: ours and Microsoft's demo PWA with a widget (the control), both by policy.
if (-not $Package) {
  Set-ItemProperty $k -Name WebAppInstallForceList -Value ('[{"url":"' + $Url + '","default_launch_container":"window","create_desktop_shortcut":true},{"url":"https://microsoftedge.github.io/Demos/pwamp/","default_launch_container":"window","create_desktop_shortcut":true}]')
}
# PWA widgets are an Edge feature that is off by default: PWABuilder's Store package switches it on with exactly this flag
# (pwabuilder-microsoft-store, "enable-features" = "msWebAppWidgets"). Runs 4-8 without it: neither Microsoft's demo nor ours in the picker.
if ($Package) { Start-Process $edge -ArgumentList '--no-first-run', 'about:blank' } else { Start-Process $edge -ArgumentList '--no-first-run', '--enable-features=msWebAppWidgets', $Url }
Start-Sleep 45
Shot 'edge'; Tree 'edge'
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Applications" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object FullName | Out-File "$Out\web-applications.txt" -Width 400
Get-ChildItem "$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop" -ErrorAction SilentlyContinue | Select-Object FullName | Out-File -Append "$Out\web-applications.txt" -Width 400
Get-AppxPackage | Where-Object { $_.Name -match 'edge|uposatha|dhamma|pwa' } | Select-Object Name, Version, PackageFamilyName | Format-Table -AutoSize | Out-File -Append "$Out\web-applications.txt" -Width 400
# the app's own window once, so that its worker is running
foreach ($app in 'PWAmp', 'Uposatha') {
  $lnk = Get-ChildItem "$env:USERPROFILE\Desktop\*.lnk" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $app } | Select-Object -First 1
  if ($lnk) { Start-Process $lnk.FullName; Start-Sleep 20; Shot "app-window-$app" } else { Log "no $app shortcut on the desktop: that PWA was not installed" }
}

# 2b. The same PWA as a Windows package (PWABuilder's test package, what goes to the Microsoft Store in its signed form). Windows
# reads a widget provider and its widgets from a PACKAGE's manifest (AppExtension com.microsoft.windows.widgets); a PWA installed
# from the browser has no package, which is why runs 4-9 never saw a PWA widget in the picker, Microsoft's own demo included.
if ($Package) {
  try {
    $zip = "$env:TEMP\upo-package.zip"; $dir = "$env:TEMP\upo-package"
    Invoke-WebRequest $Package -OutFile $zip -UseBasicParsing
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath $dir -Force
    Get-ChildItem $dir -Recurse | Select-Object FullName, Length | Out-File "$Out\package.txt" -Width 300
    $msix = Get-ChildItem $dir -Recurse -Filter '*.sideload.msix' | Select-Object -First 1
    $inst = Get-ChildItem $dir -Recurse -Filter 'pwainstaller.exe' | Select-Object -First 1
    $p = Start-Process $inst.FullName -ArgumentList ('"' + $msix.FullName + '"') -Wait -PassThru
    Log "package installer: exit $($p.ExitCode)"
    Start-Sleep 5
    $pkg = Get-AppxPackage | Where-Object { $_.Name -match 'Uposatha' }
    Log ("package installed: " + $(if ($pkg) { $pkg.PackageFullName } else { 'NO' }))
    $app = Get-StartApps | Where-Object { $_.Name -match 'Uposatha by the Suttas' } | Select-Object -Last 1
    if ($app) { Start-Process ("shell:AppsFolder\" + $app.AppID); Start-Sleep 25; Shot 'packaged-app' } else { Log 'the packaged app is not in the Start menu' }
  } catch { Log "package: $_" }
}

# 3. The Widgets Board
Dismiss
# Whatever is open over the desktop (run 5: the Start menu) is closed first; the board itself closes as soon as it loses the
# focus, so its button is pressed before anything slow (the element tree) is done.
function BoardThere { foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) { if ($w.Current.Name -match '^Widgets$') { return $true } }; return $false }
# Win+W toggles the board, so it is pressed only while the board is not there (run 11: one press opened nothing)
function OpenBoard {
  for ($i = 1; $i -le 4; $i++) {
    if (BoardThere) { return $true }
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); Start-Sleep 1
    [Keys]::WinPlus(0x57)   # Win+W
    Start-Sleep 10
  }
  $there = BoardThere; if (-not $there) { Log 'the Widgets Board did not open' }; return $there
}
OpenBoard | Out-Null
Shot 'board'
# the board's content is a web page and may still be loading (run 7: the window was there, the button not yet)
$opened = $false
for ($i = 1; $i -le 8 -and -not $opened; $i++) { OpenBoard | Out-Null; if (Tap '^Widgets$' '^Add widgets$') { $opened = $true } else { Start-Sleep 5 } }
if ($opened) { Start-Sleep 8; Shot 'board-add'; Tree 'board-add' } else { Shot 'board-no-button'; Tree 'board' }
# the picker lists the apps that have widgets; ours is there only when Windows took the PWA's widgets
$names = @()
try { foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) { if ($w.Current.Name -match 'WidgetPicker') { foreach ($e in $w.FindAll($TS::Descendants, $Cond::TrueCondition)) { if ($e.Current.ControlType.ProgrammaticName -match 'ListItem') { $names += $e.Current.Name } } } } } catch { }
Log ("picker lists: " + (($names | ForEach-Object { $_.Substring(0, [Math]::Min(40, $_.Length)) }) -join ' | '))
Log ("PWAmp (the control) in the picker: " + [bool]($names -match 'PWAmp') + "; Uposatha: " + [bool]($names -match 'Uposatha'))
# The n-th button of that name in the picker (our app has a Pin button per widget)
function TapNth([string]$window, [string]$pattern, [int]$n) {
  try {
    foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) {
      if ($w.Current.Name -notmatch $window) { continue }
      $hits = @(); foreach ($e in $w.FindAll($TS::Descendants, $Cond::TrueCondition)) { if ($e.Current.ControlType.ProgrammaticName -match 'Button' -and $e.Current.Name -match $pattern) { $hits += $e } }
      if ($hits.Count -gt $n) { $p = $null; if ($hits[$n].TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); Log "tapped button $n of $($hits.Count) [$($hits[$n].Current.Name)]"; return $true } }
      Log "only $($hits.Count) button(s) /$pattern/ in /$window/"; return $false
    }
  } catch { Log "tapNth failed: $_" }
  Log "no window /$window/ for button $n"
  return $false
}
# every widget of ours is pinned: the picker is opened anew for each (it closes after a pin); every step is tried a few times,
# because the board and the picker close when they lose the focus
for ($n = 0; $n -lt 3; $n++) {
  if ($Only -ge 0 -and $n -ne $Only) { continue }   # one widget alone is the first in the board's column, where a screenshot shows it
  $done = $false
  for ($try = 1; $try -le 3 -and -not $done; $try++) {
    $inPicker = $false
    foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) { if ($w.Current.Name -match 'WidgetPicker') { $inPicker = $true } }
    if (-not $inPicker) { OpenBoard | Out-Null; Start-Sleep 2; if (-not (Tap '^Widgets$' '^Add widgets$')) { Start-Sleep 4; continue }; Start-Sleep 6 }
    if (-not (Tap 'WidgetPicker' '^Uposatha by the Suttas$')) { Start-Sleep 3; continue }
    Start-Sleep 4
    if (TapNth 'WidgetPicker' '^Pin$' $n) { $done = $true; Start-Sleep 12; Shot "pinned-$n" }
  }
  if (-not $done) { Log "widget $n was not pinned" }
}
# what the board says in our widgets, now and a minute later (a drawn card's texts are in the element tree, wherever it is scrolled)
function BoardTexts([string]$name) {
  $t = @(); try { foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) { if ($w.Current.Name -match '^Widgets$') { foreach ($e in $w.FindAll($TS::Descendants, $Cond::TrueCondition)) { if ($e.Current.Name) { $t += ($e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', '') + ' | ' + $e.Current.Name } } } } } catch { }
  $t | Out-File "$Out\board-texts-$name.txt" -Encoding utf8
  Log ("board texts ($name): " + $t.Count + "; PROBE lines: " + (($t -match 'PROBE-') -join ' / ') + "; main card (day . coming/now): " + [bool]($t -match 'day . (coming|now)|день . (скоро|сейчас)') + "; our titles: " + (($t -match 'Uposatha \+ kala|Day & night|^Text \| Month$').Count))
}
# One of our widgets in another size (Small / Medium / Large): its own "More options" is the first such button after its title
if ($Size) {
  OpenBoard | Out-Null
  try {
    $seen = $false; $done = $false
    foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) {
      if ($w.Current.Name -notmatch '^Widgets$') { continue }
      foreach ($e in $w.FindAll($TS::Descendants, $Cond::TrueCondition)) {
        if ($e.Current.Name -match '^(Uposatha \+ kala|Day & night|Month)$') { $seen = $true; continue }
        if ($seen -and -not $done -and $e.Current.Name -match '^More options$') {
          $p = $null; if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); $done = $true; Log 'opened our widget''s More options' }
        }
      }
    }
    Start-Sleep 3; Shot 'widget-menu'; Tree 'widget-menu'
    $hit = $false
    foreach ($w in $AE::RootElement.FindAll($TS::Children, $Cond::TrueCondition)) {
      foreach ($e in $w.FindAll($TS::Descendants, $Cond::TrueCondition)) {
        if (-not $hit -and $e.Current.Name -match ('^' + $Size + '( |$)')) { $p = $null; if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); $hit = $true; Log "size $Size chosen" } }
      }
    }
    if (-not $hit) { Log "no menu item $Size" }
    Start-Sleep 12
  } catch { Log "size: $_" }
}
OpenBoard | Out-Null
Shot 'board-after-pins'; BoardTexts 'now'
Start-Sleep 45
OpenBoard | Out-Null
Shot 'board-a-minute-later'; BoardTexts 'later'
Start-Sleep 5
Shot 'end'
Get-ChildItem $Out | Select-Object Name, Length
