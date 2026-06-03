# Parkir Installer v2.0

Master installer untuk semua service SMARTPARK. Install, update, dan uninstall service di Windows dalam satu perintah.

## Cara Kerja

### 1. Install Baru

```powershell
# Buka PowerShell sebagai Administrator
cd "E:\Project\Project Parkir\SERVICE\parkir-installer"
.\install.ps1
```

**Alur lengkap:**

```
1. Admin Check
   -> Kalo bukan Administrator, minta run as admin

2. Tools Check (otomatis)
   -> Cek NSSM di SERVICE\tools\nssm.exe
   -> Kalo belum ada: tanya download? [y/N]
   -> Cek Cloudflared di SERVICE\tools\cloudflared.exe
   -> Kalo belum ada: tanya download? [y/N]

3. Pilih Mode Instalasi
   [1] Server
       -> Detection Plate (ANPR)
       -> Webhook QRIS
       -> Auto Cleanup
   [2] Client
       -> Video Recorder (RTSP)
       -> QRIS Display (SSE)
   [3] Manual
       -> Pilih sendiri (misal: 1,3,5)
   [A] All
       -> Install semua

4. Clone Repo
   -> Clone dari github.com/sreracode/parkir-*
   -> Langsung ke SERVICE\ (bukan subfolder repos\)
   -> Kalo repo sudah ada:
      [S]kip - lewati
      [U]pdate - git pull
      [C]ancel - batalkan instalasi

5. Install Dependencies
   -> python -m venv venv (otomatis)
   -> pip install -r requirements.txt

6. Register NSSM Service
   -> Setiap service di-register sebagai Windows service
   -> Auto-start saat Windows boot
```

### 2. Update

```powershell
.\install.ps1 -Update
```

```
1. Git pull semua repo (setiap service)
2. Tanya: restart semua service? [y/N]
   -> Kalo y: nssm restart untuk setiap service
```

### 3. Uninstall

```powershell
.\install.ps1 -Uninstall
```

```
1. Tampilkan daftar service
2. Pilih service yang mau dihapus (nomor, pisah koma)
3. nssm stop + nssm remove untuk masing-masing
```

## Menu Screenshot

```
============================================
   PARKIR SERVICE INSTALLER v2.0
   Master installer SMARTPARK services
============================================

  [v] NSSM ditemukan di E:\...\SERVICE\tools\nssm.exe
  [v] Cloudflared ditemukan di E:\...\SERVICE\tools\cloudflared.exe

Tipe instalasi:
  [1] Server (Detection Plate, Webhook QRIS, Auto Cleanup)
  [2] Client (Video Recorder, QRIS Display)
  [3] Manual - pilih sendiri
  [A] All - install semua

Pilih [1-3/A]:
```

## Daftar Service

| Service | Port | Type | NSSM Name | Fungsi |
|---------|------|------|-----------|--------|
| parkir-detectionplate | 5000 | Server | ParkirDetectionPlate | ANPR YOLO deteksi plat nomor |
| parkir-video-recorder | 5050 | Client | ParkirVideoRecorder | Rekam video dari kamera RTSP |
| parkir-qris-display | 8001 | Client | QrisDisplay | Tampilkan QRIS di monitor client |
| parkir-webhook-qris | 8090 | Server | (PHP, no NSSM) | Terima notifikasi QRIS dari API |
| parkir-auto-cleanup | - | Server | ParkirAutoCleanup | Hapus otomatis file expired |

## Struktur Folder Setelah Install

```
E:\Project\Project Parkir\SERVICE\
├── parkir-installer\            ← Master installer script
│   ├── install.ps1
│   ├── README.md
│   └── .git
├── tools\                       ← Tools (auto-download)
│   ├── nssm.exe
│   └── cloudflared.exe
├── parkir-detectionplate\       ← Clone dari GitHub
│   ├── src\main.py
│   ├── venv\
│   ├── config.yaml
│   └── install.bat
├── parkir-video-recorder\       ← Clone dari GitHub
│   ├── src\main.py
│   ├── venv\
│   ├── config.yaml
│   └── install.bat
├── parkir-qris-display\         ← Clone dari GitHub
│   ├── src\main.py
│   ├── venv\
│   ├── config.yaml
│   └── install.bat
├── parkir-webhook-qris\         ← Clone dari GitHub
│   ├── src\webhook.php
│   ├── config.php
│   └── install.bat
└── parkir-auto-cleanup\         ← Clone dari GitHub
    ├── src\main.py
    ├── venv\
    ├── config.yaml
    └── install.bat
```

## Persyaratan

- Windows 10/11
- PowerShell 5.1+
- Python 3.11+ (di PATH)
- Git for Windows (`git` di PATH)
- Internet (untuk clone dan download tools)
- **Jalankan sebagai Administrator**

## Catatan

- Semua service auto-start saat Windows boot via NSSM
- Update cukup `git pull` + `install.ps1 -Update`, tanpa install ulang
- Uninstall hapus service NSPM, folder repo tetap ada
