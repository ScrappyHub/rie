param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "WRITE_PATH_EMPTY" }
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
function Run-Child([string]$ScriptPath,[hashtable]$ArgMap,[string]$OutLog,[string]$ErrLog){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_MISSING: " + $ScriptPath) }
  $psExe = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
  $args = New-Object System.Collections.Generic.List[string]
  [void]$args.Add("-NoProfile")
  [void]$args.Add("-NonInteractive")
  [void]$args.Add("-ExecutionPolicy")
  [void]$args.Add("Bypass")
  [void]$args.Add("-File")
  [void]$args.Add($ScriptPath)
  foreach($k in @(@($ArgMap.Keys))){
    [void]$args.Add("-" + [string]$k)
    $v = $ArgMap[$k]
    if($null -eq $v){ $v = "" }
    [void]$args.Add([string]$v)
  }
  Ensure-Dir (Split-Path -Parent $OutLog)
  Ensure-Dir (Split-Path -Parent $ErrLog)
  $p = Start-Process -FilePath $psExe -ArgumentList $args.ToArray() -Wait -PassThru -NoNewWindow -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
  if($p.ExitCode -ne 0){ Die ("CHILD_FAIL_EXITCODE: " + $p.ExitCode) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Scripts = Join-Path $RepoRoot "scripts"
$Schemas = Join-Path $RepoRoot "schemas"
$TV      = Join-Path $RepoRoot "test_vectors"
$Proofs  = Join-Path $RepoRoot "proofs\receipts"
$Logs    = Join-Path $RepoRoot "proofs\logs"
Ensure-Dir $Scripts
Ensure-Dir $Schemas
Ensure-Dir $TV
Ensure-Dir $Proofs
Ensure-Dir $Logs

Write-Host "RIE_OVERWRITE_V5_START" -ForegroundColor Cyan

# 1) Schemas (SAFE here-strings)
$schemaSourceRecord = @'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RIE Source Record v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema","source_id","content_kind","title","provenance"],
  "properties": {
    "schema": { "const": "rie.source_record.v1" },
    "source_id": { "type": "string", "minLength": 1 },
    "content_kind": { "type": "string", "minLength": 1 },
    "title": { "type": "string", "minLength": 1 },
    "provenance": {
      "type": "object",
      "additionalProperties": false,
      "required": ["discovered_from","retrieved_at_utc"],
      "properties": {
        "discovered_from": { "type": "string", "minLength": 1 },
        "retrieved_at_utc": { "type": "string", "minLength": 1 }
      }
    },
    "tags": { "type": "array", "items": { "type": "string" } }
  }
}
