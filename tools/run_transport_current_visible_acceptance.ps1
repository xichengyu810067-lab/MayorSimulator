#requires -Version 7.4
[CmdletBinding()] param([Parameter(Mandatory)][string]$GodotExe,[Parameter(Mandatory)][string]$OutputRoot,[int]$TimeoutSeconds=300)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path; $OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path $OutputRoot){throw 'OutputRoot already exists'}; New-Item -ItemType Directory $OutputRoot|Out-Null
$env:APPDATA=Join-Path $OutputRoot 'appdata';$env:LOCALAPPDATA=Join-Path $OutputRoot 'localappdata';New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA|Out-Null
$commit=(git -c safe.directory=$root -C $root rev-parse HEAD).Trim();$env:MAYOR_ACCEPTANCE_COMMIT=$commit
$out=Join-Path $OutputRoot 'stdout.log';$err=Join-Path $OutputRoot 'stderr.log';$log=Join-Path $OutputRoot 'godot.log'
$p=Start-Process -FilePath $GodotExe -ArgumentList @('--path',$root,'--script','res://tests/manual/transport_current_visible_acceptance.gd','--log-file',$log,'--',"--transport-current-output-dir=$OutputRoot") -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
if(-not $p.WaitForExit($TimeoutSeconds*1000)){Stop-Process -Id $p.Id -Force;throw 'Godot timeout'};if($p.ExitCode-ne 0){throw "Godot exit=$($p.ExitCode)"}
$stdoutText=Get-Content -Raw $out;$text=$stdoutText,(Get-Content -Raw $err),(Get-Content -Raw $log) -join "`n";if($text-match '(?m)^(?:SCRIPT ERROR|ERROR|WARNING):|Leaked instance:|ObjectDB instances? .* leaked'){throw 'product diagnostics found'};if(([regex]::Matches($stdoutText,'TRANSPORT_CURRENT_NATIVE_VISIBLE_ACCEPTANCE_PASSED')).Count-ne 1){throw 'success marker missing'}
$r=Get-Content -Raw (Join-Path $OutputRoot 'transport-current-result.json')|ConvertFrom-Json;if($r.status-ne 'PASS' -or $r.commit-ne $commit -or $r.captures.Count-ne 4){throw 'result incomplete or commit mismatch'}
if((@($r.actor_kinds)|Sort-Object) -join ',' -ne 'bus,car,metro_train,motorcycle,plane,train'){throw 'actor kinds are not exact'};$i=$r.crossing_interlock;if(-not $i.car_stop_anchor -or -not $i.motorcycle_stop_anchor -or $i.car_frozen_frames -lt 10 -or $i.motorcycle_frozen_frames -lt 10 -or -not $i.car_resumed -or -not $i.motorcycle_resumed){throw 'crossing stop/resume evidence incomplete'}
foreach($c in $r.captures){$f=Join-Path $OutputRoot $c.filename;if(-not(Test-Path $f)){throw "missing $($c.filename)"};$h=(Get-FileHash $f -Algorithm SHA256).Hash.ToLower();if($h-ne $c.sha256){throw "hash mismatch $($c.filename)"}}
$summary=[ordered]@{schema_version=1;suite=$r.suite;status='PASS';commit=$commit;process=@{exit_code=$p.ExitCode;cleanup_confirmed=$true};result=$r};$summary|ConvertTo-Json -Depth 20|Set-Content -NoNewline (Join-Path $OutputRoot 'summary.json');Write-Output "Transport current visible acceptance passed: output=$OutputRoot"
