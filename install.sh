#!/usr/bin/env bash
# =============================================================================
# ROS 2 Jazzy on Arduino UNO Q — one-command installer
#
# Automates https://docs.arduino.cc/tutorials/uno-q/ros2-setup/ up to (but not
# including) the talker / listener test.
#
# Usage (on the UNO Q):
#   curl -fsSL https://raw.githubusercontent.com/salmanfarisvp/unoq-ros2/main/install.sh | bash
#
# Options (environment variables):
#   SKIP_UPGRADE=1        skip "apt upgrade" (still runs "apt update")
#   MOVE_DOCKER_DATA=0    keep Docker's data on the root partition
#   DOCKER_DATA_DIR=...   where to move Docker's data (default: $HOME/docker-data)
#   ROS2_DIR=...          project folder (default: $HOME/ros2)
#   SKIP_DISPLAY=1        skip the monitor display / xhost setup
#   SKIP_WEB_DISPLAY=1    skip the browser display (noVNC on port 6080)
#
# Safe to re-run: every step checks whether it is already done.
# =============================================================================

set -euo pipefail

# ---- settings ---------------------------------------------------------------
ROS_IMAGE="ros:jazzy-ros-base"
WORKSHOP_REPO="https://github.com/arduino/workshop_robotics_unoq.git"
WORKSHOP_DIR="${WORKSHOP_DIR:-$HOME/workshop_robotics_unoq}"
ROS2_DIR="${ROS2_DIR:-$HOME/ros2}"
DOCKER_DATA_DIR="${DOCKER_DATA_DIR:-$HOME/docker-data}"
SKIP_UPGRADE="${SKIP_UPGRADE:-0}"
MOVE_DOCKER_DATA="${MOVE_DOCKER_DATA:-1}"
SKIP_DISPLAY="${SKIP_DISPLAY:-0}"
SKIP_WEB_DISPLAY="${SKIP_WEB_DISPLAY:-0}"
WEB_PORT="${WEB_PORT:-6080}"

# ---- output helpers ---------------------------------------------------------
if [ -t 1 ]; then
  C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_C=$'\e[36m'; C_0=$'\e[0m'
else
  C_B=; C_G=; C_Y=; C_R=; C_C=; C_0=
fi
STEP=0
step() { STEP=$((STEP + 1)); printf '\n%s==> [%d] %s%s\n' "$C_B$C_C" "$STEP" "$*" "$C_0"; }
ok()   { printf '%s  ✔ %s%s\n' "$C_G" "$*" "$C_0"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$C_Y" "$*" "$C_0"; }
die()  { printf '%s  ✘ %s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }

# =============================================================================
# Steps
# =============================================================================

preflight() {
  step "Pre-flight checks"
  [ "$(id -u)" -ne 0 ] || die "Run as the normal user (e.g. arduino), not root. The script uses sudo when needed."
  [ "$(uname -m)" = "aarch64" ] || warn "Expected aarch64 (UNO Q); found $(uname -m). Continuing anyway."
  command -v apt-get >/dev/null || die "apt-get not found. This script targets the UNO Q's Debian image."
  info "User: $USER   Home: $HOME"
  info "Project folder: $ROS2_DIR"
  info "sudo may ask for your password once."
  sudo -v || die "sudo is required."
  # Keep the sudo timestamp fresh while the script runs (long docker builds).
  ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
  ok "Ready"
}

update_system() {
  step "Updating the system (guide: Preparing the System)"
  sudo apt-get update
  if [ "$SKIP_UPGRADE" = "1" ]; then
    warn "SKIP_UPGRADE=1, skipping apt upgrade"
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl python3 x11-xserver-utils
  ok "System packages up to date"
}

setup_docker() {
  step "Checking Docker and Docker Compose (guide: Verifying Docker)"
  if ! command -v docker >/dev/null; then
    info "Docker not found, installing docker.io and docker-compose"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1 || true

  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    info "Adding $USER to the docker group"
    sudo usermod -aG docker "$USER"
    warn "Group change applies after you log out and back in. This run uses sudo for docker."
  fi

  # Use plain docker if we already have access; otherwise fall back to sudo for this run.
  if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi

  if "${DOCKER[@]}" compose version >/dev/null 2>&1; then
    COMPOSE=("${DOCKER[@]}" compose)
  elif command -v docker-compose >/dev/null; then
    if [ "${DOCKER[0]}" = "sudo" ]; then COMPOSE=(sudo docker-compose); else COMPOSE=(docker-compose); fi
  else
    die "Docker Compose not available. Install it with: sudo apt install docker-compose"
  fi

  info "$("${DOCKER[@]}" --version)"
  info "$("${COMPOSE[@]}" version | head -1)"
  "${DOCKER[@]}" run --rm hello-world >/dev/null && ok "Docker works (hello-world)"
}

move_docker_data() {
  step "Moving Docker's data folder to the larger partition (guide: Moving Docker's Data Folder)"
  df -h / "$HOME" | sed 's/^/    /'

  if [ "$MOVE_DOCKER_DATA" != "1" ]; then
    warn "MOVE_DOCKER_DATA=0, leaving Docker data where it is"
    return
  fi

  local current
  current="$("${DOCKER[@]}" info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [ "$current" = "$DOCKER_DATA_DIR" ]; then
    ok "Already using $DOCKER_DATA_DIR"
    return
  fi

  info "Current Docker Root Dir: ${current:-unknown} -> $DOCKER_DATA_DIR"
  warn "Arduino App Lab will re-download its images the next time you run an app."

  sudo systemctl stop docker docker.socket
  sudo mkdir -p "$DOCKER_DATA_DIR"
  sudo mkdir -p /etc/docker
  [ -f /etc/docker/daemon.json ] && sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)"

  # Merge "data-root" into daemon.json, keeping existing settings (log-opts, ...).
  sudo python3 - "$DOCKER_DATA_DIR" <<'PY'
import json, os, sys
path = "/etc/docker/daemon.json"
cfg = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        cfg = json.load(f)
cfg["data-root"] = sys.argv[1]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  sed 's/^/    /' /etc/docker/daemon.json

  sudo systemctl reset-failed docker >/dev/null 2>&1 || true
  sudo systemctl start docker
  current="$("${DOCKER[@]}" info --format '{{.DockerRootDir}}')"
  [ "$current" = "$DOCKER_DATA_DIR" ] || die "Docker Root Dir is $current, expected $DOCKER_DATA_DIR. Check: sudo journalctl -u docker.service -n 30 --no-pager"
  ok "Docker Root Dir: $current"
  info "Old data is still in /var/lib/docker. Once everything works you can free it with: sudo rm -rf /var/lib/docker"
}

pull_image() {
  step "Pulling $ROS_IMAGE (guide: Pulling the Image)"
  "${DOCKER[@]}" pull "$ROS_IMAGE"
  ok "Image pulled"
}

get_project_files() {
  step "Getting the project files (guide: Preparing the Project Files)"
  if [ -d "$WORKSHOP_DIR/.git" ]; then
    info "Updating $WORKSHOP_DIR"
    git -C "$WORKSHOP_DIR" pull --ff-only || warn "Could not update the workshop repo, using the existing copy"
  else
    git clone --depth 1 "$WORKSHOP_REPO" "$WORKSHOP_DIR"
  fi

  if [ -d "$ROS2_DIR" ]; then
    warn "$ROS2_DIR already exists, keeping it (your edits and workspace are preserved)"
  else
    cp -r "$WORKSHOP_DIR/ros2" "$ROS2_DIR"
    ok "Copied ros2 folder to $ROS2_DIR"
  fi
  for f in Dockerfile docker-compose.yml ros_entrypoint.sh; do
    [ -f "$ROS2_DIR/$f" ] || die "Missing $ROS2_DIR/$f"
  done
  mkdir -p "$ROS2_DIR/ros2_ws/src"
}

patch_dockerfile() {
  step "Adding packages to the Dockerfile (guide: Installing the Packages)"
  local df="$ROS2_DIR/Dockerfile"
  [ -f "$df.orig" ] || cp "$df" "$df.orig"

  # Insert new package lines *before* an anchor line. Every inserted line ends
  # with a plain backslash, so the existing "&& \" on the last package stays valid.
  add_pkg_before() {  # $1 = package, $2 = anchor package already in the file
    if grep -qE "^[[:space:]]+$1([[:space:]]|$)" "$df"; then
      info "$1 already present"
      return
    fi
    grep -qE "^[[:space:]]+$2([[:space:]]|$)" "$df" || die "Could not find '$2' in $df to anchor '$1'. Edit the Dockerfile by hand (see the guide)."
    sed -i -E "0,/^([[:space:]]+)$2([[:space:]]|$)/s//\1$1 \\\\\n&/" "$df"
    ok "Added $1"
  }

  add_pkg_before "nano"                     "python3-colcon-common-extensions"
  add_pkg_before "ros-jazzy-demo-nodes-cpp" "ros-jazzy-demo-nodes-py"
  add_pkg_before "ros-jazzy-turtlesim"      "ros-jazzy-demo-nodes-py"

  info "Package blocks now read:"
  grep -nE '^[[:space:]]+(git|nano|python3-|ros-jazzy-)' "$df" | sed 's/^/      /'
}

patch_compose() {
  step "Giving the container display access (guide: Starting the Container)"
  local dc="$ROS2_DIR/docker-compose.yml"
  [ -f "$dc.orig" ] || cp "$dc" "$dc.orig"

  python3 - "$dc" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)
text = "".join(lines)
changed = []

def insert_after(pattern, new_line):
    for i, l in enumerate(lines):
        m = re.match(r"^(\s*)" + pattern, l)
        if m:
            lines.insert(i + 1, f"{m.group(1)}{new_line}\n")
            return True
    return False

if "DISPLAY=" not in text:
    if not insert_after(r"- ROS_DOMAIN_ID=", "- DISPLAY=${DISPLAY:-:0}"):
        sys.exit("Could not find 'ROS_DOMAIN_ID' in environment list")
    changed.append("DISPLAY")
if "/tmp/.X11-unix" not in text:
    if not insert_after(r"- \./ros2_ws:/ros2_ws", "- /tmp/.X11-unix:/tmp/.X11-unix"):
        sys.exit("Could not find './ros2_ws:/ros2_ws' in volumes list")
    changed.append("X11 socket")

open(path, "w").write("".join(lines))
print("    added: " + ", ".join(changed) if changed else "    already configured")
PY
  grep -qE 'network_mode:[[:space:]]*host' "$dc" || warn "network_mode: host missing from compose file"
  grep -qE 'ipc:[[:space:]]*host' "$dc"          || warn "ipc: host missing from compose file"
  ok "docker-compose.yml ready"
}

setup_display() {
  step "Allowing containers to use the board's display (guide: Allowing Container Access to the Display)"
  if [ "$SKIP_DISPLAY" = "1" ]; then
    warn "SKIP_DISPLAY=1, skipping"
    return
  fi

  # 1) SSH sessions: point at the monitor's X server (:0).
  local marker="# ros2-on-unoq: use the board's monitor for GUI apps"
  if ! grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null; then
    cat >>"$HOME/.bashrc" <<EOF

$marker
if [ -z "\${DISPLAY:-}" ] && [ -S /tmp/.X11-unix/X0 ]; then
  export DISPLAY=:0
  export XAUTHORITY="\$HOME/.Xauthority"
fi
EOF
    ok "Added DISPLAY/XAUTHORITY to ~/.bashrc (for SSH sessions)"
  else
    info "$HOME/.bashrc already configured"
  fi

  # 2) Re-apply "xhost +local:docker" automatically at every desktop login,
  #    so it survives reboots.
  local autostart="$HOME/.config/autostart/xhost-docker.desktop"
  mkdir -p "$(dirname "$autostart")"
  cat >"$autostart" <<'EOF'
[Desktop Entry]
Type=Application
Name=Allow Docker X11 access
Comment=Lets local Docker containers (ROS 2) open windows on this display
Exec=xhost +local:docker
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  ok "Autostart entry: $autostart"

  # 3) Apply it now if a desktop session is running.
  if [ -S /tmp/.X11-unix/X0 ] && [ -f "$HOME/.Xauthority" ]; then
    if DISPLAY=:0 XAUTHORITY="$HOME/.Xauthority" xhost +local:docker >/dev/null 2>&1; then
      ok "xhost +local:docker applied on :0"
    else
      warn "Could not reach display :0. Log in on the board's desktop, then run: xhost +local:docker"
    fi
  else
    warn "No desktop session on :0 right now. It will be applied automatically at the next desktop login."
  fi
}

setup_web_display() {
  step "Adding the browser display (no monitor needed)"
  if [ "$SKIP_WEB_DISPLAY" = "1" ]; then
    warn "SKIP_WEB_DISPLAY=1, skipping"
    return
  fi
  local dir="$ROS2_DIR/web-display"
  mkdir -p "$dir"

  # Virtual X display :99 (TigerVNC) served to the browser by noVNC.
  cat >"$dir/Dockerfile" <<'EOF'
FROM debian:trixie-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends tigervnc-standalone-server novnc websockify && \
    rm -rf /var/lib/apt/lists/* && \
    printf '<meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale">\n' > /usr/share/novnc/index.html
COPY start.sh /start.sh
RUN chmod +x /start.sh
CMD ["/start.sh"]
EOF

  cat >"$dir/start.sh" <<'EOF'
#!/bin/sh
# Virtual X display :99, shown in the browser at http://<board-ip>:6080
set -e
DISPLAY_NUM="${DISPLAY_NUM:-99}"
GEOMETRY="${GEOMETRY:-1024x768}"
WEB_PORT="${WEB_PORT:-6080}"
VNC_PORT=$((5900 + DISPLAY_NUM))
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
Xtigervnc ":${DISPLAY_NUM}" -geometry "$GEOMETRY" -depth 24 \
  -SecurityTypes None -localhost -rfbport "$VNC_PORT" \
  -AlwaysShared -ac -nolisten tcp &
echo "Web display: http://<board-ip>:${WEB_PORT}  (in the container: export DISPLAY=:${DISPLAY_NUM})"
exec websockify --web /usr/share/novnc "$WEB_PORT" "127.0.0.1:${VNC_PORT}"
EOF
  ok "Wrote $dir"

  local dc="$ROS2_DIR/docker-compose.yml"
  if grep -qE '^  display:' "$dc"; then
    info "display service already in docker-compose.yml"
  else
    cat >>"$dc" <<EOF

  # Browser display: open http://<board-ip>:${WEB_PORT}, then in the container: export DISPLAY=:99
  display:
    build: ./web-display
    image: unoq-web-display
    container_name: ros2_display
    network_mode: host
    ipc: host
    environment:
      - WEB_PORT=${WEB_PORT}
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix
    restart: unless-stopped
EOF
    ok "Added display service to docker-compose.yml"
  fi
}

build_and_start() {
  step "Building the image and starting the container"
  cd "$ROS2_DIR"
  local old_id new_id
  old_id="$("${DOCKER[@]}" inspect -f '{{.Id}}' ros2_jazzy 2>/dev/null || true)"

  "${COMPOSE[@]}" build
  "${COMPOSE[@]}" up -d
  new_id="$("${DOCKER[@]}" inspect -f '{{.Id}}' ros2_jazzy 2>/dev/null || true)"
  if [ -n "$old_id" ] && [ "$old_id" != "$new_id" ]; then
    warn "Container was recreated. Close any old 'docker compose exec' shells and open new ones."
  fi

  info "Waiting for the first workspace build inside the container..."
  local _
  for _ in $(seq 1 120); do
    if [ -f "$ROS2_DIR/ros2_ws/install/setup.bash" ]; then break; fi
    if [ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' ros2_jazzy 2>/dev/null)" != "true" ]; then
      "${COMPOSE[@]}" logs --tail 40 | sed 's/^/    /'
      die "Container stopped unexpectedly (logs above)."
    fi
    sleep 5
  done
  [ -f "$ROS2_DIR/ros2_ws/install/setup.bash" ] && ok "Workspace built" || warn "Workspace build still running. Follow it with: cd $ROS2_DIR && docker compose logs -f"
}

verify() {
  step "Verifying the container"
  cd "$ROS2_DIR"
  local pkgs
  pkgs="$("${COMPOSE[@]}" exec -T ros2 bash -c 'source /opt/ros/jazzy/setup.bash && ros2 pkg list' 2>/dev/null || true)"
  local p missing=0
  for p in demo_nodes_cpp demo_nodes_py turtlesim; do
    if grep -qx "$p" <<<"$pkgs"; then ok "$p installed"; else warn "$p NOT found"; missing=1; fi
  done
  local disp
  disp="$("${COMPOSE[@]}" exec -T ros2 printenv DISPLAY 2>/dev/null || true)"
  [ -n "$disp" ] && ok "Container DISPLAY=$disp" || warn "Container has no DISPLAY set"
  info "Network/IPC mode: $("${DOCKER[@]}" inspect --format '{{.HostConfig.NetworkMode}} {{.HostConfig.IpcMode}}' ros2_jazzy)"
  if [ "$SKIP_WEB_DISPLAY" != "1" ]; then
    if curl -fs -o /dev/null "http://127.0.0.1:${WEB_PORT}/"; then ok "Browser display on port ${WEB_PORT}"; else warn "Browser display not answering on port ${WEB_PORT} yet"; fi
  fi
  [ "$missing" = "0" ] || die "Some packages are missing. Check $ROS2_DIR/Dockerfile."
}

finish() {
  cat <<EOF

${C_B}${C_G}============================================================
 ROS 2 Jazzy is installed and running on your UNO Q
============================================================${C_0}

${C_B}Test it: talker / listener${C_0}

  Terminal 1:
    cd $ROS2_DIR
    docker compose exec ros2 bash
    ros2 run demo_nodes_cpp talker

  Terminal 2:
    cd $ROS2_DIR
    docker compose exec ros2 bash
    ros2 run demo_nodes_cpp listener

  Expected:  [listener]: I heard: [Hello World: 1] ...

${C_B}GUI test: turtlesim${C_0}
  On the board's monitor:
    ros2 run turtlesim turtlesim_node
  In your browser (no monitor): open http://$(hostname -I 2>/dev/null | awk '{print $1}'):${WEB_PORT}
    export DISPLAY=:99
    ros2 run turtlesim turtlesim_node

${C_B}Everyday commands (run in $ROS2_DIR)${C_0}
    docker compose up -d            start
    docker compose down             stop
    docker compose up -d --build    rebuild after editing Dockerfile / compose
EOF
  if ! id -nG | tr ' ' '\n' | grep -qx docker; then
    printf '\n%sLog out and back in (or reboot) so you can run docker without sudo.%s\n' "$C_Y" "$C_0"
  fi
}

main() {
  printf '%sROS 2 Jazzy on Arduino UNO Q — installer%s\n' "$C_B" "$C_0"
  preflight
  update_system
  setup_docker
  move_docker_data
  pull_image
  get_project_files
  patch_dockerfile
  patch_compose
  setup_display
  setup_web_display
  build_and_start
  verify
  finish
}

# Wrapped in main so a partially downloaded script never runs half-way.
main "$@"
