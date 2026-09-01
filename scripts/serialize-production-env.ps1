function ConvertTo-ProductionEnvironmentFile {
  param([System.Collections.IDictionary]$Entries)
  $lines = foreach ($entry in $Entries.GetEnumerator()) {
    $key = [string]$entry.Key
    if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw 'Invalid environment variable name' }
    if ($null -eq $entry.Value) { throw "Missing environment value for $key" }
    $value = [string]$entry.Value
    if ($value.Contains("`r") -or $value.Contains("`n") -or $value.Contains([string][char]0)) { throw "Environment value for $key must be single-line and contain no NUL" }
    # Single quotes preserve whitespace, #, backslashes and double quotes.
    if (-not $value.Contains("'")) { "${key}='$value'" }
    # Node expands literal backslash-n in double quotes. Never silently alter it.
    elseif (-not $value.Contains('"') -and -not $value.Contains('\n') -and -not $value.Contains('\r')) { "${key}=`"$value`"" }
    else { throw "Environment value for $key cannot be represented losslessly; use a path without mixed quotes or URL-encode credential punctuation" }
  }
  return ($lines -join "`n") + "`n"
}
