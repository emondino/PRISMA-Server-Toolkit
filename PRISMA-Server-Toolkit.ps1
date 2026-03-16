param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [switch]$Help
)

# =========================================
# CONFIGURACION GENERAL
# =========================================
$Script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ModulesPath = Join-Path $Script:BasePath "Modules"
$Script:LogsPath = Join-Path $Script:BasePath "Logs"

if (!(Test-Path $Script:LogsPath)) {
    New-Item -Path $Script:LogsPath -ItemType Directory -Force | Out-Null
}

$Script:LogFile = Join-Path $Script:LogsPath ("PRISMA_Server_Toolkit_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# Crear archivo de log con codificacion fija
"" | Out-File -FilePath $Script:LogFile -Encoding UTF8

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $Message

    switch ($Level.ToUpper()) {
        "ERROR" { Write-Host $Line -ForegroundColor Red }
        "WARN"  { Write-Host $Line -ForegroundColor Yellow }
        "INFO"  { Write-Host $Line -ForegroundColor Gray }
        default { Write-Host $Line -ForegroundColor Gray }
    }

    $Line | Out-File -FilePath $Script:LogFile -Append -Encoding UTF8
}

function Show-Help {
    Write-Host ""
    Write-Host "PRISMA-Server-Toolkit.ps1"
    Write-Host "Suite PowerShell para administracion y diagnostico de servidores Windows."
    Write-Host ""
    Write-Host "Uso:"
    Write-Host "  .\PRISMA-Server-Toolkit.ps1"
    Write-Host "  .\PRISMA-Server-Toolkit.ps1 -ComputerName SERVIDOR01"
    Write-Host "  .\PRISMA-Server-Toolkit.ps1 -Help"
    Write-Host ""
}

function Pause-Console {
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

# =========================================
# CARGA DE MODULOS
# =========================================
$ModuleFiles = @(
    "Colors.ps1"
    "ServerInfo.ps1",
    "Services.ps1",
    "Disks.ps1",
    "ServiceHealth.ps1",
    "Processes.ps1",
    "Network.ps1",
    "Events.ps1"
    "IIS.ps1"
    "Storage.ps1"
    "Certificates.ps1"
    "IISLogs.ps1"
    "HealthCheck.ps1"

)

foreach ($ModuleFile in $ModuleFiles) {
    $FullPath = Join-Path $Script:ModulesPath $ModuleFile
    if (Test-Path $FullPath) {
        . $FullPath
        Write-Log "Modulo cargado: $ModuleFile"
    }
    else {
        Write-Log "No se encontro el modulo: $ModuleFile" "WARN"
    }
}

function Show-MainMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Clear-Host
        Write-Title "======== PRISMA SERVER TOOLKIT ========"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host " 1. Informacion del servidor"
        Write-Host " 2. Servicios"
        Write-Host " 3. Discos"
        Write-Host " 4. Health Check de servicios"
        Write-Host " 5. Procesos"
        Write-Host " 6. Red"
        Write-Host " 7. Eventos"
        Write-Host " 8. IIS"
        Write-Host " 9. Storage"
        Write-Host "11. IIS Log Analyzer"
        Write-Host "12. Health Check"
        Write-Host "13. Salir"
        Write-Host "==========================================="
        Write-Title "==  Desarrollado por Ernesto Mondino   =="
        Write-Host ""
        $Option = Read-Host "Seleccione una opcion"


switch ($Option) {
    "1" {
        if (Get-Command Get-ServerInfoReport -ErrorAction SilentlyContinue) {
            Get-ServerInfoReport -ComputerName $ComputerName
        }
        else {
            Write-Log "La funcion Get-ServerInfoReport no esta disponible" "ERROR"
        }
        Pause-Console
    }
    "2" {
        if (Get-Command Show-ServicesMenu -ErrorAction SilentlyContinue) {
            Show-ServicesMenu -ComputerName $ComputerName
        }
        else {
            Write-Log "La funcion Show-ServicesMenu no esta disponible" "ERROR"
            Pause-Console
        }
    }
    "3" {
        if (Get-Command Get-DiskReport -ErrorAction SilentlyContinue) {
            Get-DiskReport -ComputerName $ComputerName
        }
        else {
            Write-Log "La funcion Get-DiskReport no esta disponible" "ERROR"
        }
        Pause-Console
    }
    "4" {
        if (Get-Command Get-ServiceHealthCheck -ErrorAction SilentlyContinue) {
            Get-ServiceHealthCheck -ComputerName $ComputerName
        }
        else {
            Write-Log "La funcion Get-ServiceHealthCheck no esta disponible" "ERROR"
        }
        Pause-Console
    }
    "5" {
    if (Get-Command Show-ProcessesMenu -ErrorAction SilentlyContinue) {
        Show-ProcessesMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-ProcessesMenu no esta disponible" "ERROR"
    }
    Pause-Console
}
    "6" {
    if (Get-Command Show-NetworkMenu -ErrorAction SilentlyContinue) {
        Show-NetworkMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-NetworkMenu no esta disponible" "ERROR"
    }
    Pause-Console
}
"7" {
    if (Get-Command Show-EventsMenu -ErrorAction SilentlyContinue) {
        Show-EventsMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-EventsMenu no esta disponible" "ERROR"
    }
    Pause-Console
}
"8" {
    if (Get-Command Show-IISMenu -ErrorAction SilentlyContinue) {
        Show-IISMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-IISMenu no esta disponible" "ERROR"
    }
    Pause-Console
}
"9" {
    if (Get-Command Show-StorageMenu -ErrorAction SilentlyContinue) {
        Show-StorageMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-StorageMenu no esta disponible" "ERROR"
        Pause-Console
    }
}

"10" {
    if (Get-Command Show-CertificatesMenu -ErrorAction SilentlyContinue) {
        Show-CertificatesMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-CertificatesMenu no esta disponible" "ERROR"
        Pause-Console
    }
}
"11" {
    if (Get-Command Show-IISLogsMenu -ErrorAction SilentlyContinue) {
        Show-IISLogsMenu -ComputerName $ComputerName
    }
    else {
        Write-Log "La funcion Show-IISLogsMenu no esta disponible" "ERROR"
        Pause-Console
    }
}
"12" {
    Invoke-PRISMAHealthCheck -ComputerName $ComputerName
    Pause-Console
}
"13" {
    Write-Log "Salida de la herramienta"
}
    default {
        Write-ErrorText "Opcion invalida"
        Pause-Console
    }
}
    } while ($Option -ne "13")
}

if ($Help) {
    Show-Help
    return
}

Write-Log "Inicio de PRISMA Server Toolkit para [$ComputerName]"
Show-MainMenu -ComputerName $ComputerName