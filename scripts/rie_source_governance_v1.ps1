Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function RIE-GovDie([string]$m){ throw $m }

function RIE-GovReadUtf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-GovDie ("FILE_MISSING: " + $Path) }
  $b = [System.IO.File]::ReadAllBytes($Path)
  $enc = New-Object System.Text.UTF8Encoding($false,$true)
  return $enc.GetString($b)
}

function RIE-GovWriteUtf8NoBomLf([string]$Path,[string]$Text){
  if([string]::IsNullOrWhiteSpace($Path)){ RIE-GovDie "WRITE_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function RIE-GovNewId([string]$Prefix){
  $utc = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
  $rand = [Guid]::NewGuid().ToString("N").Substring(0,12)
  return ($Prefix + "_" + $utc + "_" + $rand)
}

function RIE-GovToHashtableDeep($v){
  if($null -eq $v){ return $null }

  if(($v -is [hashtable]) -or ($v -is [System.Collections.IDictionary]) -or ($v -is [System.Collections.Specialized.OrderedDictionary])){
    $h = @{}
    foreach($k in @($v.Keys)){
      $h[[string]$k] = RIE-GovToHashtableDeep $v[$k]
    }
    return $h
  }

  if(($v -is [System.Collections.IEnumerable]) -and -not ($v -is [string])){
    $L = New-Object System.Collections.Generic.List[object]
    foreach($x in $v){
      [void]$L.Add((RIE-GovToHashtableDeep $x))
    }
    return $L.ToArray()
  }

  return $v
}

function RIE-GovLoadJson([string]$Path){
  $raw = RIE-GovReadUtf8NoBom $Path
  $raw = $raw.Replace("`r`n","`n").Replace("`r","`n")
  try{
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.RecursionLimit = 256
    $ser.MaxJsonLength = 2147483647
    $obj = $ser.DeserializeObject($raw)
    return (RIE-GovToHashtableDeep $obj)
  } catch {
    $m = $_.Exception.Message
    if([string]::IsNullOrWhiteSpace($m)){ $m = ($_ | Out-String) }
    $m = ($m -replace "(\r\n|\r|\n)"," | ")
    RIE-GovDie ("JSON_PARSE_FAIL: " + $Path + " :: " + $m)
  }
}

function RIE-GovToJson($Obj){
  return ($Obj | ConvertTo-Json -Depth 20 -Compress)
}

function RIE-GovHasKey($Obj,[string]$Key){
  if($null -eq $Obj){ return $false }
  if([string]::IsNullOrWhiteSpace($Key)){ return $false }

  if($Obj -is [hashtable]){ return $Obj.ContainsKey($Key) }
  if($Obj -is [System.Collections.Specialized.OrderedDictionary]){ return $Obj.Contains($Key) }
  if($Obj -is [System.Collections.IDictionary]){
    try { return $Obj.Contains($Key) } catch { }
    try { return $Obj.ContainsKey($Key) } catch { }
  }
  return $false
}

function RIE-GovGetString($Obj,[string]$Key){
  if($null -eq $Obj){ return "" }
  if(RIE-GovHasKey $Obj $Key){
    if($null -ne $Obj[$Key]){ return [string]$Obj[$Key] }
  }
  return ""
}

function RIE-GovGetBool($Obj,[string]$Key,[bool]$Default){
  if(-not (RIE-GovHasKey $Obj $Key)){ return $Default }
  $v = $Obj[$Key]
  if($v -is [bool]){ return [bool]$v }
  $s = [string]$v
  if($s -eq "true"){ return $true }
  if($s -eq "false"){ return $false }
  return $Default
}

function RIE-GovGetInt($Obj,[string]$Key,[int]$Default){
  if(-not (RIE-GovHasKey $Obj $Key)){ return $Default }
  try { return [int]$Obj[$Key] } catch { return $Default }
}

function RIE-GovCountTrustSignals($Source){
  if(-not (RIE-GovHasKey $Source "trust_signals")){ return 0 }
  $ts = $Source["trust_signals"]
  if($null -eq $ts){ return 0 }
  if(($ts -is [System.Collections.IEnumerable]) -and -not ($ts -is [string])){
    return @($ts).Count
  }
  return 0
}

function RIE-GovHasProvenance($Source){
  if(-not (RIE-GovHasKey $Source "provenance")){ return $false }
  $p = $Source["provenance"]
  if(-not (($p -is [hashtable]) -or ($p -is [System.Collections.IDictionary]))){ return $false }
  $d = RIE-GovGetString $p "discovered_from"
  $r = RIE-GovGetString $p "retrieved_at_utc"
  return ((-not [string]::IsNullOrWhiteSpace($d)) -and (-not [string]::IsNullOrWhiteSpace($r)))
}

function RIE-GovGetDomainFromSource($Source){
  if(-not (RIE-GovHasKey $Source "provenance")){ return "" }
  $p = $Source["provenance"]
  if(-not (($p -is [hashtable]) -or ($p -is [System.Collections.IDictionary]))){ return "" }

  $u = RIE-GovGetString $p "canonical_url"
  if([string]::IsNullOrWhiteSpace($u)){ $u = RIE-GovGetString $p "discovered_from" }
  if([string]::IsNullOrWhiteSpace($u)){ return "" }

  try{
    $uri = [Uri]$u
    return $uri.Host.ToLowerInvariant()
  } catch {
    return ""
  }
}

function RIE-GovContainsAnswerLikePattern($Source){
  foreach($k in @("answer","solution","steps","explanation")){
    if(RIE-GovHasKey $Source $k){ return $true }
  }
  return $false
}


function RIE-GovLoadDomainProfileMap([string]$DomainProfilesPath){
  if([string]::IsNullOrWhiteSpace($DomainProfilesPath)){ return @{} }
  if(-not (Test-Path -LiteralPath $DomainProfilesPath -PathType Leaf)){ return @{} }

  $doc = RIE-GovLoadJson $DomainProfilesPath
  $map = @{}

  if(RIE-GovHasKey $doc "profiles"){
    $profiles = $doc["profiles"]
    foreach($p in @($profiles)){
      if(($p -is [hashtable]) -or ($p -is [System.Collections.IDictionary])){
        $d = RIE-GovGetString $p "domain"
        if(-not [string]::IsNullOrWhiteSpace($d)){
          $map[$d.ToLowerInvariant()] = $p
        }
      }
    }
  }

  return $map
}

function RIE-GovFindDomainProfile([string]$Domain,$DomainProfiles){
  if([string]::IsNullOrWhiteSpace($Domain)){ return $null }
  if($null -eq $DomainProfiles){ return $null }

  if(RIE-GovHasKey $DomainProfiles "profiles"){
    $arr = $DomainProfiles["profiles"]
    foreach($p in @($arr)){
      if(($p -is [hashtable]) -or ($p -is [System.Collections.IDictionary])){
        $d = RIE-GovGetString $p "domain"
        if($d.ToLowerInvariant() -eq $Domain.ToLowerInvariant()){
          return $p
        }
      }
    }
  }
  return $null
}

function RIE-GovHasInstitutionalOrPublisherAnchor($Source,$DomainProfile){
  $domainClass = ""
  if($null -ne $DomainProfile){ $domainClass = RIE-GovGetString $DomainProfile "classification" }

  if($domainClass -in @("institution","publisher","government","museum_library_archive")){ return $true }

  if(RIE-GovHasKey $Source "publisher"){
    $pub = RIE-GovGetString $Source "publisher"
    if(-not [string]::IsNullOrWhiteSpace($pub)){ return $true }
  }

  $trustCount = RIE-GovCountTrustSignals $Source
  if($trustCount -gt 0){
    $signals = $Source["trust_signals"]
    foreach($sig in @($signals)){
      if(($sig -is [hashtable]) -or ($sig -is [System.Collections.IDictionary])){
        $kind = RIE-GovGetString $sig "kind"
        if($kind -in @("doi_registry_present","publisher_verified","institution_directory_match","lab_page_linked","syllabus_linked","government_science_source")){
          return $true
        }
      }
    }
  }

  return $false
}

function RIE-GovIsGovernmentScienceSource($Source,$DomainProfile){
  if($null -ne $DomainProfile){
    $domainClass = RIE-GovGetString $DomainProfile "classification"
    if($domainClass -eq "government"){ return $true }
  }

  if(RIE-GovHasKey $Source "trust_signals"){
    foreach($sig in @($Source["trust_signals"])){
      if(($sig -is [hashtable]) -or ($sig -is [System.Collections.IDictionary])){
        if((RIE-GovGetString $sig "kind") -eq "government_science_source"){ return $true }
      }
    }
  }

  return $false
}

function RIE-GovIsCommunitySource($Source,$DomainProfile){
  if($null -ne $DomainProfile){
    $domainClass = RIE-GovGetString $DomainProfile "classification"
    if($domainClass -eq "community_educator"){ return $true }

    if(RIE-GovHasKey $DomainProfile "policy_tags"){
      foreach($tag in @($DomainProfile["policy_tags"])){
        if([string]$tag -eq "community_source"){ return $true }
      }
    }
  }

  $domain = RIE-GovGetDomainFromSource $Source
  if($domain -like "*youtube.com"){ return $true }

  return $false
}



function RIE-EvaluateSourceV1(
  $Source,
  $AudiencePolicy,
  $SourcePolicy,
  $DomainProfileMap
){
  $domain = RIE-GovGetDomainFromSource $Source

  $profile = $null
  if($null -ne $DomainProfileMap){
    if(($DomainProfileMap -is [hashtable]) -and $DomainProfileMap.ContainsKey($domain)){
      $profile = $DomainProfileMap[$domain]
    } elseif(($DomainProfileMap -is [System.Collections.IDictionary])){
      try {
        if($DomainProfileMap.Contains($domain)){ $profile = $DomainProfileMap[$domain] }
      } catch {
      }
    }
  }

  $hasAnswer = RIE-GovContainsAnswerLikePattern $Source
  $hasProv   = RIE-GovHasProvenance $Source
  $isComm    = RIE-GovIsCommunitySource $Source $profile
  $isGov     = RIE-GovIsGovernmentScienceSource $Source $profile
  $hasAnchor = RIE-GovHasInstitutionalOrPublisherAnchor $Source $profile
  $trustCnt  = RIE-GovCountTrustSignals $Source

  $domainStatus = ""
  if($null -ne $profile){
    $domainStatus = RIE-GovGetString $profile "status"
  }

  return [ordered]@{
    evaluation_id = (RIE-GovNewId "gov_eval")
    source_id = (RIE-GovGetString $Source "source_id")
    domain = $domain
    domain_status = $domainStatus
    has_answer_like_patterns = $hasAnswer
    has_provenance = $hasProv
    is_community_source = $isComm
    is_government_science_source = $isGov
    has_institutional_anchor = $hasAnchor
    has_publisher_anchor = ((RIE-GovGetString $Source "publisher") -ne "")
    trust_signal_count = $trustCnt
    audience_policy_id = (RIE-GovGetString $AudiencePolicy "policy_id")
    source_policy_id = (RIE-GovGetString $SourcePolicy "policy_id")
  }
}


function RIE-DecideAdmissionV1(
  $Evaluation,
  $AudiencePolicy,
  $SourcePolicy
){
  $audienceBand = RIE-GovGetString $AudiencePolicy "audience_band"
  $sourceId = ""
  $domain = ""
  if(($Evaluation -is [hashtable]) -or ($Evaluation -is [System.Collections.IDictionary])){
    $sourceId = RIE-GovGetString $Evaluation "source_id"
    $domain   = RIE-GovGetString $Evaluation "domain"
  }

  $hasAnswer = $false
  $hasProv   = $false
  $isComm    = $false
  $isGov     = $false
  $hasAnchor = $false
  $trustCnt  = 0

  if(($Evaluation -is [hashtable]) -or ($Evaluation -is [System.Collections.IDictionary])){
    try { $hasAnswer = [bool]$Evaluation["has_answer_like_patterns"] } catch { }
    try { $hasProv   = [bool]$Evaluation["has_provenance"] } catch { }
    try { $isComm    = [bool]$Evaluation["is_community_source"] } catch { }
    try { $isGov     = [bool]$Evaluation["is_government_science_source"] } catch { }
    try { $hasAnchor = [bool]$Evaluation["has_institutional_anchor"] } catch { }
    try { $trustCnt  = [int]$Evaluation["trust_signal_count"] } catch { }
  }

  if((RIE-GovGetBool $AudiencePolicy "deny_for_answer_like_patterns" $true) -and $hasAnswer){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_FORBIDDEN_ANSWER_CONTENT"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  if((RIE-GovGetBool $AudiencePolicy "require_provenance" $true) -and (-not $hasProv)){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_MISSING_PROVENANCE"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  if($audienceBand -eq "child_7_10" -and $isGov){
    return [ordered]@{
      action = "ALLOW_CHILD_SAFE"
      reason_code = "ALLOW_CHILD_SAFE_GOV_SCIENCE"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  if($isComm){
    $allowCommunity = RIE-GovGetBool $AudiencePolicy "allow_community_sources" $false
    $allowWarning   = RIE-GovGetBool $AudiencePolicy "allow_warning_labeled_results" $false
    $allowQuar      = RIE-GovGetBool $AudiencePolicy "allow_quarantined_results" $false

    if(-not $allowCommunity){
      return [ordered]@{
        action = "QUARANTINE_REVIEW_ONLY"
        reason_code = "QUARANTINE_REQUIRES_REVIEW"
        warning_label = "community_source"
        audience_band = $audienceBand
        source_id = $sourceId
        domain = $domain
      }
    }

    if($allowWarning){
      return [ordered]@{
        action = "ALLOW_WITH_EDUCATOR_WARNING"
        reason_code = "ALLOW_COMMUNITY_WITH_WARNING"
        warning_label = "community_source"
        audience_band = $audienceBand
        source_id = $sourceId
        domain = $domain
      }
    }

    if($allowQuar){
      return [ordered]@{
        action = "QUARANTINE_REVIEW_ONLY"
        reason_code = "QUARANTINE_REQUIRES_REVIEW"
        warning_label = "community_source"
        audience_band = $audienceBand
        source_id = $sourceId
        domain = $domain
      }
    }

    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_POLICY_DEFAULT"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  $requireAnchor = RIE-GovGetBool $AudiencePolicy "require_institutional_or_publisher_anchor" $false
  if($requireAnchor -and (-not $hasAnchor)){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_MISSING_INSTITUTIONAL_OR_PUBLISHER_ANCHOR"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  $minTrust = RIE-GovGetInt $AudiencePolicy "min_trust_signal_count" 0
  if($trustCnt -lt $minTrust){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_TRUST_SIGNAL_THRESHOLD"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  return [ordered]@{
    action = "ALLOW"
    reason_code = "ALLOW_TRUSTED_SOURCE"
    warning_label = ""
    audience_band = $audienceBand
    source_id = $sourceId
    domain = $domain
  }
}

function RIE-GovGetDecision($Source,$AudiencePolicy,$SourcePolicy,$DomainProfiles){
  $audienceBand = RIE-GovGetString $AudiencePolicy "audience_band"
  $sourceId = RIE-GovGetString $Source "source_id"
  $domain = RIE-GovGetDomainFromSource $Source
  $profile = RIE-GovFindDomainProfile $domain $DomainProfiles

  if((RIE-GovGetBool $AudiencePolicy "deny_for_answer_like_patterns" $true) -and (RIE-GovContainsAnswerLikePattern $Source)){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_FORBIDDEN_ANSWER_CONTENT"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  if((RIE-GovGetBool $AudiencePolicy "require_provenance" $true) -and (-not (RIE-GovHasProvenance $Source))){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_MISSING_PROVENANCE"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  $isGovScience = RIE-GovIsGovernmentScienceSource $Source $profile
  if($audienceBand -eq "child_7_10" -and $isGovScience){
    return [ordered]@{
      action = "ALLOW_CHILD_SAFE"
      reason_code = "ALLOW_CHILD_SAFE_GOV_SCIENCE"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  $isCommunity = RIE-GovIsCommunitySource $Source $profile
  if($isCommunity){
    $allowCommunity = RIE-GovGetBool $AudiencePolicy "allow_community_sources" $false
    $allowWarning   = RIE-GovGetBool $AudiencePolicy "allow_warning_labeled_results" $false
    $allowQuar      = RIE-GovGetBool $AudiencePolicy "allow_quarantined_results" $false

    if(-not $allowCommunity){
      return [ordered]@{
        action = "QUARANTINE_REVIEW_ONLY"
        reason_code = "QUARANTINE_REQUIRES_REVIEW"
        warning_label = "community_source"
        audience_band = $audienceBand
        source_id = $sourceId
        domain = $domain
      }
    }

    if($allowWarning){
      return [ordered]@{
        action = "ALLOW_WITH_EDUCATOR_WARNING"
        reason_code = "ALLOW_COMMUNITY_WITH_WARNING"
        warning_label = "community_source"
        audience_band = $audienceBand
        source_id = $sourceId
        domain = $domain
      }
    }

    if($allowQuar){
      return [ordered]@{
        action = "QUARANTINE_REVIEW_ONLY"
        reason_code = "QUARANTINE_REQUIRES_REVIEW"
        warning_label = "community_source"
        audience_band = $audienceBand
        source_id = $sourceId
        domain = $domain
      }
    }

    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_POLICY_DEFAULT"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  $requireAnchor = RIE-GovGetBool $AudiencePolicy "require_institutional_or_publisher_anchor" $false
  if($requireAnchor -and (-not (RIE-GovHasInstitutionalOrPublisherAnchor $Source $profile))){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_MISSING_INSTITUTIONAL_OR_PUBLISHER_ANCHOR"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  $minTrust = RIE-GovGetInt $AudiencePolicy "min_trust_signal_count" 0
  if((RIE-GovCountTrustSignals $Source) -lt $minTrust){
    return [ordered]@{
      action = "DENY"
      reason_code = "DENY_TRUST_SIGNAL_THRESHOLD"
      warning_label = ""
      audience_band = $audienceBand
      source_id = $sourceId
      domain = $domain
    }
  }

  return [ordered]@{
    action = "ALLOW"
    reason_code = "ALLOW_TRUSTED_SOURCE"
    warning_label = ""
    audience_band = $audienceBand
    source_id = $sourceId
    domain = $domain
  }
}


function RIE-WriteGovernanceReceiptV1(
  [string]$RepoRoot,
  $Evaluation,
  $Admission,
  $AudiencePolicy,
  $SourcePolicy,
  [string]$OutDir
){
  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-GovDie "REPO_ROOT_EMPTY" }
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

  if([string]::IsNullOrWhiteSpace($OutDir)){
    $OutDir = Join-Path $RepoRoot "proofs\receipts"
  }
  if(-not (Test-Path -LiteralPath $OutDir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  }

  $evaluationId = ""
  if(($Evaluation -is [hashtable]) -or ($Evaluation -is [System.Collections.IDictionary])){
    $evaluationId = RIE-GovGetString $Evaluation "evaluation_id"
  }
  if([string]::IsNullOrWhiteSpace($evaluationId)){
    $evaluationId = RIE-GovNewId "gov_eval"
  }

  $receipt = [ordered]@{
    schema = "rie.source_governance.v1"
    evaluation_id = $evaluationId
    utc = (Get-Date).ToUniversalTime().ToString("o")
    source_id = (RIE-GovGetString $Evaluation "source_id")
    domain = (RIE-GovGetString $Evaluation "domain")
    audience_band = (RIE-GovGetString $Admission "audience_band")
    action = (RIE-GovGetString $Admission "action")
    reason_code = (RIE-GovGetString $Admission "reason_code")
    warning_label = (RIE-GovGetString $Admission "warning_label")
    audience_policy_id = (RIE-GovGetString $AudiencePolicy "policy_id")
    source_policy_id = (RIE-GovGetString $SourcePolicy "policy_id")
  }

  $line = RIE-GovToJson $receipt

  $ledger = Join-Path $RepoRoot "proofs\receipts\rie.source_governance.v1.ndjson"
  $existing = ""
  if(Test-Path -LiteralPath $ledger -PathType Leaf){
    $existing = RIE-GovReadUtf8NoBom $ledger
    $existing = $existing.Replace("
","
").Replace("
","
")
  }
  RIE-GovWriteUtf8NoBomLf $ledger (($existing.TrimEnd() + "
" + $line).Trim() + "
")

  $receiptPath = Join-Path $OutDir ($evaluationId + ".json")
  RIE-GovWriteUtf8NoBomLf $receiptPath ($line + "
")

  return [pscustomobject]@{
    ok = $true
    evaluation_id = $evaluationId
    receipt_path = $receiptPath
    ledger_path = $ledger
    action = (RIE-GovGetString $Admission "action")
    reason_code = (RIE-GovGetString $Admission "reason_code")
  }
}

function RIE-RunSourceGovernanceV1(
  [string]$RepoRoot,
  [string]$SourcePath,
  [string]$AudiencePolicyPath,
  [string]$SourcePolicyPath,
  [string]$DomainProfilesPath,
  [string]$OutDir
){
  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-GovDie "REPO_ROOT_EMPTY" }
  if([string]::IsNullOrWhiteSpace($SourcePath)){ RIE-GovDie "SOURCE_PATH_EMPTY" }
  if([string]::IsNullOrWhiteSpace($AudiencePolicyPath)){ RIE-GovDie "AUDIENCE_POLICY_PATH_EMPTY" }
  if([string]::IsNullOrWhiteSpace($SourcePolicyPath)){ RIE-GovDie "SOURCE_POLICY_PATH_EMPTY" }

  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)){ RIE-GovDie ("FILE_MISSING: " + $SourcePath) }
  if(-not (Test-Path -LiteralPath $AudiencePolicyPath -PathType Leaf)){ RIE-GovDie ("FILE_MISSING: " + $AudiencePolicyPath) }
  if(-not (Test-Path -LiteralPath $SourcePolicyPath -PathType Leaf)){ RIE-GovDie ("FILE_MISSING: " + $SourcePolicyPath) }

  $Source = RIE-GovLoadJson $SourcePath
  $AudiencePolicy = RIE-GovLoadJson $AudiencePolicyPath
  $SourcePolicy = RIE-GovLoadJson $SourcePolicyPath
  $DomainProfiles = $null
  if(-not [string]::IsNullOrWhiteSpace($DomainProfilesPath)){
    if(Test-Path -LiteralPath $DomainProfilesPath -PathType Leaf){
      $DomainProfiles = RIE-GovLoadJson $DomainProfilesPath
    }
  }

  $decision = RIE-GovGetDecision $Source $AudiencePolicy $SourcePolicy $DomainProfiles
  $evaluationId = RIE-GovNewId "gov_eval"
  $utc = (Get-Date).ToUniversalTime().ToString("o")

  $receipt = [ordered]@{
    schema = "rie.source_governance.v1"
    evaluation_id = $evaluationId
    utc = $utc
    source_id = [string]$decision.source_id
    audience_band = [string]$decision.audience_band
    action = [string]$decision.action
    reason_code = [string]$decision.reason_code
    warning_label = [string]$decision.warning_label
    domain = [string]$decision.domain
    audience_policy_id = (RIE-GovGetString $AudiencePolicy "policy_id")
    source_policy_id = (RIE-GovGetString $SourcePolicy "policy_id")
    source_path = $SourcePath
    audience_policy_path = $AudiencePolicyPath
    source_policy_path = $SourcePolicyPath
  }

  $receiptsRoot = Join-Path $RepoRoot "proofs\receipts"
  if(-not (Test-Path -LiteralPath $receiptsRoot -PathType Container)){
    New-Item -ItemType Directory -Force -Path $receiptsRoot | Out-Null
  }

  $receiptLedger = Join-Path $receiptsRoot "rie.source_governance.v1.ndjson"
  $line = (RIE-GovToJson $receipt)
  $existing = ""
  if(Test-Path -LiteralPath $receiptLedger -PathType Leaf){
    $existing = RIE-GovReadUtf8NoBom $receiptLedger
    $existing = $existing.Replace("`r`n","`n").Replace("`r","`n")
  }
  RIE-GovWriteUtf8NoBomLf $receiptLedger (($existing.TrimEnd() + "`n" + $line).Trim() + "`n")

  $receiptPath = ""
  if(-not [string]::IsNullOrWhiteSpace($OutDir)){
    if(-not (Test-Path -LiteralPath $OutDir -PathType Container)){
      New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    }
    $receiptPath = Join-Path $OutDir ($evaluationId + ".json")
    RIE-GovWriteUtf8NoBomLf $receiptPath ($line + "`n")
  }

  return [pscustomobject]@{
    ok = $true
    evaluation_id = $evaluationId
    action = [string]$decision.action
    reason_code = [string]$decision.reason_code
    warning_label = [string]$decision.warning_label
    source_id = [string]$decision.source_id
    audience_band = [string]$decision.audience_band
    domain = [string]$decision.domain
    audience_policy_id = (RIE-GovGetString $AudiencePolicy "policy_id")
    source_policy_id = (RIE-GovGetString $SourcePolicy "policy_id")
    receipt_path = $receiptPath
    ledger_path = $receiptLedger
  }
}
