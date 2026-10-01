using System;
using System.IO;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public sealed class ElixrValidatePaths : Task
{
    [Required] public ITaskItem[] Paths { get; set; }
    [Required] public ITaskItem[] AllowedRoots { get; set; }
    public string AssemblyName { get; set; }

    public override bool Execute()
    {
        try
        {
            if (AssemblyName != null && (string.IsNullOrWhiteSpace(AssemblyName) ||
                AssemblyName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 ||
                AssemblyName.IndexOfAny(new[] { '*', '?', ';', '%', '/', '\\' }) >= 0 ||
                AssemblyName == "." || AssemblyName == ".."))
                throw new InvalidOperationException("Elixr cleanup requires one literal assembly filename, without path or wildcard characters.");
            if (Paths == null || Paths.Length == 0 || AllowedRoots == null || AllowedRoots.Length == 0)
                throw new InvalidOperationException("Elixr output paths and allowed roots must be nonempty.");
            foreach (var item in Paths)
            {
                var path = item.ItemSpec;
                if (string.IsNullOrWhiteSpace(path) || !Path.IsPathRooted(path))
                    throw new InvalidOperationException("Elixr output operations require an absolute, nonempty path.");
                path = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                var allowed = false;
                foreach (var rootItem in AllowedRoots)
                {
                    if (string.IsNullOrWhiteSpace(rootItem.ItemSpec) || !Path.IsPathRooted(rootItem.ItemSpec))
                        throw new InvalidOperationException("Elixr allowed roots must be absolute and nonempty.");
                    var root = Path.GetFullPath(rootItem.ItemSpec).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                    if (path.Equals(root, StringComparison.OrdinalIgnoreCase) ||
                        path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                        allowed = true;
                }
                if (!allowed)
                    throw new InvalidOperationException("Elixr output path is outside the approved build roots: " + path);
                // Reject aliases before either Delete or Copy can follow a directory junction.
                for (var ancestor = path; !string.IsNullOrEmpty(ancestor); ancestor = Path.GetDirectoryName(ancestor))
                {
                    if ((File.Exists(ancestor) || Directory.Exists(ancestor)) &&
                        (File.GetAttributes(ancestor) & FileAttributes.ReparsePoint) != 0)
                        throw new InvalidOperationException("Elixr output operations reject reparse points: " + ancestor);
                }
            }
            return true;
        }
        catch (Exception error)
        {
            Log.LogErrorFromException(error, false);
            return false;
        }
    }
}
