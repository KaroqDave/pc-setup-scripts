WINDOWS SETUP

1. Copy this folder to the Windows PC (USB stick is fine).
2. Double-click windows-setup.cmd and confirm the admin prompt.
3. Reboot when it says so, then run it once more.

Always installed: Windows updates, GPU driver (NVIDIA/AMD), AMD chipset driver,
ASUS mainboard drivers (only those for your hardware), game runtimes, 7-Zip,
Steam, Battle.net. Everything is compared with the newest version first: only
what is missing or outdated gets installed.

ASUS boards: the mainboard drivers (LAN, Wi-Fi, Bluetooth, audio, USB-C) come
straight from your board's ASUS support page, no DriverHub needed. Only the
packages for the hardware in your PC are installed, and only when they are
newer. Other boards: the script shows the support page link.

More apps with flags (run from a terminal in this folder, combine freely):
  windows-setup.cmd -gaming    Epic Games, EA app, Ubisoft Connect, GOG Galaxy
  windows-setup.cmd -tuning    MSI Afterburner + RivaTuner, HWiNFO, CPU-Z, GPU-Z
  windows-setup.cmd -riot      Valorant, League of Legends
  windows-setup.cmd -other     Display Driver Uninstaller, OBS Studio
  windows-setup.cmd -dev       dev tools: Git, GitHub CLI, VS Code, Cursor,
                               PowerShell 7, Python, Node.js, Rust + C++ Build
                               Tools, CMake, Ninja, ripgrep, fd, jq, Claude Code,
                               OpenCode, Codex CLI
  windows-setup.cmd -all       all of the above
  windows-setup.cmd -gaming -tuning

Only look, change nothing:   windows-setup.cmd -check
                             (OK, UPDATE = newer version exists, MISSING)
Gaming settings:             windows-setup.cmd -tweaks   (off by default)
Skip parts:                  -noupdate  -nodrivers  -noapps
The app list is at the top of windows-setup.ps1 and easy to edit.

Files the script writes, all in this folder:
  windows-setup-guide.txt   the guide: every step, BIOS checklist, settings
                            changed and how to undo them, and at the end the
                            same report as -check. Refreshed after every run,
                            or on its own with: windows-setup.cmd -guide
  windows-setup.log         everything the last run printed
  downloads\                installers during a run, deleted at the end
                            (needs about 3 GB free while running)
