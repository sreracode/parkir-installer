<#
.SYNOPSIS
    Parkir Service Master Installer v2.0
.DESCRIPTION
    Install, update, dan manage semua service SMARTPARK
#>

param(
    [switch]$Uninstall,
    [switch]$Update
)

$ErrorActionPreference = "Stop"

# --- Config ---------------------------------------------------
$GITHUB_USER = "sreracode"
$REPOS = @{
    "parkir-detectionplate" = @{ Name = "Detection Plate"; Type = "SERVER" }
    "parkir-video-recorder" = @{ Name = "Video Recorder";   Type = "CLIENT" }
    "parkir-qris-display"   = @{ Name = "QRIS Display";     Type = "CLIENT" }
    "parkir-webhook-qris"   = @{ Name = "Webhook QRIS";     Type = "SERVER" }
    "parkir-auto-cleanup"   = @{ Name = "Auto Cleanup";     Type = "SERVER" }
}

$NSSM_SERVICES = @{
    "parkir-detectionplate" = "ParkirDetectionPlate"
    "parkir-video-recorder" = "ParkirVideoRecorder"
    "parkir-qris-display"   = "QrisDisplay"
    "parkir-webhook-qris"   = $null
    "parkir-auto-cleanup"   = "ParkirAutoCleanup"
}

$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$TOOLS_DIR = Join-Path $BASE_DIR "tools"
$NSSM_EXE  = Join-Path $TOOLS_DIR "nssm.exe"

# --- Functions ------------------------------------------------

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Info  { Write-Host "  [i] $($args[0])" -ForegroundColor Cyan }
function Write-OK    { Write-Host "  [v] $($args[0])" -ForegroundColor Green }
function Write-Warn  { Write-Host "  [!] $($args[0])" -ForegroundColor Yellow }
function Write-Err   { Write-Host "  [x] $($args[0])" -ForegroundColor Red }

function Ensure-Tools {
    # Create tools dir
    if (-not (Test-Path $TOOLS_DIR)) {
        New-Item -ItemType Directory -Path $TOOLS_DIR -Force | Out-Null
    }

    # --- NSSM ---
    if (Test-Path $NSSM_EXE) {
        Write-OK "NSSM ditemukan di $NSSM_EXE"
    } else {
        Write-Warn "NSSM tidak ditemukan. Download otomatis? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -ne "y") { return $false }

        $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
        $zipPath = "$env:TEMP\nssm.zip"
        $extractPath = "$env:TEMP\nssm-extract"

        Write-Info "Download NSSM..."
        Invoke-WebRequest -Uri $nssmUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        New-Item -ItemType Directory -Path $TOOLS_DIR -Force | Out-Null
        Copy-Item "$extractPath\nssm-2.24\win64\*" $TOOLS_DIR -Recurse -Force
        Remove-Item $zipPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "NSSM installed di $NSSM_EXE"
    }

    # --- Cloudflared ---
    $CLOUDFLARED_EXE = Join-Path $TOOLS_DIR "cloudflared.exe"
    if (Test-Path $CLOUDFLARED_EXE) {
        Write-OK "Cloudflared ditemukan di $CLOUDFLARED_EXE"
    } else {
        Write-Warn "Download cloudflared.exe? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -eq "y") {
            Write-Info "Download cloudflared..."
            $cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
            Invoke-WebRequest -Uri $cfUrl -OutFile $CLOUDFLARED_EXE
            Write-OK "Cloudflared installed di $CLOUDFLARED_EXE"
        }
    }

    return (Test-Path $NSSM_EXE)
}

function Get-RepoPath($repoName) {
    return Join-Path $BASE_DIR $repoName
}

function Sync-Repo($repoName) {
    $repoPath = Get-RepoPath $repoName
    if (Test-Path $repoPath) {
        Write-Host "  [?] Repo $repoName sudah ada. [S]kip / [U]pdate / [C]ancel: " -NoNewline
        $ans = Read-Host
        switch ($ans.ToLower()) {
            "u" {
                Write-Info "Update $repoName..."
                Push-Location $repoPath
                git pull 2>&1 | Out-Null
                Pop-Location
                Write-OK "$repoName updated!"
            }
            "c" { return $false }
            default { Write-Info "$repoName di-skip" }
        }
    } else {
        Write-Info "Clone $repoName..."
        $result = git clone "https://github.com/$GITHUB_USER/$repoName.git" $repoPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Gagal clone $repoName : $result"
            return $false
        }
        Write-OK "$repoName cloned!"
    }
    return $true
}

function Install-Service($repoName) {
    $repoPath = Get-RepoPath $repoName
    $installBat = Join-Path $repoPath "install.bat"
    $reqTxt = Join-Path $repoPath "requirements.txt"
    $srcDir = Join-Path $repoPath "src"
    $mainPy = Join-Path $srcDir "main.py"

    # Buat venv + install requirements kalo ada
    $venvPath = Join-Path $repoPath "venv"
    if ((Test-Path $reqTxt) -and (-not (Test-Path $venvPath))) {
        Write-Info "Membuat virtual env untuk $repoName..."
        python -m venv $venvPath 2>&1 | Out-Null
        $pip = Join-Path $venvPath "Scripts\pip.exe"
        if (Test-Path $pip) {
            & $pip install -r $reqTxt 2>&1 | Out-Null
            Write-OK "Dependencies $repoName terinstall"
        }
    }

    # Jalankan install.bat kalo ada
    if (Test-Path $installBat) {
        Write-Info "Jalankan installer $repoName..."
        Push-Location $repoPath
        & cmd /c $installBat 2>&1 | Write-Host
        Pop-Location
        return $true
    }

    # Fallback: register NSSM langsung kalo ada main.py
    if ((Test-Path $mainPy) -and $NSSM_SERVICES[$repoName]) {
        $serviceName = $NSSM_SERVICES[$repoName]
        $pyExe = Join-Path $venvPath "Scripts\python.exe"
        if (-not (Test-Path $pyExe)) { $pyExe = "python" }

        Write-Info "Register $serviceName sebagai NSSM service..."
        & $NSSM_EXE install $serviceName $pyExe $mainPy 2>&1 | Out-Null
        & $NSSM_EXE set $serviceName AppDirectory $srcDir 2>&1 | Out-Null
        & $NSSM_EXE set $serviceName Start SERVICE_AUTO_START 2>&1 | Out-Null
        & $NSSM_EXE start $serviceName 2>&1 | Out-Null
        Write-OK "$serviceName registered + started!"
        return $true
    }

    return $false
}

function Uninstall-Service($repoName) {
    $serviceName = $NSSM_SERVICES[$repoName]
    if (-not $serviceName) {
        Write-Info "$repoName tidak pakai NSSM, skip"
        return
    }
    Write-Info "Hapus service $serviceName..."
    & $NSSM_EXE stop $serviceName 2>&1 | Out-Null
    & $NSSM_EXE remove $serviceName confirm 2>&1 | Out-Null
    Write-OK "Service $serviceName dihapus"
}

# --- Menu -----------------------------------------------------

function Show-ServiceMenu {
    param([string]$mode)

    $allRepos = @()
    $i = 0
    foreach ($repo in $REPOS.Keys) {
        $i++
        $info = $REPOS[$repo]
        Write-Host "  [$i] $($info.Name) ($($info.Type))"
        $allRepos += $repo
    }

    Write-Host ""
    Write-Host "Pilihan (pisahkan dengan koma, misal: 1,3,5): " -NoNewline
    $choices = Read-Host

    $selected = @()
    $choices.Split(",") | ForEach-Object {
        $idx = $_.Trim() -as [int]
        if ($idx -gt 0 -and $idx -le $allRepos.Count) { $selected += $allRepos[$idx-1] }
    }
    return $selected
}

# --- MAIN -----------------------------------------------------

function Main {
    if (-not (Test-Admin)) {
        Write-Err "Jalankan PowerShell sebagai Administrator!"
        Write-Host "   Klik kanan > Run as Administrator"
        pause
        exit 1
    }

    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   PARKIR SERVICE INSTALLER v2.0" -ForegroundColor Cyan
    Write-Host "   Master installer SMARTPARK services" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    # Cek tools
    $toolsOK = Ensure-Tools
    if (-not $toolsOK) {
        Write-Err "NSSM diperlukan. Install manual atau jalankan ulang."
        pause
        exit 1
    }

    # --- UNINSTALL ---
    if ($Uninstall) {
        Write-Host "[!] MODE: UNINSTALL" -ForegroundColor Red
        Write-Host ""
        Write-Host "Service yang akan dihapus:" -ForegroundColor Yellow
        $selected = Show-ServiceMenu -mode "uninstall"

        Write-Host ""
        Write-Host "Hapus service di atas? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -eq "y") {
            foreach ($repo in $selected) {
                Uninstall-Service $repo
            }
        }
        Write-OK "Uninstall selesai!"
        pause
        return
    }

    # --- UPDATE ---
    if ($Update) {
        Write-Host "[i] MODE: UPDATE" -ForegroundColor Cyan
        foreach ($repo in $REPOS.Keys) {
            $info = $REPOS[$repo]
            Write-Host "[$($info.Name)]" -ForegroundColor Cyan
            Sync-Repo $repo | Out-Null
        }
        Write-Host ""
        Write-Host "Restart semua service? (y/N): " -NoNewline
        $ans = Read-Host
        if ($ans -eq "y") {
            foreach ($repo in $REPOS.Keys) {
                $serviceName = $NSSM_SERVICES[$repo]
                if ($serviceName) {
                    & $NSSM_EXE restart $serviceName 2>&1 | Out-Null
                    Write-OK "$serviceName restarted"
                }
            }
        }
        Write-OK "Update selesai!"
        pause
        return
    }

    # --- INSTALL ---
    Write-Host "Tipe instalasi:" -ForegroundColor Yellow
    Write-Host "  [1] Server (Detection Plate, Webhook QRIS, Auto Cleanup)"
    Write-Host "  [2] Client (Video Recorder, QRIS Display)"
    Write-Host "  [3] Manual - pilih sendiri"
    Write-Host "  [A] All - install semua"
    Write-Host ""
    Write-Host "Pilih [1-3/A]: " -NoNewline
    $mode = Read-Host

    $selectedRepos = @()
    switch ($mode.ToUpper()) {
        "1" { $selectedRepos = @("parkir-detectionplate", "parkir-webhook-qris", "parkir-auto-cleanup") }
        "2" { $selectedRepos = @("parkir-video-recorder", "parkir-qris-display") }
        "A" { $selectedRepos = @($REPOS.Keys) }
        default {
            Write-Host ""
            $selectedRepos = Show-ServiceMenu -mode "install"
        }
    }

    if ($selectedRepos.Count -eq 0) {
        Write-Err "Tidak ada service dipilih."
        pause
        return
    }

    Write-Host ""
    Write-Host "Service yang akan diinstal:" -ForegroundColor Cyan
    foreach ($repo in $selectedRepos) {
        $info = $REPOS[$repo]
        Write-OK "$($info.Name) ($($info.Type))"
    }

    Write-Host ""
    Write-Host "Mulai instalasi? (y/N): " -NoNewline
    $ans = Read-Host
    if ($ans -ne "y") {
        Write-Host "Dibatalkan."
        pause
        return
    }

    # Clone / update repos
    Write-Host ""
    Write-Host "Mengunduh repositori..." -ForegroundColor Cyan
    $cancelInstall = $false
    foreach ($repo in $selectedRepos) {
        $result = Sync-Repo $repo
        if ($result -eq $false) {
            $cancelInstall = $true
            break
        }
    }

    if ($cancelInstall) {
        Write-Err "Instalasi dibatalkan."
        pause
        return
    }

    # Install services
    Write-Host ""
    Write-Host "Menginstal service..." -ForegroundColor Cyan
    foreach ($repo in $selectedRepos) {
        $info = $REPOS[$repo]
        Write-Host "[$($info.Name)]" -ForegroundColor Cyan
        Install-Service $repo
    }

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "     INSTALASI SELESAI!" -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    Write-Host "  Untuk UPDATE di masa depan:" -ForegroundColor Green
    Write-Host "    .\install.ps1 -Update" -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    Write-Host "  Untuk UNINSTALL:" -ForegroundColor Green
    Write-Host "    .\install.ps1 -Uninstall" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    pause
}

Main
