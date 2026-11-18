param(
    [string]$Sln = (Join-Path $PSScriptRoot '..\TcProject\HrlRbg.Plc.sln'),   # PLC only, no HMI project
    [switch]$BuildOnly,
    [switch]$ShowErrors,   # UI not suppressed (window stays hidden) so the Error List fills

    [int]$WaitSeconds = 25
)
# Build the TwinCAT solution headlessly (Automation Interface over COM), then
# activate it on the local soft-PLC, let TcUnit run and print the xUnit summary.
# Output lines: BUILD_FAILED_PROJECTS=<n>, TESTS=<n> FAILURES=<n> ERRORS=<n>, FAIL: <suite>.<test>.
$ErrorActionPreference = 'Stop'
$Sln = (Resolve-Path $Sln).Path
$plcproj = Join-Path (Split-Path $Sln) 'HrlRbg\HrlRbgPlc\HrlRbgPlc.plcproj'
if (-not (Select-String -Path $plcproj -Pattern 'XUNITENABLEPUBLISH' -Quiet)) {
    Write-Output 'WARNING: TcUnit xUnitEnablePublish missing in HrlRbgPlc.plcproj (XAE drops it on save) - no result file will be written'
}
$xunitCandidates = @(
    'C:\ProgramData\Beckhoff\TwinCAT\3.1\Boot\tcunit_xunit_testresults.xml',   # 4026
    'C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Boot\tcunit_xunit_testresults.xml',
    'C:\TwinCAT\3.1\Boot\tcunit_xunit_testresults.xml'
)

function Retry([scriptblock]$b) {
    for ($i = 0; $i -lt 90; $i++) {
        try { return & $b } catch {
            if ($_.Exception.Message -match 'RPC_E_CALL_REJECTED|0x80010001|busy|RPC_E_SERVERCALL_RETRYLATER|0x8001010A') { Start-Sleep -Seconds 1 } else { throw }
        }
    }
    throw 'COM call kept being rejected'
}

$before = @(Get-Process TcXaeShell -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$dte = $null
try {
    $dte = New-Object -ComObject TcXaeShell.DTE.17.0
    Retry { $dte.SuppressUI = -not $ShowErrors } | Out-Null
    Retry { $dte.MainWindow.Visible = [bool]$ShowErrors } | Out-Null
    Retry { $dte.Solution.Open($Sln) } | Out-Null
    Start-Sleep -Seconds 8
    if ($ShowErrors) { try { Retry { $dte.ExecuteCommand('View.ErrorList') } | Out-Null } catch { } }
    # Default solution is HrlRbg.Plc.sln (TwinCAT project only): opening the HMI
    # project headless blocks on NuGet / engineering-server dialogs.
    Retry { $dte.Solution.SolutionBuild.Build($true) } | Out-Null
    if ($ShowErrors) { Start-Sleep -Seconds 5 }
    $failed = Retry { $dte.Solution.SolutionBuild.LastBuildInfo }
    Write-Output "BUILD_FAILED_PROJECTS=$failed"
    if ($ShowErrors) {
        try {
            $items = Retry { $dte.ToolWindows.ErrorList.ErrorItems }
            Write-Output "ERROR_ITEMS=$($items.Count)"
            for ($i = 1; $i -le [Math]::Min($items.Count, 25); $i++) {
                $it = $items.Item($i)
                Write-Output ("ITEM[" + $it.ErrorLevel + "]: " + $it.Description + " | " + [IO.Path]::GetFileName($it.FileName) + ":" + $it.Line)
            }
        } catch { Write-Output "ERRORLIST_UNAVAILABLE: $($_.Exception.Message)" }
        try {
            $panes = Retry { $dte.ToolWindows.OutputWindow.OutputWindowPanes }
            for ($p = 1; $p -le $panes.Count; $p++) {
                $pane = $panes.Item($p)
                $doc = $pane.TextDocument
                $ep = $doc.StartPoint.CreateEditPoint()
                $text = $ep.GetText($doc.EndPoint)
                $lines = $text -split "`r?`n"
                Write-Output "PANE '$($pane.Name)' lines=$($lines.Count)"
                $lines | Where-Object { $_ -match 'error|Error|C0\d{3}' } | Select-Object -First 30 | ForEach-Object { "OUT: $_" }
            }
        } catch { Write-Output "OUTPUT_UNAVAILABLE: $($_.Exception.Message)" }
    }
    if ($failed -ne 0 -or $BuildOnly) { return }

    foreach ($f in $xunitCandidates) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    $sysMan = Retry { $dte.Solution.Projects.Item(1).Object }   # HrlRbg.Plc.sln holds only the tsproj
    Retry { $sysMan.ActivateConfiguration() } | Out-Null
    Retry { $sysMan.StartRestartTwinCAT() } | Out-Null
    $started = $false
    for ($t = 0; $t -lt 30 -and -not $started; $t++) {
        Start-Sleep -Seconds 1
        try { $started = [bool]($sysMan.IsTwinCATStarted()) } catch { }
    }
    Write-Output "TWINCAT_STARTED=$started"

    $xml = $null
    for ($t = 0; $t -lt $WaitSeconds -and -not $xml; $t++) {
        Start-Sleep -Seconds 1
        $xml = $xunitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $xml) { Write-Output 'TESTS=? (no xUnit file - runtime not started or licence expired)'; return }
    Start-Sleep -Seconds 2
    [xml]$r = Get-Content $xml -Raw
    $suites = $r.testsuites
    Write-Output ("TESTS={0} FAILURES={1} ERRORS={2}" -f $suites.tests, $suites.failures, $suites.errors)
    foreach ($s in $r.testsuites.testsuite) {
        foreach ($c in $s.testcase) {
            if ($c.failure) { Write-Output ("FAIL: {0}.{1} - {2}" -f $s.name, $c.name, $c.failure.message) }
        }
    }
} finally {
    if ($dte) { try { Retry { $dte.Solution.Close($false) } | Out-Null } catch { } ; try { $dte.Quit() } catch { } }
    Start-Sleep -Seconds 3
    Get-Process TcXaeShell -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id } | Stop-Process -Force -ErrorAction SilentlyContinue
}
