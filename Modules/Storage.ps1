function Get-RemoteFolderSizes {
    param(
        [string]$ComputerName,
        [string]$Path
    )

    try {
        Write-Info "Analizando carpetas en ruta [$Path] sobre [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemotePath)

            if (-not (Test-Path $RemotePath)) {
                throw "La ruta no existe: $RemotePath"
            }

            $Folders = Get-ChildItem -Path $RemotePath -Directory -ErrorAction Stop

            foreach ($Folder in $Folders) {
                $Size = (Get-ChildItem -Path $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum).Sum

                [PSCustomObject]@{
                    Carpeta  = $Folder.FullName
                    TamanoGB = [math]::Round(($Size / 1GB), 2)
                }
            }
        } -ArgumentList $Path -ErrorAction Stop

        Write-Host ""
        Write-Title "Top carpetas por tamaño"
        Write-Host ""

        if (@($Results).Count -gt 0) {
@($Results) |
    Select-Object Carpeta, TamanoGB |
    Sort-Object TamanoGB -Descending |
    Select-Object -First 10 |
    Format-Table -AutoSize
        }
        else {
            Write-WarningText "No se encontraron subcarpetas para analizar."
        }
    }
    catch {
        Write-Log "Error analizando carpetas en [$Path] sobre [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error analizando carpetas."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-RemoteLargestFiles {
    param(
        [string]$ComputerName,
        [string]$Path
    )

    try {
        Write-Log "Buscando archivos grandes en ruta [$Path] sobre [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemotePath)

            if (-not (Test-Path $RemotePath)) {
                throw "La ruta no existe: $RemotePath"
            }

            Get-ChildItem -Path $RemotePath -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending |
                Select-Object -First 20 `
                    @{Name='Archivo'; Expression = { $_.Name }},
                    @{Name='TamañoMB'; Expression = { [math]::Round(($_.Length / 1MB), 2) }},
                    @{Name='Carpeta'; Expression = { $_.DirectoryName }}
        } -ArgumentList $Path -ErrorAction Stop

        Write-Host ""
        Write-Title "Top archivos por tamaño"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            @($Results) |
    Select-Object Archivo, TamañoMB, Carpeta |
    Format-Table -AutoSize
        }
        else {
            Write-WarningText "No se encontraron archivos."
        }
    }
    catch {
        Write-Log "Error buscando archivos grandes en [$Path] sobre [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error buscando archivos."
        Write-ErrorText $_.Exception.Message
    }
}

function Analyze-RemoteFolderInteractive {
    param(
        [string]$ComputerName
    )

    $Path = Read-Host "Ingrese la ruta a analizar en el servidor"

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-WarningText "Ruta vacia."
        return
    }

    Write-Host ""
    Write-Title " ANALISIS DE ALMACENAMIENTO"
    Write-Highlight " Servidor: $ComputerName"
    Write-Highlight " Ruta    : $Path"
    Write-Host "==========================================="

    Get-RemoteFolderSizes -ComputerName $ComputerName -Path $Path
    Get-RemoteLargestFiles -ComputerName $ComputerName -Path $Path
}

function Get-RemoteDisks {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Consultando discos en [$ComputerName]"

        $Disks = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                [PSCustomObject]@{
                    Drive = $_.DeviceID
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                    UsedGB = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
                    PercentUsed = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
                }
            }
        }

        Write-Host ""
        Write-Title " DISCOS - $ComputerName"
        Write-Host ""

        $Disks | Sort-Object PercentUsed -Descending |
            Format-Table -AutoSize

        return $Disks
    }
    catch {
        Write-ErrorText "Error consultando discos."
        Write-ErrorText $_.Exception.Message
    }
}

function Analyze-RemoteDiskRoot {
    param(
        [string]$ComputerName
    )

    try {
        $Disks = Get-RemoteDisks -ComputerName $ComputerName

        if (-not $Disks) {
            return
        }

        Write-Host ""
        $Drive = Read-Host "Ingrese el disco a analizar (ej: C: o D:)"

        if ([string]::IsNullOrWhiteSpace($Drive)) {
            Write-Info "Operacion cancelada."
            return
        }

        Write-Log "Analizando raiz de [$Drive] en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteDrive)

            Get-ChildItem "$RemoteDrive\" -ErrorAction SilentlyContinue | ForEach-Object {

                if ($_.PSIsContainer) {
    $Size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
}
                else {
                    $Size = $_.Length
                }

                [PSCustomObject]@{
                    Nombre = $_.Name
                    Tipo   = if ($_.PSIsContainer) { "Carpeta" } else { "Archivo" }
                    SizeGB = [math]::Round($Size / 1GB, 2)
                }
            }

        } -ArgumentList $Drive

        Write-Host ""
        Write-Title " ANALISIS DE RAIZ - $ComputerName ($Drive)"
        Write-Highlight " Top carpetas/archivos mas grandes"
        Write-Host ""

if (@($Results).Count -gt 0) {
    @($Results) |
        Select-Object Nombre, Tipo, SizeGB |
        Sort-Object SizeGB -Descending |
        Select-Object -First 15 |
        Format-Table -AutoSize
}
        else {
            Write-Info "No se pudo obtener informacion del disco."
        }
    }
    catch {
        Write-Log "Error analizando disco en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error analizando disco."
        Write-ErrorText $_.Exception.Message
    }
}



function Show-StorageMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Title " MODULO STORAGE"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Analizar ruta"
        Write-Host "2. Analizar raiz de disco"
        Write-Host "3. Analizar ruta manual"
        Write-Host "4. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Analyze-RemoteFolderInteractive -ComputerName $ComputerName
                Pause-Console
            }
            "2" {
    Get-RemoteDisks -ComputerName $ComputerName
    Pause-Console
}
"3" {
    Analyze-RemoteDiskRoot -ComputerName $ComputerName
    Pause-Console
}
            "4" {
                Write-Log "Salida del modulo Storage para [$ComputerName]"
            }

            default {
                Write-WarningText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "4")
}