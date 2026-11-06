FEDORA SETUP

1. Run it as your normal user, not root (it asks for your sudo password):
     bash fedora-setup.sh
2. Reboot when it says so. With an NVIDIA card and Secure Boot on, the first
   reboot shows a blue MOK screen: Enroll MOK > Continue > Yes > the password
   you set.
3. Run it once more to check that everything is in place.

Always installed: system update, RPM Fusion, full codecs, and the graphics
stack for the card it finds:
  NVIDIA   driver + CUDA (with a Secure Boot signing key if Secure Boot is on)
           and NVIDIA video acceleration
  AMD      Mesa (RADV Vulkan) with RPM Fusion's full-codec video acceleration,
           and the ROCm runtime (HIP, OpenCL) for local AI tools. No Secure
           Boot key is needed: the driver is part of Fedora's kernel.
On a two-CCD Ryzen X3D (7900X3D, 7950X3D, 9900X3D, 9950X3D) it also adds the
x3d-mode helper (cache/frequency switch) and hooks it into GameMode.

On by default, each one can be skipped with its flag:
  Dev tools (--no-dev)
    compilers, Git, Python, Node.js, Rust, VS Code, Cursor, Claude Code,
    OpenCode, Codex CLI, Distrobox
  Gaming (--no-gaming)
    Steam, GameMode, MangoHud, gamescope, Lutris, GOverlay, Heroic,
    ProtonUp-Qt, Protontricks, GPU Screen Recorder, ntsync, 16 GB shader
    cache, and dlss-swapper on NVIDIA
  Tuning (--no-tuning)
    BBR, zstd zram, audio fixes, monthly Btrfs check, tighter firewall,
    faster dnf downloads
  Snapshots (--no-snapshots)
    a snapshot before every dnf transaction (snapper), Btrfs Assistant

Optional extras with flags (combine freely):
  bash fedora-setup.sh --sunshine   Sunshine: stream games to Moonlight clients
  bash fedora-setup.sh --lact       LACT: GPU fan curves, power limit, clocks
  bash fedora-setup.sh --sunshine --lact

Only look, change nothing:   bash fedora-setup.sh --check
Skip parts:                  --no-update  --no-dev  --no-gaming
                             --no-tuning  --no-snapshots

Files the script writes, all in this folder:
  fedora-setup-guide.txt    the guide: Steam launch options, GameMode and X3D,
                            MangoHud, DLSS or FSR, Proton, snapshots, driver
                            updates, settings changed and how to undo them,
                            and at the end the same report as --check.
                            Refreshed after every run, or on its own with:
                              bash fedora-setup.sh --guide
Outside this folder it only writes the system settings it sets up (/etc,
~/.config, /usr/local/bin). Section 14 of the guide lists each file.
