using System.Diagnostics;

namespace AetherGui;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        // Watchdog mode: a tiny second copy of this exe that outlives a crashed/killed GUI and undoes its changes.
        if (args.Length == 2 && args[0] == "--watchdog")
        {
            try { Process.GetProcessById(int.Parse(args[1])).WaitForExit(); } catch { }
            foreach (var p in Process.GetProcessesByName("aether"))
                try { p.Kill(true); } catch { }
            Psiphon.Kill();
            TunMode.Cleanup();
            SystemProxy.Disable();
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
}
