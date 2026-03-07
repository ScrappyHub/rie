param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
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
  if($errs -and $errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Lib = Join-Path $RepoRoot "scripts\rie_lib_v1.ps1"
if(-not (Test-Path -LiteralPath $Lib -PathType Leaf)){ Die ("LIB_MISSING: " + $Lib) }

$bak = $Lib + ".bak_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Lib -Destination $bak -Force | Out-Null

# ---------------------------------------------------------
# Known-good lib content (NO patcher-time $var expansion)
# ---------------------------------------------------------
$L = New-Object System.Collections.Generic.List[string]

[void]$L.Add('Set-StrictMode -Version Latest')
[void]$L.Add('$ErrorActionPreference="Stop"')
[void]$L.Add('')
[void]$L.Add('function RIE-Die([string]$m){ throw $m }')
[void]$L.Add('')

[void]$L.Add('function RIE-HexPrefix([byte[]]$b,[int]$n){')
[void]$L.Add('  if($null -eq $b){ return "" }')
[void]$L.Add('  if($n -lt 1){ $n = 1 }')
[void]$L.Add('  $take = $n; if($b.Length -lt $take){ $take = $b.Length }')
[void]$L.Add('  $sb = New-Object System.Text.StringBuilder')
[void]$L.Add('  for($i=0; $i -lt $take; $i++){')
[void]$L.Add('    [void]$sb.AppendFormat("{0:x2}", $b[$i])')
[void]$L.Add('    if($i -lt ($take-1)){ [void]$sb.Append(" ") }')
[void]$L.Add('  }')
[void]$L.Add('  return $sb.ToString()')
[void]$L.Add('}')
[void]$L.Add('')

[void]$L.Add('function RIE-ParseJson([string]$Path){')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }')
[void]$L.Add('  $b=$null; $s=""')
[void]$L.Add('  try {')
[void]$L.Add('    $b = [System.IO.File]::ReadAllBytes($Path)')
[void]$L.Add('    $enc = New-Object System.Text.UTF8Encoding($false,$true)')
[void]$L.Add('    $s = $enc.GetString($b)')
[void]$L.Add('    if([string]::IsNullOrWhiteSpace($s)){ RIE-Die ("JSON_EMPTY: " + $Path) }')
[void]$L.Add('    if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }') # BOM
[void]$L.Add('    $s = $s.Replace("`r`n","`n").Replace("`r","`n")')
[void]$L.Add('    $obj = ($s | ConvertFrom-Json -Depth 32 -ErrorAction Stop)')
[void]$L.Add('    return $obj')
[void]$L.Add('  } catch {')
[void]$L.Add('    $m = $_.Exception.Message')
[void]$L.Add('    if([string]::IsNullOrWhiteSpace($m)){ $m = ($_ | Out-String) }')
[void]$L.Add('    $m = ($m -replace ''(\r\n|\r|\n)'','' | '')')
[void]$L.Add('    $hex = RIE-HexPrefix $b 24')
[void]$L.Add('    $fc = ""; if($s -and $s.Length -gt 0){ $fc = ([int][char]$s[0]).ToString() }')
[void]$L.Add('    RIE-Die ("JSON_PARSE_FAIL_V4C: " + $Path + " :: " + $m + " :: HEX_PREFIX=" + $hex + " :: FIRST_CHAR_CODE=" + $fc)')
[void]$L.Add('  }')
[void]$L.Add('}')
[void]$L.Add('')

[void]$L.Add('function RIE-Sha256Hex([byte[]]$Bytes){')
[void]$L.Add('  $sha=[System.Security.Cryptography.SHA256]::Create()')
[void]$L.Add('  try{')
[void]$L.Add('    $h=$sha.ComputeHash($Bytes)')
[void]$L.Add('    $sb=New-Object System.Text.StringBuilder')
[void]$L.Add('    foreach($x in $h){ [void]$sb.AppendFormat("{0:x2}",$x) }')
[void]$L.Add('    return $sb.ToString()')
[void]$L.Add('  } finally { $sha.Dispose() }')
[void]$L.Add('}')
[void]$L.Add('')

[void]$L.Add('function RIE-HashFileUtf8NoBomLf([string]$Path){')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }')
[void]$L.Add('  $b=[System.IO.File]::ReadAllBytes($Path)')
[void]$L.Add('  $enc=New-Object System.Text.UTF8Encoding($false,$true)')
[void]$L.Add('  $s=$enc.GetString($b)')
[void]$L.Add('  if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }')
[void]$L.Add('  $s=$s.Replace("`r`n","`n").Replace("`r","`n")')
[void]$L.Add('  if(-not $s.EndsWith("`n")){ $s += "`n" }')
[void]$L.Add('  $enc2=New-Object System.Text.UTF8Encoding($false)')
[void]$L.Add('  $bytes=$enc2.GetBytes($s)')
[void]$L.Add('  return ("sha256:" + (RIE-Sha256Hex $bytes))')
[void]$L.Add('}')
[void]$L.Add('')

[void]$L.Add('function RIE-ResolveByHash([string]$RepoRoot,[string]$Hash){')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-Die "REPO_ROOT_EMPTY" }')
[void]$L.Add('  if([string]::IsNullOrWhiteSpace($Hash)){ RIE-Die "HASH_EMPTY" }')
[void]$L.Add('  $RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$L.Add('  $store=Join-Path $RepoRoot "store\by_hash"')
[void]$L.Add('  $safe=$Hash.Trim() -replace ''[^\w:\-]+'',''_''')
[void]$L.Add('  $p=Join-Path $store ($safe + ".json")')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ RIE-Die ("HASH_NOT_FOUND: " + $Hash) }')
[void]$L.Add('  return $p')
[void]$L.Add('}')

$libText = (@($L.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $Lib $libText
Parse-GateFile $Lib

Write-Host ("PATCH_RIE_LIB_KNOWN_GOOD_V3_OK: " + $Lib) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray