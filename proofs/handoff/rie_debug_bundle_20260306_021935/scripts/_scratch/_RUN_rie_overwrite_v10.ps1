param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ if([string]::IsNullOrWhiteSpace($Path)){ Die "WRITE_PATH_EMPTY" }; $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); $enc=New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($Path,$t,$enc) }
function Parse-GateFile([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $tok=$null; $err=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err); if($err -and $err.Count -gt 0){ $msg=($err|ForEach-Object{$_.ToString()})-join "`n"; Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg) } }
function Run-Child([string]$ScriptPath,[hashtable]$ArgMap,[string]$OutLog,[string]$ErrLog){ if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_MISSING: " + $ScriptPath) }; $psExe=(Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source; $args=New-Object System.Collections.Generic.List[string]; [void]$args.Add("-NoProfile"); [void]$args.Add("-NonInteractive"); [void]$args.Add("-ExecutionPolicy"); [void]$args.Add("Bypass"); [void]$args.Add("-File"); [void]$args.Add($ScriptPath); foreach($k in @(@($ArgMap.Keys))){ [void]$args.Add("-"+[string]$k); $v=$ArgMap[$k]; if($null -eq $v){ $v="" }; [void]$args.Add([string]$v) }; EnsureDir (Split-Path -Parent $OutLog); EnsureDir (Split-Path -Parent $ErrLog); $p=Start-Process -FilePath $psExe -ArgumentList $args.ToArray() -Wait -PassThru -NoNewWindow -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog; if($p.ExitCode -ne 0){ Die ("CHILD_FAIL_EXITCODE: " + $p.ExitCode) } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"
$Schemas = Join-Path $RepoRoot "schemas"
$TV      = Join-Path $RepoRoot "test_vectors"
$Proofs  = Join-Path $RepoRoot "proofs\receipts"
$Logs    = Join-Path $RepoRoot "proofs\logs"
EnsureDir $Scripts; EnsureDir $Schemas; EnsureDir $TV; EnsureDir $Proofs; EnsureDir $Logs
Write-Host "RIE_OVERWRITE_V10_START" -ForegroundColor Cyan

$schemaSourceRecordLines = @(
  '{',
  '  "$schema": "https://json-schema.org/draft/2020-12/schema",',
  '  "title": "RIE Source Record v1",',
  '  "type": "object",',
  '  "additionalProperties": false,',
  '  "required": ["schema","source_id","content_kind","title","provenance"],',
  '  "properties": {',
  '    "schema": { "const": "rie.source_record.v1" },',
  '    "source_id": { "type": "string", "minLength": 1 },',
  '    "content_kind": { "type": "string", "minLength": 1 },',
  '    "title": { "type": "string", "minLength": 1 },',
  '    "provenance": {',
  '      "type": "object",',
  '      "additionalProperties": false,',
  '      "required": ["discovered_from","retrieved_at_utc"],',
  '      "properties": {',
  '        "discovered_from": { "type": "string", "minLength": 1 },',
  '        "retrieved_at_utc": { "type": "string", "minLength": 1 }',
  '      }',
  '    },',
  '    "tags": { "type": "array", "items": { "type": "string" } }',
  '  }',
  '}'
)
$schemaSourceRecord = ($schemaSourceRecordLines -join "`n")
Write-Utf8NoBomLf (Join-Path $Schemas "rie.source_record.v1.schema.json") ($schemaSourceRecord + "`n")

$Lib = Join-Path $Scripts "rie_lib_v1.ps1"
$libLines = @(
  'Set-StrictMode -Version Latest',
  '$ErrorActionPreference = "Stop"',
  'function RIE-Die([string]$m){ throw $m }',
  'function RIE-ReadUtf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }; $b=[System.IO.File]::ReadAllBytes($Path); $enc=New-Object System.Text.UTF8Encoding($false,$true); $enc.GetString($b) }',
  'function RIE-ParseJson([string]$Path){ $raw = RIE-ReadUtf8NoBom $Path; try { $raw | ConvertFrom-Json -Depth 200 } catch { RIE-Die ("JSON_PARSE_FAIL: " + $Path) } }',
  'function RIE-HasProp($o,[string]$name){ if($null -eq $o){ return $false }; @(@($o.PSObject.Properties.Name)) -contains $name }',
  'function RIE-AssertHasProps($o,[string[]]$names,[string]$ctx){ foreach($n in @(@($names))){ if(-not (RIE-HasProp $o $n)){ RIE-Die ("MISSING_PROP: " + $ctx + " :: " + $n) } } }',
  'function RIE-AssertNoProps($o,[string[]]$names,[string]$ctx){ foreach($n in @(@($names))){ if(RIE-HasProp $o $n){ RIE-Die ("FORBIDDEN_PROP: " + $ctx + " :: " + $n) } } }',
  'function RIE-ValidateSourceRecordV1($o,[string]$ctx){ RIE-AssertNoProps $o @("answer","solution","steps","explanation") $ctx; RIE-AssertHasProps $o @("schema","source_id","content_kind","title","provenance") $ctx; if([string]$o.schema -ne "rie.source_record.v1"){ RIE-Die ("BAD_SCHEMA: " + $ctx) }; $p=$o.provenance; RIE-AssertHasProps $p @("discovered_from","retrieved_at_utc") ($ctx + ".provenance") }'
)
$libText = ($libLines -join "`n")
Write-Utf8NoBomLf $Lib ($libText + "`n")

$Self = Join-Path $Scripts "_selftest_rie_v1.ps1"
$selfLines = @(
  'param([Parameter(Mandatory=$true)][string]$RepoRoot)',
  'Set-StrictMode -Version Latest',
  '$ErrorActionPreference = "Stop"',
  'Write-Host "RIE_SELFTEST_V1_START" -ForegroundColor Cyan',
  '$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path',
  '. (Join-Path $RepoRoot "scripts\rie_lib_v1.ps1")',
  '$tvDir = Join-Path $RepoRoot "test_vectors\minimal_valid"',
  'if(-not (Test-Path -LiteralPath $tvDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $tvDir | Out-Null }',
  '$enc = New-Object System.Text.UTF8Encoding($false)',
  '$srcLines = @(' ,
  '  "{",',
  '  "  ""schema"": ""rie.source_record.v1"","',
  '  "  ""source_id"": ""s_vid_001"","',
  '  "  ""content_kind"": ""video"","',
  '  "  ""title"": ""Example Lecture"","',
  '  "  ""provenance"": { ""discovered_from"": ""https://example.edu/course/page"", ""retrieved_at_utc"": ""2026-02-23T00:00:00Z"" },"',
  '  "  ""tags"": [""demo""]"',
  '  "}"'
  ')' ,
  '$src = ($srcLines -join "`n")',
  '$srcPath = Join-Path $tvDir "source_record.v1.json"',
  '[System.IO.File]::WriteAllText($srcPath, ($src + "`n"), $enc)',
  '$o = RIE-ParseJson $srcPath',
  'RIE-ValidateSourceRecordV1 $o "tv.source_record"',
  'Write-Host "POS_SOURCE_RECORD_OK" -ForegroundColor Green',
  '$badLines = @(' ,
  '  "{",',
  '  "  ""schema"": ""rie.source_record.v1"","',
  '  "  ""source_id"": ""s_bad_001"","',
  '  "  ""content_kind"": ""video"","',
  '  "  ""title"": ""Bad Example"","',
  '  "  ""provenance"": { ""discovered_from"": ""x"", ""retrieved_at_utc"": ""y"" },"',
  '  "  ""answer"": ""NOPE"""',
  '  "}"'
  ')' ,
  '$bad = ($badLines -join "`n")',
  '$badPath = Join-Path $tvDir "source_record.forbidden_prop.json"',
  '[System.IO.File]::WriteAllText($badPath, ($bad + "`n"), $enc)',
  '$b = RIE-ParseJson $badPath',
  'try { RIE-ValidateSourceRecordV1 $b "tv.bad"; throw "NEG_EXPECTED_FAIL_BUT_PASSED" } catch { if($_.Exception.Message -notmatch "FORBIDDEN_PROP"){ throw }; Write-Host ("NEG_FORBIDDEN_PROP_OK: " + $_.Exception.Message) -ForegroundColor Green }',
  'Write-Host "RIE_SELFTEST_V1_OK" -ForegroundColor Green'
)
$selfText = ($selfLines -join "`n")
Write-Utf8NoBomLf $Self ($selfText + "`n")

Parse-GateFile $Lib
Parse-GateFile $Self
Write-Host ("LIB_PARSE_OK: " + $Lib) -ForegroundColor Green
Write-Host ("SELFTEST_PARSE_OK: " + $Self) -ForegroundColor Green
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$outLog = Join-Path $Logs ("selftest_stdout_" + $ts + ".log")
$errLog = Join-Path $Logs ("selftest_stderr_" + $ts + ".log")
Write-Host ("RUN_CHILD_COMMAND_PRESENT=" + ([bool](Get-Command Run-Child -ErrorAction SilentlyContinue))) -ForegroundColor DarkGray
try {
  $rc = (Get-Command Run-Child -ErrorAction Stop)
  Write-Host ("RUN_CHILD_RESOLVED=" + $rc.Source) -ForegroundColor DarkGray
} catch {
  Write-Host "RUN_CHILD_RESOLVED=<none>" -ForegroundColor DarkGray
}

# INLINE CHILD EXEC (cannot be bypassed)
$psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$argList = New-Object System.Collections.Generic.List[string]
[void]$argList.Add("-NoProfile")
[void]$argList.Add("-NonInteractive")
[void]$argList.Add("-ExecutionPolicy")
[void]$argList.Add("Bypass")
[void]$argList.Add("-File")
[void]$argList.Add($Self)
[void]$argList.Add("-RepoRoot")
[void]$argList.Add($RepoRoot)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $psExe
$psi.Arguments = (@($argList.ToArray()) -join " ")
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()
$code = $p.ExitCode
Write-Utf8NoBomLf $outLog $stdout
Write-Utf8NoBomLf $errLog $stderr
$global:LASTEXITCODE = $code
if($code -ne 0){
  Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_START" -ForegroundColor Yellow
  if(Test-Path -LiteralPath $outLog -PathType Leaf){
    Write-Host ("--- STDOUT: " + $outLog) -ForegroundColor Yellow
    Get-Content -LiteralPath $outLog -Tail 200 | Out-Host
  }
  if(Test-Path -LiteralPath $errLog -PathType Leaf){
    Write-Host ("--- STDERR: " + $errLog) -ForegroundColor Yellow
    Get-Content -LiteralPath $errLog -Tail 200 | Out-Host
  }
  Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_END" -ForegroundColor Yellow
  Die ("CHILD_FAIL_EXITCODE: " + $code)
}
if($LASTEXITCODE -ne 0){
  Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_START" -ForegroundColor Yellow
  if(Test-Path -LiteralPath $outLog -PathType Leaf){
    Write-Host ("--- STDOUT: " + $outLog) -ForegroundColor Yellow
    Get-Content -LiteralPath $outLog -Tail 200 | Out-Host
  }
  if(Test-Path -LiteralPath $errLog -PathType Leaf){
    Write-Host ("--- STDERR: " + $errLog) -ForegroundColor Yellow
    Get-Content -LiteralPath $errLog -Tail 200 | Out-Host
  }
  Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_END" -ForegroundColor Yellow
  Die ("CHILD_FAIL_EXITCODE: " + $LASTEXITCODE)
}
if(-not (Test-Path -LiteralPath $outLog -PathType Leaf)){ Die ("MISSING_OUTLOG: " + $outLog) }
if(-not (Test-Path -LiteralPath $errLog -PathType Leaf)){ Die ("MISSING_ERRLOG: " + $errLog) }
Write-Host ("SELFTEST_CHILD_OK: " + $outLog) -ForegroundColor Green
Write-Host "RIE_OVERWRITE_V10_OK" -ForegroundColor Green
# BEGIN_OVERRIDE_RUN_CHILD_DUMPLOGS_V1
# Redefine Run-Child at EOF so it is used at runtime (PowerShell parses whole file; last definition wins).
function Run-Child([string]$ScriptPath,[hashtable]$Args,[string]$OutLog,[string]$ErrLog){
  $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }
  if([string]::IsNullOrWhiteSpace($OutLog)){ Die "OUTLOG_EMPTY" }
  if([string]::IsNullOrWhiteSpace($ErrLog)){ Die "ERRLOG_EMPTY" }
  $argList = New-Object System.Collections.Generic.List[string]
  [void]$argList.Add("-NoProfile")
  [void]$argList.Add("-NonInteractive")
  [void]$argList.Add("-ExecutionPolicy")
  [void]$argList.Add("Bypass")
  [void]$argList.Add("-File")
  [void]$argList.Add($ScriptPath)
  foreach($k in @($Args.Keys)){
    $v = [string]$Args[$k]
    [void]$argList.Add("-$k")
    [void]$argList.Add($v)
  }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = (@($argList.ToArray()) -join " ")
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $code = $p.ExitCode
  Write-Utf8NoBomLf $OutLog $stdout
  Write-Utf8NoBomLf $ErrLog $stderr
  $global:LASTEXITCODE = $code
  if($code -ne 0){
    Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_START" -ForegroundColor Yellow
    Write-Host ("--- STDOUT: " + $OutLog) -ForegroundColor Yellow
    if(Test-Path -LiteralPath $OutLog -PathType Leaf){ Get-Content -LiteralPath $OutLog -Tail 200 | Out-Host }
    Write-Host ("--- STDERR: " + $ErrLog) -ForegroundColor Yellow
    if(Test-Path -LiteralPath $ErrLog -PathType Leaf){ Get-Content -LiteralPath $ErrLog -Tail 200 | Out-Host }
    Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_END" -ForegroundColor Yellow
    Die ("CHILD_FAIL_EXITCODE: " + $code)
  }
}
# END_OVERRIDE_RUN_CHILD_DUMPLOGS_V1
# BEGIN_OVERRIDE_RUN_CHILD_DUMPLOGS_V1
# EOF override: last function definition wins (PowerShell parses whole file).
function Run-Child([string]$ScriptPath,[hashtable]$Args,[string]$OutLog,[string]$ErrLog){
  $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_SCRIPT_MISSING: " + $ScriptPath) }
  if([string]::IsNullOrWhiteSpace($OutLog)){ Die "OUTLOG_EMPTY" }
  if([string]::IsNullOrWhiteSpace($ErrLog)){ Die "ERRLOG_EMPTY" }

  $argList = New-Object System.Collections.Generic.List[string]
  [void]$argList.Add("-NoProfile")
  [void]$argList.Add("-NonInteractive")
  [void]$argList.Add("-ExecutionPolicy")
  [void]$argList.Add("Bypass")
  [void]$argList.Add("-File")
  [void]$argList.Add($ScriptPath)
  foreach($k in @($Args.Keys)){
    $v = [string]$Args[$k]
    [void]$argList.Add("-$k")
    [void]$argList.Add($v)
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $psExe
  $psi.Arguments = (@($argList.ToArray()) -join " ")
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $code = $p.ExitCode

  Write-Utf8NoBomLf $OutLog $stdout
  Write-Utf8NoBomLf $ErrLog $stderr
  $global:LASTEXITCODE = $code

  if($code -ne 0){
    Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_START" -ForegroundColor Yellow
    if(Test-Path -LiteralPath $OutLog -PathType Leaf){
      Write-Host ("--- STDOUT: " + $OutLog) -ForegroundColor Yellow
      Get-Content -LiteralPath $OutLog -Tail 200 | Out-Host
    }
    if(Test-Path -LiteralPath $ErrLog -PathType Leaf){
      Write-Host ("--- STDERR: " + $ErrLog) -ForegroundColor Yellow
      Get-Content -LiteralPath $ErrLog -Tail 200 | Out-Host
    }
    Write-Host "SELFTEST_CHILD_FAILED_DUMP_LOGS_END" -ForegroundColor Yellow
    Die ("CHILD_FAIL_EXITCODE: " + $code)
  }
}
# END_OVERRIDE_RUN_CHILD_DUMPLOGS_V1
