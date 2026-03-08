# Pocket Provisioner v0.0.4 *(Alpha)*

> ⚠️ **This is an early alpha release.** Versions will stay in the `0.0.x` range while the app is actively being developed. Expect frequent revisions and breaking changes between releases.

**Pocket Provisioner** is a mobile field utility for Telecommunications Technicians. It turns an Android/iOS device into a temporary **Provisioning Server**, allowing for rapid deployment of VoIP handsets (Yealink, Polycom, Cisco) without needing a laptop or complex on-site infrastructure.

## 🚀 Core Features

* **Server Hop Architecture:** Provisions a handset with local settings (Wallpaper, Buttons) and then automatically hands it off to your production **DMS / EPM** (Endpoint Manager).
* **Smart CSV Import:** Automatically detects Carrier/Broadworks headers and generic exports.
* **Auto-Advance Scanning:** Rapidly map MAC addresses to Extensions using the camera.
* **Smart Wallpaper Tool:** Pick any image from your gallery; the app auto-resizes and formats it for the specific handset model (e.g., Yealink T54W) and hosts it locally.
* **Button Layout Editor:** Configure BLF, Speed Dial, and Line keys before the phone even boots.

---

## 🛠 Usage Workflow

### 1. Categorized Settings
Tap the **Gear Icon [⚙]** to configure your job environment using the new categorized layout:

* **Network & SIP:**
    * **Primary SIP Server:** Leave Blank for Cloud/DMS jobs. Enter IP (e.g., `192.168.1.10`) for manual On-Premise PBX jobs.
    * **Voice VLAN ID:** Configure the network VLAN for voice traffic.
* **Preferences:**
    * Configure **NTP Server**, **Timezone Offset**, and **Default Ringtone**.
    * **Wallpaper Source:** Use the **Smart Tool [🪄]** to pick an image. It auto-resizes for your models.
    * **Carry-Over Settings:** Enable global toggles to reuse Wallpaper, Button Layouts, Ringtone, and Volume across an entire deployment batch.
* **Management:**
    * **Target DMS / EPM Server:** Enter the URL where the phone should go *after* initial setup.
    * **Local Admin Password:** Set a global administrative password for the phones.
    * Use links here to manage Device Templates, Line Keys, and Hosted Files.

### 2. Import Data (CSV / Excel)
Tap **Import CSV / Excel**. The app accepts `.csv`, `.txt`, and `.xlsx` files. It reads the first row as column headers (case-insensitive) and maps them to the following fields:

| Field | Accepted column names |
|---|---|
| **Extension** *(required)* | `Extension`, `Device Username`, `Username`, `User` |
| **Secret / Password** | `Secret`, `DMS Password`, or any column containing `pass` |
| **Label / Name** | `Name`, `Label`, `Description`, `Display Name`, `Device Name`, `Caller ID Name` |
| **Model** | `Model`, `Device Type`, `Phone Model`, `Handset` |
| **Phone / DID** *(prepended to label)* | `Phone`, `User ID`, `DN`, `DID`, or any column containing `direct` |
| **MAC Address** | Any column containing `mac` |

The app supports two common export formats out of the box:

**A. Carrier / Broadworks Bulk Export:**
* `Device username` → Extension (Auth ID)
* `DMS password` → Secret (Auth Password)
* `Device type` → Model
* `User ID` or `Phone Number` → Combined with Name for the Label (e.g., "0755551234 - Reception")

**B. Standard / FreePBX Export:**
* `Extension`
* `Secret`
* `Model`
* `Label` or `Name`

> **Tip:** Tap the ℹ️ icon next to the **Import CSV / Excel** button in the app to see the full list of accepted column names at any time.

### 3. Deploy
1.  Tap **Start Server**. (Android will ask for Location permission to find Wi-Fi IP).
2.  Set your Router's **DHCP Option 66** to the URL displayed (e.g., `http://192.168.1.50:8080`).
3.  Tap **Start Scanning**.
4.  Scan the barcode on the phone box. The app matches it to the user and auto-advances.
5.  Boot the phone. It will:
    * Download Config from App.
    * Apply Wallpaper & Buttons.
    * Read the "Target DMS" URL.
    * Reboot and connect to your Carrier/PBX using the injected credentials.

---

## 📦 Supported Hardware

* **Yealink:** T54W, T46U, T48G, T57W, T58W (Generic T4x/T5x support)
* **Poly (Polycom):** Edge E Series (E350, E450), VVX Series
* **Cisco:** 8851, 8865 (3PCC / MPP)

## 🔧 Template Management
Missing a model?
1.  Go to **Settings -> Manage Templates**.
2.  Import a `.cfg` or `.xml` file.
3.  Or load a "Base Template" (Yealink/Poly/Cisco), edit it, and save it.
4.  You can also **Export** templates to share with your team.

## 📦 Tech Stack

* **Framework:** Flutter (Dart)
* **Server:** `shelf` & `shelf_router`
* **Database:** `sqflite`
* **Scanner:** `mobile_scanner`
* **Image Processing:** `image`

---

## 🏗 Getting Started / Building from Source

### Prerequisites

* **Flutter SDK** `>=3.0.0 <4.0.0` — [Install Flutter](https://docs.flutter.dev/get-started/install)
* **Android Studio** (for Android builds) or **Xcode 14+** (for iOS builds, macOS only)
* **Git**

### Clone the Repository

```bash
git clone https://github.com/Ezra90/Pocket-Provisioner.git
cd Pocket-Provisioner
```

### Install Dependencies

```bash
flutter pub get
```

### Run on Device / Emulator

```bash
flutter run
```

### Build Release APK (Android)

The CI pipeline builds a split-per-ABI APK (one file per CPU architecture). To reproduce this locally:

```bash
flutter build apk --release --split-per-abi
```

Output files will be in `build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk` — most modern Android phones
- `app-armeabi-v7a-release.apk` — older 32-bit devices
- `app-x86_64-release.apk` — emulators / Intel devices

To build a single universal APK instead:

```bash
flutter build apk --release
```

### Build App Bundle (Android)

```bash
flutter build appbundle --release
```

### Build Release IPA (iOS)

> Requires Xcode and an Apple Developer account.

```bash
flutter build ipa --release
```

### Required Permissions

| Permission | Purpose |
|---|---|
| `CAMERA` | Barcode / MAC-address scanning |
| `ACCESS_FINE_LOCATION` | Detecting the device's Wi-Fi IP address (Android) |
| `INTERNET` | Hosting the local provisioning server |

### Minimum SDK Versions

| Platform | Version |
|---|---|
| Android `minSdkVersion` | 23 (Android 6.0+) |
| Android `targetSdkVersion` | 36 |
| iOS `MinimumOSVersion` | 12.0 |

---

## 🔢 Versioning

This project uses [semantic versioning](https://semver.org/) in the format `MAJOR.MINOR.PATCH+BUILD`:

- **Version string** (e.g., `0.0.4`) is defined in `pubspec.yaml` and maps to the Android `versionName`.
- **Build number** (e.g., `+1`) is appended in `pubspec.yaml` and maps to the Android `versionCode`.

Since this is a very early alpha, versions will remain in the `0.0.x` range for the foreseeable future. To release a new version:

1. Update the `version` field in `pubspec.yaml` (e.g., `0.0.4+1` → `0.0.5+1`).
2. Commit and push to `main` — the CI workflow builds the APK and uploads it as an artifact named `pocket-provisioner-v<version>-apk`.
3. To create an official GitHub Release, push a matching git tag: `git tag v0.0.5 && git push origin v0.0.5`.