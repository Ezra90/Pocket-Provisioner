# Pocket-Provisioner

<p align="center">
  <strong>Turn your Android phone into a VoIP provisioning server</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-green" alt="Platform: Android">
  <img src="https://img.shields.io/badge/Flutter-3.0+-blue" alt="Flutter 3.0+">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License: MIT">
</p>

> ⚠️ **Alpha Release** — This app is under active development. Expect frequent updates and breaking changes between versions.

**Pocket-Provisioner** is a mobile field utility for Telecommunications Technicians. It transforms your Android device into a fully-functional **HTTP Provisioning Server** for rapid deployment of VoIP handsets — no laptop required.

---

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 📱 **Mobile Provisioning Server** | Host configurations directly from your phone via HTTP |
| 🔄 **Dual Operating Modes** | DMS/Carrier bootstrap OR complete standalone configs |
| 📷 **Barcode Scanner** | Rapid MAC address scanning with auto-advance |
| 🖼️ **Wallpaper Hosting** | Auto-resize images to exact phone model specs |
| 🔔 **Ringtone Hosting** | Import WAV files with automatic stereo-to-mono conversion |
| 📚 **Phonebook Generator** | Per-device XML phonebooks (Yealink/Polycom/Cisco formats) |
| ⚡ **Firmware Hosting** | Serve firmware files for phone auto-upgrade |
| 🎛️ **Button Layout Editor** | Configure BLF, Speed Dial, and Line keys visually |
| 📊 **Real-Time Access Log** | Monitor handset connections and file downloads |

---

## 📦 Supported Handsets

### Yealink (T-Series)
- **T54W** / **T46U** — Color screen desk phones
- **T48G** / **T57W** — Touchscreen models
- **T58W** / **T58G** — Video flagship phones
- Generic T3x/T4x/T5x template support

### Poly (Polycom)
- **VVX Series** — VVX150, VVX250, VVX350, VVX450, VVX1500
- **Edge E Series** — E350, E450

### Cisco MPP (Multiplatform)
- **8800 Series** — 8851, 8865 (3PCC/MPP firmware)
- Uses official Cisco `<flat-profile>` XML format

---

## 🔀 Operating Modes

### ☁️ Mode 1: DMS / Carrier Bootstrap

For **Telstra**, **Broadworks**, or other hosted PBX deployments:

1. App injects handset credentials from your CSV import
2. Points phone to your carrier's DMS/EPM URL
3. Phone reboots and auto-provisions from the carrier server

> **Best for:** Carrier-hosted services where configuration lives in the cloud.

### 🏢 Mode 2: Standalone / FreePBX

For **on-premise** PBX deployments (FreePBX, Asterisk, 3CX, etc.):

1. App generates complete configuration files
2. Includes SIP registration, features, media URLs
3. Phone registers directly with your PBX — no DMS hop

> **Best for:** Local PBX installations without DMS integration.

---

## 🚀 Quick Start

### 1. Import Device Data

Tap **Import CSV / Excel** and select your export file. The app auto-detects these formats:

| Format | Example Columns |
|--------|-----------------|
| **Broadworks Export** | `Device username`, `DMS password`, `Device type`, `User ID` |
| **FreePBX Export** | `Extension`, `Secret`, `Name`, `Model` |
| **Generic CSV** | Any columns containing `extension`, `secret`, `mac`, `model` |

### 2. Configure Settings ⚙️

Open **Global Settings** to configure:

- **Provisioning Mode** — DMS or Standalone
- **SIP Server** — Your PBX address (Standalone mode)
- **DMS URL** — Your carrier's provisioning server (DMS mode)
- **NTP Server** — Time synchronization (default: `0.pool.ntp.org`)
- **Timezone** — Phone display timezone
- **Voice VLAN ID** — 802.1Q VLAN tag for voice traffic

### 3. Start Provisioning

1. Tap **Start Server** — displays URL like `http://192.168.1.50:8080`
2. Configure your **DHCP Option 66** to point to this URL
3. Tap **Start Scanning** and scan device barcodes
4. Boot phones — they'll auto-provision from your device

---

## 📁 File Hosting

The provisioning server hosts files at these endpoints:

| Endpoint | Content | Directory |
|----------|---------|-----------|
| `/{MAC}.cfg` or `/{MAC}.xml` | Device configuration | Dynamic or `generated_configs/` |
| `/media/{file}` | Wallpaper images | `Pocket-Provisioner/media/` |
| `/ringtones/{file}` | Ringtone WAV files | `Pocket-Provisioner/ringtones/` |
| `/phonebook/{file}` | XML phonebook | `Pocket-Provisioner/phonebook/` |
| `/firmware/{file}` | Firmware binaries | `Pocket-Provisioner/firmware/` |

### File Storage Location

User files are stored in:
```
/storage/emulated/0/Pocket-Provisioner/
├── firmware/      → Firmware binaries (.rom, .ld, .loads)
├── media/         → Wallpaper images (auto-resized PNGs)
├── phonebook/     → Per-device XML phonebooks
└── ringtones/     → WAV ringtones (8kHz/16kHz mono)
```

### HTTP Headers

The server sets appropriate headers for each file type:

| File Type | Content-Type | Cache-Control |
|-----------|--------------|---------------|
| Config (XML) | `application/xml; charset=utf-8` | `no-cache, no-store` |
| Config (CFG) | `text/plain; charset=utf-8` | `no-cache, no-store` |
| Wallpaper | `image/png` or `image/jpeg` | `max-age=3600` |
| Ringtone | `audio/wav` | `max-age=3600` |
| Firmware | `application/octet-stream` | `max-age=86400` |

---

## 📊 Access Logging

Monitor all handset requests in the **Access Log** screen:

- **Real-time updates** as phones connect
- **MAC address resolution** from config file requests
- **Device labels** from your imported data
- **Resource tracking** — see which files each phone downloaded:
  - ✅ Config · ✅ Wallpaper · ✅ Ringtone · ✅ Phonebook · ✅ Firmware

### Console Debug Output

All requests are logged to the debug console:
```
[2024-03-14T10:30:00.000Z] 200 GET /AABBCCDDEEFF.cfg from 192.168.1.100 MAC=AABBCCDDEEFF (Ext 101 - Reception) [config]
[2024-03-14T10:30:01.000Z] 200 GET /media/logo_480x272.png from 192.168.1.100 MAC=AABBCCDDEEFF (Ext 101 - Reception) [wallpaper]
```

---

## 🔧 Template System

### Bundled Templates

| Template | File | Handsets |
|----------|------|----------|
| Yealink T4x/T5x | `yealink_t4x.cfg.mustache` | T54W, T46U, T48G, T57W, T58W |
| Polycom VVX | `polycom_vvx.xml.mustache` | VVX series, Edge E series |
| Cisco 8800 MPP | `cisco_88xx.xml.mustache` | 8851, 8865 (3PCC) |

### Custom Templates

1. Navigate to **Settings → Manage Templates**
2. Import a `.cfg` or `.xml` file
3. Or edit a base template using the built-in editor
4. Export templates to share with your team

Templates use **Mustache** syntax with variables like:
```mustache
{{sip_server}}          <!-- SIP registrar address -->
{{extension}}           <!-- User extension -->
{{secret}}              <!-- SIP password -->
{{wallpaper_url}}       <!-- Full URL to wallpaper -->
{{ringtone_url}}        <!-- Full URL to ringtone -->
{{firmware_url}}        <!-- Full URL to firmware -->
{{phonebook_url}}       <!-- Full URL to phonebook -->
```

---

## 🖼️ Wallpaper Specifications

The app auto-resizes images to match each phone model:

| Phone Model | Resolution | Format |
|-------------|------------|--------|
| Yealink T54W / T46U | 480 × 272 | PNG |
| Yealink T48G / T57W | 800 × 480 | PNG |
| Yealink T58W | 1024 × 600 | PNG |
| Poly Edge E350 | 320 × 240 | PNG |
| Poly Edge E450 | 480 × 272 | PNG |
| Cisco 8851 / 8865 | 800 × 480 | PNG |

---

## 🔔 Ringtone Specifications

| Requirement | Value |
|-------------|-------|
| Format | WAV (PCM) |
| Sample Rate | 8000 Hz or 16000 Hz |
| Bit Depth | 16-bit |
| Channels | Mono |
| Max Size | 1 MB |

> **Note:** Stereo WAV files are automatically converted to mono on import.

---

## 🏗️ Building from Source

### Prerequisites

- **Flutter SDK** `>=3.0.0 <4.0.0` — [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Android Studio** — For Android builds
- **Git**

### Build Commands

```bash
# Clone repository
git clone https://github.com/Ezra90/Pocket-Provisioner.git
cd Pocket-Provisioner

# Install dependencies
flutter pub get

# Run in development
flutter run

# Build release APK (split by architecture)
flutter build apk --release --split-per-abi

# Build universal APK
flutter build apk --release
```

### Output Files

Split APKs are generated in `build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk` — Modern 64-bit devices
- `app-armeabi-v7a-release.apk` — Older 32-bit devices
- `app-x86_64-release.apk` — Emulators / x86 devices

---

## 📋 Required Permissions

| Permission | Purpose |
|------------|---------|
| `CAMERA` | Barcode scanning for MAC addresses |
| `ACCESS_FINE_LOCATION` | Required to detect Wi-Fi IP address |
| `INTERNET` | Host the provisioning server |
| `MANAGE_EXTERNAL_STORAGE` | Store files in `Pocket-Provisioner/` folder |

---

## 📱 Minimum Requirements

| Platform | Version |
|----------|---------|
| Android | 6.0+ (API 23) |
| Target SDK | 36 |

---

## 📦 Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart) |
| HTTP Server | `shelf` + `shelf_router` |
| Database | `sqflite` |
| Barcode Scanner | `mobile_scanner` |
| Image Processing | `image` |
| Templating | `mustache_template` |

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ for Telecommunications Technicians
</p>