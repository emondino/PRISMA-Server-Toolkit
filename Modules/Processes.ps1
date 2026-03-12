function Format-ProcessTable {
    param(
        [array]$Processes,
        [string]$Mode
    )

    if (-not $Processes -or $Processes.Count -eq 0) {
        Write-Host ""
        Write-Host "No hay datos para mostrar."
        return
    }

    if ($Mode -eq "Memory") {
        $Processes |
            Select-Object `
                @{Name='Proceso'; Expression = { $_.ProcessName }}, `
                @{Name='Id'; Expression = { $_.Id }}, `
                @{Name='MemoriaMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 2) }} |
            Format-Table -AutoSize
    }
    elseif ($Mode -eq "CPU") {
        $Processes |
            Select-Object `
                @{Name='Proceso'; Expression = { $_.ProcessName }}, `
                @{Name='Id'; Expression = { $_.Id }}, `
                @{Name='CPU(seg)'; Expression = { if ($_.CPU -ne $null) { [math]::Round($_.CPU, 2) } else { 0 } }}, `
                @{Name='MemoriaMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 2) }} |
            Format-Table -AutoSize
    }
    elseif ($Mode -eq "Search") {
        $Processes |
            Select-Object `
                @{Name='Proceso'; Expression = { $_.ProcessName }}, `
                @{Name='Id'; Expression = { $_.Id }}, `
                @{Name='CPU(seg)'; Expression = { if ($_.CPU -ne $null) { [math]::Round($_.CPU, 2) } else { 0 } }}, `
                @{Name='MemoriaMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 2) }} |
            Format-Table -AutoSize
    }
}

function Get-TopProcessesByMemory {
    param(
        [string]$ComputerName,
        [int]$Top = 10
    )

    try {
        Write-Log "Listando top $Top procesos por memoria en [$ComputerName]"

        $Processes = Get-Process -ComputerName $ComputerName -ErrorAction Stop |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First $Top

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " TOP $Top PROCESOS POR MEMORIA - $ComputerName"
        Write-Host "==========================================="
        Format-ProcessTable -Processes $Processes -Mode "Memory"
    }
    catch {
        Write-Log "Error listando procesos por memoria en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error listando procesos por memoria."
        Write-Host $_.Exception.Message
    }
}

function Get-TopProcessesByCPU {
    param(
        [string]$ComputerName,
        [int]$Top = 10
    )

    try {
        Write-Log "Listando top $Top procesos por CPU en [$ComputerName]"

        $Processes = Get-Process -ComputerName $ComputerName -ErrorAction Stop |
            Sort-Object CPU -Descending |
            Select-Object -First $Top

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " TOP $Top PROCESOS POR CPU - $ComputerName"
        Write-Host "==========================================="
        Write-Host "Nota: CPU(seg) representa tiempo acumulado de CPU, no porcentaje instantaneo."
        Write-Host ""
        Format-ProcessTable -Processes $Processes -Mode "CPU"
    }
    catch {
        Write-Log "Error listando procesos por CPU en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error listando procesos por CPU."
        Write-Host $_.Exception.Message
    }
}

function Find-ProcessByName {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese nombre del proceso o parte del nombre"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-Host "Busqueda vacia."
        return
    }

    try {
        Write-Log "Buscando procesos con texto [$SearchText] en [$ComputerName]"

        $Processes = Get-Process -ComputerName $ComputerName -ErrorAction Stop |
            Where-Object { $_.ProcessName -like "*$SearchText*" } |
            Sort-Object ProcessName

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " BUSQUEDA DE PROCESOS - $ComputerName"
        Write-Host "==========================================="

        if ($Processes -and $Processes.Count -gt 0) {
            Format-ProcessTable -Processes $Processes -Mode "Search"
        }
        else {
            Write-Host "No se encontraron procesos que coincidan con la busqueda."
        }
    }
    catch {
        Write-Log "Error buscando procesos en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error buscando procesos."
        Write-Host $_.Exception.Message
    }
}

function Get-ProcessOwnerSafe {
    param(
        [object]$WmiProcess
    )

    try {
        $OwnerInfo = Invoke-CimMethod -InputObject $WmiProcess -MethodName GetOwner -ErrorAction Stop
        if ($OwnerInfo.ReturnValue -eq 0) {
            return ("{0}\{1}" -f $OwnerInfo.Domain, $OwnerInfo.User)
        }
        else {
            return "N/A"
        }
    }
    catch {
        return "N/A"
    }
}

function Get-ProcessesWithUser {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Listando procesos con usuario en [$ComputerName]"

        $WmiProcesses = Get-CimInstance Win32_Process -ComputerName $ComputerName -ErrorAction Stop
        $PsProcesses  = Get-Process -ComputerName $ComputerName -ErrorAction SilentlyContinue

        $Results = foreach ($Proc in $WmiProcesses) {
            $Owner = Get-ProcessOwnerSafe -WmiProcess $Proc

            $MatchingProcess = $PsProcesses | Where-Object { $_.Id -eq $Proc.ProcessId } | Select-Object -First 1
            $MemoryMB = if ($MatchingProcess) { [math]::Round($MatchingProcess.WorkingSet64 / 1MB, 2) } else { 0 }

            [PSCustomObject]@{
                Proceso   = $Proc.Name
                Id        = $Proc.ProcessId
                Usuario   = $Owner
                MemoriaMB = $MemoryMB
            }
        }

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " PROCESOS CON USUARIO - $ComputerName"
        Write-Host "==========================================="

    $Results |
    Sort-Object Usuario, Proceso |
    Format-Table -AutoSize

    }
    catch {
        Write-Log "Error listando procesos con usuario en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error listando procesos con usuario."
        Write-Host $_.Exception.Message
    }
}

function Show-ProcessesMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Host "==========================================="
        Write-Host " MODULO PROCESOS"
        Write-Host " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Top 10 procesos por memoria"
        Write-Host "2. Top 10 procesos por CPU"
        Write-Host "3. Buscar proceso por nombre"
        Write-Host "4. Listar procesos con usuario"
        Write-Host "5. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Get-TopProcessesByMemory -ComputerName $ComputerName -Top 10
                Pause-Console
            }
            "2" {
                Get-TopProcessesByCPU -ComputerName $ComputerName -Top 10
                Pause-Console
            }
            "3" {
                Find-ProcessByName -ComputerName $ComputerName
                Pause-Console
            }
            "4" {
                Get-ProcessesWithUser -ComputerName $ComputerName
                Pause-Console
            }
            "5" {
                Write-Log "Salida del modulo Procesos para [$ComputerName]"
            }
            default {
                Write-Host "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "5")
}