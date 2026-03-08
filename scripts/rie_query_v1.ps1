param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$QueryPath,
  [Parameter(Mandatory=$true)][string]$IndexPath,
  [Parameter(Mandatory=$true)][string]$AudiencePolicyPath,
  [Parameter(Mandatory=$true)][string]$SourcePolicyPath,
  [Parameter(Mandatory=$false)][string]$DomainProfilesPath,
  [Parameter(Mandatory=$false)][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\rie_source_governance_v1.ps1")

function RIE-QueryDie([string]$m){ throw $m }

function RIE-QueryTokenize([string]$Text){
  if([string]::IsNullOrWhiteSpace($Text)){ return @() }
  $t = $Text.ToLowerInvariant()
  $parts = [regex]::Split($t, '[^a-z0-9]+')
  $out = New-Object System.Collections.Generic.List[string]
  foreach($p in @(@($parts))){
    if(-not [string]::IsNullOrWhiteSpace($p)){ [void]$out.Add($p) }
  }
  return @($out.ToArray())
}

function RIE-QueryResolvePath([string]$RepoRoot,[string]$PathText){
  if([string]::IsNullOrWhiteSpace($PathText)){ RIE-QueryDie "PATH_EMPTY" }
  try {
    if([System.IO.Path]::IsPathRooted($PathText)){ return $PathText }
  } catch { }
  return (Join-Path $RepoRoot $PathText)
}

function RIE-QueryShouldIncludeDecision($AudiencePolicy,$Decision){
  $action = [string]$Decision["action"]
  $allowWarnings = $false
  $allowQuarantine = $false

  if(($AudiencePolicy -is [hashtable]) -or ($AudiencePolicy -is [System.Collections.IDictionary])){
    if($AudiencePolicy.ContainsKey("allow_warning_labeled_results")){ $allowWarnings = [bool]$AudiencePolicy["allow_warning_labeled_results"] }
    if($AudiencePolicy.ContainsKey("allow_quarantined_results")){ $allowQuarantine = [bool]$AudiencePolicy["allow_quarantined_results"] }
  }

  switch($action){
    "ALLOW_CHILD_SAFE" { return $true }
    "ALLOW_WITH_EDUCATOR_WARNING" { return $allowWarnings }
    "DOWNRANK" { return $allowWarnings }
    "QUARANTINE_REVIEW_ONLY" { return $allowQuarantine }
    default { return $false }
  }
}

function RIE-QueryBuildAdmissionDecisionSummary($Decision){
  return [ordered]@{
    decision_id = [string]$Decision["decision_id"]
    evaluation_id = [string]$Decision["evaluation_id"]
    action = [string]$Decision["action"]
    reason_code = [string]$Decision["reason_code"]
    warning_label = [string]$Decision["warning_label"]
    audience_band = [string]$Decision["audience_band"]
    policy_id = [string]$Decision["policy_id"]
  }
}

function RIE-QueryRunV1(
  [string]$RepoRoot,
  [string]$QueryPath,
  [string]$IndexPath,
  [string]$AudiencePolicyPath,
  [string]$SourcePolicyPath,
  [string]$DomainProfilesPath,
  [string]$OutPath
){
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

  if(-not (Test-Path -LiteralPath $QueryPath -PathType Leaf)){ RIE-QueryDie ("QUERY_MISSING: " + $QueryPath) }
  if(-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)){ RIE-QueryDie ("INDEX_MISSING: " + $IndexPath) }
  if(-not (Test-Path -LiteralPath $AudiencePolicyPath -PathType Leaf)){ RIE-QueryDie ("AUDIENCE_POLICY_MISSING: " + $AudiencePolicyPath) }
  if(-not (Test-Path -LiteralPath $SourcePolicyPath -PathType Leaf)){ RIE-QueryDie ("SOURCE_POLICY_MISSING: " + $SourcePolicyPath) }

  if([string]::IsNullOrWhiteSpace($OutPath)){
    $queriesDir = Join-Path $RepoRoot "proofs\queries"
    if(-not (Test-Path -LiteralPath $queriesDir -PathType Container)){
      New-Item -ItemType Directory -Force -Path $queriesDir | Out-Null
    }
    $OutPath = Join-Path $queriesDir "rie_result_set.v1.json"
  }

  $query = RIE-GovLoadJson $QueryPath
  $index = RIE-GovLoadJson $IndexPath
  $aud = RIE-GovLoadJson $AudiencePolicyPath
  $srcPol = RIE-GovLoadJson $SourcePolicyPath
  $domainMap = RIE-GovLoadDomainProfileMap $DomainProfilesPath

  $queryId = RIE-GovGetString $query "query_id"
  if([string]::IsNullOrWhiteSpace($queryId)){ $queryId = RIE-GovNewId "qry" }

  $tokens = New-Object System.Collections.Generic.List[string]
  if(RIE-GovHasKey $query "inputs"){
    foreach($inp in @(@($query["inputs"]))){
      if(($inp -is [hashtable]) -or ($inp -is [System.Collections.IDictionary])){
        $kind = RIE-GovGetString $inp "kind"
        if($kind -in @("keywords","formula_latex")){
          $text = RIE-GovGetString $inp "text"
          foreach($tk in @(@(RIE-QueryTokenize $text))){
            [void]$tokens.Add($tk)
          }
        }
      }
    }
  }

  $uniqueTokens = New-Object System.Collections.Generic.List[string]
  $seenToken = @{}
  foreach($tk in @(@($tokens.ToArray()))){
    if(-not $seenToken.ContainsKey($tk)){
      $seenToken[$tk] = $true
      [void]$uniqueTokens.Add($tk)
    }
  }

  $sourceMap = @{}
  foreach($srcMeta in @(@($index["sources"]))){
    if(($srcMeta -is [hashtable]) -or ($srcMeta -is [System.Collections.IDictionary])){
      $sid = RIE-GovGetString $srcMeta "source_id"
      if(-not [string]::IsNullOrWhiteSpace($sid)){ $sourceMap[$sid] = $srcMeta }
    }
  }

  $candidateHits = @{}
  if(RIE-GovHasKey $index "keywords"){
    $kwMap = $index["keywords"]
    if(($kwMap -is [hashtable]) -or ($kwMap -is [System.Collections.IDictionary])){
      foreach($tk in @(@($uniqueTokens.ToArray()))){
        if($kwMap.ContainsKey($tk)){
          foreach($sid in @(@($kwMap[$tk]))){
            $id = [string]$sid
            if([string]::IsNullOrWhiteSpace($id)){ continue }
            if(-not $candidateHits.ContainsKey($id)){ $candidateHits[$id] = 0 }
            $candidateHits[$id] = [int]$candidateHits[$id] + 1
          }
        }
      }
    }
  }

  $resultRows = New-Object System.Collections.Generic.List[object]

  foreach($sid in @(@($candidateHits.Keys | Sort-Object))){
    if(-not $sourceMap.ContainsKey($sid)){ continue }

    $srcMeta = $sourceMap[$sid]
    $srcPathText = RIE-GovGetString $srcMeta "path"
    if([string]::IsNullOrWhiteSpace($srcPathText)){ continue }

    $srcPath = RIE-QueryResolvePath $RepoRoot $srcPathText
    if(-not (Test-Path -LiteralPath $srcPath -PathType Leaf)){ continue }

    $source = RIE-GovLoadJson $srcPath
    $evaluation = RIE-EvaluateSourceV1 $source $aud $srcPol $domainMap
    $decision = RIE-DecideAdmissionV1 $source $aud $srcPol $evaluation
    [void](RIE-WriteGovernanceReceiptV1 $RepoRoot $decision $evaluation)

    if(-not (RIE-QueryShouldIncludeDecision $aud $decision)){ continue }

    $score = [double]$candidateHits[$sid]
    if(([string]$decision["action"]) -eq "DOWNRANK"){ $score = $score * 0.5 }

    $row = [ordered]@{
      _sort_score = $score
      _sort_source_id = [string]$sid
      source = $source
      segments = @()
      admission_decision = (RIE-QueryBuildAdmissionDecisionSummary $decision)
    }
    [void]$resultRows.Add($row)
  }

  $sorted = @(@($resultRows.ToArray()) | Sort-Object @{Expression="_sort_score";Descending=$true}, @{Expression="_sort_source_id";Descending=$false})

  $results = New-Object System.Collections.Generic.List[object]
  for($i=0; $i -lt $sorted.Count; $i++){
    $r = $sorted[$i]
    [void]$results.Add([ordered]@{
      rank = ($i + 1)
      score = [double]$r["_sort_score"]
      source = $r["source"]
      segments = @($r["segments"])
      admission_decision = $r["admission_decision"]
    })
  }

  $resultSet = [ordered]@{
    schema = "rie.result_set.v1"
    query_id = $queryId
    created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    results = @($results.ToArray())
  }

  RIE-GovWriteUtf8NoBomLf $OutPath (RIE-GovToJson $resultSet)

  return [ordered]@{
    ok = $true
    out_path = $OutPath
    result_count = @(@($results.ToArray())).Count
  }
}

$run = RIE-QueryRunV1 -RepoRoot $RepoRoot -QueryPath $QueryPath -IndexPath $IndexPath -AudiencePolicyPath $AudiencePolicyPath -SourcePolicyPath $SourcePolicyPath -DomainProfilesPath $DomainProfilesPath -OutPath $OutPath
Write-Host ("RIE_QUERY_OK: " + $run["out_path"]) -ForegroundColor Green
Write-Host ("RESULT_COUNT=" + [string]$run["result_count"]) -ForegroundColor Green
