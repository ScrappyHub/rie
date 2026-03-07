param([Parameter(Mandatory=$false)][string]$RepoRoot="C:\dev\rie")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($t))
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
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }
  $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  $args = New-Object System.Collections.Generic.List[string]
  [void]$args.Add("-NoProfile")
  [void]$args.Add("-NonInteractive")
  [void]$args.Add("-ExecutionPolicy")
  [void]$args.Add("Bypass")
  [void]$args.Add("-File")
  [void]$args.Add($ScriptPath)
  foreach($k in @(@($ArgMap.Keys))){
    [void]$args.Add(("-" + [string]$k))
    [void]$args.Add([string]$ArgMap[$k])
  }
  $p = Start-Process -FilePath $psExe -ArgumentList @($args.ToArray()) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
  if($p.ExitCode -ne 0){
    $o=""; $e=""
    if(Test-Path -LiteralPath $OutLog -PathType Leaf){ $o = (Get-Content -Raw -LiteralPath $OutLog) }
    if(Test-Path -LiteralPath $ErrLog -PathType Leaf){ $e = (Get-Content -Raw -LiteralPath $ErrLog) }
    Die ("CHILD_FAIL_EXITCODE=" + $p.ExitCode + "`n---STDOUT---`n" + $o + "`n---STDERR---`n" + $e)
  }
}
function Write-Lines([string]$Path,[string[]]$Lines){
  $t = (@($Lines) -join "`n") + "`n"
  Write-Utf8NoBomLf $Path $t
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
$Logs    = Join-Path $Proofs "transcripts"

EnsureDir $Docs; EnsureDir $Schemas; EnsureDir $TVMin; EnsureDir $TVNeg; EnsureDir $Scripts; EnsureDir $Logs

Write-Host "RIE_OVERWRITE_V3_START" -ForegroundColor Cyan
Write-Host ("REPOROOT: " + $RepoRoot)

Write-Lines (Join-Path $RepoRoot "README.md") @(
  "# Research Infrastructure Engine (RIE)",
  "",
  "RIE is a STEM retrieval + evidence instrument.",
  "",
  "Inputs: keywords, formulas, references (image/diagram/dataset/url).",
  "Outputs: **sources + provenance + trust signals** (not answers).",
  "",
  "RIE is **not** an answer engine:",
  "- no final answers",
  "- no step-by-step solutions",
  "- no writing assistance / rewriting",
  "",
  "Folders:",
  "- docs/ (constitution, trust model)",
  "- schemas/ (canonical JSON schemas)",
  "- test_vectors/ (positive + negative vectors)",
  "- scripts/ (selftests / runners)"
)

Write-Lines (Join-Path $Docs "INSTRUMENT_CONSTITUTION_V1.md") @(
  "# Instrument Constitution v1 (No-Answers Rule)",
  "",
  "RIE outputs MUST NOT include fields:",
  "- answer",
  "- solution",
  "- steps",
  "- explanation",
  "",
  "RIE outputs MAY include:",
  "- sources + citations",
  "- timestamps / section pointers",
  "- provenance + trust signals",
  "",
  "This repo enforces the rule via schemas + selftests."
)

Write-Lines (Join-Path $Docs "TRUST_MODEL_V1.md") @(
  "# Trust Model v1",
  "",
  "- Tier A: institutional / archival (universities, publishers, DOI registries, government)",
  "- Tier B: verified experts (ORCID + institutional presence)",
  "- Tier C: community educators (allowed, labeled)"
)

Write-Lines (Join-Path $Schemas "rie.query_record.v1.schema.json") @(
  "{",
  "  ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",",
  "  ""$id"": ""https://schemas.rooted.dev/rie/rie.query_record.v1.schema.json"",",
  "  ""title"": ""rie.query_record.v1"",",
  "  ""type"": ""object"",",
  "  ""additionalProperties"": false,",
  "  ""required"": [""schema"",""query_id"",""created_at_utc"",""inputs"",""intent""],",
  "  ""properties"": {",
  "    ""schema"": { ""const"": ""rie.query_record.v1"" },",
  "    ""query_id"": { ""type"": ""string"" },",
  "    ""created_at_utc"": { ""type"": ""string"", ""format"": ""date-time"" },",
  "    ""intent"": { ""type"": ""string"", ""enum"": [""learn"",""find_sources"",""build_bibliography"",""watch_lecture"",""read_textbook"",""lab_protocols""] },",
  "    ""inputs"": {",
  "      ""type"": ""array"",",
  "      ""minItems"": 1,",
  "      ""items"": {",
  "        ""type"": ""object"",",
  "        ""additionalProperties"": false,",
  "        ""required"": [""kind""],",
  "        ""properties"": {",
  "          ""kind"": { ""type"": ""string"", ""enum"": [""keywords"",""formula_latex"",""image_ref"",""diagram_ref"",""dataset_ref"",""url_ref""] },",
  "          ""text"": { ""type"": ""string"" },",
  "          ""ref"":  { ""type"": ""string"" },",
  "          ""mime"": { ""type"": ""string"" }",
  "        }",
  "      }",
  "    }",
  "  }",
  "}"
)

Write-Lines (Join-Path $Schemas "rie.trust_signal.v1.schema.json") @(
  "{",
  "  ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",",
  "  ""$id"": ""https://schemas.rooted.dev/rie/rie.trust_signal.v1.schema.json"",",
  "  ""title"": ""rie.trust_signal.v1"",",
  "  ""type"": ""object"",",
  "  ""additionalProperties"": false,",
  "  ""required"": [""schema"",""signal_id"",""tier"",""kind"",""evidence"",""observed_at_utc""],",
  "  ""properties"": {",
  "    ""schema"": { ""const"": ""rie.trust_signal.v1"" },",
  "    ""signal_id"": { ""type"": ""string"" },",
  "    ""tier"": { ""type"": ""string"", ""enum"": [""A"",""B"",""C""] },",
  "    ""kind"": { ""type"": ""string"" },",
  "    ""evidence"": { ""type"": ""object"" },",
  "    ""observed_at_utc"": { ""type"": ""string"", ""format"": ""date-time"" }",
  "  }",
  "}"
)

Write-Lines (Join-Path $Schemas "rie.source_record.v1.schema.json") @(
  "{",
  "  ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",",
  "  ""$id"": ""https://schemas.rooted.dev/rie/rie.source_record.v1.schema.json"",",
  "  ""title"": ""rie.source_record.v1"",",
  "  ""type"": ""object"",",
  "  ""additionalProperties"": false,",
  "  ""required"": [""schema"",""source_id"",""content_kind"",""title"",""provenance""],",
  "  ""not"": {",
  "    ""anyOf"": [",
  "      { ""required"": [""answer""] },",
  "      { ""required"": [""solution""] },",
  "      { ""required"": [""steps""] },",
  "      { ""required"": [""explanation""] }",
  "    ]",
  "  },",
  "  ""properties"": {",
  "    ""schema"": { ""const"": ""rie.source_record.v1"" },",
  "    ""source_id"": { ""type"": ""string"" },",
  "    ""content_kind"": { ""type"": ""string"", ""enum"": [""video"",""textbook"",""paper"",""notes"",""dataset"",""protocol"",""course_page"",""syllabus""] },",
  "    ""title"": { ""type"": ""string"" },",
  "    ""provenance"": {",
  "      ""type"": ""object"",",
  "      ""additionalProperties"": false,",
  "      ""required"": [""discovered_from"",""retrieved_at_utc""],",
  "      ""properties"": {",
  "        ""discovered_from"": { ""type"": ""string"" },",
  "        ""retrieved_at_utc"": { ""type"": ""string"", ""format"": ""date-time"" }",
  "      }",
  "    }",
  "  }",
  "}"
)

Write-Lines (Join-Path $Schemas "rie.segment_pointer.v1.schema.json") @(
  "{",
  "  ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",",
  "  ""$id"": ""https://schemas.rooted.dev/rie/rie.segment_pointer.v1.schema.json"",",
  "  ""title"": ""rie.segment_pointer.v1"",",
  "  ""type"": ""object"",",
  "  ""additionalProperties"": false,",
  "  ""required"": [""schema"",""segment_id"",""source_id"",""kind"",""locator"",""matched_by"",""provenance""],",
  "  ""properties"": {",
  "    ""schema"": { ""const"": ""rie.segment_pointer.v1"" },",
  "    ""segment_id"": { ""type"": ""string"" },",
  "    ""source_id"": { ""type"": ""string"" },",
  "    ""kind"": { ""type"": ""string"" },",
  "    ""locator"": { ""type"": ""object"" },",
  "    ""matched_by"": { ""type"": ""object"" },",
  "    ""provenance"": { ""type"": ""object"" }",
  "  }",
  "}"
)

Write-Lines (Join-Path $Schemas "rie.evidence_bundle_manifest.v1.schema.json") @(
  "{",
  "  ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",",
  "  ""$id"": ""https://schemas.rooted.dev/rie/rie.evidence_bundle_manifest.v1.schema.json"",",
  "  ""title"": ""rie.evidence_bundle_manifest.v1"",",
  "  ""type"": ""object"",",
  "  ""additionalProperties"": false,",
  "  ""required"": [""schema"",""bundle_id"",""created_at_utc"",""query_id"",""items"",""provenance""],",
  "  ""properties"": {",
  "    ""schema"": { ""const"": ""rie.evidence_bundle_manifest.v1"" },",
  "    ""bundle_id"": { ""type"": ""string"" },",
  "    ""created_at_utc"": { ""type"": ""string"", ""format"": ""date-time"" },",
  "    ""query_id"": { ""type"": ""string"" },",
  "    ""items"": { ""type"": ""array"", ""minItems"": 1 },",
  "    ""provenance"": { ""type"": ""object"" }",
  "  }",
  "}"
)

Write-Lines (Join-Path $Schemas "rie.result_set.v1.schema.json") @(
  "{",
  "  ""$schema"": ""https://json-schema.org/draft/2020-12/schema"",",
  "  ""$id"": ""https://schemas.rooted.dev/rie/rie.result_set.v1.schema.json"",",
  "  ""title"": ""rie.result_set.v1"",",
  "  ""type"": ""object"",",
  "  ""additionalProperties"": false,",
  "  ""required"": [""schema"",""query_id"",""created_at_utc"",""results""],",
  "  ""properties"": {",
  "    ""schema"": { ""const"": ""rie.result_set.v1"" },",
  "    ""query_id"": { ""type"": ""string"" },",
  "    ""created_at_utc"": { ""type"": ""string"", ""format"": ""date-time"" },",
  "    ""results"": { ""type"": ""array"", ""minItems"": 1 }",
  }",
  "}"
)

Write-Lines (Join-Path $RepoRoot "test_vectors\README.md") @(
  "Positive vectors in minimal/ must PASS.",
  "Negative vectors in negative/ must FAIL (not FILE_MISSING).",
  "These enforce the No-Answers constitution and provenance requirements."
)

Write-Lines (Join-Path $TVMin "source_record_video.json") @(
  "{",
  "  ""schema"": ""rie.source_record.v1"",",
  "  ""source_id"": ""s_vid_001"",",
  "  ""content_kind"": ""video"",",
  "  ""title"": ""Convolution and Fourier Transform (Lecture)"",",
  "  ""provenance"": {",
  "    ""discovered_from"": ""https://example.edu/course/page"",",
  "    ""retrieved_at_utc"": ""2026-02-23T18:02:00Z""",
  "  }",
  "}"
)

Write-Lines (Join-Path $TVMin "evidence_bundle_manifest.json") @(
  "{",
  "  ""schema"": ""rie.evidence_bundle_manifest.v1"",",
  "  ""bundle_id"": ""b_001"",",
  "  ""created_at_utc"": ""2026-02-23T18:05:00Z"",",
  "  ""query_id"": ""q_001"",",
  "  ""items"": [ { ""source_id"": ""s_vid_001"" } ],",
  "  ""provenance"": {",
  "    ""generated_by"": ""rie-cli/0.1.0"",",
  "    ""retrieved_at_utc"": ""2026-02-23T18:05:10Z""",
  "  }",
  "}"
)

Write-Lines (Join-Path $TVMin "result_set.json") @(
  "{",
  "  ""schema"": ""rie.result_set.v1"",",
  "  ""query_id"": ""q_001"",",
  "  ""created_at_utc"": ""2026-02-23T18:06:00Z"",",
  "  ""results"": [",
  "    {",
  "      ""rank"": 1,",
  "      ""source"": {",
  "        ""schema"": ""rie.source_record.v1"",",
  "        ""source_id"": ""s_vid_001"",",
  "        ""content_kind"": ""video"",",
  "        ""title"": ""Convolution and Fourier Transform (Lecture)"",",
  "        ""provenance"": {",
  "          ""discovered_from"": ""https://example.edu/x"",",
  "          ""retrieved_at_utc"": ""2026-02-23T18:02:00Z""",
  "        }",
  "      },",
  "      ""segments"": []",
  "    }",
  "  ]",
  "}"
)

Write-Lines (Join-Path $TVNeg "source_record_has_answer.json") @(
  "{",
  "  ""schema"": ""rie.source_record.v1"",",
  "  ""source_id"": ""s_bad_001"",",
  "  ""content_kind"": ""notes"",",
  "  ""title"": ""Bad Record"",",
  "  ""answer"": ""nope"",",
  "  ""provenance"": {",
  "    ""discovered_from"": ""https://example.com"",",
  "    ""retrieved_at_utc"": ""2026-02-23T18:00:00Z""",
  "  }",
  "}"
)

Write-Lines (Join-Path $TVNeg "bundle_missing_provenance.json") @(
  "{",
  "  ""schema"": ""rie.evidence_bundle_manifest.v1"",",
  "  ""bundle_id"": ""b_bad_001"",",
  "  ""created_at_utc"": ""2026-02-23T18:05:00Z"",",
  "  ""query_id"": ""q_001"",",
  "  ""items"": [ { ""source_id"": ""s_vid_001"" } ]",
  "}"
)

Write-Lines (Join-Path $TVNeg "result_set_source_missing_provenance.json") @(
  "{",
  "  ""schema"": ""rie.result_set.v1"",",
  "  ""query_id"": ""q_001"",",
  "  ""created_at_utc"": ""2026-02-23T18:06:00Z"",",
  "  ""results"": [",
  "    {",
  "      ""rank"": 1,",
  "      ""source"": {",
  "        ""schema"": ""rie.source_record.v1"",",
  "        ""source_id"": ""s_vid_001"",",
  "        ""content_kind"": ""video"",",
  "        ""title"": ""NoProv""",
  "      },",
  "      ""segments"": []",
  "    }",
  "  ]",
  "}"
)

$Self = Join-Path $Scripts "_selftest_rie_schemas_v1.ps1"
Write-Lines $Self @(
  "param([Parameter(Mandatory=$false)][string]$RepoRoot="""")",
  "Set-StrictMode -Version Latest",
  "$ErrorActionPreference=""Stop""",
  "",
  "function Die([string]$m){ throw $m }",
  "function Ensure-RepoRoot([string]$p){",
  "  if([string]::IsNullOrWhiteSpace($p)){ $p=(Get-Location).Path }",
  "  if(-not (Test-Path -LiteralPath $p -PathType Container)){ Die (""REPOROOT_MISSING: "" + $p) }",
  "  (Resolve-Path -LiteralPath $p).Path",
  "}",
  "function Read-Utf8NoBom([string]$Path){",
  "  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die (""FILE_MISSING: "" + $Path) }",
  "  $b=[System.IO.File]::ReadAllBytes($Path)",
  "  $enc=New-Object System.Text.UTF8Encoding($false,$true)",
  "  $enc.GetString($b)",
  "}",
  "function Read-Json([string]$Path){",
  "  $raw=Read-Utf8NoBom $Path",
  "  try { $raw | ConvertFrom-Json -Depth 100 } catch { Die (""JSON_PARSE_FAIL: "" + $Path) }",
  "}",
  "function PropNames($o){ if($null -eq $o){ return @() } @(@($o.PSObject.Properties | ForEach-Object { $_.Name })) }",
  "function HasProp($o,[string]$name){ if($null -eq $o){ return $false } (@(PropNames $o) -contains $name) }",
  "function GetProp($o,[string]$name){ if(-not (HasProp $o $name)){ Die (""MISSING_PROP: "" + $name) } $o.$name }",
  "function Assert-HasProps($o,[string[]]$names,[string]$ctx){ foreach($n in @(@($names))){ if(-not (HasProp $o $n)){ Die (""MISSING_PROP: "" + $ctx + "" :: "" + $n) } } }",
  "function Assert-NoProps($o,[string[]]$names,[string]$ctx){ foreach($n in @(@($names))){ if(HasProp $o $n){ Die (""FORBIDDEN_PROP: "" + $ctx + "" :: "" + $n) } } }",
  "",
  "function Validate-SourceRecordV1($o,[string]$ctx){",
  "  Assert-NoProps $o @(""answer"",""solution"",""steps"",""explanation"") $ctx",
  "  Assert-HasProps $o @(""schema"",""source_id"",""content_kind"",""title"",""provenance"") $ctx",
  "  $prov = GetProp $o ""provenance""",
  "  Assert-HasProps $prov @(""discovered_from"",""retrieved_at_utc"") ($ctx + "".provenance"")",
  "}",
  "function Validate-BundleV1($o,[string]$ctx){ Assert-HasProps $o @(""schema"",""bundle_id"",""created_at_utc"",""query_id"",""items"",""provenance"") $ctx }",
  "function Validate-ResultSetV1($o,[string]$ctx){",
  "  Assert-HasProps $o @(""schema"",""query_id"",""created_at_utc"",""results"") $ctx",
  "  foreach($r in @(@($o.results))){",
  "    Assert-HasProps $r @(""rank"",""source"",""segments"") ($ctx + "".results[]"")",
  "    Validate-SourceRecordV1 $r.source ($ctx + "".results[].source"")",
  "  }",
  "}",
  "function Expect-Fail([scriptblock]$fn,[string]$token){",
  "  try { & $fn; Die (""NEG_EXPECTED_FAIL_BUT_PASSED: "" + $token) } catch {",
  "    Write-Host (""NEG_EXPECTED_FAIL_OK: "" + $token + "" :: "" + $_.Exception.Message) -ForegroundColor Green",
  "  }",
  "}",
  "",
  "$RepoRoot = Ensure-RepoRoot $RepoRoot",
  "$TVMin = Join-Path $RepoRoot ""test_vectors\minimal""",
  "$TVNeg = Join-Path $RepoRoot ""test_vectors\negative""",
  "",
  "Write-Host ""SELFTEST_RIE_SCHEMAS_V1_START"" -ForegroundColor Cyan",
  "Validate-SourceRecordV1 (Read-Json (Join-Path $TVMin ""source_record_video.json"")) ""minimal/source_record_video""",
  "Validate-BundleV1 (Read-Json (Join-Path $TVMin ""evidence_bundle_manifest.json"")) ""minimal/bundle""",
  "Validate-ResultSetV1 (Read-Json (Join-Path $TVMin ""result_set.json"")) ""minimal/result_set""",
  "Write-Host ""POS_VECTORS_OK"" -ForegroundColor Green",
  "",
  "Expect-Fail { Validate-SourceRecordV1 (Read-Json (Join-Path $TVNeg ""source_record_has_answer.json"")) ""neg/source_has_answer"" } ""NEG_SOURCE_HAS_ANSWER""",
  "Expect-Fail { Validate-BundleV1 (Read-Json (Join-Path $TVNeg ""bundle_missing_provenance.json"")) ""neg/bundle_missing_prov"" } ""NEG_BUNDLE_MISSING_PROVENANCE""",
  "Expect-Fail { Validate-ResultSetV1 (Read-Json (Join-Path $TVNeg ""result_set_source_missing_provenance.json"")) ""neg/result_source_missing_prov"" } ""NEG_RESULT_SOURCE_MISSING_PROVENANCE""",
  "Write-Host ""NEG_VECTORS_OK"" -ForegroundColor Green",
  "",
  "Write-Host ""SELFTEST_RIE_SCHEMAS_V1_OK"" -ForegroundColor Green"
)
Parse-GateFile $Self
Write-Host ("SELFTEST_PARSE_OK: " + $Self) -ForegroundColor Green

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$outLog = Join-Path $Logs ("selftest_stdout_" + $ts + ".log")
$errLog = Join-Path $Logs ("selftest_stderr_" + $ts + ".log")
Run-Child $Self @{ RepoRoot = $RepoRoot } $outLog $errLog
if(-not (Test-Path -LiteralPath $outLog -PathType Leaf)){ Die ("MISSING_OUTLOG: " + $outLog) }
if(-not (Test-Path -LiteralPath $errLog -PathType Leaf)){ Die ("MISSING_ERRLOG: " + $errLog) }
Write-Host ("SELFTEST_CHILD_OK: " + $outLog) -ForegroundColor Green
Write-Host "RIE_OVERWRITE_V3_OK" -ForegroundColor Green
