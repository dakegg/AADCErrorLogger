The AADC Error Logger tool is a powershell script that can be used on an AAD Connect server to retrieve event log entries for Azure export failures and create a CSV output file.

The Output file will contain the Azure Connector Space DN, as well as the Object Type, OnPremises DN of the object (if a User, otherwise SamAccountName for groups)
along with the attribute in conflict, the error and the error value.

If the export error is due to an object in the tenant with a conflicting value, the script will output the Azure Object ID of the conflicting object, object type,
along with the last dirsync time of the object (if applicable) and the SID of the conflicting Azure object.

The script takes 2 arguments:

1 - The number of recent Azure connector errors to retrieve.
2 - A switch to allow skipping the use of Azure AD powershell to retrieve offending object details.

If prompted for Azure credentials and the prompt fails, the script will default to local attribute details only and not retrieve Azure data.

