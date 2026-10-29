#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Audits Windows services and offers to stop/disable/delete ones that look illegitimate.

.DESCRIPTION
    A service is considered "legit" if it passes ONE of these checks:
      1. Its name is in the $ApprovedServices allowlist, OR
      2. Its executable has a VALID digital signature from a publisher in
         $TrustedPublishers AND is not running from a suspicious folder.

    Anything else is flagged with the specific reasons, and you're asked what to do.

.NOTES
    Signed does not always mean safe, and unsigned does not always mean malicious
    (plenty of small legit vendors ship unsigned services). Treat flags as
    "worth a look", not as a verdict. Research a service before deleting it.
#>

# ---------------------------------------------------------------------------
# 1. CONFIGURATION
# ---------------------------------------------------------------------------
# Service names (the short "Name", not the DisplayName) you personally vouch for.
# Example: @('Spooler', 'MyCompanyAgent')
$ApprovedServices = @(
    'NothingYet'
)

# Regex patterns matched against the certificate's Subject text.
# 'O=Microsoft Corporation' matches a cert issued to Microsoft Corporation.
# Add vendors you trust, e.g. 'O=Google LLC', 'O="Intel Corporation"'
$TrustedPublishers = @(
    'O=Microsoft Corporation',
    'O=Microsoft Windows'
)

# Folders where a legit service should basically never live.
# A match is checked as a regex against the exe path, so backslashes are doubled (\\).
$SuspiciousPathPatterns = @(
    '\\Temp\\',
    '\\AppData\\',
    '\\Users\\',
    '\\ProgramData\\',
    '\\Downloads\\',
    '\\Windows\\Fonts\\'
)

# ---------------------------------------------------------------------------
# 2. HELPER FUNCTION: pull the .exe path out of a service's PathName
# ---------------------------------------------------------------------------
# A service's PathName can look like several things:
#   "C:\Program Files\Foo\foo.exe" -arg      (quoted, with arguments)
#   C:\Windows\System32\svchost.exe -k netsvcs (unquoted, with arguments)
# 'function' defines a reusable block of code. 'param' declares its input.
function Get-ServiceExePath {
    param([string]$PathName)

    if ([string]::IsNullOrWhiteSpace($PathName)) { return $null }

    # -match runs a regex; if it succeeds, captured groups land in $Matches.
    if ($PathName -match '^\s*"([^"]+)"') {
        $Path = $Matches[1]                 # text inside the quotes
    }
    elseif ($PathName -match '^\s*(.+?\.exe)') {
        $Path = $Matches[1]                 # everything up to the first ".exe" (lazy match)
    }
    else {
        $Path = $PathName.Trim()
    }

    # Turns things like %SystemRoot% into real paths.
    return [Environment]::ExpandEnvironmentVariables($Path)
}

# ---------------------------------------------------------------------------
# 3. GATHER SERVICES
# ---------------------------------------------------------------------------
# Get-CimInstance Win32_Service gives more detail than Get-Service, notably
# PathName (the exe), StartName (the account it runs as), and StartMode.
$Services = Get-CimInstance -ClassName Win32_Service

# A hashtable (@{}) is a key/value dictionary. We use it as a cache so we only
# check each exe's signature once (many services share svchost.exe).
$SignatureCache = @{}

Write-Host "Checking $($Services.Count) services...`n" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 4. CHECK EACH SERVICE
# ---------------------------------------------------------------------------
foreach ($Svc in $Services) {

    $Name = $Svc.Name

    # Check 1: manual allowlist
    if ($ApprovedServices -contains $Name) {
        Write-Host "[APPROVED] $Name" -ForegroundColor Green
        continue
    }

    # A List is a resizable array; we collect every reason this service looks off.
    $Reasons = [System.Collections.Generic.List[string]]::new()

    $ExePath = Get-ServiceExePath -PathName $Svc.PathName

    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) {
        # Test-Path checks whether the file exists. -LiteralPath avoids wildcard surprises.
        $Reasons.Add("Executable not found on disk ($ExePath)")
    }
    else {
        # Check 2: digital signature (cached)
        if (-not $SignatureCache.ContainsKey($ExePath)) {
            $SignatureCache[$ExePath] = Get-AuthenticodeSignature -FilePath $ExePath
        }
        $Sig = $SignatureCache[$ExePath]

        if ($Sig.Status -ne 'Valid') {
            # Status can be NotSigned, HashMismatch (file modified after signing), etc.
            $Reasons.Add("Signature status: $($Sig.Status)")
        }
        else {
            # Valid signature, but is it from a publisher we trust?
            $Subject = $Sig.SignerCertificate.Subject
            $Trusted = $false
            foreach ($Pattern in $TrustedPublishers) {
                if ($Subject -match [regex]::Escape($Pattern)) { $Trusted = $true; break }
            }
            if (-not $Trusted) {
                $Reasons.Add("Signed by an untrusted/unknown publisher: $Subject")
            }
        }

        # Check 3: location
        foreach ($Pattern in $SuspiciousPathPatterns) {
            if ($ExePath -match $Pattern) {
                $Reasons.Add("Runs from a suspicious location: $ExePath")
                break
            }
        }
    }

    # No reasons collected means it passed every check.
    if ($Reasons.Count -eq 0) {
        Write-Host "[OK]       $Name" -ForegroundColor DarkGreen
        continue
    }

    # -----------------------------------------------------------------------
    # 5. REPORT AND PROMPT
    # -----------------------------------------------------------------------
    Write-Host "`n[FLAGGED]  $Name  ($($Svc.DisplayName))" -ForegroundColor Red
    Write-Host "           State: $($Svc.State) | StartMode: $($Svc.StartMode) | RunsAs: $($Svc.StartName)"
    Write-Host "           Path : $($Svc.PathName)"
    foreach ($Reason in $Reasons) {
        Write-Host "           - $Reason" -ForegroundColor Yellow
    }

    $Answer = Read-Host "  [S]top + disable, [D]elete, or [N]o action? (S/D/N, default N)"

    switch -Regex ($Answer) {

        '^[Ss]' {
            try {
                # Stop-Service halts it now; Set-Service -StartupType Disabled
                # prevents it from starting again on reboot. This is reversible.
                if ($Svc.State -eq 'Running') { Stop-Service -Name $Name -Force -ErrorAction Stop }
                Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
                Write-Host "  Stopped and disabled '$Name'.`n" -ForegroundColor Cyan
            }
            catch {
                Write-Host "  Failed: $($_.Exception.Message)`n" -ForegroundColor Magenta
            }
        }

        '^[Dd]' {
            # Deleting is permanent, so ask a second time.
            $Confirm = Read-Host "  Permanently delete service '$Name'? Type the service name to confirm"
            if ($Confirm -eq $Name) {
                try {
                    if ($Svc.State -eq 'Running') { Stop-Service -Name $Name -Force -ErrorAction Stop }

                    # sc.exe is a classic Windows tool. We use it because the
                    # Remove-Service cmdlet only exists in PowerShell 6+.
                    # & is the "call operator": it runs the command that follows.
                    & sc.exe delete $Name | Out-Null

                    # $LASTEXITCODE holds the exit code of the last external program (0 = success).
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  Deleted '$Name'. (If it was running, a reboot may finish removal.)`n" -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "  sc.exe returned exit code $LASTEXITCODE.`n" -ForegroundColor Magenta
                    }
                }
                catch {
                    Write-Host "  Failed: $($_.Exception.Message)`n" -ForegroundColor Magenta
                }
            }
            else {
                Write-Host "  Name didn't match. Skipped.`n"
            }
        }

        default {
            Write-Host "  No action taken.`n"
        }
    }
}

Write-Host "Service audit complete." -ForegroundColor Cyan