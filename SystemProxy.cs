using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace AetherGui;

// Windows system (WinINet) proxy pointing at the GUI's mixed proxy port.
static class SystemProxy
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
    // Plain host:port is what Windows shows cleanly in Settings; it is read as an HTTP proxy.
    private static string Server => $"127.0.0.1:{Aether.ProxyPort}";
    private const string Bypass = "<-loopback>;localhost;*.local;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*";

    private static readonly string AetherExe = Path.Combine(AppContext.BaseDirectory, "aether.exe").Replace("'", "''");
    private static readonly string PsiphonExe = Psiphon.Exe.Replace("'", "''");
    private static readonly string TunExe = Path.Combine(AppContext.BaseDirectory, "tun2socks", "tun2socks.exe").Replace("'", "''");

    [DllImport("wininet.dll")]
    private static extern bool InternetSetOption(IntPtr h, int option, IntPtr buf, int len);

    // Second, independent layer: a hidden PowerShell that waits for the GUI to die and then undoes the proxy.
    // It is not named AetherGui.exe and is detached via cmd's `start`, so `taskkill /IM AetherGui.exe`
    // and `taskkill /T` (kill the whole tree) that take out the GUI and the --watchdog copy do not reach it.
    public static void StartIndependentGuard(int pid)
    {
        var script = $@"
Wait-Process -Id {pid} -ErrorAction SilentlyContinue
Get-Process aether -ErrorAction SilentlyContinue | Where-Object {{ $_.Path -eq '{AetherExe}' }} | Stop-Process -Force
Get-Process psiphon3 -ErrorAction SilentlyContinue | Where-Object {{ $_.Path -eq '{PsiphonExe}' }} | Stop-Process -Force
Get-Process tun2socks -ErrorAction SilentlyContinue | Where-Object {{ $_.Path -eq '{TunExe}' }} | Stop-Process -Force
Start-Sleep -Milliseconds 500
$k = 'HKCU:\{KeyPath}'
$port = (Get-ItemProperty 'HKCU:\Software\AetherGui' -ErrorAction SilentlyContinue).ProxyPort
if (-not $port) {{ $port = {Aether.DefaultProxyPort} }} # read now: the port may have changed since this guard started
$srv = (Get-ItemProperty $k).ProxyServer
if ($srv -eq ""127.0.0.1:$port"" -or ($srv -like '*socks=127.0.0.1:*' -and -not (Get-Process psiphon3 -ErrorAction SilentlyContinue))) {{
    Set-ItemProperty $k ProxyEnable 0
    Add-Type -MemberDefinition '[DllImport(""wininet.dll"")] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);' -Name W -Namespace G
    [G.W]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [G.W]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}}";
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        Process.Start(new ProcessStartInfo("cmd.exe", $"/c start \"\" /b powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand {encoded}")
        { CreateNoWindow = true, UseShellExecute = false });
    }

    public static void Enable() => Set(1, Server);

    public static string Status()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        var on = key?.GetValue("ProxyEnable") is 1;
        var srv = key?.GetValue("ProxyServer") as string;
        return on ? (srv == Server ? $"ON -> {srv} (ours)" : $"ON -> {srv} (NOT ours)") : "OFF";
    }

    // Only touches the setting if it is ours, so a user's own proxy is never cleared.
    // Psiphon's own one counts too once no psiphon3 runs: we kill it, so it can never restore it itself.
    public static void Disable()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        var srv = key?.GetValue("ProxyServer") as string;
        if (srv == Server || IsDeadPsiphonProxy(srv)) Set(0, Server);
    }

    private static bool IsDeadPsiphonProxy(string? srv) =>
        srv?.Contains("socks=127.0.0.1:") == true && Process.GetProcessesByName("psiphon3").Length == 0;

    private static void Set(int enable, string server)
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath, true)!;
        key.SetValue("ProxyServer", server);
        key.SetValue("ProxyOverride", Bypass);
        key.SetValue("ProxyEnable", enable);
        InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0); // SETTINGS_CHANGED
        InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0); // REFRESH
    }
}
