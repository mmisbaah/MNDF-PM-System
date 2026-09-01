$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'serialize-production-env.ps1')
$entries=[ordered]@{
  TEST_PATH='C:\Private records\evidence #1'
  TEST_SPACES='  preserve surrounding spaces  '
  TEST_URL='postgresql://fixture:abc%23def%27ghi@127.0.0.1/test'
  TEST_APOSTROPHE="C:\Evidence\Team's files #2"
  TEST_QUOTES='contains "double quotes"'
  TEST_LITERAL='C:\new\records'
  TEST_PUNCTUATION='dollar$=value;#not-comment'
  TEST_EMPTY=''
}
$content=ConvertTo-ProductionEnvironmentFile $entries
@{content=$content;expected=$entries} | ConvertTo-Json -Compress | & node (Join-Path $PSScriptRoot 'test-env-roundtrip.mjs')
if($LASTEXITCODE -ne 0){throw 'Environment round-trip test failed'}
foreach($value in @("line`nbreak","line`rbreak",("nul"+[char]0),"both'and`"quotes", "Team's\new")) {
  $failed=$false
  try {ConvertTo-ProductionEnvironmentFile @{TEST_VALUE=$value} | Out-Null} catch {$failed=$true}
  if(-not $failed){throw 'Unsafe or lossy value accepted'}
}
$failed=$false
try {ConvertTo-ProductionEnvironmentFile @{'BAD=KEY'='test'} | Out-Null} catch {$failed=$true}
if(-not $failed){throw 'Invalid variable name accepted'}
Write-Output 'PASS rejects control characters, ambiguous quoting and invalid keys'
