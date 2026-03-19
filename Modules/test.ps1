function Test-IISExpiredCertificatesInUseData {
    param(
        [string]$ComputerName
    )

    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Import-Module WebAdministration -ErrorAction Stop

            Write-Host "Modulo WebAdministration: OK"
            $Sites = Get-Website
            Write-Host "Cantidad de sitios: $($Sites.Count)"

            foreach ($Site in $Sites) {
                Write-Host "Sitio: $($Site.Name)"

                foreach ($Binding in $Site.Bindings.Collection) {
                    if ($Binding.protocol -eq 'https') {
                        Write-Host "  Binding HTTPS: $($Binding.bindingInformation)"
                        Write-Host "  CertificateHash tipo: $($Binding.CertificateHash.GetType().FullName)"
                    }
                }
            }
        } -ErrorAction Stop
    }
    catch {
        Write-ErrorText "Fallo debug IIS certs"
        Write-ErrorText $_.Exception.Message
    }
}