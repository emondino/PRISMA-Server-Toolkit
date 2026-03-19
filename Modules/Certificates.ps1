function Get-CertificateCN {
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

function Get-CertificateDaysRemaining {
    param(
        [datetime]$NotAfter
    )

    return [int](New-TimeSpan -Start (Get-Date) -End $NotAfter).TotalDays
}

function Format-CertificateTable {
    param(
        [array]$Certificates
    )

    if (-not $Certificates -or @($Certificates).Count -eq 0) {
        Write-Info "No se encontraron certificados."
        return
    }

    @($Certificates) |
        Select-Object `
            @{Name='CN'; Expression = { Get-CertificateCN $_.Subject }},
            @{Name='IssuerCN'; Expression = { Get-CertificateCN $_.Issuer }},
            @{Name='Desde'; Expression = { $_.NotBefore.ToString("yyyy-MM-dd") }},
            @{Name='Hasta'; Expression = { $_.NotAfter.ToString("yyyy-MM-dd") }},
            @{Name='Dias'; Expression = { Get-CertificateDaysRemaining -NotAfter $_.NotAfter }},
            @{Name='PrivKey'; Expression = { $_.HasPrivateKey }},
            @{Name='Thumbprint'; Expression = {
                if ($_.Thumbprint.Length -gt 16) { $_.Thumbprint.Substring(0,16) + "..." } else { $_.Thumbprint }
            }} |
        Format-Table -AutoSize
}

function Get-RemoteCertificatesData {
    param(
        [string]$ComputerName
    )

    $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\My | ForEach-Object {
            [PSCustomObject]@{
                Subject       = $_.Subject
                Issuer        = $_.Issuer
                NotBefore     = $_.NotBefore
                NotAfter      = $_.NotAfter
                Thumbprint    = $_.Thumbprint
                HasPrivateKey = $_.HasPrivateKey
                FriendlyName  = $_.FriendlyName
                SerialNumber  = $_.SerialNumber
            }
        }
    } -ErrorAction Stop

    return @($Results) | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint, HasPrivateKey, FriendlyName, SerialNumber
}

function Get-RemoteCertificates {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Listando certificados en [$ComputerName]"

        $Results = Get-RemoteCertificatesData -ComputerName $ComputerName

        Write-Host ""
        Write-Title " CERTIFICADOS - $ComputerName"
        Write-Highlight " Store: LocalMachine\My"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            $Results = @($Results) | Sort-Object NotAfter
            Format-CertificateTable -Certificates $Results
        }
        else {
            Write-Info "No se encontraron certificados."
        }
    }
    catch {
        Write-Log "Error listando certificados en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error listando certificados."
        Write-ErrorText $_.Exception.Message
    }
}

function Find-RemoteCertificate {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese texto a buscar (Subject, Issuer, CN o Thumbprint)"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-Info "Busqueda vacia."
        return
    }

    try {
        Write-Log "Buscando certificados con texto [$SearchText] en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteSearchText)

            Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                $_.Subject -like "*$RemoteSearchText*" -or
                $_.Issuer -like "*$RemoteSearchText*" -or
                $_.Thumbprint -like "*$RemoteSearchText*" -or
                $_.FriendlyName -like "*$RemoteSearchText*"
            } | ForEach-Object {
                [PSCustomObject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    NotBefore     = $_.NotBefore
                    NotAfter      = $_.NotAfter
                    Thumbprint    = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                    FriendlyName  = $_.FriendlyName
                    SerialNumber  = $_.SerialNumber
                }
            }
        } -ArgumentList $SearchText -ErrorAction Stop

        $Results = @($Results) | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint, HasPrivateKey, FriendlyName, SerialNumber

        Write-Host ""
        Write-Title " BUSQUEDA DE CERTIFICADOS - $ComputerName"
        Write-Highlight " Texto: $SearchText"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            $Results = @($Results) | Sort-Object NotAfter
            Format-CertificateTable -Certificates $Results
        }
        else {
            Write-Info "No se encontraron certificados que coincidan con la busqueda."
        }
    }
    catch {
        Write-Log "Error buscando certificados en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error buscando certificados."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-RemoteCertificatesExpiringSoon {
    param(
        [string]$ComputerName,
        [int]$Days = 30
    )

    try {
        Write-Log "Consultando certificados que vencen en $Days dias en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteDays)

            $LimitDate = (Get-Date).AddDays($RemoteDays)

            Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                $_.NotAfter -le $LimitDate
            } | ForEach-Object {
                [PSCustomObject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    NotBefore     = $_.NotBefore
                    NotAfter      = $_.NotAfter
                    DiasRestantes = [int](New-TimeSpan -Start (Get-Date) -End $_.NotAfter).TotalDays
                    Thumbprint    = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                    FriendlyName  = $_.FriendlyName
                    SerialNumber  = $_.SerialNumber
                }
            }
        } -ArgumentList $Days -ErrorAction Stop

        $Results = @($Results) | Select-Object Subject, Issuer, NotBefore, NotAfter, DiasRestantes, Thumbprint, HasPrivateKey, FriendlyName, SerialNumber

        Write-Host ""
        Write-Title " CERTIFICADOS PROXIMOS A VENCER - $ComputerName"
        Write-Highlight " Dentro de $Days dias"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            @($Results) |
                Sort-Object DiasRestantes |
                Select-Object `
                    @{Name='CN'; Expression = { Get-CertificateCN $_.Subject }},
                    @{Name='IssuerCN'; Expression = { Get-CertificateCN $_.Issuer }},
                    @{Name='Vence'; Expression = { $_.NotAfter.ToString("yyyy-MM-dd") }},
                    DiasRestantes,
                    @{Name='PrivKey'; Expression = { $_.HasPrivateKey }},
                    @{Name='Thumbprint'; Expression = {
                        if ($_.Thumbprint.Length -gt 16) { $_.Thumbprint.Substring(0,16) + "..." } else { $_.Thumbprint }
                    }} |
                Format-Table -AutoSize
        }
        else {
            Write-Info "No se encontraron certificados proximos a vencer."
        }
    }
    catch {
        Write-Log "Error consultando certificados proximos a vencer en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando certificados proximos a vencer."
        Write-ErrorText $_.Exception.Message
    }
}

function Show-CertificateDetails {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese CN, texto del Subject o Thumbprint"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-Info "Busqueda vacia."
        return
    }

    try {
        Write-Log "Consultando detalle de certificado con texto [$SearchText] en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteSearchText)

            Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                $_.Subject -like "*$RemoteSearchText*" -or
                $_.Thumbprint -like "*$RemoteSearchText*" -or
                $_.FriendlyName -like "*$RemoteSearchText*"
            } | ForEach-Object {
                [PSCustomObject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    NotBefore     = $_.NotBefore
                    NotAfter      = $_.NotAfter
                    Thumbprint    = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                    FriendlyName  = $_.FriendlyName
                    SerialNumber  = $_.SerialNumber
                    DiasRestantes = [int](New-TimeSpan -Start (Get-Date) -End $_.NotAfter).TotalDays
                }
            }
        } -ArgumentList $SearchText -ErrorAction Stop

        $Results = @($Results)

        Write-Host ""
        Write-Title " DETALLE DE CERTIFICADO - $ComputerName"
        Write-Highlight " Texto: $SearchText"
        Write-Host ""

        if ($Results.Count -eq 0) {
            Write-Info "No se encontraron certificados que coincidan con la busqueda."
            return
        }

        foreach ($Cert in $Results) {
            Write-Host "CN             : $(Get-CertificateCN $Cert.Subject)"
            Write-Host "Subject        : $($Cert.Subject)"
            Write-Host "Issuer         : $($Cert.Issuer)"
            Write-Host "FriendlyName   : $($Cert.FriendlyName)"
            Write-Host "SerialNumber   : $($Cert.SerialNumber)"
            Write-Host "NotBefore      : $($Cert.NotBefore)"
            Write-Host "NotAfter       : $($Cert.NotAfter)"
            Write-Host "DiasRestantes  : $($Cert.DiasRestantes)"
            Write-Host "HasPrivateKey  : $($Cert.HasPrivateKey)"
            Write-Host "Thumbprint     : $($Cert.Thumbprint)"
            Write-Host "-------------------------------------------"
        }
    }
    catch {
        Write-Log "Error consultando detalle de certificado en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error consultando detalle de certificado."
        Write-ErrorText $_.Exception.Message
    }
}

function Get-ReplacedExpiredCertificates {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Buscando certificados vencidos con reemplazo en [$ComputerName]"

        $Certs = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-ChildItem Cert:\LocalMachine\My | ForEach-Object {
                [PSCustomObject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    NotBefore     = $_.NotBefore
                    NotAfter      = $_.NotAfter
                    Thumbprint    = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                    FriendlyName  = $_.FriendlyName
                    SerialNumber  = $_.SerialNumber
                }
            }
        } -ErrorAction Stop

        $Certs = @($Certs)
        $Now = Get-Date

        $NormalizedCerts = foreach ($Cert in $Certs) {
            $CN = (Get-CertificateCN $Cert.Subject).Trim().ToLower()

            [PSCustomObject]@{
                CN             = $CN
                Subject        = $Cert.Subject
                Issuer         = $Cert.Issuer
                NotBefore      = [datetime]$Cert.NotBefore
                NotAfter       = [datetime]$Cert.NotAfter
                Thumbprint     = $Cert.Thumbprint
                HasPrivateKey  = $Cert.HasPrivateKey
                FriendlyName   = $Cert.FriendlyName
                SerialNumber   = $Cert.SerialNumber
            }
        }

        $Grouped = $NormalizedCerts | Group-Object CN

        $Results = foreach ($Group in $Grouped) {
            $Expired = @($Group.Group | Where-Object { $_.NotAfter -lt $Now })
            $Valid   = @($Group.Group | Where-Object { $_.NotAfter -ge $Now })

            if ($Expired.Count -gt 0 -and $Valid.Count -gt 0) {
                foreach ($Cert in $Expired) {
                    [PSCustomObject]@{
                        CN               = $Group.Name
                        IssuerCN         = Get-CertificateCN $Cert.Issuer
                        Vencido          = $Cert.NotAfter.ToString("yyyy-MM-dd")
                        DiasVencido      = [int](New-TimeSpan -Start $Cert.NotAfter -End $Now).TotalDays
                        Thumbprint       = if ($Cert.Thumbprint.Length -gt 16) { $Cert.Thumbprint.Substring(0,16) + "..." } else { $Cert.Thumbprint }
                        ReemplazoVigente = "Si"
                    }
                }
            }
        }

        Write-Host ""
        Write-Title " CERTIFICADOS VENCIDOS CON REEMPLAZO - $ComputerName"
        Write-Highlight " Store: LocalMachine\My"
        Write-Host ""

        if (@($Results).Count -gt 0) {
            @($Results) |
                Sort-Object DiasVencido -Descending |
                Format-Table -AutoSize
        }
        else {
            Write-Success "No se detectaron certificados vencidos con reemplazo."
        }
    }
    catch {
        Write-Log "Error buscando certificados vencidos con reemplazo en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-ErrorText "Error buscando certificados vencidos con reemplazo."
        Write-ErrorText $_.Exception.Message
    }
}


function Show-CertificatesMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Title " MODULO CERTIFICADOS"
        Write-Highlight " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Listar certificados"
        Write-Host "2. Buscar certificado"
        Write-Host "3. Ver certificados proximos a vencer"
        Write-Host "4. Ver detalle de certificado"
        Write-Host "5. Certificados vencidos con reemplazo"
        Write-Host "6. Volver"
        Write-Host "==========================================="
        $Option = Read-Host "Seleccione una opcion"

        switch ($Option) {
            "1" {
                Get-RemoteCertificates -ComputerName $ComputerName
                Pause-Console
            }
            "2" {
                Find-RemoteCertificate -ComputerName $ComputerName
                Pause-Console
            }
            "3" {
                Get-RemoteCertificatesExpiringSoon -ComputerName $ComputerName -Days 30
                Pause-Console
            }
            "4" {
                Show-CertificateDetails -ComputerName $ComputerName
                Pause-Console
            }
"5" {
    Get-ReplacedExpiredCertificates -ComputerName $ComputerName
    Pause-Console
}
"6" {
    Write-Log "Salida del modulo Certificados para [$ComputerName]"
}
            default {
                Write-ErrorText "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "6")
}