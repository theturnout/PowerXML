. "$PSScriptRoot\powerxml.ps1"
. "$PSScriptRoot\utilities.ps1"
Import-Module "$PSScriptRoot/polyglot"
Export-ModuleMember -Function Parse-MimeMultipart
Export-ModuleMember -Function ConvertTo-NativeType
Export-ModuleMember -Function Transform-Xml
Export-ModuleMember -Function Get-PXClassPath 
