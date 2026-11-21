using System.Diagnostics;

namespace AetherGui;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--restore-proxy")
        {
            SystemProxy.Disable(args[1]);
            return;
        }

        // Watchdog mode: a tiny second copy of this exe that outlives a crashed/killed GUI and undoes its changes.
        if (args.Length is 2 or 3 && args[0] == "--watchdog")
        {
            string? owner = null;
            try
            {
                using var parent = Process.GetProcessById(int.Parse(args[1]));
                owner = parent.Id + ":" + parent.StartTime.ToUniversalTime().Ticks;
                parent.WaitForExit();
            }
            catch { }
            if (args.Length == 3 && int.TryParse(args[2], out var corePid))
                KillOwnedCore(corePid);
            Psiphon.Kill();
            TunMode.Cleanup();
            if (owner != null) SystemProxy.Disable(owner);
            return;
        }

        TunMode.ElevatedForTun = args.Contains("--tun");

        // Single instance. Must come before anything that touches the proxy or aether. The elevated
        // copy starts while the old one is still shutting down, so wait a few seconds for the mutex.
        var mutex = new Mutex(true, @"Local\AetherGui.SingleInstance", out var isFirst);
        for (var i = 0; !isFirst && i < 20; i++)
        {
            Thread.Sleep(250);
            mutex.Dispose();
            mutex = new Mutex(true, @"Local\AetherGui.SingleInstance", out isFirst);
        }
        if (!isFirst)
        {
            mutex.Dispose();
            MessageBox.Show("Aether GUI is already running.", "Aether GUI", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        try
        {
            SystemProxy.Disable(); // leftover from a previous run that died with the machine (power loss, etc.)
            ApplicationConfiguration.Initialize();
            Application.Run(new Form1());
        }
        finally
        {
            mutex.Dispose();
        }
    }

    private static void KillOwnedCore(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            var expected = Path.Combine(AppContext.BaseDirectory, "aether.exe");
            if (!ProcessOwnership.MatchesExecutable(process, expected)) return;
            process.Kill(true);
            process.WaitForExit(2000);
        }
        catch { }
    }
}
