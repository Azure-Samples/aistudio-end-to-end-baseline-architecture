# Connect to Azure with your account
Connect-AzAccount

# Get the current Azure user's detail
$currentUser = Get-AzADUser -UserPrincipalName (Get-AzContext).Account.Id

# User's object ID (objectId)
$userObjectId = $currentUser.Id

# Output the user's object ID
Write-Host "Your Azure user object ID is: $userObjectId"
