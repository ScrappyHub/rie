param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

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

# Write known-good minimal lib (PS5.1 safe)
$L = New-Object System.Collections.Generic.List[string]

[void]$L.Add('Set-StrictMode -Version Latest')
[void]$L.Add('$ErrorActionPreference = "Stop"')
[void]$L.Add('')
[void]$L.Add('function RIE-Die([string]$m){ throw $m }')
[void]$L.Add('')
[void]$L.Add('function RIE-DeepToHashtable($v){')
[void]$L.Add('  if($null -eq $v){ return $null }')
[void]$L.Add('  if($v -is [System.Collections.IDictionary]){')
[void]$L.Add('    $h=@{}')
[void]$L.Add('    foreach($k in $v.Keys){ $h[[string]$k] = RIE-DeepToHashtable $v[$k] }')
[void]$L.Add('    return $h')
[void]$L.Add('  }')
[void]$L.Add('  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){')
[void]$L.Add('    $arr = New-Object System.Collections.Generic.List[object]')
[void]$L.Add('    foreach($x in $v){ [void]$arr.Add((RIE-DeepToHashtable $x)) }')
[void]$L.Add('    return $arr.ToArray()')
[void]$L.Add('  }')
[void]$L.Add('  return $v')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-ParseJson([string]$Path){')
[void]$L.Add('  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }')
[void]$L.Add('  $b = $null')
[void]$L.Add('  $s = $null')
[void]$L.Add('  try {')
[void]$L.Add('    $b = [System.IO.File]::ReadAllBytes($Path)')
[void]$L.Add('    $enc = New-Object System.Text.UTF8Encoding($false,$true)')
[void]$L.Add('    $s = $enc.GetString($b)')
[void]$L.Add('    if([string]::IsNullOrWhiteSpace($s)){ RIE-Die ("JSON_EMPTY: " + $Path) }')
[void]$L.Add('    if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }')
[void]$L.Add('    $s = $s.Replace("`r`n","`n").Replace("`r","`n")')
[void]$L.Add('')
[void]$L.Add('    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop')
[void]$L.Add('    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer')
[void]$L.Add('    $ser.RecursionLimit = 256')
[void]$L.Add('    $ser.MaxJsonLength = 2147483647')
[void]$L.Add('    $obj = $ser.DeserializeObject($s)')
[void]$L.Add('    return (RIE-DeepToHashtable $obj)')
[void]$L.Add('  } catch {')
[void]$L.Add('    $m = $_.Exception.Message')
[void]$L.Add('    if([string]::IsNullOrWhiteSpace($m)){ $m = ($_ | Out-String) }')
[void]$L.Add('    $m = ($m -replace "(\r\n|\r|\n)"," | ")')
[void]$L.Add('    RIE-Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $m)')
[void]$L.Add('  }')
[void]$L.Add('}')
[void]$L.Add('')
[void]$L.Add('function RIE-ValidateSourceRecordV1($o,[string]$ctx){')
[void]$L.Add('  if($null -eq $o){ RIE-Die ("SRC_NULL: " + $ctx) }')
[void]$L.Add('  if(-not ($o -is [hashtable])){ RIE-Die ("SRC_NOT_OBJECT: " + $ctx) }')
[void]$L.Add('  foreach($k in @("schema","source_id","content_kind","title","provenance","tags")){')
[void]$L.Add('    if(-not $o.ContainsKey($k)){ RIE-Die ("MISSING_PROP:" + $k + ":" + $ctx) }')
[void]$L.Add('  }')
[void]$L.Add('  if([string]$o["schema"] -ne "rie.source_record.v1"){ RIE-Die ("BAD_SCHEMA:" + [string]$o["schema"] + ":" + $ctx) }')
[void]$L.Add('  if($o.ContainsKey("answer")){ RIE-Die ("FORBIDDEN_PROP:answer:" + $ctx) }')
[void]$L.Add('  $p = $o["provenance"]')
[void]$L.Add('  if(-not ($p -is [hashtable])){ RIE-Die ("PROVENANCE_NOT_OBJECT:" + $ctx) }')
[void]$L.Add('  foreach($k2 in @("discovered_from","retrieved_at_utc")){')
[void]$L.Add('    if(-not $p.ContainsKey($k2)){ RIE-Die ("MISSING_PROP:provenance." + $k2 + ":" + $ctx) }')
[void]$L.Add('  }')
[void]$L.Add('  $t = $o["tags"]')
[void]$L.Add('  if(-not ($t -is [object[]])){ RIE-Die ("TAGS_NOT_ARRAY:" + $ctx) }')
[void]$L.Add('}')
[void]$L.Add('')

$libText = (@($L.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $Lib $libText
Parse-GateFile $Lib

Write-Host ("PATCH_OVERWRITE_RIE_LIB_KNOWN_GOOD_PS51_OK: " + $Lib) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
