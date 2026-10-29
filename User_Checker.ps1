#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Audits local user accounts against approved lists and offers to remove
    any account that isn't approved.

.NOTES
    Run from an elevated (Run as Administrator) PowerShell window.
    Uses the LocalAccounts module (built into Windows PowerShell 5.1 and
    PowerShell 7+ on Windows). It only handles LOCAL accounts, not domain accounts.
#>

# ---------------------------------------------------------------------------
# 1. CONFIGURATION: edit these arrays with users you want to approve
# ---------------------------------------------------------------------------
# @( ... ) creates an array. Items are separated by commas.
$ApprovedAdmins = @('Alice', 'AdminSteve')
$ApprovedUsers  = @('Bob', 'Carol', 'Dave')

# Built-in Windows accounts we never want to prompt about.
$BuiltInAccounts = @('Administrator', 'DefaultAccount', 'Guest', 'WDAGUtilityAccount')

# ---------------------------------------------------------------------------
# 2. FIND WHO IS AN ADMIN
# ---------------------------------------------------------------------------
# S-1-5-32-544 is the well-known SID (security identifier) of the local
# Administrators group. Using the SID instead of the name "Administrators"
# keeps the script working on non-English versions of Windows.
#
# Get-LocalGroupMember returns objects whose Name looks like "PCNAME\Alice".
# The pipeline (|) passes each object to the next command:
#   Where-Object   -> keeps only items matching a condition (here: real users, not groups)
#   ForEach-Object -> runs a code block on each item; $_ is the current item
#   .Split('\')[-1] -> splits "PCNAME\Alice" on the backslash, [-1] grabs the last piece ("Alice")
$AdminNames = Get-LocalGroupMember -SID 'S-1-5-32-544' |
    Where-Object { $_.ObjectClass -eq 'User' } |
    ForEach-Object { $_.Name.Split('\')[-1] }

# ---------------------------------------------------------------------------
# 3. CHECK EVERY LOCAL ACCOUNT
# ---------------------------------------------------------------------------
# Get-LocalUser lists all local accounts. foreach loops over them one at a time.
foreach ($Account in Get-LocalUser) {

    $Name = $Account.Name

    # -contains checks whether an array holds a value (case-insensitive by default).
    # 'continue' skips the rest of this loop pass and moves to the next account.
    if ($BuiltInAccounts -contains $Name) { continue }

    # Decide whether this account is an Admin or Standard user.
    if ($AdminNames -contains $Name) { $Role = 'Admin' } else { $Role = 'Standard' }

    # Decide whether it's approved for the role it currently holds.
    if ($Role -eq 'Admin') {
        $IsApproved = $ApprovedAdmins -contains $Name
    }
    else {
        # A standard account is fine if it's on either list.
        $IsApproved = ($ApprovedUsers -contains $Name) -or ($ApprovedAdmins -contains $Name)
    }

    # -------------------------------------------------------------------
    # 4. REPORT / PROMPT
    # -------------------------------------------------------------------
    if ($IsApproved) {
        Write-Host "[OK]      $Name ($Role)" -ForegroundColor Green

        # Extra check: someone approved only as a normal user who is secretly an admin.
        # We warn but don't delete, because the account itself is legitimate.
        if ($Role -eq 'Admin' -and $ApprovedUsers -contains $Name -and $ApprovedAdmins -notcontains $Name) {
            Write-Host "          WARNING: '$Name' is approved as a standard user but has admin rights." -ForegroundColor Yellow
            $answer = Read-Host "  Remove admin rights from '$Name'? (y/N)"
            if ($answer -match '^(y|yes)$') {
                try {
                    Remove-LocalGroupMember -Group 'Administrators' -Member $Name -ErrorAction Stop
                    Write-Host "  Removed '$Name' from Administrators." -ForegroundColor Cyan
                }
                catch {
                    Write-Host "  Failed to remove '$Name' from Administrators: $($_.Exception.Message)" -ForegroundColor Magenta
                }
            }
        }
        continue
    }

    Write-Host "[UNAPPROVED] $Name ($Role) - Enabled: $($Account.Enabled)" -ForegroundColor Red

    # Read-Host pauses the script and returns whatever the user types.
    $Answer = Read-Host "  Remove user '$Name'? (y/N)"

    if ($Answer -match '^(y|yes)$') {
        # try/catch handles errors: if Remove-LocalUser fails, the catch block runs
        # instead of the whole script crashing. -ErrorAction Stop turns a normal
        # (non-terminating) error into one that catch can actually catch.
        try {
            Remove-LocalUser -Name $Name -ErrorAction Stop
            Write-Host "  Removed '$Name'." -ForegroundColor Cyan
        }
        catch {
            # $_ here is the error record; .Exception.Message is the readable text.
            Write-Host "  Failed to remove '$Name': $($_.Exception.Message)" -ForegroundColor Magenta
        }
    }
    else {
        Write-Host "  Skipped '$Name'."
    }
}

Write-Host "`Audit complete." -ForegroundColor Cyan