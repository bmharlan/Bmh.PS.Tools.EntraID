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
        This is the SAML assertion consumer endpoint. I.E. where the SAML response should be sent back too.
    .PARAMETER Identifier
        This is the identifier or entity ID of the SAML application
    .NOTES
        This function requires the Microsoft.Graph.Applications module
    
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,
        [Parameter(Mandatory = $false)]
        [string]$ReplyUrl,
        [Parameter(Mandatory = $false)]
        [string]$Identifier,
        [switch]$addTokenCert
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
            Activity        = $MyInvocation.MyCommand
            Status          = "Creating new Saml application"
            PercentComplete = 0
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

        Start-Sleep -Seconds 5
        Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) Process ] Application $DisplayName successfully created. Updating application with redirect and Identifier"

        # Update progParams hashtable
        $progParams.Status = "Grabbing new application's SPN ID and AppID"
        $progParams.PercentComplete = 25

        Write-Progress @progParams

        # Check if the application was created successfully based on results of the Try/Catch Block. Only continue if there was a success.
        If ($Ok) {
            # Grab the service principal ID of the newly created enterprise app
            $spn = Get-MgServicePrincipal -Filter "DisplayName eq '$DisplayName'"
            $servicePrincipalId = $spn.Id

            # Grab the application/client ID of the newly created enterprise app
            $appReg = Get-MgApplication -Filter "DisplayName eq '$DisplayName'"
            $appId = $appReg.Id

            #update prog params
            $progParams.Status = "Setting SAML as preferred SSO method"
            $progParams.PercentComplete = 50
            Write-Progress @progParams
            Start-Sleep 1

            #Validate that SPN and App IDs are not empty before moving forward. Run a While loop to try and get the IDs
            #Initialize a counter for the while loop
            $attempts = 0
            while ($attempts -lt 4) {
                if (-not [string]::IsNullOrEmpty($appId) -and -not [string]::IsNullOrEmpty($servicePrincipalId)) {
                    # Exit the loop if both variables have a value
                    Break
                }
                Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) Process ] AppID and SpnID Variables are empty. Attemtping to refetch the IDs."
                Start-Sleep 5

                $appReg = Get-MgApplication -Filter "DisplayName eq '$DisplayName'"
                $appId = $appReg.Id

                $spn = Get-MgServicePrincipal -Filter "DisplayName eq '$DisplayName'"
                $servicePrincipalId = $spn.Id

                #increment the counter
                $attempts++
                
            }



            # Create hashtable to hold the sso method that will be applied  
            $samlParams = @{PreferredSingleSignOnMode = "saml" }

            Try {
                # Update the service principal with the preferred sso method  
                Update-MgServicePrincipal -ServicePrincipalId $servicePrincipalId -BodyParameter $samlParams -ErrorAction Stop
            }
            Catch {
                $Msg = "Failure to set the preferred sso method to saml for application $DisplayName. $($_.Exception.Message)"
                Write-Warning $Msg
            }


            # update prog params hashtable
            $progParams.Status = "Updating new application with redirect and Identifier"
            $progParams.PercentComplete = 75
            Write-Progress @progParams
            Start-Sleep 1

            if (-not $ReplyUrl) {
                $ReplyUrl = "https://localhost.corp/{0}" -f $appId
            }

            if (-not $Identifier) {
                $Identifier = "https://localhost.corp/{0}" -f $appId
            }

            # Create Hashtable to hold the redirect and identifier URIs that will be applied
            $webParams = @{
                Web            = @{
                    RedirectUris = @("$ReplyUrl")
                }
                IdentifierUris = "$Identifier"
            }

            # Run Try/Catch block for error handling during update
            Try {
                # Update the application with the provided redirect and identifier URIs
                Update-MgApplication -ApplicationId $appId -BodyParameter $webParams -ErrorAction Stop
            }
            Catch {
                $Msg = "Failure to apply ReplyUrl $ReplyUrl and Identifier $Identifier to application $DisplayName. $($_.Exception.Message)"
                Write-Warning $Msg
            }

            # Check if addTokenCert param was applied and run code based on check
            if ($addTokenCert) {
                $progParams.Status = "Adding token signing certificate"
                $progParams.PercentComplete = 90
                Write-Progress @progParams

                Try {
                    # Generate a Entra token signing certificate for the new application.  
                    Add-MgServicePrincipalTokenSigningCertificate -ServicePrincipalId $servicePrincipalId -ErrorAction Stop
                }
                Catch {
                    $Msg = "Failure to add token signing certificate to application $DisplayName. $($_.Exception.Message)"
                    Write-Warning $Msg
                }
                Start-Sleep 1
            }

            # Update prog params 
            $progParams.Status = "Wrapping things up..."
            $progParams.PercentComplete = 95
            Write-Progress @progParams
            Start-Sleep 1



        }
    }

    End {
        Write-Verbose "[$((Get-Date).TimeOfDay.ToString()) End ] Ending: $($MyInvocation.MyCommand)"

        Disconnect-MgGraph
    }
    
}