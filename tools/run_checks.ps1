# Runs every tools/*_check.gd headless and reports which passed.
#
#   powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1
#   powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter boat,furnace
#
# A check fails on a non-zero exit, on any script error or FAILED line in its output, or when it
# runs past -TimeoutSeconds. Checks stop themselves on a failed requirement or after their own
# time limit (tools/check_watchdog.gd); this timeout is the backstop for a check that blocks.
# Many checks boot game.tscn, which loads and autosaves the user:// save, so each check runs with
# its own empty user:// folder: no check sees another's save, and your real saves are never read
# or touched.
#
# Godot is found from -Godot, then $env:GODOT, then the console build on PATH.

param(
	[string[]]$Filter = @(),
	[int]$TimeoutSeconds = 120,
	[string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# Output that marks a failure even when the process exits 0: assert/runtime errors, parse errors,
# and the push_error("FAILED: ...") / "Name: FAIL (n)" lines the expect()-style checks print.
$failurePattern = "SCRIPT ERROR|Parse Error|FAILED|: FAIL\b"

function Resolve-Godot {
	if ($Godot -ne "") { return $Godot }
	if ($env:GODOT) { return $env:GODOT }
	foreach ($name in @("Godot_v4.6.3-stable_win64_console.exe", "godot")) {
		$command = Get-Command $name -ErrorAction SilentlyContinue
		if ($null -ne $command) { return $command.Source }
	}
	$command = Get-Command "Godot*console*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $command) { return $command.Source }
	throw "Godot not found: pass -Godot <path> or set `$env:GODOT."
}

$godotPath = Resolve-Godot

$checks = @(Get-ChildItem (Join-Path $root "tools") -Filter "*_check.gd" | Sort-Object Name)
# Run with -File, "-Filter boat,furnace" arrives as one string.
$Filter = @($Filter | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
if ($Filter.Count -gt 0) {
	$checks = @($checks | Where-Object {
		$name = $_.BaseName
		@($Filter | Where-Object { $name -like "*$_*" }).Count -gt 0
	})
}
if ($checks.Count -eq 0) {
	Write-Host "No checks match: $($Filter -join ', ')"
	exit 1
}

$runDir = Join-Path ([System.IO.Path]::GetTempPath()) ("resource-isles-checks-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $runDir | Out-Null

$failed = @()
$originalAppData = $env:APPDATA
# Tells checks their user:// is a throwaway one, so they may freely write and delete saves there.
$env:RESOURCE_ISLES_ISOLATED_USER_DIR = "1"
try {
	foreach ($check in $checks) {
		$name = $check.BaseName
		# On Windows Godot puts user:// under APPDATA, so a fresh one gives the check its own.
		$env:APPDATA = Join-Path $runDir "appdata\$name"
		New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
		$stdout = Join-Path $runDir "$name.out.log"
		$stderr = Join-Path $runDir "$name.err.log"
		$timer = [System.Diagnostics.Stopwatch]::StartNew()
		$process = Start-Process -FilePath $godotPath -NoNewWindow -PassThru `
			-ArgumentList @("--headless", "--path", "`"$root`"", "--script", "res://tools/$name.gd") `
			-RedirectStandardOutput $stdout -RedirectStandardError $stderr
		# Touching Handle keeps ExitCode readable after exit (a Windows PowerShell quirk).
		$null = $process.Handle

		$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
		if ($timedOut) {
			# The console build launches the editor binary as a child; end the whole tree.
			& taskkill /T /F /PID $process.Id 2>&1 | Out-Null
		}
		$process.WaitForExit()
		$timer.Stop()

		$output = @(Get-Content $stdout, $stderr -ErrorAction SilentlyContinue)
		$errors = @($output | Select-String -Pattern $failurePattern)
		$seconds = "{0:N1}s" -f $timer.Elapsed.TotalSeconds

		$reason = ""
		if ($timedOut) { $reason = "timed out after ${TimeoutSeconds}s" }
		elseif ($process.ExitCode -ne 0) { $reason = "exit code $($process.ExitCode)" }
		elseif ($errors.Count -gt 0) { $reason = "errors in output" }

		if ($reason -eq "") {
			Write-Host ("PASS  {0,-28} {1}" -f $name, $seconds) -ForegroundColor Green
			continue
		}

		$failed += $name
		Write-Host ("FAIL  {0,-28} {1}  ({2})" -f $name, $seconds, $reason) -ForegroundColor Red
		foreach ($line in ($errors | Select-Object -First 10)) {
			Write-Host "      $($line.Line.Trim())"
		}
		Write-Host "      log: $stdout"
	}
} finally {
	$env:APPDATA = $originalAppData
	Remove-Item Env:RESOURCE_ISLES_ISOLATED_USER_DIR -ErrorAction SilentlyContinue
}

Write-Host ""
if ($failed.Count -eq 0) {
	Write-Host "All $($checks.Count) checks passed." -ForegroundColor Green
	exit 0
}
Write-Host "$($failed.Count) of $($checks.Count) checks failed: $($failed -join ', ')" -ForegroundColor Red
exit 1
