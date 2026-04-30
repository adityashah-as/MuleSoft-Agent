<#
.SYNOPSIS
  Tests Salesforce credentials in .env directly against the SOAP login API.
  No Mule involved. If this fails, the creds are wrong (not a Mule bug).
  If this succeeds, the creds are right and the issue is somewhere in the Mule pipeline.

.DESCRIPTION
  Reads SFDC_USERNAME, SFDC_PASSWORD, SFDC_SECURITY_TOKEN from .env at the
  project root, and POSTs a SOAP login request to the URL configured in
  src/main/resources/config.yaml (sfdc.url). Reports session id on success or
  the exact Salesforce fault on failure.

.NOTES
  Salesforce concatenates password + token for SOAP login.
  Use https://test.salesforce.com/... for SANDBOX; https://login.salesforce.com/... for PRODUCTION.
#>

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# ---------- 1. Load .env ----------
$envFile = Join-Path $projectRoot '.env'
if (-not (Test-Path $envFile)) { Write-Error ".env not found at $envFile" }

Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*#') { return }
  if ($_ -match '^\s*$') { return }
  if ($_ -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
    Set-Item -Path "Env:$($matches[1].Trim())" -Value $matches[2].Trim()
  }
}

$user = $env:SFDC_USERNAME
$pass = $env:SFDC_PASSWORD
$tok  = $env:SFDC_SECURITY_TOKEN

foreach ($pair in @{ SFDC_USERNAME=$user; SFDC_PASSWORD=$pass; SFDC_SECURITY_TOKEN=$tok }.GetEnumerator()) {
  if ([string]::IsNullOrWhiteSpace($pair.Value)) {
    Write-Error "$($pair.Key) is empty in .env"
  }
  Write-Host ("{0,-22} length = {1}" -f $pair.Key, $pair.Value.Length)
}

# ---------- 2. Read sfdc.url from config.yaml ----------
$configYaml = Join-Path $projectRoot 'src\main\resources\config.yaml'
$urlLine    = Select-String -Path $configYaml -Pattern '^\s*url:\s*"?([^"\s]+)"?' | Select-Object -First 1
if (-not $urlLine) { Write-Error "Could not find sfdc.url in $configYaml" }
$loginUrl   = $urlLine.Matches[0].Groups[1].Value
Write-Host ""
Write-Host "Login URL: $loginUrl"
$envHint    = if ($loginUrl -match 'test\.salesforce\.com') { 'SANDBOX' }
              elseif ($loginUrl -match 'login\.salesforce\.com') { 'PRODUCTION' }
              else { 'CUSTOM' }
Write-Host "Org type:  $envHint"
Write-Host ""

# ---------- 3. Build SOAP login envelope ----------
function Encode-Xml($s) { [System.Security.SecurityElement]::Escape($s) }
$soap = @"
<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
  <env:Body>
    <n1:login xmlns:n1="urn:partner.soap.sforce.com">
      <n1:username>$(Encode-Xml $user)</n1:username>
      <n1:password>$(Encode-Xml ($pass + $tok))</n1:password>
    </n1:login>
  </env:Body>
</env:Envelope>
"@

# ---------- 4. POST and report ----------
Write-Host "Calling Salesforce SOAP login..."
try {
  $response = Invoke-RestMethod -Uri $loginUrl -Method POST `
    -Body $soap `
    -ContentType 'text/xml; charset=UTF-8' `
    -Headers @{ 'SOAPAction' = 'login' }

  $sessionId = $response.Envelope.Body.loginResponse.result.sessionId
  $serverUrl = $response.Envelope.Body.loginResponse.result.serverUrl
  $userId    = $response.Envelope.Body.loginResponse.result.userId

  Write-Host ""
  Write-Host "==================== LOGIN OK ====================" -ForegroundColor Green
  Write-Host "User Id:    $userId"
  Write-Host "Server URL: $serverUrl"
  Write-Host ("Session Id: {0}..." -f $sessionId.Substring(0, [Math]::Min(20, $sessionId.Length)))
  Write-Host "==================================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "These credentials WORK against Salesforce."
  Write-Host "If Mule still rejects them, the issue is somewhere in the script -> system property -> Mule placeholder chain (not the creds)."
}
catch {
  $resp = $_.Exception.Response
  if ($resp) {
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $errBody = $reader.ReadToEnd()
    Write-Host ""
    Write-Host "==================== LOGIN FAILED ====================" -ForegroundColor Red
    Write-Host "HTTP status: $([int]$resp.StatusCode) $($resp.StatusDescription)"
    Write-Host ""
    if ($errBody -match '<faultstring>([^<]+)</faultstring>') {
      Write-Host "faultstring: $($matches[1])" -ForegroundColor Yellow
    }
    if ($errBody -match '<sf:exceptionCode[^>]*>([^<]+)</sf:exceptionCode>') {
      Write-Host "exceptionCode: $($matches[1])" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Common causes:"
    Write-Host "  1. Wrong security token (most common) - resets every time you change password"
    Write-Host "  2. Wrong URL - sandbox needs test.salesforce.com, prod needs login.salesforce.com"
    Write-Host "  3. Username missing the sandbox suffix (e.g. you\@company.com.dev1)"
    Write-Host "  4. Trailing whitespace in .env values"
    Write-Host "  5. API access not enabled on this user profile"
    Write-Host "==================================================" -ForegroundColor Red
  } else {
    throw
  }
}
