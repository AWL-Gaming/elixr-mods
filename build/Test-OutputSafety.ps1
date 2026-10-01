param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$solution = [IO.File]::ReadAllText((Join-Path $root 'Full Kit.sln'))
$solutionProjects = @([regex]::Matches($solution, '(?m)^Project\("\{[^\}]+\}"\) = "[^\"]+", "([^\"]+\.csproj)"') | ForEach-Object { $_.Groups[1].Value })
if ($solutionProjects.Count -eq 0) { throw 'No solution projects found.' }
foreach ($relative in $solutionProjects) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Solution project leaves the source tree.' }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($path, $settings)
    try {
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        foreach ($exec in $document.SelectNodes("//*[local-name()='Target']//*[local-name()='Exec']")) {
            if ($exec.GetAttribute('Command') -match '(?i)\b(del|erase|rd|rmdir|move|robocopy|Remove-Item)\b') {
                throw ('Unsafe shell cleanup remains in ' + $relative)
            }
        }
    } finally { $reader.Dispose() }
}
$scratch = Join-Path $root ('build\fixtures\output-safety-' + [Guid]::NewGuid().ToString('N'))
$projectDir = Join-Path $scratch 'project with spaces'
$output = Join-Path $projectDir 'bin\shared output'
$outside = Join-Path $scratch 'outside'
New-Item -ItemType Directory -Path $output,$outside -Force | Out-Null
$project = Join-Path $projectDir 'fixture.proj'
$targets = [Security.SecurityElement]::Escape((Join-Path $PSScriptRoot 'ElixrOutput.targets'))
[IO.File]::WriteAllText($project, @"
<Project>
  <PropertyGroup>
    <TargetDir>$([Security.SecurityElement]::Escape($output))\</TargetDir>
    <TargetName>Eco.EM.Probe</TargetName>
    <ElixrCleanOutput>true</ElixrCleanOutput>
    <ElixrStripArtistry>true</ElixrStripArtistry>
  </PropertyGroup>
  <Import Project="$targets" />
</Project>
"@)
$passes = $solutionProjects.Count
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passes++
}
function Invoke-Cleanup([string[]]$Properties, [bool]$ExpectedSuccess = $true) {
    $log = & $Dotnet msbuild $project /nologo /v:minimal /t:ElixrCleanOutput @Properties 2>&1
    $success = $LASTEXITCODE -eq 0
    if ($success -ne $ExpectedSuccess) { throw ('Unexpected cleanup result for ' + ($Properties -join ' ') + ', exit ' + $LASTEXITCODE + ': ' + ($log -join [Environment]::NewLine)) }
    if (-not $ExpectedSuccess -and ($log -join [Environment]::NewLine) -notmatch 'Elixr (cleanup|output)') {
        throw ('Failure did not exercise the Elixr guard: ' + ($log -join [Environment]::NewLine))
    }
    $script:passes++
}
$removed = @('Eco.Core.dll','Eco.EM.Framework.dll','Eco.EM.Framework.pdb','Eco.EM.Framework.xml',
    'Eco.EM.Framework.deps.json','Eco.EM.Framework.runtimeconfig.json','Eco.EM.Framework.dll.config',
    'Eco.EM.Artistry.dll','Eco.EM.Artistry.pdb','Eco.EM.Artistry.xml','Eco.EM.Artistry.deps.json',
    'Eco.EM.Artistry.runtimeconfig.json','Eco.EM.Artistry.dll.config',
    'Eco.EM.Probe.deps.json','Eco.EM.Probe.runtimeconfig.json','Eco.EM.Probe.dll.config')
$preserved = @('Eco.EM.Probe.dll','Eco.EM.Probe.pdb','Eco.EM.Building.Blocks.dll','Eco.EM.Sibling.deps.json',
    'NetFabric.Hyperlinq.dll','System.Memory.dll','appsettings.json','server.config','another.txt','Eco.EM.Framework.Custom.dll')
foreach ($name in $removed + $preserved) { [IO.File]::WriteAllText((Join-Path $output $name), 'sentinel:' + $name) }
Invoke-Cleanup -Properties @()
foreach ($name in $removed) { Assert-True (-not (Test-Path -LiteralPath (Join-Path $output $name))) ('Cleanup did not remove ' + $name) }
foreach ($name in $preserved) { Assert-True ([IO.File]::ReadAllText((Join-Path $output $name)) -eq ('sentinel:' + $name)) ('Cleanup changed required output ' + $name) }
[IO.File]::WriteAllText((Join-Path $output 'Eco.EM.Artistry.dll'), 'artistry')
Invoke-Cleanup -Properties @('/p:ElixrStripArtistry=false')
Assert-True ([IO.File]::ReadAllText((Join-Path $output 'Eco.EM.Artistry.dll')) -eq 'artistry') 'Artistry project/dependents lost their own output'
$sentinel = Join-Path $outside 'Eco.Core.dll'
[IO.File]::WriteAllText($sentinel, 'outside must survive')
Invoke-Cleanup -Properties @('/p:TargetDir=' + $outside) -ExpectedSuccess $false
Assert-True ([IO.File]::ReadAllText($sentinel) -eq 'outside must survive') 'Outside-output file changed'
Invoke-Cleanup -Properties @('/p:TargetDir=') -ExpectedSuccess $false
Invoke-Cleanup -Properties @('/p:TargetName=') -ExpectedSuccess $false
Invoke-Cleanup -Properties @('/p:TargetName=..\..\outside\Eco.Core') -ExpectedSuccess $false
Invoke-Cleanup -Properties @('/p:TargetName=*') -ExpectedSuccess $false
Invoke-Cleanup -Properties @('/p:TargetName=Eco.EM.?') -ExpectedSuccess $false
Invoke-Cleanup -Properties @('/p:TargetName=Eco.EM.Probe%3bEco.EM.Sibling') -ExpectedSuccess $false
Assert-True ([IO.File]::ReadAllText($sentinel) -eq 'outside must survive') 'Target-name escape changed an outside file'
$fakeRoot = Join-Path $scratch 'fake repository'
$fakeBin = Join-Path $fakeRoot 'bin'
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
$fakeSentinel = Join-Path $fakeBin 'Eco.Core.dll'
[IO.File]::WriteAllText($fakeSentinel, 'fake root must survive')
Invoke-Cleanup -Properties @(('/p:ElixrRepositoryRoot=' + $fakeRoot), ('/p:TargetDir=' + $fakeBin)) -ExpectedSuccess $false
Assert-True ([IO.File]::ReadAllText($fakeSentinel) -eq 'fake root must survive') 'Command-line root override escaped the checkout'
$junction = Join-Path $projectDir 'bin\alias'
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
Invoke-Cleanup -Properties @('/p:TargetDir=' + $junction) -ExpectedSuccess $false
Assert-True ([IO.File]::ReadAllText($sentinel) -eq 'outside must survive') 'Junction guard failed'
$modularProject = Join-Path $root '10\Collaborations\ModularTools\ModularTools.csproj'
$packageDestination = Join-Path $root 'bin\ModularTools\Mods\UserCode'
New-Item -ItemType Directory -Path $packageDestination -Force | Out-Null
$packageSentinel = Join-Path $packageDestination ('unrelated-' + [Guid]::NewGuid().ToString('N') + '.config')
[IO.File]::WriteAllText($packageSentinel, 'unrelated package data')
$log = & $Dotnet msbuild $modularProject /nologo /v:minimal /t:PostBuild 2>&1
if ($LASTEXITCODE -ne 0) { throw ('ModularTools packaging failed: ' + ($log -join [Environment]::NewLine)) }
$passes++
Assert-True ([IO.File]::ReadAllText($packageSentinel) -eq 'unrelated package data') 'ModularTools purged unrelated package data'
$modularRoot = Split-Path -Parent $modularProject
foreach ($folder in @('AutoGen','ModularTools','Tools')) {
    $source = Join-Path $modularRoot $folder
    $destination = Join-Path $root ('bin\ModularTools\Mods\UserCode\' + $folder)
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\')
        $copy = Join-Path $destination $relative
        Assert-True ((Get-FileHash -LiteralPath $file.FullName).Hash -eq (Get-FileHash -LiteralPath $copy).Hash) ('ModularTools copy differs: ' + $relative)
    }
}
$log = & $Dotnet msbuild $modularProject /nologo /v:minimal /t:PostBuild 2>&1
if ($LASTEXITCODE -ne 0) { throw ('Repeated ModularTools packaging failed: ' + ($log -join [Environment]::NewLine)) }
$passes++
Assert-True ([IO.File]::ReadAllText($packageSentinel) -eq 'unrelated package data') 'Repeated packaging changed unrelated data'
# Exercise the actual packaging target with an incomplete task-owned source tree.
$incompleteDir = Join-Path $scratch 'incomplete source'
New-Item -ItemType Directory -Path $incompleteDir -Force | Out-Null
$incompleteProject = Join-Path $incompleteDir 'incomplete.proj'
[xml]$originalProject = [IO.File]::ReadAllText($modularProject)
$fixtureDocument = [Xml.XmlDocument]::new()
$fixtureDocument.LoadXml('<Project />')
$import = $fixtureDocument.CreateElement('Import')
$import.SetAttribute('Project', (Join-Path $PSScriptRoot 'ElixrOutput.targets'))
[void]$fixtureDocument.DocumentElement.AppendChild($import)
$packagingTarget = $originalProject.SelectSingleNode("/Project/Target[@Name='PostBuild']")
[void]$fixtureDocument.DocumentElement.AppendChild($fixtureDocument.ImportNode($packagingTarget, $true))
$fixtureDocument.Save($incompleteProject)
$log = & $Dotnet msbuild $incompleteProject /nologo /v:minimal /t:PostBuild 2>&1
Assert-True ($LASTEXITCODE -ne 0 -and ($log -join [Environment]::NewLine) -match "packaging requires the current project's three source directories") 'Missing packaging roots did not fail closed'
foreach ($folder in @('AutoGen','ModularTools','Tools')) { New-Item -ItemType Directory -Path (Join-Path $incompleteDir $folder) | Out-Null }
$log = & $Dotnet msbuild $incompleteProject /nologo /v:minimal /t:PostBuild 2>&1
Assert-True ($LASTEXITCODE -ne 0 -and ($log -join [Environment]::NewLine) -match 'packaging refuses an incomplete source tree') 'Empty packaging roots did not fail closed'
Write-Output ('Output safety passed ' + $passes + ' assertions and operations; fixture retained at ' + $scratch)
# The final probes deliberately fail; return the suite outcome rather than that native exit code.
exit 0
