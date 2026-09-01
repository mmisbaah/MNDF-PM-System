$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'release-source-check.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
$fixture=Join-Path $base ('tracker-source-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Invoke-FixtureGit([string[]]$Arguments){
  & git -C $fixture @Arguments | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Fixture Git command failed'}
}
function Assert-SourceRejected([string]$Path,[string]$Scenario){
  $rejected=$false
  try {Get-CleanReleaseCommit $Path | Out-Null} catch {$rejected=$true}
  if(-not $rejected){throw "Accepted unsafe source: $Scenario"}
  Write-Output "PASS rejects $Scenario"
}
try {
  Invoke-FixtureGit @('init','--quiet')
  [IO.File]::WriteAllText((Join-Path $fixture 'source.txt'),'original')
  $projectIgnore=[IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) '.gitignore'))
  [IO.File]::WriteAllText((Join-Path $fixture '.gitignore'),$projectIgnore+"`nignored/`n")
  Invoke-FixtureGit @('add','source.txt','.gitignore')
  # All commits are solely in this disposable repository; hooks/signing disabled.
  Invoke-FixtureGit @('-c','user.name=Fixture','-c','user.email=fixture@pilot.test','-c','commit.gpgsign=false','-c','core.hooksPath=ignored/hooks','commit','--quiet','-m','fixture')
  $commit=Get-CleanReleaseCommit $fixture
  if($commit -notmatch '^[0-9a-f]{40}$'){throw 'Clean revision rejected'}
  Write-Output 'PASS clean committed source'
  [IO.File]::WriteAllText((Join-Path $fixture 'next-env.d.ts'),'// generated Next.js declarations')
  if((Get-CleanReleaseCommit $fixture) -ne $commit){throw 'Generated Next.js declarations changed release source'}
  Write-Output 'PASS generated root next-env.d.ts leaves source clean'
  $nested=Join-Path $fixture 'src'
  New-Item -ItemType Directory -Path $nested | Out-Null
  $nestedDeclaration=Join-Path $nested 'next-env.d.ts'
  [IO.File]::WriteAllText($nestedDeclaration,'// unexpected source declaration')
  Assert-SourceRejected $fixture 'nested declaration outside generated-file exception'
  Remove-Item -LiteralPath $nestedDeclaration
  [IO.File]::WriteAllText((Join-Path $fixture 'source.txt'),'changed')
  Assert-SourceRejected $fixture 'unstaged change'
  Invoke-FixtureGit @('add','source.txt')
  Assert-SourceRejected $fixture 'staged change'
  # Commit only disposable fixture changes, never reset the real working tree.
  Invoke-FixtureGit @('-c','user.name=Fixture','-c','user.email=fixture@pilot.test','-c','commit.gpgsign=false','-c','core.hooksPath=ignored/hooks','commit','--quiet','-m','fixture change')
  $untracked=Join-Path $fixture 'untracked.txt'
  [IO.File]::WriteAllText($untracked,'fixture')
  Assert-SourceRejected $fixture 'untracked file'
  Remove-Item -LiteralPath $untracked
  $ignored=Join-Path $fixture 'ignored'
  New-Item -ItemType Directory -Path $ignored | Out-Null
  [IO.File]::WriteAllText((Join-Path $ignored 'build.txt'),'ignored fixture output')
  Get-CleanReleaseCommit $fixture | Out-Null
  Write-Output 'PASS ignored build outputs do not dirty source'
  Assert-SourceRejected $ignored 'nested project directory'
  if([IO.File]::ReadAllText((Join-Path $fixture 'source.txt')) -ne 'changed'){throw 'Source checker modified a file'}
} finally {
  $resolved=[IO.Path]::GetFullPath($fixture)
  $prefix=Join-Path $base 'tracker-source-test-'
  if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
