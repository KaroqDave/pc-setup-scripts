# PC setup scripts

Quick setup scripts for a fresh install. Each one checks what is already done
and only does what is missing, so it is safe to re-run.

| Folder | System | What it sets up |
|---|---|---|
| [`fedora/`](fedora/) | Fedora 44/45 KDE | NVIDIA + CUDA, codecs, dev tools, AI coding CLIs, gaming tools, system tuning, Btrfs snapshots |
| [`windows/`](windows/) | Windows 10/11 | Windows updates, NVIDIA/AMD GPU driver, AMD chipset driver, ASUS mainboard drivers, game runtimes, Steam, Battle.net, more launchers, tools and dev tools by flag, gaming settings |

## Download

Every version is on the [Releases](../../releases) page:

- `fedora-setup-vX.Y.Z.tar.gz`: unpack with `tar xzf`, then `bash fedora-setup.sh`
- `windows-setup-vX.Y.Z.zip`: unzip on the PC, then double-click `windows-setup.cmd`
- `SHA256SUMS.txt`: checksums of both archives

New release: `git tag v1.2.0 && git push origin v1.2.0`. A GitHub Action
builds the archives and publishes the release.

## Fedora

Run as your normal user, not root (it asks for your sudo password).

```bash
bash fedora/fedora-setup.sh --check              # look only
bash fedora/fedora-setup.sh                      # set up
bash fedora/fedora-setup.sh --no-gaming --lact   # skip gaming, add LACT
```

| Flag | What it does |
|---|---|
| `--check` | Show what is installed and active, change nothing (no sudo needed) |
| `--guide` | Only write the guide (no sudo needed) |
| `--no-update` | Skip the full `dnf upgrade` at the start |
| `--no-dev` | Skip dev tools: compilers, Git, Python, Node.js, Rust, VS Code, Cursor, Claude Code, OpenCode, Codex CLI, Distrobox |
| `--no-gaming` | Skip gaming: Steam, GameMode, MangoHud, gamescope, Lutris, Heroic, ProtonUp-Qt, dlss-swapper and the shader/DLSS setup |
| `--no-tuning` | Skip system tuning: sysctl, zram, audio fixes, firewall, monthly Btrfs check |
| `--no-snapshots` | Skip snapper and the snapshot before every dnf transaction |
| `--sunshine` | Also install Sunshine (stream games to Moonlight) |
| `--lact` | Also install LACT (GPU fan curves, power limit, clocks) |

Everything is on by default except `--sunshine` and `--lact`. Details:
`fedora/README.txt`; the full guide is `fedora/fedora-setup-guide.txt`.

## Windows

Copy the `windows` folder to the PC and double-click `windows-setup.cmd`, or run
it from a terminal in that folder with flags:

```bat
windows-setup.cmd -check              :: look only
windows-setup.cmd                     :: set up
windows-setup.cmd -gaming -tuning     :: plus more launchers and tuning tools
```

| Flag | What it does |
|---|---|
| `-check` | Show what is installed and active, change nothing (no admin needed) |
| `-guide` | Only write the guide (no admin needed) |
| `-noupdate` | Skip Windows Update |
| `-nodrivers` | Skip the GPU, chipset and mainboard drivers |
| `-noapps` | Skip runtimes and launchers |
| `-notweaks` | Skip the gaming settings |
| `-gaming` | Also install Epic Games, EA app, Ubisoft Connect, GOG Galaxy |
| `-tuning` | Also install MSI Afterburner + RivaTuner, HWiNFO, CPU-Z, GPU-Z |
| `-riot` | Also install Valorant, League of Legends |
| `-other` | Also install Display Driver Uninstaller, OBS Studio |
| `-dev` | Also install Git, GitHub CLI, VS Code, Cursor, PowerShell 7, Python, Node.js, Rust with the C++ Build Tools, CMake, Ninja, ripgrep, fd, jq, Claude Code, OpenCode, Codex CLI |
| `-all` | All of the "also install" flags above |

Always installed: Windows updates, GPU and chipset drivers, ASUS mainboard
drivers, game runtimes, 7-Zip, Steam, Battle.net and the gaming settings.
`-dev` is roughly the Windows side of the Fedora dev setup; WSL is left out on
purpose (see the guide). Details: `windows/README.txt`; the full guide
(`windows-setup-guide.txt`) is written on the first run.

### ASUS mainboard drivers

Windows Update often has no drivers for the board, so on ASUS boards the script
gets them straight from ASUS. No DriverHub or Armoury Crate needed.

- **Source:** the same driver list your board's ASUS support page shows. The
  script looks up the model Windows reports.
- **What it installs:** LAN, Wi-Fi, Bluetooth, audio and USB-C drivers. For each
  driver it takes only the newest package and checks the download against the
  SHA-256 checksum that ASUS publishes.
- **Only what fits:** each ASUS package lists the hardware it is for. The
  script installs a package only if that hardware is in the PC and the installed
  driver is older or Windows' generic one. For example, if a board can come
  with Realtek or MediaTek Wi-Fi, only the chip you have gets a driver.
- **How:** silently, with ASUS's own install command from the package.
- **Left out:** chipset (installed from AMD directly, which is newer), the GPU
  driver for the CPU's built-in graphics, BIOS, RAID, and utilities such as
  Armoury Crate.
- **Re-runs:** every package handled is recorded in `asus-drivers.txt` next to
  the script. Later runs and `-check` only look at packages ASUS has added
  since. Failed installs are retried. Delete a line there to make the script
  look at that package again.
- **First run:** downloads about 300 MB once. Each package is deleted after it's
  handled.

Other board makers (MSI, Gigabyte, ASRock) have no public driver list, so the
script links to the board's support page instead.

## Files the scripts create

Each script writes its own files only into its own folder:

| Script | Files |
|---|---|
| Fedora | `fedora-setup-guide.txt`: the guide, with the `--check` report at the end |
| Windows | `windows-setup-guide.txt`: the guide, with the `-check` report at the end<br>`windows-setup.log`: everything the last run printed<br>`asus-drivers.txt`: the ASUS packages already handled<br>`downloads\`: installers during a run, deleted at the end |

Outside their folders they only change what they are meant to set up: system
settings, installed apps and drivers. The Windows script needs about 3 GB free in
its folder during a run (the NVIDIA driver package is unpacked there). If you run it
from a USB stick, those downloads go to the stick.
Both guides are refreshed at the end of every run, or on demand with `--guide`
(Fedora) and `-guide` (Windows).
