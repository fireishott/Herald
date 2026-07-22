# Herald TestFlight Release Pipeline — Mimo Handoff

**For:** Mimo (via Claude Code on MBP)
**Last updated:** 2026-07-21 (post 1.8.0 release)
**Current state:** v1.8.0 build 43 shipped to GitHub. Build 42 on ASC is 1.7.6. Next release uses next unused build number.

---

## 1. Environment & Access

### MBP (Build Host)
```
Host:     192.168.10.121
User:     curtisfreeman
Password: 11aaxx2wR
Project:  ~/Herald/
SSH:      sshpass -p '11aaxx2wR' ssh -o StrictHostKeyChecking=no curtisfreeman@192.168.10.121
```

### GitHub
```
Repo:     https://github.com/fireishott/Herald
Username: fireishott
Token:    Stored in macOS keychain. Extract with:
          security unlock-keychain -p '11aaxx2wR' ~/Library/Keychains/login.keychain-db 2>/dev/null
          security find-internet-password -s github.com -a fireishott -w 2>/dev/null

Fallback: Token also in Flynt Hermes profile at fih-ai-host:
          GH_CONFIG_DIR=/home/fihadmin/.hermes/profiles/flynt/home/.config/gh gh auth token
```

### App Store Connect API Keys (MBP)
```
Location:  ~/.appstoreconnect/private_keys/
  AuthKey_32NT26772F.p8  → App Manager role (for uploads, builds)
  AuthKey_UQWH2GWTLU.p8  → Admin role (full access, tester management)
  AuthKey_LH5GM8356P.p8  → APNs push only — NOT for ASC (do not use for uploads)

Issuer ID: 69a6de93-5191-47e3-e053-5b8c7c11a4d1
App ID:    6792659019 (Herald Companion)
Bundle ID: net.fihonline.herald
Team ID:   58U7UPFS53 (C Freeman)
Account:   djkurttsaynomore@gmail.com
```

### Apple Signing (Keychain)
```
Identity:  Apple Development: C Freeman (UU4BX97G8J)
Team:      58U7UPFS53
Keychain:  ~/Library/Keychains/login.keychain-db
Password:  11aaxx2wR

Unlock (required before any archive/export):
  security unlock-keychain -p '11aaxx2wR' ~/Library/Keychains/login.keychain-db
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '11aaxx2wR' ~/Library/Keychains/login.keychain-db
```

---

## 2. Pre-Flight Checklist

Run these BEFORE starting any build:

```bash
# 1. Verify MBP is reachable
sshpass -p '11aaxx2wR' ssh curtisfreeman@192.168.10.121 "echo connected"

# 2. Check GitHub for latest commits — local clone may be behind
curl -s "https://api.github.com/repos/fireishott/Herald/commits?per_page=5" | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    print(c['sha'][:7], c['commit']['message'].split(chr(10))[0])
"

# 3. Pull latest on MBP
ssh MBP "cd ~/Herald && git fetch origin && git rev-list --count master..origin/master"
# If >0: git pull origin master

# 4. Check current version/build in project.yml
ssh MBP "cd ~/Herald && grep -n 'MARKETING_VERSION\|CURRENT_PROJECT_VERSION' project.yml"

# 5. Determine next unused build number on ASC
# Query: https://api.appstoreconnect.apple.com/v1/apps/6792659019/builds
# OR check manually at appstoreconnect.apple.com → Herald → TestFlight → Builds
```

---

## 3. Version & Build Bump

**CRITICAL: Always check ASC for the latest build number first. Never reuse a build number.**

```bash
# Bump in project.yml (both app AND widget targets — 2 instances each)
ssh MBP "cd ~/Herald && python3 << 'PYEOF'
with open('project.yml', 'r') as f:
    content = f.read()

# Change version
content = content.replace('MARKETING_VERSION: \"1.8.0\"', 'MARKETING_VERSION: \"1.9.0\"')
# Change build
content = content.replace('CURRENT_PROJECT_VERSION: \"43\"', 'CURRENT_PROJECT_VERSION: \"44\"')

with open('project.yml', 'w') as f:
    f.write(content)
print('Bumped to 1.9.0 build 44')
PYEOF"

# Verify
ssh MBP "cd ~/Herald && grep -n 'MARKETING_VERSION\|CURRENT_PROJECT_VERSION' project.yml"

# Commit
ssh MBP "cd ~/Herald && git add project.yml && git commit -m 'chore: bump to X.Y.Z build N'"
```

---

## 4. Build & Export IPA

**CRITICAL: Archive + export MUST run in a SINGLE SSH call.** Keychain re-locks between sessions.

### Step 1: Write ExportOptions.plist

```bash
ssh MBP "mkdir -p ~/Hermes-iOS-Builds/exports && cat > /tmp/ExportOptions.plist << 'XEOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>58U7UPFS53</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
XEOF"
```

### Step 2: Strip entitlements (App Store profiles lack App Groups/HealthKit)

```bash
ssh MBP "cd ~/Herald && python3 << 'PYEOF'
import plistlib
for p in ['Herald/Herald.entitlements', 'HeraldWidgets/HeraldWidgets.entitlements']:
    with open(p, 'wb') as f:
        plistlib.dump({}, f)
    print(f'Stripped: {p}')
PYEOF"
```

### Step 3: Patch Info.plist (Apple validation requirements)

```bash
ssh MBP "cd ~/Herald && python3 << 'PYEOF'
import plistlib

# Main Info.plist
with open('Herald/Resources/Info.plist', 'rb') as f:
    m = plistlib.load(f)
m['CFBundleDisplayName'] = 'Herald Companion'
m['ITSAppUsesNonExemptEncryption'] = False
m['UISupportedInterfaceOrientations'] = [
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight'
]
m['UISupportedInterfaceOrientations~ipad'] = [
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight'
]
m['BGTaskSchedulerPermittedIdentifiers'] = [
    'net.fihonline.herald.task.refresh',
    'net.fihonline.herald.task.processing'
]
with open('Herald/Resources/Info.plist', 'wb') as f:
    plistlib.dump(m, f)

# Widget Info.plist
with open('HeraldWidgets/Info.plist', 'rb') as f:
    w = plistlib.load(f)
w['CFBundleDisplayName'] = 'Herald Widgets'
with open('HeraldWidgets/Info.plist', 'wb') as f:
    plistlib.dump(w, f)

print('Info.plists patched')
PYEOF"
```

### Step 4: Archive + Export (SINGLE SSH CALL)

```bash
# Write build script
cat > /tmp/herald_build.sh << 'SCRIPT'
#!/bin/bash
set -e

# Unlock keychain (suppress dump noise)
exec 2>/dev/null
security unlock-keychain -p '11aaxx2wR' ~/Library/Keychains/login.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '11aaxx2wR' ~/Library/Keychains/login.keychain-db
exec 2>&1

cd ~/Herald
rm -rf ~/Library/Developer/Xcode/DerivedData/Herald-*
rm -rf ~/Hermes-iOS-Builds/archives/Herald.xcarchive
rm -rf ~/Hermes-iOS-Builds/exports/Herald.ipa

echo "=== ARCHIVING ==="
xcodebuild -project Herald.xcodeproj -scheme Herald \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath ~/Hermes-iOS-Builds/archives/Herald.xcarchive \
  -allowProvisioningUpdates archive 2>&1 | tail -5

echo "=== EXPORTING ==="
xcodebuild -exportArchive \
  -archivePath ~/Hermes-iOS-Builds/archives/Herald.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -exportPath ~/Hermes-iOS-Builds/exports \
  -allowProvisioningUpdates 2>&1 | tail -5

echo "=== DONE ==="
ls -lh ~/Hermes-iOS-Builds/exports/Herald.ipa

# Verify entitlements in exported app
echo "=== ENTITLEMENTS ==="
codesign -d --entitlements - ~/Hermes-iOS-Builds/exports/Herald.ipa 2>/dev/null | grep -A5 'aps-environment\|application-identifier' | head -10
SCRIPT

# SCP and run
sshpass -p '11aaxx2wR' scp /tmp/herald_build.sh curtisfreeman@192.168.10.121:~/Hermes-iOS-Builds/
sshpass -p '11aaxx2wR' ssh -o StrictHostKeyChecking=no curtisfreeman@192.168.10.121 \
  'bash ~/Hermes-iOS-Builds/herald_build.sh'
```

### Step 5: Restore entitlements + Info.plist

```bash
ssh MBP "cd ~/Herald && git checkout -- Herald/Herald.entitlements HeraldWidgets/HeraldWidgets.entitlements Herald/Resources/Info.plist HeraldWidgets/Info.plist"
```

---

## 5. Upload to TestFlight

### Method: altool (CLI — RECOMMENDED)

```bash
sshpass -p '11aaxx2wR' ssh -o StrictHostKeyChecking=no curtisfreeman@192.168.10.121 \
  "xcrun altool --upload-app \
    --type ios \
    --file ~/Hermes-iOS-Builds/exports/Herald.ipa \
    --apiKey 32NT26772F \
    --apiIssuer 69a6de93-5191-47e3-e053-5b8c7c11a4d1"
```

Wait for `"No errors uploading"` and note the delivery UUID.

### Processing

- Build appears in TestFlight after 5–30 minutes
- Monitor: `https://api.appstoreconnect.apple.com/v1/apps/6792659019/builds`
- Wait for `processingState: VALID` before adding testers

---

## 6. TestFlight Tester Management

### Current Testers
```
Mark (markbdvt@gmail.com)
Mini Me (curtisdate@icloud.com)
```

### Add tester to build (via ASC API — Admin key)

```python
import jwt, time, requests

token = jwt.encode(
    {"iss": "69a6de93-5191-47e3-e053-5b8c7c11a4d1", "exp": int(time.time())+1200, "aud": "appstoreconnect-v1"},
    open("AuthKey_UQWH2GWTLU.p8").read(), algorithm="ES256",
    headers={"alg": "ES256", "kid": "UQWH2GWTLU", "typ": "JWT"}
)

headers = {"Authorization": f"Bearer {token}"}

# Add tester linked to build
payload = {
    "data": {
        "type": "betaTesters",
        "attributes": {
            "email": "tester@gmail.com",
            "firstName": "First",
            "lastName": "Last"
        },
        "relationships": {
            "builds": {
                "data": [{"id": "BUILD_ID", "type": "builds"}]
            }
        }
    }
}
r = requests.post("https://api.appstoreconnect.apple.com/v1/betaTesters", headers=headers, json=payload)
print(r.status_code, r.json())
```

---

## 7. GitHub: Tag + Release

### Push commits (if needed)

```bash
# From MBP (if keychain unlocked):
ssh MBP "cd ~/Herald && git push origin master"

# OR from fih-ai-host using Flynt profile token:
TOKEN=$(GH_CONFIG_DIR=/home/fihadmin/.hermes/profiles/flynt/home/.config/gh gh auth token 2>/dev/null)
cd /tmp/Herald-clone && git push "https://fireishott:${TOKEN}@github.com/fireishott/Herald.git" master
```

### Create tag

```bash
TOKEN=$(GH_CONFIG_DIR=/home/fihadmin/.hermes/profiles/flynt/home/.config/gh gh auth token 2>/dev/null)

# Clone fresh
cd /tmp && rm -rf Herald-release && git clone https://github.com/fireishott/Herald.git Herald-release
cd Herald-release
git config user.email "freemancurtisd@gmail.com"
git config user.name "Curtis Freeman"

# Tag and push
git tag -a vX.Y.Z -m "Herald vX.Y.Z — <one-line summary>"
git push "https://fireishott:${TOKEN}@github.com/fireishott/Herald.git" vX.Y.Z
```

### Create release

```bash
TOKEN=$(GH_CONFIG_DIR=/home/fihadmin/.hermes/profiles/flynt/home/.config/gh gh auth token 2>/dev/null)

curl -s -X POST \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/fireishott/Herald/releases \
  -d '{
    "tag_name": "vX.Y.Z",
    "name": "Herald vX.Y.Z — <title>",
    "body": "<changelog in markdown>",
    "draft": false,
    "prerelease": false
  }'
```

---

## 8. CHANGELOG.md Format

Each release section follows this structure:

```markdown
## [X.Y.Z] - YYYY-MM-DD

Brief summary paragraph.

### Added
- New features

### Fixed
- Bug fixes

### Changed
- Behavioral changes

### Known Limitations
- Documented gaps

### Operational Notes
- Deployment order, compatibility requirements
```

---

## 9. Common Pitfalls

| Issue | Fix |
|---|---|
| `errSecInternalComponent` during export | Keychain re-locked. Run archive+export in ONE SSH call. |
| Build number collision on ASC | Check ASC builds before bumping. Never reuse a number. |
| Entitlements mismatch (App Groups/HealthKit) | Strip entitlements before App Store build. Restore after. |
| `CFBundleDisplayName` missing (90360) | Patch Info.plist before archiving. |
| `UISupportedInterfaceOrientations` missing (90474) | Patch Info.plist before archiving. |
| `BGTaskSchedulerPermittedIdentifiers` missing (90771) | Patch Info.plist before archiving. |
| ASC API 403 on app creation | Apple doesn't expose app creation via API. Manual only. |
| APNs key used for ASC upload (401) | Use ASC API key, not APNs key. Different portal pages. |
| `security find-internet-password` returns empty | Keychain locked. Run `security unlock-keychain` first in same shell. |
| `git push` fails "Device not configured" | Keychain requires GUI. Use token from Flynt profile instead. |
| `sed` corrupts project.yml | Use Python scripts for file edits, never sed. |
| Build doesn't appear in TestFlight | Wait up to 30 min. Check export compliance. |

---

## 10. Quick Reference Card

```
┌─────────────────────────────────────────────────────────┐
│                 HERALD TESTFLIGHT PIPELINE               │
├─────────────────────────────────────────────────────────┤
│ MBP SSH:    curtisfreeman@192.168.10.121 / 11aaxx2wR    │
│ Project:    ~/Herald/                                    │
│ GitHub:     fireishott/Herald                            │
│ ASC App:    Herald Companion (6792659019)                │
│ Bundle:     net.fihonline.herald                         │
│ Team:       58U7UPFS53 (C Freeman)                       │
│ Signing:    Apple Development: C Freeman (UU4BX97G8J)    │
│ ASC Key:    ~/.appstoreconnect/private_keys/             │
│              AuthKey_32NT26772F.p8 (App Manager)         │
│              AuthKey_UQWH2GWTLU.p8 (Admin)               │
│ Issuer:     69a6de93-5191-47e3-e053-5b8c7c11a4d1         │
│ GH Token:   Flynt profile on fih-ai-host                 │
│             /home/fihadmin/.hermes/profiles/flynt/       │
│             home/.config/gh (user: fireishott)           │
├─────────────────────────────────────────────────────────┤
│ FLOW:                                                    │
│ 1. Pull latest → 2. Bump version/build → 3. Commit       │
│ 4. Strip entitlements → 5. Patch Info.plist              │
│ 6. Archive + Export (ONE SSH call) → 7. Restore files    │
│ 8. altool upload → 9. Wait processing → 10. GH release   │
└─────────────────────────────────────────────────────────┘
```
