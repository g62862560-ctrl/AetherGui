using System.Security.Cryptography;
using Microsoft.Win32;
using AetherGui;

static class SecurityChecks
{
    public static void Run()
    {
        static void Check(bool ok, string name)
        {
            if (!ok) throw new Exception(name);
            Console.WriteLine("PASS: " + name);
        }
        var bytes = new byte[] { 1, 2, 3 };
        var hash = Convert.ToHexString(SHA256.HashData(bytes));
        foreach (var valid in new[] { hash, hash.ToLowerInvariant() + "  aether-windows-x86_64.zip\n", hash + " *aether-windows-x86_64.zip" })
            Aether.VerifyCoreChecksum(bytes, valid);
        Check(true, "Core checksum accepts matching raw and named SHA-256 formats");
        foreach (var invalid in new string?[] { null, "", "bad", new string('0', 64), new string('z', 64), hash + " other.zip", hash + " aether-windows-x86_64.zip extra" })
        {
            bool refused = false;
            try { Aether.VerifyCoreChecksum(bytes, invalid); }
            catch (InvalidDataException) { refused = true; }
            Check(refused, "Core checksum rejects missing, malformed, mismatched or wrong-file data");
        }
        var path = @"Software\AetherGui.Tests\" + Guid.NewGuid().ToString("N");
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(path + @"\Settings");
            using var journal = Registry.CurrentUser.CreateSubKey(path + @"\Journal");
            void Enable(string owner = "one", string server = "127.0.0.1:1234") => SystemProxy.ApplyTransaction(key, journal, server, owner);
            void Restore(string? owner = null) => SystemProxy.ApplyTransaction(key, journal, null, "recovery", owner);
            key.SetValue("ProxyServer", "%USERPROFILE%\\proxy", RegistryValueKind.ExpandString);
            key.SetValue("ProxyEnable", 0);
            Enable(); Enable(); Restore();
            Check((string?)key.GetValue("ProxyServer", null, RegistryValueOptions.DoNotExpandEnvironmentNames) == "%USERPROFILE%\\proxy"
                && key.GetValueKind("ProxyServer") == RegistryValueKind.ExpandString && key.GetValue("ProxyEnable") is 0
                && key.GetValue("ProxyOverride") == null, "Proxy restores original values, types and absence after repeated enable");
            Enable(); key.SetValue("ProxyOverride", "user-change"); Restore();
            Check((string?)key.GetValue("ProxyOverride") == "user-change", "Proxy restoration preserves external edits");
            Enable(); Restore("old-owner");
            Check((string?)key.GetValue("ProxyServer") == "127.0.0.1:1234", "Stale guard cannot restore a different owner");
            Restore("one");
            Enable(); Enable("one", "127.0.0.1:5678"); Restore();
            Check(key.GetValue("ProxyEnable") is 0, "Proxy port change retains original configuration");
            Enable(); Enable("two"); Restore("one");
            Check(key.GetValue("ProxyEnable") is 1, "Previous owner cannot restore new transaction");
            Restore("two"); Restore();
            Check(key.GetValue("ProxyEnable") is 0 && journal.GetValue("Ready") == null, "Persisted recovery is idempotent and clears journal");
            Enable();
            key.SetValue("ProxyEnable", 0); // Simulate a crash before the final write.
            Restore();
            Check(key.GetValue("ProxyEnable") is 0 && (string?)key.GetValue("ProxyOverride") == "user-change",
                "Recovery handles an interrupted partial proxy write");
            Enable();
            key.SetValue("ProxyServer", "127.0.0.1:1234", RegistryValueKind.ExpandString);
            Restore();
            Check(key.GetValueKind("ProxyServer") == RegistryValueKind.ExpandString,
                "Recovery preserves external registry type changes");
        }
        finally { Registry.CurrentUser.DeleteSubKeyTree(path, false); }
    }
}
