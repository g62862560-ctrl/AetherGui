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
& '{Environment.ProcessPath!.Replace("'", "''")}' --restore-proxy '{Owner}'";
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        Process.Start(new ProcessStartInfo("cmd.exe", $"/c start \"\" /b powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand {encoded}")
        { CreateNoWindow = true, UseShellExecute = false });
    }

    public static void Enable() => Change(true);

    private const string JournalPath = @"Software\AetherGui\ProxyTransaction";
    private static readonly string Owner = Environment.ProcessId + ":" + Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
    internal static string CurrentOwner => Owner;

    private static void Change(bool enable, string? expectedOwner = null)
    {
        using var mutex = new Mutex(false, @"Local\AetherGui.ProxyTransaction");
        try { if (!mutex.WaitOne(TimeSpan.FromSeconds(10))) throw new TimeoutException("Proxy transaction is busy"); }
        catch (AbandonedMutexException) { }
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
            using var journal = Registry.CurrentUser.CreateSubKey(JournalPath);
            ApplyTransaction(key, journal, enable ? Server : null, Owner, expectedOwner);
            InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
            InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
        }
        finally { mutex.ReleaseMutex(); }
    }

    // The journal is flushed before any proxy mutation. Each original value retains its registry type.
    // Recovery restores only values still equal to our write (or already equal to their original).
    internal static void ApplyTransaction(RegistryKey key, RegistryKey journal, string? server, string owner, string? expectedOwner = null)
    {
        string[] names = ["ProxyServer", "ProxyOverride", "ProxyEnable"];
        object[] desired = [server ?? "", Bypass, 1];
        if (server != null && journal.GetValue("Ready") is 1)
        {
            if ((string?)journal.GetValue("Owner") == owner && Equals(journal.GetValue("Written0"), server)
                && names.Select((n, i) => Equals(key.GetValue(n), journal.GetValue("Written" + i))).All(x => x))
                return;
            ApplyTransaction(key, journal, null, owner);
        }
        if (server != null)
        {
            for (var i = 0; i < names.Length; i++)
            {
                var original = key.GetValue(names[i], null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                journal.SetValue("Present" + i, original == null ? 0 : 1);
                if (original != null) journal.SetValue("Original" + i, original, key.GetValueKind(names[i]));
                else journal.DeleteValue("Original" + i, false);
                journal.SetValue("Written" + i, desired[i]);
            }
            journal.SetValue("Owner", owner);
            journal.SetValue("Ready", 1);
            journal.Flush();
            try
            {
                for (var i = 0; i < names.Length; i++) key.SetValue(names[i], desired[i]);
                key.Flush();
            }
            catch { ApplyTransaction(key, journal, null, owner); throw; }
            return;
        }
        if (journal.GetValue("Ready") is not 1 || (expectedOwner != null && (string?)journal.GetValue("Owner") != expectedOwner)) return;
        for (var i = 0; i < names.Length; i++)
        {
            var current = key.GetValue(names[i], null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            var original = journal.GetValue("Original" + i, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            if (!Equals(current, journal.GetValue("Written" + i))
                || key.GetValueKind(names[i]) != journal.GetValueKind("Written" + i)) continue; // preserve external edits
            if (journal.GetValue("Present" + i) is 1)
                key.SetValue(names[i], original!, journal.GetValueKind("Original" + i));
            else key.DeleteValue(names[i], false);
        }
        key.Flush();
        journal.DeleteValue("Ready", false);
        journal.Flush();
    }

    public static string Status()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        var on = key?.GetValue("ProxyEnable") is 1;
        var srv = key?.GetValue("ProxyServer") as string;
        return on ? (srv == Server ? $"ON -> {srv} (ours)" : $"ON -> {srv} (NOT ours)") : "OFF";
    }

    public static void Disable(string? expectedOwner = null) => Change(false, expectedOwner);
}
