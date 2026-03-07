param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }
function Ensure-Dir([string]$p){
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
function Run-Child([string]$ScriptPath,[hashtable]$ArgMap,[string]$OutLog,[string]$ErrLog){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("CHILD_MISSING: " + $ScriptPath) }
  $psExe = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
  $args = New-Object System.Collections.Generic.List[string]
  [void]$args.Add("-NoProfile"); [void]$args.Add("-NonInteractive"); [void]$args.Add("-ExecutionPolicy"); [void]$args.Add("Bypass")
  [void]$args.Add("-File"); [void]$args.Add($ScriptPath)
  foreach($k in @(@($ArgMap.Keys))){
    [void]$args.Add("-" + [string]$k)
    $v = $ArgMap[$k]; if($null -eq $v){ $v = "" }
    [void]$args.Add([string]$v)
  }
  Ensure-Dir (Split-Path -Parent $OutLog)
  Ensure-Dir (Split-Path -Parent $ErrLog)
  $p = Start-Process -FilePath $psExe -ArgumentList $args.ToArray() -Wait -PassThru -NoNewWindow -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
  if($p.ExitCode -ne 0){ Die ("CHILD_FAIL_EXITCODE: " + $p.ExitCode) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"
$Schemas = Join-Path $RepoRoot "schemas"
$TV      = Join-Path $RepoRoot "test_vectors"
$Proofs  = Join-Path $RepoRoot "proofs\receipts"
$Logs    = Join-Path $RepoRoot "proofs\logs"
Ensure-Dir $Scripts; Ensure-Dir $Schemas; Ensure-Dir $TV; Ensure-Dir $Proofs; Ensure-Dir $Logs

Write-Host "RIE_OVERWRITE_V7_START" -ForegroundColor Cyan

$schemaSourceRecord = @(
'{'
'  "$schema": "https://json-schema.org/draft/2020-12/schema",'
'  "title": "RIE Source Record v1",'
'  "type": "object",'
'  "additionalProperties": false,'
'  "required": ["schema","source_id","content_kind","title","provenance"],'
'  "properties": {'
'    "schema": { "const": "rie.source_record.v1" },'
'    "source_id": { "type": "string", "minLength": 1 },'
'    "content_kind": { "type": "string", "minLength": 1 },'
'    "title": { "type": "string", "minLength": 1 },'
'    "provenance": {'
'      "type": "object",'
'      "additionalProperties": false,'
'      "required": ["discovered_from","retrieved_at_utc"],'
'      "properties": {'
'        "discovered_from": { "type": "string", "minLength": 1 },'
'        "retrieved_at_utc": { "type": "string", "minLength": 1 }'
'      }'
'    },'
'    "tags": { "type": "array", "items": { "type": "string" } }'
'  }'
'}'
) -join "`n"
Write-Utf8NoBomLf (Join-Path $Schemas "rie.source_record.v1.schema.json") ($schemaSourceRecord + "`n")

$schemaBundle = @(
'{'
'  "$schema": "https://json-schema.org/draft/2020-12/schema",'
'  "title": "RIE Evidence Bundle Manifest v1",'
'  "type": "object",'
'  "additionalProperties": false,'
'  "required": ["schema","bundle_id","items","meta"],'
'  "properties": {'
'    "schema": { "const": "rie.evidence_bundle_manifest.v1" },'
'    "bundle_id": { "type": "string", "minLength": 1 },'
'    "items": {'
'      "type": "array",'
'      "minItems": 1,'
'      "items": {'
'        "type": "object",'
'        "additionalProperties": false,'
'        "required": ["source_id"],'
'        "properties": { "source_id": { "type": "string", "minLength": 1 } }'
'      }'
'    },'
'    "meta": {'
'      "type": "object",'
'      "additionalProperties": false,'
'      "required": ["generated_by","generated_at_utc"],'
'      "properties": {'
'        "generated_by": { "type": "string", "minLength": 1 },'
'        "generated_at_utc": { "type": "string", "minLength": 1 }'
'      }'
'    }'
'  }'
'}'
) -join "`n"
Write-Utf8NoBomLf (Join-Path $Schemas "rie.evidence_bundle_manifest.v1.schema.json") ($schemaBundle + "`n")

$schemaResultSet = @(
'{'
'  "$schema": "https://json-schema.org/draft/2020-12/schema",'
'  "title": "RIE Result Set v1",'
'  "type": "object",'
'  "additionalProperties": false,'
'  "required": ["schema","query_id","created_at_utc","results"],'
'  "properties": {'
'    "schema": { "const": "rie.result_set.v1" },'
'    "query_id": { "type": "string", "minLength": 1 },'
'    "created_at_utc": { "type": "string", "minLength": 1 },'
'    "results": {'
'      "type": "array",'
'      "minItems": 1,'
'      "items": {'
'        "type": "object",'
'        "additionalProperties": false,'
'        "required": ["rank","source","segments"],'
'        "properties": {'
'          "rank": { "type": "integer", "minimum": 1 },'
'          "source": { "type": "object" },'
'          "segments": { "type": "array", "items": { "type": "object" } }'
'        }'
'      }'
'    }'
'  }'
'}'
) -join "`n"
Write-Utf8NoBomLf (Join-Path $Schemas "rie.result_set.v1.schema.json") ($schemaResultSet + "`n")

$Lib  = Join-Path $Scripts "rie_lib_v1.ps1"
$Self = Join-Path $Scripts "_selftest_rie_v1.ps1"

$libText = @(
'Set-StrictMode -Version Latest'
'$ErrorActionPreference = "Stop"'
''
'function RIE-Die([string]$m){ throw $m }'
''
'function RIE-ReadUtf8NoBom([string]$Path){'
'  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }'
'  $b=[System.IO.File]::ReadAllBytes($Path)'
'  $enc=New-Object System.Text.UTF8Encoding($false,$true)'
'  $enc.GetString($b)'
'}'
''
'function RIE-ParseJson([string]$Path){'
'  $raw = RIE-ReadUtf8NoBom $Path'
'  try { $raw | ConvertFrom-Json -Depth 200 } catch { RIE-Die ("JSON_PARSE_FAIL: " + $Path) }'
'}'
''
'function RIE-HasProp($o,[string]$name){'
'  if($null -eq $o){ return $false }'
'  @(@($o.PSObject.Properties.Name)) -contains $name'
'}'
''
'function RIE-AssertHasProps($o,[string[]]$names,[string]$ctx){'
'  foreach($n in @(@($names))){ if(-not (RIE-HasProp $o $n)){ RIE-Die ("MISSING_PROP: " + $ctx + " :: " + $n) } }'
'}'
''
'function RIE-AssertNoProps($o,[string[]]$names,[string]$ctx){'
'  foreach($n in @(@($names))){ if(RIE-HasProp $o $n){ RIE-Die ("FORBIDDEN_PROP: " + $ctx + " :: " + $n) } }'
'}'
''
'function RIE-ValidateSourceRecordV1($o,[string]$ctx){'
'  RIE-AssertNoProps $o @("answer","solution","steps","explanation") $ctx'
'  RIE-AssertHasProps $o @("schema","source_id","content_kind","title","provenance") $ctx'
'  if([string]$o.schema -ne "rie.source_record.v1"){ RIE-Die ("BAD_SCHEMA: " + $ctx) }'
'  $p = $o.provenance'
'  RIE-AssertHasProps $p @("discovered_from","retrieved_at_utc") ($ctx + ".provenance")'
'}'
''
'function RIE-ValidateResultSetV1($o,[string]$ctx){'
'  RIE-AssertHasProps $o @("schema","query_id","created_at_utc","results") $ctx'
'  if([string]$o.schema -ne "rie.result_set.v1"){ RIE-Die ("BAD_SCHEMA: " + $ctx) }'
'  foreach($r in @(@($o.results))){'
'    RIE-AssertHasProps $r @("rank","source","segments") ($ctx + ".results[]")'
'    RIE-ValidateSourceRecordV1 $r.source ($ctx + ".results[].source")'
'  }'
'}'
) -join "`n"
Write-Utf8NoBomLf $Lib ($libText + "`n")

$selfText = @(
'param([Parameter(Mandatory=$true)][string]$RepoRoot)'
''
'Set-StrictMode -Version Latest'
'$ErrorActionPreference = "Stop"'
''
'Write-Host "RIE_SELFTEST_V1_START" -ForegroundColor Cyan'
'$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path'
''
'. (Join-Path $RepoRoot "scripts\rie_lib_v1.ps1")'
''
'$tvDir = Join-Path $RepoRoot "test_vectors\minimal_valid"'
'if(-not (Test-Path -LiteralPath $tvDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $tvDir | Out-Null }'
'$enc = New-Object System.Text.UTF8Encoding($false)'
''
'$srcLines = @(
'  "{",'
'  "  ""schema"": ""rie.source_record.v1"",",'
'  "  ""source_id"": ""s_vid_001"",",'
'  "  ""content_kind"": ""video"",",'
'  "  ""title"": ""Example Lecture"",",'
'  "  ""provenance"": { ""discovered_from"": ""https://example.edu/course/page"", ""retrieved_at_utc"": ""2026-02-23T00:00:00Z"" },",'
'  "  ""tags"": [""demo""]",'
'  "}"'
')'
'$src = ($srcLines -join "`n")'
'$srcPath = Join-Path $tvDir "source_record.v1.json"'
'[System.IO.File]::WriteAllText($srcPath, ($src.Replace("`r`n","`n").Replace("`r","`n") + "`n"), $enc)'
'$o = RIE-ParseJson $srcPath'
'RIE-ValidateSourceRecordV1 $o "tv.source_record"'
'Write-Host "POS_SOURCE_RECORD_OK" -ForegroundColor Green'
''
'$badLines = @(
'  "{",'
'  "  ""schema"": ""rie.source_record.v1"",",'
'  "  ""source_id"": ""s_bad_001"",",'
'  "  ""content_kind"": ""video"",",'
'  "  ""title"": ""Bad Example"",",'
'  "  ""provenance"": { ""discovered_from"": ""x"", ""retrieved_at_utc"": ""y"" },",'
'  "  ""answer"": ""NOPE""",'
'  "}"'
')'
'$bad = ($badLines -join "`n")'
'$badPath = Join-Path $tvDir "source_record.forbidden_prop.json"'
'[System.IO.File]::WriteAllText($badPath, ($bad.Replace("`r`n","`n").Replace("`r","`n") + "`n"), $enc)'
'$b = RIE-ParseJson $badPath'
'try { RIE-ValidateSourceRecordV1 $b "tv.bad"; throw "NEG_EXPECTED_FAIL_BUT_PASSED" } catch {'
'  if($_.Exception.Message -notmatch "FORBIDDEN_PROP"){ throw }'
'  Write-Host ("NEG_FORBIDDEN_PROP_OK: " + $_.Exception.Message) -ForegroundColor Green'
'}'
''
'Write-Host "RIE_SELFTEST_V1_OK" -ForegroundColor Green'
) -join "`n"
Write-Utf8NoBomLf $Self ($selfText + "`n")

Parse-GateFile $Lib
Parse-GateFile $Self
Write-Host ("LIB_PARSE_OK: " + $Lib) -ForegroundColor Green
Write-Host ("SELFTEST_PARSE_OK: " + $Self) -ForegroundColor Green

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$outLog = Join-Path $Logs ("selftest_stdout_" + $ts + ".log")
$errLog = Join-Path $Logs ("selftest_stderr_" + $ts + ".log")
Run-Child $Self @{ RepoRoot = $RepoRoot } $outLog $errLog
if(-not (Test-Path -LiteralPath $outLog -PathType Leaf)){ Die ("MISSING_OUTLOG: " + $outLog) }
if(-not (Test-Path -LiteralPath $errLog -PathType Leaf)){ Die ("MISSING_ERRLOG: " + $errLog) }
Write-Host ("SELFTEST_CHILD_OK: " + $outLog) -ForegroundColor Green

Write-Host "RIE_OVERWRITE_V7_OK" -ForegroundColor Green
