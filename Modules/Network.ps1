function Get-ProcessNameByIdSafe {
    param(
        [int]$ProcessId,
        [string]$ComputerName
    )

    try {
        $Proc = Get-Process -ComputerName $ComputerName -Id $ProcessId -ErrorAction Stop
        return $Proc.ProcessName
    }
    catch {
        return "N/A"
    }
}

function Get-NetworkConfigReport {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Obteniendo configuracion de red en [$ComputerName]"

        $Configs = Get-CimInstance Win32_NetworkAdapterConfiguration -ComputerName $ComputerName -ErrorAction Stop |
            Where-Object { $_.IPEnabled -eq $true }

        Write-Host ""
        Write-Title " CONFIGURACION DE RED - $ComputerName"
        

        foreach ($Cfg in $Configs) {
            Write-Host ""
            Write-Host ("Interfaz      : {0}" -f $Cfg.Description)
            Write-Host ("MAC           : {0}" -f $Cfg.MACAddress)
            Write-Host ("IP            : {0}" -f (($Cfg.IPAddress -join ", ")))
            Write-Host ("Mascara       : {0}" -f (($Cfg.IPSubnet -join ", ")))
            Write-Host ("Gateway       : {0}" -f (($Cfg.DefaultIPGateway -join ", ")))
            Write-Host ("DNS           : {0}" -f (($Cfg.DNSServerSearchOrder -join ", ")))
            Write-Host ("DHCP Habilitado: {0}" -f $Cfg.DHCPEnabled)
            Write-Host "-------------------------------------------"
        }
    }
    catch {
        Write-Log "Error obteniendo configuracion de red en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error obteniendo configuracion de red."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-ListeningPortsModern {
    param(
        [string]$ComputerName
    )

    try {
        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            $Processes = Get-Process | Select-Object Id, ProcessName

            $Listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop

            foreach ($Conn in $Listeners) {
                $Proc = $Processes | Where-Object { $_.Id -eq $Conn.OwningProcess } | Select-Object -First 1

                [PSCustomObject]@{
                    Protocolo = "TCP"
                    IPLocal   = $Conn.LocalAddress
                    Puerto    = $Conn.LocalPort
                    PID       = $Conn.OwningProcess
                    Proceso   = if ($Proc) { $Proc.ProcessName } else { "N/A" }
                }
            }
        } -ErrorAction Stop

        return @($Results) | Select-Object Protocolo, IPLocal, Puerto, PID, Proceso | Sort-Object Puerto, Proceso
    }
    catch {
        return $null
    }
}

function Get-ListeningPortsLegacy {
    param(
        [string]$ComputerName
    )

    try {
        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            $Processes = Get-Process | Select-Object Id, ProcessName
            $Output = netstat -ano -p tcp | findstr /I "LISTENING"

            foreach ($Line in $Output) {
                $CleanLine = ($Line -replace '\s+', ' ').Trim()
                $Parts = $CleanLine.Split(' ')

                if ($Parts.Count -ge 5) {
                    $Proto = $Parts[0]
                    $LocalEndpoint = $Parts[1]
                    $State = $Parts[3]
                    $PID = $Parts[4]

                    if ($State -eq "LISTENING") {
                        $LastColon = $LocalEndpoint.LastIndexOf(":")
                        if ($LastColon -gt 0) {
                            $LocalIP = $LocalEndpoint.Substring(0, $LastColon)
                            $LocalPort = $LocalEndpoint.Substring($LastColon + 1)

                            $Proc = $Processes | Where-Object { $_.Id -eq [int]$PID } | Select-Object -First 1

                            [PSCustomObject]@{
                                Protocolo = $Proto
                                IPLocal   = $LocalIP
                                Puerto    = [int]$LocalPort
                                PID       = [int]$PID
                                Proceso   = if ($Proc) { $Proc.ProcessName } else { "N/A" }
                            }
                        }
                    }
                }
            }
        } -ErrorAction Stop

        return @($Results) | Select-Object Protocolo, IPLocal, Puerto, PID, Proceso | Sort-Object Puerto, Proceso
    }
    catch {
        Write-Log "Error obteniendo puertos en escucha con metodo legacy en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Get-ListeningPorts {
    param(
        [string]$ComputerName
    )

    Write-Log "Obteniendo puertos en escucha en [$ComputerName]"

    $Ports = Get-ListeningPortsModern -ComputerName $ComputerName

    if (-not $Ports -or @($Ports).Count -eq 0) {
        Write-Log "Get-NetTCPConnection no disponible o fallo en [$ComputerName]. Se utilizara netstat -ano" "WARN"
        $Ports = Get-ListeningPortsLegacy -ComputerName $ComputerName
    }

    Write-Host ""
    Write-Title " PUERTOS EN ESCUCHA - $ComputerName"

    if ($Ports -and @($Ports).Count -gt 0) {
        @($Ports) | Format-Table -AutoSize
    }
    else {
        Write-WarningText "No se encontraron puertos en escucha o no fue posible obtenerlos."
    }
}

function Find-PortByNumber {
    param(
        [string]$ComputerName
    )

    $PortNumber = Read-Host "Ingrese el numero de puerto"

    if ($PortNumber -notmatch '^\d+$') {
        Write-ErrorText "Puerto invalido."
        return
    }

    Write-Log "Buscando puerto [$PortNumber] en [$ComputerName]"

    $Ports = Get-ListeningPortsModern -ComputerName $ComputerName

    if (-not $Ports) {
        Write-Log "Busqueda de puerto via Get-NetTCPConnection no disponible en [$ComputerName]. Se utilizara netstat -ano" "WARN"
        $Ports = Get-ListeningPortsLegacy -ComputerName $ComputerName
    }

    $Matches = @($Ports) | Where-Object { $_.Puerto -eq [int]$PortNumber }

    Write-Host ""
    Write-Title " BUSQUEDA DE PUERTO - $ComputerName"
    

    if (@($Matches).Count -gt 0) {
        $Matches | Format-Table -AutoSize
    }
    else {
        Write-Success "No se encontraron procesos escuchando en el puerto $PortNumber."
    }
}

function Show-NetworkMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Title " MODULO RED"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Ver configuracion IP"
        Write-Host "2. Ver puertos en escucha"
        Write-Host "3. Buscar puerto especifico"
        Write-Host "4. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Get-NetworkConfigReport -ComputerName $ComputerName
                Pause-Console
            }
            "2" {
                Get-ListeningPorts -ComputerName $ComputerName
                Pause-Console
            }
            "3" {
                Find-PortByNumber -ComputerName $ComputerName
                Pause-Console
            }
            "4" {
                Write-Log "Salida del modulo Red para [$ComputerName]"
            }
            default {
                Write-ErrorText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "4")
}