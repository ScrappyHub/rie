param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_QUERY_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot "scripts\rie_source_governance_v1.ps1")

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$enc = New-Object System.Text.UTF8Encoding($false)
$tvDir = Join-Path $RepoRoot "test_vectors\query_governance_v1"
Ensure-Dir $tvDir

$sourceA = Join-Path $tvDir "source_record.nasa.query.json"
$sourceAText = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_nasa_q_001",',
  '  "content_kind": "course_page",',
  '  "title": "NASA Example Lecture Demo",',
  '  "publisher": "NASA",',
  '  "summary": "A safe educational source for climate and Earth science.",
  "audience": "child_safe",',
  '  "provenance": {',
  '    "discovered_from": "https://www.nasa.gov",',
  '    "retrieved_at_utc": "2026-03-07T00:00:00Z",',
  '    "canonical_url": "https://www.nasa.gov/"',
  '  },',
  '  "trust_signals": [',
  '    {',
  '      "schema": "rie.trust_signal.v1",',
  '      "signal_id": "sig_nasa_q_001",',
  '      "tier": "A",',
  '      "kind": "government_science_source",',
  '      "evidence": { "note": "NASA official domain", "domain": "nasa.gov" },',
  '      "observed_at_utc": "2026-03-07T00:00:00Z"',
  '    }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($sourceA, ($sourceAText + "`n"), $enc)

$sourceB = Join-Path $tvDir "source_record.blocked.query.json"
$sourceBText = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_block_q_001",',
  '  "content_kind": "notes",',
  '  "title": "Solver Notes",',
  '  "provenance": {',
  '    "discovered_from": "https://coursehero.com/x",',
  '    "retrieved_at_utc": "2026-03-07T00:00:00Z",',
  '    "canonical_url": "https://coursehero.com/x"',
  '  },',
  '  "answer": "not allowed"',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($sourceB, ($sourceBText + "`n"), $enc)

$indexPath = Join-Path $tvDir "rie.keyword_index.v1.query_selftest.json"
$indexText = @(
  '{',
  '  "schema": "rie.keyword_index.v1",',
  '  "generated_at_utc": "2026-03-07T00:00:00Z",',
  '  "source_count": 2,',
  '  "keyword_count": 5,',
  '  "sources": [',
  '    {',
  '      "source_id": "s_nasa_q_001",',
  '      "path": "test_vectors\\query_governance_v1\\source_record.nasa.query.json",',
  '      "hash": "sha256:dummy_nasa_q_001"',
  '    },',
  '    {',
  '      "source_id": "s_block_q_001",',
  '      "path": "test_vectors\\query_governance_v1\\source_record.blocked.query.json",',
  '      "hash": "sha256:dummy_block_q_001"',
  '    }',
  '  ],',
  '  "keywords": {',
  '    "nasa": ["s_nasa_q_001"],',
  '    "example": ["s_nasa_q_001"],',
  '    "lecture": ["s_nasa_q_001"],',
  '    "demo": ["s_nasa_q_001"],',
  '    "solver": ["s_block_q_001"]',
  '  }',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($indexPath, ($indexText + "`n"), $enc)

$queryPath = Join-Path $tvDir "rie.query_record.child_safe.json"
$queryText = @(
  '{',
  '  "schema": "rie.query_record.v1",',
  '  "query_id": "q_childsafe_001",',
  '  "created_at_utc": "2026-03-07T00:00:00Z",',
  '  "intent": "find_sources",',
  '  "inputs": [',
  '    {',
  '      "kind": "keywords",',
  '      "text": "nasa lecture demo solver"',
  '    }',
  '  ],',
  '  "constraints": {',
  '    "level": "hs",',
  '    "formats": ["video", "notes", "paper"],',
  '    "language": "en-US"',
  '  }',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($queryPath, ($queryText + "`n"), $enc)

$audPath = Join-Path $RepoRoot "test_vectors\source_governance_v1\audience_policy.child_7_10.json"
$srcPolicyPath = Join-Path $RepoRoot "test_vectors\source_governance_v1\source_policy.child_7_10.v1.json"
$domainProfilesPath = Join-Path $RepoRoot "test_vectors\source_governance_v1\domain_profiles.v1.json"
if(-not (Test-Path -LiteralPath $audPath -PathType Leaf)){ throw ("MISSING_AUDIENCE_POLICY: " + $audPath) }
if(-not (Test-Path -LiteralPath $srcPolicyPath -PathType Leaf)){ throw ("MISSING_SOURCE_POLICY: " + $srcPolicyPath) }
if(-not (Test-Path -LiteralPath $domainProfilesPath -PathType Leaf)){ throw ("MISSING_DOMAIN_PROFILES: " + $domainProfilesPath) }

$outPath = Join-Path $RepoRoot "proofs\queries\rie_result_set_query_governance_child_safe.json"
$QueryScript = Join-Path $RepoRoot "scripts\rie_query_v1.ps1"
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $QueryScript `
  -RepoRoot $RepoRoot `
  -QueryPath $queryPath `
  -IndexPath $indexPath `
  -AudiencePolicyPath $audPath `
  -SourcePolicyPath $srcPolicyPath `
  -DomainProfilesPath $domainProfilesPath `
  -OutPath $outPath | Out-Host

if(-not (Test-Path -LiteralPath $outPath -PathType Leaf)){ throw ("QUERY_RESULT_MISSING: " + $outPath) }

$resultSet = RIE-GovLoadJson $outPath
$results = @(@($resultSet["results"]))

if($results.Count -ne 1){ throw ("EXPECTED_ONE_RESULT_GOT: " + $results.Count) }

$r0 = $results[0]
$src = $r0["source"]
$adm = $r0["admission_decision"]

if([string]$src["source_id"] -ne "s_nasa_q_001"){ throw ("UNEXPECTED_SOURCE_ID: " + [string]$src["source_id"]) }
if([string]$adm["action"] -ne "ALLOW_CHILD_SAFE"){ throw ("UNEXPECTED_ACTION: " + [string]$adm["action"]) }
if(([string]$adm["reason_code"]).IndexOf("ALLOW_CHILD_SAFE",[System.StringComparison]::Ordinal) -lt 0){ throw ("UNEXPECTED_REASON_CODE: " + [string]$adm["reason_code"]) }

Write-Host ("QUERY_RESULT_OK: " + $outPath) -ForegroundColor Green
Write-Host "RIE_QUERY_SELFTEST_V1_OK" -ForegroundColor Green
