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

function Get-ExpectedReboots {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Consultando reinicios esperados en [$ComputerName]"

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName='System'
            Id=1074,13,6009
            StartTime=(Get-Date).AddDays(-2)
        } -ErrorAction Stop

        Write-Host ""
        Write-Title " REINICIOS ESPERADOS - $ComputerName"
        Write-Highlight " Ultimas 48 horas"
        Write-Host ""

        if(@($Events).Count -gt 0){
            $Events |
            Select-Object TimeCreated, Id, ProviderName,
            @{Name='Mensaje';Expression={$_.Message.Substring(0,[math]::Min(120,$_.Message.Length))}} |
            Format-Table -AutoSize
        }
        else{
            Write-Success "No se detectaron reinicios esperados recientes."
        }

    }
    catch {
        Write-Log "Error consultando reinicios esperados en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando reinicios esperados."
    }
}

function Get-UnexpectedReboots {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Consultando reinicios inesperados en [$ComputerName]"

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName='System'
            Id=41,6008
            StartTime=(Get-Date).AddDays(-2)
        } -ErrorAction Stop

        Write-Host ""
        Write-Title " REINICIOS INESPERADOS - $ComputerName"
        Write-Highlight " Ultimas 48 horas"
        Write-Host ""

        if(@($Events).Count -gt 0){
            $Events |
            Select-Object TimeCreated, Id, ProviderName,
            @{Name='Mensaje';Expression={$_.Message.Substring(0,[math]::Min(120,$_.Message.Length))}} |
            Format-Table -AutoSize
        }
        else{
            Write-Success "No se detectaron reinicios inesperados."
        }

    }
    catch {
        Write-Log "Error consultando reinicios inesperados en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando reinicios inesperados."
    }
}

function Format-ShortEventMessage {
    param(
        [string]$Message,
        [int]$MaxLength = 140
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return ""
    }

    $Clean = ($Message -replace "`r|`n", " ").Trim()

    if ($Clean.Length -le $MaxLength) {
        return $Clean
    }

    return $Clean.Substring(0, $MaxLength) + "..."
}

function Get-IISAppPoolCrashEvents {
    param(
        [string]$ComputerName,
        [int]$Hours = 48
    )

    try {
        Write-Log "Consultando eventos criticos IIS/AppPool en [$ComputerName] ultimas $Hours hs"

        $StartTime = (Get-Date).AddHours(-$Hours)

        $CriticalIds = @(5002,5009,5011,5057,5059,5074,2282)

        $Events = Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{
            LogName   = 'System'
            StartTime = $StartTime
            Id        = $CriticalIds
        } -ErrorAction Stop


        Write-Title " EVENTOS CRITICOS IIS / APP POOLS - $ComputerName"
        Write-Highlight " Ultimas $Hours horas"


if (@($Events).Count -gt 0) {

$DisplayRows = @($Events) |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 30 `
        @{Name='FechaHora'; Expression = { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss") }},
        @{Name='EventID'; Expression = { $_.Id }},
        @{Name='AppPool'; Expression = { Get-AppPoolFromMessage $_.Message }},
        @{Name='Provider'; Expression = { $_.ProviderName }},
        @{Name='Resumen'; Expression = { Get-IISAppPoolEventMeaning $_.Id }},
        @{Name='Mensaje'; Expression = {
            $Msg = ($_.Message -replace "`r|`n", " ").Trim()
            if ($Msg.Length -gt 110) { $Msg.Substring(0,110) + "..." } else { $Msg }
        }}

$DisplayRows | Format-Table -AutoSize | Out-Host

Write-Title "Resumen de actividad por AppPool"

$Summary = @(
    $Events |
        ForEach-Object {
            Get-AppPoolFromMessage $_.Message
        } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "N/A" } |
        Group-Object |
        Sort-Object Count -Descending
)

if (@($Summary).Count -gt 0) {
    foreach ($Item in $Summary) {
        Write-Host ("- {0,-30} {1} evento(s)" -f $Item.Name, $Item.Count)
    }
}
else {
    Write-WarningText "No se pudo generar el resumen por AppPool."
}


    Write-Title "Diccionario rapido de eventos IIS / App Pools"

    $UniqueIds = @($Events | Select-Object -ExpandProperty Id -Unique | Sort-Object)

    foreach ($Id in $UniqueIds) {
        Write-Host ("- {0}: {1}" -f $Id, (Get-IISAppPoolEventMeaning -EventId $Id))
    }

}
        else {
            Write-Success "No se detectaron eventos criticos recientes de IIS/App Pools."
        }
    }
    catch {
        Write-Log "Error consultando eventos criticos IIS/AppPool en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando eventos criticos IIS/App Pools."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-IISAppPoolEventMeaning {
    param(
        [int]$EventId
    )

    switch ($EventId) {
        5002 { return "El App Pool fue deshabilitado o no pudo iniciarse correctamente." }
        5009 { return "El proceso del App Pool excedio el limite de fallas (rapid-fail protection)." }
        5011 { return "Un worker process del App Pool sufrio una falla de comunicacion fatal con WAS." }
        5057 { return "El App Pool fue deshabilitado por una configuracion o error relacionado a identidad/configuracion." }
        5059 { return "El App Pool fue deshabilitado o detenido por una condicion de error." }
        5074 { return "El worker process del App Pool fue detenido o reciclado." }
        5186 { return "Evento informativo del worker process/App Pool; puede indicar inicio, recycle o actividad del proceso." }
        2282 { return "Evento de IIS/W3SVC relacionado a worker process o inicializacion del proceso." }
        default { return "Sin descripcion resumida cargada en PRISMA." }
    }
}

function Get-AppPoolFromMessage {
    param(
        [string]$Message
    )

    if ($Message -match "application pool '([^']+)'") {
        return $Matches[1]
    }

    return "N/A"
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
        Write-Host "5. Reinicios esperados"
        Write-Host "6. Reinicios inesperados"
        Write-Host "7. Eventos IIS / App Pools"
        Write-Host "8. Volver"
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
    Get-ExpectedReboots -ComputerName $ComputerName
    Pause-Console
}

"6" {
    Get-UnexpectedReboots -ComputerName $ComputerName
    Pause-Console
}
"7" {
    Get-IISAppPoolCrashEvents -ComputerName $ComputerName -Hours 48
    Pause-Console
}
            "8" {
                Write-Log "Salida del modulo Eventos para [$ComputerName]"
            }
            default {
                Write-ErrorText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "8")
}