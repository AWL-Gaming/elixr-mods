Build the current solution with native Windows and the .NET 8 SDK selected by `global.json`:

```powershell
./build/Test-OutputSafety.ps1
dotnet restore 'Full Kit.sln' --disable-parallel
dotnet build 'Full Kit.sln' --no-restore --no-incremental -m:1 -p:BuildInParallel=false
dotnet test 'Full Kit.sln' --no-build --no-restore --verbosity normal
```

The current solution's output paths remain unchanged. Several projects share output directories, so use a serialized solution build. The repository's NuGet configuration resolves its public dependencies without using host-specific feeds or credentials. CI uses a new checkout and package/CLI caches for each run attempt. A trusted, separately approved native Windows runner must be registered before these jobs can execute. Fork and untrusted PR jobs are skipped rather than placed on persistent infrastructure.

`ElixrOutput.targets` removes only explicitly named Eco host assemblies, Framework sidecars, and Artistry sidecars for the projects that previously excluded Artistry. It removes only the current assembly's generated JSON/config sidecars, leaving other projects' JSON/config files intact. Other mod assemblies and any copied runtime package dependencies survive cleanup, including NetFabric when present. Existing SDK package-copy behavior and NuGet dependency declarations remain unchanged; this change does not make class-library builds copy every transitive runtime DLL. Cleanup refuses paths outside the repository/project `bin` roots and refuses junctions or other reparse points. Custom output paths outside those roots fail closed.

ModularTools copies the current project's `AutoGen`, `ModularTools`, and `Tools` source folders to the existing `bin/ModularTools/Mods/UserCode` layout. Missing or empty source folders fail rather than producing an incomplete package. Copying preserves unrelated destination files; it does not mirror, purge or delete them.

The native safety suite verifies solution cleanup commands, exact-name cleanup, required/sibling output preservation, invalid output/name paths, junction rejection, and byte-identical ModularTools packaging. Test fixtures stay under `build/fixtures` for inspection. The solution's `dotnet test` target currently contains no test projects; the separate historical unit-test project points to an absent `9.0` framework and is not a claimed regression result.
