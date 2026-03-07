param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_HASH_LOOKUP_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $RepoRoot "scripts\rie_lib_v1.ps1")
. (Join-Path $RepoRoot "scripts\rie_hash_store_v1.ps1")

$tvDir = Join-Path $RepoRoot "test_vectors\hash_lookup_v1"
if(-not (Test-Path -LiteralPath $tvDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $tvDir | Out-Null
}

$sample = @(
  "{",
  "  ""schema"": ""rie.source_record.v1"",",
  "  ""source_id"": ""s_hash_001"",",
  "  ""content_kind"": ""paper"",",
  "  ""title"": ""Hash Lookup Example"",",
  "  ""provenance"": { ""discovered_from"": ""https://example.org/paper"", ""retrieved_at_utc"": ""2026-03-06T00:00:00Z"" },",
  "  ""tags"": [""hash"",""lookup""]",
  "}"
) -join "`n"

$samplePath = Join-Path $tvDir "source_record.hash_lookup.json"
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($samplePath, ($sample + "`n"), $enc)

$pub = RIE-PublishFileToHashStore $RepoRoot $samplePath
if(-not $pub.ok){ throw "PUBLISH_NOT_OK" }
Write-Host ("HASH_PUBLISH_OK: " + $pub.hash) -ForegroundColor Green

$resolved = RIE-ResolveByHash $RepoRoot $pub.hash
if(-not (Test-Path -LiteralPath $resolved -PathType Leaf)){ throw ("RESOLVED_PATH_MISSING: " + $resolved) }
Write-Host ("HASH_RESOLVE_OK: " + $resolved) -ForegroundColor Green

$o = RIE-ParseJson $resolved
RIE-ValidateSourceRecordV1 $o "hash_lookup.resolve"
Write-Host "HASH_RESOLVE_VALIDATE_OK" -ForegroundColor Green

try{
  [void](RIE-ResolveByHash $RepoRoot "sha256:does_not_exist")
  throw "NEG_EXPECTED_FAIL_BUT_PASSED"
} catch {
  if($_.Exception.Message -notmatch "HASH_NOT_FOUND"){
    throw
  }
  Write-Host ("NEG_HASH_NOT_FOUND_OK: " + $_.Exception.Message) -ForegroundColor Green
}

Write-Host "RIE_HASH_LOOKUP_SELFTEST_V1_OK" -ForegroundColor Green
