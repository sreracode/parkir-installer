<#
.SYNOPSIS
    Parkir Service Master Installer v2.0
.DESCRIPTION
    Install, update, dan manage semua service SMARTPARK.
    - NSSM & cloudflared auto-download ke SERVICE\tools\
    - Clone repo langsung ke SERVICE\
    - Auto venv + pip install + NSSM register
#>

param(
    [switch]$Uninstall,
    [switch]$Update
)

$ErrorActionPreference = "Stop"

# ─── Config ────────────────────────────────────────────────────
$GITHUB_USER = "sreracode"
$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$TOOLS_DIR = Join-Path $BASE_DIR "tools"
$REPOS = @{
    "parkir-detectionplate" = @{ Name = "Detection Plate"; Type = "SERVER"; Port = 5000; Desc = "ANPR YOLO + OCR" }
    "parkir-video-recorder" = @{ Name = "Video Recorder"; Type = "CLIENT"; Port = 5050; Desc = "RTSP Recording" }
    "parkir-qris-display"   = @{ Name = "QRIS Display";    Type = "CLIENT"; Port = 8001; Desc = "QRIS SSE Display" }
    "parkir-webhook-qris"   = @{ Name = "Webhook QRIS";    Type = "SERVER"; Port = 8090; Desc = "PHP Webhook + Cloudflare Tunnel" }
    "parkir-auto-cleanup"   = @{ Name = "Auto Cleanup";    Type = "SERVER"; Port = 0;   Desc = "Hapus file expired" }
}

$NSSM_SERVICES = @{
    "parkir-detectionplate" = @("ParkirDetectionPlate")
    "parkir-video-recorder" = @("ParkirVideoRecorder")
    "parkir-qris-display"   = @("QrisDisplay")
    "parkir-webhook-qris"   = @("ParkirWebhookPHP", "ParkirWebhookTunnel")
    "parkir-auto-cleanup"   = @("ParkirAutoCleanup")
}

# ─── Function: Admin Check ─────────────────────────────────────
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─── Function: Download Tools ──────────────────────────────────
function Ensure-NSSM {
    $nssmPath = Join-Path $TOOLS_DIR "nssm.exe"
    if (Test-Path $nssmPath) {
        Write-Host "  ✅ NSSM: $nssmPath" -ForegroundColor Green
        return $nssmPath
    }

    Write-Host "  ⬇️  Download NSSM..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $TOOLS_DIR -Force | Out-Null

    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $zipPath = "$env:TEMP\nssm.zip"
    $extractPath = "$env:TEMP\nssm-extract"

    try {
        Invoke-WebRequest -Uri $nssmUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Copy-Item "$extractPath\nssm-2.24\win64\nssm.exe" $nssmPath -Force
        Write-Host "  ✅ NSSM installed: $nssmPath" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ Gagal download NSSM: $_" -ForegroundColor Red
        return $null
    } finally {
        Remove-Item $zipPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $nssmPath
}

function Ensure-Cloudflared {
    $cfPath = Join-Path $TOOLS_DIR "cloudflared.exe"
    if (Test-Path $cfPath) {
        Write-Host "  ✅ Cloudflared: $cfPath" -ForegroundColor Green
        return $cfPath
    }

    Write-Host "  ⬇️  Download Cloudflared..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $TOOLS_DIR -Force | Out-Null

    # Cloudflare tunnel client for Windows AMD64
    $cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"

    try {
        Invoke-WebRequest -Uri $cfUrl -OutFile $cfPath -UseBasicParsing
        Write-Host "  ✅ Cloudflared installed: $cfPath" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️  Gagal download cloudflared: $_" -ForegroundColor Yellow
        Write-Host "     Download manual: $cfUrl" -ForegroundColor Yellow
        return $null
    }
    return $cfPath
}

# ─── Function: Repo Path ───────────────────────────────────────
function Get-RepoPath($repoName) {
    return Join-Path $BASE_DIR $repoName
}

# ─── Function: Sync Repo ───────────────────────────────────────
function Sync-Repo($repoName) {
    $repoPath = Get-RepoPath $repoName
    if (Test-Path $repoPath) {
        Write-Host "  📂 $repoName sudah ada." -ForegroundColor Yellow
        Write-Host "     [S]kip  [U]pdate (git pull)  [C]ancel: " -NoNewline
        $ans = Read-Host
        switch ($ans.ToUpper()) {
            "S" { return "skip" }
            "U" {
                Write-Host "  🔄 Update $repoName..." -ForegroundColor Cyan
                Push-Location $repoPath
                git pull 2>&1 | Out-Null
                Pop-Location
                return "updated"
            }
            default {
                Write-Host "  ⛔ Instalasi dibatalkan." -ForegroundColor Red
                return "cancelled"
            }
        }
    }

    Write-Host "  📥 Clone $repoName..." -ForegroundColor Cyan
    git clone "https://github.com/$GITHUB_USER/$repoName.git" $repoPath 2>&1 | Out-Null
    return "cloned"
}

# ─── Function: Setup Service ───────────────────────────────────
function Setup-Service($repoName) {
    $repoPath = Get-RepoPath $repoName
    $info = $REPOS[$repoName]

    Write-Host "  ⚙️  Setup $($info.Name)..." -ForegroundColor Cyan

    # Cek requirements.txt
    $reqFile = Join-Path $repoPath "requirements.txt"
    $venvPath = Join-Path $repoPath ".venv"

    if (Test-Path $reqFile) {
        # Buat venv kalo belum
        if (-not (Test-Path $venvPath)) {
            Write-Host "     📦 Membuat virtual environment..." -ForegroundColor Gray
            & "python" -m venv $venvPath 2>&1 | Out-Null
        }

        # Install dependencies
        Write-Host "     📦 Install dependencies..." -ForegroundColor Gray
        $pip = Join-Path $venvPath "Scripts\pip.exe"
        if (Test-Path $pip) {
            & $pip install -r $reqFile --quiet 2>&1 | Out-Null
        }
    }

    # Cek install.bat
    $installBat = Join-Path $repoPath "install.bat"
    if (Test-Path $installBat) {
        Write-Host "     ⚙️  Jalankan install.bat..." -ForegroundColor Gray
        Push-Location $repoPath
        & cmd /c $installBat 2>&1 | Out-Null
        Pop-Location
        Write-Host "  ✅ $($info.Name) siap!" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  install.bat tidak ditemukan, manual setup diperlukan" -ForegroundColor Yellow
    }
}

# ─── Function: Uninstall Service ───────────────────────────────
function Uninstall-Service($repoName, $nssmPath) {
    $serviceNames = $NSSM_SERVICES[$repoName]
    if (-not $serviceNames -or $serviceNames.Count -eq 0) {
        Write-Host "  ⏭️  $repoName tidak pakai NSSM" -ForegroundColor Yellow
        return
    }

    foreach ($serviceName in $serviceNames) {
        Write-Host "  🗑️  Hapus service $serviceName..." -ForegroundColor Red
        # Stop dulu, ignore error kalo udah mati
        & $nssmPath stop $serviceName 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
        & $nssmPath remove $serviceName confirm 2>&1 | Out-Null
        Write-Host "  ✅ $serviceName dihapus" -ForegroundColor Green
    }
}

# ─── Function: Get Service Selection ───────────────────────────
function Get-ServiceSelection($mode) {
    $allRepos = @()
    $i = 0
    foreach ($repo in $REPOS.Keys) {
        $i++
        $info = $REPOS[$repo]
        $allRepos += @{ Key = $repo; Index = $i; Name = $info.Name; Type = $info.Type; Desc = $info.Desc }
    }

    if ($mode -eq "server") {
        return $allRepos | Where-Object { $_.Type -eq "SERVER" } | ForEach-Object { $_.Key }
    }
    if ($mode -eq "client") {
        return $allRepos | Where-Object { $_.Type -eq "CLIENT" } | ForEach-Object { $_.Key }
    }

    # Manual mode
    Write-Host "`nPilih service (pisahkan dengan koma, misal: 1,3,5):" -ForegroundColor Yellow
    foreach ($r in $allRepos) {
        Write-Host "  [$($r.Index)] $($r.Name) ($($r.Type)) — $($r.Desc)"
    }
    Write-Host "  [A] Semua service" -ForegroundColor Cyan
    Write-Host "Pilihan: " -NoNewline
    $choices = Read-Host

    if ($choices.ToUpper() -eq "A") {
        return $allRepos | ForEach-Object { $_.Key }
    }

    $selected = @()
    $choices.Split(",") | ForEach-Object {
        $idx = $_.Trim() -as [int]
        $match = $allRepos | Where-Object { $_.Index -eq $idx }
        if ($match) { $selected += $match.Key }
    }
    return $selected
}

# ─── MAIN ───────────────────────────────────────────────────────
function Main {
    if (-not (Test-Admin)) {
        Write-Host "❌ Jalankan PowerShell sebagai Administrator!" -ForegroundColor Red
        Write-Host "   Klik kanan > Run as Administrator"
        pause
        exit 1
    }

    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════╗
║     PARKIR SERVICE INSTALLER v2.0       ║
║     ═══════════════════════════          ║
║                                          ║
║  Lokasi: $BASE_DIR
║                                          ║
╚══════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # ── Mode UNINSTALL ──
    if ($Uninstall) {
        Write-Host "`n🗑️  MODE: UNINSTALL`n" -ForegroundColor Red

        # Cari service yang masih terinstal
        $nssmPath = Join-Path $TOOLS_DIR "nssm.exe"
        if (-not (Test-Path $nssmPath)) {
            Write-Host "❌ NSSM tidak ditemukan di $nssmPath" -ForegroundColor Red
            pause
            return
        }

        $selectedRepos = Get-ServiceSelection "manual"

        Write-Host "`nHapus service-service ini? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -eq "y") {
            foreach ($repo in $selectedRepos) {
                $info = $REPOS[$repo]
                Write-Host "`n➡️  $($info.Name)" -ForegroundColor Cyan
                Uninstall-Service $repo $nssmPath
            }
            Write-Host "`n✅ Uninstall selesai!" -ForegroundColor Green
        }
        pause
        return
    }

    # ── Mode UPDATE ──
    if ($Update) {
        Write-Host "`n🔄 MODE: UPDATE`n" -ForegroundColor Cyan

        $selectedRepos = Get-ServiceSelection "manual"

        foreach ($repo in $selectedRepos) {
            $info = $REPOS[$repo]
            Write-Host "`n➡️  $($info.Name)" -ForegroundColor Cyan
            $result = Sync-Repo $repo
            if ($result -eq "cloned" -or $result -eq "updated") {
                Setup-Service $repo
            }
        }

        Write-Host "`n✅ Update selesai!" -ForegroundColor Green
        pause
        return
    }

    # ── Mode INSTALL ──

    # 1. Cek & download tools
    Write-Host "`n🔧 Memeriksa tools...`n" -ForegroundColor Cyan
    $nssmPath = Ensure-NSSM
    if (-not $nssmPath) {
        Write-Host "❌ NSSM diperlukan. Install manual." -ForegroundColor Red
        pause
        exit 1
    }

    $cfPath = Ensure-Cloudflared

    # 2. Pilih service
    Write-Host "`n📋 Pilih service`n" -ForegroundColor Cyan
    Write-Host "Tipe instalasi:" -ForegroundColor Yellow
    Write-Host "  [1] Server ($(($REPOS.Values | Where-Object { $_.Type -eq "SERVER" }).Count -join ', '))" 
    Write-Host "  [2] Client" 
    Write-Host "  [3] Manual — pilih sendiri"
    Write-Host "Pilih [1-3]: " -NoNewline
    $mode = Read-Host

    $selLabel = switch ($mode) {
        "1" { "server" }
        "2" { "client" }
        default { "manual" }
    }

    $selectedRepos = Get-ServiceSelection $selLabel

    if ($selectedRepos.Count -eq 0) {
        Write-Host "❌ Tidak ada service dipilih." -ForegroundColor Red
        pause
        return
    }

    Write-Host "`n📦 Service yang akan diinstal:" -ForegroundColor Cyan
    foreach ($repo in $selectedRepos) {
        $info = $REPOS[$repo]
        Write-Host "  ✅ $($info.Name) ($($info.Type)) — $($info.Desc)" -ForegroundColor Green
    }

    Write-Host "`nMulai instalasi? (y/N): " -NoNewline
    $ans = Read-Host
    if ($ans -ne "y") {
        Write-Host "Dibatalkan." -ForegroundColor Yellow
        pause
        return
    }

    # 3. Clone / update repos
    Write-Host "`n📥 Menyiapkan repositori...`n" -ForegroundColor Cyan
    $cancelInstall = $false
    foreach ($repo in $selectedRepos) {
        $info = $REPOS[$repo]
        Write-Host "➡️  $($info.Name)" -ForegroundColor Cyan
        $result = Sync-Repo $repo
        if ($result -eq "cancelled") {
            $cancelInstall = $true
            break
        }
    }

    if ($cancelInstall) {
        Write-Host "`n⛔ Instalasi dibatalkan." -ForegroundColor Red
        pause
        return
    }

    # 4. Setup tiap service
    Write-Host "`n⚙️  Setup service...`n" -ForegroundColor Cyan
    foreach ($repo in $selectedRepos) {
        $info = $REPOS[$repo]
        Write-Host "➡️  $($info.Name)" -ForegroundColor Cyan
        Setup-Service $repo
    }

    # 5. Selesai
    Write-Host @"

╔══════════════════════════════════════════╗
║          INSTALASI SELESAI!              ║
║                                          ║
║  Tools: $TOOLS_DIR
║  Service: $BASE_DIR
║                                          ║
║  Untuk UPDATE: .\install.ps1 -Update    ║
║  Untuk UNINSTALL: .\install.ps1 -Uninstall
╚══════════════════════════════════════════╝
"@ -ForegroundColor Green

    # Info service
    Write-Host "`n📌 Service yang terinstall:" -ForegroundColor Cyan
    foreach ($repo in $selectedRepos) {
        $info = $REPOS[$repo]
        $svcs = $NSSM_SERVICES[$repo]
        if ($svcs) {
            foreach ($svc in $svcs) {
                Write-Host "  • $svc"
            }
        }
    }

    pause
}

Main
