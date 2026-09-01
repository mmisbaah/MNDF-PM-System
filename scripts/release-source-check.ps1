function Get-CleanReleaseCommit([string]$ProjectDirectory) {
  $project=[IO.Path]::GetFullPath($ProjectDirectory).TrimEnd('\','/')
  $top=& git -C $project rev-parse --show-toplevel 2>$null
  if($LASTEXITCODE -ne 0 -or -not $top){throw 'Release source must be a Git working tree'}
  $comparison=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
  if(-not $project.Equals([IO.Path]::GetFullPath($top.Trim()).TrimEnd('\','/'),$comparison)){throw 'ProjectDirectory must be the repository root'}
  $commit=& git -C $project rev-parse --verify HEAD 2>$null
  if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$'){throw 'A full committed Git revision is required'}
  $changes=@(& git -C $project status --porcelain=v1 --untracked-files=normal --ignore-submodules=none)
  if($LASTEXITCODE -ne 0){throw 'Could not verify release source status'}
  if($changes.Count){throw 'Release source has staged, unstaged, untracked or submodule changes. Review and commit them before packaging; nothing was modified.'}
  return $commit.Trim()
}
