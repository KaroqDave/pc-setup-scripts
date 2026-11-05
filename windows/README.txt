WINDOWS GAMING SETUP

1. Copy this folder to the Windows PC (USB stick is fine).
2. Double-click windows-gaming-setup.cmd and confirm the admin prompt.
3. Reboot when it says so, then run it once more.

Always installed: Windows updates, GPU driver (NVIDIA/AMD), AMD chipset driver,
ASUS mainboard drivers (only those for your hardware), game runtimes, 7-Zip,
Steam, Battle.net, gaming settings.

More apps with flags (run from a terminal in this folder, combine freely):
  windows-gaming-setup.cmd -Gaming    Epic Games, EA app, Ubisoft Connect, GOG Galaxy
  windows-gaming-setup.cmd -Tuning    MSI Afterburner + RivaTuner, HWiNFO, CPU-Z, GPU-Z
  windows-gaming-setup.cmd -Riot      Valorant, League of Legends
  windows-gaming-setup.cmd -Other     Display Driver Uninstaller, OBS Studio
  windows-gaming-setup.cmd -All       all of the above
  windows-gaming-setup.cmd -Gaming -Tuning

Only look, change nothing:   windows-gaming-setup.cmd -Check
Skip parts:                  -NoUpdate  -NoDrivers  -NoApps  -NoTweaks
The app list is at the top of windows-gaming-setup.ps1 and easy to edit.

After the first run, windows-gaming-guide.txt explains every step, the BIOS
checklist, the settings it changed and how to undo them.
