param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Write-Host "RIE_SELFTEST_V1_START" -ForegroundColor Cyan
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot "scripts\rie_lib_v1.ps1")
$tvDir = Join-Path $RepoRoot "test_vectors\minimal_valid"
if(-not (Test-Path -LiteralPath $tvDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $tvDir | Out-Null }
$enc = New-Object System.Text.UTF8Encoding($false)
$srcLines = @(
  "{",
  "  ""schema"": ""rie.source_record.v1"","
  "  ""source_id"": ""s_vid_001"","
  "  ""content_kind"": ""video"","
  "  ""title"": ""Example Lecture"","
  "  ""provenance"": { ""discovered_from"": ""https://example.edu/course/page"", ""retrieved_at_utc"": ""2026-02-23T00:00:00Z"" },"
  "  ""tags"": [""demo""]"
  "}"
)
$src = ($srcLines -join "`n")
$srcPath = Join-Path $tvDir "source_record.v1.json"
[System.IO.File]::WriteAllText($srcPath, ($src + "`n"), $enc)
$o = RIE-ParseJson $srcPath
RIE-ValidateSourceRecordV1 $o "tv.source_record"
Write-Host "POS_SOURCE_RECORD_OK" -ForegroundColor Green
$badLines = @(
  "{",
  "  ""schema"": ""rie.source_record.v1"","
  "  ""source_id"": ""s_bad_001"","
  "  ""content_kind"": ""video"","
  "  ""title"": ""Bad Example"","
  "  ""provenance"": { ""discovered_from"": ""x"", ""retrieved_at_utc"": ""y"" },"
  "  ""answer"": ""NOPE"""
  "}"
)
$bad = ($badLines -join "`n")
$badPath = Join-Path $tvDir "source_record.forbidden_prop.json"
[System.IO.File]::WriteAllText($badPath, ($bad + "`n"), $enc)
$b = RIE-ParseJson $badPath
try { RIE-ValidateSourceRecordV1 $b "tv.bad"; throw "NEG_EXPECTED_FAIL_BUT_PASSED" } catch { if($_.Exception.Message -notmatch "FORBIDDEN_PROP"){ throw }; Write-Host ("NEG_FORBIDDEN_PROP_OK: " + $_.Exception.Message) -ForegroundColor Green }
Write-Host "RIE_SELFTEST_V1_OK" -ForegroundColor Green
