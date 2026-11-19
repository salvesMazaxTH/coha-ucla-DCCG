# Sobe a versão do jogo em um (0.6 -> 0.7) e grava data/build_info.json para o menu mostrar.
# O Android só instala por cima se version/code crescer; version/name e config/version acompanham: code 7 = 0.7.
$presets = 'export_presets.cfg'
$project = 'project.godot'

$presetsText = [IO.File]::ReadAllText($presets)
$newCode = [int]([regex]::Match($presetsText, 'version/code=(\d+)').Groups[1].Value) + 1
$newVersion = "0.$newCode"

$presetsText = [regex]::Replace($presetsText, 'version/code=\d+', "version/code=$newCode")
$presetsText = [regex]::Replace($presetsText, 'version/name="[^"]*"', "version/name=""$newVersion""")
[IO.File]::WriteAllText($presets, $presetsText)

$projectText = [IO.File]::ReadAllText($project)
$projectText = [regex]::Replace($projectText, 'config/version="[^"]*"', "config/version=""$newVersion""")
[IO.File]::WriteAllText($project, $projectText)

$commit = (git rev-parse --short HEAD).Trim()
if ((git status --porcelain) -ne $null) { $commit = "$commit*" }
$builtAt = Get-Date -Format 'dd/MM HH:mm'
$info = "{`"version`": `"$newVersion`", `"built_at`": `"$builtAt`", `"commit`": `"$commit`"}"
[IO.File]::WriteAllText('data/build_info.json', $info)

Write-Output "Versao $newVersion ($builtAt, $commit)"
