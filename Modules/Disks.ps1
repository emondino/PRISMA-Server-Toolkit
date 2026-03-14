function Get-DiskReport {
    param(
        [string]$ComputerName
    )

    try {
        $Disks = Get-CimInstance Win32_LogicalDisk -ComputerName $ComputerName -Filter "DriveType=3"

        Write-Host ""
        Write-Title " DISCOS"
        
        foreach ($Disk in $Disks) {
            $SizeGB = [math]::Round($Disk.Size / 1GB, 2)
            $FreeGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
            $UsedGB = [math]::Round($SizeGB - $FreeGB, 2)
            $FreePct = if ($SizeGB -gt 0) { [math]::Round(($Disk.FreeSpace / $Disk.Size) * 100, 2) } else { 0 }

            Write-Host ("Unidad: {0} | Total: {1} GB | Libre: {2} GB | Usado: {3} GB | Libre %: {4}" -f `
                $Disk.DeviceID, $SizeGB, $FreeGB, $UsedGB, $FreePct)
        }

        Write-Host "==========================================="
    }
    catch {
        Write-ErrorText "Error obteniendo informacion de discos"
        Write-ErrorText $_.Exception.Message
    }
}