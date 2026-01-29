# Pocket Provisioner v0.0.3

**Pocket Provisioner** is a mobile field utility for Telecommunications Technicians. It turns an Android/iOS device into a temporary **Provisioning Server**, allowing for rapid deployment of VoIP handsets (Yealink, Polycom, Cisco) without needing a laptop or complex on-site infrastructure.

## 🚀 Core Features

* **Server Hop Architecture:** Provisions a handset with local settings (Wallpaper, Buttons) and then automatically hands it off to your production **DMS / EPM** (Endpoint Manager).
* **Smart CSV Import:** Automatically detects Carrier/Broadworks headers and generic exports.
* **Auto-Advance Scanning:** Rapidly map MAC addresses to Extensions using the camera.
* **Smart Wallpaper Tool:** Pick any image from your gallery; the app auto-resizes and formats it for the specific handset model (e.g., Yealink T54W) and hosts it locally.
* **Button Layout Editor:** Configure BLF, Speed Dial, and Line keys before the phone even boots.

---

## 🛠 Usage Workflow

### 1. The Setup (Global Settings)
Tap the **Gear Icon [⚙]** to configure your job environment.

* **Target DMS / EPM Server:**
    * Enter the URL where the phone should go *after* initial setup.
    * *Example:* `http://dms.example.com/bootstrap`
* **Primary SIP Server:**
    * **Leave Blank** for Cloud/DMS jobs. It will default to the local Android IP temporarily.
    * **Enter IP** (e.g., `192.168.1.10`) for manual On-Premise PBX jobs.
* **Wallpaper Source:**
    * Use the **Smart Tool [🪄]** to pick an image. It will save as `LOCAL_HOSTED`.

### 2. Import Data (CSV)
Tap **Import CSV**. The app supports two main formats:

**A. Carrier / Broadworks Copy-Paste:**
The app looks for these specific headers:
* `Device username` -> Maps to **Extension** (Auth ID)
* `DMS password` -> Maps to **Secret** (Auth Password)
* `Device type` -> Maps to **Model**
* `User ID` or `Phone Number` -> Combined with Name for the Label (e.g., "0755551234 - Reception")

**B. Standard / FreePBX Export:**
* `Extension`
* `Secret`
* `Model`
* `Label` or `Name`

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
