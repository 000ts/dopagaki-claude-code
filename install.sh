#!/usr/bin/env bash
# One-shot dopagaki setup for Claude Code: installs the dopagaki mod and the
# rainbow status line, and points ~/.claude/settings.json at it.
#   curl -fsSL https://raw.githubusercontent.com/000ts/dopagaki-claude-code/main/install.sh | bash
set -euo pipefail

# Overridable so the installer can be tried against local copies before a push
MOD_SOURCE="${MOD_SOURCE:-000ts/dopagaki-claude-code}"
STATUSLINE_RAW="${STATUSLINE_RAW:-https://raw.githubusercontent.com/000ts/claude-code-dopagaki-line/main}"

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP="$(date +%Y%m%d%H%M%S)"
LOG="$(mktemp -t dopagaki-install.XXXXXX)"

# Animate only on a real color terminal; logs and NO_COLOR get plain lines
FANCY=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  FANCY=1
fi
case "${COLORTERM:-}" in truecolor|24bit) TRUECOLOR=1 ;; *) TRUECOLOR=0 ;; esac
export TRUECOLOR

RESET=$'\033[0m'
ARC=('◜' '◠' '◝' '◞' '◡' '◟')

# Same hue wheel as the status line: HSV with s=0.75, v=1
hue_color() {
  local h=$(( ($1 % 360 + 360) % 360 ))
  local f=$(( h % 60 )) r g b
  local up=$(( 64 + 191 * f / 60 )) dn=$(( 255 - 191 * f / 60 ))
  case $(( h / 60 )) in
    0) r=255 g=$up b=64 ;; 1) r=$dn g=255 b=64 ;; 2) r=64 g=255 b=$up ;;
    3) r=64 g=$dn b=255 ;; 4) r=$up g=64 b=255 ;; *) r=255 g=64 b=$dn ;;
  esac
  if [ "$TRUECOLOR" = 1 ]; then
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
  else
    printf '\033[38;5;%dm' $(( 16 + 36 * ((r * 5 + 127) / 255) + 6 * ((g * 5 + 127) / 255) + (b * 5 + 127) / 255 ))
  fi
}

restore_cursor() { [ "$FANCY" = 1 ] && printf '\033[?25h'; rm -f "$LOG"; }
trap restore_cursor EXIT
trap 'exit 130' INT

# Python draws the art: it walks multi-byte box characters reliably
banner() {
  if [ "$FANCY" = 0 ] || ! command -v python3 >/dev/null; then echo "== dopagaki installer =="; return; fi
  python3 - <<'EOF'
import colorsys, os, sys, time
ART = [
    "██████╗  ██████╗ ██████╗  █████╗  ██████╗  █████╗ ██╗  ██╗██╗",
    "██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔══██╗██║ ██╔╝██║",
    "██║  ██║██║   ██║██████╔╝███████║██║  ███╗███████║█████╔╝ ██║",
    "██║  ██║██║   ██║██╔═══╝ ██╔══██║██║   ██║██╔══██║██╔═██╗ ██║",
    "██████╔╝╚██████╔╝██║     ██║  ██║╚██████╔╝██║  ██║██║  ██╗██║",
    "╚═════╝  ╚═════╝ ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝",
]
TAG = "for Claude Code  ·  maximum dopamine, zero lost information"
truecolor = os.environ.get("TRUECOLOR") == "1"

def fg(hue):
    r, g, b = (round(c * 255) for c in colorsys.hsv_to_rgb((hue % 360) / 360, 0.75, 1.0))
    if truecolor:
        return f"\033[38;2;{r};{g};{b}m"
    return f"\033[38;5;{16 + 36 * round(r / 51) + 6 * round(g / 51) + round(b / 51)}m"

width = max(len(line) for line in ART)
out = sys.stdout
out.write("\033[?25l\n")
REVEAL, FLOW = 16, 24
for frame in range(REVEAL + FLOW):
    shown = width * (frame + 1) // REVEAL
    rows = []
    for y, line in enumerate(ART):
        cells = [fg(x * 5 + y * 8 - frame * 14) + ch if x < shown else " " for x, ch in enumerate(line)]
        rows.append("  " + "".join(cells) + "\033[0m")
    out.write("\n".join(rows) + "\n")
    out.flush()
    time.sleep(0.04)
    if frame < REVEAL + FLOW - 1:
        out.write(f"\033[{len(ART)}A")
out.write("\n  " + "".join(fg(i * 6) + ch for i, ch in enumerate(TAG)) + "\033[0m\n\n")
EOF
}

TOTAL_STEPS=4
DONE_STEPS=0

progress() {
  [ "$FANCY" = 1 ] || return 0
  local width=40 filled i out=""
  filled=$(( width * DONE_STEPS / TOTAL_STEPS ))
  for (( i = 0; i < width; i++ )); do
    if [ "$i" -lt "$filled" ]; then out+="$(hue_color $(( i * 9 )))█"; else out+=$'\033[90m░'; fi
  done
  printf '  %s%s %d/%d' "$out" "$RESET" "$DONE_STEPS" "$TOTAL_STEPS"
}

# step "label" command...: runs the command with a spinner; on failure shows its output and stops
step() {
  local label=$1; shift
  if [ "$FANCY" = 0 ]; then
    echo "==> $label"
    "$@" </dev/null >>"$LOG" 2>&1 || { cat "$LOG" >&2; exit 1; }
    DONE_STEPS=$(( DONE_STEPS + 1 ))
    return
  fi
  "$@" </dev/null >>"$LOG" 2>&1 &
  local pid=$! frame=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[2K  %s%s%s %s' "$(hue_color $(( frame * 8 )))" "${ARC[frame % 6]}" "$RESET" "$label"
    printf '\n\033[2K'; progress; printf '\033[1A'
    frame=$(( frame + 1 ))
    sleep 0.1
  done
  if wait "$pid"; then
    DONE_STEPS=$(( DONE_STEPS + 1 ))
    printf '\r\033[2K  %s✔%s %s\n\033[2K' "$(hue_color $(( DONE_STEPS * 70 )))" "$RESET" "$label"
    progress; printf '\r'
  else
    printf '\r\033[2K  \033[31m✘\033[0m %s\n\033[2K\n' "$label"
    cat "$LOG" >&2
    exit 1
  fi
}

check_tools() {
  for cmd in claude python3 curl; do
    command -v "$cmd" >/dev/null || { echo "'$cmd' is required but not found"; return 1; }
  done
  mkdir -p "$CLAUDE_DIR"
}

# A mod already loaded from a local folder would run twice if installed again
mod_loaded_from_folder() {
  python3 - "$SETTINGS" <<'EOF'
import json, sys
try:
    dirs = json.load(open(sys.argv[1])).get("env", {}).get("CLAUDE_CODE_PLUGIN_DIRS", "")
except (FileNotFoundError, ValueError):
    dirs = ""
sys.exit(0 if "dopagaki" in dirs else 1)
EOF
}

install_mod() {
  if mod_loaded_from_folder; then
    echo "skipped: already loaded through CLAUDE_CODE_PLUGIN_DIRS"
    return
  fi
  claude plugin marketplace add "$MOD_SOURCE" || true
  claude plugin marketplace update dopagaki || true
  claude plugin install dopagaki@dopagaki --scope user
}

install_statusline() {
  if [ -f "$CLAUDE_DIR/statusline.py" ]; then
    cp "$CLAUDE_DIR/statusline.py" "$CLAUDE_DIR/statusline.py.$STAMP.bak"
  fi
  curl -fsSL "$STATUSLINE_RAW/statusline.py" -o "$CLAUDE_DIR/statusline.py"
  chmod +x "$CLAUDE_DIR/statusline.py"
  # Two lines (no cache/cost/today line) unless the person already has a config
  if [ ! -f "$CLAUDE_DIR/statusline_config.json" ]; then
    printf '{\n  "show_cache": false,\n  "show_cost": false,\n  "show_today_total": false\n}\n' \
      > "$CLAUDE_DIR/statusline_config.json"
  fi
}

wire_settings() {
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.$STAMP.bak"
  fi
  python3 - "$SETTINGS" <<'EOF'
import json, sys
path = sys.argv[1]
try:
    settings = json.load(open(path))
except FileNotFoundError:
    settings = {}
settings["statusLine"] = {
    "type": "command",
    "command": "~/.claude/statusline.py",
    "padding": 0,
    "refreshInterval": 1,
}
with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF
}

finale() {
  local msg="DOPAGAKI MODE: ON" i out=""
  if [ "$FANCY" = 1 ]; then
    printf '\n\n'
    for (( i = 0; i < ${#msg}; i++ )); do out+="$(hue_color $(( i * 20 )))${msg:i:1}"; done
    printf '  \033[1m%s%s\n\n' "$out" "$RESET"
  else
    printf '\n%s\n\n' "$msg"
  fi
  echo "  Start a new Claude Code session to see it."
  echo "  Turn the mod off/on:  /dopagaki off  |  /dopagaki on"
  echo "  Remove the mod:       claude plugin uninstall dopagaki@dopagaki"
  if [ -f "$SETTINGS.$STAMP.bak" ]; then
    echo "  Previous settings:    $SETTINGS.$STAMP.bak"
  fi
  echo ""
}

banner
step "Checking tools" check_tools
step "Installing the dopagaki mod" install_mod
step "Downloading the rainbow status line" install_statusline
step "Wiring up settings.json" wire_settings
finale
