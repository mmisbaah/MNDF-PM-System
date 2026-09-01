function Resolve-PerformanceTrackerNode {
  param([string]$ProjectDirectory=(Split-Path $PSScriptRoot -Parent),[string]$ExplicitPath)
  if($ExplicitPath){
    $candidate=[IO.Path]::GetFullPath($ExplicitPath)
  } else {
    $project=[IO.Path]::GetFullPath($ProjectDirectory).TrimEnd('\')
    $releases=Split-Path $project -Parent
    $installRoot=Split-Path $releases -Parent
    $installedCandidate=Join-Path $installRoot 'runtime\node.exe'
    if((Split-Path $releases -Leaf)-eq'releases'){$candidate=$installedCandidate}
    else{$command=Get-Command node.exe -ErrorAction SilentlyContinue;if($command){$candidate=$command.Source}}
  }
  if(-not$candidate-or-not(Test-Path -LiteralPath $candidate -PathType Leaf)){throw 'Approved Node.js runtime was not found'}
  $version=(& $candidate --version).Trim()
  if($LASTEXITCODE-ne0-or$version-notmatch'^v24\.'){throw "Approved Node.js 24 runtime is required; found $version"}
  return $candidate
}
