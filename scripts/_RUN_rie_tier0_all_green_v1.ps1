param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "WRITE_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("FILE_MISSING: " + $Path) }
  $b = [System.IO.File]::ReadAllBytes($Path)
  $enc = New-Object System.Text.UTF8Encoding($false,$true)
  return $enc.GetString($b)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs = @(@($err))
  if($errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg)
  }
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("FILE_MISSING: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $fs = [System.IO.File]::OpenRead($Path)
    try{
      $h = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
    $sb = New-Object System.Text.StringBuilder
    foreach($x in $h){ [void]$sb.AppendFormat("{0:x2}", $x) }
    return $sb.ToString()
  } finally {
    $sha.Dispose()
  }
}

function Json-Compress($Obj){
  return ($Obj | ConvertTo-Json -Depth 50 -Compress)
}

function Run-ChildToLogs(
  [string]$PsExe,
  [string]$ScriptPath,
  [string]$RepoRoot,
  [string]$StdOutPath,
  [string]$StdErrPath,
  [string]$RequiredToken
){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }

  & $PsExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath -RepoRoot $RepoRoot 1> $StdOutPath 2> $StdErrPath
  $code = $LASTEXITCODE

  if($code -ne 0){
    $stderr = ""
    if(Test-Path -LiteralPath $StdErrPath -PathType Leaf){
      $stderr = Get-Content -LiteralPath $StdErrPath -Raw
    }
    Die ("CHILD_EXIT_NONZERO: " + $ScriptPath + " :: " + $code + " :: " + $stderr)
  }

  if(-not (Test-Path -LiteralPath $StdOutPath -PathType Leaf)){ Die ("STDOUT_MISSING: " + $StdOutPath) }
  if(-not (Test-Path -LiteralPath $StdErrPath -PathType Leaf)){ Die ("STDERR_MISSING: " + $StdErrPath) }

  $stdoutText = Get-Content -LiteralPath $StdOutPath -Raw
  if($stdoutText.IndexOf($RequiredToken,[System.StringComparison]::Ordinal) -lt 0){
    Die ("CHILD_MISSING_TOKEN: " + $RequiredToken + " :: " + $ScriptPath)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PsExe    = (Get-Command powershell.exe -ErrorAction Stop).Source

$Scripts    = Join-Path $RepoRoot "scripts"
$Proofs     = Join-Path $RepoRoot "proofs"
$Receipts   = Join-Path $Proofs "receipts"
$Hashes     = Join-Path $Proofs "hashes"
$Logs       = Join-Path $Proofs "logs"
$RunRoot    = Join-Path $Proofs "all_green"
$Stamp      = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$RunDir     = Join-Path $RunRoot ("rie_tier0_all_green_" + $Stamp)

Ensure-Dir $Receipts
Ensure-Dir $Hashes
Ensure-Dir $Logs
Ensure-Dir $RunRoot
Ensure-Dir $RunDir

$Tier0Runner = Join-Path $Scripts "_RUN_rie_tier0_v1.ps1"
$StressRunner = Join-Path $Scripts "_RUN_rie_tier0_stress_v1.ps1"

$ParseTargets = @(
  (Join-Path $Scripts "rie_lib_v1.ps1"),
  (Join-Path $Scripts "rie_hash_store_v1.ps1"),
  (Join-Path $Scripts "rie_source_governance_v1.ps1"),
  (Join-Path $Scripts "rie_index_sources_v1.ps1"),
  (Join-Path $Scripts "rie_query_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_hash_lookup_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_source_governance_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_query_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_governance_stress_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_audience_policy_matrix_v1.ps1"),
  (Join-Path $Scripts "_selftest_rie_query_stress_v1.ps1"),
  $Tier0Runner,
  $StressRunner
)

Write-Host "RIE_TIER0_ALL_GREEN_V1_START" -ForegroundColor Cyan

foreach($p in @($ParseTargets)){
  Parse-GateFile $p
  Write-Host ("PARSEGATE_OK: " + $p) -ForegroundColor Green
}

$tier0StdOut = Join-Path $RunDir "01_tier0_stdout.log"
$tier0StdErr = Join-Path $RunDir "01_tier0_stderr.log"
Run-ChildToLogs $PsExe $Tier0Runner $RepoRoot $tier0StdOut $tier0StdErr "RIE_TIER0_V1_OK"
Write-Host ("STEP_OK: " + $Tier0Runner) -ForegroundColor Green

$stressStdOut = Join-Path $RunDir "02_stress_stdout.log"
$stressStdErr = Join-Path $RunDir "02_stress_stderr.log"
Run-ChildToLogs $PsExe $StressRunner $RepoRoot $stressStdOut $stressStdErr "RIE_TIER0_STRESS_V1_OK"
Write-Host ("STEP_OK: " + $StressRunner) -ForegroundColor Green

$receiptPath = Join-Path $Receipts "rie.tier0.all_green.v1.ndjson"
$receiptObj = [ordered]@{
  schema = "rie.tier0.all_green.v1"
  utc = (Get-Date).ToUniversalTime().ToString("o")
  repo_root = $RepoRoot
  run_dir = $RunDir
  tier0_runner = $Tier0Runner
  stress_runner = $StressRunner
  tier0_stdout = $tier0StdOut
  tier0_stderr = $tier0StdErr
  stress_stdout = $stressStdOut
  stress_stderr = $stressStdErr
  tier0_stdout_sha256 = (Sha256HexFile $tier0StdOut)
  tier0_stderr_sha256 = (Sha256HexFile $tier0StdErr)
  stress_stdout_sha256 = (Sha256HexFile $stressStdOut)
  stress_stderr_sha256 = (Sha256HexFile $stressStdErr)
  ok = $true
}
$receiptLine = Json-Compress $receiptObj

$existingReceipt = ""
if(Test-Path -LiteralPath $receiptPath -PathType Leaf){
  $existingReceipt = Read-Utf8NoBom $receiptPath
  $existingReceipt = $existingReceipt.Replace("`r`n","`n").Replace("`r","`n").TrimEnd()
}
if([string]::IsNullOrWhiteSpace($existingReceipt)){
  Write-Utf8NoBomLf $receiptPath ($receiptLine + "`n")
} else {
  Write-Utf8NoBomLf $receiptPath ($existingReceipt + "`n" + $receiptLine + "`n")
}

$hashManifest = Join-Path $Hashes ("rie_tier0_all_green_" + $Stamp + "_sha256sums.txt")
$rows = New-Object System.Collections.Generic.List[string]
[void]$rows.Add((Sha256HexFile $tier0StdOut) + "  " + $tier0StdOut)
[void]$rows.Add((Sha256HexFile $tier0StdErr) + "  " + $tier0StdErr)
[void]$rows.Add((Sha256HexFile $stressStdOut) + "  " + $stressStdOut)
[void]$rows.Add((Sha256HexFile $stressStdErr) + "  " + $stressStdErr)
[void]$rows.Add((Sha256HexFile $receiptPath) + "  " + $receiptPath)
Write-Utf8NoBomLf $hashManifest ((@($rows.ToArray()) -join "`n") + "`n")

Write-Host ("RECEIPT_OK: " + $receiptPath) -ForegroundColor Green
Write-Host ("HASH_MANIFEST_OK: " + $hashManifest) -ForegroundColor Green
Write-Host ("RUN_DIR_OK: " + $RunDir) -ForegroundColor Green
Write-Host "RIE_TIER0_ALL_GREEN_V1_OK" -ForegroundColor Green