# Releasing BugHive (GitHub Releases)

This app is distributed as a signed Android APK attached to a GitHub Release
(not the Play Store). Follow the one-time setup once, then the per-release
steps for every version you ship.

---

## One-time setup: create your signing keystore

Android requires every APK to be signed. **App updates only install if signed
with the same key**, so create ONE keystore, back it up, and reuse it forever.
If you lose it, users can never update in place — they'd have to uninstall and
reinstall (losing their local session).

### 1. Generate the keystore

`keytool` ships with the JDK. If it's not on your PATH, use the one bundled with
Android Studio, e.g.:
`"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"`

Run this once (from any folder — keep the output file OUTSIDE the repo, e.g. in
your user folder):

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It will prompt for:
- A **keystore password** and a **key password** (can be the same — remember them).
- Name / org / location — fill anything reasonable; it isn't shown to users.

This produces `upload-keystore.jks`. **Back this file up** (password manager,
private cloud). It is NOT in git and cannot be regenerated.

### 2. Point the build at it

Copy the template and fill in your values:

```bash
cp android/key.properties.example android/key.properties
```

Edit `android/key.properties`:

```properties
storePassword=<your keystore password>
keyPassword=<your key password>
keyAlias=upload
storeFile=C:/Users/Rafi/upload-keystore.jks
```

> `key.properties`, `*.jks`, and `*.keystore` are gitignored — never commit them.
> The build automatically uses this keystore when `android/key.properties` exists,
> and falls back to debug signing when it doesn't.

---

## Per-release steps

### 1. Bump the version

In `pubspec.yaml`, increase `version`. The number after `+` (the Android
versionCode) **must go up every release**:

```yaml
version: 1.0.1+2   # was 1.0.0+1  -> name 1.0.1, versionCode 2
```

### 2. Make sure `.env` is set to production

`.env` lives only on your machine (it's gitignored) and holds your keys. Confirm:

```
APP_ENV="production"
APP_DEBUG=false
```

> **Do NOT commit `.env` or remove it from `.gitignore`.** The APK reads the
> compiled `lib/bootstrap/env.g.dart`, not `.env`. `.env` just needs to exist on
> the build machine so the next step can regenerate that file.

### 3. Regenerate the encrypted env, then build

```bash
dart run nylo_framework:main make:env
flutter build apk --release --split-per-abi
```

Output APKs land in `build/app/outputs/flutter-apk/`:

| File | For |
| --- | --- |
| `app-arm64-v8a-release.apk` (~22 MB) | **All modern phones — ship this** |
| `app-armeabi-v7a-release.apk` (~20 MB) | Older 32-bit devices (optional) |
| `app-x86_64-release.apk` (~24 MB) | Emulators / x86 (usually skip) |

### 4. Verify the build is properly signed

```bash
# should print the SHA-256 of YOUR "upload" key, not "androiddebugkey"
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### 5. Smoke-test on a real device

Install the arm64 APK and check the critical paths:
- GitHub login returns to the app (deep link `bughive://auth-callback`)
- Add a repo that has **closed** issues (imports without error)
- Create + sync a log, mark it finished, delete a log
- Delete account flow

### 6. Publish the GitHub Release

```bash
git tag v1.0.1
git push origin v1.0.1
```

Then on GitHub → Releases → **Draft a new release** → pick the tag → attach
`app-arm64-v8a-release.apk` (and the armeabi-v7a one if you support old
devices) → publish.

> Tip: users must enable "Install from unknown sources" to sideload a GitHub
> APK. Mention this in the release notes.

---

## Updating the app icon (reference)

The launcher icon is generated from `assets/app_icon/icon.png`. After replacing
that file, regenerate the platform icons:

```bash
dart run flutter_launcher_icons
```

Then rebuild. (Android caches launcher icons — a fresh install shows the new one.)

---

## Quick reference

```bash
# one time
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties   # then edit it

# every release
# 1. bump version in pubspec.yaml
# 2. confirm .env has APP_ENV=production
dart run nylo_framework:main make:env
flutter build apk --release --split-per-abi
# 3. attach build/app/outputs/flutter-apk/app-arm64-v8a-release.apk to a GitHub Release
```
