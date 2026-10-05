# Google Play 內部測試自動發布

工作流程：推送 `android-v1.1.1` 這類標籤 → 安裝 .NET 10 與 MAUI Android → 使用既有上傳金鑰簽署 AAB → 保存 AAB → 上傳 Google Play `internal` 軌道。

一般 push 不會觸發。工作流程使用 `status: completed`，代表發布給內部測試軌道的測試人員；Google 的處理或審核仍依 Play Console 狀態為準。此流程不會更新商店圖片、隱私權政策、資料安全表單或正式軌道。

## 1. 確認現有 App

Play Console 的套件名稱必須是 `com.companyname.adoubleb`，與專案及 workflow 一致。使用上一次手動上傳時的 keystore 與 alias，不能重新產生另一把金鑰替代。

## 2. 設定 Google 服務帳戶

1. 在 Google Cloud 建立或選擇專案，啟用 Google Play Android Developer API。
2. 建立專用服務帳戶；不需要授予 Google Cloud 專案 Owner 或 Editor。
3. 在服務帳戶的「金鑰」建立 JSON 金鑰，保存下載的 JSON。
4. 在 Play Console「使用者與權限」邀請 JSON 中 `client_email` 的服務帳戶。
5. 僅授權此 App 的查看資訊與「發布應用程式至測試軌道」權限。設定內部測試人員名單與加入測試的連結。

Google 官方設定說明：https://developers.google.com/android-publisher/getting_started

## 3. 設定 GitHub Secrets

Repository → Settings → Secrets and variables → Actions → Secrets → New repository secret。

| Secret | 內容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 既有 keystore 的 Base64 字串 |
| `ANDROID_KEY_ALIAS` | 金鑰 alias，目前專案為 `ADoubleB_APP_Key`；請以實際金鑰為準 |
| `ANDROID_KEY_PASSWORD` | 該 alias 的金鑰密碼 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密碼 |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | 服務帳戶 JSON 的完整原文，不是檔名，也不需轉成 Base64 |

在本機 PowerShell 將 keystore 的 Base64 複製到剪貼簿，再貼到 Secret：

```powershell
# 使用實際已上傳版本所用的 keystore，避免輸出金鑰內容到終端紀錄。
$keystorePath = 'C:\Users\user\source\repos\ADoubleB\ADoubleB\ADoubleB.keystore'
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath)) | Set-Clipboard
```

不要把 keystore、密碼或服務帳戶 JSON 加進 Git。建置腳本會暫時還原金鑰與密碼檔，並在成功或失敗後清除；只將已簽署的 AAB 保存為 Artifact。

## 4. 設定版本代碼

同一頁切到 Variables，新增 Repository variable `PLAY_VERSION_CODE_BASE`。

先到 Play Console 的 App Bundle 探索工具查看**所有軌道已上傳的最大版本代碼**，將起始值設為至少等於該值。例如最大值為 `1`，可設定為 `1000`。

workflow 的版本代碼 = `PLAY_VERSION_CODE_BASE` + 此 workflow 的 `github.run_number`。起始值 `1000` 的第一次執行即為 `1001`。版本名稱則由 `android-v1.1.1` 得到 `1.1.1`，不需要每次手動修改 csproj。

不要降低起始值。未來若另行手動上傳更大的版本代碼、重新命名或重建 workflow，應重新檢查起始值。重跑同一次 workflow 會沿用同一版本代碼；若 AAB 已被 Google 接受，請建立新版本標籤觸發新執行，避免重複代碼。發布標籤請逐次推送，等待上一個流程完成。

## 5. 觸發發布

先將這次新增的 workflow、腳本與說明提交並推送到 GitHub，再對要發布的 commit 建立標籤：

```powershell
# 確認目前 commit 就是要發布的版本，且 Secrets／Variable 已設定。
git tag android-v1.1.1
git push origin android-v1.1.1
```

在 GitHub 的 Actions 查看 `Publish Google Play internal test`。成功後到 Play Console 內部測試確認版本，測試完成後手動推進正式發布。上傳失敗時仍可從成功的「Save signed bundle」步驟下載 AAB。

## 常見失敗

- **缺少 Secret／Variable**：流程會在安裝工具前停止，依錯誤補上設定。
- **簽署金鑰不符**：確認 Secrets 使用的是 Play Console 認可的上傳金鑰。
- **版本代碼已使用或過小**：調高起始值並使用新標籤重新發布。
- **403／權限不足**：確認 API 已啟用、服務帳戶已加入 Play Console，且有此 App 的測試發布權限。
- **App 仍是草稿**：先在 Play Console 完成首次發布及必要資料；草稿 App 可能只允許 `draft` 發布。
- **changesNotSentForReview 相關錯誤**：依 Play Console 實際審核狀態決定是否在上傳步驟加入 `changesNotSentForReview: true`；這會要求到 Console 手動送審，不預設啟用。

## 本機檢查（不會發布）

```powershell
# 只驗證版本格式、範圍與專案套件名稱，不讀取憑證、不建置、不上傳。
./scripts/publish-android.ps1 -VersionName 1.1.0 -VersionCode 1001 -ValidateOnly
```

建置參數依 [Microsoft MAUI 發布文件](https://learn.microsoft.com/en-us/dotnet/maui/android/deployment/publish-cli?view=net-maui-10.0) 設定；上傳使用 [r0adkll/upload-google-play](https://github.com/r0adkll/upload-google-play)，第三方 Action 及 GitHub 官方 Action 均固定 commit。
