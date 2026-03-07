param([Parameter(Mandatory=$false)][string]$RepoRoot="C:\dev\rie")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($t))
}
function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){ $msg = ($err | ForEach-Object { $_.ToString() }) -join "`n"; Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg) }
}
function Run-Child([string]$ScriptPath,[hashtable]$ArgMap,[string]$OutLog,[string]$ErrLog){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }
  $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  $args = New-Object System.Collections.Generic.List[string]
  [void]$args.Add("-NoProfile"); [void]$args.Add("-NonInteractive"); [void]$args.Add("-ExecutionPolicy"); [void]$args.Add("Bypass"); [void]$args.Add("-File"); [void]$args.Add($ScriptPath)
  foreach($k in @(@($ArgMap.Keys))){ [void]$args.Add(("-" + [string]$k)); [void]$args.Add([string]$ArgMap[$k]) }
  $p = Start-Process -FilePath $psExe -ArgumentList @($args.ToArray()) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
  if($p.ExitCode -ne 0){
    $o=""; $e=""
    if(Test-Path -LiteralPath $OutLog -PathType Leaf){ $o = (Get-Content -Raw -LiteralPath $OutLog) }
    if(Test-Path -LiteralPath $ErrLog -PathType Leaf){ $e = (Get-Content -Raw -LiteralPath $ErrLog) }
    Die ("CHILD_FAIL_EXITCODE=" + $p.ExitCode + "`n---STDOUT---`n" + $o + "`n---STDERR---`n" + $e)
  }
}

if([string]::IsNullOrWhiteSpace($RepoRoot)){ Die "REPOROOT_EMPTY" }
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("REPOROOT_MISSING: " + $RepoRoot) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Docs    = Join-Path $RepoRoot "docs"
$Schemas = Join-Path $RepoRoot "schemas"
$TVMin   = Join-Path $RepoRoot "test_vectors\minimal"
$TVNeg   = Join-Path $RepoRoot "test_vectors\negative"
$Scripts = Join-Path $RepoRoot "scripts"
$Proofs  = Join-Path $RepoRoot "proofs"
$Logs    = Join-Path $Proofs  "transcripts"
EnsureDir $Docs; EnsureDir $Schemas; EnsureDir $TVMin; EnsureDir $TVNeg; EnsureDir $Scripts; EnsureDir $Logs

Write-Host "RIE_OVERWRITE_V2_START" -ForegroundColor Cyan
Write-Host ("REPOROOT: " + $RepoRoot)

# -----------------------------
# Docs
# -----------------------------
Write-Utf8NoBomLf (Join-Path $RepoRoot "README.md") ("# Research Infrastructure Engine (RIE)`n`n" +
  "RIE is a STEM retrieval + evidence instrument.`n`n" +
  "Inputs: keywords, formulas, images/diagrams references.`n" +
  "Outputs: verified educational sources with provenance + credential/trust signals.`n`n" +
  "RIE is **not** an answer engine: no final answers, no step-by-step solutions, no writing assistance.`n")
Write-Utf8NoBomLf (Join-Path $Docs "INSTRUMENT_CONSTITUTION_V1.md") ("# Instrument Constitution v1 (No-Answers Rule)`n`n" +
  "MUST NOT output: answer/solution/steps/explanation or any worked solution content.`n" +
  "MAY output: sources, citations, timestamps, section/page pointers, provenance, trust signals.`n")
Write-Utf8NoBomLf (Join-Path $Docs "TRUST_MODEL_V1.md") ("# Trust Model v1`n`n" +
  "- Tier A: institutional/archival (universities, publishers, DOI registries, government)`n" +
  "- Tier B: verified experts (ORCID + institutional presence)`n" +
  "- Tier C: community educators (allowed, labeled)`n")

# -----------------------------
# Schemas
# -----------------------------
Write-Utf8NoBomLf (Join-Path $Schemas "rie.query_record.v1.schema.json") ("{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "rie.query_record.v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema","query_id","created_at_utc","inputs","intent"],
  "properties": {
    "schema": { "const": "rie.query_record.v1" },
    "query_id": { "type": "string" },
    "created_at_utc": { "type": "string", "format": "date-time" },
    "intent": { "type": "string", "enum": ["learn","find_sources","build_bibliography","watch_lecture","read_textbook","lab_protocols"] },
    "inputs": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["kind"],
        "properties": {
          "kind": { "type": "string", "enum": ["keywords","formula_latex","image_ref","diagram_ref","dataset_ref","url_ref"] },
          "text": { "type": "string" },
          "ref":  { "type": "string" },
          "mime": { "type": "string" }
        }
      }
    }
  }
}
" )
$Embed = New-Object System.Collections.Generic.List[string]
# Remaining schemas, vectors, and full selftest payload (v2 embed)
[void]$Embed.Add("EMBED_BLOCK_V2_START")
Write-Utf8NoBomLf (Join-Path $Scripts "_WRITE_rie_payload_v2.ps1") ("Set-StrictMode -Version Latest`n$ErrorActionPreference=`"Stop`"`nWrite-Host `"RIE_PAYLOAD_WRITER_V2_TODO`"")
Parse-GateFile (Join-Path $Scripts "_WRITE_rie_payload_v2.ps1")

# Selftest placeholder will be overwritten by payload-writer v2 in the next step
Write-Utf8NoBomLf (Join-Path $Scripts "_selftest_rie_schemas_v1.ps1") ("param([string]$RepoRoot=`"`")`nSet-StrictMode -Version Latest`n$ErrorActionPreference=`"Stop`"`nthrow `"SELFTEST_NOT_WRITTEN_YET_V2`"`n")
Parse-GateFile (Join-Path $Scripts "_selftest_rie_schemas_v1.ps1")

$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$outLog = Join-Path $Logs ("overwrite_v2_stdout_" + $ts + ".log")
$errLog = Join-Path $Logs ("overwrite_v2_stderr_" + $ts + ".log")
Write-Utf8NoBomLf $outLog "RIE_OVERWRITE_V2_TRANSCRIPT_PLACEHOLDER`n"
Write-Utf8NoBomLf $errLog ""
Write-Host ("TRANSCRIPTS_READY: " + $outLog) -ForegroundColor Yellow
Write-Host "RIE_OVERWRITE_V2_OK_PARTIAL" -ForegroundColor Green
Write-Host "NEXT: APPLY_PAYLOAD_WRITER_V2" -ForegroundColor Yellow
