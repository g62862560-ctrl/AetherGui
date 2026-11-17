using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Security.Principal;
using Microsoft.Win32;

namespace AetherGui;

// Best-effort full-device TUN: tun2socks feeds every app's traffic into aether's SOCKS port.
// Windows cannot mark aether's own sockets (SO_MARK is Linux-only), so Cloudflare's ranges are
// routed straight out the physical adapter to stop tunnel setup looping back into the TUN.
static class TunMode
{
    private const string Adapter = "AetherTun";
    private const string Ip = "198.18.0.1";
    private const string Mask = "255.254.0.0";
    private const string Dns = "1.1.1.1";
    private const string KeyPath = @"Software\AetherGui";
    private static readonly string Dir = Path.Combine(AppContext.BaseDirectory, "tun2socks");
    private static readonly string Exe = Path.Combine(Dir, "tun2socks.exe");
    private static readonly string Dll = Path.Combine(Dir, "wintun.dll");

    // aether's API and WARP endpoints are Cloudflare anycast; they must stay outside the TUN.
    private static readonly string[] Bypass =
    [
        "173.245.48.0/20", "103.21.244.0/22", "103.22.182.0/23", "103.31.4.0/22",
        "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
        "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
        "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    ];

    // Set on the copy restarted with --tun, so the form reconnects and starts the TUN.
    public static bool ElevatedForTun;

    public static bool Available => File.Exists(Exe) && File.Exists(Dll);

    public static bool Enabled
    {
        get { using var k = Registry.CurrentUser.OpenSubKey(KeyPath); return k?.GetValue("TunMode") is 1; }
        set { using var k = Registry.CurrentUser.CreateSubKey(KeyPath); k.SetValue("TunMode", value ? 1 : 0); }
    }

    public static bool IsAdmin
    {
        get { using var id = WindowsIdentity.GetCurrent(); return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator); }
    }

    private static Process? _proc;

    // Interface, next hop and metric of the active default route on a real adapter: another TUN
    // (sing-box, a VPN) must not be mistaken for the physical one.
    private static (string Name, string Gateway)? PhysicalRoute()
    {
        const string cmd =
            "$r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric; " +
            "foreach ($x in $r) { $a = Get-NetAdapter -InterfaceIndex $x.InterfaceIndex -ErrorAction SilentlyContinue; " +
            "if (-not $a) { continue }; " +
            "if ($a.InterfaceDescription -match 'Wintun' -or $a.Name -match 'tun') { continue }; " +
            "Write-Output ($a.Name + '|' + $x.NextHop); break }";
        using var p = Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -Command \"" + cmd + "\"")
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!;
        var parts = p.StandardOutput.ReadToEnd().Trim().Split('|');
        p.WaitForExit();
        return parts.Length == 2 && parts[0].Length > 0 && parts[1] is not ("0.0.0.0" or "")
            ? (parts[0], parts[1]) : null;
    }

    private static bool AdapterUp() =>
        NetworkInterface.GetAllNetworkInterfaces().Any(n => n.Name == Adapter && n.OperationalStatus == OperationalStatus.Up);

    // Wintun never answers duplicate-address detection, so the address lingers Tentative for a moment;
    // a route added before it turns Preferred is silently ignored.
    private static bool AddressPreferred()
    {
        const string cmd = "Get-NetIPAddress -InterfaceAlias " + Adapter + " -AddressFamily IPv4 -ErrorAction SilentlyContinue | " +
                           "Select-Object -First 1 -ExpandProperty AddressState";
        using var p = Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -Command \"" + cmd + "\"")
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!;
        return p.StandardOutput.ReadToEnd().Trim() == "Preferred";
    }

    private static bool Netsh(string args, Action<string> log)
    {
        using var p = Process.Start(new ProcessStartInfo("netsh.exe", "interface ipv4 " + args)
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })!;
        var err = p.StandardError.ReadToEnd();
        p.WaitForExit();
        if (p.ExitCode == 0) return true;
        log($"TUN setup failed: netsh {args}: {err.Trim()}");
        return false;
    }

    public static void Enable(int port, Action<string> log)
    {
        if (_proc is { HasExited: false }) return;
        if (!Available) { log("TUN mode unavailable: tun2socks.exe / wintun.dll missing beside the app."); return; }
        if (!IsAdmin) { log("TUN mode needs 'Run as administrator'."); return; }
        var route = PhysicalRoute();
        if (route is null) { log("TUN mode: no physical default route found (another tunnel owns it)."); return; }
        _proc?.Dispose();
        try
        {
            var psi = new ProcessStartInfo(Exe)
            {
                WorkingDirectory = Dir, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            };
            foreach (var arg in new[] { "-d", Adapter, "-p", $"socks5://127.0.0.1:{port}", "--loglevel", "silent" })
                psi.ArgumentList.Add(arg);
            _proc = new Process { StartInfo = psi };
            if (!_proc.Start()) throw new InvalidOperationException("tun2socks did not start");
        }
        catch (Exception ex) { log($"TUN start failed: {ex.Message}"); Disable(); return; }

        for (var i = 0; i < 20 && _proc is { HasExited: false } && !AdapterUp(); i++) Thread.Sleep(250);
        if (_proc.HasExited) { log($"TUN start failed: tun2socks exited ({_proc.ExitCode})."); _proc.Dispose(); _proc = null; return; }
        if (!AdapterUp()) { log("TUN start failed: the Wintun adapter never came up."); Disable(); return; }

        if (!Netsh($"set address name=\"{Adapter}\" static {Ip} {Mask}", log)
            || !Netsh($"set dnsservers name=\"{Adapter}\" static {Dns} primary", log))
        { Disable(); return; }
        Netsh($"set interface \"{Adapter}\" metric=1", log); // the effective cost is route + interface metric
        for (var i = 0; i < 20 && !AddressPreferred(); i++) Thread.Sleep(250);
        if (!AddressPreferred()) { log("TUN setup failed: the adapter address never became usable."); Disable(); return; }
        foreach (var prefix in Bypass)
            Netsh($"add route {prefix} \"{route.Value.Name}\" {route.Value.Gateway} metric=1", log);
        // Well below the physical route's cost so the TUN wins without touching the other route.
        Netsh($"add route 0.0.0.0/0 \"{Adapter}\" {Ip} metric=1", log);
        log("TUN mode on: all apps route through aether (Cloudflare endpoints bypass the tunnel).");
    }

    public static void Disable()
    {
        var proc = _proc;
        _proc = null;
        if (proc is not null)
        {
            try { if (!proc.HasExited) { proc.Kill(true); proc.WaitForExit(3000); } } catch { }
            proc.Dispose();
        }
        Cleanup();
    }

    // Crash cleanup: also runs in the watchdog copy, which never has a live _proc reference.
    public static void Cleanup()
    {
        foreach (var p in Process.GetProcessesByName("tun2socks"))
            try { if (p.MainModule?.FileName == Exe) { p.Kill(true); p.WaitForExit(3000); } } catch { }
        if (!IsAdmin) return; // removing the route needs elevation
        try
        {
            using var n = Process.Start(new ProcessStartInfo("netsh.exe", $"interface ipv4 delete route 0.0.0.0/0 \"{Adapter}\" {Ip}")
            { UseShellExecute = false, CreateNoWindow = true })!;
            n.WaitForExit(3000);
        }
        catch { }
    }
}
