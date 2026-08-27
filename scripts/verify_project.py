from __future__ import annotations

import json
import plistlib
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = [
    ".gitattributes",
    "LICENSE",
    "project.yml",
    ".github/workflows/build.yml",
    "HarborIOS/Info.plist",
    "HarborIOS/HarborIOSApp.swift",
    "HarborIOS/AppEnvironment.swift",
    "HarborIOS/RootView.swift",
    "HarborIOS/Resources/LaunchScreen.storyboard",
    "HarborIOS/Resources/PrivacyInfo.xcprivacy",
    "HarborIOS/Assets.xcassets/Contents.json",
    "HarborIOS/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "HarborIOS/Assets.xcassets/AppIcon.appiconset/HarborIcon.png",
    "Domain/Models/StremioModels.swift",
    "Domain/Models/DebridModels.swift",
    "Domain/Networking/StremioEndpoint.swift",
    "Domain/Services/DebridServicing.swift",
    "Domain/Services/StremioServicing.swift",
    "Data/Debrid/RealDebridClient.swift",
    "Data/Stremio/StremioAPIClient.swift",
    "Features/Home/HomeView.swift",
    "Features/Details/ContentDetailView.swift",
    "Features/Player/HarborPlayerView.swift",
    "Features/Player/MPVPlaybackViewController.swift",
    "Features/Player/MetalLayer.swift",
    "Features/Settings/SettingsView.swift",
    "HarborIOSTests/StremioStreamTests.swift",
    "HarborIOSTests/StremioManifestTests.swift",
    "HarborIOSTests/AddonPersistenceStateTests.swift",
    "HarborIOSTests/ContentDetailViewModelTests.swift",
    "HarborIOSTests/DebridResolverTests.swift",
    "HarborIOSTests/HomeViewModelTests.swift",
]


def fail(message: str) -> None:
    raise AssertionError(message)


def png_info(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()[:26]
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        fail(f"Not a PNG: {path}")
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    return width, height, color_type


def main() -> int:
    missing = [path for path in REQUIRED_FILES if not (ROOT / path).is_file()]
    if missing:
        fail("Missing files: " + ", ".join(missing))

    for path in ROOT.rglob("*.json"):
        json.loads(path.read_text(encoding="utf-8"))

    info = plistlib.load(open(ROOT / "HarborIOS/Info.plist", "rb"))
    privacy = plistlib.load(open(ROOT / "HarborIOS/Resources/PrivacyInfo.xcprivacy", "rb"))
    if info.get("UILaunchStoryboardName") != "LaunchScreen":
        fail("Info.plist must reference LaunchScreen.storyboard")
    if info.get("UIRequiresFullScreen") is not True:
        fail("UIRequiresFullScreen must be true")
    capabilities = set(info.get("UIRequiredDeviceCapabilities", []))
    if not {"arm64", "metal"}.issubset(capabilities):
        fail("Info.plist must require arm64 and metal")
    if "UIApplicationSceneManifest" in info or "UILaunchScreen" in info:
        fail("Legacy scene/launch dictionaries conflict with the launch storyboard")
    ats = info.get("NSAppTransportSecurity", {})
    if ats.get("NSAllowsArbitraryLoads") or ats.get("NSAllowsArbitraryLoadsForMedia"):
        fail("Arbitrary HTTP transport is forbidden")
    if privacy.get("NSPrivacyTracking") is not False:
        fail("Privacy manifest must declare tracking=false")

    storyboard = ROOT / "HarborIOS/Resources/LaunchScreen.storyboard"
    launch_root = ET.parse(storyboard).getroot()
    device = launch_root.find("device")
    if device is None or device.attrib.get("id") != "retina6_12":
        fail("Launch storyboard must target the modern retina6_12 marker")

    icon = ROOT / "HarborIOS/Assets.xcassets/AppIcon.appiconset/HarborIcon.png"
    width, height, color_type = png_info(icon)
    if (width, height) != (1024, 1024):
        fail(f"App icon is {width}x{height}, expected 1024x1024")
    if color_type not in {0, 2, 3}:
        fail("App icon contains an alpha channel")

    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
    keychain = (ROOT / "Data/Persistence/KeychainStore.swift").read_text(encoding="utf-8")
    player = (ROOT / "Features/Player/HarborPlayerView.swift").read_text(encoding="utf-8")
    mpv_player = (ROOT / "Features/Player/MPVPlaybackViewController.swift").read_text(encoding="utf-8")
    debrid_client = (ROOT / "Data/Debrid/RealDebridClient.swift").read_text(encoding="utf-8")
    for token in ('iOS: "17.0"', 'SWIFT_VERSION: "5.0"', "CODE_SIGNING_ALLOWED: \"NO\""):
        if token not in project:
            fail(f"project.yml missing {token}")
    if "TEST_HOST" not in project or "Harbor.app/Harbor" not in project:
        fail("Test host must point at the Harbor.app bundle (PRODUCT_NAME Harbor)")
    if "runs-on: macos-15" not in workflow:
        fail("CI must use macos-15")
    if "xcodebuild" not in workflow or "HarborIOS.ipa" not in workflow:
        fail("CI must test/build/package the IPA")
    if "permissions:\n  contents: read" not in workflow:
        fail("CI permissions must be read-only")
    if "codesign --force --sign -" not in workflow or "application-identifier" not in workflow:
        fail("CI must fake-sign the bundle with the application-identifier entitlement")
    if "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" not in keychain:
        fail("Keychain items must require an unlocked device")
    if "AVURLAssetHTTPHeaderFieldsKey" in player or "AVURLAssetHTTPHeaderFieldsKey" in mpv_player:
        fail("Unsupported AVURLAsset header injection must not be used")
    if "mpv_create" not in mpv_player or "moltenvk" not in mpv_player:
        fail("Player must initialize libmpv with the MoltenVK video path")
    if "MPVPlaybackSnapshot" not in mpv_player:
        fail("Player must poll mpv state into MPVPlaybackSnapshot")
    if "NuvioMedia/MPVKit" not in project:
        fail("project.yml must depend on the NuvioMedia MPVKit package")
    if "api.real-debrid.com/rest/1.0" not in debrid_client or "addMagnet" not in debrid_client:
        fail("Real-Debrid client must target the /rest/1.0 API with the addMagnet flow")

    swift_files = list(ROOT.rglob("*.swift"))
    test_files = list((ROOT / "HarborIOSTests").glob("*.swift"))
    if len(swift_files) < 24 or len(test_files) < 6:
        fail("Expected at least 24 Swift files and 6 test files")

    print(f"PASS required_files={len(REQUIRED_FILES)} swift_files={len(swift_files)} tests={len(test_files)}")
    print("PASS plists json storyboard app-icon project workflow")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        raise SystemExit(1)
