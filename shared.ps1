<#
.SYNOPSIS
    Shared module untuk semua service installer SMARTPARK.
.DESCRIPTION
    Fungsi bersama: NSSM registration, Cloudflare API, Tunnel Ingress merge.
    
    Cara pakai di tiap service install.ps1:
        $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        . (Join-Path $PSScriptRoot "..\parkir-installer\shared.ps1")
#>

# ---- Paths (relatif terhadap SERVICE root) ----
$script:ServiceRoot = Split-Path -Parent $PSScriptRoot
$script:ToolsDir    = Join-Path $script:ServiceRoot "parkir-installer\tools"
$script:NssmExe     = Join-Path $script:ToolsDir "nssm.exe"
$script:CfExe       = Join-Path $script:ToolsDir "cloudflared.exe"
$script:SharedEnv   = Join-Path $script:ServiceRoot ".env"
$script:CloudflaredDir = Join-Path $env:USERPROFILE ".cloudflared"
$script:CloudflaredConfig = Join-Path $script:CloudflaredDir "config.yml"
$script:GitHubUser = "sreracode"  # GitHub username for clone

# ---- Git & GitHub Token ----
function Test-GitInstalled {
    try { git --version 2>&1 | Out-Null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Ensure-Git {
    if (Test-GitInstalled) { wOK "Git sudah terinstall"; return $true }
    
    wWarn "Git belum terinstall. Mencoba install via winget..."
    try {
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Test-GitInstalled) { wOK "Git berhasil diinstall"; return $true }
    } catch { wErr "Winget gagal: $_" }
    
    wErr "Gagal install Git otomatis."
    wInfo "Download manual: https://git-scm.com/download/win"
    if (-not $Silent) { $ans = Read-Host "    Lanjut tanpa Git? (update tidak akan berfungsi) (y/N)"; if ($ans -ne "y") { exit 1 } }
    return $false
}

function Ensure-GitHubToken {
    $envData = Load-EnvFile $script:SharedEnv
    
    if ($envData.ContainsKey('GITHUB_TOKEN') -and -not [string]::IsNullOrWhiteSpace($envData['GITHUB_TOKEN'])) {
        wOK "GitHub token loaded from .env"
        return $envData['GITHUB_TOKEN']
    }
    
    if ($Silent) {
        wWarn "GitHub token tidak ditemukan. Clone tidak bisa dilakukan."
        wInfo "Generate token: https://github.com/settings/tokens -> repo scope"
        return $null
    }
    
    Write-Host ""
    Write-Host "=== GitHub Token Setup (sekali saja) ===" -ForegroundColor Yellow
    Write-Host "  Token diperlukan untuk clone/update dari GitHub."
    Write-Host "  Buat di: https://github.com/settings/tokens"
    Write-Host "  Scope: repo (full control)" -ForegroundColor DarkGray
    Write-Host ""
    $token = Read-Host "  GitHub Personal Access Token"
    
    if ([string]::IsNullOrWhiteSpace($token)) {
        wWarn "Token kosong. Update tidak akan berfungsi."
        return $null
    }
    
    # Save to shared .env
    $envData['GITHUB_TOKEN'] = $token
    Save-EnvFile -Path $script:SharedEnv -Data $envData -KeyOrder @('GITHUB_TOKEN','CF_API_TOKEN','CF_ACCOUNT_ID','CF_ZONE_ID','CF_TUNNEL_NAME')
    wOK "GitHub token disimpan ke .env"
    return $token
}

function Clone-ServiceRepo {
    param([string]$RepoName, [string]$TargetDir)
    
    if (Test-Path (Join-Path $TargetDir "install.ps1")) {
        wInfo "Service already exists: $TargetDir"
        return $true
    }
    
    if (-not (Test-GitInstalled)) {
        wErr "Git tidak tersedia. Tidak bisa clone."
        return $false
    }
    
    $token = Ensure-GitHubToken
    if (-not $token) {
        if (Test-Path $TargetDir) { return $true }  # folder exists, maybe from zip
        wErr "Tidak bisa clone tanpa token GitHub."
        return $false
    }
    
    $parentDir = Split-Path -Parent $TargetDir
    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
    
    wStep "Clone $RepoName dari GitHub..."
    $cloneUrl = "https://${token}@github.com/$script:GitHubUser/${RepoName}.git"
    
    Push-Location $parentDir
    $result = git clone $cloneUrl $TargetDir 2>&1
    Pop-Location
    
    if ($LASTEXITCODE -eq 0) {
        wOK "$RepoName cloned successfully"
        return $true
    } else {
        wErr "Clone gagal: $result"
        # Clean up partial clone
        if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Update-ServiceRepo {
    param([string]$RepoDir)
    
    if (-not (Test-GitInstalled)) { return $false }
    
    $gitDir = Join-Path $RepoDir ".git"
    if (-not (Test-Path $gitDir)) {
        wInfo "Bukan git repo, skip update"
        return $false
    }
    
    $token = Ensure-GitHubToken
    if (-not $token) {
        wInfo "No GitHub token, using regular git pull"
        Push-Location $RepoDir; git pull 2>&1 | Out-Null; Pop-Location
        return ($LASTEXITCODE -eq 0)
    }
    
    # Set remote URL with token for this pull
    Push-Location $RepoDir
    $origUrl = git remote get-url origin 2>&1
    $tokenUrl = "https://${token}@github.com/$script:GitHubUser/$(Split-Path $RepoDir -Leaf).git"
    git remote set-url origin $tokenUrl 2>&1 | Out-Null
    git pull 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    git remote set-url origin $origUrl 2>&1 | Out-Null  # restore original
    Pop-Location
    
    if ($ok) { wOK "Git pull OK" } else { wWarn "Git pull failed" }
    return $ok
}

# ---- Log Helpers ----
function wStep { Write-Host "  >> $($args[0])" -ForegroundColor Yellow }
function wOK   { Write-Host "  [OK] $($args[0])" -ForegroundColor Green }
function wErr  { Write-Host "  [X] $($args[0])" -ForegroundColor Red }
function wInfo { Write-Host "  [i] $($args[0])" -ForegroundColor Cyan }
function wWarn { Write-Host "  [!] $($args[0])" -ForegroundColor Yellow }

# ---- NSSM Service Registration ----
function Register-Service {
    param(
        [string]$Name, [string]$Exe, [string]$AppParams,
        [string]$Display, [string]$Desc,
        [string]$Stdout, [string]$Stderr, [string]$WorkDir
    )
    & $script:NssmExe stop $Name 2>&1 | Out-Null
    & $script:NssmExe remove $Name confirm 2>&1 | Out-Null
    & $script:NssmExe install $Name $Exe 2>&1 | Out-Null
    if ($AppParams) {
        & $script:NssmExe set $Name AppParameters $AppParams 2>&1 | Out-Null
    }
    & $script:NssmExe set $Name AppDirectory $WorkDir 2>&1 | Out-Null
    & $script:NssmExe set $Name DisplayName $Display 2>&1 | Out-Null
    & $script:NssmExe set $Name Description $Desc 2>&1 | Out-Null
    & $script:NssmExe set $Name Start SERVICE_AUTO_START 2>&1 | Out-Null
    if ($Stdout) { & $script:NssmExe set $Name AppStdout $Stdout 2>&1 | Out-Null }
    if ($Stderr) { & $script:NssmExe set $Name AppStderr $Stderr 2>&1 | Out-Null }
    & $script:NssmExe set $Name AppExit Default Exit 2>&1 | Out-Null
}

function Start-ServiceSafe {
    param([string]$Name)
    & $script:NssmExe start $Name 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    try { $s = Get-Service $Name -ErrorAction Stop; return ($s.Status -eq "Running") }
    catch { return $false }
}

# ---- .env Management ----
function Load-EnvFile {
    param([string]$Path = $script:SharedEnv)
    $data = @{}
    if (-not (Test-Path $Path)) { return $data }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($val.StartsWith('"') -and $val.EndsWith('"') -and $val.Length -ge 2) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $data[$key] = $val
    }
    return $data
}

function Save-EnvFile {
    param([string]$Path, [hashtable]$Data, [string[]]$KeyOrder)
    $lines = @()
    if (-not $KeyOrder) { $KeyOrder = @($Data.Keys) }
    foreach ($k in $KeyOrder) {
        if ($Data.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($Data[$k])) {
            $v = $Data[$k]
            $lines += "$k=$v"
        }
    }
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
    wOK ".env saved: $Path"
}

# ---- Cloudflare Shared Env ----
function Get-SharedEnvData {
    $env = Load-EnvFile $script:SharedEnv
    # Check completeness
    $required = @('CF_API_TOKEN', 'CF_ACCOUNT_ID', 'CF_ZONE_ID')
    $missing = @($required | Where-Object { -not $env.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($env[$_]) })
    if ($missing.Count -gt 0) {
        return @{ Complete = $false; Data = $env; Missing = $missing }
    }
    # Defaults
    if (-not $env.ContainsKey('CF_TUNNEL_NAME') -or [string]::IsNullOrWhiteSpace($env['CF_TUNNEL_NAME'])) {
        $env['CF_TUNNEL_NAME'] = 'parkir-tunnel'
    }
    return @{ Complete = $true; Data = $env }
}

function Prompt-SharedEnv {
    Write-Host ""
    Write-Host "Konfigurasi Cloudflare (sekali isi untuk semua service):" -ForegroundColor Yellow
    $apiToken  = Read-Host "  CF_API_TOKEN"
    $accountId = Read-Host "  CF_ACCOUNT_ID"
    $zoneId    = Read-Host "  CF_ZONE_ID"
    $tunName   = Read-Host "  CF_TUNNEL_NAME [parkir-tunnel]"
    if (-not $tunName) { $tunName = "parkir-tunnel" }

    $data = @{
        CF_API_TOKEN   = $apiToken
        CF_ACCOUNT_ID  = $accountId
        CF_ZONE_ID     = $zoneId
        CF_TUNNEL_NAME = $tunName
    }
    Save-EnvFile -Path $script:SharedEnv -Data $data -KeyOrder @('CF_API_TOKEN','CF_ACCOUNT_ID','CF_ZONE_ID','CF_TUNNEL_NAME')
    return $data
}

# ---- Cloudflare API ----
function Invoke-CloudflareApi {
    param([string]$Method, [string]$Path, $Body = $null)
    $envData = Load-EnvFile $script:SharedEnv
    $token = $envData['CF_API_TOKEN']
    $headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
    $uri = "https://api.cloudflare.com/client/v4$Path"
    
    try {
        if ($null -eq $Body) {
            return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ErrorAction Stop
        }
        $json = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json -ErrorAction Stop
    } catch {
        wErr "Cloudflare API error: $($_.Exception.Message)"
        return $null
    }
}

# ---- Tunnel Token ----
function Get-TunnelToken {
    param([string]$AccountId, [string]$TunnelId)
    wInfo "Fetching tunnel token for: $TunnelId"
    try {
        $resp = Invoke-CloudflareApi "Get" "/accounts/$AccountId/cfd_tunnel/$TunnelId/token"
        if (-not $resp) { return $null }
        if ($resp.PSObject.Properties.Name -contains 'success' -and -not $resp.success) { return $null }
        if ($resp.PSObject.Properties.Name -contains 'result') {
            if ($resp.result -is [string]) { return $resp.result }
            if ($resp.result.PSObject.Properties.Name -contains 'token') { return $resp.result.token }
        }
        return $null
    } catch { return $null }
}

# ---- DNS CNAME ----
function Update-DnsRecord {
    param([string]$ZoneId, [string]$DnsName, [string]$Target)
    
    $escaped = [uri]::EscapeDataString($DnsName)
    $existing = Invoke-CloudflareApi "Get" "/zones/$ZoneId/dns_records?type=CNAME&name=$escaped"
    
    if ($existing -and $existing.success -and $existing.result -and $existing.result.Count -gt 0) {
        $rec = $existing.result | Select-Object -First 1
        if ($rec.content -eq $Target) {
            wOK "DNS CNAME already correct: $DnsName"
            return $true
        }
        wInfo "Updating DNS: $DnsName -> $Target"
        $body = @{ type = "CNAME"; name = $DnsName; content = $Target; ttl = 1; proxied = $true }
        $upd = Invoke-CloudflareApi "Put" "/zones/$ZoneId/dns_records/$($rec.id)" $body
        if ($upd -and $upd.success) { wOK "DNS updated"; return $true }
    } else {
        wInfo "Creating DNS: $DnsName -> $Target"
        $body = @{ type = "CNAME"; name = $DnsName; content = $Target; ttl = 1; proxied = $true }
        $cre = Invoke-CloudflareApi "Post" "/zones/$ZoneId/dns_records" $body
        if ($cre -and $cre.success) { wOK "DNS created"; return $true }
    }
    wErr "DNS update failed for: $DnsName"
    return $false
}

# ---- Tunnel NSSM Service (shared, only one) ----
$script:TunnelSvcName = "ParkirCloudflareTunnel"

function Ensure-TunnelNssmService {
    param([string]$TunnelId)
    
    try { $existing = Get-Service $script:TunnelSvcName -ErrorAction Stop }
    catch { $existing = $null }
    
    if ($existing) {
        Write-Host "  [i] Tunnel NSSM service already exists: $script:TunnelSvcName"
        return $true
    }
    
    if (-not (Test-Path $script:CfExe)) {
        wWarn "cloudflared.exe not found. Skipping NSSM tunnel service."
        return $false
    }
    
    wStep "Registering shared tunnel NSSM service..."
    $tunArgs = "tunnel --protocol http2 --config `"$script:CloudflaredConfig`" run $TunnelId"
    $logDir  = Join-Path $script:ServiceRoot "parkir-installer\logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    
    Register-Service $script:TunnelSvcName $script:CfExe $tunArgs `
        "Parkir Cloudflare Tunnel" "Shared Cloudflare Tunnel for SMARTPARK" `
        (Join-Path $logDir "tunnel_stdout.log") (Join-Path $logDir "tunnel_stderr.log") `
        $script:ServiceRoot
    
    wOK "Tunnel NSSM service registered"
    return $true
}

# ═══════════════════════════════════════════════════════════════
# ⭐ ENSURE-TUNNEL-INGRESS — Smart merge logic
# ═══════════════════════════════════════════════════════════════
function Ensure-TunnelIngress {
    param(
        [Parameter(Mandatory=$true)][string]$DnsName,
        [Parameter(Mandatory=$true)][int]$LocalPort
    )
    
    # 1. Load shared env
    $sharedStatus = Get-SharedEnvData
    if (-not $sharedStatus.Complete) {
        wWarn "Shared .env incomplete. Missing: $($sharedStatus.Missing -join ', ')"
        $sharedStatus.Data = Prompt-SharedEnv
    } else {
        wOK "Shared .env loaded: $script:SharedEnv"
    }
    
    $env = $sharedStatus.Data
    $accountId  = $env['CF_ACCOUNT_ID']
    $zoneId     = $env['CF_ZONE_ID']
    $tunnelName = $env['CF_TUNNEL_NAME']
    
    # 2. Ensure cloudflared directory
    if (-not (Test-Path $script:CloudflaredDir)) {
        New-Item -ItemType Directory -Path $script:CloudflaredDir -Force | Out-Null
    }
    
    # 3. Check/create tunnel via API
    wStep "Checking tunnel '$tunnelName' via API..."
    $listResp = Invoke-CloudflareApi "Get" "/accounts/$accountId/cfd_tunnel"
    $existingTunnel = $null
    
    if ($listResp -and $listResp.success -and $listResp.result) {
        foreach ($item in $listResp.result) {
            if ($item.name -eq $tunnelName) { $existingTunnel = $item; break }
        }
    }
    
    $tunnelId = $null
    $credFile = $null
    
    if ($null -eq $existingTunnel) {
        # CREATE new tunnel
        wStep "Creating tunnel: $tunnelName..."
        $bytes = New-Object Byte[] 32
        [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
        $secret = [Convert]::ToBase64String($bytes)
        
        $createBody = @{ name = $tunnelName; tunnel_secret = $secret }
        $createResp = Invoke-CloudflareApi "Post" "/accounts/$accountId/cfd_tunnel" $createBody
        
        if (-not $createResp -or -not $createResp.success) {
            wErr "Failed to create tunnel: $tunnelName"
            return $false
        }
        $tunnelId = $createResp.result.id
        wOK "Tunnel created: $tunnelId"
        
        # Save credential JSON
        $credFile = Join-Path $script:CloudflaredDir "$tunnelId.json"
        $credJson = @{ AccountTag = $accountId; TunnelID = $tunnelId; TunnelSecret = $secret } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($credFile, $credJson, (New-Object System.Text.UTF8Encoding($false)))
        wOK "Credential saved: $credFile"
    } else {
        # EXISTING tunnel
        $tunnelId = $existingTunnel.id
        $credFile = Join-Path $script:CloudflaredDir "$tunnelId.json"
        wOK "Tunnel already exists: $tunnelName ($tunnelId)"
        
        # Check if credential file exists
        if (-not (Test-Path $credFile)) {
            wInfo "Credential file missing. Re-fetching..."
            $token = Get-TunnelToken $accountId $tunnelId
            if ($token) {
                # We have the token but not the secret. cloudflared can use token directly in config.yml.
                # Just create a minimal credential marker.
                $credJson = @{ AccountTag = $accountId; TunnelID = $tunnelId; TunnelSecret = "" } | ConvertTo-Json -Depth 5
                [System.IO.File]::WriteAllText($credFile, $credJson, (New-Object System.Text.UTF8Encoding($false)))
                wOK "Credential marker created: $credFile"
            } else {
                wWarn "Could not fetch tunnel token. Tunnel may not work."
            }
        }
    }
    
    # 4. Smart merge config.yml
    wStep "Managing config.yml ingress rules..."
    
    $ingressRules = @()
    $hasExistingConfig = Test-Path $script:CloudflaredConfig
    
    if ($hasExistingConfig) {
        # Parse existing YAML (simple line-based, no YAML lib needed)
        $lines = Get-Content $script:CloudflaredConfig
        $inIngress = $false
        $currentRule = @{}
        $catchAll = $null
        
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -eq "ingress:") {
                $inIngress = $true
                continue
            }
            if ($inIngress) {
                if ($trimmed -match '^- hostname:\s*(.+)$') {
                    if ($currentRule.Count -gt 0 -and $currentRule.ContainsKey('hostname')) {
                        if ($currentRule['hostname'] -ne "CATCH_ALL") {
                            $ingressRules += $currentRule
                        } else {
                            $catchAll = $currentRule
                        }
                    }
                    $currentRule = @{ hostname = $matches[1].Trim() }
                } elseif ($trimmed -match '^- service:\s*(.+)$') {
                    $service = $matches[1].Trim()
                    if ($currentRule.ContainsKey('hostname')) {
                        $currentRule['service'] = $service
                    } else {
                        $catchAll = @{ hostname = "CATCH_ALL"; service = $service }
                        $currentRule = @{}
                    }
                }
            }
        }
        # Don't forget last rule
        if ($currentRule.Count -gt 0 -and $currentRule.ContainsKey('hostname') -and $currentRule['hostname'] -ne "CATCH_ALL") {
            $ingressRules += $currentRule
        }
        
        # Check if this hostname already exists
        $found = $false
        $newRules = @()
        foreach ($rule in $ingressRules) {
            if ($rule['hostname'] -eq $DnsName) {
                $newService = "http://127.0.0.1:${LocalPort}"
                if ($rule['service'] -eq $newService) {
                    wOK "Ingress for $DnsName already correct (port ${LocalPort})"
                } else {
                    wInfo "Updating ingress: $DnsName -> ${newService} (was $($rule['service']))"
                    $rule['service'] = $newService
                }
                $found = $true
            }
            $newRules += $rule
        }
        $ingressRules = $newRules
        
        if (-not $found) {
            wInfo "Adding new ingress: $DnsName -> http://127.0.0.1:${LocalPort}"
            $ingressRules += @{ hostname = $DnsName; service = "http://127.0.0.1:${LocalPort}" }
        }
        if (-not $catchAll) {
            $catchAll = @{ hostname = "CATCH_ALL"; service = "http_status:404" }
        }
    } else {
        # Fresh config
        wInfo "Creating new config.yml..."
        $ingressRules = @(@{ hostname = $DnsName; service = "http://127.0.0.1:${LocalPort}" })
        $catchAll = @{ hostname = "CATCH_ALL"; service = "http_status:404" }
    }
    
    # 5. Write config.yml
    $configLines = @()
    $configLines += "tunnel: $tunnelId"
    $configLines += "credentials-file: $credFile"
    $configLines += ""
    $configLines += "ingress:"
    foreach ($rule in $ingressRules) {
        $configLines += "  - hostname: $($rule['hostname'])"
        $configLines += "    service: $($rule['service'])"
    }
    $configLines += "  - service: $($catchAll['service'])"
    
    [System.IO.File]::WriteAllLines($script:CloudflaredConfig, $configLines, (New-Object System.Text.UTF8Encoding($false)))
    wOK "config.yml updated: $script:CloudflaredConfig"
    
    # 6. DNS CNAME
    Update-DnsRecord $zoneId $DnsName "$tunnelId.cfargotunnel.com" | Out-Null
    
    # 7. Ensure tunnel NSSM service
    Ensure-TunnelNssmService $tunnelId | Out-Null
    
    # Start/restart tunnel service
    try { Restart-Service $script:TunnelSvcName -Force -ErrorAction Stop; wOK "Tunnel service restarted" }
    catch { Start-Service $script:TunnelSvcName -ErrorAction SilentlyContinue; wInfo "Tunnel service started" }
    
    Write-Host ""
    Write-Host "  Public URL: https://${DnsName}" -ForegroundColor Green
    
    return $true
}
