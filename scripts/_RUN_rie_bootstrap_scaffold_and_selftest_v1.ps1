param([Parameter(Mandatory=$false)][string]$RepoRoot="C:\dev\rie")
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path,$enc.GetBytes($t))
}
function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){ $msg = ($err | ForEach-Object { $_.ToString() }) -join "`n"; Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg) }
}
function Run-Child([string]$ScriptPath,[hashtable]$ArgMap,[string]$OutLog,[string]$ErrLog){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }
  $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  $args = New-Object System.Collections.Generic.List[string]
  [void]$args.Add("-NoProfile"); [void]$args.Add("-NonInteractive"); [void]$args.Add("-ExecutionPolicy"); [void]$args.Add("Bypass"); [void]$args.Add("-File"); [void]$args.Add($ScriptPath)
  foreach($k in @(@($ArgMap.Keys))){ [void]$args.Add(("-" + [string]$k)); [void]$args.Add([string]$ArgMap[$k]) }
  $p = Start-Process -FilePath $psExe -ArgumentList @($args.ToArray()) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
  if($p.ExitCode -ne 0){
    $o=""; $e=""
    if(Test-Path -LiteralPath $OutLog -PathType Leaf){ $o = (Get-Content -Raw -LiteralPath $OutLog) }
    if(Test-Path -LiteralPath $ErrLog -PathType Leaf){ $e = (Get-Content -Raw -LiteralPath $ErrLog) }
    Die ("CHILD_FAIL_EXITCODE=" + $p.ExitCode + "`n---STDOUT---`n" + $o + "`n---STDERR---`n" + $e)
  }
}

if([string]::IsNullOrWhiteSpace($RepoRoot)){ Die "REPOROOT_EMPTY" }
EnsureDir $RepoRoot
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Docs    = Join-Path $RepoRoot "docs"
$Schemas = Join-Path $RepoRoot "schemas"
$TVMin   = Join-Path $RepoRoot "test_vectors\minimal"
$TVNeg   = Join-Path $RepoRoot "test_vectors\negative"
$Scripts = Join-Path $RepoRoot "scripts"
$Proofs  = Join-Path $RepoRoot "proofs"
$Logs    = Join-Path $Proofs  "transcripts"
EnsureDir $Docs; EnsureDir $Schemas; EnsureDir $TVMin; EnsureDir $TVNeg; EnsureDir $Scripts; EnsureDir $Logs
Write-Host "RIE_BOOTSTRAP_V1_START" -ForegroundColor Cyan
Write-Host ("REPOROOT: " + $RepoRoot)

Write-Utf8NoBomLf (Join-Path $RepoRoot "README.md") "# Research Infrastructure Engine (RIE)`n"
Write-Utf8NoBomLf (Join-Path $Docs "RIE_LAYER.md") "# RIE Layer`nRIE is a STEM retrieval + evidence instrument (no answers).`n"
Write-Utf8NoBomLf (Join-Path $RepoRoot "test_vectors\README.md") "minimal/ must PASS; negative/ must FAIL.`n"

# Stub selftest file (we will expand next once runner is stable)
Write-Utf8NoBomLf (Join-Path $Scripts "_selftest_rie_schemas_v1.ps1") "param([string]`$RepoRoot=`"`"); Set-StrictMode -Version Latest; `$ErrorActionPreference=`"Stop`"; Write-Host `"SELFTEST_STUB_OK`" -ForegroundColor Green`n"
Parse-GateFile (Join-Path $Scripts "_selftest_rie_schemas_v1.ps1")

$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$outLog = Join-Path $Logs ("selftest_stdout_" + $ts + ".log")
$errLog = Join-Path $Logs ("selftest_stderr_" + $ts + ".log")
Run-Child (Join-Path $Scripts "_selftest_rie_schemas_v1.ps1") @{ RepoRoot = $RepoRoot } $outLog $errLog
Write-Host ("SELFTEST_CHILD_OK: " + $outLog) -ForegroundColor Green
Write-Host "RIE_BOOTSTRAP_V1_OK" -ForegroundColor Green
