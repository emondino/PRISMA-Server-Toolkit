param(
    [Parameter(Mandatory = $true)]
    [string]$ComputerName
)

Write-Host ""
Write-Host "==========================================="
Write-Host " TEST IIS CERTS DEBUG"
Write-Host "==========================================="
Write-Host "Servidor objetivo: $ComputerName"
Write-Host "==========================================="
Write-Host ""

try {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Write-Host "Inicio de prueba remota"
        Write-Host ""

        try {
            Import-Module WebAdministration -ErrorAction Stop
            Write-Host "[OK] Modulo WebAdministration cargado"
        }
        catch {
            Write-Host "[ERROR] No se pudo cargar WebAdministration"
            Write-Host $_.Exception.Message
            return
        }

        try {
            $Sites = Get-Website -ErrorAction Stop
            Write-Host "[OK] Get-Website funciona. Cantidad de sitios: $($Sites.Count)"
        }
        catch {
            Write-Host "[ERROR] Fallo Get-Website"
            Write-Host $_.Exception.Message
            return
        }

        Write-Host ""
        Write-Host "Sitios y bindings HTTPS detectados:"
        Write-Host ""

        foreach ($Site in $Sites) {
            Write-Host "Sitio: $($Site.Name)"

            foreach ($Binding in $Site.Bindings.Collection) {
                if ($Binding.protocol -eq 'https') {
                    Write-Host "  Binding HTTPS: $($Binding.bindingInformation)"

                    try {
                        if ($null -eq $Binding.CertificateHash) {
                            Write-Host "  [WARN] CertificateHash viene nulo"
                        }
                        else {
                            Write-Host "  CertificateHash type: $($Binding.CertificateHash.GetType().FullName)"

                            $Thumbprint = $Binding.CertificateHash

                            if ($Thumbprint -is [byte[]]) {
                                $Thumbprint = ($Thumbprint | ForEach-Object { $_.ToString('X2') }) -join ""
                            }

                            Write-Host "  Thumbprint convertido: $Thumbprint"

                            $Cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
                                $_.Thumbprint -eq $Thumbprint
                            } | Select-Object -First 1

                            if ($Cert) {
                                Write-Host "  [OK] Certificado encontrado en LocalMachine\My"
                                Write-Host "  Subject : $($Cert.Subject)"
                                Write-Host "  NotAfter: $($Cert.NotAfter)"
                            }
                            else {
                                Write-Host "  [WARN] No se encontro certificado en LocalMachine\My para ese thumbprint"
                            }
                        }
                    }
                    catch {
                        Write-Host "  [ERROR] Fallo procesando binding HTTPS"
                        Write-Host "  $($_.Exception.Message)"
                    }

                    Write-Host ""
                }
            }
        }

        Write-Host "Fin de prueba remota"
    } -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Fallo Invoke-Command"
    Write-Host $_.Exception.Message
}

Write-Host ""
Read-Host "Presione ENTER para salir"