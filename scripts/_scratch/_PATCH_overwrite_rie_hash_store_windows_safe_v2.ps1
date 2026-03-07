param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "WRITE_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs=@(@($err))
  if($errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg)
  }
}
$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts    = Join-Path $RepoRoot "scripts"
$HashScript = Join-Path $Scripts "rie_hash_store_v1.ps1"
if(-not (Test-Path -LiteralPath $HashScript -PathType Leaf)){ Die ("HASH_SCRIPT_MISSING: " + $HashScript) }
$bak = $HashScript + ".bak_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $HashScript -Destination $bak -Force | Out-Null
$L = New-Object System.Collections.Generic.List[string]
[void]$L.Add('Set-StrictMode -Version Latest')
[void]$L.Add('$ErrorActionPreference = "Stop"')
[void]$L.Add('')
[void]$L.Add('function RIE-HashDie([string]$m){ throw $m }')
[void]$L.Add('')
[void]$L.Add('function RIE-Sha256Hex([byte[]]$Bytes){')
[void]$L.Add('  $sha = [System.Security.Cryptography.SHA256]::Create()')
[void]$L.Add('  try{')
[void]$L.Add('    $h = $sha.ComputeHash($Bytes)')
[void]$L.Add('    $sb = New-Object System.Text.StringBuilder')
[void]$L.Add('    foreach($x in $h){ [void]$sb.AppendFormat("{0:x2}", $x) }')
[void]$L.Add('    return $sb.ToString()')
[void]$L.Add('  } finally {')
[void]$L.Add('    $sha.Dispose()')
[void]$L.Add('  }')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-ReadFileUtf8NoBomLfCanonical([string]$Path){')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-HashDie ("FILE_MISSING: " + $Path) }')
[void]$L.Add('  $b = [System.IO.File]::ReadAllBytes($Path)')
[void]$L.Add('  $enc = New-Object System.Text.UTF8Encoding($false,$true)')
[void]$L.Add('  $s = $enc.GetString($b)')
[void]$L.Add('  if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }')
[void]$L.Add('  $s = $s.Replace("`r`n","`n").Replace("`r","`n")')
[void]$L.Add('  if(-not $s.EndsWith("`n")){ $s += "`n" }')
[void]$L.Add('  return $s')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-HashFileUtf8NoBomLf([string]$Path){')
[void]$L.Add('  $s = RIE-ReadFileUtf8NoBomLfCanonical $Path')
[void]$L.Add('  $enc = New-Object System.Text.UTF8Encoding($false)')
[void]$L.Add('  $bytes = $enc.GetBytes($s)')
[void]$L.Add('  return ("sha256:" + (RIE-Sha256Hex $bytes))')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-SanitizeHashForFileName([string]$Hash){')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($Hash)){ RIE-HashDie "HASH_EMPTY" }')
[void]$L.Add('  $h = $Hash.Trim()')
[void]$L.Add('  if($h.StartsWith("sha256:", [System.StringComparison]::OrdinalIgnoreCase)){ $h = "sha256_" + $h.Substring(7) }')
[void]$L.Add('  $h = $h -replace '[<>:"/\\|?*]+','_')
[void]$L.Add('  $h = $h -replace '\s+','_')
[void]$L.Add('  $h = $h.Trim('.')')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($h)){ RIE-HashDie "HASH_SANITIZE_EMPTY" }')
[void]$L.Add('  return $h')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-ResolveByHash([string]$RepoRoot,[string]$Hash){')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-HashDie "REPO_ROOT_EMPTY" }')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($Hash)){ RIE-HashDie "HASH_EMPTY" }')
[void]$L.Add('  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$L.Add('  $store = Join-Path $RepoRoot "store\by_hash"')
[void]$L.Add('  $safe = RIE-SanitizeHashForFileName $Hash')
[void]$L.Add('  $p = Join-Path $store ($safe + ".json")')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ RIE-HashDie ("HASH_NOT_FOUND: " + $Hash) }')
[void]$L.Add('  return $p')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-PublishFileToHashStore([string]$RepoRoot,[string]$InputPath){')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-HashDie "REPO_ROOT_EMPTY" }')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($InputPath)){ RIE-HashDie "INPUT_PATH_EMPTY" }')
[void]$L.Add('  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $InputPath -PathType Leaf)){ RIE-HashDie ("FILE_MISSING: " + $InputPath) }')
[void]$L.Add('  $hash = RIE-HashFileUtf8NoBomLf $InputPath')
[void]$L.Add('  $safe = RIE-SanitizeHashForFileName $hash')
[void]$L.Add('  $store = Join-Path $RepoRoot "store\by_hash"')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $store -PathType Container)){ New-Item -ItemType Directory -Force -Path $store | Out-Null }')
[void]$L.Add('  $dest = Join-Path $store ($safe + ".json")')
[void]$L.Add('  $content = RIE-ReadFileUtf8NoBomLfCanonical $InputPath')
[void]$L.Add('  $enc = New-Object System.Text.UTF8Encoding($false)')
[void]$L.Add('  [System.IO.File]::WriteAllText($dest, $content, $enc)')
[void]$L.Add('  [pscustomobject]@{ ok = $true; hash = $hash; stored_path = $dest; file_key = $safe }')
[void]$L.Add('}')
$hashText = (@($L.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $HashScript $hashText
Parse-GateFile $HashScript
Write-Host ("PATCH_HASH_STORE_OK: " + $HashScript) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
