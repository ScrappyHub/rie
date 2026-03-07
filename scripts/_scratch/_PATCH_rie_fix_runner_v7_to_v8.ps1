param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("FILE_MISSING: " + $Path) }
  $b = [System.IO.File]::ReadAllBytes($Path)
  $enc = New-Object System.Text.UTF8Encoding($false,$true)
  $enc.GetString($b)
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
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
$Runner = Join-Path $RepoRoot "scripts\_scratch\_RUN_rie_overwrite_v7.ps1"
if(-not (Test-Path -LiteralPath $Runner -PathType Leaf)){ Die ("RUNNER_V7_MISSING: " + $Runner) }

$bak = $Runner + ".bak_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Runner -Destination $bak -Force | Out-Null

$txt = Read-Utf8NoBom $Runner

# Replace $srcLines block (array items must be comma-separated in PowerShell)
$srcBlockRe = '(?s)\$srcLines\s*=\s*@\(\s*.*?\s*\)\s*\$src\s*=\s*\(\$srcLines\s*-join\s*"`n"\)'
$srcBlockNew = @(
'$srcLines = @(',
'  ''{'',',
'  ''  "schema": "rie.source_record.v1",'',',
'  ''  "source_id": "s_vid_001",'',',
'  ''  "content_kind": "video",'',',
'  ''  "title": "Example Lecture",'',',
'  ''  "provenance": { "discovered_from": "https://example.edu/course/page", "retrieved_at_utc": "2026-02-23T00:00:00Z" },'',',
'  ''  "tags": ["demo"]'',',
'  ''}''',
')',
'$src = ($srcLines -join "`n")'
) -join "`n"

$txt2 = [regex]::Replace($txt, $srcBlockRe, $srcBlockNew, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if($txt2 -eq $txt){ Die "PATCH_FAIL_SRCBLOCK_NOT_FOUND" }

# Replace $badLines block
$badBlockRe = '(?s)\$badLines\s*=\s*@\(\s*.*?\s*\)\s*\$bad\s*=\s*\(\$badLines\s*-join\s*"`n"\)'
$badBlockNew = @(
'$badLines = @(',
'  ''{'',',
'  ''  "schema": "rie.source_record.v1",'',',
'  ''  "source_id": "s_bad_001",'',',
'  ''  "content_kind": "video",'',',
'  ''  "title": "Bad Example",'',',
'  ''  "provenance": { "discovered_from": "x", "retrieved_at_utc": "y" },'',',
'  ''  "answer": "NOPE"'',',
'  ''}''',
')',
'$bad = ($badLines -join "`n")'
) -join "`n"

$txt3 = [regex]::Replace($txt2, $badBlockRe, $badBlockNew, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if($txt3 -eq $txt2){ Die "PATCH_FAIL_BADBLOCK_NOT_FOUND" }

Write-Utf8NoBomLf $Runner ($txt3 + "`n")
Parse-GateFile $Runner

Write-Host ("PATCH_V7_TO_V8_OK: " + $Runner) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
