function Get-ServerInfoReport {
    param(
        [string]$ComputerName
    )

    try {
        $OS = Get-CimInstance Win32_OperatingSystem -ComputerName $ComputerName
        $CS = Get-CimInstance Win32_ComputerSystem -ComputerName $ComputerName
        $CPU = Get-CimInstance Win32_Processor -ComputerName $ComputerName | Select-Object -First 1
        $NIC = Get-CimInstance Win32_NetworkAdapterConfiguration -ComputerName $ComputerName |
               Where-Object { $_.IPEnabled -eq $true } |
               Select-Object -First 1

        $TotalRAMGB = [math]::Round($CS.TotalPhysicalMemory / 1GB, 2)
        $FreeRAMGB  = [math]::Round(($OS.FreePhysicalMemory * 1KB) / 1GB, 2)
        $UsedRAMGB  = [math]::Round($TotalRAMGB - $FreeRAMGB, 2)

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " INFORMACION DEL SERVIDOR"
        Write-Host "==========================================="
        Write-Host "Servidor          : $ComputerName"
        Write-Host "Sistema Operativo : $($OS.Caption)"
        Write-Host "Version           : $($OS.Version)"
        Write-Host "Ultimo reinicio   : $($OS.LastBootUpTime)"
        Write-Host "Fabricante        : $($CS.Manufacturer)"
        Write-Host "Modelo            : $($CS.Model)"
        Write-Host "CPU               : $($CPU.Name)"
        Write-Host "RAM Total (GB)    : $TotalRAMGB"
        Write-Host "RAM Libre (GB)    : $FreeRAMGB"
        Write-Host "RAM Usada (GB)    : $UsedRAMGB"
        Write-Host "Dominio           : $($CS.Domain)"
        Write-Host "IP                : $($NIC.IPAddress[0])"
        Write-Host "==========================================="
    }
    catch {
        Write-Host "Error obteniendo informacion del servidor"
        Write-Host $_.Exception.Message
    }
}