param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ResultSetPath
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ResultSetPath = (Resolve-Path -LiteralPath $ResultSetPath).Path

$Lib = Join-Path $RepoRoot "scripts\rie_lib_v1.ps1"
. $Lib

$rs = RIE-ParseJson $ResultSetPath
if([string]$rs["schema"] -ne "rie.result_set.v1"){ Die "BAD_RESULT_SET_SCHEMA" }

$bundleId = "rie_bundle_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$bundleRoot = Join-Path $RepoRoot ("proofs\bundles\" + $bundleId)
$dataRoot = Join-Path $bundleRoot "items"
Ensure-Dir $dataRoot

$items = New-Object System.Collections.Generic.List[hashtable]

foreach($r in @(@($rs["results"]))){
  $rank = [int]$r["rank"]
  $sourceId = [string]$r["source_id"]
  $hash = [string]$r["hash"]
  $original = [string]$r["path"]

  $safeSourceId = ($sourceId -replace '[<>:"/\\|?*]+','_')
  $rel = ("items\" + ("{0:D3}" -f $rank) + "_" + $safeSourceId + ".json")
  $dest = Join-Path $bundleRoot $rel
  Copy-Item -LiteralPath $original -Destination $dest -Force

  $row = [ordered]@{
    rank          = $rank
    source_id     = $sourceId
    hash          = $hash
    original_path = $original
    bundle_relpath= $rel
  }
  [void]$items.Add($row)
}

$manifest = [ordered]@{
  schema           = "rie.evidence_bundle_manifest.v1"
  bundle_id        = $bundleId
  generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  query            = [string]$rs["query"]
  item_count       = @(@($items.ToArray())).Count
  items            = @(@($items.ToArray()) | Sort-Object rank)
}

$manifestPath = Join-Path $bundleRoot "manifest.json"
Write-Utf8NoBomLf $manifestPath (To-CanonJson $manifest)

Write-Host ("RIE_BUNDLE_OK: " + $bundleRoot) -ForegroundColor Green
Write-Host ("MANIFEST_OK: " + $manifestPath) -ForegroundColor Green
Write-Host ("ITEM_COUNT=" + $manifest["item_count"]) -ForegroundColor Green