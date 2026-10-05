#!/usr/bin/env bash
# 匯入臨時簽署身分，產生 IPA；上傳由 workflow 的獨立步驟負責。
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'iOS 建置必須在 macOS 執行。' >&2; exit 1; }
: "${IOS_VERSION_NAME:?缺少版本名稱}" "${IOS_BUILD_NUMBER:?缺少建置編號}"
: "${IOS_CERTIFICATE_BASE64:?}" "${IOS_CERTIFICATE_PASSWORD:?}" "${IOS_PROFILE_BASE64:?}" "${IOS_KEYCHAIN_PASSWORD:?}"
signing_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/adoubleb-signing.XXXXXX")
keychain="$signing_dir/signing.keychain-db"
installed_profile=''
installed_legacy_profile=''
# 保留既有鑰匙圈清單，退出時恢復。
security list-keychains -d user > "$signing_dir/original-keychains.txt"
cleanup() {
  if [[ -n "$installed_profile" ]]; then rm -f -- "$installed_profile"; fi
  if [[ -n "$installed_legacy_profile" ]]; then rm -f -- "$installed_legacy_profile"; fi
  python3 - "$signing_dir/original-keychains.txt" <<'PY'
import pathlib, shlex, subprocess, sys
subprocess.run(["security", "list-keychains", "-d", "user", "-s", *shlex.split(pathlib.Path(sys.argv[1]).read_text())], check=False)
PY
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf -- "$signing_dir"
}
trap cleanup EXIT
# 使用 Python 解碼避免 macOS／Linux base64 參數差異。
python3 - "$signing_dir" <<'PY'
import base64, os, pathlib, sys
folder = pathlib.Path(sys.argv[1])
for name, filename in [("IOS_CERTIFICATE_BASE64", "certificate.p12"), ("IOS_PROFILE_BASE64", "profile.mobileprovision")]:
    folder.joinpath(filename).write_bytes(base64.b64decode("".join(os.environ[name].split()), validate=True))
PY
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
python3 scripts/ios-release.py profile "$signing_dir/profile.plist" "$signing_dir/profile.json"
profile_uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' "$signing_dir/profile.json")
identity=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["identity"])' "$signing_dir/profile.json")
security create-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$keychain"
security import "$signing_dir/certificate.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$IOS_KEYCHAIN_PASSWORD" "$keychain" >/dev/null
python3 - "$keychain" "$signing_dir/original-keychains.txt" <<'PY'
import pathlib, shlex, subprocess, sys
subprocess.run(["security", "list-keychains", "-d", "user", "-s", sys.argv[1], *shlex.split(pathlib.Path(sys.argv[2]).read_text())], check=True)
PY
security find-identity -v -p codesigning "$keychain" | grep -F "$identity" >/dev/null || { echo '憑證私鑰與描述檔不匹配，或憑證無效。' >&2; exit 1; }
# Xcode 16+ 使用的新描述檔路徑。
profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_dir"
[[ ! -e "$profile_dir/$profile_uuid.mobileprovision" ]] || { echo '描述檔已存在，請使用乾淨的 runner。' >&2; exit 1; }
installed_profile="$profile_dir/$profile_uuid.mobileprovision"
cp "$signing_dir/profile.mobileprovision" "$installed_profile"
# 同時提供 .NET 簽署工具可能使用的舊路徑。
legacy_profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$legacy_profile_dir"
[[ ! -e "$legacy_profile_dir/$profile_uuid.mobileprovision" ]] || { echo '舊路徑描述檔已存在，請使用乾淨的 runner。' >&2; exit 1; }
installed_legacy_profile="$legacy_profile_dir/$profile_uuid.mobileprovision"
cp "$signing_dir/profile.mobileprovision" "$installed_legacy_profile"
dotnet publish ADoubleB/ADoubleB.csproj -f net10.0-ios -c Release \
  -p:TargetFrameworks=net10.0-ios -p:RuntimeIdentifier=ios-arm64 \
  -p:ArchiveOnBuild=true -p:BuildIpa=true \
  "-p:ApplicationDisplayVersion=$IOS_VERSION_NAME" "-p:ApplicationVersion=$IOS_BUILD_NUMBER" \
  "-p:CodesignKey=$identity" "-p:CodesignProvision=$profile_uuid" "-p:CodesignKeychain=$keychain" \
  -o "$signing_dir/publish"
# 只保存一份 IPA，金鑰與其他建置檔案不會加入 Artifact。
python3 - "$signing_dir/publish" <<'PY'
import pathlib, shutil, sys
files = list(pathlib.Path(sys.argv[1]).glob("*.ipa"))
if len(files) != 1:
    sys.exit(f"預期一份 IPA，實際找到 {len(files)} 份。")
pathlib.Path("artifacts").mkdir(exist_ok=True)
shutil.copyfile(files[0], "artifacts/ios-release.ipa")
PY
