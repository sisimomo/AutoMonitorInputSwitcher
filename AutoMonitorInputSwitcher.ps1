#Thanks to - https://gist.github.com/selvalogesh/37b99e43b932d42b5a9901a33284b4fa
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')    | out-null
[System.Reflection.Assembly]::LoadWithPartialName('presentationframework')   | out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')          | out-null
[System.Reflection.Assembly]::LoadWithPartialName('WindowsFormsIntegration') | out-null

$ControlMyMonitorRootPath = "C:\Program Files\ControlMyMonitor"
$ControlMyMonitorExePath = "$ControlMyMonitorRootPath\ControlMyMonitor.exe"
$ConfigPath = "$ControlMyMonitorRootPath\AutoMonitorInputSwitcher-Config.json"
$LogFileFolderPath = "$env:TEMP\AutoMonitorInputSwitcher\"
$icon = "$ControlMyMonitorRootPath\AutoMonitorInputSwitcher-Icon.ico"
if (!(Test-Path $icon -PathType Leaf)) {
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($ControlMyMonitorExePath)    
}

Function Write-Log($LogString) {
    $Path = "$LogFileFolderPath\$("{0:yyyy/MM/dd}" -f (Get-Date)).log"
    # Create folder if is missing
    If (!(Test-Path $Path)) {
        New-Item -Path $Path -Force
    }
    Add-content $Path -Value $LogString -Force
}

Function Log-Info($str){
    Write-Log "$("[{0:yyyy/MM/dd} {0:HH:mm:ss}]" -f (Get-Date)) INFO: $str"
}

Log-Info "Start Auto Monitor Input Switcher with $ConfigPath"

# Delete old log files
Get-ChildItem $LogFileFolderPath -File | Where CreationTime -lt (Get-Date).AddDays(-30) | Remove-Item -Force

$Config = (Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json)


################################################################################################################################"
# ACTIONS FROM THE SYSTRAY
################################################################################################################################"

# ----------------------------------------------------
# Part - Add the systray menu
# ----------------------------------------------------        
$Main_Tool_Icon = New-Object System.Windows.Forms.NotifyIcon
$Main_Tool_Icon.Text = "Auto Monitor Input Switcher"
$Main_Tool_Icon.Icon = $icon
$Main_Tool_Icon.Visible = $true

$Menu_Start = New-Object System.Windows.Forms.MenuItem
$Menu_Start.Enabled = $false
$Menu_Start.Text = "Start"

$Menu_Stop = New-Object System.Windows.Forms.MenuItem
$Menu_Stop.Enabled = $true
$Menu_Stop.Text = "Stop"

$Menu_Exit = New-Object System.Windows.Forms.MenuItem
$Menu_Exit.Text = "Exit"


$contextmenu = New-Object System.Windows.Forms.ContextMenu
$Main_Tool_Icon.ContextMenu = $contextmenu
$Main_Tool_Icon.contextMenu.MenuItems.AddRange($Menu_Start)
$Main_Tool_Icon.contextMenu.MenuItems.AddRange($Menu_Stop)
$Main_Tool_Icon.contextMenu.MenuItems.AddRange($Menu_Exit)

# ---------------------------------------------------------------------
# Action
# ---------------------------------------------------------------------
$ActionScript = {

    function Get-TimeStamp {
        return "[{0:yyyy/MM/dd} {0:HH:mm:ss}]" -f (Get-Date)
    }

    Function Write-Log($LogString) {
        Add-content "$using:LogFileFolderPath\$("{0:yyyy/MM/dd}" -f (Get-Date)).log" -Value $LogString -Force
    }

    Function Log-Error($str){
        Write-Log "$(Get-TimeStamp) ERROR: $str"
    }

    Function Log-Info($str){
        Write-Log "$(Get-TimeStamp) INFO: $str"
    }

    Function Log-Debug($str){
        if ($using:Config.DebugMode) {
            Write-Log "$(Get-TimeStamp) DEBUG: $str"
        }
    }

    Function Execute-Control-My-Monitor-Command{
        $ParmsStr = ""
        foreach ($Monitor in $using:Config.Monitors) {
            $ParmsStr += "/SetValueIfNeeded `"$($Monitor.Id)`" $($Monitor.InputSelectVcpCode) $($Monitor.WantedInputValue) "
        }
        $Parms = $ParmsStr.Split(" ")
        Log-Info "Executed command: $using:ControlMyMonitorExePath $Parms"
        & "$using:ControlMyMonitorExePath" $Parms
    }

    Function Is-Device-Present {
        $Device = (Get-WmiObject -Query "SELECT * FROM Win32_PnPEntity WHERE Name = '$($using:Config.DeviceName)'")
        return $Device -ne $null -And $Device.Present
    }

    $PreviousDevicePresentState = $false
    Do {
        try{
            $CurrentDevicePresentState = Is-Device-Present
            if ($CurrentDevicePresentState -ne $PreviousDevicePresentState) {
                Log-Info "Device presence change from $PreviousDevicePresentState to $CurrentDevicePresentState"
                if ($CurrentDevicePresentState) {
                    Execute-Control-My-Monitor-Command
                }
                $PreviousDevicePresentState = $CurrentDevicePresentState
            } else {
                Log-Debug "Device presence didn't change"
            }
        } catch {
            Log-Error $_
        }
        Start-Sleep -s 1
    } while ($true)
}

Log-Info "Start Action Script"
Start-Job -ScriptBlock $ActionScript -Name "ActionScript"

# ---------------------------------------------------------------------
# Action when after a click on the systray icon
# ---------------------------------------------------------------------
$Main_Tool_Icon.Add_Click({
    If ($_.Button -eq [Windows.Forms.MouseButtons]::Left) {
        $Main_Tool_Icon.GetType().GetMethod("ShowContextMenu", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).Invoke($Main_Tool_Icon, $null)
    }
})

# When Start is clicked, start ActionScript job and get its pid
$Menu_Start.add_Click({
    $Menu_Stop.Enabled = $true
    $Menu_Start.Enabled = $false
    Log-Info "Start Action Script"
    Stop-Job -Name "ActionScript"
    Start-Job -ScriptBlock $ActionScript -Name "ActionScript"
})

# When Stop is clicked, kill stay ActionScript job
$Menu_Stop.add_Click({
    $Menu_Stop.Enabled = $false
    $Menu_Start.Enabled = $true
    Log-Info "Stop Action Script"
    Stop-Job -Name "ActionScript"
})

# When Exit is clicked, close everything and kill the PowerShell process
$Menu_Exit.add_Click({
    $Main_Tool_Icon.Visible = $false
    Log-Info "Exit Auto Monitor Input Switcher"
    Stop-Job -Name "ActionScript"
    Stop-Process $pid
})

# Force garbage collection just to start slightly lower RAM usage.
[System.GC]::Collect()

# Create an application context for it to all run within.
# This helps with responsiveness, especially when clicking Exit.
$appContext = New-Object System.Windows.Forms.ApplicationContext
[void][System.Windows.Forms.Application]::Run($appContext)