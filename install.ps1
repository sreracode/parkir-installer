<#
.SYNOPSIS
    Parkir Service Master Orchestrator v4.0
.DESCRIPTION
    Install, update, uninstall, status — semua service SMARTPARK.
    Delegasi ke install.ps1 masing-masing service.
    Shared module: shared.ps1
#>

param([switch]$Update,[switch]$Uninstall,[switch]$Status,[switch]$All,[switch]$Server,[switch]$Client,[switch]$Silent)

$ErrorActionPreference = "Continue"
$script:PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir   = $script:PSScriptRoot
$ParentDir = Split-Path -Parent $BaseDir

# Dot-source shared module
. (Join-Path $BaseDir "shared.ps1")

$Services = [ordered]@{
    "parkir-detectionplate" = @{ Name="Detection Plate (ANPR)"; Type="Server"; Port=5000; NssmName="ParkirDetectionPlate" }
    "parkir-video-recorder" = @{ Name="Video Recorder"; Type="Client"; Port=5050; NssmName="ParkirVideoRecorder" }
    "parkir-qris-display"   = @{ Name="QRIS Display"; Type="Client"; Port=8001; NssmName="QrisDisplay" }
    "parkir-webhook-qris"   = @{ Name="Webhook QRIS"; Type="Server"; Port=8090; NssmName="ParkirWebhookPHP"; HasTunnel=$true }
    "parkir-auto-cleanup"   = @{ Name="Auto Cleanup"; Type="Server"; Port=$null; NssmName="ParkirAutoCleanup" }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[X] Jalankan sebagai Administrator!" -ForegroundColor Red; pause; exit 1
    }
}

function Get-SelectedServices {
    if ($All)   { return @($Services.Keys) }
    if ($Server){ return @($Services.Keys | Where-Object { $Services[$_].Type -eq "Server" }) }
    if ($Client){ return @($Services.Keys | Where-Object { $Services[$_].Type -eq "Client" }) }
    Write-Host "Pilih service:" -ForegroundColor Yellow; Write-Host ""
    $i=0; $keys=@($Services.Keys)
    foreach ($key in $keys){ $i++; $svc=$Services[$key]; $st=""; try{$s=Get-Service $svc.NssmName -ErrorAction SilentlyContinue;if($s){$st=" [$($s.Status)]"}}catch{}; Write-Host "  [$i] $($svc.Name) ($($svc.Type))$st" }
    Write-Host "  [S] Server only    [C] Client only    [A] ALL"; Write-Host ""
    $c=Read-Host "Pilih"
    switch($c.ToUpper()){ "A"{return @($keys)} "S"{return @($keys|?{$Services[$_].Type-eq"Server"})} "C"{return @($keys|?{$Services[$_].Type-eq"Client"})} default{$sel=@();$c.Split(",")|%{$idx=$_.Trim()-as[int];if($idx -gt 0 -and $idx -le $keys.Count){$sel+=$keys[$idx-1]}};return $sel} }
}

function Invoke-ServiceAction {
    param([string]$ServiceKey,[string]$Action)
    $svc=$Services[$ServiceKey]; $svcDir=Join-Path $ParentDir $ServiceKey; $script=Join-Path $svcDir "install.ps1"
    Write-Host ""; Write-Host "--- $($svc.Name) ---" -ForegroundColor Cyan
    
    # Clone from GitHub if folder doesn't exist
    if ($Action -eq "install" -or $Action -eq "update") {
        if (-not (Test-Path $script)) {
            wInfo "Folder service belum ada. Clone dari GitHub..."
            if (-not (Clone-ServiceRepo $ServiceKey $svcDir)) {
                wErr "Clone gagal untuk $ServiceKey"; return
            }
        } elseif ($Action -eq "update") {
            wStep "Git pull $ServiceKey..."
            Update-ServiceRepo $svcDir | Out-Null
        }
    }
    
    if(-not(Test-Path $script)){ wErr "install.ps1 tidak ditemukan: $script"; return }
    $al=@()
    switch($Action){ "install"   { $al+="-Install"; if($Silent){$al+="-Silent"} } "update"{ $al+="-Update" } "uninstall" { $al+="-Uninstall" } "status"{ $al+="-Status" } }
    Push-Location $svcDir; & powershell -ExecutionPolicy Bypass -File $script @al; Pop-Location
}

function Read-SharedConfig {
    if($Silent){ return }  # Config handled by shared.ps1 now
}

function Main {
    Test-Admin
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   PARKIR SERVICE ORCHESTRATOR v4.0"        -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan; Write-Host ""

    if($Uninstall){
        Write-Host "[MODE: UNINSTALL]" -ForegroundColor Red; Write-Host ""
        $sel=Get-SelectedServices; if($sel.Count -eq 0){wErr "Tidak ada dipilih";pause;return}
        Write-Host "";$ans=if($Silent){"y"}else{Read-Host "Hapus? (y/N)"}
        if($ans -eq "y"){foreach($s in $sel){Invoke-ServiceAction $s "uninstall"}}
        wOK "Selesai.";pause;return
    }
    if($Status){
        Write-Host "[MODE: STATUS]" -ForegroundColor Cyan; Write-Host ""
        foreach($key in $Services.Keys){ $svc=$Services[$key]; if($svc.NssmName){ try{$s=Get-Service $svc.NssmName -ErrorAction Stop;Write-Host "  $($svc.Name): $($s.Status)" -ForegroundColor $(if($s.Status-eq"Running"){"Green"}else{"Red"})}catch{Write-Host "  $($svc.Name): BELUM TERINSTALL" -ForegroundColor DarkGray} } }
        # Also check shared tunnel
        try{$ts=Get-Service $script:TunnelSvcName -ErrorAction Stop;Write-Host "  Shared Tunnel: $($ts.Status)" -ForegroundColor $(if($ts.Status-eq"Running"){"Green"}else{"Red"})}catch{}
        pause;return
    }
    if($Update){
        Write-Host "[MODE: UPDATE]" -ForegroundColor Cyan; Write-Host ""
        $sel=if($All){@($Services.Keys)}else{Get-SelectedServices}
        foreach($s in $sel){Invoke-ServiceAction $s "update"}
        wOK "Update selesai.";pause;return
    }

    # INSTALL
    Write-Host "[MODE: INSTALL]" -ForegroundColor Green; Write-Host ""
    Ensure-Git      # First-time: install Git if needed
    Read-SharedConfig
    $sel=Get-SelectedServices; if($sel.Count -eq 0){wErr "Tidak ada dipilih";pause;return}
    Write-Host ""; Write-Host "Akan diinstal:" -ForegroundColor Cyan
    foreach($s in $sel){Write-Host "  + $($Services[$s].Name)"}
    Write-Host ""; $ans=if($Silent){"y"}else{Read-Host "Mulai? (y/N)"}
    if($ans -ne "y"){Write-Host "Dibatalkan.";pause;return}

    foreach($s in $sel){Invoke-ServiceAction $s "install"}

    Write-Host ""; Write-Host "============================================" -ForegroundColor Green
    Write-Host "     INSTALASI SELESAI!" -ForegroundColor Green
    Write-Host "  .\install.ps1 -Status | -Update | -Uninstall" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green; pause
}

Main
