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

  if($Value -is [string]){
    return (ConvertTo-Json -Compress -InputObject $Value)
  }

  if($Value -is [bool]){
    if($Value){ return "true" } else { return "false" }
  }

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

function Sha256HexUtf8([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $h = $sha.ComputeHash($bytes)
    $sb = New-Object System.Text.StringBuilder
    foreach($x in $h){ [void]$sb.AppendFormat("{0:x2}", $x) }
    return $sb.ToString()
  } finally {
    $sha.Dispose()
  }
}

function Get-KeywordTokens([hashtable]$Source){
  $bag = New-Object System.Collections.Generic.List[string]

  foreach($v in @(
    [string]$Source["source_id"],
    [string]$Source["content_kind"],
    [string]$Source["title"]
  )){
    if(-not [string]::IsNullOrWhiteSpace($v)){ [void]$bag.Add($v.ToLowerInvariant()) }
  }

  $prov = $Source["provenance"]
  if(($prov -is [hashtable]) -or ($prov -is [System.Collections.IDictionary])){
    foreach($v in @(
      [string]$prov["discovered_from"],
      [string]$prov["retrieved_at_utc"]
    )){
      if(-not [string]::IsNullOrWhiteSpace($v)){ [void]$bag.Add($v.ToLowerInvariant()) }
    }
  }

  $tags = $Source["tags"]
  if($tags -is [string]){
    [void]$bag.Add($tags.ToLowerInvariant())
  } elseif(($tags -is [System.Collections.IEnumerable]) -and -not ($tags -is [string])) {
    foreach($t in @(@($tags))){
      if(-not [string]::IsNullOrWhiteSpace([string]$t)){ [void]$bag.Add(([string]$t).ToLowerInvariant()) }
    }
  }

  $raw = ((@($bag.ToArray())) -join " ").ToLowerInvariant()
  $tokens = [regex]::Matches($raw,'[a-z0-9_:\.-]+') | ForEach-Object { $_.Value } | Where-Object { $_.Length -ge 2 }
  return @(@($tokens) | Sort-Object -Unique)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Lib = Join-Path $RepoRoot "scripts\rie_lib_v1.ps1"
$HashLib = Join-Path $RepoRoot "scripts\rie_hash_store_v1.ps1"
Parse-GateFile $Lib
Parse-GateFile $HashLib

. $Lib
. $HashLib

$OutDir = Join-Path $RepoRoot "proofs\index"
Ensure-Dir $OutDir

$candidates = New-Object System.Collections.Generic.List[string]

foreach($root in @(
  (Join-Path $RepoRoot "test_vectors"),
  (Join-Path $RepoRoot "store\by_hash")
)){
  if(Test-Path -LiteralPath $root -PathType Container){
    foreach($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.json)){
      [void]$candidates.Add($f.FullName)
    }
  }
}

$sourceRows = New-Object System.Collections.Generic.List[hashtable]
$kwMap = @{}

foreach($path in @(@($candidates.ToArray()) | Sort-Object -Unique)){
  try{
    $obj = RIE-ParseJson $path
    RIE-ValidateSourceRecordV1 $obj $path
  } catch {
    continue
  }

  $hash = RIE-HashFileUtf8NoBomLf $path
  $row = [ordered]@{
    source_id = [string]$obj["source_id"]
    path      = [string]$path
    hash      = [string]$hash
  }
  [void]$sourceRows.Add($row)

  foreach($kw in @(Get-KeywordTokens $obj)){
    if(-not $kwMap.ContainsKey($kw)){
      $kwMap[$kw] = New-Object System.Collections.Generic.List[string]
    }
    $sid = [string]$obj["source_id"]
    if((@(@($kwMap[$kw].ToArray())) -notcontains $sid)){
      [void]$kwMap[$kw].Add($sid)
    }
  }
}

$keywordsOut = @{}
foreach($k in @(@($kwMap.Keys) | Sort-Object)){
  $keywordsOut[$k] = @(@($kwMap[$k].ToArray()) | Sort-Object)
}

$indexObj = [ordered]@{
  schema          = "rie.keyword_index.v1"
  generated_at_utc= (Get-Date).ToUniversalTime().ToString("o")
  source_count    = @(@($sourceRows.ToArray())).Count
  keyword_count   = @(@($keywordsOut.Keys)).Count
  sources         = @(@($sourceRows.ToArray()) | Sort-Object source_id, path)
  keywords        = $keywordsOut
}

$canon = To-CanonJson $indexObj
$outPath = Join-Path $OutDir "rie.keyword_index.v1.json"
Write-Utf8NoBomLf $outPath $canon

Write-Host ("RIE_INDEX_OK: " + $outPath) -ForegroundColor Green
Write-Host ("SOURCE_COUNT=" + $indexObj["source_count"]) -ForegroundColor Green
Write-Host ("KEYWORD_COUNT=" + $indexObj["keyword_count"]) -ForegroundColor Green
