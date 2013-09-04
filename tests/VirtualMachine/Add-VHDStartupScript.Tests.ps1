$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Describe "Add-VHDStartupScript" {
    try{
        $TargetScriptDirectory = "Boxstarter.Startup"
        Import-Module "$here\..\..\Boxstarter.VirtualMachine\Boxstarter.VirtualMachine.psd1" -Force
        mkdir $env:temp\Boxstarter.tests | Out-Null
        $testRoot="$env:temp\Boxstarter.tests"
        $v = new-vhd -Path $testRoot\test.vhdx -SizeBytes 200MB | Mount-VHD -PassThru | Initialize-Disk -PartitionStyle mbr -Confirm:$false -PassThru | New-Partition -UseMaximumSize -AssignDriveLetter -MbrType IFS | Format-Volume -NewFileSystemLabel "VHD" -Confirm:$false
        Get-PSDrive | Out-Null
        mkdir "$($v.DriveLetter):\Windows\System32\config" | Out-Null
        reg save HKLM\Software "$($v.DriveLetter):\Windows\System32\config\SOFTWARE" /y /c | Out-Null
        Dismount-VHD $testRoot\test.vhdx
        New-Item "$testRoot\file1.ps1" -Type File | Out-Null
        New-Item "$testRoot\file2.ps1" -Type File | Out-Null

        Context "When adding a startup script to a clean vhd" {

            Add-VHDStartupScript $testRoot\test.vhdx -FilesToCopy "$testRoot\file1.ps1","$testRoot\file2.ps1" {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null

            $vol = Mount-VHD "$testRoot\test.vhdx" -Passthru | get-disk | Get-Partition | Get-Volume
            Get-PSDrive | Out-Null
            It "Should create startup script"{
                & "$($vol.DriveLetter):\$TargetScriptDirectory\startup.bat" | should be "hi"
            }
            It "Should copy supporting scripts"{
                Test-Path "$($vol.DriveLetter):\$TargetScriptDirectory\file1.ps1" | should be $true
                Test-Path "$($vol.DriveLetter):\$TargetScriptDirectory\file2.ps1" | should be $true
            }
            It "Should set Group Policy"{
                reg load HKLM\VHDSYS "$($vol.DriveLetter):\windows\system32\config\software" | Out-Null
                (Get-ItemProperty -path "HKLM:\VHDSYS\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0\0" -name Script).Script | should be "%SystemDrive%\$TargetScriptDirectory\startup.bat"
            }
            [GC]::Collect()
            reg unload HKLM\VHDSYS | Out-Null
            Remove-Item "$($vol.DriveLetter):\Windows\System32\config\SOFTWARE"
            reg save HKLM\Software "$($vol.DriveLetter):\Windows\System32\config\SOFTWARE" /y /c | Out-Null
            Dismount-VHD $testRoot\test.vhdx
        }

        Context "When adding a startup script when another startup script exists" {
            Add-VHDStartupScript $testRoot\test.vhdx {
                    function say-hi {"hi"}
                    say-hi
                }
            $v = Mount-VHD $testRoot\test.vhdx -Passthru | get-disk | Get-Partition | Get-Volume
            Get-PSDrive | Out-Null
            reg load HKLM\VHDSYS "$($v.DriveLetter):\windows\system32\config\software" | out-null
            Set-ItemProperty -path "HKLM:\VHDSYS\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0\0" -name Script -value "%SystemDrive%\$TargetScriptDirectory\otherstartup.bat"
            [GC]::Collect()
            reg unload HKLM\VHDSYS | out-null
            Dismount-VHD $testRoot\test.vhdx

            Add-VHDStartupScript $testRoot\test.vhdx {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null

            It "Should set Group Policy"{
                $vol = Mount-VHD "$testRoot\test.vhdx" -Passthru | get-disk | Get-Partition | Get-Volume
                reg load HKLM\VHDSYS "$($vol.DriveLetter):\windows\system32\config\software" | Out-Null
                (Get-ItemProperty -path "HKLM:\VHDSYS\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0\1" -name Script).Script | should be "%SystemDrive%\$TargetScriptDirectory\startup.bat"
            }
            [GC]::Collect()
            reg unload HKLM\VHDSYS | Out-Null
            Dismount-VHD $testRoot\test.vhdx
        }

        Context "When providing a nonexistent vhd path" {

            try {
                Add-VHDStartupScript $testRoot\notest.vhdx {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null
            }
            catch{
                $err = $_
            }

            It "Should throw a validation error"{
                $err.CategoryInfo.Category | should be "InvalidData"
            }
        }

        Context "When providing a nonexistent file to copy" {

            try {
                Add-VHDStartupScript $testRoot\test.vhdx -FilesToCopy "$testRoot\nofile1.ps1","$testRoot\nofile2.ps1" {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null
            }
            catch{
                $err = $_
            }

            It "Should throw a validation error"{
                $err.CategoryInfo.Category | should be "InvalidData"
            }
        }

        Context "When providing a path to a non vhd" {

            try {
                Add-VHDStartupScript $env:SystemRoot {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null
            }
            catch{
                $err = $_
            }

            It "Should throw a validation error"{
                $err.CategoryInfo.Category | should be "InvalidData"
            }
        }

        Context "When the vhd is read only" {
            Set-ItemProperty $testRoot\test.vhdx -name IsReadOnly -Value $true

            try {
                Add-VHDStartupScript $testRoot\test.vhdx {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null
            }
            catch{
                $err = $_
            }
            finally{
                Set-ItemProperty $testRoot\test.vhdx -name IsReadOnly -Value $false
            }

            It "Should throw a InvalidOperation Exception"{
                $err.CategoryInfo.Reason | should be "InvalidOperationException"
            }
        }

        Context "When the vhd is not a system volume" {
            Mount-VHD $testRoot\test.vhdx
            Get-PSDrive | Out-Null
            Remove-Item "$($v.DriveLetter):\Windows" -recurse -Force
            Dismount-VHD $testRoot\test.vhdx

            try {
                Add-VHDStartupScript $testRoot\test.vhdx {
                    function say-hi {"hi"}
                    say-hi
                } | Out-Null
            }
            catch{
                $err = $_
            }
            finally{
                $v = Get-Volume | ? {$_.FileSystemLabel -eq "VHD"}
                Get-PSDrive | Out-Null
                mkdir "$($v.DriveLetter):\Windows\System32\config" | Out-Null
                reg save HKLM\Software "$($v.DriveLetter):\Windows\System32\config\SOFTWARE" /y /c | Out-Null
            }

            It "Should throw a InvalidOperation Exception"{
                $err.CategoryInfo.Reason | should be "InvalidOperationException"
            }
        }        
    }
    finally{
        [GC]::Collect()
        reg unload HKLM\VHDSYS 2>&1 | Out-Null
        if(Test-Path $testRoot\test.vhdx){
            Dismount-VHD $testRoot\test.vhdx -ErrorAction SilentlyContinue
            Remove-Item $testRoot\test.vhdx
        }
        del $env:temp\Boxstarter.tests -recurse -force
    }
}