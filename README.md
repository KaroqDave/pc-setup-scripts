# PC setup scripts

Quick setup scripts for a fresh install. Each one checks what is already done
and only does what is missing, so it is safe to re-run.

| Folder | System | What it sets up |
|---|---|---|
| [`fedora/`](fedora/) | Fedora 44/45 KDE | NVIDIA + CUDA, codecs, dev tools, AI coding CLIs, gaming tools, system tuning, Btrfs snapshots |
| [`windows/`](windows/) | Windows 10/11 | Windows updates, NVIDIA/AMD GPU driver, AMD chipset driver, ASUS mainboard drivers, game runtimes, Steam, Battle.net, more launchers and tools by flag, gaming settings |

## Fedora

```bash
bash fedora/fedora-setup.sh --check   # look only
bash fedora/fedora-setup.sh           # set up
```

Options and details: top of `fedora/fedora-setup.sh` and `fedora/fedora-setup-guide.txt`.

## Windows

Copy the `windows` folder to the PC and double-click `windows-setup.cmd`.

```bat
windows-setup.cmd -check              :: look only
windows-setup.cmd -gaming -tuning     :: plus Epic/EA/Ubisoft/GOG and Afterburner/HWiNFO/CPU-Z/GPU-Z
```

App flags: `-gaming`, `-tuning`, `-riot`, `-other`, `-all`. Details: `windows/README.txt`;
the full guide (`windows-setup-guide.txt`) is written on the first run.

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
