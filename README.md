# Pocket Provisioner v0.0.2

**Pocket Provisioner** is a mobile field utility designed for Telecommunications Technicians. It turns an Android/iOS device into a temporary **Provisioning Server**, allowing for rapid deployment of VoIP handsets without needing a laptop or complex on-site server infrastructure.

## 🚀 Core Features

* **Mobile Web Server:** Hosts configuration files directly from your phone on Port 8080.
* **The "Server Hop":** Generates config files that apply local settings (Wallpapers, Buttons) and then automatically repoint the handset to the ISP's production DMS (e.g., Telstra, 3CX, FusionPBX).
* **Multi-Vendor Support:**
    * **Yealink:** T4x, T5x (Generated `.cfg` with BLF injection).
    * **Polycom:** VVX, Edge E Series (Generated XML).
    * **Cisco:** 8851/8865 (3PCC `.cnf.xml` support).
* **Visual Layout Editor:** Drag-and-drop style editor to configure BLF, Speed Dials, and Line keys for Yealink models.
* **Auto-Advance Scanning:** Rapidly map MAC addresses to Extensions using the camera.

## 🛠 Supported Hardware & Templates

We provide built-in fallback templates for the following. Wallpaper sizes are noted for your reference when hosting local media:

| Manufacturer | Models | Wallpaper Size |
| :--- | :--- | :--- |
| **Yealink** | T54W, T46U | 480 x 272 |
| **Yealink** | T48G, T57W | 800 x 480 |
| **Poly** | Edge E450 | 480 x 272 |
| **Poly** | Edge E350 | 320 x 240 |
| **Poly** | VVX 1500 | 800 x 480 |
| **Cisco** | 8851, 8865 | 800 x 480 |

## 📦 Usage Workflow

1.  **Import:** Tap "Import CSV". Load your Telstra or FreePBX export file.
2.  **Design (Optional):** Go to "Manage Button Layouts". Select your model and define keys 1-10 as BLFs or Speed Dials (Yealink only).
3.  **Scan:** Walk the site. Scan the box barcode to assign MAC to Extension.
4.  **Network Setup:**
    * Connect Mobile to Voice VLAN.
    * Configure **DHCP Option 66** on the router to `http://<YOUR_IP>:8080`.
5.  **Deploy:** Boot the phones. They will:
    1.  Pull the config from your mobile.
    2.  Apply your custom buttons and wallpaper.
    3.  **Hop** (Reboot) into the production ISP ecosystem.

## 📚 References & Credits


## 🤝 Contributing

This is an Alpha release. Pull requests for new Handset Templates or improved Regex matching for MAC addresses are welcome.
