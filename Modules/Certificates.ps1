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

function Format-CertificateTable {
    param(
        [array]$Certificates
    )

    if (-not $Certificates -or @($Certificates).Count -eq 0) {
        Write-Host "No se encontraron certificados."
        return
    }

    @($Certificates) |
        Select-Object `
            @{Name='CN'; Expression = { Get-CertificateCN $_.Subject }}, `
            @{Name='IssuerCN'; Expression = { Get-CertificateCN $_.Issuer }}, `
            @{Name='Desde'; Expression = { $_.NotBefore.ToString("yyyy-MM-dd") }}, `
            @{Name='Hasta'; Expression = { $_.NotAfter.ToString("yyyy-MM-dd") }}, `
            @{Name='PrivKey'; Expression = { $_.HasPrivateKey }}, `
            @{Name='Thumbprint'; Expression = {
                if ($_.Thumbprint.Length -gt 16) { $_.Thumbprint.Substring(0,16) + "..." } else { $_.Thumbprint }
            }} |
        Format-Table -AutoSize
}



function Get-RemoteCertificates {
    param(
        [string]$ComputerName
    )

    try {
        Write-Log "Listando certificados en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-ChildItem Cert:\LocalMachine\My | ForEach-Object {
                [PSCustomObject]@{
                    Subject     = $_.Subject
                    Issuer      = $_.Issuer
                    NotBefore   = $_.NotBefore
                    NotAfter    = $_.NotAfter
                    Thumbprint  = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                }
            }
        } -ErrorAction Stop

        $Results = @($Results) | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint, HasPrivateKey

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " CERTIFICADOS - $ComputerName"
        Write-Host " Store: LocalMachine\My"
        Write-Host "==========================================="
        Write-Host ""

if (@($Results).Count -gt 0) {
    $Results = @($Results) | Sort-Object NotAfter
    Format-CertificateTable -Certificates $Results
}
else {
    Write-Host "No se encontraron certificados."
}
    }
    catch {
        Write-Log "Error listando certificados en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error listando certificados."
        Write-Host $_.Exception.Message
    }
}

function Find-RemoteCertificate {
    param(
        [string]$ComputerName
    )

    $SearchText = Read-Host "Ingrese texto a buscar (Subject, Issuer o Thumbprint)"

    if ([string]::IsNullOrWhiteSpace($SearchText)) {
        Write-Host "Busqueda vacia."
        return
    }

    try {
        Write-Log "Buscando certificados con texto [$SearchText] en [$ComputerName]"

        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($RemoteSearchText)

            Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                $_.Subject -like "*$RemoteSearchText*" -or
                $_.Issuer -like "*$RemoteSearchText*" -or
                $_.Thumbprint -like "*$RemoteSearchText*"
            } | ForEach-Object {
                [PSCustomObject]@{
                    Subject       = $_.Subject
                    Issuer        = $_.Issuer
                    NotBefore     = $_.NotBefore
                    NotAfter      = $_.NotAfter
                    Thumbprint    = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                }
            }
        } -ArgumentList $SearchText -ErrorAction Stop

        $Results = @($Results) | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint, HasPrivateKey

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " BUSQUEDA DE CERTIFICADOS - $ComputerName"
        Write-Host " Texto: $SearchText"
        Write-Host "==========================================="
        Write-Host ""

if (@($Results).Count -gt 0) {
    $Results = @($Results) | Sort-Object NotAfter
    Format-CertificateTable -Certificates $Results
}
else {
    Write-Host "No se encontraron certificados que coincidan con la busqueda."
}
    }
    catch {
        Write-Log "Error buscando certificados en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error buscando certificados."
        Write-Host $_.Exception.Message
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
                    NotAfter      = $_.NotAfter
                    DiasRestantes = [int](New-TimeSpan -Start (Get-Date) -End $_.NotAfter).TotalDays
                    Thumbprint    = $_.Thumbprint
                }
            }
        } -ArgumentList $Days -ErrorAction Stop

        $Results = @($Results) | Select-Object Subject, Issuer, NotAfter, DiasRestantes, Thumbprint

        Write-Host ""
        Write-Host "==========================================="
        Write-Host " CERTIFICADOS PROXIMOS A VENCER - $ComputerName"
        Write-Host " Dentro de $Days dias"
        Write-Host "==========================================="
        Write-Host ""

if (@($Results).Count -gt 0) {
    @($Results) |
        Sort-Object DiasRestantes |
        Select-Object `
            @{Name='CN'; Expression = { Get-CertificateCN $_.Subject }}, `
            @{Name='IssuerCN'; Expression = { Get-CertificateCN $_.Issuer }}, `
            @{Name='Vence'; Expression = { $_.NotAfter.ToString("yyyy-MM-dd") }}, `
            DiasRestantes, `
            @{Name='Thumbprint'; Expression = {
                if ($_.Thumbprint.Length -gt 16) { $_.Thumbprint.Substring(0,16) + "..." } else { $_.Thumbprint }
            }} |
        Format-Table -AutoSize
}
else {
    Write-Host "No se encontraron certificados proximos a vencer."
}
    }
    catch {
        Write-Log "Error consultando certificados proximos a vencer en [$ComputerName]. $($_.Exception.Message)" "ERROR"
        Write-Host "Error consultando certificados proximos a vencer."
        Write-Host $_.Exception.Message
    }
}

function Show-CertificatesMenu {
    param(
        [string]$ComputerName
    )

    do {
        Clear-Host
        Write-Host "==========================================="
        Write-Host " MODULO CERTIFICADOS"
        Write-Host " Servidor objetivo: $ComputerName"
        Write-Host "==========================================="
        Write-Host "1. Listar certificados"
        Write-Host "2. Buscar certificado"
        Write-Host "3. Ver certificados proximos a vencer"
        Write-Host "4. Volver"
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
                Write-Log "Salida del modulo Certificados para [$ComputerName]"
            }
            default {
                Write-Host "Opcion invalida"
                Pause-Console
            }
        }
    } while ($Option -ne "4")
}