# ============================================================
#  NSSM Service Manager - Interactive Menu
#  Bisa dijalankan dengan: klik kanan > Run with PowerShell
# ============================================================

# Trap semua error supaya tidak langsung close
trap {
    Write-Host ""
    Write-Host "  [ERROR] $_" -ForegroundColor Red
    Write-Host "  Di baris: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Tekan Enter untuk keluar..." -ForegroundColor Yellow
    Read-Host | Out-Null
    exit 1
}

# Tampilkan info session saat startup untuk debug
Write-Host "  [*] Memulai NSSM Manager..." -ForegroundColor DarkGray
Write-Host "  [*] PowerShell versi : $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host "  [*] ExecutionPolicy  : $(Get-ExecutionPolicy)" -ForegroundColor DarkGray

# Cek Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "  [*] Administrator    : $isAdmin" -ForegroundColor DarkGray

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [!] Bukan Administrator. Meminta elevasi UAC..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "  [*] OK, melanjutkan sebagai Administrator..." -ForegroundColor Green
Start-Sleep -Seconds 1

function Show-Header {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "       NSSM Service Manager                " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-NssmServices {
    $services = @(Get-CimInstance win32_service | Where-Object { $_.PathName -like '*nssm*' })
    return $services
}

function Show-ServiceList {
    param($services)

    if ($services.Count -eq 0) {
        Write-Host "  [!] Tidak ada service NSSM yang ditemukan." -ForegroundColor Yellow
        return
    }

    Write-Host "  No.  Name                        Status       DisplayName" -ForegroundColor White
    Write-Host "  ---  --------------------------  -----------  ----------------------------" -ForegroundColor DarkGray

    $i = 1
    foreach ($svc in $services) {
        $statusColor = if ($svc.State -eq "Running") { "Green" } else { "Red" }
        $num    = $i.ToString().PadRight(4)
        $name   = $svc.Name.PadRight(28)
        $state  = $svc.State.PadRight(12)
        $disp   = $svc.DisplayName
        Write-Host "  $num $name " -NoNewline
        Write-Host "$state " -ForegroundColor $statusColor -NoNewline
        Write-Host "$disp"
        $i++
    }
}

function Remove-SelectedService {
    param($services)

    Show-ServiceList $services
    if ($services.Count -eq 0) { return }

    Write-Host ""
    Write-Host "  Masukkan nomor service yang ingin dihapus (0 = batal): " -ForegroundColor Yellow -NoNewline
    $inputNum = Read-Host

    if ($inputNum -eq "0" -or $inputNum -eq "") {
        Write-Host "  Dibatalkan." -ForegroundColor DarkGray
        return
    }

    if ($inputNum -notmatch '^\d+$') {
        Write-Host "  [!] Masukkan angka yang valid!" -ForegroundColor Red
        return
    }

    $index = [int]$inputNum - 1
    if ($index -lt 0 -or $index -ge $services.Count) {
        Write-Host "  [!] Nomor tidak valid!" -ForegroundColor Red
        return
    }

    $svc = $services[$index]
    Write-Host ""
    Write-Host "  Service yang akan dihapus:" -ForegroundColor White
    Write-Host "    Nama    : $($svc.Name)" -ForegroundColor Cyan
    Write-Host "    Display : $($svc.DisplayName)" -ForegroundColor Cyan
    Write-Host "    Status  : $($svc.State)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Yakin ingin menghapus? (y/n): " -ForegroundColor Red -NoNewline
    $confirm = Read-Host

    if ($confirm -eq "y" -or $confirm -eq "Y") {
        if ($svc.State -eq "Running") {
            Write-Host "  [*] Menghentikan service..." -ForegroundColor Yellow
            try {
                Stop-Service -Name $svc.Name -Force -ErrorAction Stop
            } catch {
                Write-Host "  [!] Gagal stop service: $_" -ForegroundColor Red
                return
            }
            Start-Sleep -Seconds 2
        }

        $nssmPath = Get-Command nssm.exe -ErrorAction SilentlyContinue
        if ($nssmPath) {
            Write-Host "  [*] Menghapus via NSSM..." -ForegroundColor Yellow
            nssm remove $svc.Name confirm
        } else {
            Write-Host "  [*] nssm.exe tidak ditemukan di PATH, menghapus via sc.exe..." -ForegroundColor Yellow
            sc.exe delete $svc.Name
        }

        Write-Host ""
        Write-Host "  [OK] Service '$($svc.Name)' berhasil dihapus!" -ForegroundColor Green
    } else {
        Write-Host "  Dibatalkan." -ForegroundColor DarkGray
    }
}

function Stop-StartService {
    param($services, [string]$action)

    Show-ServiceList $services
    if ($services.Count -eq 0) { return }

    Write-Host ""
    $actionText = if ($action -eq "start") { "START" } else { "STOP" }
    Write-Host "  Pilih nomor service untuk di-$actionText (0 = batal): " -ForegroundColor Yellow -NoNewline
    $inputNum = Read-Host

    if ($inputNum -eq "0" -or $inputNum -eq "") { return }

    if ($inputNum -notmatch '^\d+$') {
        Write-Host "  [!] Masukkan angka yang valid!" -ForegroundColor Red
        return
    }

    $index = [int]$inputNum - 1
    if ($index -lt 0 -or $index -ge $services.Count) {
        Write-Host "  [!] Nomor tidak valid!" -ForegroundColor Red
        return
    }

    $svc = $services[$index]
    try {
        if ($action -eq "start") {
            if ($svc.State -eq "Running") {
                Write-Host "  [!] Service '$($svc.Name)' sudah dalam kondisi Running." -ForegroundColor Yellow
                return
            }
            Start-Service -Name $svc.Name -ErrorAction Stop
            Write-Host "  [OK] Service '$($svc.Name)' berhasil dijalankan!" -ForegroundColor Green
        } else {
            if ($svc.State -ne "Running") {
                Write-Host "  [!] Service '$($svc.Name)' sudah dalam kondisi Stopped." -ForegroundColor Yellow
                return
            }
            Stop-Service -Name $svc.Name -Force -ErrorAction Stop
            Write-Host "  [OK] Service '$($svc.Name)' berhasil dihentikan!" -ForegroundColor Green
        }
    } catch {
        if ($_ -match "Cannot open") {
            Write-Host "  [!] Akses ditolak. Pastikan script dijalankan sebagai Administrator." -ForegroundColor Red
        } else {
            Write-Host "  [!] Error: $_" -ForegroundColor Red
        }
    }
}

# ---- MAIN LOOP ----
do {
    Show-Header
    $services = @(Get-NssmServices)

    Write-Host "  Daftar Service NSSM:" -ForegroundColor White
    Write-Host ""
    Show-ServiceList $services
    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkGray
    Write-Host "  [1] Refresh daftar service" -ForegroundColor White
    Write-Host "  [2] Hapus service" -ForegroundColor Red
    Write-Host "  [3] Start service" -ForegroundColor Green
    Write-Host "  [4] Stop service" -ForegroundColor Yellow
    Write-Host "  [0] Keluar" -ForegroundColor DarkGray
    Write-Host "============================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Pilihan: " -ForegroundColor Cyan -NoNewline
    $choice = Read-Host

    switch ($choice) {
        "1" { Show-Header; continue }
        "2" { Show-Header; Remove-SelectedService $services }
        "3" { Show-Header; Stop-StartService $services "start" }
        "4" { Show-Header; Stop-StartService $services "stop" }
        "0" { break }
        default { Write-Host "  [!] Pilihan tidak valid!" -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Write-Host ""
        Write-Host "  Tekan Enter untuk lanjut..." -ForegroundColor DarkGray
        Read-Host | Out-Null
    }

} while ($choice -ne "0")

Write-Host ""
Write-Host "  Goodbye!" -ForegroundColor Cyan
Write-Host "  Tekan Enter untuk keluar..." -ForegroundColor DarkGray
Read-Host | Out-Null
