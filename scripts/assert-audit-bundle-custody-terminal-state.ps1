param(
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$ReceiptSignaturePath,
  [Parameter(Mandatory=$true)][string]$ExceptionPath,
  [Parameter(Mandatory=$true)][string]$ExceptionSignaturePath
)
$ErrorActionPreference='Stop'
function Assert-OrdinaryPath([string]$Path){$current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;while($current){if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Custody outcome path contains a reparse point: $($current.FullName)"};$parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop}}
$receipt=[IO.Path]::GetFullPath($ReceiptPath);$receiptSignature=[IO.Path]::GetFullPath($ReceiptSignaturePath);$exception=[IO.Path]::GetFullPath($ExceptionPath);$exceptionSignature=[IO.Path]::GetFullPath($ExceptionSignaturePath)
$receiptParts=@($receipt,$receiptSignature)|ForEach-Object{Test-Path -LiteralPath $_ -PathType Leaf};$exceptionParts=@($exception,$exceptionSignature)|ForEach-Object{Test-Path -LiteralPath $_ -PathType Leaf}
if(($receiptParts|Where-Object{$_}).Count-eq1-or($exceptionParts|Where-Object{$_}).Count-eq1){throw 'Custody terminal outcome is incomplete'}
$hasReceipt=-not($receiptParts-contains$false);$hasException=-not($exceptionParts-contains$false)
if($hasReceipt-eq$hasException){throw 'Custody transfer must have exactly one terminal outcome'}
$selected=if($hasReceipt){@($receipt,$receiptSignature)}else{@($exception,$exceptionSignature)};$streams=[Collections.Generic.List[IO.FileStream]]::new()
try{foreach($path in $selected){Assert-OrdinaryPath $path;$streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))};if($hasReceipt){Write-Output 'Custody terminal outcome: RECEIVED'}else{Write-Output 'Custody terminal outcome: EXCEPTION'};foreach($path in $selected){Write-Output "$([IO.Path]::GetFileName($path)): $((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())"}}finally{for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}}

