Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function RIE-Die([string]$m){ throw $m }

function RIE-DeepToHashtable($v){
  if($null -eq $v){ return $null }
  if($v -is [System.Collections.IDictionary]){
    $h=@{}
    foreach($k in $v.Keys){ $h[[string]$k] = RIE-DeepToHashtable $v[$k] }
    return $h
  }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    $arr = New-Object System.Collections.Generic.List[object]
    foreach($x in $v){ [void]$arr.Add((RIE-DeepToHashtable $x)) }
    return $arr.ToArray()
  }
  return $v
}

function RIE-ParseJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ RIE-Die ("FILE_MISSING: " + $Path) }
  $b = $null
  $s = $null
  try {
    $b = [System.IO.File]::ReadAllBytes($Path)
    $enc = New-Object System.Text.UTF8Encoding($false,$true)
    $s = $enc.GetString($b)
    if([string]::IsNullOrWhiteSpace($s)){ RIE-Die ("JSON_EMPTY: " + $Path) }
    if($s.Length -gt 0 -and [int][char]$s[0] -eq 65279){ $s = $s.Substring(1) }
    $s = $s.Replace("`r`n","`n").Replace("`r","`n")

    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.RecursionLimit = 256
    $ser.MaxJsonLength = 2147483647
    $obj = $ser.DeserializeObject($s)
    return (RIE-DeepToHashtable $obj)
  } catch {
    $m = $_.Exception.Message
    if([string]::IsNullOrWhiteSpace($m)){ $m = ($_ | Out-String) }
    $m = ($m -replace "(\r\n|\r|\n)"," | ")
    RIE-Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $m)
  }
}

function RIE-ValidateSourceRecordV1($o,[string]$ctx){
  if($null -eq $o){ RIE-Die ("SRC_NULL:" + $ctx) }

  # accept hashtable or dictionary-like objects
  if(-not (($o -is [hashtable]) -or ($o -is [System.Collections.IDictionary]))){
    RIE-Die ("SRC_NOT_OBJECT:" + $ctx)
  }

  foreach($k in @("schema","source_id","content_kind","title","provenance","tags")){
    if(-not $o.ContainsKey($k)){ RIE-Die ("MISSING_PROP:" + $k + ":" + $ctx) }
  }

  if([string]$o["schema"] -ne "rie.source_record.v1"){
    RIE-Die ("BAD_SCHEMA:" + [string]$o["schema"] + ":" + $ctx)
  }

  if($o.ContainsKey("answer")){ RIE-Die ("FORBIDDEN_PROP:answer:" + $ctx) }

  $p = $o["provenance"]
  if(-not (($p -is [hashtable]) -or ($p -is [System.Collections.IDictionary]))){
    RIE-Die ("PROVENANCE_NOT_OBJECT:" + $ctx)
  }

  foreach($k2 in @("discovered_from","retrieved_at_utc")){
    if(-not $p.ContainsKey($k2)){ RIE-Die ("MISSING_PROP:provenance." + $k2 + ":" + $ctx) }
  }

  $t = $o["tags"]
  if(-not (($t -is [System.Collections.IEnumerable]) -and -not ($t -is [string]))){
    RIE-Die ("TAGS_NOT_ARRAY:" + $ctx)
  }
}
