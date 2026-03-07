param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "RIE_QUERY_SELFTEST_V1_START" -ForegroundColor Cyan

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$Index = Join-Path $RepoRoot "scripts\rie_index_sources_v1.ps1"
$Query = Join-Path $RepoRoot "scripts\rie_query_v1.ps1"
$Bundle = Join-Path $RepoRoot "scripts\rie_build_bundle_v1.ps1"

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Index -RepoRoot $RepoRoot | Out-Null
$q = "example lecture demo"

$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Query -RepoRoot $RepoRoot -Query $q 2>&1 | Out-String
if($out.IndexOf("RIE_QUERY_OK:",[System.StringComparison]::Ordinal) -lt 0){
  throw "QUERY_RUN_FAILED"
}

$queryPath = Join-Path $RepoRoot "proofs\queries\rie_result_set_example_lecture_demo.json"
if(-not (Test-Path -LiteralPath $queryPath -PathType Leaf)){ throw ("QUERY_RESULT_MISSING: " + $queryPath) }

. (Join-Path $RepoRoot "scripts\rie_lib_v1.ps1")
$rs = RIE-ParseJson $queryPath
if([string]$rs["schema"] -ne "rie.result_set.v1"){ throw "BAD_RESULT_SET_SCHEMA" }
if([int]$rs["result_count"] -lt 1){ throw "RESULT_COUNT_LT_1" }

Write-Host ("QUERY_RESULT_OK: " + $queryPath) -ForegroundColor Green

$bOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Bundle -RepoRoot $RepoRoot -ResultSetPath $queryPath 2>&1 | Out-String
if($bOut.IndexOf("RIE_BUNDLE_OK:",[System.StringComparison]::Ordinal) -lt 0){
  throw "BUNDLE_RUN_FAILED"
}

Write-Host "RIE_QUERY_SELFTEST_V1_OK" -ForegroundColor Green