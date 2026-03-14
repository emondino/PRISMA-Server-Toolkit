function Read-RemoteIISLogFile {
    param(
        [string]$ComputerName,
        [string]$LogPath
    )

    try {
        Write-Log "Leyendo log IIS [$LogPath] en [$ComputerName]"

        $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteLogPath)

            if (-not (Test-Path $RemoteLogPath)) {
                throw "El archivo no existe: $RemoteLogPath"
            }

            $Lines = Get-Content -Path $RemoteLogPath -ErrorAction Stop

            $FieldLine = $Lines | Where-Object { $_ -like "#Fields:*" } | Select-Object -First 1
            if (-not $FieldLine) {
                throw "No se encontro la linea #Fields en el log IIS."
            }

            $Fields = ($FieldLine -replace '^#Fields:\s*', '') -split '\s+'

            $DataLines = $Lines | Where-Object {
                $_ -and
                $_.Trim() -ne "" -and
                $_ -notmatch '^#'
            }

            foreach ($Line in $DataLines) {
                $Values = $Line -split '\s+'
                if ($Values.Count -lt $Fields.Count) {
                    continue
                }

                $Obj = [ordered]@{}
                for ($i = 0; $i -lt $Fields.Count; $i++) {
                    $Obj[$Fields[$i]] = $Values[$i]
                }

                [PSCustomObject]$Obj
            }
        } -ArgumentList $LogPath -ErrorAction Stop

        return @($Result)
    }
    catch {
        Write-Log "Error leyendo log IIS [$LogPath] en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error leyendo log IIS."
        Write-ErrorText $_.Exception.Message
        return @()
    }
}

function Get-IISSitesForLogs {
    param(
        [string]$ComputerName
    )

    try {
        $Sites = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Import-Module WebAdministration -ErrorAction Stop

            Get-Website | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    Id   = $_.Id
                    State = $_.State
                }
            }
        } -ErrorAction Stop

        return @($Sites) | Select-Object Name, Id, State
    }
    catch {
        Write-Log "Error obteniendo sitios IIS para logs en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorTextt "Error obteniendo sitios IIS."
        Write-ErrorText $_.Exception.Message
        return @()
    }
}

function Select-IISSiteForLogAnalysis {
    param(
        [string]$ComputerName
    )

    $Sites = Get-IISSitesForLogs -ComputerName $ComputerName

    if (-not $Sites -or @($Sites).Count -eq 0) {
        Write-Info "No se encontraron sitios IIS."
        return $null
    }

    Write-Host ""
    Write-Title "Sitios IIS disponibles:"
    Write-Host ""

    $i = 1
    foreach ($Site in $Sites) {
        Write-Host ("{0}. [{1}] {2} (ID: {3})" -f $i, $Site.State, $Site.Name, $Site.Id)
        $i++
    }

    Write-Host ""
    $Selection = Read-Host "Seleccione un numero"

    if ($Selection -match '^\d+$') {
        $Index = [int]$Selection
        if ($Index -ge 1 -and $Index -le @($Sites).Count) {
            return @($Sites)[$Index - 1]
        }
    }

    Write-WarningText "Seleccion invalida."
    return $null
}

function Get-LatestIISLogForSite {
    param(
        [string]$ComputerName,
        [int]$SiteId
    )

    try {
        $LatestLog = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteSiteId)

            $LogFolder = "C:\inetpub\logs\LogFiles\W3SVC$RemoteSiteId"

            if (-not (Test-Path $LogFolder)) {
                throw "No existe la carpeta de logs del sitio: $LogFolder"
            }

            Get-ChildItem -Path $LogFolder -Filter *.log -File -ErrorAction Stop |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 |
                ForEach-Object {
                    [PSCustomObject]@{
                        FullName      = $_.FullName
                        Name          = $_.Name
                        LastWriteTime = $_.LastWriteTime
                    }
                }
        } -ArgumentList $SiteId -ErrorAction Stop

        return $LatestLog
    }
    catch {
        Write-Log "Error obteniendo ultimo log IIS para sitio ID [$SiteId] en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error obteniendo el ultimo log del sitio."
        Write-ErrorText $_.Exception.Message
        return $null
    }
}

function Get-IISLogTopStatusCodes {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP CODIGOS HTTP"
    

    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $LogData |
        Group-Object 'sc-status' |
        Sort-Object Count -Descending |
        Select-Object @{
            Name = 'Status'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogTopUrls {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP URLS"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $LogData |
        Group-Object 'cs-uri-stem' |
        Sort-Object Count -Descending |
        Select-Object -First 20 @{
            Name = 'URL'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogTopClientIPs {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP IPS CLIENTE"
    

    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $LogData |
        Group-Object 'c-ip' |
        Sort-Object Count -Descending |
        Select-Object -First 20 @{
            Name = 'IP'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogRequestsPerHour {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " REQUESTS POR HORA"
    

    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $Hourly = foreach ($Row in $LogData) {
        try {
            $DatePart = $Row.date
            $TimePart = $Row.time

            if ($DatePart -and $TimePart) {
                $DateTime = [datetime]::ParseExact(
                    "$DatePart $TimePart",
                    "yyyy-MM-dd HH:mm:ss",
                    $null
                )

                [PSCustomObject]@{
                    Hora = $DateTime.ToString("yyyy-MM-dd HH:00")
                }
            }
        }
        catch {
        }
    }

    @($Hourly) |
        Group-Object Hora |
        Sort-Object Name |
        Select-Object @{
            Name = 'Hora'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogErrors5xx {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " ERRORES 5XX"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $Errors = $LogData | Where-Object {
        $_.'sc-status' -match '^5\d\d$'
    }

    if (@($Errors).Count -eq 0) {
        Write-Info "No se encontraron errores 5xx."
        return
    }

    $Errors |
        Select-Object -First 50 `
            date,
            time,
            @{Name='IP'; Expression = { $_.'c-ip' }},
            @{Name='Metodo'; Expression = { $_.'cs-method' }},
            @{Name='URL'; Expression = { $_.'cs-uri-stem' }},
            @{Name='Status'; Expression = { $_.'sc-status' }},
            @{Name='SubStatus'; Expression = { $_.'sc-substatus' }},
            @{Name='TimeTaken'; Expression = { $_.'time-taken' }} |
        Format-Table -AutoSize
}

function Get-IISLogErrors4xx {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " ERRORES 4XX"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $Errors = $LogData | Where-Object {
        $_.'sc-status' -match '^4\d\d$'
    }

    if (@($Errors).Count -eq 0) {
        Write-Info "No se encontraron errores 4xx."
        return
    }

    $Errors |
        Select-Object -First 50 `
            date,
            time,
            @{Name='IP'; Expression = { $_.'c-ip' }},
            @{Name='Metodo'; Expression = { $_.'cs-method' }},
            @{Name='URL'; Expression = { $_.'cs-uri-stem' }},
            @{Name='Status'; Expression = { $_.'sc-status' }},
            @{Name='SubStatus'; Expression = { $_.'sc-substatus' }},
            @{Name='TimeTaken'; Expression = { $_.'time-taken' }} |
        Format-Table -AutoSize
}

function Load-LatestIISLogBySite {
    param(
        [string]$ComputerName
    )

    $SelectedSite = Select-IISSiteForLogAnalysis -ComputerName $ComputerName
    if (-not $SelectedSite) { return }

    $LatestLog = Get-LatestIISLogForSite -ComputerName $ComputerName -SiteId $SelectedSite.Id
    if (-not $LatestLog) { return }

    Write-Host ""
    Write-Host "Sitio seleccionado : $($SelectedSite.Name)"
    Write-Host "Site ID            : $($SelectedSite.Id)"
    Write-Host "Ultimo log         : $($LatestLog.FullName)"
    Write-Host "Fecha archivo      : $($LatestLog.LastWriteTime)"
    Write-Host ""

    $Script:IISLogData = Read-RemoteIISLogFile -ComputerName $ComputerName -LogPath $LatestLog.FullName
    $Script:IISLogSource = $LatestLog.FullName

    if (@($Script:IISLogData).Count -gt 0) {
        Write-Info "Archivo cargado correctamente. Registros leidos: $(@($Script:IISLogData).Count)"
        Write-Info "Log IIS cargado para sitio [$($SelectedSite.Name)] desde [$($LatestLog.FullName)] en [$ComputerName]"
    }
    else {
        Write-WarningText "No se pudieron cargar datos del log."
    }
}

function Load-IISLogManual {
    param(
        [string]$ComputerName
    )

    $LogPath = Read-Host "Ingrese la ruta completa del log IIS en el servidor"

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        Write-WarningText "Ruta vacia."
        return
    }

    $Script:IISLogData = Read-RemoteIISLogFile -ComputerName $ComputerName -LogPath $LogPath
    $Script:IISLogSource = $LogPath

    if (@($Script:IISLogData).Count -gt 0) {
        Write-Host ""
        Write-Success "Archivo cargado correctamente. Registros leidos: $(@($Script:IISLogData).Count)"
        Write-Success "Log IIS cargado manualmente desde [$LogPath] en [$ComputerName]"
    }
    else {
        Write-Host ""
        Write-WarningText "No se pudieron cargar datos del log."
    }
}

function Get-IISLogTopUrls5xx {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP URLS CON ERRORES 5XX"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $Errors = $LogData | Where-Object {
        $_.'sc-status' -match '^5\d\d$'
    }

    if (@($Errors).Count -eq 0) {
        Write-Info "No se encontraron errores 5xx."
        return
    }

    $Errors |
        Group-Object 'cs-uri-stem' |
        Sort-Object Count -Descending |
        Select-Object -First 20 `
            @{Name='URL'; Expression = { $_.Name }},
            @{Name='Cantidad5xx'; Expression = { $_.Count }} |
        Format-Table -AutoSize
}

function Get-IISLogRequestsPerMinute {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " REQUESTS POR MINUTO"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-Info "No hay datos."
        return
    }

    $PerMinute = foreach ($Row in $LogData) {
        try {
            $DatePart = $Row.date
            $TimePart = $Row.time

            if ($DatePart -and $TimePart) {
                $DateTime = [datetime]::ParseExact(
                    "$DatePart $TimePart",
                    "yyyy-MM-dd HH:mm:ss",
                    $null
                )

                [PSCustomObject]@{
                    Minuto = $DateTime.ToString("yyyy-MM-dd HH:mm")
                }
            }
        }
        catch {
        }
    }

    if (-not $PerMinute -or @($PerMinute).Count -eq 0) {
        Write-WarningText "No se pudieron agrupar requests por minuto."
        return
    }

    @($PerMinute) |
        Group-Object Minuto |
        Sort-Object Name |
        Select-Object @{
            Name = 'Minuto'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogTopRequestMinutes {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP MINUTOS CON MAS REQUESTS"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-WarningText "No hay datos."
        return
    }

    $PerMinute = foreach ($Row in $LogData) {
        try {
            $DatePart = $Row.date
            $TimePart = $Row.time

            if ($DatePart -and $TimePart) {
                $DateTime = [datetime]::ParseExact(
                    "$DatePart $TimePart",
                    "yyyy-MM-dd HH:mm:ss",
                    $null
                )

                [PSCustomObject]@{
                    Minuto = $DateTime.ToString("yyyy-MM-dd HH:mm")
                }
            }
        }
        catch {
        }
    }

    if (-not $PerMinute -or @($PerMinute).Count -eq 0) {
        Write-WarningText "No se pudieron calcular los minutos con requests."
        return
    }

    @($PerMinute) |
        Group-Object Minuto |
        Sort-Object Count -Descending |
        Select-Object -First 20 @{
            Name = 'Minuto'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogTopIPs5xx {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP IPS CON ERRORES 5XX"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-WarningText "No hay datos."
        return
    }

    $Errors = $LogData | Where-Object {
        $_.'sc-status' -match '^5\d\d$'
    }

    if (@($Errors).Count -eq 0) {
        Write-WarningText "No se encontraron errores 5xx."
        return
    }

    $Errors |
        Group-Object 'c-ip' |
        Sort-Object Count -Descending |
        Select-Object -First 20 @{
            Name = 'IP'
            Expression = { $_.Name }
        }, @{
            Name = 'Cantidad5xx'
            Expression = { $_.Count }
        } |
        Format-Table -AutoSize
}

function Get-IISLogTopIPUrl5xx {
    param(
        [array]$LogData
    )

    Write-Host ""
    Write-Title " TOP IP + URL CON ERRORES 5XX"
    
    if (-not $LogData -or @($LogData).Count -eq 0) {
        Write-WarningText "No hay datos."
        return
    }

    $Errors = $LogData | Where-Object {
        $_.'sc-status' -match '^5\d\d$'
    }

    if (@($Errors).Count -eq 0) {
        Write-WarningText "No se encontraron errores 5xx."
        return
    }

    $Grouped = $Errors | Group-Object {
        "{0}|{1}" -f $_.'c-ip', $_.'cs-uri-stem'
    }

    $Results = foreach ($Group in $Grouped) {
        $Parts = $Group.Name -split '\|', 2

        [PSCustomObject]@{
            IP          = $Parts[0]
            URL         = $Parts[1]
            Cantidad5xx = $Group.Count
        }
    }

    @($Results) |
        Sort-Object Cantidad5xx -Descending |
        Select-Object -First 30 |
        Format-Table -AutoSize
}

function Show-IISLogsMenu {
    param(
        [string]$ComputerName
    )

    $Script:IISLogData = @()
    $Script:IISLogSource = $null

    do {
        Clear-Host
        Write-Title " MODULO IIS LOG ANALYZER"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        if ($Script:IISLogSource) {
            Write-Highlight " Log cargado: $Script:IISLogSource"
            Write-Host "-------------------------------------------"
        }
        Write-Host "1. Cargar ultimo log por sitio IIS"
        Write-Host "2. Cargar log manualmente"
        Write-Host "3. Top codigos HTTP"
        Write-Host "4. Top URLs"
        Write-Host "5. Top IPs cliente"
        Write-Host "6. Requests por hora"
        Write-Host "7. Errores 5xx"
        Write-Host "8. Errores 4xx"
        Write-Host "9. Top URLs 5xx"
        Write-Host "10. Requests por minuto"
        Write-Host "11. Top minutos con mas requests"
        Write-Host "12. Top IPs con errores 5xx"
        Write-Host "13. Top IP + URL con errores 5xx"
        Write-Host "14. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Load-LatestIISLogBySite -ComputerName $ComputerName
                Pause-Console
            }
            "2" {
                Load-IISLogManual -ComputerName $ComputerName
                Pause-Console
            }
            "3" {
                Get-IISLogTopStatusCodes -LogData $Script:IISLogData
                Pause-Console
            }
            "4" {
                Get-IISLogTopUrls -LogData $Script:IISLogData
                Pause-Console
            }
            "5" {
                Get-IISLogTopClientIPs -LogData $Script:IISLogData
                Pause-Console
            }
            "6" {
                Get-IISLogRequestsPerHour -LogData $Script:IISLogData
                Pause-Console
            }
            "7" {
                Get-IISLogErrors5xx -LogData $Script:IISLogData
                Pause-Console
            }
            "8" {
                Get-IISLogErrors4xx -LogData $Script:IISLogData
                Pause-Console
            }
            "9" {
    Get-IISLogTopUrls5xx -LogData $Script:IISLogData
    Pause-Console
}
"10" {
    Get-IISLogRequestsPerMinute -LogData $Script:IISLogData
    Pause-Console
}
"11" {
    Get-IISLogTopRequestMinutes -LogData $Script:IISLogData
    Pause-Console
}
"12" {
    Get-IISLogTopIPs5xx -LogData $Script:IISLogData
    Pause-Console
}
"13" {
    Get-IISLogTopIPUrl5xx -LogData $Script:IISLogData
    Pause-Console
}
"14" {
    Write-Success "Salida del modulo IIS Log Analyzer para [$ComputerName]"
}
            default {
                Write-WarningText "Opcion invalida."
                Pause-Console
            }
        }
    } while ($Option -ne "14")
}