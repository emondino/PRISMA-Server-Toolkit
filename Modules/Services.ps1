function Get-ServiceMatches {
    param(
        [string]$ComputerName,
        [string]$SearchText
    )

    try {
        $AllServices = Get-CimInstance Win32_Service -ComputerName $ComputerName -ErrorAction Stop

        $Matches = $AllServices | Where-Object {
            $_.DisplayName -like "*$SearchText*" -or $_.Name -like "*$SearchText*"
        } | Sort-Object DisplayName

        return $Matches
    }
    catch {
        Write-Log "Error buscando servicios en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error buscando servicios en el servidor."
        Write-ErrorText $_.Exception.Message
        return @()
    }
}

function Select-ServiceFromMatches {
    param(
        [array]$Matches
    )

    $Matches = @($Matches)

    if ($Matches.Count -eq 0) {
        Write-Host ""
        Write-WarningText "No se encontraron servicios que coincidan con la busqueda."
        return $null
    }

    if ($Matches.Count -eq 1) {
        return $Matches[0]
    }

    Write-Host ""
    Write-Highlight "Se encontraron varias coincidencias:"
    Write-Host ""

    $OptionsMap = @{}

    for ($i = 0; $i -lt $Matches.Count; $i++) {
        $Key = [string]($i + 1)
        $Match = $Matches[$i]

        $OptionsMap[$Key] = $Match

        Write-Host ("{0}. [{1}] {2} | Inicio: {3}" -f $Key, $Match.State, $Match.DisplayName, $Match.StartMode)
    }

    Write-Host ""
    $Selection = (Read-Host "Seleccione un numero").Trim()

    if ($OptionsMap.ContainsKey($Selection)) {
        return $OptionsMap[$Selection]
    }

    Write-ErrorText "Seleccion invalida."
    return $null
}

function Confirm-Action {
    param(
        [string]$Message
    )

    $Answer = Read-Host "$Message (S/N)"
    return ($Answer -match '^[sS]$')
}

function Show-ServiceSummary {
    param(
        [object]$Service,
        [string]$ComputerName
    )

    Write-Host ""
    Write-Title " DETALLE DEL SERVICIO"
    Write-Host "Servidor : $ComputerName"
    Write-Host "Alias    : $($Service.DisplayName)"
    Write-Host "Estado   : $($Service.State)"
    Write-Host "Inicio   : $($Service.StartMode)"
    Write-Host "==========================================="
}

function Format-ServiceTable {
    param(
        [array]$Services
    )

    if (-not $Services -or $Services.Count -eq 0) {
        Write-Host ""
        Write-WarningText "No hay datos para mostrar."
        return
    }

    $Services |
        Select-Object `
            @{Name='Estado'; Expression = { $_.State }}, `
            @{Name='Alias'; Expression = { $_.DisplayName }}, `
            @{Name='Inicio'; Expression = { $_.StartMode }} |
        Format-Table -AutoSize
}

function Get-RunningDependentServices {
    param(
        [string]$ComputerName,
        [string]$ServiceName
    )

    try {
        $DependentServices = Get-Service -ComputerName $ComputerName -Name $ServiceName -ErrorAction Stop |
            Select-Object -ExpandProperty DependentServices |
            Where-Object { $_.Status -eq 'Running' }

        return $DependentServices
    }
    catch {
        Write-Log "Error consultando dependencias del servicio [$ServiceName] en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Wait-ServiceStatus {
    param(
        [string]$ComputerName,
        [string]$ServiceName,
        [string]$DesiredStatus,
        [int]$TimeoutSeconds = 20
    )

    $StartTime = Get-Date

    do {
        try {
            $CurrentService = Get-Service -ComputerName $ComputerName -Name $ServiceName -ErrorAction Stop
            if ($CurrentService.Status.ToString().ToLower() -eq $DesiredStatus.ToLower()) {
                return $true
            }
        }
        catch {
            Write-Log "Error esperando estado [$DesiredStatus] para servicio [$ServiceName] en [$ComputerName]. $($_.Exception.Message)" "ERROR"
            return $false
        }

        Start-Sleep -Seconds 1
    }
    while (((Get-Date) - $StartTime).TotalSeconds -lt $TimeoutSeconds)

    return $false
}

function Find-ServiceInteractive {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese alias del servicio o parte del nombre"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-WarningText "Busqueda vacia."
        return $null
    }

$Matches = @(Get-ServiceMatches -ComputerName $ComputerName -SearchText $SearchText)
$SelectedService = Select-ServiceFromMatches -Matches $Matches

    return $SelectedService
}

function Show-AllServices {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Listando todos los servicios en [$ComputerName]"
        $Services = Get-CimInstance Win32_Service -ComputerName $ComputerName -ErrorAction Stop |
            Sort-Object DisplayName

        Write-Host ""
        Write-Title " TODOS LOS SERVICIOS - $ComputerName"
        Format-ServiceTable -Services $Services
    }
    catch {
        Write-Log "Error listando todos los servicios en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error listando todos los servicios."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-StoppedServices {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Listando servicios detenidos en [$ComputerName]"
        $Services = Get-CimInstance Win32_Service -ComputerName $ComputerName -ErrorAction Stop |
            Where-Object { $_.State -eq 'Stopped' } |
            Sort-Object DisplayName

        Write-Host ""
        Write-Title " SERVICIOS DETENIDOS - $ComputerName"
        Format-ServiceTable -Services $Services
    }
    catch {
        Write-Log "Error listando servicios detenidos en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error listando servicios detenidos."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-AutoStoppedServices {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Listando servicios automaticos detenidos en [$ComputerName]"
        $Services = Get-CimInstance Win32_Service -ComputerName $ComputerName -ErrorAction Stop |
            Where-Object { $_.State -eq 'Stopped' -and $_.StartMode -eq 'Auto' } |
            Sort-Object DisplayName

        Write-Host ""
        Write-Title " SERVICIOS AUTOMATICOS DETENIDOS - $ComputerName"
        Format-ServiceTable -Services $Services
    }
    catch {
        Write-Log "Error listando servicios automaticos detenidos en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error listando servicios automaticos detenidos."
        Write-ErrorText $_.Exception.Message
    }
}

function Start-ServiceSafe {
    param(
        [string]$ComputerName
    )

    $SelectedService = Find-ServiceInteractive -ComputerName $ComputerName
    if (-not $SelectedService) { return }

    Show-ServiceSummary -Service $SelectedService -ComputerName $ComputerName

    if ($SelectedService.State -eq 'Running') {
        Write-Host ""
        Write-Info "El servicio ya se encuentra en ejecucion."
        return
    }

    if (-not (Confirm-Action -Message "Confirma iniciar el servicio '$($SelectedService.DisplayName)'")) {
        Write-WarningText "Accion cancelada."
        return
    }

    try {
        Write-Info "Iniciando servicio [$($SelectedService.Name)] '$($SelectedService.DisplayName)' en [$ComputerName]"
        Start-Service -InputObject (Get-Service -ComputerName $ComputerName -Name $SelectedService.Name -ErrorAction Stop) -ErrorAction Stop

        if (Wait-ServiceStatus -ComputerName $ComputerName -ServiceName $SelectedService.Name -DesiredStatus 'Running') {
            Write-Log "Servicio '$($SelectedService.DisplayName)' iniciado correctamente en [$ComputerName]"
            Write-Success "Servicio iniciado correctamente."
        }
        else {
            Write-Log "Timeout esperando inicio del servicio '$($SelectedService.DisplayName)' en [$ComputerName]" "WARN"
            Write-WarningText "El servicio recibio la orden, pero no se confirmo su inicio dentro del tiempo esperado."
        }
    }
    catch {
        Write-Log "Error iniciando servicio '$($SelectedService.DisplayName)' en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error iniciando el servicio."
        Write-ErrorText $_.Exception.Message
    }
}

function Stop-ServiceSafe {
    param(
        [string]$ComputerName
    )

    $SelectedService = Find-ServiceInteractive -ComputerName $ComputerName
    if (-not $SelectedService) { return }

    Show-ServiceSummary -Service $SelectedService -ComputerName $ComputerName

    if ($SelectedService.State -eq 'Stopped') {
        Write-Host ""
        Write-Info "El servicio ya se encuentra detenido."
        return
    }

    $RunningDependents = Get-RunningDependentServices -ComputerName $ComputerName -ServiceName $SelectedService.Name
    if ($RunningDependents -and $RunningDependents.Count -gt 0) {
        Write-Host ""
        Write-WarningText "No se puede detener el servicio porque existen servicios dependientes en ejecucion:"
        Write-Host ""

        foreach ($Dependent in $RunningDependents) {
            Write-Host ("- {0}" -f $Dependent.DisplayName)
        }

        Write-Host ""
        Write-WarningText "Accion cancelada por seguridad."
        Write-Log "Cancelada detencion de servicio '$($SelectedService.DisplayName)' en [$ComputerName] por dependientes activos" "WARN"
        return
    }

    if (-not (Confirm-Action -Message "Confirma detener el servicio '$($SelectedService.DisplayName)'")) {
        Write-ErrorText "Accion cancelada."
        return
    }

    try {
        Write-Log "Deteniendo servicio [$($SelectedService.Name)] '$($SelectedService.DisplayName)' en [$ComputerName]"
        Stop-Service -InputObject (Get-Service -ComputerName $ComputerName -Name $SelectedService.Name -ErrorAction Stop) -ErrorAction Stop

        if (Wait-ServiceStatus -ComputerName $ComputerName -ServiceName $SelectedService.Name -DesiredStatus 'Stopped') {
            Write-Log "Servicio '$($SelectedService.DisplayName)' detenido correctamente en [$ComputerName]"
            Write-Success "Servicio detenido correctamente."
        }
        else {
            Write-Log "Timeout esperando detencion del servicio '$($SelectedService.DisplayName)' en [$ComputerName]" "WARN"
            Write-WarningText "El servicio recibio la orden, pero no se confirmo su detencion dentro del tiempo esperado."
        }
    }
    catch {
        Write-Log "Error deteniendo servicio '$($SelectedService.DisplayName)' en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error deteniendo el servicio."
        Write-ErrorText $_.Exception.Message
    }
}

function Restart-ServiceSafe {
    param(
        [string]$ComputerName
    )

    $SelectedService = Find-ServiceInteractive -ComputerName $ComputerName
    if (-not $SelectedService) { return }

    Show-ServiceSummary -Service $SelectedService -ComputerName $ComputerName

    $RunningDependents = Get-RunningDependentServices -ComputerName $ComputerName -ServiceName $SelectedService.Name
    if ($RunningDependents -and $RunningDependents.Count -gt 0) {
        Write-Host ""
        Write-WarningText "No se puede reiniciar el servicio porque existen servicios dependientes en ejecucion:"
        Write-Host ""

        foreach ($Dependent in $RunningDependents) {
            Write-Host ("- {0}" -f $Dependent.DisplayName)
        }

        Write-Host ""
        Write-WarningText "Accion cancelada por seguridad."
        Write-Log "Cancelado reinicio de servicio '$($SelectedService.DisplayName)' en [$ComputerName] por dependientes activos" "WARN"
        return
    }

    if (-not (Confirm-Action -Message "Confirma reiniciar el servicio '$($SelectedService.DisplayName)'")) {
        Write-WarningText "Accion cancelada."
        return
    }

    try {
        if ($SelectedService.State -eq 'Running') {
            Write-Log "Deteniendo para reinicio servicio [$($SelectedService.Name)] '$($SelectedService.DisplayName)' en [$ComputerName]"
            Stop-Service -InputObject (Get-Service -ComputerName $ComputerName -Name $SelectedService.Name -ErrorAction Stop) -ErrorAction Stop

            if (-not (Wait-ServiceStatus -ComputerName $ComputerName -ServiceName $SelectedService.Name -DesiredStatus 'Stopped')) {
                Write-Log "Timeout esperando detencion previa al reinicio del servicio '$($SelectedService.DisplayName)' en [$ComputerName]" "WARN"
                Write-WarningText "No se pudo confirmar la detencion del servicio antes del reinicio."
                return
            }
        }

        Write-Log "Iniciando nuevamente servicio [$($SelectedService.Name)] '$($SelectedService.DisplayName)' en [$ComputerName]"
        Start-Service -InputObject (Get-Service -ComputerName $ComputerName -Name $SelectedService.Name -ErrorAction Stop) -ErrorAction Stop

        if (Wait-ServiceStatus -ComputerName $ComputerName -ServiceName $SelectedService.Name -DesiredStatus 'Running') {
            Write-Log "Servicio '$($SelectedService.DisplayName)' reiniciado correctamente en [$ComputerName]"
            Write-Success "Servicio reiniciado correctamente."
        }
        else {
            Write-Log "Timeout esperando inicio posterior al reinicio del servicio '$($SelectedService.DisplayName)' en [$ComputerName]" "WARN"
            Write-WarningText "No se pudo confirmar el inicio del servicio luego del reinicio."
        }
    }
    catch {
        Write-Log "Error reiniciando servicio '$($SelectedService.DisplayName)' en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error reiniciando el servicio."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-ServicesMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Title " MODULO SERVICIOS"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Consultar un servicio"
        Write-Host "2. Listar todos los servicios"
        Write-Host "3. Listar servicios detenidos"
        Write-Host "4. Listar servicios automaticos detenidos"
        Write-Host "5. Iniciar servicio"
        Write-Host "6. Detener servicio"
        Write-Host "7. Reiniciar servicio"
        Write-Host "8. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                $SelectedService = Find-ServiceInteractive -ComputerName $ComputerName
                if ($SelectedService) {
                    Show-ServiceSummary -Service $SelectedService -ComputerName $ComputerName
                    Write-Log "Consulta de servicio '$($SelectedService.DisplayName)' en [$ComputerName]"
                }
                Pause-Console
            }
            "2" {
                Show-AllServices -ComputerName $ComputerName
                Pause-Console
            }
            "3" {
                Show-StoppedServices -ComputerName $ComputerName
                Pause-Console
            }
            "4" {
                Show-AutoStoppedServices -ComputerName $ComputerName
                Pause-Console
            }
            "5" {
                Start-ServiceSafe -ComputerName $ComputerName
                Pause-Console
            }
            "6" {
                Stop-ServiceSafe -ComputerName $ComputerName
                Pause-Console
            }
            "7" {
                Restart-ServiceSafe -ComputerName $ComputerName
                Pause-Console
            }
            "8" {
                Write-Log "Salida del modulo Servicios para [$ComputerName]"
            }
            default {
                Write-ErrorText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "8")
}