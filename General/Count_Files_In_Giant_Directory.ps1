# Small script to parse "giant" directories with numerous subdirectories

$jobs = @();
$dir_todo = "\\path\to\directory"
$max_running_jobs = 20
gci $dir_todo -Directory | %{
    while (($jobs | where State -eq Running).Count -gt $max_running_job) { Sleep -Seconds 1 }
    $jobs+= start-job -ScriptBlock {(gci $args[0] -File -Recurse).count} -ArgumentList $($_.FullName)
}

$result = $jobs | Wait-Job | Receive-Job
$stats = $result | Measure-Object -Sum
Write-Host "FileCount: $($stats.Sum)"
Write-Host "JobCount: $($stats.Count)"
