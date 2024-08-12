function New-BmhEntraSamlApplication {
    <#
    .SYNOPSIS
        Creates a new Saml application in Entra.
    .DESCRIPTION
        This function will create a new SAML application in Entra. It will create the application object, service principal object, and a token signing certificate for the application.
    .EXAMPLE
        New-BmhEntraSamlApplication -DisplayName "Test" -ReplyUrl "http://localhost/saml" -Identifier "http://localhost"
    .PARAMETER DisplayName
        This will be the name that shows for the new application
    .PARAMETER ReplyUrl
        This is the SAML assertion consumer endpiont. I.E. where the SAML response should be sent back too.
    .PARAMETER Identifier
        This is the identifier or entity ID of the SAML application
    .NOTES
        This function requires the Microsoft.Graph.Applications module
    
#>
    [CmdletBinding()]
    param (
        [string]$DisplayName,
        [string]$ReplyUrl,
        [string]$Identifier
    )

    Begin {
        Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) Begin ] Starting: $($MyInvocation.Mycommand)"

        # Import required modules
        Import-Module Microsoft.Graph.Applications

        # Establish graph session
        Connect-MgGraph -Scopes "Application.ReadWrite.All"
    }

    Process {
        Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) Process ] Creating SAML application $DisplayName"

        # create hashtable for values to be used with write-progress
        $progParams = @{
            Activity = $MyInvocation.MyCommand
            Status   = "Creating new Saml application"
        }

        # Create variable to store a generic template ID to instantiate a non-gallery enterprise application in Entra.
        $applicationTemplateId = "8adf8e6e-67b2-4cf2-a259-e3dc5476c621"

        # Create DisplayName param. This will be the name of the service principal object in Entra.
        $params = @{DisplayName = $DisplayName }

        Write-Progress @progParams

        # Run a Try/Catch block to attempt to create the application and catch an errors.
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
        Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) Process ] Application $DisplayName successfully created. Updating application with redirect and Identifier"

        # Update progParams hashtable
        $progParams.Status = "Grabbing new applications SPN ID and AppID"

        Write-Progress @progParams

        # Check if the application was created successfully based on results of the Try/Catch Block. Only continue if there was a success.
        If ($Ok) {
            # Grab the service principal ID of the newly created enterprise app
            $spn = Get-MgServicePrincipal -Filter "DisplayName eq $DisplayName"
            $servicePrincipalId = $spn.Id

            # Grab the application/client ID of the newly created enterprise app
            $appReg = Get-MgApplication -Filter "DisplayName eq $DisplayName"
            $appId = $appReg.Id

            # Create Hashtable to hold the redirect and identifier URIs that will be applied
            $webParams = @{
                Web            = @{
                    RedirectUris = @("$ReplyUrl")
                }
                IdentifierUris = "$Identifier"
            }

            # update prog params hashtable
            $progParams.Status = "Updating new application with redirect and Identifier"

            Write-Progress @progParams

            # Update the application with the provided redirect and identifier URIs
            Update-MgApplication -ApplicationId $appId -BodyParameter $webParams

            # Create hashtable to hold the sso method that will be applied  
            $samlParams = @{PreferredSignleSignOnMode = "saml" }

            # Update the service principal with the preferred sso method  
            Update-MgServicePrincipal -ServicePrincipalId $servicePrincipalId -BodyParameter $samlParams

            # Generate a Entra token signing certificate for the new application.  
            Add-MgServicePrincipalTokenSigningCertificate -ServicePrincipalId $servicePrincipalId
            Start-Sleep -Seconds 10
        }
    }

    End {
        Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) End ] Ending: $($MyInvocation.MyCommand)"

        Disconnect-MgGraph
    }
    
}