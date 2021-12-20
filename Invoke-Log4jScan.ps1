function Invoke-Log4jScan {
    <#
    .SYNOPSIS
        Scans disk for trace of log4j
    .DESCRIPTION
        Recursively scans disks for filenames matching log4j or jar files containing log4j.
        If match if found a PSCustomObject is created
        [PSCustomObject]@{
            File      = <Name of file>
            Path      = <Full path of file>
            Attribute = <If it's file or content of jar>
            Line      = <Which line in jar file contains log4j>
            Value     = <Value of line in jar file>
        }
        And saved to List<T> which is returned at end of runtime
    .EXAMPLE
        $log = Invoke-Log4jScan -Drives ([System.IO.Directory]::GetLogicalDrives())
        Goes through all logical drives and outputs result to $log variable

        $log = Invoke-Log4jScan -Drives 'C:\'
        Goes through C: drive and outputs result to $log variable
    .INPUTS
        Drives [string[]]
    .OUTPUTS
        [System.Collections.Generic.List[PSCustomObject]]
    #>
    [CmdletBinding(PositionalBinding = $true)]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0,
            HelpMessage = 'Enter which disk/s to search in format of "C:\", "D:\"'
        )]
        [ValidateNotNull()]
        [string[]]
        $Drives
    )
    
    begin {
        [System.Collections.Hashtable]$Parameters = @{}
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool = [RunspaceFactory]::CreateRunspacePool(
            [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        )
        [void]$RunspacePool.SetMaxRunspaces(([System.Environment]::ProcessorCount * 2))
        $RunspacePool.Open()
        [System.Collections.ArrayList]$jobs = [System.Collections.ArrayList]::new()
        [System.Collections.Generic.List[PSCustomObject]]$Log4jList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    
    process {
        $Drives.ForEach({
                $Parameters.Pipeline = $_
                [PowerShell]$PowerShell = [PowerShell]::Create()
                $PowerShell.RunspacePool = $RunspacePool

                [void]$PowerShell.AddScript({
                        Param (
                            $Pipeline
                        )

                        [string]$drive = $Pipeline

                        [System.IO.EnumerationOptions]$enumOption = [System.IO.EnumerationOptions]::new()
                        $enumOption.IgnoreInaccessible = $true
                        $enumOption.MatchCasing = [System.IO.MatchCasing]::CaseInsensitive
                        $enumOption.MatchType = [System.IO.MatchType]::Simple
                        $enumOption.RecurseSubdirectories = -1
                        $enumOption.RecurseSubdirectories = $true
                        $enumOption.ReturnSpecialDirectories = $false
                    
                        [System.IO.Enumeration.FileSystemEnumerable[string]]$jarFiles = [System.IO.Directory]::EnumerateFiles($drive, '*.jar', $enumOption)
                        [System.IO.Enumeration.FileSystemEnumerable[string]]$log4jFiles = [System.IO.Directory]::EnumerateFiles($drive, '*log4j*', $enumOption)
                    
                        $log4jFiles.ForEach({
                                [PSCustomObject]@{
                                    File      = [System.IO.Path]::GetFileName($_)
                                    Path      = [string]$_
                                    Attribute = [string]'File'
                                    Line      = [int]$null
                                    Value     = [string]$null
                                }
                            })
                    
                        $jarFiles.ForEach({
                                if ([System.IO.File]::ReadAllText($_).Contains('log4j')) {
                                    [string]$log4jFilePath = $_
                                    [string[]]$log4jFileLines = [System.IO.File]::ReadAllLines($log4jFilePath, [System.Text.Encoding]::UTF8)
                    
                                    for ($i = 0; $i -lt $log4jFileLines.Count; $i++) {
                                        if ($log4jFileLines[$i].Contains('log4j')) {
                                            [PSCustomObject]@{
                                                File      = [System.IO.Path]::GetFileName($log4jFilePath)
                                                Path      = [string]$log4jFilePath
                                                Attribute = [string]'Jar'
                                                Line      = [int]$i
                                                Value     = [string]$log4jFileLines[$i]
                                            }
                                        }
                                    }
                                }
                            })
                    }, $True) #Setting UseLocalScope to $True fixes scope creep with variables in RunspacePool

                [void]$PowerShell.AddParameters($Parameters)
                [void]$jobs.Add((
                        [pscustomobject]@{
                            PowerShell = $PowerShell
                            Handle     = $PowerShell.BeginInvoke()
                        }
                    ))
            })
    }
    
    end {
        While ($jobs.handle.IsCompleted -eq $False) {
            [System.Threading.Thread]::Sleep(100)
        }
        
        $return = $jobs.ForEach({
                $_.powershell.EndInvoke($_.handle)
                $_.PowerShell.Dispose()
            })

        $return.ForEach({
                $Log4jList.Add($_)
            })

        $jobs.clear()
        $RunspacePool.Close()
        $RunspacePool.Dispose()
        return $Log4jList
    }
}
