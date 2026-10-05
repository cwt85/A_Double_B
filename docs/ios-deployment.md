# iOS／TestFlight：使用 Mac 與 GitHub Actions 自動部署

本文件針對 ADoubleB 的 iOS App，不是 Mac Catalyst 桌面 App。專案已包含 `net10.0-ios`，目前 Bundle ID 為 `com.companyname.adoubleb`。

專案已建立 `.github/workflows/ios-testflight.yml`，推送 `ios-v*` 標籤會建置並上傳 App Store Connect。Android 使用獨立的 `android-v*` 標籤。

## 1. 先理解流程

```text
推送 ios-v1.0.0 標籤
    → GitHub macOS runner 安裝相容的 .NET／iOS workload／Xcode
    → 匯入 Apple 簽署憑證與描述檔
    → 編譯、簽署並產生 .ipa
    → 使用 App Store Connect API Key 上傳
    → Apple 處理版本
    → 在 TestFlight 設定測試
    → 測試完成後手動送 App Store 審核
```

三種資料各有不同用途：

| 資料 | 用途 |
| --- | --- |
| Apple Distribution 憑證與私鑰（`.p12`） | 簽署 App，證明發布者身分 |
| App Store Connect 描述檔（`.mobileprovision`） | 將 App ID、Apple 團隊與發布憑證對應起來 |
| App Store Connect API Key（`.p8`） | 授權 GitHub Actions 上傳建置版本 |

GitHub 提供的 macOS runner 負責雲端建置；你的 Mac 可用來準備憑證。正式上架還需要商店資料、隱私權資訊、截圖與 Apple 審核，不會因為上傳 IPA 就自動完成。

## 2. 準備 Apple 帳號與 App

1. 準備有效的 Apple Developer Program 會員資格。
2. 登入 [Apple Developer](https://developer.apple.com/account)。
3. 到 **Certificates, Identifiers & Profiles → Identifiers → ＋ → App IDs** 註冊明確的 Bundle ID。
4. 可嘗試註冊目前的 `com.companyname.adoubleb`，或在首次 iOS 發布前選定自己的名稱；若更換，後續只修改 iOS 的 ApplicationId，保留 Android 已發布的套件名稱。
5. 到 [App Store Connect](https://appstoreconnect.apple.com) 的 **我的 App → ＋ → 新增 App**。
6. 選擇 iOS，填入名稱、主要語言、Bundle ID 與自訂 SKU（例如 `ADoubleB-iOS`）。

程式、描述檔與 App Store Connect 必須使用相同 Bundle ID。不要把 Bundle ID、Apple Team ID 與 App Store Connect 的數字 Apple ID 混在一起。

官方說明：[App Store Connect 工作流程](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow)。

## 3. 在 Mac 產生 CSR

CSR 是申請憑證用的檔案；產生時對應的私鑰會留在這台 Mac 的鑰匙圈中。

1. 開啟 Mac 的 **鑰匙圈存取（Keychain Access）**。
2. 選單選擇 **憑證輔助程式 → 向憑證授權單位要求憑證**。
3. 使用者電子郵件填入 `cwt5278@gmail.com`。
4. 常用名稱可填入 `陳瑋廷 ADoubleB Distribution`。
5. CA 電子郵件留空，選擇 **儲存到磁碟**。
6. 保存產生的 `.certSigningRequest`。

官方說明：[建立 CSR](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/)。

## 4. 建立 Apple Distribution 憑證並匯出 P12

1. 在 Apple Developer 的 **Certificates, Identifiers & Profiles → Certificates → ＋** 選擇 **Apple Distribution**。
2. 上傳剛產生的 CSR，建立並下載 `.cer`。
3. 在產生 CSR 的同一台 Mac 雙擊 `.cer`，匯入鑰匙圈。
4. 在鑰匙圈的 **我的憑證** 找到 `Apple Distribution: …`。
5. 展開憑證，確認下方有對應私鑰。
6. 選取這份憑證與私鑰，匯出為 `.p12`，例如 `ADoubleB-distribution.p12`。
7. 設定並保存匯出密碼。

只有 `.cer` 不足以簽署 App。如果無法匯出 `.p12` 或找不到私鑰，先確認是否使用當初建立 CSR 的 Mac。記下完整的憑證名稱，後续會作為 `CodesignKey`。

## 5. 建立 App Store Connect 描述檔

1. 到 **Certificates, Identifiers & Profiles → Profiles → ＋**。
2. 在 Distribution 選擇 **App Store Connect**。
3. 選擇此遊戲的 App ID。
4. 選擇上一節建立的 Apple Distribution 憑證。
5. 名稱可填入 `ADoubleB-AppStore`。
6. 產生並下載 `.mobileprovision`。

TestFlight 使用 App Store 發布用描述檔，不使用 Development 或 Ad Hoc 描述檔。記下描述檔名稱，後續會作為 `CodesignProvision`。

官方說明：[建立 App Store Connect 描述檔](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)。

## 6. 建立 App Store Connect API Key

此文件採用 Team API Key，因為會使用 Key ID、Issuer ID 與 `.p8`。

1. 到 App Store Connect 的 **使用者與存取權限 → 整合 → App Store Connect API**。
2. 若尚未開通，由 Account Holder 申請 API 存取權限。
3. 開啟 **Team Keys**，建立 API Key，名稱例如 `GitHub-ADoubleB-iOS`。
4. 若用途是上傳建置版本，可使用 **Developer** 角色；若未來自動處理更多發布操作，再依需求檢查角色權限。
5. 保存 **Key ID**、**Issuer ID** 與下載的 `AuthKey_XXXXXXXXXX.p8`。

API 私鑰只能下載一次。Team API Key 的權限涵蓋團隊的 App，不是僅限這個遊戲。

官方說明：[App Store Connect API 設定](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)。

## 7. 設定 GitHub Secrets

在 GitHub Repository 的 **Settings → Secrets and variables → Actions → Secrets → New repository secret** 逐一新增。

以下名稱是 iOS workflow 使用的名稱；新增 Secrets 本身不會執行部署。

| Name | Secret 內容 |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | `.p12` 檔案轉換後的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | 匯出 `.p12` 時設定的密碼 |
| `IOS_PROFILE_BASE64` | `.mobileprovision` 檔案轉換後的 Base64 |
| `IOS_KEYCHAIN_PASSWORD` | 自行設定的一組強密碼，用於 runner 暫時鑰匙圈，與 Apple 登入密碼無關 |
| `APP_STORE_CONNECT_KEY_ID` | API Key 的 Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Key 的 Issuer ID，與 Apple Team ID 不同 |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `.p8` 完整原文，包括 BEGIN／END PRIVATE KEY 行 |

在 Mac Terminal 執行以下指令，可直接將 Base64 放入剪貼簿。請把範例路徑替換成實際檔案位置；每次複製後先貼到對應 Secret，再執行下一個指令。

```bash
# 複製 P12 的 Base64，貼到 IOS_CERTIFICATE_BASE64。
base64 < "$HOME/Downloads/ADoubleB-distribution.p12" | tr -d '\n' | pbcopy

# 複製描述檔的 Base64，貼到 IOS_PROFILE_BASE64。
base64 < "$HOME/Downloads/ADoubleB-AppStore.mobileprovision" | tr -d '\n' | pbcopy

# 複製 P8 的完整原文，貼到 APP_STORE_CONNECT_PRIVATE_KEY。
pbcopy < "$HOME/Downloads/AuthKey_XXXXXXXXXX.p8"
```

不要把憑證私鑰、密碼或描述檔提交到 Git。runner 會在暫時鑰匙圈匯入憑證，建置後清除；Artifacts 只保存要交付的 IPA。

GitHub 官方流程：[在 macOS runner 安裝憑證與描述檔](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。

## 8. 建立符合專案的 iOS workflow

已建立 `.github/workflows/ios-testflight.yml`、`scripts/publish-ios.sh` 與 `scripts/ios-release.py`，目前設定如下：

- 使用 `macos-26` runner、Xcode `26.6`、.NET SDK `10.0.401` 與 workload set `10.0.401`，固定相容版本。
- 描述檔 UUID 與憑證 SHA-1 由描述檔解析，不需額外設定名稱。
- 建置編號為 `IOS_BUILD_NUMBER_BASE + github.run_number`。Repository variable `IOS_BUILD_NUMBER_BASE` 未設定時使用 `0`，第一次執行為 `1`。
- 如果 App Store Connect 已有建置，請在 GitHub Variables 設定起始值至少等於已使用的最大建置編號。本流程使用 1–9999 的整數編號。
- 同一次執行重跑會使用相同建置編號；若 Apple 已接受該編號，請使用新標籤觸發下一次執行。
- 使用 `xcrun altool` 與 API Key 上傳，不會自動送正式審核或新增 TestFlight 測試人員。

後續維護需確認：

- 使用 GitHub macOS runner，選擇符合 Apple 上傳要求、並與 .NET iOS workload 相容的 Xcode 版本；不要只依賴 runner 預設版本。
- 安裝 .NET 10 與 iOS workload，限定 `TargetFrameworks=net10.0-ios`，避免同時還原 Mac Catalyst 等其他平台。
- 驗證憑證、私鑰、描述檔的 Bundle ID、Team ID、期限與配對關係。
- 憑證與描述檔名稱可由檔案解析或用設定變數指定。
- 設定 `RuntimeIdentifier=ios-arm64`、`ArchiveOnBuild=true` 與 `BuildIpa=true`，產生已簽署 IPA。
- 隔離目前 csproj 的 Android Release 簽署設定與本機設定檔，避免 iOS 建置讀取 Android 設定。
- 版本名稱由 `ios-v1.0.0` 解析為 `1.0.0`；建置編號每次上傳必須符合 Apple 的遞增及唯一性要求，iOS 應使用自己的起始值與 workflow 執行次數。
- 使用 Apple 支援的上傳工具及 API Key 驗證，清理暫存私鑰、描述檔與鑰匙圈。

建置命令的概念如下，這不是已能直接執行的完整部署腳本；憑證與描述檔需先安裝，名稱也需換成實際值。

```bash
# 在已設定好簽署環境的 Mac／runner 建置，不會自行上傳。
dotnet publish ADoubleB/ADoubleB.csproj \
  -f net10.0-ios -c Release \
  -p:TargetFrameworks=net10.0-ios \
  -p:RuntimeIdentifier=ios-arm64 \
  -p:ArchiveOnBuild=true \
  -p:BuildIpa=true \
  -p:ApplicationDisplayVersion=1.0.0 \
  -p:ApplicationVersion=1 \
  '-p:CodesignKey=Apple Distribution: YOUR_NAME (YOUR_TEAM_ID)' \
  -p:CodesignProvision=ADoubleB-AppStore
```

Microsoft 文件：[MAUI iOS 命令列發布](https://learn.microsoft.com/en-us/dotnet/maui/ios/deployment/publish-cli?view=net-maui-10.0)。

## 9. Workflow 完成後才推送版本標籤

先把實際的 iOS workflow 與程式變更 commit／push，再標記要發布的 commit：

```bash
# 只在 iOS workflow 已建立並完成設定後執行。
git tag ios-v1.0.0
git push origin ios-v1.0.0
```

Android 現有流程使用 `android-v*`；iOS 預定使用 `ios-v*`，兩者各自觸發。一般 commit 或推送 master 不會觸發現有 Android 發布。

## 10. 上傳後使用 TestFlight

1. 在 GitHub Actions 確认建置與上傳成功。
2. 等待 Apple 處理，再到 App Store Connect 的 App → TestFlight 查看建置版本。
3. 完成出口合規等必要問題；若目前遊戲只使用系統功能，仍應依實際加密用途回答，不能直接假設答案。
4. 建立內部測試群組，加入具備適當 App Store Connect 權限的測試者，並將建置加入群組，或設定自動分發。
5. 測試者在 iPhone／iPad 安裝 TestFlight 後接受邀請。
6. 若邀請沒有 App Store Connect 存取權的外部測試者，改用外部測試；首個外部測試建置通常需要 Beta App Review。
7. 正式上架時，另外填寫版本資料、截圖、隱私權與年齡分級，選擇建置並提交 App Review。

上傳成功不等於測試者立即可用，也不等於正式上架。

Apple 文件：[上傳建置](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)／[TestFlight 概觀](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

## 常見問題

| 問題 | 優先檢查 |
| --- | --- |
| 找不到簽署身分 | P12 是否含私鑰、密碼是否正確、runner 是否成功匯入並解鎖鑰匙圈 |
| 找不到或無法使用描述檔 | Bundle ID、團隊、憑證是否匹配，以及描述檔是否過期 |
| Xcode／SDK 不相容 | .NET iOS workload 要求的 Xcode 版本，以及 Apple 當下上傳要求 |
| App Store Connect 找不到 App | App 是否已建立、Bundle ID 是否相同、API Key 是否有權限 |
| 建置編號重複 | 選擇新的編號與標籤；不要重跑已被 Apple 接受的相同建置編號 |
| 上傳完成但 TestFlight 沒出現 | 等待 Apple 處理，檢查通知、錯誤與合規問題 |

文件建立日期：2026 年 10 月 5 日。Apple 的選單與 SDK 要求可能變更，實際建立 workflow 時需再次核對官方文件。
