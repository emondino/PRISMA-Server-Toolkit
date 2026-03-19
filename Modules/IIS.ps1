function Test-IISModuleAvailable {
    param(
        [string]$ComputerName
    )

    try {
        $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            if (Get-Module -ListAvailable -Name WebAdministration) {
                return $true
            }
            else {
                return $false
            }
        } -ErrorAction Stop

        return [bool]$Result
    }
    catch {
        Write-ErrorText "No se pudo verificar WebAdministration en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-AppPoolsData {
    param(
        [string]$ComputerName
    )

    try {
        $Data = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Import-Module WebAdministration -ErrorAction Stop

            $Pools = Get-ChildItem IIS:\AppPools

            foreach ($Pool in $Pools) {
                $PoolState = $Pool.state

                $ManagedRuntimeVersion = $Pool.managedRuntimeVersion
                if ([string]::IsNullOrWhiteSpace($ManagedRuntimeVersion)) {
                    $ManagedRuntimeVersion = "No Managed Code"
                }

                $IdentityType = $Pool.processModel.identityType
                $IdentityShown = $IdentityType

                if ($IdentityType -eq "SpecificUser") {
                    if (-not [string]::IsNullOrWhiteSpace($Pool.processModel.userName)) {
                        $IdentityShown = $Pool.processModel.userName
                    }
                    else {
                        $IdentityShown = "SpecificUser"
                    }
                }

                [PSCustomObject]@{
                    Estado   = $PoolState
                    AppPool  = $Pool.Name
                    Runtime  = $ManagedRuntimeVersion
                    Pipeline = $Pool.managedPipelineMode
                    Identity = $IdentityShown
                }
            }
        } -ErrorAction Stop

        return @($Data) | Select-Object Estado, AppPool, Runtime, Pipeline, Identity
    }
    catch {
        Write-Log "Error obteniendo App Pools en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error obteniendo App Pools."
        Write-ErrorText $_.Exception.Message
        return @()
    }
}

function Show-AllAppPools {
    param(
        [string]$ComputerName
    )

    Write-Info "Listando App Pools en [$ComputerName]"

    $Pools = Get-AppPoolsData -ComputerName $ComputerName

    Write-Host ""
    Write-Title " APP POOLS - $ComputerName"
    
    if (@($Pools).Count -gt 0) {
        @($Pools) |
            Sort-Object AppPool |
            Format-Table -AutoSize
    }
    else {
        Write-WarningText "No se encontraron App Pools o no fue posible consultarlos."
    }
}

function Find-AppPoolInteractive {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese nombre del App Pool o parte del nombre"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-WarningText "Busqueda vacia."
        return $null
    }

    $Pools = Get-AppPoolsData -ComputerName $ComputerName |
        Where-Object { $_.AppPool -like "*$SearchText*" } |
        Sort-Object AppPool

    if (@($Pools).Count -eq 0) {
        Write-WarningText "No se encontraron coincidencias."
        return $null
    }

    if (@($Pools).Count -eq 1) {
        return @($Pools)[0]
    }

    Write-Host ""
    Write-Title "Se encontraron varias coincidencias:"
    Write-Host ""

    $i = 1
    foreach ($Pool in $Pools) {
        Write-Host ("{0}. [{1}] {2}" -f $i, $Pool.Estado, $Pool.AppPool)
        $i++
    }

    Write-Host ""
    $Selection = Read-Host "Seleccione un numero"

    if ($Selection -match '^\d+$') {
        $Index = [int]$Selection
        if ($Index -ge 1 -and $Index -le @($Pools).Count) {
            return @($Pools)[$Index - 1]
        }
    }

    Write-WarningText "Seleccion invalida."
    return $null
}

function Show-AppPoolSummary {
    param(
        [object]$AppPool,
        [string]$ComputerName
    )

    Write-Host ""
    Write-Title " DETALLE APP POOL"
    Write-Host "Servidor : $ComputerName"
    Write-Host "App Pool : $($AppPool.AppPool)"
    Write-Host "Estado   : $($AppPool.Estado)"
    Write-Host "Runtime  : $($AppPool.Runtime)"
    Write-Host "Pipeline : $($AppPool.Pipeline)"
    Write-Host "Identity : $($AppPool.Identity)"
    Write-Host "==========================================="
}

function Start-AppPoolSafe {
    param(
        [string]$ComputerName
    )

    $SelectedPool = Find-AppPoolInteractive -ComputerName $ComputerName
    if (-not $SelectedPool) { return }

    Show-AppPoolSummary -AppPool $SelectedPool -ComputerName $ComputerName

    if ($SelectedPool.Estado -eq "Started") {
        Write-Host ""
        Write-Info "El App Pool ya se encuentra iniciado."
        return
    }

    if (-not (Confirm-Action -Message "Confirma iniciar el App Pool '$($SelectedPool.AppPool)'")) {
        Write-WarningText "Accion cancelada."
        return
    }

    try {
        Write-Success "Iniciando App Pool '$($SelectedPool.AppPool)' en [$ComputerName]"

        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($PoolName)
            Import-Module WebAdministration -ErrorAction Stop
            Start-WebAppPool -Name $PoolName -ErrorAction Stop
        } -ArgumentList $SelectedPool.AppPool -ErrorAction Stop

        Write-Success "App Pool iniciado correctamente."
        Write-Log "App Pool '$($SelectedPool.AppPool)' iniciado correctamente en [$ComputerName]"
    }
    catch {
        Write-Log "Error iniciando App Pool '$($SelectedPool.AppPool)' en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error iniciando App Pool."
        Write-ErrorText $_.Exception.Message
    }
}

function Stop-AppPoolSafe {
    param(
        [string]$ComputerName
    )

    $SelectedPool = Find-AppPoolInteractive -ComputerName $ComputerName
    if (-not $SelectedPool) { return }

    Show-AppPoolSummary -AppPool $SelectedPool -ComputerName $ComputerName

    if ($SelectedPool.Estado -eq "Stopped") {
        Write-Host ""
        Write-Info "El App Pool ya se encuentra detenido."
        return
    }

    if (-not (Confirm-Action -Message "Confirma detener el App Pool '$($SelectedPool.AppPool)'")) {
        Write-WarningText "Accion cancelada."
        return
    }

    try {
        Write-Log "Deteniendo App Pool '$($SelectedPool.AppPool)' en [$ComputerName]"

        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($PoolName)
            Import-Module WebAdministration -ErrorAction Stop
            Stop-WebAppPool -Name $PoolName -ErrorAction Stop
        } -ArgumentList $SelectedPool.AppPool -ErrorAction Stop

        Write-Success "App Pool detenido correctamente."
        Write-Log "App Pool '$($SelectedPool.AppPool)' detenido correctamente en [$ComputerName]"
    }
    catch {
        Write-Log "Error deteniendo App Pool '$($SelectedPool.AppPool)' en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error deteniendo App Pool."
        Write-ErrorText $_.Exception.Message
    }
}

function Restart-AppPoolSafe {
    param(
        [string]$ComputerName
    )

    $SelectedPool = Find-AppPoolInteractive -ComputerName $ComputerName
    if (-not $SelectedPool) { return }

    Show-AppPoolSummary -AppPool $SelectedPool -ComputerName $ComputerName

    if (-not (Confirm-Action -Message "Confirma reciclar el App Pool '$($SelectedPool.AppPool)'")) {
        Write-WarningText "Accion cancelada."
        return
    }

    try {
        Write-Info "Reciclando App Pool '$($SelectedPool.AppPool)' en [$ComputerName]"

        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($PoolName)
            Import-Module WebAdministration -ErrorAction Stop
            Restart-WebAppPool -Name $PoolName -ErrorAction Stop
        } -ArgumentList $SelectedPool.AppPool -ErrorAction Stop

        Write-Success "App Pool reciclado correctamente."
        Write-Log "App Pool '$($SelectedPool.AppPool)' reciclado correctamente en [$ComputerName]"
    }
    catch {
        Write-Log "Error reciclando App Pool '$($SelectedPool.AppPool)' en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error reciclando App Pool."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-AppPoolDetails {
    param(
        [string]$ComputerName
    )

    $SelectedPool = Find-AppPoolInteractive -ComputerName $ComputerName
    if (-not $SelectedPool) { return }

    Show-AppPoolSummary -AppPool $SelectedPool -ComputerName $ComputerName
    Write-Log "Consulta App Pool '$($SelectedPool.AppPool)' en [$ComputerName]"
}

function Get-IISSites {
    param(
        [string]$ComputerName
    )

    try {

        Write-Log "Listando sitios IIS en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {

            Import-Module WebAdministration

            Get-Website | ForEach-Object {

                $Bindings = $_.Bindings.Collection.bindingInformation -join ","

                [PSCustomObject]@{
                    Estado  = $_.State
                    Sitio   = $_.Name
                    Puerto  = ($Bindings -split ":")[1]
                    AppPool = $_.ApplicationPool
                    Ruta    = $_.PhysicalPath
                }

            }

        }

        $Results = $Results | Select-Object Estado,Sitio,Puerto,AppPool,Ruta

        Write-Host ""
        Write-Title " SITIOS IIS - $ComputerName"
        Write-Host ""

        $Results | Format-Table -AutoSize

    }
    catch {

        Write-Log "Error listando sitios IIS en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando sitios IIS."

    }
}

function Get-IISSiteDetail {
    param(
        [string]$ComputerName
    )

    $SiteName = Read-Host "Ingrese nombre del sitio"

    try {

        Write-Log "Consultando sitio IIS [$SiteName] en [$ComputerName]"

        $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {

            param($RemoteSite)

            Import-Module WebAdministration

            $Site = Get-Website -Name $RemoteSite

            if ($Site -eq $null) {
                throw "El sitio no existe"
            }

            [PSCustomObject]@{
                Nombre   = $Site.Name
                Estado   = $Site.State
                AppPool  = $Site.ApplicationPool
                Ruta     = $Site.PhysicalPath
                Bindings = ($Site.Bindings.Collection.bindingInformation -join ",")
            }

        } -ArgumentList $SiteName

        Write-Host ""
        Write-Title " DETALLE SITIO IIS"
        Write-Host ""

        $Result | Format-List

    }
    catch {

        Write-Log "Error consultando sitio [$SiteName] en [$ComputerName]" "ERROR"
        Write-ErrorText $_.Exception.Message

    }
}

function Start-IISSite {
    param(
        [string]$ComputerName
    )

    $SiteName = Read-Host "Ingrese nombre del sitio a iniciar"

    try {

        Write-Log "Iniciando sitio [$SiteName] en [$ComputerName]"

        Invoke-Command -ComputerName $ComputerName -ScriptBlock {

            param($RemoteSite)

            Import-Module WebAdministration
            Start-Website -Name $RemoteSite

        } -ArgumentList $SiteName

        Write-Success "Sitio iniciado correctamente."

    }
    catch {

        Write-Log "Error iniciando sitio [$SiteName] en [$ComputerName]" "ERROR"
        Write-ErrorText $_.Exception.Message

    }
}

function Stop-IISSite {
    param(
        [string]$ComputerName
    )

    $SiteName = Read-Host "Ingrese nombre del sitio a detener"

    try {

        Write-Log "Deteniendo sitio [$SiteName] en [$ComputerName]"

        Invoke-Command -ComputerName $ComputerName -ScriptBlock {

            param($RemoteSite)

            Import-Module WebAdministration
            Stop-Website -Name $RemoteSite

        } -ArgumentList $SiteName

        Write-Success "Sitio detenido correctamente."

    }
    catch {

        Write-Log "Error deteniendo sitio [$SiteName] en [$ComputerName]" "ERROR"
        Write-ErrorText $_.Exception.Message

    }
}

function Get-CertificateCNFromDN {
    param(
        [string]$DistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
        return ""
    }

    $Match = [regex]::Match($DistinguishedName, 'CN=([^,]+)')
    if ($Match.Success) {
        return $Match.Groups[1].Value
    }

    return $DistinguishedName
}

function Get-IISHttpsBindings {
    param(
        [string]$ComputerName
    )

    try {
        Write-Info "Consultando bindings HTTPS y certificados IIS en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Import-Module WebAdministration -ErrorAction Stop

            $Sites = Get-Website

            foreach ($Site in $Sites) {
                foreach ($Binding in $Site.Bindings.Collection) {
                    if ($Binding.protocol -eq 'https') {
                        $Thumbprint = $null
                        $CertSubject = $null
                        $CertNotAfter = $null
                        $DaysRemaining = $null

                        try {
                            $Thumbprint = $Binding.CertificateHash
                            if ($Thumbprint -is [byte[]]) {
                                $Thumbprint = ($Thumbprint | ForEach-Object { $_.ToString("X2") }) -join ""
                            }

                            if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
                                $Cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                                    $_.Thumbprint -eq $Thumbprint
                                } | Select-Object -First 1

                                if ($Cert) {
                                    $CertSubject = $Cert.Subject
                                    $CertNotAfter = $Cert.NotAfter
                                    $DaysRemaining = [int](New-TimeSpan -Start (Get-Date) -End $Cert.NotAfter).TotalDays
                                }
                            }
                        }
                        catch {
                        }

                        [PSCustomObject]@{
                            Sitio         = $Site.Name
                            Estado        = $Site.State
                            Protocolo     = $Binding.protocol
                            Binding       = $Binding.bindingInformation
                            Thumbprint    = $Thumbprint
                            CertSubject   = $CertSubject
                            NotAfter      = $CertNotAfter
                            DiasRestantes = $DaysRemaining
                        }
                    }
                }
            }
        } -ErrorAction Stop

        $Results = @($Results) | Select-Object Sitio, Estado, Protocolo, Binding, Thumbprint, CertSubject, NotAfter, DiasRestantes

        Write-Host ""
        Write-Title " IIS SSL INSPECTOR - $ComputerName"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            @($Results) |
                Select-Object `
                    Sitio,
                    Estado,
                    Binding,
                    @{Name='CN'; Expression = { Get-CertificateCNFromDN $_.CertSubject }},
                    @{Name='Vence'; Expression = {
                        if ($_.NotAfter) { $_.NotAfter.ToString("yyyy-MM-dd") } else { "N/A" }
                    }},
                    @{Name='Dias'; Expression = {
                        if ($_.DiasRestantes -ne $null) { $_.DiasRestantes } else { "N/A" }
                    }},
                    @{Name='Thumbprint'; Expression = {
                        if ($_.Thumbprint -and $_.Thumbprint.Length -gt 16) {
                            $_.Thumbprint.Substring(0,16) + "..."
                        }
                        else {
                            $_.Thumbprint
                        }
                    }} |
                Format-Table -AutoSize
        }
        else {
            Write-Info "No se encontraron bindings HTTPS en IIS."
        }
    }
    catch {
        Write-Log "Error consultando bindings HTTPS IIS en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando IIS SSL Inspector."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-IISHttpsBindingsExpiringSoon {
    param(
        [string]$ComputerName,
        [int]$Days = 30
    )

    try {
        Write-Info "Consultando certificados IIS HTTPS que vencen en $Days dias en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteDays)

            Import-Module WebAdministration -ErrorAction Stop

            $Sites = Get-Website

            foreach ($Site in $Sites) {
                foreach ($Binding in $Site.Bindings.Collection) {
                    if ($Binding.protocol -eq 'https') {
                        $Thumbprint = $null

                        try {
                            $Thumbprint = $Binding.CertificateHash
                            if ($Thumbprint -is [byte[]]) {
                                $Thumbprint = ($Thumbprint | ForEach-Object { $_.ToString("X2") }) -join ""
                            }

                            if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
                                $Cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                                    $_.Thumbprint -eq $Thumbprint -and $_.NotAfter -le (Get-Date).AddDays($RemoteDays)
                                } | Select-Object -First 1

                                if ($Cert) {
                                    [PSCustomObject]@{
                                        Sitio         = $Site.Name
                                        Estado        = $Site.State
                                        Binding       = $Binding.bindingInformation
                                        CertSubject   = $Cert.Subject
                                        NotAfter      = $Cert.NotAfter
                                        DiasRestantes = [int](New-TimeSpan -Start (Get-Date) -End $Cert.NotAfter).TotalDays
                                        Thumbprint    = $Cert.Thumbprint
                                    }
                                }
                            }
                        }
                        catch {
                        }
                    }
                }
            }
        } -ArgumentList $Days -ErrorAction Stop

        $Results = @($Results) | Select-Object Sitio, Estado, Binding, CertSubject, NotAfter, DiasRestantes, Thumbprint

        Write-Host ""
        Write-Title " IIS SSL - PROXIMOS A VENCER - $ComputerName"
        Write-Highlight " Dentro de $Days dias"
        Write-Host "==========================================="
        Write-Host ""

        if (@($Results).Count -gt 0) {
            @($Results) |
                Sort-Object DiasRestantes |
                Select-Object `
                    Sitio,
                    Estado,
                    Binding,
                    @{Name='CN'; Expression = { Get-CertificateCNFromDN $_.CertSubject }},
                    @{Name='Vence'; Expression = { $_.NotAfter.ToString("yyyy-MM-dd") }},
                    DiasRestantes,
                    @{Name='Thumbprint'; Expression = {
                        if ($_.Thumbprint.Length -gt 16) {
                            $_.Thumbprint.Substring(0,16) + "..."
                        }
                        else {
                            $_.Thumbprint
                        }
                    }} |
                Format-Table -AutoSize
        }
        else {
            Write-Info "No se encontraron certificados HTTPS de IIS proximos a vencer."
        }
    }
    catch {
        Write-Log "Error consultando certificados HTTPS proximos a vencer en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando expiracion de certificados HTTPS IIS."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-IISExpiredCertificatesInUse {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Consultando certificados vencidos usados por IIS en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Import-Module WebAdministration -ErrorAction Stop

            $Now = Get-Date
            $Sites = Get-Website

            foreach ($Site in $Sites) {
                foreach ($Binding in $Site.Bindings.Collection) {
                    if ($Binding.protocol -eq 'https') {
                        $Thumbprint = $null

                        try {
                            $Thumbprint = $Binding.CertificateHash

                            if ($Thumbprint -is [byte[]]) {
                                $Thumbprint = ($Thumbprint | ForEach-Object { $_.ToString("X2") }) -join ""
                            }

                            if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
                                $Cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                                    $_.Thumbprint -eq $Thumbprint
                                } | Select-Object -First 1

                                if ($Cert -and $Cert.NotAfter -lt $Now) {
                                    [PSCustomObject]@{
                                        Sitio         = $Site.Name
                                        Estado        = $Site.State
                                        Binding       = $Binding.bindingInformation
                                        Subject       = $Cert.Subject
                                        NotAfter      = $Cert.NotAfter
                                        DiasVencido   = [int](New-TimeSpan -Start $Cert.NotAfter -End $Now).TotalDays
                                        Thumbprint    = $Cert.Thumbprint
                                    }
                                }
                            }
                        }
                        catch {
                        }
                    }
                }
            }
        } -ErrorAction Stop

        $Results = @($Results)

        Write-Host ""
        Write-Title " CERTIFICADOS VENCIDOS USADOS POR IIS - $ComputerName"
        Write-Highlight " Bindings HTTPS con certificado vencido"
        Write-Host ""

        if ($Results.Count -gt 0) {
            $Results |
                Sort-Object DiasVencido -Descending |
                Select-Object `
                    Sitio,
                    Estado,
                    Binding,
                    @{Name='CN'; Expression = { Get-CertificateCN $_.Subject }},
                    @{Name='Vence'; Expression = { $_.NotAfter.ToString("yyyy-MM-dd") }},
                    DiasVencido,
                    @{Name='Thumbprint'; Expression = {
                        if ($_.Thumbprint.Length -gt 16) { $_.Thumbprint.Substring(0,16) + "..." } else { $_.Thumbprint }
                    }} |
                Format-Table -AutoSize
        }
        else {
            Write-Success "No se detectaron certificados vencidos en uso por IIS."
        }
    }
    catch {
        Write-Log "Error consultando certificados vencidos usados por IIS en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando certificados vencidos usados por IIS."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-IISMenu {
    param(
        [string]$ComputerName
    )

    if (-not (Test-IISModuleAvailable -ComputerName $ComputerName)) {
        Write-Host ""
        Write-ErrorText "No se detecto el modulo WebAdministration o no fue posible consultarlo en el servidor."
        Pause-Console
        return
    }

    do {
        Clear-Host
        Write-Title " MODULO IIS"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Listar App Pools"
        Write-Host "2. Consultar App Pool"
        Write-Host "3. Iniciar App Pool"
        Write-Host "4. Detener App Pool"
        Write-Host "5. Reciclar App Pool"
        Write-Host "6. Listar sitios"
        Write-Host "7. Consultar sitio"
        Write-Host "8. Iniciar sitio"
        Write-Host "9. Detener sitio"
        Write-Host "10. IIS SSL Inspector"
        Write-Host "11. IIS SSL proximos a vencer"
        Write-Host "12. Certificados Vencidos usados por IIS"
        Write-Host "13. Volver"


        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Show-AllAppPools -ComputerName $ComputerName
                Pause-Console
            }
            "2" {
                Show-AppPoolDetails -ComputerName $ComputerName
                Pause-Console
            }
            "3" {
                Start-AppPoolSafe -ComputerName $ComputerName
                Pause-Console
            }
            "4" {
                Stop-AppPoolSafe -ComputerName $ComputerName
                Pause-Console
            }
            "5" {
                Restart-AppPoolSafe -ComputerName $ComputerName
                Pause-Console
            }
            "6" {
    Get-IISSites -ComputerName $ComputerName
    Pause-Console
}

"7" {
    Get-IISSiteDetail -ComputerName $ComputerName
    Pause-Console
}

"8" {
    Start-IISSite -ComputerName $ComputerName
    Pause-Console
}

"9" {
    Stop-IISSite -ComputerName $ComputerName
    Pause-Console
}
            "10" {
                Get-IISHttpsBindings -ComputerName $ComputerName
                Pause-Console
            }
            "11" {
                Get-IISHttpsBindingsExpiringSoon -ComputerName $ComputerName -Days 30
                Pause-Console
            }
"12" {
    Get-IISExpiredCertificatesInUse -ComputerName $ComputerName
    Pause-Console
}
"13" {
    Write-Log "Salida del modulo IIS para [$ComputerName]"
}
            default {
                Write-ErrorText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "13")
}