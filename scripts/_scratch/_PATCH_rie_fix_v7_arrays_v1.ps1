param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$RunnerRel = "scripts\_scratch\_RUN_rie_overwrite_v7.ps1"
)

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
$Runner = Join-Path $RepoRoot $RunnerRel
if(-not (Test-Path -LiteralPath $Runner -PathType Leaf)){ Die ("RUNNER_MISSING: " + $Runner) }

$bak = $Runner + ".bak_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Runner -Destination $bak -Force | Out-Null

$txt = Read-Utf8NoBom $Runner
$lines = $txt.Replace("`r`n","`n").Replace("`r","`n") -split "`n", -1

# Replacement blocks (comma-separated array literal items)
$srcReplace = New-Object System.Collections.Generic.List[string]
[void]$srcReplace.Add('$srcLines = @(')
[void]$srcReplace.Add('  ''{'',')
[void]$srcReplace.Add('  ''  "schema": "rie.source_record.v1",'',')
[void]$srcReplace.Add('  ''  "source_id": "s_vid_001",'',')
[void]$srcReplace.Add('  ''  "content_kind": "video",'',')
[void]$srcReplace.Add('  ''  "title": "Example Lecture",'',')
[void]$srcReplace.Add('  ''  "provenance": { "discovered_from": "https://example.edu/course/page", "retrieved_at_utc": "2026-02-23T00:00:00Z" },'',')
[void]$srcReplace.Add('  ''  "tags": ["demo"]'',')
[void]$srcReplace.Add('  ''}''')
[void]$srcReplace.Add(')')
[void]$srcReplace.Add('$src = ($srcLines -join "`n")')

$badReplace = New-Object System.Collections.Generic.List[string]
[void]$badReplace.Add('$badLines = @(')
[void]$badReplace.Add('  ''{'',')
[void]$badReplace.Add('  ''  "schema": "rie.source_record.v1",'',')
[void]$badReplace.Add('  ''  "source_id": "s_bad_001",'',')
[void]$badReplace.Add('  ''  "content_kind": "video",'',')
[void]$badReplace.Add('  ''  "title": "Bad Example",'',')
[void]$badReplace.Add('  ''  "provenance": { "discovered_from": "x", "retrieved_at_utc": "y" },'',')
[void]$badReplace.Add('  ''  "answer": "NOPE"'',')
[void]$badReplace.Add('  ''}''')
[void]$badReplace.Add(')')
[void]$badReplace.Add('$bad = ($badLines -join "`n")')

# State machine patch
$out = New-Object System.Collections.Generic.List[string]
$inSrc = $false
$inBad = $false
$skipNextSrcAssign = $false
$skipNextBadAssign = $false
$hitSrc = $false
$hitBad = $false

for($i=0; $i -lt $lines.Length; $i++){
  $ln = $lines[$i]

  if($skipNextSrcAssign){
    $skipNextSrcAssign = $false
    if($ln -match '^\s*\$src\s*=\s*\(\s*\$srcLines\s*-join\s*"`n"\s*\)\s*$'){ continue }
  }
  if($skipNextBadAssign){
    $skipNextBadAssign = $false
    if($ln -match '^\s*\$bad\s*=\s*\(\s*\$badLines\s*-join\s*"`n"\s*\)\s*$'){ continue }
  }

  if(-not $inSrc -and -not $inBad){
    if($ln -match '^\s*\$srcLines\s*=\s*@\(\s*$'){
      $inSrc = $true
      $hitSrc = $true
      foreach($x in @($srcReplace.ToArray())){ [void]$out.Add($x) }
      continue
    }
    if($ln -match '^\s*\$badLines\s*=\s*@\(\s*$'){
      $inBad = $true
      $hitBad = $true
      foreach($x in @($badReplace.ToArray())){ [void]$out.Add($x) }
      continue
    }

    [void]$out.Add($ln)
    continue
  }

  # We are inside a block: skip until closing ')'
  if($inSrc){
    if($ln -match '^\s*\)\s*$'){
      $inSrc = $false
      $skipNextSrcAssign = $true
    }
    continue
  }
  if($inBad){
    if($ln -match '^\s*\)\s*$'){
      $inBad = $false
      $skipNextBadAssign = $true
    }
    continue
  }
}

if(-not $hitSrc){ Die "PATCH_FAIL_SRCBLOCK_NOT_FOUND_LINEWISE" }
if(-not $hitBad){ Die "PATCH_FAIL_BADBLOCK_NOT_FOUND_LINEWISE" }

$patched = (@($out.ToArray()) -join "`n")
Write-Utf8NoBomLf $Runner ($patched + "`n")
Parse-GateFile $Runner

Write-Host ("PATCH_RIE_V7_ARRAYS_OK: " + $Runner) -ForegroundColor Green
Write-Host ("BACKUP: " + $bak) -ForegroundColor DarkGray
