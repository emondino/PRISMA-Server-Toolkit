function Format-EventTable {
    param(
        [array]$Events
    )

    if (-not $Events -or $Events.Count -eq 0) {
        Write-Host ""
        Write-Info "No se encontraron eventos."
        return
    }

    $Events |
        Select-Object `
            @{Name='FechaHora'; Expression = { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") }}, `
            @{Name='EventID'; Expression = { $_.Id }}, `
            @{Name='Origen'; Expression = { $_.ProviderName }}, `
            @{Name='Nivel'; Expression = { $_.LevelDisplayName }}, `
            @{Name='Mensaje'; Expression = {
                if ($_.Message) {
                    ($_.Message -replace "`r|`n", " ").Substring(0, [Math]::Min(120, ($_.Message -replace "`r|`n", " ").Length))
                }
                else {
                    ""
                }
            }} |
        Format-Table -AutoSize
}

function Get-RecentApplicationErrors {
    param(
        [string]$ComputerName,
        [int]$Hours = 24
    )

    try {
        Write-Log "Consultando errores de Application ultimas $Hours hs en [$ComputerName]"

        $StartTime = (Get-Date).AddHours(-$Hours)

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'Application'
            StartTime = $StartTime
            Level     = 2
        } -ErrorAction Stop

        Write-Host ""
        Write-Title " ERRORES APPLICATION - $ComputerName"
        Write-Highlight " Ultimas $Hours horas"
        Write-Host "==========================================="

        Format-EventTable -Events $Events
    }
    catch {
        Write-Log "Error consultando Application en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando eventos de Application."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-RecentSystemErrors {
    param(
        [string]$ComputerName,
        [int]$Hours = 24
    )

    try {
        Write-Log "Consultando errores de System ultimas $Hours hs en [$ComputerName]"

        $StartTime = (Get-Date).AddHours(-$Hours)

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'System'
            StartTime = $StartTime
            Level     = 2
        } -ErrorAction Stop

        Write-Host ""
        Write-Title " ERRORES SYSTEM - $ComputerName"
        Write-Highlight " Ultimas $Hours horas"
        Write-Host "==========================================="

        Format-EventTable -Events $Events
    }
    catch {
        Write-Log "Error consultando System en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando eventos de System."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-RecentSecurityLogonFailures {
    param(
        [string]$ComputerName,
        [int]$Hours = 24
    )

    try {
        Write-Info "Consultando Security 4625 ultimas $Hours hs en [$ComputerName]"

        $StartTime = (Get-Date).AddHours(-$Hours)

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4625
            StartTime = $StartTime
        } -ErrorAction Stop

        $Results = @(
    foreach ($Event in $Events) {
            try {
                $Xml = [xml]$Event.ToXml()

                $EventData = @{}
                foreach ($DataNode in $Xml.Event.EventData.Data) {
                    $Name = $DataNode.Name
                    $Value = $DataNode.'#text'
                    if ($Name) {
                        $EventData[$Name] = $Value
                    }
                }

                [PSCustomObject]@{
                    FechaHora    = $Event.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Usuario      = $EventData['TargetUserName']
                    Dominio      = $EventData['TargetDomainName']
                    LogonType    = $EventData['LogonType']
                    Status       = $EventData['Status']
                    SubStatus    = $EventData['SubStatus']
                    Workstation  = $EventData['WorkstationName']
                    IPOrigen     = $EventData['IpAddress']
                    Proceso      = $EventData['ProcessName']
                }
            }
            catch {
                [PSCustomObject]@{
                    FechaHora    = $Event.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Usuario      = "N/A"
                    Dominio      = "N/A"
                    LogonType    = "N/A"
                    Status       = "N/A"
                    SubStatus    = "N/A"
                    Workstation  = "N/A"
                    IPOrigen     = "N/A"
                    Proceso      = "N/A"
                }
            }
        }
        )

        Write-Host ""
        Write-Title " FALLOS DE LOGON (4625) - $ComputerName"
        Write-Title " Ultimas $Hours horas"
        Write-Host "==========================================="

if (@($Results).Count -gt 0) {
    @($Results) | Format-Table -AutoSize
}
else {
    Write-Info "No se encontraron eventos 4625."
}
    }
    catch {
        Write-Log "Error consultando Security 4625 en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando eventos de Security (4625)."
        Write-ErrorText $_.Exception.Message
    }
}

function Search-EventsByText {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese texto a buscar en el mensaje del evento"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-WarningText "Busqueda vacia."
        return
    }

    try {
        Write-Info "Buscando eventos por texto [$SearchText] en [$ComputerName]"

        $StartTime = (Get-Date).AddHours(-24)

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'Application','System'
            StartTime = $StartTime
        } -ErrorAction Stop | Where-Object {
            $_.Message -like "*$SearchText*"
        }

        Write-Host ""
        Write-Title " BUSQUEDA DE EVENTOS - $ComputerName"
        Write-Highlight " Texto: $SearchText"
        Write-Highlight " Ultimas 24 horas"
        Write-Host "==========================================="

        Format-EventTable -Events $Events
    }
    catch {
        Write-Log "Error buscando eventos por texto en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error buscando eventos."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-EventsMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Title " MODULO EVENTOS"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Errores de Application ultimas 24 hs"
        Write-Host "2. Errores de System ultimas 24 hs"
        Write-Host "3. Fallos de logon Security (4625) ultimas 24 hs"
        Write-Host "4. Buscar eventos por texto"
        Write-Host "5. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Get-RecentApplicationErrors -ComputerName $ComputerName -Hours 24
                Pause-Console
            }
            "2" {
                Get-RecentSystemErrors -ComputerName $ComputerName -Hours 24
                Pause-Console
            }
            "3" {
                Get-RecentSecurityLogonFailures -ComputerName $ComputerName -Hours 24
                Pause-Console
            }
            "4" {
                Search-EventsByText -ComputerName $ComputerName
                Pause-Console
            }
            "5" {
                Write-Log "Salida del modulo Eventos para [$ComputerName]"
            }
            default {
                Write-ErrorText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "5")
}