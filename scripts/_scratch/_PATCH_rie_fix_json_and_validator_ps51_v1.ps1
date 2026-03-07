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

function DeepToHashtable($v){
  if($null -eq $v){ return $null }
  if($v -is [System.Collections.IDictionary]){
    $h=@{}
    foreach($k in $v.Keys){ $h[[string]$k] = DeepToHashtable $v[$k] }
    return $h
  }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $L = New-Object System.Collections.Generic.List[object]
    foreach($x in $v){ [void]$L.Add((DeepToHashtable $x)) }
    return $L.ToArray()
  }
  return $v
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Lib = Join-Path $RepoRoot "scripts\rie_lib_v1.ps1"
if(-not (Test-Path -LiteralPath $Lib -PathType Leaf)){ Die ("LIB_MISSING: " + $Lib) }

$bak = $Lib + ".bak_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Lib -Destination $bak -Force | Out-Null

$txt = Read-Utf8NoBom $Lib
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

# --- Known-good PS5.1 JSON + validator block (replace-or-append) ---

$block = @"
function RIE-ParseJson([string]`$Path){
  if(-not (Test-Path -LiteralPath `$Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + `$Path) }
  try{
    `$b = [System.IO.File]::ReadAllBytes(`$Path)
    `$enc = New-Object System.Text.UTF8Encoding(`$false,`$true)
    `$s = `$enc.GetString(`$b)
    if([string]::IsNullOrWhiteSpace(`$s)){ RIE-Die ("JSON_EMPTY: " + `$Path) }
    if(`$s.Length -gt 0 -and [int][char]`$s[0] -eq 65279){ `$s = `$s.Substring(1) } # BOM
    `$s = `$s.Replace("`r`n","`n").Replace("`r","`n")

    # PS5.1-safe: JavaScriptSerializer (no ConvertFrom-Json -Depth)
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    `$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    `$ser.RecursionLimit = 256
    `$ser.MaxJsonLength = 2147483647
    `$obj = `$ser.DeserializeObject(`$s)

    return (DeepToHashtable `$obj)
  } catch {
    `$m = `$_.Exception.Message
    if([string]::IsNullOrWhiteSpace(`$m)){ `$m = (`$_ | Out-String) }
    `$m = (`$m -replace "(\r\n|\r|\n)"," | ")
    RIE-Die ("JSON_PARSE_FAIL: " + `$Path + " :: " + `$m)
  }
}

function RIE-ValidateSourceRecordV1(`$o,[string]`$ctx){
  if(`$null -eq `$o){ RIE-Die ("SRC_NULL: " + `$ctx) }
  if(-not (`$o -is [hashtable])){ RIE-Die ("SRC_NOT_OBJECT: " + `$ctx) }

  foreach(`$k in @("schema","source_id","content_kind","title","provenance","tags")){
    if(-not `$o.ContainsKey(`$k)){ RIE-Die ("MISSING_PROP:" + `$k + ":" + `$ctx) }
  }

  if(`$o["schema"] -ne "rie.source_record.v1"){ RIE-Die ("BAD_SCHEMA:" + [string]`$o["schema"] + ":" + `$ctx) }

  # forbid prop: answer
  if(`$o.ContainsKey("answer")){ RIE-Die ("FORBIDDEN_PROP:answer:" + `$ctx) }

  # provenance object must contain discovered_from and retrieved_at_utc
  `$p = `$o["provenance"]
  if(-not (`$p -is [hashtable])){ RIE-Die ("PROVENANCE_NOT_OBJECT:" + `$ctx) }
  foreach(`$k2 in @("discovered_from","retrieved_at_utc")){
    if(-not `$p.ContainsKey(`$k2)){ RIE-Die ("MISSING_PROP:provenance." + `$k2 + ":" + `$ctx) }
  }

  # tags must be array
  `$t = `$o["tags"]
  if(-not (`$t -is [object[]])){ RIE-Die ("TAGS_NOT_ARRAY:" + `$ctx) }
}
"@

$fnPattern1 = '(?s)function\s+RIE-ParseJson\s*\([^)]*\)\s*\{.*?\n\}'
$fnPattern2 = '(?s)function\s+RIE-ValidateSourceRecordV1\s*\([^)]*\)\s*\{.*?\n\}'

$txt2 = $txt
if($txt2 -match $fnPattern1){ $txt2 = [regex]::Replace($txt2, $fnPattern1, ($block -split "function RIE-ValidateSourceRecordV1")[0].TrimEnd(), 1) }
if($txt2 -match $fnPattern2){
  # replace validator too (extract second function)
  $parts = $block -split "function RIE-ValidateSourceRecordV1"
  $valFn = ("function RIE-ValidateSourceRecordV1" + $parts[1]).TrimEnd()
  $txt2 = [regex]::Replace($txt2, $fnPattern2, $valFn, 1)
} else {
  $txt2 = $txt2.TrimEnd() + "`n`n" + $block.TrimEnd() + "`n"
}

Write-Utf8NoBomLf $Lib ($txt2.TrimEnd() + "`n")
Parse-GateFile $Lib

Write-Host ("PATCH_RIE_JSON_AND_VALIDATOR_PS51_OK: " + $Lib) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
