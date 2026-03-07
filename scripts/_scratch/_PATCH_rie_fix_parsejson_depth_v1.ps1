param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$m){ throw $m }
function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("FILE_MISSING: " + $Path) }
  $b=[System.IO.File]::ReadAllBytes($Path)
  $enc=New-Object System.Text.UTF8Encoding($false,$true)
  $enc.GetString($b)
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir=Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t=$Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc=New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $msg = ($err | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Lib = Join-Path $RepoRoot "scripts\rie_lib_v1.ps1"
if(-not (Test-Path -LiteralPath $Lib -PathType Leaf)){ Die ("LIB_MISSING: " + $Lib) }
$bak = $Lib + ".bak_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Lib -Destination $bak -Force | Out-Null

$txt = Read-Utf8NoBom $Lib
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

# remove any previous override block (idempotent)
$txt = [regex]::Replace($txt, '(?s)\n# BEGIN_OVERRIDE_RIE_PARSEJSON_AND_HASHLOOKUP_V2\n.*?\n# END_OVERRIDE_RIE_PARSEJSON_AND_HASHLOOKUP_V2\n', "`n")
$txt = [regex]::Replace($txt, '(?s)\n# BEGIN_OVERRIDE_RIE_PARSEJSON_AND_HASHLOOKUP_V1\n.*?\n# END_OVERRIDE_RIE_PARSEJSON_AND_HASHLOOKUP_V1\n', "`n")

$A = New-Object System.Collections.Generic.List[string]
[void]$A.Add($txt.TrimEnd())
[void]$A.Add("")
[void]$A.Add("# BEGIN_OVERRIDE_RIE_PARSEJSON_AND_HASHLOOKUP_V2")
[void]$A.Add("# EOF override: PS uses last definition. PS5.1-safe ConvertFrom-Json -Depth 32.")
[void]$A.Add("")

function RIE-DeepToHashtable($v){
  if($null -eq $v){ return $null }
  if($v -is [System.Collections.IDictionary]){
    $h=@{}; foreach($k in $v.Keys){ $h[[string]$k]=RIE-DeepToHashtable $v[$k] }; return $h
  }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $L = New-Object System.Collections.Generic.List[object]
    foreach($x in $v){ [void]$L.Add((RIE-DeepToHashtable $x)) }
    return $L.ToArray()
  }
  if($v -is [psobject] -and $v.PSObject -and $v.PSObject.Properties){
    $names=@($v.PSObject.Properties.Name)
    if($names.Count -gt 0){
      $h2=@{}; foreach($n in $names){ $h2[[string]$n]=RIE-DeepToHashtable ($v.$n) }; return $h2
    }
  }
  return $v
}

function RIE-ParseJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }
  try {
    $b = [System.IO.File]::ReadAllBytes($Path)
    $enc = New-Object System.Text.UTF8Encoding($false,$true)
    $s = $enc.GetString($b)
    if([string]::IsNullOrWhiteSpace($s)){ RIE-Die ("JSON_EMPTY: " + $Path) }
    if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }
    $s = $s.Replace("`r`n","`n").Replace("`r","`n")
    # PS5.1 default depth is 2 -> MUST raise for nested objects
    $obj = ($s | ConvertFrom-Json -Depth 32 -ErrorAction Stop)
    return (RIE-DeepToHashtable $obj)
  } catch {
    $m = $_.Exception.Message
    if([string]::IsNullOrWhiteSpace($m)){ $m = ($_ | Out-String) }
    # single-line message to avoid truncation
    $m = ($m -replace "(\r\n|\r|\n)"," | ")
    RIE-Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $m)
  }
}

function RIE-Sha256Hex([byte[]]$Bytes){
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try{ $h=$sha.ComputeHash($Bytes); $sb=New-Object System.Text.StringBuilder; foreach($x in $h){ [void]$sb.AppendFormat("{0:x2}",$x) }; $sb.ToString() } finally { $sha.Dispose() }
}
function RIE-HashFileUtf8NoBomLf([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }
  $b=[System.IO.File]::ReadAllBytes($Path)
  $enc=New-Object System.Text.UTF8Encoding($false,$true)
  $s=$enc.GetString($b)
  if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }
  $s=$s.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $s.EndsWith("`n")){ $s += "`n" }
  $enc2=New-Object System.Text.UTF8Encoding($false)
  $bytes=$enc2.GetBytes($s)
  return ("sha256:" + (RIE-Sha256Hex $bytes))
}
function RIE-ResolveByHash([string]$RepoRoot,[string]$Hash){
  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-Die "REPO_ROOT_EMPTY" }
  if([string]::IsNullOrWhiteSpace($Hash)){ RIE-Die "HASH_EMPTY" }
  $RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
  $store=Join-Path $RepoRoot "store\by_hash"
  $safe=$Hash.Trim() -replace '[^\w:\-]+' , '_'
  $p=Join-Path $store ($safe + ".json")
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ RIE-Die ("HASH_NOT_FOUND: " + $Hash) }
  return $p
}

[void]$A.Add("# END_OVERRIDE_RIE_PARSEJSON_AND_HASHLOOKUP_V2")

$patched = (@($A.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $Lib $patched
Parse-GateFile $Lib
Write-Host ("PATCH_RIE_PARSEJSON_DEPTH_OK: " + $Lib) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
