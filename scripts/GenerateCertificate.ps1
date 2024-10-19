# Set the domain name
$DomainName = "contoso.com"
$certName = "appgw"

# Avoid using Cert:\LocalMachine due to access denied issues, use Cert:\CurrentUser instead
# Generate a self-signed certificate
$cert = New-SelfSignedCertificate -DnsName $DomainName -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(1)

# Ensure the target directory exists
$targetDir = ".\"
If (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Force -Path $targetDir
}

# Path where the PFX file will be exported
$filePath = "$targetDir\$certName.pfx"

# Create password for the PFX file
$password = New-Object System.Security.SecureString

# Export the certificate to a PFX file with the password
Export-PfxCertificate -Cert $cert -FilePath $filePath -Password $password

# Read the contents of the PFX file and encode it in base64
$CertContent = Get-Content -Path $filePath -AsByteStream
$CertBase64 = [Convert]::ToBase64String($CertContent)

# Output the encoded certificate to the console
Write-Host "APP_GATEWAY_LISTENER_CERTIFICATE_APPSERV_BASELINE: $CertBase64"
