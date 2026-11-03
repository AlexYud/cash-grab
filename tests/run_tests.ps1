<#
.SYNOPSIS
  Launches real, separate game instances on localhost (one host + N clients), each driven by a scripted bot,
  and reports the [TEST] lines they print. Nothing needs a window: instances run with --headless.

.EXAMPLE
  $env:GODOT_BIN = "C:\path\to\Godot_v4.7-stable_win64_console.exe"   # the *_console.exe next to the main exe
  .\tests\run_tests.ps1 -Test m0
  .\tests\run_tests.ps1 -Test all

.NOTES
  Tests (bots live in tests/bots/):
    m0   two players: movement sync, shove launch, grab pull/release
    m1   gunplay: pistol kills, kill confirm, friendly-fire shotgun knockback, reload, zombie bites, regen
    m2   barricades: zombies break boards and enter, repair prompt, holding E rebuilds
    m3a  downed: crawl, pistol-only, revive, drag, bleed-out, wave-clear restore
    m3b  ragdolls (shove + capped deaths), barrel explosion, game over + restart
    m4a  late join mid-run + a player leaving while grabbing someone
    m4b  proximity voice pipeline (test tone, distance culling)
    m4c  a fifth player is turned away from a full game
    m5   special zombies, trips, snacks, hugger
    m6   carry + throw, Yank/Disco guns, leaper, bloater
    m7   shared cash, headshots, ADS, invisible walls, shops, two-lever annex door, mystery box, Tesla/Boing, stumble
    m8   rigged zombies: feet planted, poses per state, ragdoll on trip / blast / death, tether, get-up, domino, corpses
    nav  navmesh reaches every window and shop spot (single process)
    soak2 / soak4  whole five-wave runs with 2 / 4 scripted players at 3x speed (god mode, so bots always finish)
#>
param(
	[string]$Test = "m0",
	[string]$Godot = $env:GODOT_BIN,
	[string]$Project = (Resolve-Path "$PSScriptRoot\..").Path,
	[string]$LogDir = (Join-Path ([System.IO.Path]::GetTempPath()) "cashgrab-tests"),
	[int]$Timeout = 180
)

# Host = host bot. Clients = bot name, or @{ Bot; Delay (s before launching); Args }.
# Extra = args for everyone, HostExtra/ClientExtra = per role. Limit = in-game --quit-after (s).
$Tests = [ordered]@{
	"m0"  = @{ Host = "m0_host"; Clients = @("m0_client"); Limit = 60 }
	"m1"  = @{ Host = "m1_host"; Clients = @("m1_client"); Limit = 120; Extra = @("--hold-waves") }
	"m2"  = @{ Host = "m2_host"; Clients = @("m2_client"); Limit = 150; Extra = @("--hold-waves") }
	"m3a" = @{ Host = "m3a_host"; Clients = @("m3a_client"); Limit = 150; Extra = @("--hold-waves", "--bleed-time=12") }
	"m3b" = @{ Host = "m3b_host"; Clients = @("m3b_client"); Limit = 150; Extra = @("--hold-waves") }
	"m4a" = @{ Host = "m4a_host"; Clients = @("m4a_leaver", @{ Bot = "m4a_late"; Delay = 14 }); Autostart = 2; Limit = 120; Extra = @("--hold-waves") }
	"m4b" = @{ Host = "m4b_host"; Clients = @("m4b_listener"); Limit = 90; Extra = @("--hold-waves"); HostExtra = @("--voice-test-tone") }
	"m5"  = @{ Host = "m5_host"; Clients = @("m5_client"); Limit = 150; Extra = @("--hold-waves") }
	"m6"  = @{ Host = "m6_host"; Clients = @("m6_client"); Limit = 180; Extra = @("--hold-waves") }
	"m7"  = @{ Host = "m7_host"; Clients = @("m7_client"); Limit = 240; Extra = @("--hold-waves"); Plain = $true }
	"m8"  = @{ Host = "m8_host"; Clients = @("m8_client"); Limit = 120; Extra = @("--hold-waves") }
	"nav" = @{ Host = "nav_check"; Clients = @(); Limit = 40; Extra = @("--hold-waves") }
	"m4d" = @{ Host = "m4d_host"; Clients = @("m4d_client"); Limit = 90; Extra = @("--hold-waves") }
	"m4c" = @{ Host = "m4c_host"; Clients = @("m4c_filler", "m4c_filler", "m4c_filler", @{ Bot = ""; Delay = 8; Args = @("--expect-join-fail") }); Autostart = 4; Limit = 120; Extra = @("--hold-waves") }
	# whole 5-wave runs with scripted players (3x game speed); passing means VICTORY with no script errors
	"soak2" = @{ Host = "soak"; Clients = @("soak"); Limit = 2800; Extra = @("--time-scale=3", "--god") }
	"soak4" = @{ Host = "soak"; Clients = @("soak", "soak", "soak"); Limit = 2800; Extra = @("--time-scale=3", "--god") }
	# informational, not part of `all`: the same bots without god mode. It is a difficulty probe, so it may fail.
	"hard2" = @{ Host = "soak"; Clients = @("soak"); Limit = 2800; Extra = @("--time-scale=3"); Informational = $true }
	"hard4" = @{ Host = "soak"; Clients = @("soak", "soak", "soak"); Limit = 2800; Extra = @("--time-scale=3"); Informational = $true }
}

function Get-FreeUdpPort {
	# ENet needs a free UDP port; a random one can collide with another program, so probe before using it
	for ($i = 0; $i -lt 50; $i++) {
		$p = Get-Random -Minimum 30000 -Maximum 60000
		try { $u = New-Object System.Net.Sockets.UdpClient($p); $u.Close(); return $p } catch { }
	}
	throw "could not find a free UDP port"
}

if (-not $Godot -or -not (Test-Path $Godot)) { throw "Set -Godot or `$env:GODOT_BIN to a Godot 4.7 *console* executable." }
New-Item -ItemType Directory -Force $LogDir | Out-Null
$names = if ($Test -eq "all") { @($Tests.Keys | Where-Object { -not $Tests[$_].Informational }) } else { @($Test) }
$overall = 0

foreach ($name in $names) {
	if (-not $Tests.Contains($name)) { throw "Unknown test '$name'. Known: $($Tests.Keys -join ', ')" }
	$t = $Tests[$name]
	$port = Get-FreeUdpPort
	$extra = @(); if ($t.Extra) { $extra = $t.Extra }
	if (-not $t.Plain) { $extra += "--all-weapons" } # tests of the weapon-shop rules set Plain = $true
	$hostExtra = @(); if ($t.HostExtra) { $hostExtra = $t.HostExtra }
	$clientExtra = @(); if ($t.ClientExtra) { $clientExtra = $t.ClientExtra }
	$autostart = if ($t.Autostart) { $t.Autostart } else { 1 + $t.Clients.Count }

	$specs = @(@{ Role = "host"; Delay = 0; Args = @("--host=$port", "--bind=127.0.0.1", "--name=Host", "--autostart=$autostart", "--bot=$($t.Host)", "--quit-after=$($t.Limit)") + $extra + $hostExtra })
	$i = 0
	foreach ($c in $t.Clients) {
		$i++
		if ($c -is [string]) { $c = @{ Bot = $c } }
		$a = @("--join=127.0.0.1:$port", "--name=Client$i", "--quit-after=$($t.Limit)") + $extra + $clientExtra
		if ($c.Bot) { $a += "--bot=$($c.Bot)" }
		if ($c.Args) { $a += $c.Args }
		$delay = 0; if ($c.Delay) { $delay = $c.Delay }
		$specs += @{ Role = "client$i"; Delay = $delay; Args = $a }
	}
	Write-Host "=== $name (port $port, $($specs.Count) processes) ===" -ForegroundColor Cyan

	$procs = @()
	$t0 = Get-Date
	foreach ($s in $specs) {
		$wait = $s.Delay - ((Get-Date) - $t0).TotalSeconds
		if ($wait -gt 0) { Start-Sleep -Seconds ([Math]::Ceiling($wait)) }
		$log = Join-Path $LogDir "$name-$($s.Role).log"
		$err = Join-Path $LogDir "$name-$($s.Role).err.log"
		$argList = @("--headless", "--path", "`"$Project`"", "--") + $s.Args
		$p = Start-Process -FilePath $Godot -ArgumentList $argList -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError $err
		$null = $p.Handle # caches the handle; without it ExitCode comes back empty in Windows PowerShell
		$procs += @{ Role = $s.Role; Proc = $p; Log = $log; Err = $err }
		if ($s.Role -eq "host") { Start-Sleep -Seconds 2 } # give the host time to listen
	}
	$deadline = (Get-Date).AddSeconds($Timeout)
	foreach ($p in $procs) {
		$left = [int][Math]::Max(1, ($deadline - (Get-Date)).TotalSeconds)
		if (-not $p.Proc.WaitForExit($left * 1000)) { $p.Proc.Kill(); Write-Host "  $($p.Role): killed after timeout" -ForegroundColor Red; $overall = 1 }
		$p.Proc.WaitForExit() # parameterless call is what makes ExitCode available in Windows PowerShell
	}
	foreach ($p in $procs) {
		$lines = @(Get-Content $p.Log -ErrorAction SilentlyContinue) + @(Get-Content $p.Err -ErrorAction SilentlyContinue)
		$results = $lines | Where-Object { $_ -match "^\[TEST\]" }
		# "Unable to send packet on channel 0, max channels: 0" is the engine logging a sync packet aimed at a peer that is
		# mid-disconnect (several clients quitting at once). Harmless, so it is not counted as a failure.
		$bad = $lines | Where-Object { $_ -match "SCRIPT ERROR|^ERROR:|Parse Error|Invalid (call|access)|Node not found|Cannot (call|get)" -and $_ -notmatch "max channels: 0" }
		foreach ($l in $results) {
			$color = if ($l -match "PASS") { "Green" } else { "Red" }
			Write-Host "  [$($p.Role)] $l" -ForegroundColor $color
		}
		foreach ($l in ($bad | Select-Object -First 6)) { Write-Host "  [$($p.Role)] $l" -ForegroundColor Yellow }
		$code = $p.Proc.ExitCode
		if ($code -ne 0 -or $bad) { $overall = 1 }
		if (-not $results) { Write-Host "  [$($p.Role)] no test results (see $($p.Log))" -ForegroundColor Red; $overall = 1 }
		Write-Host "  [$($p.Role)] exit=$code  log=$($p.Log)" -ForegroundColor DarkGray
	}
}
if ($overall -eq 0) { Write-Host "ALL PASSED" -ForegroundColor Green } else { Write-Host "FAILURES - see above" -ForegroundColor Red }
exit $overall
