param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_AUDIENCE_POLICY_MATRIX_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot "scripts\rie_source_governance_v1.ps1")

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$enc = New-Object System.Text.UTF8Encoding($false)
$tvDir = Join-Path $RepoRoot "test_vectors\audience_policy_matrix_v1"
Ensure-Dir $tvDir

$DomainProfilesPath = Join-Path $tvDir "domain_profiles.v1.json"
$DomainProfilesText = @(
  '{',
  '  "profiles": [',
  '    { "schema": "rie.domain_profile.v1", "domain": "youtube.com", "observed_at_utc": "2026-03-08T00:00:00Z", "classification": "community_educator", "status": "caution", "policy_tags": ["community_source","requires_warning"] }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($DomainProfilesPath, ($DomainProfilesText + "`n"), $enc)

$SourcePath = Join-Path $tvDir "source_record.community_video.json"
$SourceText = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_matrix_community_001",',
  '  "content_kind": "video",',
  '  "title": "Community Astronomy Lesson",',
  '  "provenance": { "discovered_from": "https://youtube.com/watch?v=matrix1", "retrieved_at_utc": "2026-03-08T00:00:00Z", "canonical_url": "https://youtube.com/watch?v=matrix1" },',
  '  "trust_signals": [',
  '    { "schema": "rie.trust_signal.v1", "signal_id": "sig_matrix_001", "tier": "C", "kind": "lab_page_linked", "evidence": { "note": "Community educator with external linkage", "domain": "youtube.com" }, "observed_at_utc": "2026-03-08T00:00:00Z" }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($SourcePath, ($SourceText + "`n"), $enc)

$Policies = @(
  [pscustomobject]@{
    AudienceBand = "child_7_10"
    AudiencePath = (Join-Path $tvDir "aud.child_7_10.json")
    SourcePath   = (Join-Path $tvDir "src.child_7_10.json")
    AudienceJson = @(
      '{',
      '  "schema": "rie.audience_policy.v1",',
      '  "policy_id": "aud.child_7_10.matrix.v1",',
      '  "audience_band": "child_7_10",',
      '  "require_provenance": true,',
      '  "require_institutional_or_publisher_anchor": false,',
      '  "allow_community_sources": false,',
      '  "allow_video_platforms": true,',
      '  "allow_warning_labeled_results": false,',
      '  "allow_quarantined_results": false,',
      '  "deny_for_answer_like_patterns": true,',
      '  "max_results_per_domain": 3,',
      '  "min_trust_signal_count": 1',
      '}'
    ) -join "`n"
    SourceJson = @(
      '{',
      '  "schema": "rie.source_policy.v1",',
      '  "policy_id": "src.child_7_10.matrix.v1",',
      '  "version": "v1",',
      '  "created_at_utc": "2026-03-08T00:00:00Z",',
      '  "label": "Matrix child 7-10",',
      '  "default_action": "DENY",',
      '  "audience_policy_id": "aud.child_7_10.matrix.v1",',
      '  "domain_lists": { "allowlist": [], "denylist": [], "cautionlist": ["youtube.com"], "watchlist": [] }',
      '}'
    ) -join "`n"
    ExpectedAction = "QUARANTINE_REVIEW_ONLY"
  },
  [pscustomobject]@{
    AudienceBand = "child_11_13"
    AudiencePath = (Join-Path $tvDir "aud.child_11_13.json")
    SourcePath   = (Join-Path $tvDir "src.child_11_13.json")
    AudienceJson = @(
      '{',
      '  "schema": "rie.audience_policy.v1",',
      '  "policy_id": "aud.child_11_13.matrix.v1",',
      '  "audience_band": "child_11_13",',
      '  "require_provenance": true,',
      '  "require_institutional_or_publisher_anchor": false,',
      '  "allow_community_sources": true,',
      '  "allow_video_platforms": true,',
      '  "allow_warning_labeled_results": true,',
      '  "allow_quarantined_results": false,',
      '  "deny_for_answer_like_patterns": true,',
      '  "max_results_per_domain": 4,',
      '  "min_trust_signal_count": 1',
      '}'
    ) -join "`n"
    SourceJson = @(
      '{',
      '  "schema": "rie.source_policy.v1",',
      '  "policy_id": "src.child_11_13.matrix.v1",',
      '  "version": "v1",',
      '  "created_at_utc": "2026-03-08T00:00:00Z",',
      '  "label": "Matrix child 11-13",',
      '  "default_action": "DENY",',
      '  "audience_policy_id": "aud.child_11_13.matrix.v1",',
      '  "domain_lists": { "allowlist": [], "denylist": [], "cautionlist": ["youtube.com"], "watchlist": [] }',
      '}'
    ) -join "`n"
    ExpectedAction = "ALLOW_WITH_EDUCATOR_WARNING"
  },
  [pscustomobject]@{
    AudienceBand = "teen"
    AudiencePath = (Join-Path $tvDir "aud.teen.json")
    SourcePath   = (Join-Path $tvDir "src.teen.json")
    AudienceJson = @(
      '{',
      '  "schema": "rie.audience_policy.v1",',
      '  "policy_id": "aud.teen.matrix.v1",',
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
    SourceJson = @(
      '{',
      '  "schema": "rie.source_policy.v1",',
      '  "policy_id": "src.teen.matrix.v1",',
      '  "version": "v1",',
      '  "created_at_utc": "2026-03-08T00:00:00Z",',
      '  "label": "Matrix teen",',
      '  "default_action": "DENY",',
      '  "audience_policy_id": "aud.teen.matrix.v1",',
      '  "domain_lists": { "allowlist": [], "denylist": [], "cautionlist": ["youtube.com"], "watchlist": [] }',
      '}'
    ) -join "`n"
    ExpectedAction = "ALLOW_WITH_EDUCATOR_WARNING"
  },
  [pscustomobject]@{
    AudienceBand = "adult"
    AudiencePath = (Join-Path $tvDir "aud.adult.json")
    SourcePath   = (Join-Path $tvDir "src.adult.json")
    AudienceJson = @(
      '{',
      '  "schema": "rie.audience_policy.v1",',
      '  "policy_id": "aud.adult.matrix.v1",',
      '  "audience_band": "adult",',
      '  "require_provenance": true,',
      '  "require_institutional_or_publisher_anchor": false,',
      '  "allow_community_sources": true,',
      '  "allow_video_platforms": true,',
      '  "allow_warning_labeled_results": true,',
      '  "allow_quarantined_results": true,',
      '  "deny_for_answer_like_patterns": true,',
      '  "max_results_per_domain": 8,',
      '  "min_trust_signal_count": 0',
      '}'
    ) -join "`n"
    SourceJson = @(
      '{',
      '  "schema": "rie.source_policy.v1",',
      '  "policy_id": "src.adult.matrix.v1",',
      '  "version": "v1",',
      '  "created_at_utc": "2026-03-08T00:00:00Z",',
      '  "label": "Matrix adult",',
      '  "default_action": "DENY",',
      '  "audience_policy_id": "aud.adult.matrix.v1",',
      '  "domain_lists": { "allowlist": [], "denylist": [], "cautionlist": ["youtube.com"], "watchlist": [] }',
      '}'
    ) -join "`n"
    ExpectedAction = "ALLOW_WITH_EDUCATOR_WARNING"
  }
)

$OutDir = Join-Path $RepoRoot "proofs\audience_matrix"
Ensure-Dir $OutDir

foreach($p in @($Policies)){
  [System.IO.File]::WriteAllText($p.AudiencePath, ($p.AudienceJson + "`n"), $enc)
  [System.IO.File]::WriteAllText($p.SourcePath, ($p.SourceJson + "`n"), $enc)

  $r = RIE-RunSourceGovernanceV1 -RepoRoot $RepoRoot -SourcePath $SourcePath -AudiencePolicyPath $p.AudiencePath -SourcePolicyPath $p.SourcePath -DomainProfilesPath $DomainProfilesPath -OutDir $OutDir
  if([string]$r.action -ne [string]$p.ExpectedAction){
    throw ("AUDIENCE_MATRIX_ACTION_MISMATCH:" + $p.AudienceBand + ": expected=" + $p.ExpectedAction + " got=" + [string]$r.action)
  }
  Write-Host ("MATRIX_OK: " + $p.AudienceBand + " :: " + $r.action) -ForegroundColor Green
}

Write-Host "RIE_AUDIENCE_POLICY_MATRIX_SELFTEST_V1_OK" -ForegroundColor Green
