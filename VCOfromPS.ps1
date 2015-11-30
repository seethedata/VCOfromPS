$ErrorActionPreference = "Stop" 
<#
.SYNOPSIS
Runs a specified vCO Workflow
	 
.DESCRIPTION
Runs a specified vCO Workflow

#>
	 
##################################################################################################
# Edit the variables below to match the configuration of the VMware Orchestrator server	 
#

$Username="username"
$Password="password"
$Server="x.x.x.x"
$PortNumber=8281
$WorkflowName="Display all locks"	 
##################################################################################################

$EscapedWorkflowName=[System.uri]::EscapeDataString($WorkflowName)
		 
# Craft our URL and encoded details note we escape the colons with a backtick.
$vCoURL = "https`://$Server`:$PortNumber/vco/api/workflows/?conditions=name=$EscapedWorkflowName"
$UserPassCombined = "$Username`:$Password"
$EncodedUsernamePassword = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($UserPassCombined))
$Header = "Authorization: Basic $EncodedUsernamePassword"
		 
# Ignore SSL warning
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}


# Create our web client object, and add header for basic authentication with our encoded details
$wc = New-Object System.Net.WebClient;
$wc.Headers.Add($Header)
		 
# Download the JSON response from the Restful API, and convert it to an object from JSON.
Try {
    $jsonResult = $wc.downloadString($vCoURL)
}
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Host "Error looking for Workflow ID for $WorkflowName : $ErrorMessage"
   Exit 1
}

Try {
    $jsonObject = $jsonResult | ConvertFrom-Json
}
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Host "Error parsing result of looking for Workflow ID for $WorkflowName : $ErrorMessage"
    Exit 1
}	 

$WorkflowURL= $jsonObject.link.href


$ExecuteURL=$WorkflowURL + "executions"

$auth = "Basic $($EncodedUsernamePassword)"
$headers = @{"Authorization"=$auth;"Content-Type"="application/json";"Accept"="application/json"}

# The body variable is used to input any parameters that are required for the workflow. If there are no parameters, use an empty set of curly braces in quotes, "{}".
# To use parameters, assign the value for the "-Body" flag of the Invoke-Webrequest call by using a here-doc similar to the following:
<#
$body= @"
{
    "parameters": [
            {
                "type": "VC:HostSystem",
                "scope": "local",
                "name": "host",
                "value": {
                    "sdk-object":{
                        "type":"VC:HostSystem",
                        "id":"localhost/host-10"
                    }
                }
            },
            {
                "type": "string",
                "scope": "local",
                "name": "ServerOwner",
                "value": {
                    "string": {
                        "value": "administrator"
                    }
                }
            }
    ]
}
"@ 
#>

$body= "{}"

Try {
          $ExecuteReturn = Invoke-WebRequest -Method Post -uri $ExecuteURL -Headers $headers -Body $body
} 
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Host "Error executing workflow $WorkflowName : $ErrorMessage"
    Write-Host "Are input parameters defined and correct?"
    Exit 1

}


$LocationURL= $ExecuteReturn.Headers.Get_Item("Location")
$StateURL=$LocationURL + "state"


$WorkflowStatus=@{}
do {
    Try {
        $StatusReturn = Invoke-WebRequest -Method Get -uri $StateURL -Headers $headers
        $WorkflowStatus=(ConvertFrom-Json $StatusReturn.Content).value
        Write-Host "$WorkflowName : Current status [$WorkflowStatus]..."
        Start-Sleep -s 5
    } 
    Catch {
        $ErrorMessage = $_.Exception.Message
        Write-Host "Error getting status of workflow $WorkflowName : $ErrorMessage"
        Exit 1

    }
}
until ($WorkflowStatus -notmatch "running")

if ($WorkflowStatus -notmatch "completed") {
    Write-Host "Workflow $WorkflowName did not complete successfully."
    Exit 1
} else {
    Write-Host "Workflow $WorkflowName completed successfully."
}
