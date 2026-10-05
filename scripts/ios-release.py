"""驗證 iOS 發布標籤與描述檔；僅使用 Python 標準函式庫。"""
import datetime
import hashlib
import json
import os
import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET


def metadata():
    """驗證必要 Secrets，並輸出版號供後續步驟使用。"""
    tag = os.environ.get("RELEASE_TAG", "")
    if not re.fullmatch(r"ios-v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag):
        raise ValueError("標籤必須是 ios-v1.0.0 這類格式。")
    version = tag.removeprefix("ios-v")
    # Apple 三段版本的第一段最多四位，其餘兩段最多兩位。
    components = version.split(".")
    if int(components[0]) == 0 or any(len(v) > limit for v, limit in zip(components, (4, 2, 2))):
        raise ValueError("iOS 版本第一段須大於零，三段最多分別為 4、2、2 位。")
    base, run = os.environ.get("BUILD_BASE", "0"), os.environ.get("RUN_NUMBER", "")
    if not re.fullmatch(r"\d+", base) or not re.fullmatch(r"[1-9]\d*", run):
        raise ValueError("建置編號起始值須為非負整數。")
    build = int(base) + int(run)
    # 使用整數編號，符合 CFBundleVersion 第一段最多四位的限制。
    if not 1 <= build <= 9999:
        raise ValueError("iOS 建置編號超出可用範圍。")
    build_number = str(build)
    required = ("IOS_CERTIFICATE_BASE64", "IOS_CERTIFICATE_PASSWORD", "IOS_PROFILE_BASE64",
                "IOS_KEYCHAIN_PASSWORD", "APP_STORE_CONNECT_KEY_ID",
                "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_PRIVATE_KEY")
    for name in required:
        if not os.environ.get(name):
            raise ValueError(f"缺少 Secret：{name}")
    if not re.fullmatch(r"[A-Za-z0-9]+", os.environ["APP_STORE_CONNECT_KEY_ID"]):
        raise ValueError("API Key ID 格式不正確。")
    if "-----BEGIN PRIVATE KEY-----" not in os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]:
        raise ValueError("API 私鑰必須是 P8 完整原文。")
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        output.write(f"IOS_VERSION_NAME={version}\nIOS_BUILD_NUMBER={build_number}\n")
    print(f"版本：{version}；建置編號：{build_number}")


def profile(source, destination):
    """確認描述檔用途、期限與 Bundle ID，輸出簽署用資訊。"""
    with open(source, "rb") as stream:
        data = plistlib.load(stream)
    root = ET.parse("ADoubleB/ADoubleB.csproj").getroot()
    bundle_id = root.findtext("PropertyGroup/ApplicationId")
    entitlements = data["Entitlements"]
    prefix = data["ApplicationIdentifierPrefix"][0]
    if entitlements.get("application-identifier") != f"{prefix}.{bundle_id}":
        raise ValueError(f"描述檔必須對應專案 Bundle ID：{bundle_id}")
    if data["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("描述檔已過期。")
    if data.get("ProvisionedDevices") or data.get("ProvisionsAllDevices") or entitlements.get("get-task-allow"):
        raise ValueError("請使用 App Store Connect 發布描述檔。")
    certificate = data["DeveloperCertificates"][0]
    result = {"uuid": data["UUID"], "identity": hashlib.sha1(certificate).hexdigest().upper()}
    if not re.fullmatch(r"[A-Fa-f0-9-]+", result["uuid"]):
        raise ValueError("描述檔 UUID 格式錯誤。")
    pathlib.Path(destination).write_text(json.dumps(result), encoding="utf-8")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["metadata"]:
            metadata()
        elif len(sys.argv) == 4 and sys.argv[1] == "profile":
            profile(sys.argv[2], sys.argv[3])
        else:
            raise ValueError("用法：ios-release.py metadata 或 profile 輸入.plist 輸出.json")
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
