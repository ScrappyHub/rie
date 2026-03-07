param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
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

$L = New-Object System.Collections.Generic.List[string]
[void]$L.Add("Set-StrictMode -Version Latest")
[void]$L.Add("$ErrorActionPreference=`"Stop`"")
[void]$L.Add("")
[void]$L.Add("function RIE-Die([string]$m){ throw $m }")
[void]$L.Add("")
[void]$L.Add("function RIE-ParseJson([string]$Path){")
[void]$L.Add('  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }')
[void]$L.Add('  $b=$null; $s=""')
[void]$L.Add('  try { ')
[void]$L.Add('    $b=[System.IO.File]::ReadAllBytes($Path)')
[void]$L.Add('    $enc=New-Object System.Text.UTF8Encoding($false,$true)')
[void]$L.Add('    $s=$enc.GetString($b)')
[void]$L.Add('    if([string]::IsNullOrWhiteSpace($s)){ RIE-Die ("JSON_EMPTY: " + $Path) }')
[void]$L.Add('    if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s=$s.Substring(1) }')
[void]$L.Add('    $s=$s.Replace("`r`n","`n").Replace("`r","`n")')
[void]$L.Add('    $obj=($s | ConvertFrom-Json -Depth 32 -ErrorAction Stop)')
[void]$L.Add('    return $obj')
[void]$L.Add('  } catch { ')
[void]$L.Add('    $m=$_.Exception.Message')
[void]$L.Add('    if([string]::IsNullOrWhiteSpace($m)){ $m=($_ | Out-String) }')
[void]$L.Add('    $m=($m -replace "(\r\n|\r|\n)"," | ")')
[void]$L.Add('    $hex=""; if($b -ne $null -and $b.Length -gt 0){ $take=24; if($b.Length -lt $take){ $take=$b.Length }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $take;$i++){ [void]$sb.AppendFormat("{0:x2}",$b[$i]); if($i -lt ($take-1)){ [void]$sb.Append(" ") } }; $hex=$sb.ToString() }')
[void]$L.Add('    $fc=""; if($s -and $s.Length -gt 0){ $fc=([int][char]$s[0]).ToString() }')
[void]$L.Add('    RIE-Die ("JSON_PARSE_FAIL_V4C: " + $Path + " :: " + $m + " :: HEX_PREFIX=" + $hex + " :: FIRST_CHAR_CODE=" + $fc)')
[void]$L.Add('  }')
[void]$L.Add("}")
[void]$L.Add("}")

$libText = (@($L.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $Lib $libText
Parse-GateFile $Lib
Write-Host ("PATCH_RIE_LIB_KNOWN_GOOD_V2_OK: " + $Lib) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
