param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_SOURCE_GOVERNANCE_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot "scripts\rie_source_governance_v1.ps1")

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$tvDir = Join-Path $RepoRoot "test_vectors\source_governance_v1"
Ensure-Dir $tvDir

$enc = New-Object System.Text.UTF8Encoding($false)

$domainProfilesPath = Join-Path $tvDir "domain_profiles.v1.json"
$domainProfilesJson = @(
  '{',
  '  "profiles": [',
  '    {',
  '      "schema": "rie.domain_profile.v1",',
  '      "domain": "nasa.gov",',
  '      "observed_at_utc": "2026-03-07T00:00:00Z",',
  '      "classification": "government",',
  '      "status": "allow",',
  '      "policy_tags": ["child_safe_preferred"]',
  '    },',
  '    {',
  '      "schema": "rie.domain_profile.v1",',
  '      "domain": "ted.com",',
  '      "observed_at_utc": "2026-03-07T00:00:00Z",',
  '      "classification": "educational_video_platform",',
  '      "status": "allow",',
  '      "policy_tags": ["child_safe_preferred","video_platform"]',
  '    },',
  '    {',
  '      "schema": "rie.domain_profile.v1",',
  '      "domain": "youtube.com",',
  '      "observed_at_utc": "2026-03-07T00:00:00Z",',
  '      "classification": "community_educator",',
  '      "status": "caution",',
  '      "policy_tags": ["community_source","requires_warning"]',
  '    },',
  '    {',
  '      "schema": "rie.domain_profile.v1",',
  '      "domain": "coursehero.com",',
  '      "observed_at_utc": "2026-03-07T00:00:00Z",',
  '      "classification": "blocked",',
  '      "status": "deny",',
  '      "policy_tags": ["denylisted"]',
  '    }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($domainProfilesPath, ($domainProfilesJson + "`n"), $enc)

$audPath = Join-Path $tvDir "audience_policy.child_7_10.json"
$srcPolicyPath = Join-Path $tvDir "source_policy.child_7_10.v1.json"

if(-not (Test-Path -LiteralPath $audPath -PathType Leaf)){ throw ("MISSING_AUDIENCE_POLICY: " + $audPath) }
if(-not (Test-Path -LiteralPath $srcPolicyPath -PathType Leaf)){ throw ("MISSING_SOURCE_POLICY: " + $srcPolicyPath) }

$posGov = Join-Path $tvDir "source_record.nasa.child_safe.json"
$posGovJson = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_nasa_001",',
  '  "content_kind": "course_page",',
  '  "title": "NASA Climate for Kids",',
  '  "publisher": "NASA",',
  '  "summary": "Educational material for children about climate and Earth science.",',
  '  "provenance": {',
  '    "discovered_from": "https://www.nasa.gov",',
  '    "retrieved_at_utc": "2026-03-07T00:00:00Z",',
  '    "canonical_url": "https://www.nasa.gov/"',
  '  },',
  '  "trust_signals": [',
  '    {',
  '      "schema": "rie.trust_signal.v1",',
  '      "signal_id": "sig_nasa_001",',
  '      "tier": "A",',
  '      "kind": "government_science_source",',
  '      "evidence": { "note": "NASA official domain", "domain": "nasa.gov" },',
  '      "observed_at_utc": "2026-03-07T00:00:00Z"',
  '    }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($posGov, ($posGovJson + "`n"), $enc)

$negAnswer = Join-Path $tvDir "source_record.answer_site.json"
$negAnswerJson = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_bad_answer_001",',
  '  "content_kind": "notes",',
  '  "title": "Homework Solver",',
  '  "provenance": {',
  '    "discovered_from": "https://coursehero.com/x",',
  '    "retrieved_at_utc": "2026-03-07T00:00:00Z",',
  '    "canonical_url": "https://coursehero.com/x"',
  '  },',
  '  "tags": ["solver"],',
  '  "answer": "42"',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($negAnswer, ($negAnswerJson + "`n"), $enc)

$negMissingProv = Join-Path $tvDir "source_record.missing_provenance.json"
$negMissingProvJson = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_missing_prov_001",',
  '  "content_kind": "paper",',
  '  "title": "Unknown Paper"',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($negMissingProv, ($negMissingProvJson + "`n"), $enc)

$negCommunity = Join-Path $tvDir "source_record.community_video.json"
$negCommunityJson = @(
  '{',
  '  "schema": "rie.source_record.v1",',
  '  "source_id": "s_comm_001",',
  '  "content_kind": "video",',
  '  "title": "Community Science Video",',
  '  "provenance": {',
  '    "discovered_from": "https://youtube.com/watch?v=abc",',
  '    "retrieved_at_utc": "2026-03-07T00:00:00Z",',
  '    "canonical_url": "https://youtube.com/watch?v=abc"',
  '  },',
  '  "trust_signals": [',
  '    {',
  '      "schema": "rie.trust_signal.v1",',
  '      "signal_id": "sig_comm_001",',
  '      "tier": "C",',
  '      "kind": "lab_page_linked",',
  '      "evidence": { "note": "Community educator with some linkage", "domain": "youtube.com" },',
  '      "observed_at_utc": "2026-03-07T00:00:00Z"',
  '    }',
  '  ]',
  '}'
) -join "`n"
[System.IO.File]::WriteAllText($negCommunity, ($negCommunityJson + "`n"), $enc)

$outDir = Join-Path $RepoRoot "proofs\governance"

$r1 = RIE-RunSourceGovernanceV1 -RepoRoot $RepoRoot -SourcePath $posGov -AudiencePolicyPath $audPath -SourcePolicyPath $srcPolicyPath -DomainProfilesPath $domainProfilesPath -OutDir $outDir
if([string]$r1.action -ne "ALLOW_CHILD_SAFE"){ throw ("EXPECTED_ALLOW_CHILD_SAFE_GOT: " + [string]$r1.action) }
if([string]$r1.reason_code -notin @("ALLOW_CHILD_SAFE_TRUSTED_EDU","ALLOW_CHILD_SAFE_GOV_SCIENCE","ALLOW_CHILD_SAFE_PUBLISHER_BACKED")){ throw ("UNEXPECTED_REASON_POS: " + [string]$r1.reason_code) }
Write-Host ("POS_CHILD_SAFE_OK: " + $r1.reason_code) -ForegroundColor Green

$r2 = RIE-RunSourceGovernanceV1 -RepoRoot $RepoRoot -SourcePath $negAnswer -AudiencePolicyPath $audPath -SourcePolicyPath $srcPolicyPath -DomainProfilesPath $domainProfilesPath -OutDir $outDir
if([string]$r2.action -ne "DENY"){ throw ("EXPECTED_DENY_GOT: " + [string]$r2.action) }
if([string]$r2.reason_code -ne "DENY_FORBIDDEN_ANSWER_CONTENT"){ throw ("EXPECTED_DENY_FORBIDDEN_ANSWER_CONTENT_GOT: " + [string]$r2.reason_code) }
Write-Host ("NEG_ANSWER_DENY_OK: " + $r2.reason_code) -ForegroundColor Green

$r3 = RIE-RunSourceGovernanceV1 -RepoRoot $RepoRoot -SourcePath $negMissingProv -AudiencePolicyPath $audPath -SourcePolicyPath $srcPolicyPath -DomainProfilesPath $domainProfilesPath -OutDir $outDir
if([string]$r3.action -ne "DENY"){ throw ("EXPECTED_DENY_GOT: " + [string]$r3.action) }
if([string]$r3.reason_code -ne "DENY_MISSING_PROVENANCE"){ throw ("EXPECTED_DENY_MISSING_PROVENANCE_GOT: " + [string]$r3.reason_code) }
Write-Host ("NEG_PROVENANCE_DENY_OK: " + $r3.reason_code) -ForegroundColor Green

$r4 = RIE-RunSourceGovernanceV1 -RepoRoot $RepoRoot -SourcePath $negCommunity -AudiencePolicyPath $audPath -SourcePolicyPath $srcPolicyPath -DomainProfilesPath $domainProfilesPath -OutDir $outDir
if([string]$r4.action -ne "QUARANTINE_REVIEW_ONLY"){ throw ("EXPECTED_QUARANTINE_GOT: " + [string]$r4.action) }
if([string]$r4.reason_code -ne "QUARANTINE_REQUIRES_REVIEW"){ throw ("EXPECTED_QUARANTINE_REQUIRES_REVIEW_GOT: " + [string]$r4.reason_code) }
Write-Host ("NEG_COMMUNITY_QUARANTINE_OK: " + $r4.reason_code) -ForegroundColor Green

$receiptPath = Join-Path $RepoRoot "proofs\receipts\rie.source_governance.v1.ndjson"
if(-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)){ throw ("GOV_RECEIPT_MISSING: " + $receiptPath) }
Write-Host ("GOV_RECEIPT_OK: " + $receiptPath) -ForegroundColor Green

Write-Host "RIE_SOURCE_GOVERNANCE_SELFTEST_V1_OK" -ForegroundColor Green
