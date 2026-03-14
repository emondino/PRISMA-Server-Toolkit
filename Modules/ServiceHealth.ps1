function Get-ServiceHealthCheck {
    param(
        [string]$ComputerName
    )

    $DefaultServiceChecks = @(
        "Spooler",
        "w32time",
        "wuauserv"
    )

    $Results = @()
    $OkCount = 0
    $AlertCount = 0
    $InfoCount = 0

    Write-Log "Iniciando Health Check de servicios en [$ComputerName]"

    try {
        $AllServices = Get-CimInstance Win32_Service -ComputerName $ComputerName -ErrorAction Stop
    }
    catch {
        Write-Log "Error obteniendo servicios para Health Check en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error obteniendo servicios del servidor."
        Write-ErrorText $_.Exception.Message
        return
    }

    foreach ($ServiceName in $DefaultServiceChecks) {
        $Svc = $AllServices | Where-Object { $_.Name -eq $ServiceName } | Select-Object -First 1

        if ($Svc) {
            $StatusLabel = "INFO"

            if ($Svc.State -eq "Running" -and $Svc.StartMode -eq "Auto") {
                $StatusLabel = "OK"
                $OkCount++
            }
            elseif ($Svc.State -eq "Stopped" -and $Svc.StartMode -eq "Auto") {
                $StatusLabel = "ALERTA"
                $AlertCount++
            }
            else {
                $StatusLabel = "INFO"
                $InfoCount++
            }

            $Results += [PSCustomObject]@{
                EstadoCheck = $StatusLabel
                Alias       = $Svc.DisplayName
                Estado      = $Svc.State
                Inicio      = $Svc.StartMode
            }
        }
        else {
            $Results += [PSCustomObject]@{
                EstadoCheck = "NO ENCONTRADO"
                Alias       = $ServiceName
                Estado      = "-"
                Inicio      = "-"
            }
        }
    }

    $AutoStopped = $AllServices |
        Where-Object { $_.State -eq 'Stopped' -and $_.StartMode -eq 'Auto' } |
        Sort-Object DisplayName

    Write-Host ""
    Write-Title " HEALTH CHECK DE SERVICIOS"
    Write-Highlight " Servidor objetivo: $ComputerName"
    Write-Host "==========================================="
    Write-Highlight "Servicios monitoreados:"
    Write-Host ""

    foreach ($Result in $Results) {
        switch ($Result.EstadoCheck) {
            "OK" {
                Write-Host ("[OK]         {0,-35} | {1,-8} | {2}" -f $Result.Alias, $Result.Estado, $Result.Inicio)
            }
            "ALERTA" {
                Write-Host ("[ALERTA]     {0,-35} | {1,-8} | {2}" -f $Result.Alias, $Result.Estado, $Result.Inicio)
            }
            "INFO" {
                Write-Host ("[INFO]       {0,-35} | {1,-8} | {2}" -f $Result.Alias, $Result.Estado, $Result.Inicio)
            }
            default {
                Write-Host ("[NO ENCONTRADO] {0,-30} | {1,-8} | {2}" -f $Result.Alias, $Result.Estado, $Result.Inicio)
            }
        }
    }

    Write-Host ""
    Write-Host "-------------------------------------------"
    Write-Highlight "Servicios automaticos detenidos detectados:"
    if ($AutoStopped.Count -gt 0) {
        foreach ($Svc in $AutoStopped) {
            Write-Host ("- {0}" -f $Svc.DisplayName)
        }
    }
    else {
        Write-Host "Ninguno."
    }

    Write-Host "-------------------------------------------"
    Write-Highlight "Resumen:"
    Write-Host "OK     : $OkCount"
    Write-Host "ALERTA : $AlertCount"
    Write-Host "INFO   : $InfoCount"
    Write-Host "Auto detenidos: $($AutoStopped.Count)"
    Write-Host "==========================================="

    Write-Log "Health Check finalizado en [$ComputerName]. OK=$OkCount ALERTA=$AlertCount INFO=$InfoCount AutoDetenidos=$($AutoStopped.Count)"
}