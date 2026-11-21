using System.Diagnostics;

namespace AetherGui;

static class ProcessOwnership
{
    internal static bool MatchesExecutable(Process process, string expectedPath)
    {
        try
        {
            return string.Equals(Path.GetFullPath(process.MainModule?.FileName ?? ""),
                Path.GetFullPath(expectedPath), StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }
}
