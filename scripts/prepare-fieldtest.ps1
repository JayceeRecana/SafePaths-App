param([switch]$DeployRules)
$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testConfigPath = Join-Path $workspace 'android/app/src/fieldtest/google-services.json'
if (-not (Test-Path -LiteralPath $testConfigPath)) {
  throw 'Download the TEST Android google-services.json into android/app/src/fieldtest first.'
}
$testConfig = Get-Content -LiteralPath $testConfigPath -Raw | ConvertFrom-Json
$productionConfig = Get-Content -LiteralPath (Join-Path $workspace 'android/app/google-services.json') -Raw | ConvertFrom-Json
$testProject = $testConfig.project_info.project_id
if (-not $testProject -or $testProject -eq $productionConfig.project_info.project_id) {
  throw 'A separate TEST Firebase project is required. Refusing the production project.'
}
if (-not ($testConfig.client | Where-Object { $_.client_info.android_client_info.package_name -eq 'com.safepaths.safepaths_app.test' })) {
  throw 'The test Firebase Android app must use com.safepaths.safepaths_app.test.'
}
$sourceEnv = Get-Content -LiteralPath (Join-Path $workspace '.env')
$tokenLine = $sourceEnv | Where-Object { $_ -match '^\s*MAPBOX_ACCESS_TOKEN\s*=' } | Select-Object -First 1
if (-not $tokenLine) { throw 'MAPBOX_ACCESS_TOKEN is missing from .env.' }
$publicToken = ($tokenLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
if (-not $publicToken.StartsWith('pk.')) { throw 'A public Mapbox token beginning with pk. is required.' }
# Generate an allowlisted asset. Never copy Supabase, FCM, or other credentials.
$asset = "FIELDTEST_FIREBASE_PROJECT_ID=$testProject`nMAPBOX_ACCESS_TOKEN=$publicToken`n"
[System.IO.File]::WriteAllText((Join-Path $workspace '.env.fieldtest'), $asset, [System.Text.UTF8Encoding]::new($false))
Write-Output "Test configuration prepared for project: $testProject"
if ($DeployRules) {
  if ($testProject -ne 'safepaths-test') {
    throw 'The migrated test rules/indexes are pinned to safepaths-test. Review a different target separately.'
  }
  Push-Location $workspace
  try {
    # Include the extra reports(roadId, createdAt desc) index used by road report
    # history. The earlier baseline config omits it. No deployment occurs unless
    # this script is explicitly invoked with -DeployRules.
    & firebase.cmd deploy --only firestore --project $testProject --config firebase.spark-proof.json
    if ($LASTEXITCODE -ne 0) { throw 'Test rules deployment failed.' }
  } finally { Pop-Location }
}
