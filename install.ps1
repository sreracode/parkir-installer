<#
.SYNOPSIS
    Parkir Service Master Installer v1.0
.DESCRIPTION
    Install, update, dan manage semua service SMARTPARK
#>

param(
    [switch]$Uninstall,
    [switch]$Update
)

$ErrorActionPreference = "Stop"

# ─── Config ────────────────────────────────────────────────────
$GITHUB_USER = "sreracode"
$REPOS = @{
    "parkir-detectionplate" = @{ Name = "Detection Plate"; Type = "SERVER" }
    "parkir-video-recorder" = @{ Name = "Video Recorder"; Type = "CLIENT" }
    "parkir-qris-display"   = @{ Name = "QRIS Display";    Type = "CLIENT" }
    "parkir-webhook-qris"   = @{ Name = "Webhook QRIS";    Type = "SERVER" }
    "parkir-auto-cleanup"   = @{ Name = "Auto Cleanup";    Type = "SERVER" }
}

$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Function: NSSM Check ──────────────────────────────────────
function Ensure-NSSM {
    $nssmPaths = @(
        "$env:ProgramFiles\nssm\win64\nssm.exe",
        "${env:ProgramFiles(x86)}\nssm\win64\nssm.exe",
        "C:\nssm\win64\nssm.exe",
        "$env:LOCALAPPDATA\nssm\win64\nssm.exe"
    )
    
    $existing = $nssmPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($existing) {
        Write-Host "✅ NSSM ditemukan di: $existing" -ForegroundColor Green
        return $existing
    }
    
    Write-Host "⚠️ NSSM tidak ditemukan. Download otomatis? (y/N): " -ForegroundColor Yellow -NoNewline
    $ans = Read-Host
    if ($ans -ne "y") { return $null }
    
    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $zipPath = "$env:TEMP\nssm.zip"
    $extractPath = "$env:TEMP\nssm-extract"
    $installDir = "C:\nssm"
    
    Write-Host "Downloading NSSM..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $nssmUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Copy-Item "$extractPath\nssm-2.24\win64\*" "$installDir\win64\" -Recurse -Force
    Remove-Item $zipPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "✅ NSSM installed di: C:\nssm\win64\nssm.exe" -ForegroundColor Green
    return "C:\nssm\win64\nssm.exe"
}

# ─── Function: Check Admin ─────────────────────────────────────
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─── Function: Get repo path ───────────────────────────────────
function Get-RepoPath($repoName) {
    return Join-Path $BASE_DIR "repos\$repoName"
}

# ─── Function: Clone or pull repo ──────────────────────────────
function Sync-Repo($repoName) {
    $repoPath = Get-RepoPath $repoName
    if (Test-Path $repoPath) {
        Write-Host "  Updating $repoName..." -ForegroundColor Cyan
        Push-Location $repoPath
        git pull 2>&1 | Out-Null
        Pop-Location
    } else {
        Write-Host "  Cloning $repoName..." -ForegroundColor Cyan
        git clone "https://github.com/$GITHUB_USER/$repoName.git" $repoPath 2>&1 | Out-Null
    }
}

# ─── Function: Install Service ─────────────────────────────────
function Install-Service($repoName, $nssmPath) {
    $repoPath = Get-RepoPath $repoName
    $installBat = Join-Path $repoPath "install.bat"
    
    if (-not (Test-Path $installBat)) {
        Write-Host "  ❌ install.bat tidak ditemukan di $repoName" -ForegroundColor Red
        return $false
    }
    
    Write-Host "  ⚙️  Menjalankan installer $repoName..." -ForegroundColor Yellow
    Push-Location $repoPath
    & cmd /c $installBat 2>&1 | Write-Host
    Pop-Location
    return $true
}

# ─── Function: Uninstall Service ───────────────────────────────
$NSSM_SERVICES = @{
    "parkir-detectionplate" = @("ParkirDetectionPlate")
    "parkir-video-recorder" = @("ParkirVideoRecorder")
    "parkir-qris-display"   = @("QrisDisplay")
    "parkir-webhook-qris"   = @("ParkirWebhookPHP", "ParkirWebhookTunnel")  # PHP + Cloudflare Tunnel
    "parkir-auto-cleanup"   = @("ParkirAutoCleanup")
}

function Uninstall-Service($repoName) {
    $serviceNames = $NSSM_SERVICES[$repoName]
    if (-not $serviceNames -or $serviceNames.Count -eq 0) {
        Write-Host "  ⏭️  $repoName tidak pakai NSSM, skip" -ForegroundColor Yellow
        return
    }
    
    foreach ($serviceName in $serviceNames) {
        Write-Host "  🗑️  Menghapus service $serviceName..." -ForegroundColor Red
        & "C:\nssm\win64\nssm.exe" stop $serviceName 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
        & "C:\nssm\win64\nssm.exe" remove $serviceName confirm 2>&1 | Out-Null
        Write-Host "  ✅ Service $serviceName dihapus" -ForegroundColor Green
    }
}

# ─── MENU ───────────────────────────────────────────────────────
function Show-Menu {
    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════╗
║     PARKIR SERVICE INSTALLER v1.0       ║
║     ═══════════════════════════          ║
║                                          ║
║  Pilih service yang akan diinstal:       ║
║                                          ║
"@ -ForegroundColor Cyan
    
    param([ref]$selected)
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
║     PARKIR SERVICE INSTALLER v1.0       ║
║     ═══════════════════════════          ║
║                                          ║
║  Master installer untuk semua service    ║
║  SMARTPARK parking system.               ║
║                                          ║
╚══════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    # Cek NSSM
    $nssmPath = Ensure-NSSM
    if (-not $nssmPath) {
        Write-Host "❌ NSSM diperlukan untuk service management. Install manual." -ForegroundColor Red
        pause
        exit 1
    }
    
    # Mode UNINSTALL
    if ($Uninstall) {
        Write-Host "`n🗑️  MODE: UNINSTALL SERVICE`n" -ForegroundColor Red
        Write-Host "Service yang akan dihapus:" -ForegroundColor Yellow
        $i = 0
        $selectedServices = @()
        foreach ($repo in $REPOS.Keys) {
            $i++
            $info = $REPOS[$repo]
            Write-Host "  [$i] $($info.Name) ($($info.Type))"
            $selectedServices += $repo
        }
        
        Write-Host "`nHapus semua? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -eq "y") {
            foreach ($repo in $selectedServices) {
                Write-Host "`n➡️  $($REPOS[$repo].Name)" -ForegroundColor Cyan
                Uninstall-Service $repo
            }
        }
        
        Write-Host "`n✅ Uninstall selesai!" -ForegroundColor Green
        pause
        return
    }
    
    # Mode UPDATE
    if ($Update) {
        Write-Host "`n🔄 MODE: UPDATE SERVICE`n" -ForegroundColor Cyan
        
        foreach ($repo in $REPOS.Keys) {
            $info = $REPOS[$repo]
            Write-Host "`n➡️  $($info.Name) ($($info.Type))" -ForegroundColor Cyan
            Sync-Repo $repo
            Write-Host "  ✅ $repo updated!" -ForegroundColor Green
        }
        
        Write-Host "`nRestart semua service? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -eq "y") {
            foreach ($repo in $REPOS.Keys) {
                $serviceNames = $NSSM_SERVICES[$repo]
                if ($serviceNames -and $serviceNames.Count -gt 0) {
                    foreach ($svc in $serviceNames) {
                        & $nssmPath restart $svc 2>&1 | Out-Null
                        Write-Host "  ✅ $svc restarted" -ForegroundColor Green
                    }
                }
            }
        }
        
        Write-Host "`n✅ Update selesai!" -ForegroundColor Green
        pause
        return
    }
    
    # ─── INSTALL MODE ─────────────────────────────────────────────
    
    # Tentukan mode
    Write-Host @"
Tipe instalasi:
  [1] Server (Detection Plate, Webhook QRIS, Auto Cleanup)
  [2] Client (Video Recorder, QRIS Display)
  [3] Manual — pilih sendiri
"@
    Write-Host "Pilih [1-3]: " -NoNewline
    $mode = Read-Host
    
    $availableRepos = @()
    switch ($mode) {
        "1" { $availableRepos = @("parkir-detectionplate", "parkir-webhook-qris", "parkir-auto-cleanup") }
        "2" { $availableRepos = @("parkir-video-recorder", "parkir-qris-display") }
        default {
            # Tampilkan semua
            Write-Host "`nPilih service (pisahkan dengan koma, misal: 1,3,5):" -ForegroundColor Yellow
            $i = 0
            $allRepos = @()
            foreach ($repo in $REPOS.Keys) {
                $i++
                $info = $REPOS[$repo]
                Write-Host "  [$i] $($info.Name) ($($info.Type))"
                $allRepos += $repo
            }
            Write-Host "Pilihan: " -NoNewline
            $choices = Read-Host
            $availableRepos = $choices.Split(",") | ForEach-Object {
                $idx = $_.Trim() -as [int]
                if ($idx -gt 0 -and $idx -le $allRepos.Count) { $allRepos[$idx-1] }
            }
        }
    }
    
    Write-Host "`n📦 Service yang akan diinstal:" -ForegroundColor Cyan
    foreach ($repo in $availableRepos) {
        $info = $REPOS[$repo]
        Write-Host "  ✅ $($info.Name) ($($info.Type))" -ForegroundColor Green
    }
    
    Write-Host "`nMulai instalasi? (y/N): " -NoNewline
    $ans = Read-Host
    if ($ans -ne "y") {
        Write-Host "Dibatalkan."
        pause
        return
    }
    
    # Clone repos
    Write-Host "`n📥 Mengunduh repositori..." -ForegroundColor Cyan
    foreach ($repo in $availableRepos) {
        Sync-Repo $repo
    }
    
    # Install services
    Write-Host "`n⚙️  Menginstal service..." -ForegroundColor Cyan
    foreach ($repo in $availableRepos) {
        $info = $REPOS[$repo]
        Write-Host "`n➡️  $($info.Name) ($($repo))" -ForegroundColor Cyan
        Install-Service $repo $nssmPath
    }
    
    Write-Host @"

╔══════════════════════════════════════════╗
║          INSTALASI SELESAI!              ║
║                                          ║
║  Untuk UPDATE di masa depan,            ║
║  jalankan: .\install.ps1 -Update        ║
║                                          ║
║  Untuk UNINSTALL:                       ║
║  jalankan: .\install.ps1 -Uninstall     ║
╚══════════════════════════════════════════╝
"@ -ForegroundColor Green
    pause
}

Main
