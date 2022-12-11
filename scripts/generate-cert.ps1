#
# NOTE: elevated admin rights needed !!!
#
# source
# https://github.com/Azure/azure-quickstart-templates/tree/master/quickstarts/microsoft.network/application-gateway-2vms-iis-ssl
param ($frontendDnsName='frontend.frontend',$certOutputRelativePath='cert')

# generate password script
# ------------------------
# Source: https://rakesh-suryawanshi.medium.com/generate-random-password-in-azure-bicep-template-3411aba22fff
# Code Source: https://gist.githubusercontent.com/krishrocks1904/c142e3e281348925304fea3cc53da6ec/raw/9ff24cd9bdb439849d1b07e97c961bd6459967c7/generate-pwd.ps1
function Get-RandomCharacters($length, $characters) {
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
    $private:ofs=""
    return [String]$characters[$random]
}
function Scramble-String([string]$inputString){     
    $characterArray = $inputString.ToCharArray()   
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
    $outputString = -join $scrambledStringArray
    return $outputString 
}

$password = Get-RandomCharacters -length 8 -characters 'abcdefghiklmnoprstuvwxyz'
$password += Get-RandomCharacters -length 3 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
$password += Get-RandomCharacters -length 3 -characters '1234567890'
$password += Get-RandomCharacters -length 3 -characters '@#*+'
#not allowed character " ' ` / \ < % ~ | $ & !

$password = Scramble-String $password
### --------------------

$localPath = Get-Location
# the target directory
$certDir = Join-Path -Path $localPath -ChildPath $certOutputRelativePath

New-Item -ItemType Directory -Force -Path $certDir

$password > "$certDir/cert_password.txt"
$pw = $password

# create forntend.pfx
# -------------------
# Front End Certificate: This is the certificate that will terminate SSL on the Application Gateway for traffic coming
# from the internet. This will need to be in .pfx format, and will need to be encoded in base-64 in order to include in
# the template deployment.
Get-ChildItem -Path $(New-SelfSignedCertificate -dnsname $frontendDnsName).pspath `
| Export-PfxCertificate -FilePath "$certDir/frontend.pfx" -Password $(ConvertTo-SecureString -String $pw -Force -AsPlainText)

# base64 encoding
[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$certDir/frontend.pfx")) > "$certDir/frontend.txt"

# create backend.pfx
# ------------------
# Back End Certificate: This is the certificate that will be installed on the IIS servers to encrypt traffic between
# the Application Gateway and the IIS servers. This could be the same as the front end certificate or could be a
# different certificate. This will need to be in .pfx format, and will need to be encoded in base-64 in order to include
# in the template deployment.
$cert = Get-ChildItem -Path $(New-SelfSignedCertificate -dnsname backend.backend).pspath
Export-PfxCertificate -Cert $cert -FilePath "$certDir/backend.pfx" -Password $(ConvertTo-SecureString -String $pw -Force -AsPlainText)

# base64 encoding
[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$certDir/backend.pfx")) > "$certDir/backend.txt"

# create backend-public.cer
# -------------------------
# Back End Public Key: This is the public key from the back end certificate that will be used by the Application
# Gateway to whitelist the back end servers. This will need to be in .cer format, and will need to be encoded in
# base-64 in order to include in the template deployment.
Export-Certificate -Cert $cert -FilePath "$certDir/backend-public.cer"

# base64 encoding
[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$certDir/backend-public.cer")) > "$certDir/backend-public.txt"
#>