function Show-FindingsSummary {
    param(
        [string]$ComputerName
    )

    Write-Host ""
    Write-Title " HALLAZGOS AUTOMATICOS - $ComputerName"
    Write-Host ""

    $AnyFinding = $false

    # =========================
    # 1. Discos con alto uso
    # =========================
    try {
        $Disks = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                [PSCustomObject]@{
                    Drive = $_.DeviceID
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                    UsedGB = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
                    PercentUsed = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
                }
            }
        } -ErrorAction Stop

        foreach ($Disk in @($Disks)) {
            if ($Disk.PercentUsed -ge 90) {
                Write-ErrorText "[ALERTA] Disco $($Disk.Drive) al $($Disk.PercentUsed)% de uso"
                $AnyFinding = $true
            }
            elseif ($Disk.PercentUsed -ge 80) {
                Write-WarningText "[WARN] Disco $($Disk.Drive) al $($Disk.PercentUsed)% de uso"
                $AnyFinding = $true
            }
        }
    }
    catch {
        Write-WarningText "[WARN] No fue posible analizar discos."
    }

    # =========================
    # 2. Eventos IIS / AppPools
    # =========================
    try {
        $CriticalIISIds = @(5002,5009,5011,5057,5059,5074,2282)

        $IISEvents = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'System'
            Id        = $CriticalIISIds
            StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue

        $GroupedIIS = @($IISEvents) | Group-Object Id | Sort-Object Count -Descending

        if (@($GroupedIIS).Count -gt 0) {
            foreach ($Group in $GroupedIIS) {
                $Meaning = Get-IISAppPoolEventMeaning -EventId ([int]$Group.Name)
                Write-WarningText "[WARN] Se detectaron $($Group.Count) evento(s) $($Group.Name) → $Meaning"
            }

            $AppPools = @(
                @($IISEvents) |
                    ForEach-Object { Get-AppPoolFromMessage $_.Message } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "N/A" }
            )

            if (@($AppPools).Count -gt 0) {
                $TopAppPools = $AppPools | Group-Object | Sort-Object Count -Descending | Select-Object -First 3

                foreach ($Pool in $TopAppPools) {
                    Write-Info "[INFO] AppPool con eventos: $($Pool.Name) → $($Pool.Count) evento(s)"
                }
            }

            $AnyFinding = $true
        }
        else {
            Write-Success "[OK] Sin eventos criticos recientes de IIS/AppPools"
        }
    }
    catch {
        Write-WarningText "[WARN] No fue posible analizar eventos IIS/AppPool."
    }

    # =========================
    # 3. Certificados vencidos con reemplazo
    # =========================
    try {
        $Certs = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-ChildItem Cert:\LocalMachine\My | ForEach-Object {
                [PSCustomObject]@{
                    Subject    = $_.Subject
                    NotAfter   = $_.NotAfter
                    Thumbprint = $_.Thumbprint
                }
            }
        } -ErrorAction Stop

        $Now = Get-Date

        $NormalizedCerts = foreach ($Cert in @($Certs)) {
            $CN = if ($Cert.Subject -match 'CN=([^,]+)') {
                $Matches[1].Trim().ToLower()
            }
            else {
                $Cert.Subject.Trim().ToLower()
            }

            [PSCustomObject]@{
                CN         = $CN
                Subject    = $Cert.Subject
                NotAfter   = [datetime]$Cert.NotAfter
                Thumbprint = $Cert.Thumbprint
            }
        }

        $Grouped = $NormalizedCerts | Group-Object CN

        $ReplacedExpiredCount = 0

        foreach ($Group in $Grouped) {
            $Expired = @($Group.Group | Where-Object { $_.NotAfter -lt $Now })
            $Valid   = @($Group.Group | Where-Object { $_.NotAfter -ge $Now })

            if ($Expired.Count -gt 0 -and $Valid.Count -gt 0) {
                $ReplacedExpiredCount += $Expired.Count
            }
        }

        if ($ReplacedExpiredCount -gt 0) {
            Write-WarningText "[WARN] Se detectaron $ReplacedExpiredCount certificado(s) vencido(s) con reemplazo en LocalMachine\My"
            $AnyFinding = $true
        }
    }
    catch {
        Write-WarningText "[WARN] No fue posible analizar certificados."
    }



    # =========================
    # Resultado final
    # =========================
    if (-not $AnyFinding) {
        Write-Success "[OK] No se detectaron hallazgos relevantes en esta revision."
    }
}


function Get-IISExpiredCertificatesInUseData {
    param(
        [string]$ComputerName
    )

    try {
        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Import-Module WebAdministration -ErrorAction Stop

            $Now = Get-Date
            $Sites = Get-Website -ErrorAction Stop
            $StoreCerts = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop)

            foreach ($Site in $Sites) {
                foreach ($Binding in $Site.Bindings.Collection) {
                    if ($Binding.protocol -eq 'https') {
                        try {
                            $Thumbprint = $Binding.CertificateHash

                            if ($Thumbprint -is [byte[]]) {
                                $Thumbprint = ($Thumbprint | ForEach-Object { $_.ToString("X2") }) -join ""
                            }

                            if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
                                $Cert = $StoreCerts | Where-Object {
                                    $_.Thumbprint -eq $Thumbprint
                                } | Select-Object -First 1

                                if ($Cert -and $Cert.NotAfter -lt $Now) {
                                    [PSCustomObject]@{
                                        Sitio      = $Site.Name
                                        Binding    = $Binding.bindingInformation
                                        Subject    = $Cert.Subject
                                        NotAfter   = $Cert.NotAfter
                                        Thumbprint = $Cert.Thumbprint
                                    }
                                }
                            }
                        }
                        catch {
                            # Ignora bindings puntuales problemáticos y sigue
                        }
                    }
                }
            }
        } -ErrorAction Stop

        return @($Results)
    }
    catch {
        $Msg = $_.Exception.Message
        Write-Log "Error validando certificados vencidos usados por IIS en [$ComputerName]. $Msg" "WARN"
        Write-WarningText "[WARN][DEBUG] Error IIS certs: $Msg"
        return $null
    }
}