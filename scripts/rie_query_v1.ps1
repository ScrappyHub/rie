param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Query
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

function To-CanonJson($Value){
  if($null -eq $Value){ return "null" }
  if($Value -is [string]){ return (ConvertTo-Json -Compress -InputObject $Value) }
  if($Value -is [bool]){ if($Value){ return "true" } else { return "false" } }
  if(
    $Value -is [byte] -or
    $Value -is [int16] -or
    $Value -is [int32] -or
    $Value -is [int64] -or
    $Value -is [uint16] -or
    $Value -is [uint32] -or
    $Value -is [uint64] -or
    $Value -is [decimal] -or
    $Value -is [double] -or
    $Value -is [single]
  ){
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $Value))
  }
  if(($Value -is [System.Collections.IDictionary]) -or ($Value -is [hashtable])){
    $keys = @(@($Value.Keys) | ForEach-Object { [string]$_ } | Sort-Object)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($k in $keys){
      [void]$parts.Add((ConvertTo-Json -Compress -InputObject $k) + ":" + (To-CanonJson $Value[$k]))
    }
    return "{" + ((@($parts.ToArray())) -join ",") + "}"
  }
  if(($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])){
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($item in $Value){
      [void]$parts.Add((To-CanonJson $item))
    }
    return "[" + ((@($parts.ToArray())) -join ",") + "]"
  }
  if($Value -is [psobject] -and $Value.PSObject -and $Value.PSObject.Properties){
    $h = @{}
    foreach($p in @(@($Value.PSObject.Properties))){
      $h[[string]$p.Name] = $p.Value
    }
    return (To-CanonJson $h)
  }
  return (ConvertTo-Json -Compress -InputObject ([string]$Value))
}

function Get-QueryTokens([string]$Text){
  $tokens = [regex]::Matches($Text.ToLowerInvariant(),'[a-z0-9_:\.-]+') | ForEach-Object { $_.Value } | Where-Object { $_.Length -ge 2 }
  return @(@($tokens) | Sort-Object -Unique)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Lib = Join-Path $RepoRoot "scripts\rie_lib_v1.ps1"
$IndexScript = Join-Path $RepoRoot "scripts\rie_index_sources_v1.ps1"
Parse-GateFile $Lib
Parse-GateFile $IndexScript
. $Lib

$IndexPath = Join-Path $RepoRoot "proofs\index\rie.keyword_index.v1.json"
if(-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)){
  & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $IndexScript -RepoRoot $RepoRoot | Out-Null
}

$index = RIE-ParseJson $IndexPath
if([string]$index["schema"] -ne "rie.keyword_index.v1"){ Die "BAD_INDEX_SCHEMA" }

$sourceMap = @{}
foreach($row in @(@($index["sources"]))){
  $sourceMap[[string]$row["source_id"]] = $row
}

$scores = @{}
foreach($tok in @(Get-QueryTokens $Query)){
  if($index["keywords"].ContainsKey($tok)){
    foreach($sid in @(@($index["keywords"][$tok]))){
      if(-not $scores.ContainsKey([string]$sid)){ $scores[[string]$sid] = 0 }
      $scores[[string]$sid] = [int]$scores[[string]$sid] + 1
    }
  }
}

$results = New-Object System.Collections.Generic.List[hashtable]
$rank = 0

$orderedIds = @(
  @(@($scores.GetEnumerator())) |
    Sort-Object @{Expression={$_.Value};Descending=$true}, @{Expression={$_.Key};Descending=$false} |
    ForEach-Object { [string]$_.Key }
)

foreach($sid in @($orderedIds)){
  $rank = $rank + 1
  $meta = $sourceMap[$sid]
  $path = [string]$meta["path"]
  $src = RIE-ParseJson $path
  RIE-ValidateSourceRecordV1 $src ("result:" + $sid)

  $row = [ordered]@{
    rank      = $rank
    source_id = $sid
    score     = [int]$scores[$sid]
    hash      = [string]$meta["hash"]
    path      = $path
    source    = $src
  }
  [void]$results.Add($row)
}

$outObj = [ordered]@{
  schema         = "rie.result_set.v1"
  query          = $Query
  created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  result_count   = @(@($results.ToArray())).Count
  results        = @(@($results.ToArray()))
}

$outDir = Join-Path $RepoRoot "proofs\queries"
Ensure-Dir $outDir

$safeQuery = (([regex]::Matches($Query.ToLowerInvariant(),'[a-z0-9]+') | ForEach-Object { $_.Value }) -join "_")
if([string]::IsNullOrWhiteSpace($safeQuery)){ $safeQuery = "query" }

$outPath = Join-Path $outDir ("rie_result_set_" + $safeQuery + ".json")
Write-Utf8NoBomLf $outPath (To-CanonJson $outObj)

Write-Host ("RIE_QUERY_OK: " + $outPath) -ForegroundColor Green
Write-Host ("RESULT_COUNT=" + $outObj["result_count"]) -ForegroundColor Green
