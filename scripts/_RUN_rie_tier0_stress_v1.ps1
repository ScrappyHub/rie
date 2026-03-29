param([Parameter(Mandatory=$true)][string]$RepoRoot)

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

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs=@(@($err))
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
    try{ $h = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
    $sb = New-Object System.Text.StringBuilder
    foreach($x in $h){ [void]$sb.AppendFormat("{0:x2}", $x) }
    return $sb.ToString()
  } finally { $sha.Dispose() }
}

function Run-ChildToLogs(
  [string]$PsExe,
  [string]$ScriptPath,
  [string]$RepoRoot,
  [string]$StdOut,
  [string]$StdErr,
  [string]$RequiredToken
){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }

  & $PsExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath -RepoRoot $RepoRoot 1> $StdOut 2> $StdErr
  $code = $LASTEXITCODE

  if($code -ne 0){
    $stderr = ""
    if(Test-Path -LiteralPath $StdErr -PathType Leaf){ $stderr = Get-Content -LiteralPath $StdErr -Raw }
    Die ("CHILD_EXIT_NONZERO: " + $ScriptPath + " :: " + $code + " :: " + $stderr)
  }

  if(-not (Test-Path -LiteralPath $StdOut -PathType Leaf)){ Die ("STDOUT_MISSING: " + $StdOut) }
  if(-not (Test-Path -LiteralPath $StdErr -PathType Leaf)){ Die ("STDERR_MISSING: " + $StdErr) }

  $stdoutText = Get-Content -LiteralPath $StdOut -Raw
  if($stdoutText.IndexOf($RequiredToken,[System.StringComparison]::Ordinal) -lt 0){
    Die ("CHILD_MISSING_TOKEN: " + $RequiredToken + " :: " + $ScriptPath)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PsExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$Scripts  = Join-Path $RepoRoot "scripts"
$Proofs   = Join-Path $RepoRoot "proofs"
$Logs     = Join-Path $Proofs "logs"
$Receipts = Join-Path $Proofs "receipts"
$Hashes   = Join-Path $Proofs "hashes"

Ensure-Dir $Logs
Ensure-Dir $Receipts
Ensure-Dir $Hashes

$BaseRunner = Join-Path $Scripts "_RUN_rie_tier0_v1.ps1"
$GovStress  = Join-Path $Scripts "_selftest_rie_governance_stress_v1.ps1"
$AudMatrix  = Join-Path $Scripts "_selftest_rie_audience_policy_matrix_v1.ps1"
$QryStress  = Join-Path $Scripts "_selftest_rie_query_stress_v1.ps1"

Write-Host "RIE_TIER0_STRESS_RUNNER_V1_START" -ForegroundColor Cyan

foreach($p in @($BaseRunner,$GovStress,$AudMatrix,$QryStress)){
  Parse-GateFile $p
  Write-Host ("PARSEGATE_OK: " + $p) -ForegroundColor Green
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")

$baseOut = Join-Path $Logs ("rie_tier0_base_stdout_" + $stamp + ".log")
$baseErr = Join-Path $Logs ("rie_tier0_base_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $BaseRunner $RepoRoot $baseOut $baseErr "RIE_TIER0_V1_OK"
Write-Host ("SELFTEST_OK: " + $BaseRunner) -ForegroundColor Green

$govOut = Join-Path $Logs ("rie_gov_stress_stdout_" + $stamp + ".log")
$govErr = Join-Path $Logs ("rie_gov_stress_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $GovStress $RepoRoot $govOut $govErr "RIE_GOVERNANCE_STRESS_SELFTEST_V1_OK"
Write-Host ("SELFTEST_OK: " + $GovStress) -ForegroundColor Green

$audOut = Join-Path $Logs ("rie_audience_matrix_stdout_" + $stamp + ".log")
$audErr = Join-Path $Logs ("rie_audience_matrix_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $AudMatrix $RepoRoot $audOut $audErr "RIE_AUDIENCE_POLICY_MATRIX_SELFTEST_V1_OK"
Write-Host ("SELFTEST_OK: " + $AudMatrix) -ForegroundColor Green

$qryOut = Join-Path $Logs ("rie_query_stress_stdout_" + $stamp + ".log")
$qryErr = Join-Path $Logs ("rie_query_stress_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $QryStress $RepoRoot $qryOut $qryErr "RIE_QUERY_STRESS_SELFTEST_V1_OK"
Write-Host ("SELFTEST_OK: " + $QryStress) -ForegroundColor Green

$receiptPath = Join-Path $Receipts "rie.tier0.stress.v1.ndjson"
$receiptObj = [ordered]@{
  schema = "rie.tier0.stress.v1"
  utc = (Get-Date).ToUniversalTime().ToString("o")
  repo_root = $RepoRoot
  base_stdout = $baseOut
  base_stderr = $baseErr
  governance_stress_stdout = $govOut
  governance_stress_stderr = $govErr
  audience_matrix_stdout = $audOut
  audience_matrix_stderr = $audErr
  query_stress_stdout = $qryOut
  query_stress_stderr = $qryErr
  base_stdout_sha256 = (Sha256HexFile $baseOut)
  base_stderr_sha256 = (Sha256HexFile $baseErr)
  governance_stress_stdout_sha256 = (Sha256HexFile $govOut)
  governance_stress_stderr_sha256 = (Sha256HexFile $govErr)
  audience_matrix_stdout_sha256 = (Sha256HexFile $audOut)
  audience_matrix_stderr_sha256 = (Sha256HexFile $audErr)
  query_stress_stdout_sha256 = (Sha256HexFile $qryOut)
  query_stress_stderr_sha256 = (Sha256HexFile $qryErr)
  ok = $true
}
$receiptLine = ($receiptObj | ConvertTo-Json -Depth 10 -Compress)
Write-Utf8NoBomLf $receiptPath ($receiptLine + "`n")

$hashManifest = Join-Path $Hashes ("rie_tier0_stress_" + $stamp + "_sha256sums.txt")
$rows = New-Object System.Collections.Generic.List[string]
foreach($p in @($baseOut,$baseErr,$govOut,$govErr,$audOut,$audErr,$qryOut,$qryErr,$receiptPath)){
  [void]$rows.Add((Sha256HexFile $p) + "  " + $p)
}
Write-Utf8NoBomLf $hashManifest ((@($rows.ToArray()) -join "`n") + "`n")

Write-Host ("RECEIPT_OK: " + $receiptPath) -ForegroundColor Green
Write-Host ("HASH_MANIFEST_OK: " + $hashManifest) -ForegroundColor Green
Write-Host "RIE_TIER0_STRESS_V1_OK" -ForegroundColor Green
