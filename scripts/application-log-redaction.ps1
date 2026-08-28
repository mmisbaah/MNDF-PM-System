function Protect-ApplicationLogLine {
  param([AllowEmptyString()][string]$Line)
  $protected=$Line-replace'(?i)(postgres(?:ql)?://[^:\s]+:)[^@\s]+@','$1[REDACTED]@'
  $protected=$protected-replace'(?i)(authorization\s*[:=]\s*bearer\s+)[A-Za-z0-9._~-]+','$1[REDACTED]'
  $protected=$protected-replace'(?i)((?:secret|password|token|passphrase|encryption_key)\s*[:=]\s*)\S+','$1[REDACTED]'
  $protected
}
