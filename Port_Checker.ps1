#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Checks all ports on the system and reports which ones are listening, along with the process name and PID.

.DESCRIPTION
    # blank right now, but will be filled in later

.NOTES
    also blank right now, but will be filled in later
#>

param(
    [string]$OutputFile = "PortCheckResults.txt", # Optional: includes a default value
    [int]$PortRangeStart = 1, # Optional: includes a default value
    [int]$PortRangeEnd = 65535, # Optional: includes a default value
    [int]$Timeout = 30 # Optional: includes a default value
)

# ---------------------------------------------------------------------------
# 1. Configuration: Ports to check
# ---------------------------------------------------------------------------

$portsToCheck = @(21, 22, 23, 25, 53, 80, 110, 123, 143, 443, 445, 1433, 3306, 3389, 8000, 8088, 8443, 8888, 9000) # Add or remove ports as needed


# ---------------------------------------------------------------------------
# 2. HELPER FUNCTION: Takes an array of ports and prints weather each port is listening on this machine
# ---------------------------------------------------------------------------

function Test-Ports {
    param([int[]]$Ports)

    foreach ($Port in $Ports) {
        $PortListening = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($PortListening) {
            Write-Host "Port $Port is listening (PID: $($PortListening.OwningProcess))" -ForegroundColor Green
        } else {
            Write-Host "Port $Port is NOT listening" -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Check each port in the list and report the results
# ---------------------------------------------------------------------------

Test-Ports -Ports $portsToCheck


