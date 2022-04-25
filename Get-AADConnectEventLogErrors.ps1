<#
.SYNOPSIS
	This script can be used on an AAD Connect server to retrieve event log entries for Azure export failures and create a CSV output file

.DESCRIPTION
	The AADC Error Logger tool is a powershell script that can be used on an AAD Connect server to retrieve event log entries for Azure export failures and create a CSV output file.

	The Output file will contain the Azure Connector Space DN, as well as the Object Type, OnPremises DN of the object (if a User, otherwise SamAccountName for groups) along with the attribute in conflict, the error and the error value.

	If the export error is due to an object in the tenant with a conflicting value, the script will output the Azure Object ID of the conflicting object, object type, along with the last dirsync time of the object (if applicable) and the SID of the conflicting Azure object.

	The script takes 3 arguments:

	1 - [NumberOfErrors] The number of recent Azure connector errors to retrieve.

	2 - [NoAzure] A switch to allow skipping the use of Azure AD powershell to retrieve offending object details.

	3 - [FileName] Filename to use for the output of the error details (CSV)

	If prompted for Azure credentials and the prompt fails, the script will default to local attribute details only and not retrieve Azure data.

.PARAMETER NumberOfErrors
	The number of recent Azure connector errors to retrieve

.PARAMETER NoAzure
	A switch to allow skipping the use of Azure AD powershell to retrieve offending object details

.PARAMETER FileName
	Filename to use for the output of the error CSV.

.EXAMPLE
	Get-AADConnectEventLogErrors.ps1 -NumberOfErrors 10

	Retrieves the latest 10 AAD Connect Azure AD export errors, outputs to ErrorsLog.CSV in the local directory and attempts to connect to Azure.

.EXAMPLE
    Get-AADConnectEventLogErrors.ps1 -NumberOfErrors 10 -NoAzure
    
    Retrieves the latest 10 AAD Connect Azure AD export errors, outputs to ErrorsLog.CSV in the local directory.  Does NOT attempt to connect to Azure.

.EXAMPLE
    Get-AADConnectEventLogErrors.ps1 -NumberOfErrors 10 -NoAzure -FileName Output.CSV
    
    Retrieves the latest 10 AAD Connect Azure AD export errors, outputs to output.CSV in the local directory.  Does NOT attempt to connect to Azure.

.INPUTS
	NumberOfErrors
    NoAzure
	FileName

.OUTPUTS
	CSV file

.NOTES
	NAME:	Get-AADConnectEventLogErrors.ps1
	AUTHOR:	Darryl Kegg
	DATE:	24 April, 2022
	EMAIL:	dkegg@microsoft.com

	VERSION HISTORY:
	1.0 24 April, 2022 	Initial Version
	1.1 25 April, 2022	Added Try\Catch to Azure object calls
						ImmutableID and conversion to Azure AAD Connect DN for reporting
						Added UserType to report for identification or conflicts with Guest objects

#>

[CmdletBinding()]
Param (
	[int]$NumberOfErrors = 618,
	[switch]$NoAzure,
	[string]$FileName = ".\ErrorsLog.csv"
)

If (Test-Path $FileName)
{
	$File  = Get-Item -Path $FileName
	$NewTimeStamp = (get-date -Format "MM.dd.yy.HH.mm.ss").ToString()
	Rename-Item $file -NewName "$($file.basename)$NewTimeStamp$($file.Extension)"
}

if (!$NoAzure)
{
	Try { Get-AzureADTenantDetail -ea Stop }
	Catch
	{
		Try
		{
			Connect-AzureAD -ea Stop
		}
		Catch
		{
			Write-Host -Fore Yellow "Unable to connect to Azure AD, limiting report detail to data from AAD Connect."
			$NoAzure = $true
		}
	}
}

$TempObject = $null
$TempObject = New-Object PSObject -Property @{            
    "Object Type" = $null
    "AzureDN" = $null
    "OnPrem Identifier" = $null
	"AttributeInError" = $null
	"Error Description" = $null
	"Attribute Value In Conflict" = $null
	"Azure ObjectID in Conflict" = $null
	"Cloud Conflict Object Type" = $null
	"Cloud Conflict Object User Type" = $null
	"Cloud Conflict SID" = $null
	"Cloud Conflict ImmutableID" = $null
	"Cloud Conflict AzureDN" = $null
    "Cloud Conflict Dir Synced"	= $false                
    "Cloud Conflict Last Dirsync" = $null
} 

$Logerrors = get-eventlog -LogName application -EntryType Error -InstanceId 1073748765 -Newest $NumberOfErrors

$Count = 0

foreach ($Item in $LogErrors)
{
	$ErrorObject = $null;
	$ErrorObject = $TempObject | Select-Object "Object Type", "AzureDN", "OnPrem Identifier", "AttributeInError", "Error Description", "Attribute Value In Conflict", "Azure ObjectID in Conflict", "Cloud Conflict Object Type", "Cloud Conflict Object User Type", "Cloud Conflict SID", "Cloud Conflict ImmutableID", "Cloud Conflict AzureDN", "Cloud Conflict Dir Synced", "Cloud Conflict Last Dirsync"
		
	$Detail = $Item.Message
	$AzureDNStartLocation = $detail.IndexOf("DN:")
	
	$AzureDN = $detail.Substring($AzureDNStartLocation + 4, 53)
	
	$ErrorNameStringArr = $detail -split ("Error Name: ")
	$ErrorNameString = $ErrorNameStringArr[1]
	$ErrorNameEndLocation = $ErrorNameString.IndexOf("`r`nE")
	$ErrorName = $ErrorNameString.substring(0, $ErrorNameEndLocation - 2)
	
	$AttributeNameStart = $ErrorNameString.indexof("[")
	$AttributeNameEnd = $ErrorNameString.indexof("]")
	$AttributeName = $ErrorNameString.Substring($AttributeNameStart + 1, ($AttributeNameEnd - 1) - $AttributeNameStart)
	
	$AzureObject = Get-ADSyncCSObject -DistinguishedName $AzureDN -ConnectorIdentifier b891884f-051e-4a83-95af-2544101c9083
	$AzureObjectAttributes = $AzureObject.Attributes
	$AzureObjectType = $AzureObject.ObjectType
	
	$ErrorHash = $null
	$ErrorHash = $azureobject.exporterror.ErrorExtraDetails | ConvertFrom-Json
	if ($ErrorHash)
	{
		$Hash = @{ }
		($ErrorHash | Get-Member -MemberType NoteProperty).Name | Foreach-Object { $hash[$_] = $ErrorHash.$_ }
		
		$ObjectIdInConflict = $hash.value[($hash.key.indexof('ObjectIdInConflict'))]
		$AttributeInConflict = $hash.value[($hash.key.indexof('AttributeConflictName'))]
		$AttributeValueInConflict = $hash.value[($hash.key.indexof('AttributeConflictValues'))]
	}
	else
	{
		$AttributeInConflict = $AttributeName
	}
	
	
	if ($AzureObjectType -eq "GROUP")
	{
		$OnPremDN = ($AzureObjectAttributes | where { $_.name -eq "onPremisesSamAccountName" }).values
	}
	elseif ($AzureObjectType -eq "USER")
	{
		$OnPremDN = ($AzureObjectAttributes | where { $_.name -eq "OnPremisesDistinguishedName" }).values
	}
	elseif ($AzureObjectType -eq "CONTACT")
	{
		$OnPremDN = ($AzureObjectAttributes | where { $_.name -eq "mail" }).values
	}
	elseif ($AzureObjectType -eq "DEVICE")
	{
		$OnPremDN = ($AzureObjectAttributes | where { $_.name -eq "displayName" }).values
	}
	
	$ErrorObject.'Object Type' = $AzureObjectType
	$ErrorObject.AzureDN = $AzureDN
	$ErrorObject.'OnPrem Identifier' = $OnPremDN[0]
	$ErrorObject.AttributeInError = $AttributeInConflict
	$ErrorObject.'Error Description' = $AttributeValueInConflict
	$ErrorObject.'Azure ObjectID in Conflict' = $ObjectIdInConflict

	# need azure connectivity here, or nothing returned
	if (!$NoAzure -and ($ObjectIdInConflict -ne $null) )
	{
		$AzureObject = $null
		Try
		{
			$AzureObject = Get-AzureADObjectByObjectId -ObjectIds $ObjectIdInConflict -ea Stop
			If ($AzureObject)
			{
				$CloudConflictObject = $AzureObject.ObjectType
				$CloudConflictSID = $AzureObject.OnPremisesSecurityIdentifier
				$CloudConflictDirSynced = $AzureObject.DirSyncEnabled
				$CloudConflictLastDirsync = $AzureObject.LastDirSyncTime
				
				$ErrorObject.'Cloud Conflict Object Type' = $CloudConflictObject
				$ErrorObject.'Cloud Conflict Object User Type' = $AzureObject.UserType
				$ErrorObject.'Cloud Conflict SID' = $CloudConflictSID
				
				$ErrorObject.'Cloud Conflict ImmutableID' = $AzureObject.ImmutableId
				
				if ($AzureObject.ImmutableID)
				{
					$enc = [system.text.encoding]::utf8
					$result = $enc.getbytes($AzureObject.ImmutableId)
					$newarray = @{ }
					$newarray = $result | foreach { [convert]::tostring($_, 16) }
					$middle = $newarray -join ''
					$ErrorObject.'Cloud Conflict AzureDN' = "CN={" + $middle + "}"
				}
				
				$ErrorObject.'Cloud Conflict Dir Synced' = $CloudConflictDirSynced
				$ErrorObject.'Cloud Conflict Last Dirsync' = $CloudConflictLastDirsync
				
			}
		}
		Catch {$null}
	}
	
	$ErrorObject | Export-Csv ErrorsLog.csv -Append -NoTypeInformation
	
	$ActivityMessage = "Gathering error details, please wait..."
	$StatusMessage = ("Processing {0} of {1}: {2}" -f $count, @($Logerrors).count, $OnPremDN[0])
	$PercentComplete = ($count / @($Logerrors).count * 100)
	Write-Progress -Activity $ActivityMessage -Status $StatusMessage -PercentComplete $PercentComplete
	$Count ++
}

