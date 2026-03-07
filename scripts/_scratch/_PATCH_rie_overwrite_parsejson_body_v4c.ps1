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

$txt = Read-Utf8NoBom $Lib
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

$newFn = @"
function RIE-ParseJson([string]`$Path){
  if(-not (Test-Path -LiteralPath `$Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + `$Path) }
  `$b = `$null
  `$s = ""
  try {
    `$b = [System.IO.File]::ReadAllBytes(`$Path)
    `$enc = New-Object System.Text.UTF8Encoding(`$false,`$true)
    `$s = `$enc.GetString(`$b)
    if([string]::IsNullOrWhiteSpace(`$s)){ RIE-Die ("JSON_EMPTY: " + `$Path) }
    if(`$s.Length -gt 0 -and [int][char]`$s[0] -eq 65279){ `$s = `$s.Substring(1) } # BOM
    `$s = `$s.Replace("`r`n","`n").Replace("`r","`n")
    `$obj = (`$s | ConvertFrom-Json -Depth 32 -ErrorAction Stop)
    return `$obj
  } catch {
    `$m = `$_.Exception.Message
    if([string]::IsNullOrWhiteSpace(`$m)){ `$m = (`$_ | Out-String) }
    `$m = (`$m -replace "(\r\n|\r|\n)"," | ")

    # hex prefix (first 24 bytes) + first char code
    `$hex = ""
    if(`$b -ne `$null -and `$b.Length -gt 0){
      `$take = 24; if(`$b.Length -lt `$take){ `$take = `$b.Length }
      `$sb = New-Object System.Text.StringBuilder
      for(`$i=0; `$i -lt `$take; `$i++){
        [void]`$sb.AppendFormat("{0:x2}", `$b[`$i])
        if(`$i -lt (`$take-1)){ [void]`$sb.Append(" ") }
      }
      `$hex = `$sb.ToString()
    }

    `$fc = ""
    if(`$s -and `$s.Length -gt 0){ `$fc = ([int][char]`$s[0]).ToString() }

    RIE-Die ("JSON_PARSE_FAIL_V4C: " + `$Path + " :: " + `$m + " :: HEX_PREFIX=" + `$hex + " :: FIRST_CHAR_CODE=" + `$fc)
  }
}
"@

$pattern = '(?s)function\s+RIE-ParseJson\s*\([^)]*\)\s*\{.*?\n\}'
if($txt -match $pattern){
  $txt2 = [regex]::Replace($txt, $pattern, $newFn, 1)
} else {
  $txt2 = $txt.TrimEnd() + "`n`n" + $newFn + "`n"
}

Write-Utf8NoBomLf $Lib ($txt2.TrimEnd() + "`n")
Parse-GateFile $Lib

Write-Host ("PATCH_PARSEJSON_BODY_V4C_OK: " + $Lib) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
