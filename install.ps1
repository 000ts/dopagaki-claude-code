# One-shot dopagaki setup for Claude Code on Windows: installs the dopagaki mod and the
# rainbow status line, and points ~/.claude/settings.json at it.
#   irm https://raw.githubusercontent.com/000ts/dopagaki-claude-code/main/install.ps1 | iex
# Runs through iex in the caller's session, so it lives in a script block and fails with
# throw: `exit` would close their PowerShell window.

& {
  # Overridable so the installer can be tried against local copies before a push
  $ModSource = if ($env:MOD_SOURCE) { $env:MOD_SOURCE } else { '000ts/dopagaki-claude-code' }
  $StatuslineRaw = if ($env:STATUSLINE_RAW) { $env:STATUSLINE_RAW } else { 'https://raw.githubusercontent.com/000ts/claude-code-dopagaki-line/main' }

  $ClaudeDir = Join-Path $HOME '.claude'
  $Settings = Join-Path $ClaudeDir 'settings.json'
  $Stamp = Get-Date -Format 'yyyyMMddHHmmss'

  # Animate only on a real console; logs and NO_COLOR get plain lines
  $Fancy = -not $env:NO_COLOR -and -not [Console]::IsOutputRedirected
  $E = [char]27

  # Same hue wheel as the status line: HSV with s=0.75, v=1
  function Hue($h) {
    $h = (($h % 360) + 360) % 360
    $f = $h % 60
    $up = 64 + [math]::Floor(191 * $f / 60)
    $dn = 255 - [math]::Floor(191 * $f / 60)
    $r, $g, $b = switch ([math]::Floor($h / 60)) {
      0 { 255, $up, 64 } 1 { $dn, 255, 64 } 2 { 64, 255, $up }
      3 { 64, $dn, 255 } 4 { $up, 64, 255 } default { 255, 64, $dn }
    }
    "$E[38;2;$r;$g;${b}m"
  }

  if ($Fancy) {
    $Art = @(
      '██████╗  ██████╗ ██████╗  █████╗  ██████╗  █████╗ ██╗  ██╗██╗'
      '██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔══██╗██║ ██╔╝██║'
      '██║  ██║██║   ██║██████╔╝███████║██║  ███╗███████║█████╔╝ ██║'
      '██║  ██║██║   ██║██╔═══╝ ██╔══██║██║   ██║██╔══██║██╔═██╗ ██║'
      '██████╔╝╚██████╔╝██║     ██║  ██║╚██████╔╝██║  ██║██║  ██╗██║'
      '╚═════╝  ╚═════╝ ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝'
    )
    $Tag = 'for Claude Code  ·  maximum dopamine, zero lost information'
    $Width = ($Art | Measure-Object Length -Maximum).Maximum
    $Reveal = 16; $Flow = 24
    [Console]::CursorVisible = $false
    [Console]::Write("`n")
    for ($frame = 0; $frame -lt $Reveal + $Flow; $frame++) {
      $shown = [math]::Floor($Width * ($frame + 1) / $Reveal)
      $sb = [Text.StringBuilder]::new()
      for ($y = 0; $y -lt $Art.Count; $y++) {
        [void]$sb.Append('  ')
        for ($x = 0; $x -lt $Art[$y].Length; $x++) {
          if ($x -lt $shown) { [void]$sb.Append((Hue ($x * 5 + $y * 8 - $frame * 14))).Append($Art[$y][$x]) }
          else { [void]$sb.Append(' ') }
        }
        [void]$sb.Append("$E[0m`n")
      }
      [Console]::Write($sb.ToString())
      Start-Sleep -Milliseconds 40
      if ($frame -lt $Reveal + $Flow - 1) { [Console]::Write("$E[$($Art.Count)A") }
    }
    $line = for ($i = 0; $i -lt $Tag.Length; $i++) { (Hue ($i * 6)) + $Tag[$i] }
    [Console]::Write("`n  $(-join $line)$E[0m`n`n")
    [Console]::CursorVisible = $true
  } else {
    Write-Host '== dopagaki installer =='
  }

  Write-Host '==> Checking tools'
  foreach ($cmd in 'claude', 'git') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "'$cmd' is required but not found" }
  }
  # The Microsoft Store "python" alias resolves but doesn't run Python, so probe by executing.
  # 3.7+ is needed for sys.stdout.reconfigure in the status line.
  $Python = $null
  foreach ($cmd in 'python', 'py', 'python3') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { continue }
    & $cmd -c 'import sys; sys.exit(sys.version_info < (3, 7))' *> $null
    if ($LASTEXITCODE -eq 0) { $Python = $cmd; break }
  }
  if (-not $Python) { throw 'Python 3.7+ is required but not found (https://www.python.org/downloads/)' }
  New-Item -ItemType Directory -Force $ClaudeDir | Out-Null

  Write-Host '==> Installing the dopagaki mod'
  # A mod already loaded from a local folder would run twice if installed again
  if ((Test-Path $Settings) -and (Select-String -Quiet -Path $Settings -Pattern 'CLAUDE_CODE_PLUGIN_DIRS.*dopagaki')) {
    Write-Host 'skipped: already loaded through CLAUDE_CODE_PLUGIN_DIRS'
  } else {
    claude plugin marketplace add $ModSource
    claude plugin marketplace update dopagaki
    claude plugin install dopagaki@dopagaki --scope user
    if ($LASTEXITCODE -ne 0) { throw 'Installing the dopagaki mod failed' }
  }

  Write-Host '==> Downloading the rainbow status line'
  $Script = Join-Path $ClaudeDir 'statusline.py'
  if (Test-Path $Script) { Copy-Item $Script "$Script.$Stamp.bak" }
  Invoke-WebRequest "$StatuslineRaw/statusline.py" -OutFile $Script -UseBasicParsing -ErrorAction Stop
  # Two lines (no cache/cost/today line) unless the person already has a config
  $Config = Join-Path $ClaudeDir 'statusline_config.json'
  if (-not (Test-Path $Config)) {
    [IO.File]::WriteAllText($Config, "{`n  `"show_cache`": false,`n  `"show_cost`": false,`n  `"show_today_total`": false`n}`n")
  }

  Write-Host '==> Wiring up settings.json'
  if (Test-Path $Settings) { Copy-Item $Settings "$Settings.$Stamp.bak" }
  # Fed through stdin: PowerShell 5.1 mangles double quotes in arguments to native commands.
  # The command calls the interpreter by absolute path since Windows ignores the shebang.
  @'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    settings = json.loads(path.read_text(encoding="utf-8-sig"))
except FileNotFoundError:
    settings = {}
script = (Path.home() / ".claude" / "statusline.py").as_posix()
python = Path(sys.executable).as_posix()
settings["statusLine"] = {
    "type": "command",
    "command": f'"{python}" "{script}"',
    "padding": 0,
    "refreshInterval": 1,
}
path.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
'@ | & $Python - $Settings
  if ($LASTEXITCODE -ne 0) { throw 'Updating settings.json failed' }

  $Msg = 'DOPAGAKI MODE: ON'
  if ($Fancy) {
    $line = for ($i = 0; $i -lt $Msg.Length; $i++) { (Hue ($i * 20)) + $Msg[$i] }
    [Console]::Write("`n`n  $E[1m$(-join $line)$E[0m`n`n")
  } else {
    Write-Host "`n$Msg`n"
  }
  Write-Host '  Start a new Claude Code session to see it.'
  Write-Host '  Turn the mod off/on:  /dopagaki off  |  /dopagaki on'
  Write-Host '  Remove the mod:       claude plugin uninstall dopagaki@dopagaki'
  if (Test-Path "$Settings.$Stamp.bak") { Write-Host "  Previous settings:    $Settings.$Stamp.bak" }
  Write-Host ''
}
