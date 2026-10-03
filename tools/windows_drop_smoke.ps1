# Drags a file onto the built Rooster, for real: an OLE drag started from a
# small window, the mouse moved over Rooster with the button held, and let go.
# Fails when Rooster refuses the drop (the "forbidden" cursor), which is what
# someone dragging a file from Explorer would see.
#
#   pwsh tools/windows_drop_smoke.ps1 -Bundle rooster/build/windows/x64/runner/Release
param(
  [Parameter(Mandatory = $true)][string]$Bundle,
  [int]$StartupSeconds = 90
)
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public static class Native {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr hwnd, string name);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  public static string ClassOf(IntPtr hwnd) {
    var s = new StringBuilder(256);
    GetClassName(hwnd, s, 256);
    return s.ToString();
  }

  // The visible top-level windows of a process.
  public static List<IntPtr> WindowsOf(uint pid) {
    var found = new List<IntPtr>();
    EnumWindows((h, l) => {
      uint owner;
      GetWindowThreadProcessId(h, out owner);
      if (owner == pid && IsWindowVisible(h)) found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found;
  }

  public static List<IntPtr> ChildrenOf(IntPtr parent) {
    var found = new List<IntPtr>();
    EnumChildWindows(parent, (h, l) => { found.Add(h); return true; }, IntPtr.Zero);
    return found;
  }

  // OLE keeps a window's IDropTarget in this property: set means the window
  // is registered for drops.
  public static bool TakesDrops(IntPtr hwnd) {
    return GetProp(hwnd, "OleDropTargetInterface") != IntPtr.Zero;
  }
}

// A window a file is dragged out of, as it is out of Explorer.
public class DragSource : Form {
  public DragDropEffects Result = DragDropEffects.None;
  public DragDropEffects OverTarget = DragDropEffects.None;
  public bool Dragged;
  DragDropEffects last = DragDropEffects.None;
  readonly string[] files;
  readonly Point target;

  public DragSource(string[] files, Point target, Point at) {
    this.files = files;
    this.target = target;
    Text = "drag source";
    StartPosition = FormStartPosition.Manual;
    FormBorderStyle = FormBorderStyle.None;
    Location = at;
    Size = new Size(120, 120);
    TopMost = true;
    BackColor = Color.OrangeRed;
  }

  protected override void OnShown(EventArgs e) {
    base.OnShown(e);
    var centre = new Point(Left + Width / 2, Top + Height / 2);
    new Thread(() => {
      Thread.Sleep(500);
      Native.SetCursorPos(centre.X, centre.Y);
      Thread.Sleep(200);
      Native.mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); // left down
      // Never hang the build: when no drag started, give up.
      Thread.Sleep(20000);
      if (!Dragged) BeginInvoke((Action)Close);
    }) { IsBackground = true }.Start();
  }

  protected override void OnMouseDown(MouseEventArgs e) {
    base.OnMouseDown(e);
    Dragged = true;
    var centre = new Point(Left + Width / 2, Top + Height / 2);
    new Thread(() => {
      for (int i = 1; i <= 40; i++) {
        Native.SetCursorPos(centre.X + (target.X - centre.X) * i / 40,
                            centre.Y + (target.Y - centre.Y) * i / 40);
        Native.mouse_event(0x0001, 0, 0, 0, UIntPtr.Zero); // move
        Thread.Sleep(25);
      }
      // Hover, as a person does, and keep what the target answers.
      for (int i = 0; i < 20; i++) {
        Native.mouse_event(0x0001, i % 2 == 0 ? 1 : -1, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);
      }
      OverTarget = last;
      Native.mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero); // left up
    }) { IsBackground = true }.Start();
    var data = new DataObject(DataFormats.FileDrop, files);
    Result = DoDragDrop(data,
        DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link);
    Close();
  }

  protected override void OnGiveFeedback(GiveFeedbackEventArgs e) {
    last = e.Effect;
    base.OnGiveFeedback(e);
  }
}
'@

$exe = Join-Path (Resolve-Path $Bundle) 'rooster.exe'
if (-not (Test-Path $exe)) { throw "no rooster.exe in $Bundle" }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output "running as $($identity.Name), elevated: $elevated"

$dropped = Join-Path $env:TEMP 'rooster-drop-smoke.txt'
Set-Content -LiteralPath $dropped -Value 'dropped on Rooster'
$stdout = Join-Path $env:TEMP 'rooster-drop-stdout.log'
$stderr = Join-Path $env:TEMP 'rooster-drop-stderr.log'

$app = Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) `
  -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$code = 1
try {
  # Rooster's window, once it is shown.
  $window = [IntPtr]::Zero
  $deadline = (Get-Date).AddSeconds($StartupSeconds)
  while ((Get-Date) -lt $deadline -and $window -eq [IntPtr]::Zero) {
    if ($app.HasExited) { throw "Rooster exited with $($app.ExitCode) before showing a window" }
    foreach ($h in [Native]::WindowsOf([uint32]$app.Id)) {
      if ([Native]::ClassOf($h) -eq 'FLUTTER_RUNNER_WIN32_WINDOW') { $window = $h }
    }
    Start-Sleep -Milliseconds 500
  }
  if ($window -eq [IntPtr]::Zero) { throw "Rooster showed no window in $StartupSeconds s" }
  # Let the first screen settle.
  Start-Sleep -Seconds 5

  [void][Native]::SetWindowPos($window, [IntPtr]::Zero, 0, 0, 800, 600, 0x0040)
  [void][Native]::SetForegroundWindow($window)
  Start-Sleep -Seconds 1
  $rect = New-Object Native+RECT
  [void][Native]::GetWindowRect($window, [ref]$rect)
  Write-Output ("window {0}: {1},{2} to {3},{4}; takes drops: {5}" -f $window,
    $rect.Left, $rect.Top, $rect.Right, $rect.Bottom, [Native]::TakesDrops($window))
  $registered = [Native]::TakesDrops($window)
  foreach ($child in [Native]::ChildrenOf($window)) {
    $takes = [Native]::TakesDrops($child)
    if ($takes) { $registered = $true }
    Write-Output ("  child {0} {1}; takes drops: {2}" -f $child, [Native]::ClassOf($child), $takes)
  }

  # Somewhere in the middle of Rooster, and the source in its bottom corner.
  $target = New-Object Drawing.Point (
    [int]($rect.Left + ($rect.Right - $rect.Left) / 3),
    [int]($rect.Top + ($rect.Bottom - $rect.Top) / 2))
  $at = New-Object Drawing.Point (($rect.Right - 140), ($rect.Bottom - 140))
  $point = New-Object Native+POINT
  $point.X = $target.X; $point.Y = $target.Y
  $under = [Native]::GetAncestor([Native]::WindowFromPoint($point), 2)
  Write-Output "under the drop point: $under ($([Native]::ClassOf($under)))"

  $source = New-Object DragSource (@($dropped), $target, $at)
  [Windows.Forms.Application]::Run($source)
  Start-Sleep -Seconds 2

  Write-Output "drag started: $($source.Dragged)"
  Write-Output "while over Rooster: $($source.OverTarget)"
  Write-Output "drop result: $($source.Result)"
  if (-not $source.Dragged) {
    Write-Output 'FAIL: the drag never started (no interactive desktop?)'
  } elseif (-not $registered) {
    Write-Output 'FAIL: no window of Rooster is registered for drops'
  } elseif ($source.Result -eq [Windows.Forms.DragDropEffects]::None) {
    Write-Output 'FAIL: Rooster refused the drop'
  } else {
    Write-Output 'OK: Rooster took the drop'
    $code = 0
  }
} finally {
  if (-not $app.HasExited) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 1
  foreach ($log in @($stdout, $stderr)) {
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 0) {
      Write-Output "---- $(Split-Path -Leaf $log) ----"
      Get-Content $log -Tail 40
    }
  }
}
exit $code
