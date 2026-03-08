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

function RIE-GovLoadJson([string]$Path){
  $raw = RIE-GovReadUtf8NoBom $Path
  $raw = $raw.Replace("`r`n","`n").Replace("`r","`n")
  try{
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.RecursionLimit = 256
    $ser.MaxJsonLength = 2147483647
    return $ser.DeserializeObject($raw)
  } catch {
    RIE-GovDie ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message)
  }
}

function RIE-GovToJson($Obj){
  return ($Obj | ConvertTo-Json -Depth 20 -Compress)
}

function RIE-GovGetString($Obj,[string]$Key){
  if($null -eq $Obj){ return "" }
  if(($Obj -is [hashtable]) -or ($Obj -is [System.Collections.IDictionary])){
    if($Obj.ContainsKey($Key) -and $null -ne $Obj[$Key]){ return [string]$Obj[$Key] }
  }
  return ""
}

function RIE-GovHasKey($Obj,[string]$Key){
  if($null -eq $Obj){ return $false }
  if(($Obj -is [hashtable]) -or ($Obj -is [System.Collections.IDictionary])){
    return $Obj.ContainsKey($Key)
  }
  return $false
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

function RIE-GovHasInstitutionalOrPublisherAnchor($Source,[hashtable]$DomainProfile){
  $domainClass = ""
  if($DomainProfile -ne $null){ $domainClass = RIE-GovGetString $DomainProfile "classification" }

  if($domainClass -in @("institution","publisher","government","museum_library_archive")){ return $true }

  if(RIE-GovHasKey $Source "publisher"){
    $pub = RIE-GovGetString $Source "publisher"
    if(-not [string]::IsNullOrWhiteSpace($pub)){ return $true }
  }

  $trustCount = RIE-GovCountTrustSignals $Source
  if($trustCount -gt 0){
    foreach($sig in @($Source["trust_signals"])){
      if(($sig -is [hashtable]) -or ($sig -is [System.Collections.IDictionary])){
        $kind = RIE-GovGetString $sig "kind"
        if($kind -in @("domain_verified","doi_registry_present","publisher_verified","institution_directory_match","lab_page_linked","government_science_source","syllabus_linked")){
          return $true
        }
      }
    }
  }

  return $false
}

function RIE-GovLoadDomainProfileMap([string]$Path){
  $map = @{}
  if([string]::IsNullOrWhiteSpace($Path)){ return $map }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $map }

  $obj = RIE-GovLoadJson $Path
  if(($obj -is [hashtable]) -or ($obj -is [System.Collections.IDictionary])){
    if(RIE-GovHasKey $obj "domain"){
      $d = (RIE-GovGetString $obj "domain").ToLowerInvariant()
      if(-not [string]::IsNullOrWhiteSpace($d)){ $map[$d] = $obj }
      return $map
    }
    if(RIE-GovHasKey $obj "profiles"){
      foreach($p in @($obj["profiles"])){
        if(($p -is [hashtable]) -or ($p -is [System.Collections.IDictionary])){
          $d2 = (RIE-GovGetString $p "domain").ToLowerInvariant()
          if(-not [string]::IsNullOrWhiteSpace($d2)){ $map[$d2] = $p }
        }
      }
    }
  }
  return $map
}

function RIE-GovIsListed([string]$Domain,$List){
  if([string]::IsNullOrWhiteSpace($Domain)){ return $false }
  if($null -eq $List){ return $false }
  foreach($x in @($List)){
    $v = [string]$x
    if([string]::IsNullOrWhiteSpace($v)){ continue }
    $v = $v.ToLowerInvariant()
    if($Domain -eq $v){ return $true }
    if($Domain.EndsWith("." + $v)){ return $true }
  }
  return $false
}

function RIE-GovNewCheck([string]$Id,[string]$Kind,[string]$Status,[string]$Detail,[string]$Reason){
  return [ordered]@{
    check_id = $Id
    kind = $Kind
    status = $Status
    detail = $Detail
    reason_code = $Reason
  }
}

function RIE-EvaluateSourceV1(
  $Source,
  $AudiencePolicy,
  $SourcePolicy,
  [hashtable]$DomainProfileMap
){
  if($null -eq $Source){ RIE-GovDie "SOURCE_NULL" }
  if($null -eq $AudiencePolicy){ RIE-GovDie "AUDIENCE_POLICY_NULL" }
  if($null -eq $SourcePolicy){ RIE-GovDie "SOURCE_POLICY_NULL" }
  if($null -eq $DomainProfileMap){ $DomainProfileMap = @{} }

  $sourceId = RIE-GovGetString $Source "source_id"
  if([string]::IsNullOrWhiteSpace($sourceId)){ $sourceId = "unknown_source" }

  $audienceBand = RIE-GovGetString $AudiencePolicy "audience_band"
  $domain = RIE-GovGetDomainFromSource $Source
  $domainProfile = $null
  if(-not [string]::IsNullOrWhiteSpace($domain) -and $DomainProfileMap.ContainsKey($domain)){
    $domainProfile = $DomainProfileMap[$domain]
  }

  $checks = New-Object System.Collections.Generic.List[object]
  $warnCount = 0
  $failCount = 0
  $passCount = 0
  $finalRecommendation = "ALLOW_CHILD_SAFE"

  $hasProv = RIE-GovHasProvenance $Source
  if($hasProv){
    [void]$checks.Add((RIE-GovNewCheck "chk_prov" "provenance_present" "pass" "Required provenance fields present." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
    $passCount++
  } else {
    [void]$checks.Add((RIE-GovNewCheck "chk_prov" "provenance_present" "fail" "Required provenance fields missing." "DENY_MISSING_PROVENANCE"))
    $failCount++
    $finalRecommendation = "DENY"
  }

  $hasForbidden = RIE-GovContainsAnswerLikePattern $Source
  if($hasForbidden){
    [void]$checks.Add((RIE-GovNewCheck "chk_answer" "forbidden_answer_like_pattern" "fail" "Answer-like or solution-like fields are present." "DENY_FORBIDDEN_ANSWER_CONTENT"))
    $failCount++
    $finalRecommendation = "DENY"
  } else {
    [void]$checks.Add((RIE-GovNewCheck "chk_answer" "forbidden_answer_like_pattern" "pass" "No forbidden answer-like fields present." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
    $passCount++
  }

  $domainLists = $null
  if(RIE-GovHasKey $SourcePolicy "domain_lists"){ $domainLists = $SourcePolicy["domain_lists"] }

  $domainStatus = ""
  if(($domainLists -is [hashtable]) -or ($domainLists -is [System.Collections.IDictionary])){
    if(RIE-GovIsListed $domain $domainLists["denylist"]){
      $domainStatus = "denylist"
      [void]$checks.Add((RIE-GovNewCheck "chk_domain" "domain_policy" "fail" "Domain is denylisted." "DENY_DOMAIN_POLICY_BLOCKED"))
      $failCount++
      $finalRecommendation = "DENY"
    } elseif(RIE-GovIsListed $domain $domainLists["cautionlist"]){
      $domainStatus = "cautionlist"
      [void]$checks.Add((RIE-GovNewCheck "chk_domain" "domain_policy" "warn" "Domain is caution-listed." "QUARANTINE_REQUIRES_REVIEW"))
      $warnCount++
      if($finalRecommendation -ne "DENY"){ $finalRecommendation = "QUARANTINE_REVIEW_ONLY" }
    } elseif(RIE-GovIsListed $domain $domainLists["watchlist"]){
      $domainStatus = "watchlist"
      [void]$checks.Add((RIE-GovNewCheck "chk_domain" "domain_policy" "warn" "Domain is watch-listed." "DOWNRANK_LOW_SIGNAL"))
      $warnCount++
      if($finalRecommendation -eq "ALLOW_CHILD_SAFE"){ $finalRecommendation = "DOWNRANK" }
    } elseif(RIE-GovIsListed $domain $domainLists["allowlist"]){
      $domainStatus = "allowlist"
      [void]$checks.Add((RIE-GovNewCheck "chk_domain" "domain_policy" "pass" "Domain is allowlisted." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
      $passCount++
    } else {
      [void]$checks.Add((RIE-GovNewCheck "chk_domain" "domain_policy" "warn" "Domain is unlisted." "DOWNRANK_LOW_SIGNAL"))
      $warnCount++
      if($finalRecommendation -eq "ALLOW_CHILD_SAFE"){ $finalRecommendation = "DOWNRANK" }
    }
  }

  $anchorRequired = $false
  if(RIE-GovHasKey $AudiencePolicy "require_institutional_or_publisher_anchor"){
    $anchorRequired = [bool]$AudiencePolicy["require_institutional_or_publisher_anchor"]
  }
  $hasAnchor = RIE-GovHasInstitutionalOrPublisherAnchor $Source $domainProfile
  if($anchorRequired){
    if($hasAnchor){
      [void]$checks.Add((RIE-GovNewCheck "chk_anchor" "institutional_or_publisher_anchor" "pass" "Institutional or publisher anchor present." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
      $passCount++
    } else {
      [void]$checks.Add((RIE-GovNewCheck "chk_anchor" "institutional_or_publisher_anchor" "fail" "Required institutional or publisher anchor missing." "DENY_AUDIENCE_POLICY_CHILD_SAFE"))
      $failCount++
      $finalRecommendation = "DENY"
    }
  } else {
    [void]$checks.Add((RIE-GovNewCheck "chk_anchor" "institutional_or_publisher_anchor" "pass" "Anchor not required by audience policy." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
    $passCount++
  }

  $trustCount = RIE-GovCountTrustSignals $Source
  $minTrust = 0
  if(RIE-GovHasKey $AudiencePolicy "min_trust_signal_count"){ $minTrust = [int]$AudiencePolicy["min_trust_signal_count"] }
  if($trustCount -ge $minTrust){
    [void]$checks.Add((RIE-GovNewCheck "chk_trust" "trust_signal_count" "pass" ("Trust signal count=" + $trustCount) "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
    $passCount++
  } else {
    [void]$checks.Add((RIE-GovNewCheck "chk_trust" "trust_signal_count" "fail" ("Trust signal count=" + $trustCount + " is below required minimum=" + $minTrust) "DENY_LOW_TRUST_UNVERIFIED_SOURCE"))
    $failCount++
    $finalRecommendation = "DENY"
  }

  $allowCommunity = [bool]$AudiencePolicy["allow_community_sources"]
  $classification = ""
  if($domainProfile -ne $null){ $classification = RIE-GovGetString $domainProfile "classification" }
  if($classification -eq "community_educator"){
    if($allowCommunity){
      [void]$checks.Add((RIE-GovNewCheck "chk_comm" "community_source_gate" "warn" "Community source allowed with educator warning." "ALLOW_WITH_EDUCATOR_WARNING_COMMUNITY_SOURCE"))
      $warnCount++
      if($finalRecommendation -eq "ALLOW_CHILD_SAFE"){ $finalRecommendation = "ALLOW_WITH_EDUCATOR_WARNING" }
    } else {
      [void]$checks.Add((RIE-GovNewCheck "chk_comm" "community_source_gate" "fail" "Community source blocked for this audience." "QUARANTINE_COMMUNITY_SOURCE_UNVERIFIED"))
      $failCount++
      if($finalRecommendation -ne "DENY"){ $finalRecommendation = "QUARANTINE_REVIEW_ONLY" }
    }
  } else {
    [void]$checks.Add((RIE-GovNewCheck "chk_comm" "community_source_gate" "pass" "Not classified as community source." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
    $passCount++
  }

  $allowVideoPlatforms = [bool]$AudiencePolicy["allow_video_platforms"]
  $contentKind = RIE-GovGetString $Source "content_kind"
  if(($classification -eq "educational_video_platform") -or ($contentKind -eq "video")){
    if($allowVideoPlatforms){
      [void]$checks.Add((RIE-GovNewCheck "chk_video" "video_platform_gate" "pass" "Video source permitted by audience policy." "ALLOW_CHILD_SAFE_TRUSTED_EDU"))
      $passCount++
    } else {
      [void]$checks.Add((RIE-GovNewCheck "chk_video" "video_platform_gate" "fail" "Video source blocked by audience policy." "DENY_AUDIENCE_POLICY_CHILD_SAFE"))
      $failCount++
      $finalRecommendation = "DENY"
    }
  }

  if($domainStatus -eq "watchlist"){
    [void]$checks.Add((RIE-GovNewCheck "chk_domshare" "domain_dominance_risk" "warn" "Watch-listed domain contributes dominance risk." "DOWNRANK_DOMAIN_DOMINANCE"))
    $warnCount++
    if($finalRecommendation -eq "ALLOW_CHILD_SAFE"){ $finalRecommendation = "DOWNRANK" }
  }

  if($failCount -gt 0 -and $finalRecommendation -eq "ALLOW_CHILD_SAFE"){ $finalRecommendation = "DENY" }

  return [ordered]@{
    schema = "rie.source_evaluation.v1"
    evaluation_id = RIE-GovNewId "eval"
    evaluated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source_id = $sourceId
    source_hash = RIE-GovGetString $Source "content_hash"
    audience_band = $audienceBand
    domain_profile_ref = $domain
    checks = @($checks.ToArray())
    summary = [ordered]@{
      passed_count = $passCount
      warn_count = $warnCount
      failed_count = $failCount
      final_recommendation = $finalRecommendation
    }
  }
}

function RIE-DecideAdmissionV1(
  $Source,
  $AudiencePolicy,
  $SourcePolicy,
  $Evaluation
){
  if($null -eq $Source){ RIE-GovDie "SOURCE_NULL" }
  if($null -eq $AudiencePolicy){ RIE-GovDie "AUDIENCE_POLICY_NULL" }
  if($null -eq $SourcePolicy){ RIE-GovDie "SOURCE_POLICY_NULL" }
  if($null -eq $Evaluation){ RIE-GovDie "EVALUATION_NULL" }

  $action = [string]$Evaluation["summary"]["final_recommendation"]
  $reason = ""

  switch($action){
    "ALLOW_CHILD_SAFE" {
      $classificationReason = "ALLOW_CHILD_SAFE_TRUSTED_EDU"
      $domain = RIE-GovGetDomainFromSource $Source
      if($domain.EndsWith(".gov") -or $domain -eq "nasa.gov" -or $domain -eq "nih.gov"){
        $classificationReason = "ALLOW_CHILD_SAFE_GOV_SCIENCE"
      } elseif(RIE-GovHasKey $Source "publisher"){
        $pub = RIE-GovGetString $Source "publisher"
        if(-not [string]::IsNullOrWhiteSpace($pub)){ $classificationReason = "ALLOW_CHILD_SAFE_PUBLISHER_BACKED" }
      }
      $reason = $classificationReason
    }
    "ALLOW_WITH_EDUCATOR_WARNING" { $reason = "ALLOW_WITH_EDUCATOR_WARNING_COMMUNITY_SOURCE" }
    "QUARANTINE_REVIEW_ONLY" { $reason = "QUARANTINE_REQUIRES_REVIEW" }
    "DOWNRANK" { $reason = "DOWNRANK_LOW_SIGNAL" }
    "DENY" {
      $reason = "DENY_LOW_TRUST_UNVERIFIED_SOURCE"
      foreach($c in @($Evaluation["checks"])){
        if(($c -is [hashtable]) -or ($c -is [System.Collections.IDictionary])){
          if([string]$c["status"] -eq "fail"){
            $reason = [string]$c["reason_code"]
            break
          }
        }
      }
    }
    default { $reason = "DENY_LOW_TRUST_UNVERIFIED_SOURCE"; $action = "DENY" }
  }

  $warning = ""
  if($action -eq "ALLOW_WITH_EDUCATOR_WARNING"){
    $warning = "Community source allowed only with educator warning."
  } elseif($action -eq "QUARANTINE_REVIEW_ONLY"){
    $warning = "Source requires review before surfacing to learner."
  }

  return [ordered]@{
    schema = "rie.admission_decision.v1"
    decision_id = RIE-GovNewId "adm"
    decided_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source_id = RIE-GovGetString $Source "source_id"
    source_hash = RIE-GovGetString $Source "content_hash"
    audience_band = RIE-GovGetString $AudiencePolicy "audience_band"
    policy_id = RIE-GovGetString $SourcePolicy "policy_id"
    evaluation_id = [string]$Evaluation["evaluation_id"]
    action = $action
    reason_code = $reason
    warning_label = $warning
    notes = ""
  }
}

function RIE-WriteGovernanceReceiptV1([string]$RepoRoot,$Decision,$Evaluation){
  if([string]::IsNullOrWhiteSpace($RepoRoot)){ RIE-GovDie "REPO_ROOT_EMPTY" }
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  $receiptsDir = Join-Path $RepoRoot "proofs\receipts"
  if(-not (Test-Path -LiteralPath $receiptsDir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $receiptsDir | Out-Null
  }

  $line = [ordered]@{
    schema = "rie.governance.receipt.v1"
    utc = (Get-Date).ToUniversalTime().ToString("o")
    decision_id = [string]$Decision["decision_id"]
    evaluation_id = [string]$Decision["evaluation_id"]
    source_id = [string]$Decision["source_id"]
    audience_band = [string]$Decision["audience_band"]
    action = [string]$Decision["action"]
    reason_code = [string]$Decision["reason_code"]
    failed_count = [int]$Evaluation["summary"]["failed_count"]
    warn_count = [int]$Evaluation["summary"]["warn_count"]
    passed_count = [int]$Evaluation["summary"]["passed_count"]
    ok = $true
  }

  $path = Join-Path $receiptsDir "rie.source_governance.v1.ndjson"
  $json = RIE-GovToJson $line
  if(Test-Path -LiteralPath $path -PathType Leaf){
    $existing = RIE-GovReadUtf8NoBom $path
    RIE-GovWriteUtf8NoBomLf $path ($existing.TrimEnd("`r","`n") + "`n" + $json + "`n")
  } else {
    RIE-GovWriteUtf8NoBomLf $path ($json + "`n")
  }
  return $path
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
  if([string]::IsNullOrWhiteSpace($OutDir)){ $OutDir = Join-Path $RepoRoot "proofs\governance" }
  if(-not (Test-Path -LiteralPath $OutDir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  }

  $source = RIE-GovLoadJson $SourcePath
  $aud = RIE-GovLoadJson $AudiencePolicyPath
  $policy = RIE-GovLoadJson $SourcePolicyPath
  $domainMap = RIE-GovLoadDomainProfileMap $DomainProfilesPath

  $eval = RIE-EvaluateSourceV1 $source $aud $policy $domainMap
  $dec = RIE-DecideAdmissionV1 $source $aud $policy $eval

  $sourceId = RIE-GovGetString $source "source_id"
  if([string]::IsNullOrWhiteSpace($sourceId)){ $sourceId = "unknown_source" }

  $evalPath = Join-Path $OutDir ("rie_source_evaluation_" + $sourceId + ".json")
  $decPath  = Join-Path $OutDir ("rie_admission_decision_" + $sourceId + ".json")

  RIE-GovWriteUtf8NoBomLf $evalPath (RIE-GovToJson $eval)
  RIE-GovWriteUtf8NoBomLf $decPath  (RIE-GovToJson $dec)
  $receiptPath = RIE-WriteGovernanceReceiptV1 $RepoRoot $dec $eval

  return [ordered]@{
    ok = $true
    evaluation_path = $evalPath
    decision_path = $decPath
    receipt_path = $receiptPath
    action = [string]$dec["action"]
    reason_code = [string]$dec["reason_code"]
  }
}
