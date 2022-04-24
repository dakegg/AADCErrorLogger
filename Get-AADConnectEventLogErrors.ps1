Param (
	[int]$NumberOfErrors = 649,
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
	"Cloud Conflict SID" = $null
    "Cloud Conflict Dir Synced"	= $false                
    "Cloud Conflict Last Dirsync" = $null
} 

$Logerrors = get-eventlog -LogName application -EntryType Error -InstanceId 1073748765 -Newest $NumberOfErrors

$Count = 0

foreach ($Item in $LogErrors)
{
	$ErrorObject = $null;
	$ErrorObject = $TempObject | Select-Object "Object Type", "AzureDN", "OnPrem Identifier", "AttributeInError", "Error Description", "Attribute Value In Conflict", "Azure ObjectID in Conflict", "Cloud Conflict Object Type", "Cloud Conflict SID", "Cloud Conflict Dir Synced", "Cloud Conflict Last Dirsync"
		
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
	
	<#
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "Object Type" -Value $AzureObjectType
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "AzureDN" -Value $AzureDN
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "OnPrem Identifier" -Value $OnPremDN[0]
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "AttributeInError" -Value $AttributeInConflict
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "Error Description" -Value $ErrorName
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "Attribute Value In Conflict" -Value $AttributeValueInConflict
	$ErrorObject | Add-Member -MemberType NoteProperty -Name "Azure ObjectID in Conflict" -Value $ObjectIdInConflict
	#>
	
	# need azure connectivity here, or nothing returned
	if (!$NoAzure -or !$ObjectIdInConflict)
	{
		$AzureObject = $null
		$AzureObject = Get-AzureADObjectByObjectId -ObjectIds $ObjectIdInConflict
		If ($AzureObject)
		{
			$CloudConflictObject = $AzureObject.ObjectType
			$CloudConflictSID = $AzureObject.OnPremisesSecurityIdentifier
			$CloudConflictDirSynced = $AzureObject.DirSyncEnabled
			$CloudConflictLastDirsync = $AzureObject.LastDirSyncTime
			
			<#
			$ErrorObject | Add-Member -MemberType NoteProperty -Name "Cloud Conflict Object Type" -Value $CloudConflictObject
			$ErrorObject | Add-Member -MemberType NoteProperty -Name "Cloud Conflict SID" -Value $CloudConflictSID
			$ErrorObject | Add-Member -MemberType NoteProperty -Name "Cloud Conflict Dir Synced" -Value $CloudConflictDirSynced
			$ErrorObject | Add-Member -MemberType NoteProperty -Name "Cloud Conflict Last Dirsync" -Value $CloudConflictLastDirsync
			#>
			
			$ErrorObject.'Cloud Conflict Object Type' = $CloudConflictObject
			$ErrorObject.'Cloud Conflict SID' = $CloudConflictSID
			$ErrorObject.'Cloud Conflict Dir Synced' = $CloudConflictDirSynced
			$ErrorObject.'Cloud Conflict Last Dirsync' = $CloudConflictLastDirsync
			
		}
	}
	
	$ErrorObject | Export-Csv ErrorsLog.csv -Append -NoTypeInformation
	
	$ActivityMessage = "Gathering error details, please wait..."
	$StatusMessage = ("Processing {0} of {1}: {2}" -f $count, @($Logerrors).count, $OnPremDN[0])
	$PercentComplete = ($count / @($Logerrors).count * 100)
	Write-Progress -Activity $ActivityMessage -Status $StatusMessage -PercentComplete $PercentComplete
	$Count ++
}



