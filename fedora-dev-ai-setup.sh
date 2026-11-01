#!/usr/bin/env bash
# Fedora 44/45 KDE: dev + local AI + gaming setup for the RTX 5090 / 9950X3D machine
# Installs: NVIDIA driver + CUDA (RPM Fusion), full codecs, dev tools, Rust, VS Code,
#           Claude Code, OpenCode, Codex CLI, gaming tools, Bazzite/CachyOS/Nobara-style
#           system tuning, and pre-update Btrfs snapshots.
# It checks what is already set up first and only does what is missing, so it is
# safe to re-run at any time.
#
# Run as your normal user (not root):  bash fedora-dev-ai-setup.sh
#   --check         show what is installed/active and change nothing (no sudo needed)
#   --guide         only write the instructions file (no sudo needed)
#   --no-update     skip the full "dnf upgrade" at the start
#   --no-dev        skip dev tools, Rust, VS Code, Cursor and the AI coding CLIs
#   --no-gaming     skip gaming packages and the GameMode/shader/DLSS setup
#   --no-tuning     skip sysctl, zram, I/O scheduler and audio tuning
#   --no-snapshots  skip snapper and the pre-dnf snapshots
#   --sunshine      also install Sunshine (stream games to Moonlight clients)
#   --lact          also install LACT (GPU fan curves, power limit, clocks)
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not root. It uses sudo where needed." >&2
  exit 1
fi

MODE=apply
UPDATE=true
DEV=true
GAMING=true
TUNING=true
SNAPSHOTS=true
SUNSHINE=false
LACT=false
for arg in "$@"; do
  case "$arg" in
    --check)        MODE=check ;;
    --guide)        MODE=guide ;;
    --no-update)    UPDATE=false ;;
    --no-dev)       DEV=false ;;
    --no-gaming)    GAMING=false ;;
    --no-tuning)    TUNING=false ;;
    --no-snapshots) SNAPSHOTS=false ;;
    --sunshine)     SUNSHINE=true ;;
    --lact)         LACT=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Installers put their tools here; check them even in a shell that predates them.
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.cargo/bin:$PATH"

SCRIPT_PATH="$(readlink -f "$0")"
# The guide lives next to the script, so the folder stays complete.
GUIDE_FILE="$(dirname "$SCRIPT_PATH")/fedora-setup-guide.txt"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
skip() { printf '    already done: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Installs only the packages that are missing. Name the arch where it matters:
# "gamemode" alone counts as present when only gamemode.i686 is installed.
need_pkgs() {
  local missing=() p
  for p in "$@"; do
    rpm -q "$p" >/dev/null 2>&1 || rpm -q --whatprovides "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    skip "packages ($*)"
  else
    sudo dnf install -y "${missing[@]}"
  fi
}

# Same for Flatpak apps.
need_flatpaks() {
  local missing=() app
  for app in "$@"; do
    flatpak info "$app" >/dev/null 2>&1 || missing+=("$app")
  done
  if (( ${#missing[@]} == 0 )); then
    skip "Flatpaks ($*)"
  else
    flatpak install --user -y flathub "${missing[@]}"
  fi
}

# Writes stdin to a root-owned file. Returns 0 if the file changed, 1 if it was
# already correct, so callers can reload a service only when needed:
#   if put_file /etc/x.conf <<'EOF'; then reload; fi
#   put_file /etc/y.conf <<'EOF' || true
put_file() {
  local path="$1" mode="${2:-0644}" content
  content="$(cat; printf x)"
  if [[ -r "$path" ]] && [[ "$(cat "$path"; printf x)" == "$content" ]]; then
    skip "$path"
    return 1
  fi
  sudo install -d -m 0755 "$(dirname "$path")"
  printf '%s' "${content%x}" | sudo tee "$path" >/dev/null
  sudo chmod "$mode" "$path"
  return 0
}

# Facts the checks and the setup steps share ------------------------------
secure_boot_on()   { [[ "$(mokutil --sb-state 2>/dev/null)" == *enabled* ]]; }
mok_enrolled()     { [[ "$(mokutil --list-enrolled 2>/dev/null)" == *akmods@* ]]; }
mok_queued()       { [[ -n "$(mokutil --list-new 2>/dev/null)" ]]; }
newest_kernel()    { rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1; }
on_newest_kernel() { [[ "$(uname -r)" == "$(newest_kernel)" ]]; }
driver_rpm()       { rpm -q --qf '%{VERSION}' xorg-x11-drv-nvidia 2>/dev/null; }
driver_live()      { [[ "$(cat /sys/module/nvidia/version 2>/dev/null)" == "$(driver_rpm)" ]]; }
kmod_for_newest()  { [[ -n "$(modinfo -k "$(newest_kernel)" -F version nvidia 2>/dev/null)" ]]; }
kmod_is_open()     { [[ "$(modinfo -F license nvidia 2>/dev/null)" == *MIT* ]]; }
kmod_loaded()      { [[ -r /proc/driver/nvidia/version ]]; }
sb_key_ok()        { ! secure_boot_on || mok_enrolled; }
gl_flatpak()       { local v; v="$(driver_rpm)"; flatpak info "org.freedesktop.Platform.$1.nvidia-${v//./-}" 1.4; }
x3d_active()       { compgen -G '/sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode'; }
x3d_nopasswd()     { sudo -n -l /usr/local/libexec/x3d-mode-set cache; }
sysctl_is()        { [[ "$(sysctl -n "$1" 2>/dev/null)" == "$2" ]]; }
in_file()          { grep -q "$1" "$2" 2>/dev/null; }
hud_layer()        { local rt; rt="$(flatpak info --show-runtime com.heroicgameslauncher.hgl 2>/dev/null)"; printf '%s' "${rt##*/}"; }

# Status report -----------------------------------------------------------
N_OK=0 N_MISSING=0 N_REBOOT=0
row()    { printf '  %-8s %s\n' "$1" "$2"; }
group()  { printf '\n %s\n' "$1"; }
pass()   { row OK "$1"; N_OK=$((N_OK + 1)); }
absent() { row MISSING "$1"; N_MISSING=$((N_MISSING + 1)); }
wait_reboot() { row REBOOT "$1"; N_REBOOT=$((N_REBOOT + 1)); }

# item LABEL TEST...: the test passes or the thing is missing.
item() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else absent "$label"; fi
}
# live LABEL CONFIG_FILE TEST...: set up on disk but not active until a reboot.
live() {
  local label="$1" file="$2"; shift 2
  if "$@" >/dev/null 2>&1; then pass "$label"
  elif [[ -e "$file" ]]; then wait_reboot "$label"
  else absent "$label"; fi
}
# extra LABEL HINT TEST...: optional, so never counted as missing.
extra() {
  local label="$1" hint="$2"; shift 2
  if "$@" >/dev/null 2>&1; then row OK "$label"; else row off "$label ($hint)"; fi
}

report() {
  N_OK=0 N_MISSING=0 N_REBOOT=0
  printf ' %s, kernel %s\n' "$(cat /etc/fedora-release)" "$(uname -r)"

  group "Base system"
  item "RPM Fusion repos" rpm -q rpmfusion-free-release rpmfusion-nonfree-release
  if on_newest_kernel; then pass "Running the newest installed kernel"
  else wait_reboot "Running the newest installed kernel ($(newest_kernel))"; fi
  item "Secure Boot key enrolled (or Secure Boot off)" sb_key_ok

  group "NVIDIA ($(driver_rpm))"
  item "Kernel module loaded" kmod_loaded
  item "Open kernel module in use" kmod_is_open
  item "Module built for the newest kernel" kmod_for_newest
  if driver_live; then pass "Loaded driver matches the installed packages"
  else wait_reboot "Loaded driver matches the installed packages"; fi
  item "CUDA runtime" rpm -q xorg-x11-drv-nvidia-cuda
  item "32-bit libraries" rpm -q xorg-x11-drv-nvidia-libs.i686
  item "Video acceleration (VA-API)" rpm -q libva-nvidia-driver.x86_64
  item "Flatpak GL runtime matches the driver" gl_flatpak GL
  item "Flatpak 32-bit GL runtime matches the driver" gl_flatpak GL32

  group "Codecs"
  item "Full ffmpeg" rpm -q ffmpeg
  item "GStreamer plugins" rpm -q gstreamer1-plugin-libav gstreamer1-plugins-bad-freeworld

  if $DEV; then
    group "Dev tools"
    item "Compiler toolchain" rpm -q gcc make cmake clang
    item "Rust (rustup)" have rustup
    item "VS Code" have code
    item "Cursor" have cursor
    item "Claude Code" have claude
    item "OpenCode" have opencode
    item "Codex CLI" have codex
    item "Distrobox" have distrobox
  fi

  if $GAMING; then
    group "Gaming"
    item "Steam" rpm -q steam
    item "GameMode 64-bit" rpm -q gamemode.x86_64
    item "GameMode 32-bit" rpm -q gamemode.i686
    item "MangoHud 64-bit + 32-bit" rpm -q mangohud.x86_64 mangohud.i686
    item "gamescope" rpm -q gamescope
    item "Lutris" rpm -q lutris
    item "GOverlay" rpm -q goverlay
    item "Heroic" flatpak info com.heroicgameslauncher.hgl
    item "MangoHud for Heroic" flatpak info org.freedesktop.Platform.VulkanLayer.MangoHud "$(hud_layer)"
    item "ProtonUp-Qt" flatpak info net.davidotek.pupgui2
    item "Protontricks" flatpak info com.github.Matoking.protontricks
    item "GPU Screen Recorder" flatpak info com.dec05eba.gpu_screen_recorder
    item "dlss-swapper" have dlss-swapper
    item "ntsync" test -e /dev/ntsync
    item "16 GB shader cache" in_file '=17179869184$' "$HOME/.config/environment.d/90-nvidia-shader-cache.conf"
    item "x3d-mode helper" have x3d-mode
    item "x3d-mode runs without a password" x3d_nopasswd
    item "X3D driver active (BIOS CPPC = Driver)" x3d_active
    item "GameMode switches X3D mode" in_file 'x3d-mode game' "$HOME/.config/gamemode.ini"
    item "GameMode pins games to the V-Cache cores" in_file '^pin_cores=0-7,16-23' "$HOME/.config/gamemode.ini"
  fi

  if $TUNING; then
    group "System tuning"
    live "BBR congestion control" /etc/sysctl.d/90-gaming-dev.conf sysctl_is net.ipv4.tcp_congestion_control bbr
    live "File-watcher limit" /etc/sysctl.d/90-gaming-dev.conf sysctl_is fs.inotify.max_user_instances 8192
    live "Earlier disk write flushing" /etc/sysctl.d/90-gaming-dev.conf sysctl_is vm.dirty_bytes 268435456
    live "zram uses zstd" /etc/systemd/zram-generator.conf in_file '\[zstd\]' /sys/block/zram0/comp_algorithm
    item "Audio devices stay awake" test -e /etc/wireplumber/wireplumber.conf.d/51-disable-suspension.conf
    item "Wine audio crackle fix" test -e /etc/pipewire/pipewire-pulse.conf.d/wine_gaming.conf
  fi

  if $SNAPSHOTS; then
    group "Snapshots"
    item "snapper root config" test -d /.snapshots
    item "Snapshot before each dnf transaction" test -e /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
    item "Btrfs Assistant" rpm -q btrfs-assistant
  fi

  group "Optional"
  extra "Sunshine game streaming" "add with --sunshine" rpm -q Sunshine
  extra "LACT GPU control" "add with --lact" rpm -q lact

  printf '\n Summary: %d OK, %d missing, %d waiting for a reboot\n' "$N_OK" "$N_MISSING" "$N_REBOOT"
}

# Instructions file --------------------------------------------------------
write_guide() {
  {
    printf 'FEDORA GAMING + DEV SETUP GUIDE\n'
    printf 'Written by fedora-dev-ai-setup.sh on %s\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'Refresh this file:  bash %s --guide\n' "$SCRIPT_PATH"
    printf 'Check the system:   bash %s --check\n' "$SCRIPT_PATH"
    cat <<'EOF'

CONTENTS
  1. Steam launch options       8. GPU Screen Recorder
  2. GameMode and X3D           9. LACT (optional)
  3. MangoHud                  10. Sunshine (optional)
  4. GOverlay                  11. Snapshots
  5. DLSS swapper              12. NVIDIA driver updates
  6. Proton, ntsync and HDR    13. Anti-cheat
  7. Other game tools          14. System settings and how to undo them
                               15. Dev tools and Distrobox
                               16. Current system state


1. STEAM LAUNCH OPTIONS
-----------------------
Where: right-click a game > Properties > General > Launch Options.
First time only: Steam > Settings > Compatibility > enable Steam Play for all titles.

Order matters: VARIABLES first, then tools, then %command% last.

  Everyday:
    gamemoderun mangohud %command%

  Games with DLSS:
    gamemoderun mangohud dlss-swapper %command%

  Confirm which DLSS is running (GE-Proton or Proton-CachyOS):
    PROTON_DLSS_INDICATOR=1 gamemoderun mangohud dlss-swapper %command%

  Native Wayland window (GE-Proton or Proton-CachyOS):
    PROTON_ENABLE_WAYLAND=1 gamemoderun mangohud %command%

  Through gamescope at your monitor's native mode:
    gamemoderun gamescope -W 3840 -H 2160 -r 240 -f --adaptive-sync --mangoapp -- %command%

  Render at 1440p and upscale with gamescope:
    gamemoderun gamescope -W 3840 -H 2160 -w 2560 -h 1440 -r 240 -f -F fsr --mangoapp -- %command%


2. GAMEMODE AND X3D
-------------------
"gamemoderun" does the following while a game runs, then undoes it on exit:
  - switches the 9950X3D to cache mode (x3d-mode game)
  - pins the game to the V-Cache cores (CPUs 0-7 and 16-23)
  - sets the CPU governor to performance

Check that it works, while a game is running:
  gamemoded -s      should say "gamemode is active"
  x3d-mode          should say "x3d-mode: cache"

Manual control:
  x3d-mode          show the current mode
  x3d-mode game     cache mode, best for most games
  x3d-mode dev      frequency mode, best for compiling and general work

Cache mode and pinning are two different things:
  - Cache mode is a preference. The CPU favours the V-Cache cores, but game
    threads can still land on the other, slower-cache cores.
  - Pinning is a rule. The game can only run on the V-Cache cores.

Settings file: ~/.config/gamemode.ini
A game that wants more than these 16 threads can lose out from pinning. To test
that, remove the pin_cores line and compare.


3. MANGOHUD
-----------
The in-game overlay for FPS, frametimes, temperatures and usage.

Default keys:
  Right Shift + F12    show/hide the overlay
  Right Shift + F10    next preset
  Left Shift + F1      cycle the FPS limit
  Left Shift + F2      start/stop logging performance to a file
  Left Shift + F4      reload the config

Config, highest priority first:
  ~/.config/MangoHud/<application_name>.conf     one game only
  ~/.config/MangoHud/MangoHud.conf               all games
All options with explanations: /usr/share/doc/mangohud/MangoHud.conf.example
GOverlay (next section) edits all of this with a GUI.


4. GOVERLAY
-----------
A GUI for MangoHud, vkBasalt (sharpening and other effects) and OptiScaler
(upscaler and frame generation swapping). Start it from the application menu.

  - For one game: select the game. It gets its own config folder, and GOverlay
    shows a launch command ending in %command%.
  - Paste that into Steam's Launch Options, with gamemoderun in front:
      gamemoderun <the command GOverlay shows>
  - OptiScaler copies files into the game folder, so avoid it in online games
    with anti-cheat.


5. DLSS SWAPPER
---------------
"dlss-swapper" is a small wrapper you add per game. It does two things:
  - PROTON_DLSS_UPGRADE=1 makes GE-Proton and Proton-CachyOS download newer DLSS
    files. Other Proton builds, including Proton Experimental, ignore this.
  - It selects the latest DLSS Super Resolution and Ray Reconstruction presets
    and turns on the frame generation override. Those work with any Proton.

How to use it:
  1. Pick GE-Proton or Proton-CachyOS: Properties > Compatibility > Force a specific tool.
  2. Launch options:  gamemoderun mangohud dlss-swapper %command%
  3. To confirm, add PROTON_DLSS_INDICATOR=1 in front. A small DLSS text overlay
     shows in-game. Remove the variable afterwards.

Try it on single-player games first. It changes DLSS files, and how anti-cheat
reacts to that varies by game.


6. PROTON, NTSYNC AND HDR
-------------------------
Install new Proton builds: open ProtonUp-Qt, press "Add version", pick GE-Proton,
then restart Steam. Choose it under Properties > Compatibility.

ntsync: GE-Proton uses it automatically, no launch option needed. To confirm
while a game runs:
  lsof /dev/ntsync      should list the game's processes
To turn it off for one game on GE-Proton: PROTON_NO_NTSYNC=1 %command%

HDR: turn it on in KDE (System Settings > Display & Monitor), then in the game.
GE-Proton detects HDR for DX11/DX12 automatically. If a game does not offer it,
try PROTON_ENABLE_WAYLAND=1. Through gamescope, add --hdr-enabled instead.


7. OTHER GAME TOOLS
-------------------
Protontricks installs Windows components into one game's Proton prefix:
  flatpak run com.github.Matoking.protontricks --gui

Lutris: to add GameMode and MangoHud, put "gamemoderun mangohud" in a game's
Command prefix setting (Configure > System options).

Heroic (Epic, GOG, Amazon): open a game's settings and turn on the GameMode and
Mangohud options. Confirm GameMode with the checks in section 2.


8. GPU SCREEN RECORDER
----------------------
Records and clips gameplay through NVENC with very low overhead, similar to
ShadowPlay. Start it from the application menu, then pick the capture target,
codec, and hotkeys in the app. Its Replay mode keeps the last few minutes so you
can save a clip after something happens. Encoding on your RTX 5090 runs on a
dedicated chip, so games keep their performance.


9. LACT (optional, install with --lact)
---------------------------------------
GPU control panel: fan curves, power limit and clocks. Start it from the
application menu. Your RTX 5090 allows a 400-600 W power limit, and lowering it
is the simplest way to cut heat and noise. Changes need the background service:
  systemctl status lactd


10. SUNSHINE (optional, install with --sunshine)
------------------------------------------------
Streams your desktop and games to Moonlight on another device.
  1. Open https://localhost:47990 straight away and create the admin login.
  2. In Moonlight, add this PC and enter the PIN into the web page.
Your Fedora firewall zone already allows the ports on your network.


11. SNAPSHOTS
-------------
A snapshot of the system (not /home) is taken before every dnf transaction, and
the last 10 are kept.

  sudo snapper -c root list                     list snapshots
  sudo snapper -c root status <pre>..<post>     see what changed
  sudo snapper -c root undochange <pre>..<post> put those files back

Btrfs Assistant does the same with a GUI. These undo file changes, but you can't
boot into a snapshot, and /boot isn't included, so kernels aren't covered. They
do not replace a backup.


12. NVIDIA DRIVER UPDATES
-------------------------
After a kernel or driver update, the module is rebuilt in the background, which
takes a few minutes. Before rebooting, confirm it finished by running the
--check command from the top of this file.
"Module built for the newest kernel" must say OK.

If you boot to a black screen: restart, pick the previous kernel in the GRUB
menu, then run:
  sudo akmods --force --kernels <new kernel version>

Flatpak apps need a runtime that matches the driver. After a driver update run:
  flatpak update
If --check still shows it as MISSING, Flathub hasn't published it yet.


13. ANTI-CHEAT
--------------
Easy Anti-Cheat Linux v2 (for example Fortnite) needs Secure Boot, TPM 2.0,
kernel lockdown and modules signed by a recognised authority. Your NVIDIA module
is signed with your own local key, and Epic says an enrolled key doesn't satisfy
this by itself, so expect EAC v2 games to refuse to run on this setup.


14. SYSTEM SETTINGS AND HOW TO UNDO THEM
----------------------------------------
Each setting is one file. Delete it with sudo rm and reboot to undo it.

  /etc/sysctl.d/90-gaming-dev.conf
      BBR networking, MTU probing, file-watcher limit, zram swap behaviour,
      earlier disk write flushing
  /etc/systemd/zram-generator.conf
      16 GB zstd zram instead of Fedora's 8 GB lzo-rle
  /etc/wireplumber/wireplumber.conf.d/51-disable-suspension.conf
      keeps audio devices awake. Delete this if you never hear pops or
      clipped sound when audio starts.
  /etc/pipewire/pipewire-pulse.conf.d/wine_gaming.conf
      bigger Wine audio buffer, against crackling
  /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
      the snapshot before each dnf transaction
  ~/.config/environment.d/90-nvidia-shader-cache.conf
      16 GB NVIDIA shader cache, up from the 1 GB default
  ~/.config/gamemode.ini
      X3D switching ([custom]) and core pinning ([cpu])

Left at Fedora's defaults on purpose:
  - NVMe scheduler stays on "none". Bazzite and CachyOS use kyber, Nobara uses
    none, and there is no problem here for it to fix. To try kyber until the
    next reboot:  echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler
  - vm.max_map_count stays at 1048576. Only Star Citizen is known to want more:
    if you play it, add vm.max_map_count = 16777216 to the sysctl file above.


15. DEV TOOLS AND DISTROBOX
---------------------------
Skip all of this with --no-dev. It covers the compilers, Rust, VS Code, Cursor,
Claude Code, OpenCode, Codex CLI and Distrobox.

Distrobox runs another Linux distro in a container that feels like part of your
desktop. It shares your home folder, GUI, audio and USB devices, so it is useful
when a tool only supports Ubuntu or Arch, or needs libraries that you don't want
on Fedora. Nothing inside the box touches the host system.

  distrobox create --nvidia --image ubuntu:24.04 --name ubuntu
  distrobox enter ubuntu       work inside it, with apt and your own files
  distrobox list               show your boxes
  distrobox rm ubuntu          delete the box (your home folder files stay)

--nvidia passes your GPU through, including CUDA, for local AI tools.


16. CURRENT SYSTEM STATE
------------------------
OK = working   MISSING = not set up   REBOOT = takes effect after a reboot
off = optional and not installed

EOF
    report
  } > "$GUIDE_FILE"
}

if [[ $MODE == check ]]; then
  report
  (( N_MISSING == 0 ))
  exit
fi
if [[ $MODE == guide ]]; then
  write_guide
  echo "Guide written to: $GUIDE_FILE"
  exit
fi

step "Current state"
report

# 1. System update --------------------------------------------------------
if $UPDATE; then
  step "Updating the system"
  sudo dnf upgrade --refresh -y
fi

# 2. RPM Fusion (free + nonfree) -------------------------------------------
step "Enabling RPM Fusion"
if rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
  skip "RPM Fusion repos"
else
  FED="$(rpm -E %fedora)"
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FED}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FED}.noarch.rpm"
fi

# 3. Secure Boot key (only if Secure Boot is on) ---------------------------
need_pkgs mokutil
MOK_PENDING=false
if secure_boot_on; then
  if mok_enrolled; then
    skip "Secure Boot signing key"
  elif mok_queued; then
    echo "A key is already waiting for the blue MOK screen; finish that on the next reboot."
    MOK_PENDING=true
  else
    MOK_KEY=/etc/pki/akmods/certs/public_key.der
    step "Secure Boot is ON: creating a signing key for the NVIDIA module"
    need_pkgs kmodtool akmods openssl
    sudo test -f "$MOK_KEY" || sudo kmodgenca -a
    echo "You'll now set a one-time password. Remember it: you type it once at the blue MOK screen after reboot."
    sudo mokutil --import "$MOK_KEY"
    MOK_PENDING=true
  fi
fi

# 4. NVIDIA driver + CUDA runtime -----------------------------------------
step "Installing the NVIDIA driver and CUDA runtime"
need_pkgs kernel-devel akmod-nvidia xorg-x11-drv-nvidia-cuda nvtop
# Keep dnf autoremove from ever taking the driver out (RPM Fusion's advice).
sudo dnf mark user akmod-nvidia >/dev/null 2>&1 || true

if ! kmod_for_newest; then
  step "Building the NVIDIA kernel module (can take a few minutes)"
  sudo akmods --force --kernels "$(newest_kernel)"
fi
if kmod_for_newest; then
  echo "NVIDIA module built: version $(modinfo -k "$(newest_kernel)" -F version nvidia)"
else
  echo "WARNING: module not found yet. It will retry on next boot; check with: modinfo -F version nvidia"
fi

# 4b. Full codecs + NVIDIA video acceleration ------------------------------
# Bazzite and Nobara ship these out of the box; stock Fedora has the patent-free set.
step "Installing full codecs and NVIDIA video acceleration"
if rpm -q ffmpeg-free >/dev/null 2>&1; then
  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
fi
need_pkgs ffmpeg gstreamer1-plugin-libav gstreamer1-plugins-bad-freeworld \
  libva-nvidia-driver.x86_64 libva-nvidia-driver.i686 libva-utils vdpauinfo

if $DEV; then
  # 5. Dev tools -------------------------------------------------------------
  step "Installing dev tools"
  # rpm, not "dnf group list": dnf can stop to ask a question, which would be
  # invisible here and freeze the script.
  if rpm -q make gcc patch >/dev/null 2>&1; then
    skip "development-tools group"
  else
    sudo dnf group install -y development-tools
  fi
  need_pkgs \
    git git-lfs gcc-c++ clang clang-tools-extra cmake ninja-build gdb \
    python3 python3-pip python3-devel nodejs npm \
    jq ripgrep fd-find htop curl wget unzip \
    distrobox btop fastfetch compsize lm_sensors p7zip
  git lfs install >/dev/null

  # Rust (official rustup: stable toolchain + editor/lint tools)
  step "Installing Rust"
  if have rustup; then
    skip "rustup"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  fi
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
  RUST_HAVE="$(rustup component list --installed)"
  for c in rust-analyzer clippy rustfmt; do
    [[ "$RUST_HAVE" == *"$c"* ]] || rustup component add "$c"
  done

  # 6. VS Code (Microsoft repo) ---------------------------------------------
  step "Installing VS Code"
  if rpm -q code >/dev/null 2>&1; then
    skip "VS Code"
  else
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    sudo dnf install -y code
  fi

  # 6b. Cursor (official repo, same file the Cursor RPM writes) ---------------
  step "Installing Cursor"
  if rpm -q cursor >/dev/null 2>&1; then
    skip "Cursor"
  else
    sudo tee /etc/yum.repos.d/cursor.repo >/dev/null <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
repo_gpgcheck=1
EOF
    sudo dnf install -y cursor || echo "NOTE: Cursor didn't install; get it from https://cursor.com instead."
  fi

  # 7. Claude Code (native installer, auto-updates) --------------------------
  if have claude; then
    skip "Claude Code"
  else
    step "Installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash
  fi

  # 8. OpenCode --------------------------------------------------------------
  if have opencode; then
    skip "OpenCode"
  else
    step "Installing OpenCode"
    curl -fsSL https://opencode.ai/install | bash
  fi

  # 8b. Codex CLI (OpenAI, terminal) -----------------------------------------
  if have codex; then
    skip "Codex CLI"
  else
    step "Installing Codex CLI"
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
  fi
fi

# 9. Gaming (optional) -----------------------------------------------------
if $GAMING; then
  step "Installing gaming tools"
  need_pkgs \
    steam steam-devices \
    xorg-x11-drv-nvidia-libs.i686 \
    gamemode.x86_64 gamemode.i686 mangohud.x86_64 mangohud.i686 gamescope \
    goverlay ntsync-autoload
  # Same flag Bazzite uses: Lutris fetches its own runners, so skip the weak deps.
  if rpm -q lutris >/dev/null 2>&1; then
    skip "Lutris"
  else
    sudo dnf install -y --setopt=install_weak_deps=False lutris
  fi

  # Flathub apps. Protontricks is the Flatpak on purpose: the RPM drags in 2 GiB
  # of Wine + mingw. GPU Screen Recorder is Nobara's low-overhead NVENC recorder.
  need_pkgs flatpak
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  need_flatpaks \
    com.heroicgameslauncher.hgl \
    net.davidotek.pupgui2 \
    com.github.Matoking.protontricks \
    com.dec05eba.gpu_screen_recorder
  # Flatpak sandboxes can't see the second Steam library unless told to.
  if [[ -d /data/games ]]; then
    flatpak override --user --filesystem=/data/games com.github.Matoking.protontricks
  fi
  # Heroic's "Enable Mangohud" needs the layer built for Heroic's own runtime.
  HUD_BRANCH="$(hud_layer)"
  if [[ -n "$HUD_BRANCH" ]] && ! flatpak info org.freedesktop.Platform.VulkanLayer.MangoHud "$HUD_BRANCH" >/dev/null 2>&1; then
    flatpak install --user -y flathub "org.freedesktop.Platform.VulkanLayer.MangoHud//$HUD_BRANCH" \
      || echo "NOTE: MangoHud for Heroic isn't on Flathub for $HUD_BRANCH yet."
  fi
  # Flatpak games need a GL runtime that matches the driver exactly (Bazzite
  # runs a service for this). Flathub can lag a new driver by a few days.
  NV_DASHED="$(driver_rpm)"; NV_DASHED="${NV_DASHED//./-}"
  for gl in GL GL32; do
    if ! gl_flatpak "$gl" >/dev/null 2>&1; then
      flatpak install --user -y flathub "org.freedesktop.Platform.$gl.nvidia-$NV_DASHED//1.4" \
        || echo "NOTE: Flathub doesn't have $gl for this driver yet; retry later with --check."
    fi
  done

  # Let your user use GameMode
  if id -nG "$USER" | grep -qw gamemode; then
    skip "gamemode group"
  else
    sudo usermod -aG gamemode "$USER"
  fi

  # 16 GB NVIDIA shader cache for large libraries. Set for the whole session as
  # NVIDIA's README advises: an app that sets it alone can make others wipe it.
  mkdir -p "$HOME/.config/environment.d"
  cat > "$HOME/.config/environment.d/90-nvidia-shader-cache.conf" <<'EOF'
__GL_SHADER_DISK_CACHE_SIZE=17179869184
EOF

  # Per-game wrapper for the newest DLSS. Use it as: dlss-swapper %command%
  put_file /usr/local/bin/dlss-swapper 0755 <<'EOF' || true
#!/usr/bin/bash
# Newest DLSS for one game. Steam launch option: dlss-swapper %command%
# GE-Proton and Proton-CachyOS: download newer DLSS DLLs.
export PROTON_DLSS_UPGRADE=1
# Any Proton: use the latest presets (overrides from CachyOS's dlss-swapper, GPLv3).
export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE=on
export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE=on
export DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE=on
export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
exec "$@"
EOF
fi

# 9b. Optional extras ------------------------------------------------------
if $SUNSHINE; then
  step "Installing Sunshine"
  if rpm -q Sunshine >/dev/null 2>&1; then
    skip "Sunshine"
  else
    sudo dnf copr enable -y lizardbyte/stable
    sudo dnf install -y Sunshine
  fi
  # Needed for KMS capture on a Wayland desktop (Sunshine's own docs).
  if [[ "$(getcap "$(readlink -f /usr/bin/sunshine)" 2>/dev/null)" != *cap_sys_admin* ]]; then
    sudo setcap cap_sys_admin+p "$(readlink -f /usr/bin/sunshine)"
  fi
  systemctl --user enable app-dev.lizardbyte.app.Sunshine.service \
    || echo "NOTE: enable Sunshine yourself: systemctl --user enable app-dev.lizardbyte.app.Sunshine.service"
fi

if $LACT; then
  step "Installing LACT"
  if rpm -q lact >/dev/null 2>&1; then
    skip "LACT"
  else
    sudo dnf copr enable -y ilyaz/LACT
    sudo dnf install -y lact
  fi
  sudo systemctl enable --now lactd
fi

# 10. System tuning (optional) ---------------------------------------------
# Only settings that still change something on Fedora 44 / kernel 7.2 and this
# hardware. Each one is a single file, so deleting it undoes it (see the guide).
if $TUNING; then
  step "Applying Bazzite/CachyOS/Nobara system tuning"

  if put_file /etc/sysctl.d/90-gaming-dev.conf <<'EOF'; then
# Bazzite: BBR congestion control. Bazzite + Nobara: recover from broken-MTU paths
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
# Bazzite: file-watcher limit (Fedora's 128 is easy to hit with VS Code + Node)
fs.inotify.max_user_instances = 8192
# CachyOS: swap is RAM-backed zram here, so use it freely
vm.swappiness = 100
# CachyOS: flush writes early. Percent defaults allow ~12 GB of dirty pages on
# this machine, which can stall everything when it all hits the disk at once.
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
EOF
    sudo sysctl -q -p /etc/sysctl.d/90-gaming-dev.conf
  fi

  # Bazzite: zstd zram, up to 16 GB (Fedora: lzo-rle, 8 GB). Applies after reboot.
  put_file /etc/systemd/zram-generator.conf <<'EOF' || true
[zram0]
compression-algorithm = zstd
zram-size = min(ram / 2, 16384)
EOF

  # Bazzite: keep audio devices awake, avoiding pops and clipped sound on start.
  put_file /etc/wireplumber/wireplumber.conf.d/51-disable-suspension.conf <<'EOF' || true
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_input.*" },
      { node.name = "~alsa_output.*" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF

  # Nobara: a bigger audio buffer for Wine, which stops crackling in games.
  put_file /etc/pipewire/pipewire-pulse.conf.d/wine_gaming.conf <<'EOF' || true
pulse.rules = [
    {
        matches = [ { application.process.binary = "wine64-preloader" } ]
        actions = {
            update-props = {
                pulse.min.quantum = 1024/48000
            }
        }
    }
]
EOF
fi

# 11. Snapshots before every dnf transaction (optional) --------------------
# Bazzite gets rollback from its image updates; this is the closest fit for a
# normal Fedora install. Root only: /home holds games and models, not system state.
if $SNAPSHOTS && [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
  step "Setting up system snapshots"
  need_pkgs snapper btrfs-assistant libdnf5-plugin-actions

  if sudo snapper -c root get-config >/dev/null 2>&1; then
    skip "snapper root config"
  else
    sudo snapper -c root create-config /
    sudo snapper -c root set-config \
      TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
  fi

  put_file /etc/dnf/libdnf5-plugins/actions.d/snapper.actions <<'EOF' || true
# Runs once per transaction. A failed snapshot does not block dnf.
pre_transaction:::enabled=host-only:/usr/bin/snapper -c root create -c number -d dnf-pre-transaction
EOF
  sudo systemctl enable --now snapper-cleanup.timer

  # Keep snapshots out of the plocate index.
  if ! grep -q '^PRUNENAMES' /etc/updatedb.conf; then
    echo 'PRUNENAMES = ".snapshots"' | sudo tee -a /etc/updatedb.conf >/dev/null
  fi
fi

# 12. x3d-mode helper (9950X3D cache/frequency switch) ---------------------
# Needs BIOS: CPPC Dynamic Preferred Cores = Driver.
step "Installing x3d-mode helper"

# Root-only setter: accepts exactly "cache" or "frequency", nothing else.
put_file /usr/local/libexec/x3d-mode-set 0755 <<'EOF' || true
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
case "$mode" in
  cache|frequency) ;;
  *) echo "usage: x3d-mode-set cache|frequency" >&2; exit 2 ;;
esac
shopt -s nullglob
files=(/sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode)
if (( ${#files[@]} == 0 )); then
  echo "amd_x3d_vcache driver not active (BIOS CPPC must be 'Driver')." >&2
  exit 1
fi
for f in "${files[@]}"; do echo "$mode" > "$f"; done
EOF

# Allow your user to run only that setter, only with those two values, without a password.
if x3d_nopasswd >/dev/null 2>&1; then
  skip "x3d-mode sudo rule"
else
  SUDOERS_TMP="$(mktemp)"
  cat > "$SUDOERS_TMP" <<EOF
$USER ALL=(root) NOPASSWD: /usr/local/libexec/x3d-mode-set cache, /usr/local/libexec/x3d-mode-set frequency
EOF
  if sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
    sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/x3d-mode
  else
    echo "WARNING: sudoers rule failed validation; x3d-mode will ask for your password." >&2
  fi
  rm -f "$SUDOERS_TMP"
fi

# User-facing command
put_file /usr/local/bin/x3d-mode 0755 <<'EOF' || true
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
files=(/sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode)
case "${1:-status}" in
  game|cache)    sudo -n /usr/local/libexec/x3d-mode-set cache 2>/dev/null \
                   || sudo /usr/local/libexec/x3d-mode-set cache ;;
  dev|frequency) sudo -n /usr/local/libexec/x3d-mode-set frequency 2>/dev/null \
                   || sudo /usr/local/libexec/x3d-mode-set frequency ;;
  status) ;;
  *) echo "usage: x3d-mode [game|dev|status]" >&2; exit 2 ;;
esac
if (( ${#files[@]} == 0 )); then
  echo "x3d-mode: driver not active (set BIOS CPPC Dynamic Preferred Cores = Driver)."
  exit 1
fi
echo "x3d-mode: $(cat "${files[0]}")"
EOF

# GameMode hook: cache mode while a game runs, back to frequency after.
if $GAMING; then
  GM_INI="$HOME/.config/gamemode.ini"
  mkdir -p "$HOME/.config"
  if [[ ! -f "$GM_INI" ]]; then
    cat > "$GM_INI" <<'EOF'
[custom]
start=/usr/local/bin/x3d-mode game
end=/usr/local/bin/x3d-mode dev
script_timeout=10
EOF
  elif ! grep -q 'x3d-mode game' "$GM_INI"; then
    echo "NOTE: $GM_INI exists; add these lines under [custom] yourself:"
    echo "  start=/usr/local/bin/x3d-mode game"
    echo "  end=/usr/local/bin/x3d-mode dev"
  fi
  # GameMode 1.8 only auto-detects the 7900X3D/7950X3D, so name the V-Cache CCD
  # outright: CPUs 0-7 and their SMT siblings 16-23 have the 96 MB L3.
  if ! grep -q '^\[cpu\]' "$GM_INI"; then
    cat >> "$GM_INI" <<'EOF'

[cpu]
park_cores=no
pin_cores=0-7,16-23
EOF
  fi
fi

# Make sure ~/.local/bin is on PATH for claude
if $DEV && ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# Report -------------------------------------------------------------------
step "Final state"
report
write_guide

step "Done"
echo " Instructions: $GUIDE_FILE"
echo " Check again anytime: bash $SCRIPT_PATH --check"
if $MOK_PENDING; then
  echo " Next: reboot. At the blue MOK screen: Enroll MOK > Continue > Yes > enter your password."
elif (( N_REBOOT > 0 )); then
  echo " Next: reboot to finish the items marked REBOOT above."
fi
