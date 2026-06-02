# Parkir Installer

Master installer untuk semua service SMARTPARK. Memudahkan instalasi, update, dan uninstall service di Windows.

## Cara Pakai

### Install
```powershell
# Jalankan PowerShell sebagai Administrator
.\install.ps1
```

Pilih mode:
- **Server** — Detection Plate, Webhook QRIS, Auto Cleanup
- **Client** — Video Recorder, QRIS Display
- **Manual** — Pilih sendiri

### Update
```powershell
.\install.ps1 -Update
```
Akan pull semua repo terbaru dan restart services.

### Uninstall
```powershell
.\install.ps1 -Uninstall
```
Hapus semua service NSSM.

## Persyaratan

- Windows 10/11
- PowerShell 5.1+
- Python 3.11+
- Git for Windows (`git` must be in PATH)
- Internet (untuk clone repositori)

## Struktur

```
parkir-installer/
├── install.ps1          ← Main installer
├── README.md
└── repos/              ← Auto-cloned repos (gitignored)
    ├── parkir-detectionplate/
    ├── parkir-video-recorder/
    ├── parkir-qris-display/
    ├── parkir-webhook-qris/
    └── parkir-auto-cleanup/
```
