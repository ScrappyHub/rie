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

function Run-ChildToLogs(
  [string]$PsExe,
  [string]$ScriptPath,
  [string]$RepoRoot,
  [string[]]$ExtraArgs,
  [string]$StdOut,
  [string]$StdErr,
  [string]$RequiredToken
){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }

  $argList = New-Object System.Collections.Generic.List[string]
  [void]$argList.Add("-NoProfile")
  [void]$argList.Add("-NonInteractive")
  [void]$argList.Add("-ExecutionPolicy")
  [void]$argList.Add("Bypass")
  [void]$argList.Add("-File")
  [void]$argList.Add($ScriptPath)
  [void]$argList.Add("-RepoRoot")
  [void]$argList.Add($RepoRoot)

  foreach($a in @(@($ExtraArgs))){
    [void]$argList.Add([string]$a)
  }

  & $PsExe @($argList.ToArray()) 1> $StdOut 2> $StdErr
  $code = $LASTEXITCODE

  if($code -ne 0){
    $stderr = ""
    if(Test-Path -LiteralPath $StdErr -PathType Leaf){
      $stderr = Get-Content -LiteralPath $StdErr -Raw
    }
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

$Lib       = Join-Path $Scripts "rie_lib_v1.ps1"
$SelfA     = Join-Path $Scripts "_selftest_rie_v1.ps1"
$HashLib   = Join-Path $Scripts "rie_hash_store_v1.ps1"
$SelfB     = Join-Path $Scripts "_selftest_rie_hash_lookup_v1.ps1"
$Index     = Join-Path $Scripts "rie_index_sources_v1.ps1"
$QuerySelf = Join-Path $Scripts "_selftest_rie_query_v1.ps1"

Write-Host "RIE_TIER0_RUNNER_V1_START" -ForegroundColor Cyan

foreach($p in @($Lib,$SelfA,$HashLib,$SelfB,$Index,$QuerySelf)){
  Parse-GateFile $p
  Write-Host ("PARSEGATE_OK: " + $p) -ForegroundColor Green
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")

$selfAOut = Join-Path $Logs ("rie_selftest_stdout_" + $stamp + ".log")
$selfAErr = Join-Path $Logs ("rie_selftest_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $SelfA $RepoRoot @() $selfAOut $selfAErr "RIE_SELFTEST_V1_OK"
Write-Host ("SELFTEST_OK: " + $SelfA) -ForegroundColor Green

$selfBOut = Join-Path $Logs ("rie_hash_selftest_stdout_" + $stamp + ".log")
$selfBErr = Join-Path $Logs ("rie_hash_selftest_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $SelfB $RepoRoot @() $selfBOut $selfBErr "RIE_HASH_LOOKUP_SELFTEST_V1_OK"
Write-Host ("SELFTEST_OK: " + $SelfB) -ForegroundColor Green

$selfCOut = Join-Path $Logs ("rie_query_selftest_stdout_" + $stamp + ".log")
$selfCErr = Join-Path $Logs ("rie_query_selftest_stderr_" + $stamp + ".log")
Run-ChildToLogs $PsExe $QuerySelf $RepoRoot @() $selfCOut $selfCErr "RIE_QUERY_SELFTEST_V1_OK"
Write-Host ("SELFTEST_OK: " + $QuerySelf) -ForegroundColor Green

$receiptPath = Join-Path $Receipts "rie.tier0.runner.v1.ndjson"
$receiptObj = [ordered]@{
  schema = "rie.tier0.runner.v1"
  utc = (Get-Date).ToUniversalTime().ToString("o")
  repo_root = $RepoRoot
  selftest_primary_stdout = $selfAOut
  selftest_primary_stderr = $selfAErr
  selftest_hash_stdout = $selfBOut
  selftest_hash_stderr = $selfBErr
  selftest_query_stdout = $selfCOut
  selftest_query_stderr = $selfCErr
  selftest_primary_stdout_sha256 = (Sha256HexFile $selfAOut)
  selftest_primary_stderr_sha256 = (Sha256HexFile $selfAErr)
  selftest_hash_stdout_sha256 = (Sha256HexFile $selfBOut)
  selftest_hash_stderr_sha256 = (Sha256HexFile $selfBErr)
  selftest_query_stdout_sha256 = (Sha256HexFile $selfCOut)
  selftest_query_stderr_sha256 = (Sha256HexFile $selfCErr)
  ok = $true
}
$receiptLine = ($receiptObj | ConvertTo-Json -Compress)
Write-Utf8NoBomLf $receiptPath ($receiptLine + "`n")

$hashManifest = Join-Path $Hashes ("rie_tier0_runner_" + $stamp + "_sha256sums.txt")
$rows = New-Object System.Collections.Generic.List[string]
foreach($p in @($selfAOut,$selfAErr,$selfBOut,$selfBErr,$selfCOut,$selfCErr,$receiptPath)){
  [void]$rows.Add((Sha256HexFile $p) + "  " + $p)
}
Write-Utf8NoBomLf $hashManifest ((@($rows.ToArray()) -join "`n") + "`n")

Write-Host ("RECEIPT_OK: " + $receiptPath) -ForegroundColor Green
Write-Host ("HASH_MANIFEST_OK: " + $hashManifest) -ForegroundColor Green
Write-Host "RIE_TIER0_V1_OK" -ForegroundColor Green
