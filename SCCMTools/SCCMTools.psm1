<#  
.Description
This Module contains tools to perform the various SCCM Client functions as well as restart the SCCM service on a client

There are also two experimental functions to list and deploy pending updates


#>


Function Get-SCCMClientUpdateStatus
{
<#
.SYNOPSIS
Gathers status information from a ConfigMan Client regarding Software Updates

.DESCRIPTION


.EXAMPLE

.NOTES

#>
[CmdletBinding(ConfirmImpact='Medium')]
param (
      # Enter a computername or multiple computernames
      [Parameter(
      Mandatory=$false, 
      ValueFromPipeline=$True, 
      ValueFromPipelineByPropertyName=$True,
      HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")]             
      [Alias("__Server")]
      [String[]]$ComputerName = $env:COMPUTERNAME,
      # Enter a Credential object, like (Get-credential)
      [Parameter(
      HelpMessage="Enter a Credential object, like (Get-credential)")]
      [System.Management.Automation.PSCredential]$credential
      )
Begin 
    {
        $Params = @{
                Scriptblock = {
                        Try {$VerbosePreference = $Using:VerbosePreference} Catch {}
                        Write-Verbose "Query Updates on $ENV:COMPUTERNAME"
                        $Updates = gwmi -Namespace root\ccm\ClientSDK -Class CCM_SoftwareUpdate
                        $UP = $Updates | Where {($_.Evaluationstate -eq 8) -or ($_.Evaluationstate -eq 9)}
                        $inst = $Updates | where {$_.Evaluationstate -eq 6}
                        Write-Verbose "Gather LastBootTime"
                        $lbt = Get-WmiObject win32_operatingsystem
                        $lbt = $lbt.ConvertToDateTime($lbt.LastBootUpTime)
                        Write-Verbose "Get pending status"
                        $pend = Try {([wmiclass]"\\$env:COMPUTERNAME\root\ccm\ClientSDK:CCM_ClientUtilities").DetermineIfRebootPending().rebootpending} Catch {}
                        Write-Verbose "Create custom object"
                        New-Object -TypeName PSObject -Property @{
                                ComputerName = $ENV:COMPUTERNAME
                                'PendingReboot?' = $pend
                                UpdateCount = ($Updates | measure).Count
                                UpdatesPendingReboot = ($UP | measure).Count
                                UpdatesInProgress = ($inst | measure).Count
                                LastRebootTime = $lbt
                            }
                    }
            }
        If ($credential) {$Params.Add('Credential',$credential)}
    }
Process
    {
        [System.Collections.ArrayList]$comps += $ComputerName 
    }
End {
        if ($Comps -contains $ENV:COMPUTERNAME)
                {
                    $Comps.Remove("$ENV:COMPUTERNAME")
                    $local = $True
                }
            if (($Comps |measure).Count -gt 0)
                {
                    try {$params.Add('ComputerName',$Comps)} Catch {}
                    Invoke-Command @params | select ComputerName,'PendingReboot?',UpdateCount,UpdatesPendingReboot,UpdatesInProgress,LastRebootTime
                }
            if ($local)
                {
                    Try {$params.Remove('ComputerName')} Catch {}
                    Invoke-Command @params | select ComputerName,'PendingReboot?',UpdateCount,UpdatesPendingReboot,UpdatesInProgress,LastRebootTime
                }   
    }
}

Function Start-SCCMUpdateEvaluationCycle
{
<#
.SYNOPSIS
Initiates the Software Updates Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Software Updates and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMUpdateEvaluationCycle

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        Write-Verbose "Building Scriptblock"
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Software Updates Assignments Evaluation Cycle"}
                $action.PerformAction()
                Write-Verbose "The SCCM client is now performing the Software Update Evaluation Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) 
            {
                Write-Verbose "Adding credentials"
                $param.Add("Credential",$credential)
            }
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMSoftwareMeteringCycle
{
<#
.SYNOPSIS
Initiates the Software Metering Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Software Metering and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMSoftwareMeeteringCycle

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $Action = $SMSActions | where {$_.Name -eq "Software Metering Usage Report Cycle"}
                $Action.PerformAction()
                Write-verbose "The SCCM client is now performing the Software Metering Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Update-SCCMMachinePolicy
{
<#
.SYNOPSIS
Initiates the Machine Policy Evaluation Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Machine Policy Evaluation and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Update-SCCMMachinePolicy

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {`
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Request & Evaluate Machine Policy"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the Machine Policy Evaluation Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
   {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMUpdatesSourceScan
{
<#
.SYNOPSIS
Initiates the Updates Source scan Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Updates Source scan and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMUpdateSourceScan

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Updates Source Scan Cycle"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the Updates Source scan Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Update-SCCMUserPolicy
{
<#
.SYNOPSIS
Initiates the User Policy Evaluation Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the User Policy Evaluation and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMUserPolicy

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Request & Evaluate User Policy"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the User Policy Evaluation Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
       If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMHardwareInventory
{
<#
.SYNOPSIS
Initiates the Hardware Inventory Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Hardware Inventory and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMHardwareInventory

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
    $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Hardware Inventory Collection Cycle"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the Hardware Inventory Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMSoftwareInventory
{
<#
.SYNOPSIS
Initiates the Software Inventory Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Software Inventory and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]
.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMSoftwareInventory

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Software Inventory Collection Cycle"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the Software Inventory Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
   {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Update-SCCMApplicationPolicy
{
<#
.SYNOPSIS
Initiates the Application Policy Evaluation Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Application Policy Evaluation and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Update-SCCMApplicationPolicy

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Application Global Evaluation Task"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the Application Policy Evaluation Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMDataDiscovery
{
<#
.SYNOPSIS
Initiates the Data Discovery Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the Data Discovery and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMDataDiscovery

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Discovery Data Collection Cycle"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the Data Discovery Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMFileCollection
{
<#
.SYNOPSIS
Initiates the File Collection Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the File Collection and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMFileCollection

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "Standard File Collection Cycle"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the File Collection Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Start-SCCMMSIProductSource
{
<#
.SYNOPSIS
Initiates the MSI Product Source Cycle on a given computer

.DESCRIPTION
Uses a COM interface and Invoke-Command to initiate the MSI Product Source and Evalutation cycle on a local or remote computer

.PARAMETER ComputerName

.PARAMETER Credential
Accepts a credential object, [System.Management.Automation.PSCredential]

.EXAMPLE 
Get-content C:\computers.txt | Start-SCCMMSIProductSource

Starts the cycle on all computers listed in the file c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
            if (-not(Test-Path C:\Windows\CCM\CcmExec.exe)) 
                {
                Write-Warning "The SCCM Client is not installed on $env:COMPUTERNAME"
                }
            Else 
                {
                $CPAppletMGR = new-object -ComObject CPApplet.CPAppletmgr
                $SMSActions = $CPAppletMGR.GetClientActions()
                $action = $SMSActions | where {$_.Name -eq "MSI Product Source Update Cycle"}
                $action.PerformAction()
                Write-verbose "The SCCM client is now performing the MSI Product Source Cycle on $env:COMPUTERNAME"
                }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
    }
End {}
}

Function Restart-SCCMAgent
{
<#
.SYNOPSIS
Restarts the SCCM Agent

.DESCRIPTION
Uses Invoke-Command and Restart-service to restart the ccmexec service on a target computer of computers

.EXAMPLE 
Get-content C:\computers.txt | Restart-SCCMAgent

Restarts the SCCM Agent on all the computers listed in c:\computers.txt

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]

Param
    (
        # Enter a ComputerName or IP Address, accepts multiple ComputerNames
        [Parameter( 
        ValueFromPipeline=$True, 
        ValueFromPipelineByPropertyName=$True,
        HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames")] 
        [String[]]$ComputerName = "$env:COMPUTERNAME",
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential,
        # Activate this switch to force the function to run an ICMP check before running
        [Parameter(
        HelpMessage="Activate this switch to force the function to run an ICMP check before running")]
        [Switch]$ping
    )
Begin 
    {
        $param = @{ScriptBlock = {
                Get-Service Ccmexec | Restart-Service
            }}
        if ($credential) {$param.Add("Credential",$credential)}
                
    }
Process 
    {
        If ($Ping) 
            {
                Write-Verbose "Testing connection to $ComputerName"
                if (-not(Test-Connection -ComputerName $ComputerName -Quiet)) 
                    {
                        Write-Warning "Could not ping $ComputerName" ; $Problem = $true
                    }
            }
        Write-Verbose "Beginning operation on $ComputerName"
        If (-not($Problem))
            {
                Try 
                    {
                        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -ComputerName $ComputerName @param}
                        Else {Invoke-Command @param}
                    }
                Catch
                    {
                        Write-Warning $_.exception.message
                        Write-Warning "Operation failed on $ComputerName"
                        $Problem = $True
                    }
            }
        if ($Problem) {$Problem = $false}
        }
End {}
}

Function Get-SCCMLogEntry
{
<#
.SYNOPSIS
Retrieves timestamped SCCM log entries

.DESCRIPTION
Reads SCCM Logs and creates custom object for the individual entries.  The date is a datetime object and can be sorted and filtered.

.EXAMPLE
Get-SCCMLog -path C:\Windows\ccm\Logs\WUAHandler.log

message                                 date                          
-------                                 ----                          
Search Criteria is (DeploymentAction... 5/16/2013 10:08:00 PM         
Async searching of updates using WUA... 5/16/2013 10:08:00 PM         
Async searching completed.              5/16/2013 10:08:13 PM         
Successfully completed scan.            5/16/2013 10:08:14 PM         
Its a WSUS Update Source type ({BFEB... 5/17/2013 10:37:00 PM         
...

Pulls the entries from the WUAHanlder log file on the local computer TestVM

.NOTES
Written by Jason Morgan
Last Modified 7/17/2013

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
[OutputType('PSObject')]
Param 
    (
        # Enter the path to the target SCCM Log
        [Parameter(Mandatory=$True,
         HelpMessage="Enter the path to the target SCCM Log")]
        [String]$path,
        # Enter the target computer name, uses PSRemoting so similar restrictions apply when using an IP address
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$True,
        ValueFromPipelineByPropertyName=$True) ]
        [string[]]$ComputerName	= $env:COMPUTERNAME,
        # Enter the startime for the log
        [Parameter(Mandatory=$false)]
        [datetime]$starttime
    )
Begin 
    {
        $params = @{
                Argumentlist = $Path,$starttime
                ScriptBlock = {
                        Param ($Path,$starttime)
                        get-content -path $Path | ForEach-Object {
                                if (-not($_.endswith('">')))
                                    {
                                        $string += $_
                                        $frag= $true    
                                    }
                                Else 
                                    {
                                        $string += $_
                                        $frag =$false
                                    }
                                if (-not($frag))
                                    {
                                        $hash = @{
                                                Message = ($string -Split 'LOG')[1].trimstart('[').trimend(']')
                                                date = [datetime]"$(($string -Split 'date="')[1].substring(0,10).trimend(' ').trimend('"')) $(($string -csplit 'time="')[1].substring(0,12))" 
                                            } 
                                        $entry = New-Object -TypeName PSObject -Property $hash
                                        if ($StartTime) {If ($entry.date -ge $StartTime) {$entry}}
                                        Else {$entry}
                                        Remove-Variable string
                                    }
                        }
                    }
            }
    }
Process
    {
        If ($ComputerName -ne $env:COMPUTERNAME) {Invoke-Command -Computername $ComputerName @params} 
        Else {Invoke-Command @params}
    }
End {}
}

Function Test-SCCMPatchStart
{
<#
.SYNOPSIS
Test if a system has started patching

.DESCRIPTION
Scrubs the WUAHanlder log to determine if patching has started within a specified timeframe

.EXAMPLE
Get-Content c:\servers.txt | Test-SCCMPatchStart

.NOTES
Written by Jason Morgan
Last Modified 8/21/2013

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
[OutputType('PSObject')]
Param 
    (
        # Enter the target computer name, uses PSRemoting so similar restrictions apply when using an IP address
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$True,
        ValueFromPipelineByPropertyName=$True) ]
        [string[]]$ComputerName,
        # Log entry age in hours
        [int]$age = 8
    )
Begin {}
Process
    {
        If 
            (
                Get-SCCMLogEntry -ComputerName $ComputerName -path C:\Windows\CCM\logs\WUAHandler.log -starttime ((Get-Date).addhours(-$age))| 
                where {$_.message -like '*Synchronous searching of all updates started...*'}
            ) 
            {
                New-object -TypeName PSObject -Property @{
                        ComputerName = $ComputerName
                        Patching = $true
                    }
            }
        Else 
            {
                    New-object -TypeName PSObject -Property @{
                        ComputerName = $ComputerName
                        Patching = $False
                    }
            }
    }
End {}
}

Function Get-LastRebootTime
{
<#
.SYNOPSIS
Display the last reboot time of a particular Computer

.DESCRIPTION
Uses PSRemoting and the Win32_OperatingSystem class to output a custom object with the last reboot time and Computername of one or more computers

.EXAMPLE
Get-content .\computers.txt | Get-Lastreboottime

.NOTES
Written by Jason Morgan
Last Modified 8/21/2013

#>
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
[OutputType('PSObject')]
Param 
    (
        # Enter the target computer name, uses PSRemoting so similar restrictions apply when using an IP address
        [Parameter(Mandatory=$false,
        ValueFromPipeline=$True,
        ValueFromPipelineByPropertyName=$True) ]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        # Enter a Credential object, like (Get-credential)
        [Parameter(
        HelpMessage="Enter a Credential object, like (Get-credential)")]
        [System.Management.Automation.PSCredential]$credential
    )
Begin 
    {
        $param = @{
                ScriptBlock = {
                $OS = Get-WmiObject -Class Win32_Operatingsystem
                New-Object -TypeName PSObject -Property @{
                        BootTime = $OS.ConvertToDateTime($OS.LastBootUpTime)
                        ComputerName = $env:COMPUTERNAME
                    }
            }}
        if ($credential) {$param.Add("Credential",$credential)}
    }
Process
    {
        If ($ComputerName -eq $env:COMPUTERNAME) {Invoke-Command @param | select Computername,Boottime}
        Else {Invoke-Command -computername $ComputerName @param | select Computername,Boottime}
    }
}

function Invoke-SCCMDCMEvaluation
{
<#
.SYNOPSIS
Begins the ConfigMan client Desired Configuration Management / Configuration Baseline evaluation process

.DESCRIPTION
Using Invoke-Command and the SCCM WMI objects this function will launch the Configuration Baseline 
evaluation process.  

.EXAMPLE
Get-Content C:\Servers.txt | Invoke-SCCMDCMEvaluation

Begins evaluation on all servers in the servers.txt file

.NOTES
Written for the Verizon ISD
By Jason Morgan
Created: 12/12/2013
Last Modified: 12/17/2013

#>
[CmdletBinding(ConfirmImpact='Medium')]
param (
      # Enter a computername or multiple computernames
      [Parameter(
                Mandatory=$True, 
                ValueFromPipeline=$True, 
                ValueFromPipelineByPropertyName=$True,
                HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames"
                )]             
      [Alias("__Server")]
      [Alias("PSComputerName")]
      [String[]]$ComputerName,
      # Specify a Baseline via it's DisplayName, that being the friendly name viewable in the SCCM console
      [Parameter(
                Mandatory=$True,
                ValueFromPipelineByPropertyName=$True,
                HelpMessage="Specify the name of the target Baseline or type 'All' to have the function evaluate all applicable baselines.
                If you are unsure what baselines are available please run Get-SCCMDCMCompliance"
                )]
      [Alias("DisplayName")]
      [string]$Baseline = "All"
      )
Begin 
    {
        $Params = @{
                ArgumentList = $Baseline
                Scriptblock = {
                        Param ($Baseline)
                        try {$VerbosePreference = $Using:VerbosePreference} catch {}
                        Get-WmiObject -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration | 
                        Foreach {
                                    if ($Baseline -notlike "All")
                                        {
                                            $run = $_.displayname -like $Baseline
                                        }
                                    if ($Baseline -like "All")
                                        {
                                            $run = $True
                                        }
                                    $Pol = $_.Displayname
                                    if ($run)
                                        {
                                            $val = ([wmiclass]"\\$env:COMPUTERNAME\root\ccm\dcm:SMS_DesiredConfiguration").TriggerEvaluation($_.Name, $_.Version)
                                            if ($val.returnvalue -ne 0)
                                                {
                                                    Write-Error "Failed to start evaluation for $pol, activity returned $($val.returnvalue)"
                                                }
                                            else
                                                {
                                                    Write-Verbose "Successfully started evaluation for $pol on $env:COMPUTERNAME"
                                                }
                                        }
                                    else {Write-Verbose "Skipped Policy: $Pol"}
                                }
                    }
            }
    }
Process
    {
        [System.Collections.ArrayList]$comps += $ComputerName 
    }
End {
        if ($Comps -contains $ENV:COMPUTERNAME)
                {
                    $Comps.Remove("$ENV:COMPUTERNAME")
                    $local = $True
                }
            if (($Comps |measure).Count -gt 0)
                {
                    $params.Add('ComputerName',$Comps)
                    Invoke-Command @params
                }
            if ($local)
                {
                    Try {$params.Remove('ComputerName')} Catch {}
                    Invoke-Command @params
                }   
    }
}

function Get-SCCMDCMCompliance
{
<#
.SYNOPSIS
Retrieves information on DCM baselines 

.DESCRIPTION
Working with PSRemoting this function gathers data on SCCM Compliance Baselines and their current status.

.NOTES
Written for the Verizon ISD
By Jason Morgan
Created: 12/12/2013
Last Modified: 12/17/2013

#>
[CmdletBinding(ConfirmImpact='Medium')]
param (
      # Enter a computername or multiple computernames
      [Parameter(
                Mandatory=$false, 
                ValueFromPipeline=$True, 
                ValueFromPipelineByPropertyName=$True,
                HelpMessage="Enter a ComputerName or IP Address, accepts multiple ComputerNames"
                )]             
      [Alias("__Server")]
      [Alias("PSComputerName")]
      [String[]]$ComputerName = $ENV:COMPUTERNAME,
      # Specify a Baseline via it's DisplayName, that being the friendly name viewable in the SCCM console
      [Parameter(
                Mandatory=$false,
                ValueFromPipelineByPropertyName=$True
                )]
      [Alias("DisplayName")]
      [string]$Baseline = "All"
      )
Begin 
    {
        $Params = @{
                ArgumentList = $Baseline
                Scriptblock = {
                        Param ($Baseline)
                        try {$VerbosePreference = $Using:VerbosePreference} catch {}
                        if ($Baseline -notlike "All")
                            {
                                $run = $_.displayname -like $Baseline
                            }
                        if ($Baseline -like "All")
                            {
                                $run = $True
                            }
                        if ($run)
                            {
                                Get-WmiObject -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration | 
                                select PSComputerName,DisplayName,@{l='Compliance';E={($_.compliancedetails -as [xml]).ConfigurationItemReport.CIComplianceState} }
                            }
                        Else
                            {
                                Get-WmiObject -Namespace root\ccm\dcm -Class SMS_DesiredConfiguration | Where {$_.displayname -like $Baseline} |
                                select PSComputerName,DisplayName,@{l='Compliance';E={($_.compliancedetails -as [xml]).ConfigurationItemReport.CIComplianceState} }
                            }
                    }
            }
    }
Process
    {
        [System.Collections.ArrayList]$comps += $ComputerName 
    }
End {
        if ($Comps -contains $ENV:COMPUTERNAME)
                {
                    $Comps.Remove("$ENV:COMPUTERNAME")
                    $local = $True
                }
            if (($Comps |measure).Count -gt 0)
                {
                    $params.Add('ComputerName',$Comps)
                    Invoke-Command @params | Select PSComputerName,DisplayName,Compliance
                }
            if ($local)
                {
                    Try {$params.Remove('ComputerName')} Catch {}
                    Invoke-Command @params | Select PSComputerName,DisplayName,Compliance
                }   
    }
}

