# PC setup scripts

Quick setup scripts for a fresh install. Each one checks what is already done
and only does what is missing, so it is safe to re-run.

| Folder | System | What it sets up |
|---|---|---|
| [`fedora/`](fedora/) | Fedora 44/45 KDE | NVIDIA + CUDA, codecs, dev tools, AI coding CLIs, gaming tools, system tuning, Btrfs snapshots |
| [`windows/`](windows/) | Windows 10/11 | Windows updates, NVIDIA/AMD GPU driver, AMD chipset driver, ASUS mainboard drivers, game runtimes, Steam, Battle.net, more launchers and tools by flag, gaming settings |

## Fedora

```bash
bash fedora/fedora-dev-ai-setup.sh --check   # look only
bash fedora/fedora-dev-ai-setup.sh           # set up
```

Options and details: top of `fedora/fedora-dev-ai-setup.sh` and `fedora/fedora-setup-guide.txt`.

## Windows

Copy the `windows` folder to the PC and double-click `windows-gaming-setup.cmd`.

```bat
windows-gaming-setup.cmd -Check              :: look only
windows-gaming-setup.cmd -Gaming -Tuning     :: plus Epic/EA/Ubisoft/GOG and Afterburner/HWiNFO/CPU-Z/GPU-Z
```

App flags: `-Gaming`, `-Tuning`, `-Riot`, `-Other`, `-All`. Details: `windows/README.txt`;
the full guide (`windows-gaming-guide.txt`) is written on the first run.
