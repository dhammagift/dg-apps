# The Uposatha PWA widget on a real Windows 11 Widgets Board (a GitHub runner): installs the PWA into Edge by policy, opens the
# board (Win+W), tries to add the widget, and leaves a screenshot and the board's element tree after every step.
# A probe: it fails nothing; what it found is read from the artifact (owner, 2026-10-11: is there a way to test the Windows widget).
param([string]$Url = 'https://test.dhamma.gift/uposatha-calendar?app=1&source=pwa', [string]$Out = 'win-shots')
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
      if ($wn -match 'Widget|Uposatha|Edge|Dhamma') {
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

# 1. What this machine is
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture | Format-List | Out-File "$Out\system.txt"
Get-AppxPackage | Where-Object { $_.Name -match 'WebExperience|Widget' } | Select-Object Name, Version | Format-Table -AutoSize | Out-File -Append "$Out\system.txt"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
"Edge: $edge $((Get-Item $edge -ErrorAction SilentlyContinue).VersionInfo.ProductVersion)" | Out-File -Append "$Out\system.txt"
Get-Content "$Out\system.txt"
Shot 'desktop'

# 2. The PWA, installed by policy when Edge starts
$k = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
New-Item -Force $k | Out-Null
Set-ItemProperty $k -Name HideFirstRunExperience -Value 1 -Type DWord
Set-ItemProperty $k -Name WebAppInstallForceList -Value ('[{"url":"' + $Url + '","default_launch_container":"window","create_desktop_shortcut":true}]')
Start-Process $edge -ArgumentList '--no-first-run', $Url
Start-Sleep 45
Shot 'edge'; Tree 'edge'
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Web Applications" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object FullName | Out-File "$Out\web-applications.txt" -Width 400
Get-ChildItem "$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop" -ErrorAction SilentlyContinue | Select-Object FullName | Out-File -Append "$Out\web-applications.txt" -Width 400
Get-AppxPackage | Where-Object { $_.Name -match 'edge|uposatha|dhamma|pwa' } | Select-Object Name, Version, PackageFamilyName | Format-Table -AutoSize | Out-File -Append "$Out\web-applications.txt" -Width 400
# the app's own window once, so that its worker is running
$lnk = Get-ChildItem "$env:USERPROFILE\Desktop\*.lnk" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Uposatha' } | Select-Object -First 1
if ($lnk) { Start-Process $lnk.FullName; Start-Sleep 25; Shot 'app-window' } else { Log 'no Uposatha shortcut on the desktop: the PWA was not installed' }

# 3. The Widgets Board
[Keys]::WinPlus(0x57)   # Win+W
Start-Sleep 12
Shot 'board'; Tree 'board'
if (Tap 'Widget' 'Add widgets|Add a widget|^\+$|Discover|Pin widgets') { Start-Sleep 6; Shot 'board-add'; Tree 'board-add' }
if (Tap 'Widget' 'Uposatha') { Start-Sleep 6; Shot 'board-uposatha'; Tree 'board-uposatha' }
if (Tap 'Widget' '^Pin$|Pin widget|^Add$') { Start-Sleep 10; Shot 'board-pinned'; Tree 'board-pinned' }
Start-Sleep 5
Shot 'end'
Get-ChildItem $Out | Select-Object Name, Length
