# Parkir Service Installer

**Master Orchestrator** untuk menginstall, update, dan manage semua service SMARTPARK.

## Cara Pakai

```powershell
# Jalankan sebagai Administrator
.\install.ps1                 # Menu interaktif pilih service
.\install.ps1 -All            # Install semua service
.\install.ps1 -Server         # Hanya server side
.\install.ps1 -Client         # Hanya client side
.\install.ps1 -Update         # Update semua (git pull + restart)
.\install.ps1 -Uninstall      # Hapus semua service
.\install.ps1 -Status         # Cek status semua service
```

## Struktur

```
SERVICE/
├── .env                              # Shared config (GitHub token, CF credentials)
├── parkir-installer/
│   ├── install.ps1                   # Master orchestrator
│   ├── shared.ps1                    # Shared functions
│   └── tools/
│       ├── nssm.exe                  # Windows service manager
│       ├── cloudflared.exe          # Cloudflare tunnel client
│       └── php/                      # PHP portable
├── parkir-detectionplate/            # ANPR/LPR service
├── parkir-video-recorder/            # Camera service
├── parkir-qris-display/              # QRIS display
├── parkir-webhook-qris/              # Webhook receiver
└── parkir-auto-cleanup/              # Auto file cleanup
```

## Fitur

- **Auto-clone dari GitHub** — Pertama kali install, auto clone dari repo
- **GitHub token** — Sekali isi, simpan di `.env`, dipakai untuk update
- **Shared Cloudflare Tunnel** — Satu tunnel untuk semua service (ingress merge)
- **Notrans-based folder** — Semua foto/video disimpan dalam `YYYYMM/DD`
- **Password masking** — MySQL password pakai SecureString
- **Auto-install Git** — Via winget kalau belum ada

## Shared .env

```env
GITHUB_TOKEN=ghp_xxx
CF_API_TOKEN=xxx
CF_ACCOUNT_ID=xxx
CF_ZONE_ID=xxx
CF_TUNNEL_NAME=parkir-tunnel
```

## Untuk Menambah Service Baru

1. Buat folder service dengan `install.ps1`
2. Dot-source `shared.ps1`: `. (Join-Path $PSScriptRoot "..\parkir-installer\shared.ps1")`
3. Tambah ke `$Services` di master installer
4. Kalau butuh tunnel: panggil `Ensure-TunnelIngress -DnsName "..." -LocalPort 8080`

---

Dikembangkan untuk **SMARTPARK** — Situsindo Prima.
