function New-BmhEntraSamlApplication {
    [CmdletBinding()]
    param (
        [string]$DisplayName,
        [string]$ReplyUrl,
        [string]$Identifier
    )

    Begin {
        Import-Module Microsoft.Graph.Applications
        Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All"

        $applicationTemplateId = "8adf8e6e-67b2-4cf2-a259-e3dc5476c621"
        # Template ID for non-gallery enterprise application in Entra ID
    }

    Process {
        $params = @{DisplayName = $DisplayName }
        Try {
            Invoke-MgInstantiateApplicationTemplate -ApplicationTemplateId $applicationTemplateId -BodyParameter $params -ErrorAction Stop
            $Ok = $true
        }
        Catch {
            $Ok = $false
            $Msg = "Failed to create application using template $applicationTemplateId. $($_.Exception.Message)"
            Write-Warning $Msg
        }

        Start-Sleep -Seconds 60

        If ($Ok) {
            $spn = Get-MgServicePrincipal -Filter "DisplayName eq $DisplayName"
            $servicePrincipalId = $spn.Id
    
            $appReg = Get-MgApplication -Filter "DisplayName eq $DisplayName"
            $appId = $appReg.Id
    
            $webParams = @{
                Web            = @{
                    RedirectUris = @("$ReplyUrl")
                }
                IdentifierUris = "$Identifier"
            }
    
            Update-MgApplication -ApplicationId $appId -BodyParameter $webParams
    
            $samlParams = @{PreferredSignleSignOnMode = "saml" }
    
            Update-MgServicePrincipal -ServicePrincipalId $servicePrincipalId -BodyParameter $samlParams
    
            Add-MgServicePrincipalTokenSigningCertificate -ServicePrincipalId $servicePrincipalId
            Start-Sleep -Seconds 10
        }
    }

    End {
        Disconnect-MgGraph
    }
    
}