param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_GOVERNANCE_STRESS_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot "scripts\rie_source_governance_v1.ps1")

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$enc = New-Object System.Text.UTF8Encoding($false)
$tvDir = Join-Path $RepoRoot "test_vectors\governance_stress_v1"
Ensure-Dir $tvDir

$DomainProfilesPath = Join-Path $tvDir "domain_profiles.v1.json"
$DomainProfilesText = @(
  '{',
  '  "profiles": [',
  '    { "schema": "rie.domain_profile.v1", "domain": "nasa.gov", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "government", "status": "allow", "policy_tags": ["child_safe_preferred"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "ted.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "educational_video_platform", "status": "allow", "policy_tags": ["child_safe_preferred","video_platform"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "youtube.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "community_educator", "status": "caution", "policy_tags": ["community_source","requires_warning"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "wikipedia.org", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "reference_tertiary", "status": "watch", "policy_tags": ["watchlist"] },',
  '    { "schema": "rie.domain_profile.v1", "domain": "coursehero.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "blocked", "status": "deny", "policy_tags": ["denylisted"] }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($DomainProfilesPath, ($DomainProfilesText + "`n"), $enc)

$AudPath = Join-Path $tvDir "audience_policy.child_7_10.json"
$AudText = @(
  '{',
  '  "schema": "rie.audience_policy.v1",',
  '  "policy_id": "aud.child_7_10.stress.v1",',
  '  "audience_band": "child_7_10",',
  '  "label": "Child Safe Stress Policy",',
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
[System.IO.File]::WriteAllText($AudPath, ($AudText + "`n"), $enc)

$SrcPolPath = Join-Path $tvDir "source_policy.child_7_10.stress.v1.json"
$SrcPolText = @(
  '{',
  '  "schema": "rie.source_policy.v1",',
  '  "policy_id": "src.child_7_10.stress.v1",',
  '  "version": "v1",',
  '  "created_at_utc": "2026-03-08T00:00:00Z",',
  '  "label": "Child Safe Stress Source Policy",',
  '  "default_action": "DENY",',
  '  "audience_policy_id": "aud.child_7_10.stress.v1",',
  '  "domain_lists": {',
  '    "allowlist": ["nasa.gov","ted.com"],',
  '    "denylist": ["coursehero.com"],',
  '    "cautionlist": ["youtube.com"],',
  '    "watchlist": ["wikipedia.org"]',
  '  }',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($SrcPolPath, ($SrcPolText + "`n"), $enc)

$Cases = @()

$Cases += [pscustomobject]@{
  Name = "nasa_allow"
  Path = (Join-Path $tvDir "source_record.nasa_allow.json")
  Json = @(
    '{',
    '  "schema": "rie.source_record.v1",',
    '  "source_id": "s_gov_allow_001",',
    '  "content_kind": "course_page",',
    '  "title": "NASA Kids Climate",',
    '  "publisher": "NASA",',
    '  "provenance": { "discovered_from": "https://www.nasa.gov", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://www.nasa.gov/" },',
    '  "trust_signals": [',
    '    { "schema": "rie.trust_signal.v1", "signal_id": "sig_a1", "tier": "A", "kind": "government_science_source", "evidence": { "note": "NASA official domain", "domain": "nasa.gov" }, "observed_at_utc": "2026-03-08T00:00:00Z" }',
    '  ]',
    '}'
  ) -join "`n"
  ExpectedAction = "ALLOW_CHILD_SAFE"
  ExpectedReason = "ALLOW_CHILD_SAFE_GOV_SCIENCE"
}

$Cases += [pscustomobject]@{
  Name = "deny_answer"
  Path = (Join-Path $tvDir "source_record.deny_answer.json")
  Json = @(
    '{',
    '  "schema": "rie.source_record.v1",',
    '  "source_id": "s_deny_answer_001",',
    '  "content_kind": "notes",',
    '  "title": "Answer Site",',
    '  "provenance": { "discovered_from": "https://coursehero.com/abc", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://coursehero.com/abc" },',
    '  "answer": "forbidden"',
    '}'
  ) -join "`n"
  ExpectedAction = "DENY"
  ExpectedReason = "DENY_FORBIDDEN_ANSWER_CONTENT"
}

$Cases += [pscustomobject]@{
  Name = "deny_low_trust"
  Path = (Join-Path $tvDir "source_record.low_trust.json")
  Json = @(
    '{',
    '  "schema": "rie.source_record.v1",',
    '  "source_id": "s_low_trust_001",',
    '  "content_kind": "paper",',
    '  "title": "Low Trust Independent Blog",',
    '  "provenance": { "discovered_from": "https://unknown-example.org/post", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://unknown-example.org/post" }',
    '}'
  ) -join "`n"
  ExpectedAction = "DENY"
  ExpectedReason = "DENY_MISSING_INSTITUTIONAL_OR_PUBLISHER_ANCHOR"
}

$Cases += [pscustomobject]@{
  Name = "quarantine_community"
  Path = (Join-Path $tvDir "source_record.quarantine_community.json")
  Json = @(
    '{',
    '  "schema": "rie.source_record.v1",',
    '  "source_id": "s_quarantine_community_001",',
    '  "content_kind": "video",',
    '  "title": "Community Science Lecture",',
    '  "provenance": { "discovered_from": "https://youtube.com/watch?v=xyz", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://youtube.com/watch?v=xyz" },',
    '  "trust_signals": [',
    '    { "schema": "rie.trust_signal.v1", "signal_id": "sig_c1", "tier": "C", "kind": "lab_page_linked", "evidence": { "note": "Community educator", "domain": "youtube.com" }, "observed_at_utc": "2026-03-08T00:00:00Z" }',
    '  ]',
    '}'
  ) -join "`n"
  ExpectedAction = "QUARANTINE_REVIEW_ONLY"
  ExpectedReason = "QUARANTINE_REQUIRES_REVIEW"
}

$Cases += [pscustomobject]@{
  Name = "downrank_watchlist"
  Path = (Join-Path $tvDir "source_record.watchlist_reference.json")
  Json = @(
    '{',
    '  "schema": "rie.source_record.v1",',
    '  "source_id": "s_watchlist_001",',
    '  "content_kind": "notes",',
    '  "title": "Reference Encyclopedia Entry",',
    '  "provenance": { "discovered_from": "https://wikipedia.org/wiki/Climate", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://wikipedia.org/wiki/Climate" },',
    '  "trust_signals": [',
    '    { "schema": "rie.trust_signal.v1", "signal_id": "sig_w1", "tier": "B", "kind": "publisher_verified", "evidence": { "note": "Reference source", "domain": "wikipedia.org" }, "observed_at_utc": "2026-03-08T00:00:00Z" }',
    '  ]',
    '}'
  ) -join "`n"
  ExpectedAction = "ALLOW"
  ExpectedReason = "ALLOW_TRUSTED_SOURCE"
}

foreach($case in @($Cases)){
  [System.IO.File]::WriteAllText($case.Path, ($case.Json + "`n"), $enc)
}

$OutDir = Join-Path $RepoRoot "proofs\governance_stress"
Ensure-Dir $OutDir

foreach($case in @($Cases)){
  $r = RIE-RunSourceGovernanceV1 -RepoRoot $RepoRoot -SourcePath $case.Path -AudiencePolicyPath $AudPath -SourcePolicyPath $SrcPolPath -DomainProfilesPath $DomainProfilesPath -OutDir $OutDir
  if([string]$r.action -ne [string]$case.ExpectedAction){
    throw ("CASE_ACTION_MISMATCH:" + $case.Name + ": expected=" + $case.ExpectedAction + " got=" + [string]$r.action)
  }
  if([string]$r.reason_code -ne [string]$case.ExpectedReason){
    throw ("CASE_REASON_MISMATCH:" + $case.Name + ": expected=" + $case.ExpectedReason + " got=" + [string]$r.reason_code)
  }
  Write-Host ("CASE_OK: " + $case.Name + " :: " + $r.action + " :: " + $r.reason_code) -ForegroundColor Green
}

Write-Host "RIE_GOVERNANCE_STRESS_SELFTEST_V1_OK" -ForegroundColor Green
