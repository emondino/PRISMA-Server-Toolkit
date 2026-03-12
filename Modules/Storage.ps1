function Get-RemoteFolderSizes {
    param(
        [string]$ComputerName,
        [string]$Path
    )

    try {
        Write-Log "Analizando carpetas en ruta [$Path] sobre [$ComputerName]"

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
        Write-Host "Top carpetas por tamaño"
        Write-Host ""

        if (@($Results).Count -gt 0) {
@($Results) |
    Select-Object Carpeta, TamanoGB |
    Sort-Object TamanoGB -Descending |
    Select-Object -First 10 |
    Format-Table -AutoSize
        }
        else {
            Write-Host "No se encontraron subcarpetas para analizar."
        }
    }
    catch {
        Write-Log "Error analizando carpetas en [$Path] sobre [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error analizando carpetas."
        Write-Host $_.Exception.Message
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
        Write-Host "Top archivos por tamaño"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            @($Results) |
    Select-Object Archivo, TamañoMB, Carpeta |
    Format-Table -AutoSize
        }
        else {
            Write-Host "No se encontraron archivos."
        }
    }
    catch {
        Write-Log "Error buscando archivos grandes en [$Path] sobre [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error buscando archivos."
        Write-Host $_.Exception.Message
    }
}

function Analyze-RemoteFolderInteractive {
    param(
        [string]$ComputerName
    )

    $Path = Read-Host "Ingrese la ruta a analizar en el servidor"

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "Ruta vacia."
        return
    }

    Write-Host ""
    Write-Host "==========================================="
    Write-Host " ANALISIS DE ALMACENAMIENTO"
    Write-Host " Servidor: $ComputerName"
    Write-Host " Ruta    : $Path"
    Write-Host "==========================================="

    Get-RemoteFolderSizes -ComputerName $ComputerName -Path $Path
    Get-RemoteLargestFiles -ComputerName $ComputerName -Path $Path
}

function Show-StorageMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Host "==========================================="
        Write-Host " MODULO STORAGE"
        Write-Host " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Analizar ruta"
        Write-Host "2. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Analyze-RemoteFolderInteractive -ComputerName $ComputerName
                Pause-Console
            }
            "2" {
                Write-Log "Salida del modulo Storage para [$ComputerName]"
            }
            default {
                Write-Host "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "2")
}