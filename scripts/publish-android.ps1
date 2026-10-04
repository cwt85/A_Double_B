# 從環境變數讀取簽署資訊，建置與簽署 Google Play 所需的 AAB。
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VersionName,
    [Parameter(Mandatory)][long]$VersionCode,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
if ($VersionName -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'VersionName 必須是三段數字，例如 1.1.0。'
}
if ($VersionCode -lt 1 -or $VersionCode -gt 2100000000) { throw 'VersionCode 超出 Android 範圍。' }
$repositoryPath = Split-Path $PSScriptRoot -Parent
$projectPath = Join-Path $repositoryPath 'ADoubleB/ADoubleB.csproj'
[xml]$project = Get-Content -LiteralPath $projectPath -Raw
$applicationId = [string]($project.Project.PropertyGroup.ApplicationId | Where-Object { $_ })
if ($applicationId -ne 'com.companyname.adoubleb') { throw 'ApplicationId 已變更，請同步檢查 workflow 與 Play Console 套件名稱。' }
if ($ValidateOnly) {
    Write-Output "設定檢查成功：$applicationId / $VersionName / $VersionCode"
    return
}
foreach ($name in @('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEYSTORE_PASSWORD')) {
    if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) { throw "缺少環境變數：$name" }
}

# 每次建置使用獨立暫存目錄，避免把金鑰及密碼放入專案或 Artifact。
$signingPath = Join-Path ([IO.Path]::GetTempPath()) ("adoubleb-signing-" + [guid]::NewGuid().ToString('N'))
$artifactPath = Join-Path $repositoryPath 'artifacts'
$publishPath = Join-Path $signingPath 'publish'
New-Item -ItemType Directory -Path $signingPath | Out-Null
try {
    $keystorePath = Join-Path $signingPath 'upload.keystore'
    $keyPasswordPath = Join-Path $signingPath 'key-password.txt'
    $storePasswordPath = Join-Path $signingPath 'store-password.txt'
    [IO.File]::WriteAllBytes($keystorePath, [Convert]::FromBase64String($env:ANDROID_KEYSTORE_BASE64))
    [IO.File]::WriteAllText($keyPasswordPath, $env:ANDROID_KEY_PASSWORD)
    [IO.File]::WriteAllText($storePasswordPath, $env:ANDROID_KEYSTORE_PASSWORD)
    # AAB 使用 file: 讀取密碼，避免把密碼列在命令或建置紀錄中。
    $publishArguments = @(
        'publish', $projectPath, '-f', 'net10.0-android', '-c', 'Release',
        '-p:TargetFrameworks=net10.0-android', '-p:AndroidPackageFormats=aab',
        '-p:AndroidPackageFormat=aab', '-p:AndroidKeyStore=true',
        "-p:ApplicationDisplayVersion=$VersionName", "-p:ApplicationVersion=$VersionCode",
        "-p:AndroidSigningKeyStore=$keystorePath", "-p:AndroidSigningKeyAlias=$env:ANDROID_KEY_ALIAS",
        "-p:AndroidSigningKeyPass=file:$keyPasswordPath", "-p:AndroidSigningStorePass=file:$storePasswordPath",
        '-o', $publishPath
    )
    & dotnet @publishArguments
    if ($LASTEXITCODE -ne 0) { throw 'Android Release 建置或簽署失敗。' }
    # 僅接受一個已簽署的 Bundle，避免誤上傳 unsigned 檔案。
    $bundles = @(Get-ChildItem -LiteralPath $publishPath -Filter '*-Signed.aab')
    if ($bundles.Count -ne 1) { throw "預期一個已簽署 AAB，實際找到 $($bundles.Count) 個。" }
    New-Item -ItemType Directory -Force -Path $artifactPath | Out-Null
    Copy-Item -LiteralPath $bundles[0].FullName -Destination (Join-Path $artifactPath 'play-release.aab')
    Write-Output "AAB 已產生：artifacts/play-release.aab（$VersionName / $VersionCode）"
} finally {
    # 僅清除本次建立的獨立暫存目錄，建置失敗時也會清除。
    $resolvedSigningPath = [IO.Path]::GetFullPath($signingPath)
    $resolvedTempPath = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (!$resolvedSigningPath.StartsWith($resolvedTempPath, [StringComparison]::OrdinalIgnoreCase)) { throw '暫存目錄位置不符合預期。' }
    Remove-Item -LiteralPath $resolvedSigningPath -Recurse -Force
}
