# Pocket Provisioner v0.0.1

**Pocket Provisioner** is a mobile field utility designed for Telecommunications Technicians. It turns an Android/iOS device into a temporary **Provisioning Server**, allowing for rapid deployment of VoIP handsets (Yealink, Polycom) without needing a laptop or complex on-site server infrastructure.

## 🚀 Core Features

* **Mobile Web Server:** Hosts configuration files directly from your phone on Port 8080.
* **Auto-Advance Scanning:** Rapidly map MAC addresses to Extensions using the camera.
* **The "Server Hop":** Generates config files that apply local settings (Wallpapers, Buttons) and then automatically repoint the handset to the ISP's production DMS (e.g., Telstra).
* **Multi-Vendor Support:** Smart detection for Yealink (`.cfg`) and Polycom (`.xml`) request formats.
* **Dynamic Template Engine:** Add new handset models on-the-fly by importing text or XML templates directly in the app.
* **Database Driven:** Uses SQLite to manage deployment lists for 100+ devices.

## 🛠 Usage Workflow

1.  **Import:** Load your extension list (CSV) or use the "Mock Data" generator.
2.  **Scan:** Walk the site. The app prompts: *"Find the phone for Ext 101"*. Scan the box barcode. The app assigns it and instantly advances to Ext 102.
3.  **Network Setup:**
    * Connect your Mobile to the local Voice VLAN (e.g., Unifi UX Express).
    * Set a Static IP on your Mobile (e.g., `192.168.1.50`).
    * Configure **DHCP Option 66** on the router to `http://192.168.1.50:8080`.
4.  **Deploy:** Boot the phones. They will pull the config from your mobile, apply settings, and reboot into the ISP's management ecosystem.

## 📦 Tech Stack

* **Framework:** Flutter (Dart)
* **Server:** `shelf` & `shelf_router`
* **Database:** `sqflite`
* **Scanner:** `mobile_scanner`
* **Background:** `wakelock_plus` (Prevents server sleep on iOS/Android)
* **File Handling:** `file_picker` & `share_plus`

## 🤝 Contributing

This is an early Alpha (v0.0.1). Pull requests for new Handset Templates are welcome.
