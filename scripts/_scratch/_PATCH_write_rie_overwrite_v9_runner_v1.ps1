param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "WRITE_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $msg = ($err | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Runner   = Join-Path $RepoRoot "scripts\_scratch\_RUN_rie_overwrite_v9.ps1"
EnsureDir (Split-Path -Parent $Runner)

$R = New-Object System.Collections.Generic.List[string]

# --- prologue
[void]$R.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$R.Add('')
[void]$R.Add('Set-StrictMode -Version Latest')
[void]$R.Add('$ErrorActionPreference = "Stop"')
[void]$R.Add('')
[void]$R.Add('function Die([string]$m){ throw $m }')
[void]$R.Add('function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }')
[void]$R.Add('function Write-Utf8NoBomLf([string]$Path,[string]$Text){')
[void]$R.Add('  if([string]::IsNullOrWhiteSpace($Path)){ Die "WRITE_PATH_EMPTY" }')
[void]$R.Add('  $dir = Split-Path -Parent $Path')
[void]$R.Add('  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }')
[void]$R.Add('  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")')
[void]$R.Add('  $enc = New-Object System.Text.UTF8Encoding($false)')
[void]$R.Add('  [System.IO.File]::WriteAllText($Path,$t,$enc)')
[void]$R.Add('}')
[void]$R.Add('function Parse-GateFile([string]$Path){')
[void]$R.Add('  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }')
[void]$R.Add('  $tok=$null; $err=$null')
[void]$R.Add('  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)')
[void]$R.Add('  if($err -and $err.Count -gt 0){ $msg = ($err | ForEach-Object { $_.ToString() }) -join "`n"; Die ("PARSEGATE_FAIL: " + $Path + "`n" + $msg) }')
[void]$R.Add('}')
[void]$R.Add('function Run-Child([string]$ScriptPath,[hashtable]$ArgMap,[string]$OutLog,[string]$ErrLog){')
[void]$R.Add('  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_MISSING: " + $ScriptPath) }')
[void]$R.Add('  $psExe = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source')
[void]$R.Add('  $args = New-Object System.Collections.Generic.List[string]')
[void]$R.Add('  [void]$args.Add("-NoProfile"); [void]$args.Add("-NonInteractive"); [void]$args.Add("-ExecutionPolicy"); [void]$args.Add("Bypass"); [void]$args.Add("-File"); [void]$args.Add($ScriptPath)')
[void]$R.Add('  foreach($k in @(@($ArgMap.Keys))){ [void]$args.Add("-" + [string]$k); $v=$ArgMap[$k]; if($null -eq $v){ $v="" }; [void]$args.Add([string]$v) }')
[void]$R.Add('  EnsureDir (Split-Path -Parent $OutLog); EnsureDir (Split-Path -Parent $ErrLog)')
[void]$R.Add('  $p = Start-Process -FilePath $psExe -ArgumentList $args.ToArray() -Wait -PassThru -NoNewWindow -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog')
[void]$R.Add('  if($p.ExitCode -ne 0){ Die ("CHILD_FAIL_EXITCODE: " + $p.ExitCode) }')
[void]$R.Add('}')
[void]$R.Add('')
[void]$R.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$R.Add('$Scripts = Join-Path $RepoRoot "scripts"')
[void]$R.Add('$Schemas = Join-Path $RepoRoot "schemas"')
[void]$R.Add('$TV      = Join-Path $RepoRoot "test_vectors"')
[void]$R.Add('$Proofs  = Join-Path $RepoRoot "proofs\receipts"')
[void]$R.Add('$Logs    = Join-Path $RepoRoot "proofs\logs"')
[void]$R.Add('EnsureDir $Scripts; EnsureDir $Schemas; EnsureDir $TV; EnsureDir $Proofs; EnsureDir $Logs')
[void]$R.Add('Write-Host "RIE_OVERWRITE_V9_START" -ForegroundColor Cyan')
[void]$R.Add('')

# --- schema source_record (HERE-STRING start/end are emitted explicitly and unambiguously)
[void]$R.Add('$schemaSourceRecord = ' + "@'")
[void]$R.Add('{')
[void]$R.Add('  "$schema": "https://json-schema.org/draft/2020-12/schema",')
[void]$R.Add('  "title": "RIE Source Record v1",')
[void]$R.Add('  "type": "object",')
[void]$R.Add('  "additionalProperties": false,')
[void]$R.Add('  "required": ["schema","source_id","content_kind","title","provenance"],')
[void]$R.Add('  "properties": {')
[void]$R.Add('    "schema": { "const": "rie.source_record.v1" },')
[void]$R.Add('    "source_id": { "type": "string", "minLength": 1 },')
[void]$R.Add('    "content_kind": { "type": "string", "minLength": 1 },')
[void]$R.Add('    "title": { "type": "string", "minLength": 1 },')
[void]$R.Add('    "provenance": {')
[void]$R.Add('      "type": "object",')
[void]$R.Add('      "additionalProperties": false,')
[void]$R.Add('      "required": ["discovered_from","retrieved_at_utc"],')
[void]$R.Add('      "properties": {')
[void]$R.Add('        "discovered_from": { "type": "string", "minLength": 1 },')
[void]$R.Add('        "retrieved_at_utc": { "type": "string", "minLength": 1 }')
[void]$R.Add('      }')
[void]$R.Add('    },')
[void]$R.Add('    "tags": { "type": "array", "items": { "type": "string" } }')
[void]$R.Add('  }')
[void]$R.Add('}')
[void]$R.Add("'@")
[void]$R.Add('Write-Utf8NoBomLf (Join-Path $Schemas "rie.source_record.v1.schema.json") ($schemaSourceRecord + "`n")')
[void]$R.Add('')

# --- schema result_set (minimal)
[void]$R.Add('$schemaResultSet = ' + "@'")
[void]$R.Add('{')
[void]$R.Add('  "$schema": "https://json-schema.org/draft/2020-12/schema",')
[void]$R.Add('  "title": "RIE Result Set v1",')
[void]$R.Add('  "type": "object",')
[void]$R.Add('  "additionalProperties": false,')
[void]$R.Add('  "required": ["schema","query_id","created_at_utc","results"],')
[void]$R.Add('  "properties": {')
[void]$R.Add('    "schema": { "const": "rie.result_set.v1" },')
[void]$R.Add('    "query_id": { "type": "string", "minLength": 1 },')
[void]$R.Add('    "created_at_utc": { "type": "string", "minLength": 1 },')
[void]$R.Add('    "results": { "type": "array", "minItems": 1, "items": { "type": "object" } }')
[void]$R.Add('  }')
[void]$R.Add('}')
[void]$R.Add("'@")
[void]$R.Add('Write-Utf8NoBomLf (Join-Path $Schemas "rie.result_set.v1.schema.json") ($schemaResultSet + "`n")')
[void]$R.Add('')

# --- lib
[void]$R.Add('$Lib  = Join-Path $Scripts "rie_lib_v1.ps1"')
[void]$R.Add('$libText = ' + "@'")
[void]$R.Add('Set-StrictMode -Version Latest')
[void]$R.Add('$ErrorActionPreference = "Stop"')
[void]$R.Add('function RIE-Die([string]$m){ throw $m }')
[void]$R.Add('function RIE-ReadUtf8NoBom([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }; $b=[System.IO.File]::ReadAllBytes($Path); $enc=New-Object System.Text.UTF8Encoding($false,$true); $enc.GetString($b) }')
[void]$R.Add('function RIE-ParseJson([string]$Path){ $raw = RIE-ReadUtf8NoBom $Path; try { $raw | ConvertFrom-Json -Depth 200 } catch { RIE-Die ("JSON_PARSE_FAIL: " + $Path) } }')
[void]$R.Add('function RIE-HasProp($o,[string]$name){ if($null -eq $o){ return $false }; @(@($o.PSObject.Properties.Name)) -contains $name }')
[void]$R.Add('function RIE-AssertHasProps($o,[string[]]$names,[string]$ctx){ foreach($n in @(@($names))){ if(-not (RIE-HasProp $o $n)){ RIE-Die ("MISSING_PROP: " + $ctx + " :: " + $n) } } }')
[void]$R.Add('function RIE-AssertNoProps($o,[string[]]$names,[string]$ctx){ foreach($n in @(@($names))){ if(RIE-HasProp $o $n){ RIE-Die ("FORBIDDEN_PROP: " + $ctx + " :: " + $n) } } }')
[void]$R.Add('function RIE-ValidateSourceRecordV1($o,[string]$ctx){ RIE-AssertNoProps $o @("answer","solution","steps","explanation") $ctx; RIE-AssertHasProps $o @("schema","source_id","content_kind","title","provenance") $ctx; if([string]$o.schema -ne "rie.source_record.v1"){ RIE-Die ("BAD_SCHEMA: " + $ctx) }; $p=$o.provenance; RIE-AssertHasProps $p @("discovered_from","retrieved_at_utc") ($ctx + ".provenance") }')
[void]$R.Add('function RIE-ValidateResultSetV1($o,[string]$ctx){ RIE-AssertHasProps $o @("schema","query_id","created_at_utc","results") $ctx; if([string]$o.schema -ne "rie.result_set.v1"){ RIE-Die ("BAD_SCHEMA: " + $ctx) }; foreach($r in @(@($o.results))){ if(-not (RIE-HasProp $r "source")){ RIE-Die ("MISSING_PROP: " + $ctx + ".results[] :: source") }; RIE-ValidateSourceRecordV1 $r.source ($ctx + ".results[].source") } }')
[void]$R.Add("'@")
[void]$R.Add('Write-Utf8NoBomLf $Lib ($libText + "`n")')
[void]$R.Add('')

# --- selftest
[void]$R.Add('$Self = Join-Path $Scripts "_selftest_rie_v1.ps1"')
[void]$R.Add('$selfText = ' + "@'")
[void]$R.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$R.Add('Set-StrictMode -Version Latest')
[void]$R.Add('$ErrorActionPreference = "Stop"')
[void]$R.Add('Write-Host "RIE_SELFTEST_V1_START" -ForegroundColor Cyan')
[void]$R.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$R.Add('. (Join-Path $RepoRoot "scripts\rie_lib_v1.ps1")')
[void]$R.Add('$tvDir = Join-Path $RepoRoot "test_vectors\minimal_valid"')
[void]$R.Add('if(-not (Test-Path -LiteralPath $tvDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $tvDir | Out-Null }')
[void]$R.Add('$enc = New-Object System.Text.UTF8Encoding($false)')
[void]$R.Add('$src = ' + "@'")
[void]$R.Add('{')
[void]$R.Add('  "schema": "rie.source_record.v1",')
[void]$R.Add('  "source_id": "s_vid_001",')
[void]$R.Add('  "content_kind": "video",')
[void]$R.Add('  "title": "Example Lecture",')
[void]$R.Add('  "provenance": { "discovered_from": "https://example.edu/course/page", "retrieved_at_utc": "2026-02-23T00:00:00Z" },')
[void]$R.Add('  "tags": ["demo"]')
[void]$R.Add('}')
[void]$R.Add("'@")
[void]$R.Add('$srcPath = Join-Path $tvDir "source_record.v1.json"')
[void]$R.Add('[System.IO.File]::WriteAllText($srcPath, ($src.Replace("`r`n","`n").Replace("`r","`n") + "`n"), $enc)')
[void]$R.Add('$o = RIE-ParseJson $srcPath')
[void]$R.Add('RIE-ValidateSourceRecordV1 $o "tv.source_record"')
[void]$R.Add('Write-Host "POS_SOURCE_RECORD_OK" -ForegroundColor Green')
[void]$R.Add('')
[void]$R.Add('$bad = ' + "@'")
[void]$R.Add('{')
[void]$R.Add('  "schema": "rie.source_record.v1",')
[void]$R.Add('  "source_id": "s_bad_001",')
[void]$R.Add('  "content_kind": "video",')
[void]$R.Add('  "title": "Bad Example",')
[void]$R.Add('  "provenance": { "discovered_from": "x", "retrieved_at_utc": "y" },')
[void]$R.Add('  "answer": "NOPE"')
[void]$R.Add('}')
[void]$R.Add("'@")
[void]$R.Add('$badPath = Join-Path $tvDir "source_record.forbidden_prop.json"')
[void]$R.Add('[System.IO.File]::WriteAllText($badPath, ($bad.Replace("`r`n","`n").Replace("`r","`n") + "`n"), $enc)')
[void]$R.Add('$b = RIE-ParseJson $badPath')
[void]$R.Add('try { RIE-ValidateSourceRecordV1 $b "tv.bad"; throw "NEG_EXPECTED_FAIL_BUT_PASSED" } catch {')
[void]$R.Add('  if($_.Exception.Message -notmatch "FORBIDDEN_PROP"){ throw }')
[void]$R.Add('  Write-Host ("NEG_FORBIDDEN_PROP_OK: " + $_.Exception.Message) -ForegroundColor Green')
[void]$R.Add('}')
[void]$R.Add('Write-Host "RIE_SELFTEST_V1_OK" -ForegroundColor Green')
[void]$R.Add("'@")
[void]$R.Add('Write-Utf8NoBomLf $Self ($selfText + "`n")')
[void]$R.Add('')

# gates + run
[void]$R.Add('Parse-GateFile $Lib')
[void]$R.Add('Parse-GateFile $Self')
[void]$R.Add('Write-Host ("LIB_PARSE_OK: " + $Lib) -ForegroundColor Green')
[void]$R.Add('Write-Host ("SELFTEST_PARSE_OK: " + $Self) -ForegroundColor Green')
[void]$R.Add('$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")')
[void]$R.Add('$outLog = Join-Path $Logs ("selftest_stdout_" + $ts + ".log")')
[void]$R.Add('$errLog = Join-Path $Logs ("selftest_stderr_" + $ts + ".log")')
[void]$R.Add('Run-Child $Self @{ RepoRoot = $RepoRoot } $outLog $errLog')
[void]$R.Add('if(-not (Test-Path -LiteralPath $outLog -PathType Leaf)){ Die ("MISSING_OUTLOG: " + $outLog) }')
[void]$R.Add('if(-not (Test-Path -LiteralPath $errLog -PathType Leaf)){ Die ("MISSING_ERRLOG: " + $errLog) }')
[void]$R.Add('Write-Host ("SELFTEST_CHILD_OK: " + $outLog) -ForegroundColor Green')
[void]$R.Add('Write-Host "RIE_OVERWRITE_V9_OK" -ForegroundColor Green')

$runnerText = (@($R.ToArray()) -join "`n") + "`n"
Write-Utf8NoBomLf $Runner $runnerText
Parse-GateFile $Runner

Write-Host ("WROTE_RUNNER_V9_OK: " + $Runner) -ForegroundColor Green
