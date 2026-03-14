function Invoke-PRISMAHealthCheck {

    param(
        [string]$ComputerName
    )

    Write-Title "PRISMA HEALTH CHECK"
    Write-Info "Consultando servidor $ComputerName..."
    Write-Host ""

    $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {

        $OS = (Get-CimInstance Win32_OperatingSystem).Caption

        $CPU = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        $CPU = [math]::Round($CPU,2)

        $Mem = Get-CimInstance Win32_OperatingSystem
        $FreeMem = [math]::Round($Mem.FreePhysicalMemory / 1MB,2)

        $Disks = Get-CimInstance Win32_LogicalDisk |
            Where-Object { $_.DriveType -eq 3 } |
            Select-Object DeviceID,
                @{n="FreeGB";e={[math]::Round($_.FreeSpace/1GB,2)}},
                @{n="TotalGB";e={[math]::Round($_.Size/1GB,2)}}

        # Eventos recientes
        $AppErrors = Get-WinEvent -FilterHashtable @{
            LogName='Application'
            Level=2
            StartTime=(Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue | Measure-Object

        $SysErrors = Get-WinEvent -FilterHashtable @{
            LogName='System'
            Level=2
            StartTime=(Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue | Measure-Object

        $LogonFailures = Get-WinEvent -FilterHashtable @{
            LogName='Security'
            Id=4625
            StartTime=(Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue | Measure-Object

        # IIS check
        $IISInstalled = $false
        $Sites = 0
        $StoppedPools = @()

        if (Get-Module -ListAvailable -Name WebAdministration) {
            try {
                Import-Module WebAdministration -ErrorAction Stop
                $IISInstalled = $true

                $Sites = @(Get-Website).Count

                $StoppedPools = @(
                    Get-ChildItem IIS:\AppPools | Where-Object {
                        $_.state -ne "Started"
                    } | Select-Object -ExpandProperty Name
                )
            }
            catch {
                $IISInstalled = $false
                $Sites = 0
                $StoppedPools = @()
            }
        }

        # Certificates
        $Certs = Get-ChildItem Cert:\LocalMachine\My |
            Where-Object {
                $_.NotAfter -lt (Get-Date).AddDays(30)
            }

        [PSCustomObject]@{
            OS            = $OS
            CPU           = $CPU
            FreeMem       = $FreeMem
            Disks         = $Disks

            IISInstalled  = $IISInstalled
            SiteCount     = $Sites
            StoppedPools  = $StoppedPools

            ExpiringCerts = $Certs.Count

            AppErrors     = $AppErrors.Count
            SysErrors     = $SysErrors.Count
            LogonFailures = $LogonFailures.Count
        }

    }

    Write-Success "Sistema operativo: $($Result.OS)"

    # CPU
    if ($Result.CPU -gt 80) {
        Write-WarningText "CPU alta: $($Result.CPU)%"
    }
    else {
        Write-Success "CPU: $($Result.CPU)%"
    }

    # Memoria
    if ($Result.FreeMem -lt 2) {
        Write-WarningText "Memoria baja: $($Result.FreeMem) GB"
    }
    else {
        Write-Success "Memoria libre: $($Result.FreeMem) GB"
    }

    # Discos
    foreach ($Disk in $Result.Disks) {

        $Used = 100 - (($Disk.FreeGB / $Disk.TotalGB) * 100)
        $Used = [math]::Round($Used,2)

        if ($Used -gt 85) {
            Write-WarningText "Disco $($Disk.DeviceID) usado $Used%"
        }
        else {
            Write-Success "Disco $($Disk.DeviceID) usado $Used%"
        }
    }

    # IIS
    if ($Result.IISInstalled) {

        Write-Success "IIS instalado"
        Write-Info "Sitios IIS: $($Result.SiteCount)"

        if ($Result.StoppedPools.Count -gt 0) {
            Write-WarningText "AppPools detenidos: $($Result.StoppedPools.Count)"
        }
        else {
            Write-Success "AppPools activos"
        }
    }
    else {
        Write-WarningText "IIS no instalado"
    }

    # Certificados
    if ($Result.ExpiringCerts -gt 0) {
        Write-WarningText "Certificados por vencer (<30 dias): $($Result.ExpiringCerts)"
    }
    else {
        Write-Success "Certificados OK"
    }

    # Eventos
    Write-Highlight "Eventos ultimas 24 horas"

    if ($Result.AppErrors -gt 0) {
        Write-WarningText "Application errors: $($Result.AppErrors)"
    }
    else {
        Write-Success "Application errors: 0"
    }

    if ($Result.SysErrors -gt 0) {
        Write-WarningText "System errors: $($Result.SysErrors)"
    }
    else {
        Write-Success "System errors: 0"
    }

    if ($Result.LogonFailures -gt 20) {
        Write-WarningText "Logon failures: $($Result.LogonFailures)"
    }
    else {
        Write-Info "Logon failures: $($Result.LogonFailures)"
    }
}