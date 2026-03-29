param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_QUERY_STRESS_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot "scripts\rie_source_governance_v1.ps1")

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$enc = New-Object System.Text.UTF8Encoding($false)
$tvDir = Join-Path $RepoRoot "test_vectors\query_stress_v1"
Ensure-Dir $tvDir

$DomainProfilesPath = Join-Path $tvDir "domain_profiles.v1.json"
$DomainProfilesText = @(
  '{',
  '  "profiles": [',
  '    { "schema": "rie.domain_profile.v1", "domain": "nasa.gov", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "government", "status": "allow", "policy_tags": ["child_safe_preferred"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "ted.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "educational_video_platform", "status": "allow", "policy_tags": ["child_safe_preferred"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "youtube.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "community_educator", "status": "caution", "policy_tags": ["community_source"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "coursehero.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "blocked", "status": "deny", "policy_tags": ["denylisted"] }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($DomainProfilesPath, ($DomainProfilesText + "`n"), $enc)

$SrcA = Join-Path $tvDir "source_record.nasa.json"
$SrcAText = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_qs_nasa_001",',
  '  "content_kind": "course_page",',
  '  "title": "NASA Lecture Demo",',
  '  "publisher": "NASA",',
  '  "provenance": { "discovered_from": "https://www.nasa.gov", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://www.nasa.gov/" },',
  '  "trust_signals": [',
  '    { "schema": "rie.trust_signal.v1", "signal_id": "sig_qs_a", "tier": "A", "kind": "government_science_source", "evidence": { "note": "NASA official domain", "domain": "nasa.gov" }, "observed_at_utc": "2026-03-08T00:00:00Z" }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($SrcA, ($SrcAText + "`n"), $enc)

$SrcB = Join-Path $tvDir "source_record.community.json"
$SrcBText = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_qs_comm_001",',
  '  "content_kind": "video",',
  '  "title": "Community Demo Lecture",',
  '  "provenance": { "discovered_from": "https://youtube.com/watch?v=stress1", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://youtube.com/watch?v=stress1" },',
  '  "trust_signals": [',
  '    { "schema": "rie.trust_signal.v1", "signal_id": "sig_qs_b", "tier": "C", "kind": "lab_page_linked", "evidence": { "note": "Community educator", "domain": "youtube.com" }, "observed_at_utc": "2026-03-08T00:00:00Z" }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($SrcB, ($SrcBText + "`n"), $enc)

$SrcC = Join-Path $tvDir "source_record.blocked.json"
$SrcCText = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_qs_block_001",',
  '  "content_kind": "notes",',
  '  "title": "Blocked Solver",',
  '  "provenance": { "discovered_from": "https://coursehero.com/x", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://coursehero.com/x" },',
  '  "answer": "forbidden"',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($SrcC, ($SrcCText + "`n"), $enc)

$IndexPath = Join-Path $tvDir "rie.keyword_index.v1.query_stress.json"
$IndexText = @(
  '{',
  '  "schema": "rie.keyword_index.v1",',
  '  "generated_at_utc": "2026-03-08T00:00:00Z",',
  '  "source_count": 3,',
  '  "keyword_count": 7,',
  '  "sources": [',
  '    { "source_id": "s_qs_nasa_001", "path": "test_vectors\\query_stress_v1\\source_record.nasa.json", "hash": "sha256:dummy_a" },',
  '    { "source_id": "s_qs_comm_001", "path": "test_vectors\\query_stress_v1\\source_record.community.json", "hash": "sha256:dummy_b" },',
  '    { "source_id": "s_qs_block_001", "path": "test_vectors\\query_stress_v1\\source_record.blocked.json", "hash": "sha256:dummy_c" }',
  '  ],',
  '  "keywords": {',
  '    "nasa": ["s_qs_nasa_001"],',
  '    "lecture": ["s_qs_nasa_001","s_qs_comm_001"],',
  '    "demo": ["s_qs_nasa_001","s_qs_comm_001"],',
  '    "community": ["s_qs_comm_001"],',
  '    "solver": ["s_qs_block_001"],',
  '    "blocked": ["s_qs_block_001"],',
  '    "science": ["s_qs_nasa_001","s_qs_comm_001"]',
  '  }',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($IndexPath, ($IndexText + "`n"), $enc)

$ChildAudPath = Join-Path $tvDir "aud.child_7_10.json"
$ChildSrcPath = Join-Path $tvDir "src.child_7_10.json"
$TeenAudPath  = Join-Path $tvDir "aud.teen.json"
$TeenSrcPath  = Join-Path $tvDir "src.teen.json"

$ChildAudText = @(
  '{',
  '  "schema": "rie.audience_policy.v1",',
  '  "policy_id": "aud.child_7_10.query_stress.v1",',
  '  "audience_band": "child_7_10",',
  '  "require_provenance": true,',
  '  "require_institutional_or_publisher_anchor": true,',
  '  "allow_community_sources": false,',
  '  "allow_video_platforms": true,',
  '  "allow_warning_labeled_results": false,',
  '  "allow_quarantined_results": false,',
  '  "deny_for_answer_like_patterns": true,',
  '  "max_results_per_domain": 3,',
  '  "min_trust_signal_count": 1',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($ChildAudPath, ($ChildAudText + "`n"), $enc)

$ChildSrcText = @(
  '{',
  '  "schema": "rie.source_policy.v1",',
  '  "policy_id": "src.child_7_10.query_stress.v1",',
  '  "version": "v1",',
  '  "created_at_utc": "2026-03-08T00:00:00Z",',
  '  "label": "Child query stress",',
  '  "default_action": "DENY",',
  '  "audience_policy_id": "aud.child_7_10.query_stress.v1",',
  '  "domain_lists": { "allowlist": ["nasa.gov","ted.com"], "denylist": ["coursehero.com"], "cautionlist": ["youtube.com"], "watchlist": [] }',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($ChildSrcPath, ($ChildSrcText + "`n"), $enc)

$TeenAudText = @(
  '{',
  '  "schema": "rie.audience_policy.v1",',
  '  "policy_id": "aud.teen.query_stress.v1",',
  '  "audience_band": "teen",',
  '  "require_provenance": true,',
  '  "require_institutional_or_publisher_anchor": false,',
  '  "allow_community_sources": true,',
  '  "allow_video_platforms": true,',
  '  "allow_warning_labeled_results": true,',
  '  "allow_quarantined_results": true,',
  '  "deny_for_answer_like_patterns": true,',
  '  "max_results_per_domain": 6,',
  '  "min_trust_signal_count": 1',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($TeenAudPath, ($TeenAudText + "`n"), $enc)

$TeenSrcText = @(
  '{',
  '  "schema": "rie.source_policy.v1",',
  '  "policy_id": "src.teen.query_stress.v1",',
  '  "version": "v1",',
  '  "created_at_utc": "2026-03-08T00:00:00Z",',
  '  "label": "Teen query stress",',
  '  "default_action": "DENY",',
  '  "audience_policy_id": "aud.teen.query_stress.v1",',
  '  "domain_lists": { "allowlist": ["nasa.gov","ted.com"], "denylist": ["coursehero.com"], "cautionlist": ["youtube.com"], "watchlist": [] }',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($TeenSrcPath, ($TeenSrcText + "`n"), $enc)

$QueryScript = Join-Path $RepoRoot "scripts\rie_query_v1.ps1"
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$QueryChild = Join-Path $tvDir "query.child.json"
$QueryChildText = @(
  '{',
  '  "schema": "rie.query_record.v1",',
  '  "query_id": "q_query_stress_child_001",',
  '  "created_at_utc": "2026-03-08T00:00:00Z",',
  '  "intent": "find_sources",',
  '  "inputs": [ { "kind": "keywords", "text": "nasa lecture demo community solver science" } ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($QueryChild, ($QueryChildText + "`n"), $enc)

$ChildOut = Join-Path $RepoRoot "proofs\queries\rie_query_stress_child_safe.json"
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $QueryScript `
  -RepoRoot $RepoRoot `
  -QueryPath $QueryChild `
  -IndexPath $IndexPath `
  -AudiencePolicyPath $ChildAudPath `
  -SourcePolicyPath $ChildSrcPath `
  -DomainProfilesPath $DomainProfilesPath `
  -OutPath $ChildOut | Out-Host

$childRs = RIE-GovLoadJson $ChildOut
$childResults = @(@($childRs["results"]))
if($childResults.Count -ne 1){ throw ("CHILD_EXPECTED_ONE_RESULT_GOT:" + $childResults.Count) }
if([string]$childResults[0]["source"]["source_id"] -ne "s_qs_nasa_001"){ throw "CHILD_WRONG_SOURCE" }
if([string]$childResults[0]["admission_decision"]["action"] -ne "ALLOW_CHILD_SAFE"){ throw "CHILD_WRONG_ACTION" }
Write-Host ("CHILD_QUERY_OK: " + $ChildOut) -ForegroundColor Green

$QueryTeen = Join-Path $tvDir "query.teen.json"
$QueryTeenText = @(
  '{',
  '  "schema": "rie.query_record.v1",',
  '  "query_id": "q_query_stress_teen_001",',
  '  "created_at_utc": "2026-03-08T00:00:00Z",',
  '  "intent": "find_sources",',
  '  "inputs": [ { "kind": "keywords", "text": "lecture demo community science solver" } ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($QueryTeen, ($QueryTeenText + "`n"), $enc)

$TeenOut = Join-Path $RepoRoot "proofs\queries\rie_query_stress_teen.json"
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $QueryScript `
  -RepoRoot $RepoRoot `
  -QueryPath $QueryTeen `
  -IndexPath $IndexPath `
  -AudiencePolicyPath $TeenAudPath `
  -SourcePolicyPath $TeenSrcPath `
  -DomainProfilesPath $DomainProfilesPath `
  -OutPath $TeenOut | Out-Host

$teenRs = RIE-GovLoadJson $TeenOut
$teenResults = @(@($teenRs["results"]))
if($teenResults.Count -lt 1){ throw ("TEEN_EXPECTED_AT_LEAST_ONE_RESULT_GOT:" + $teenResults.Count) }

$ids = New-Object System.Collections.Generic.List[string]
foreach($r in @($teenResults)){ [void]$ids.Add([string]$r["source"]["source_id"]) }
$joined = (@($ids.ToArray()) -join ",")

if([string]::IsNullOrWhiteSpace($joined)){ throw "TEEN_NO_ALLOWED_RESULTS" }
if($joined.IndexOf("s_qs_block_001",[System.StringComparison]::Ordinal) -ge 0){ throw "TEEN_BLOCKED_SOURCE_LEAKED" }

Write-Host ("TEEN_QUERY_OK: " + $TeenOut) -ForegroundColor Green

$NoMatchQuery = Join-Path $tvDir "query.nomatch.json"
$NoMatchText = @(
  '{',
  '  "schema": "rie.query_record.v1",',
  '  "query_id": "q_query_stress_nomatch_001",',
  '  "created_at_utc": "2026-03-08T00:00:00Z",',
  '  "intent": "find_sources",',
  '  "inputs": [ { "kind": "keywords", "text": "unobtainium xyz nohit" } ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($NoMatchQuery, ($NoMatchText + "`n"), $enc)

$NoMatchOut = Join-Path $RepoRoot "proofs\queries\rie_query_stress_nomatch.json"
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $QueryScript `
  -RepoRoot $RepoRoot `
  -QueryPath $NoMatchQuery `
  -IndexPath $IndexPath `
  -AudiencePolicyPath $ChildAudPath `
  -SourcePolicyPath $ChildSrcPath `
  -DomainProfilesPath $DomainProfilesPath `
  -OutPath $NoMatchOut | Out-Host

$noMatchRs = RIE-GovLoadJson $NoMatchOut
$noMatchResults = @(@($noMatchRs["results"]))
if($noMatchResults.Count -ne 0){ throw ("NOMATCH_EXPECTED_ZERO_GOT:" + $noMatchResults.Count) }
Write-Host ("NOMATCH_QUERY_OK: " + $NoMatchOut) -ForegroundColor Green

Write-Host "RIE_QUERY_STRESS_SELFTEST_V1_OK" -ForegroundColor Green
