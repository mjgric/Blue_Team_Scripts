<#This script disables autoruns, deletes bad users,
and changes defualt passwords. It is meant to be run on all windows machines
at the start of IRSec.#>

#Removes global autoruns. User autoruns will persist after this step.
Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\*"

#Array of local user accounts
$LocalUsers = Get-LocalUser

#Deletes all unwanted user accounts with user confirmation
Echo "------User Deletion------"
foreach ($User in $LocalUsers){
    Write-Host $User.Name
    $Decision = Read-Host -Prompt "Delete this user? y/n: "
    if ($Decision -eq "y"){
        Get-CimInstance -ClassName Win32_UserProfile | 
        Where-Object { $_.LocalPath.split('\')[-1] -eq $User.Name } | 
        Remove-CimInstance
        Remove-LocalUser -InputObject $User
    }
}

#Reset the array because accounts got blown up.
$LocalUsers = Get-LocalUser

#Password reset for all remaining users
Echo "------Password Changes------"
foreach ($User in $LocalUsers){
    $Pass = Read-Host -Prompt "New Password for "$User": " -AsSecureString
    Set-LocalUser -Name $User.Name -Password $Pass
}