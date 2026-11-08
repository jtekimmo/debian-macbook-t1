# Debian on MacBook Pro 2016 with Touch Bar (T1): MacBookPro13,2 scripts

**Debian 13 (trixie) on the MacBook Pro 13-inch 2016 with Touch Bar (MacBookPro13,2, Apple T1 chip):**
Touch Bar with F1-F12 by default, Touch ID fingerprint login, Howdy face unlock with the H.264-only
camera, Wi-Fi 2.4 GHz and 5 GHz (Broadcom BCM43602 `brcmfmac` NVRAM), power-button handling and firewall rule for
the T1 link. Scripts and small patches only; [t1bridge](https://github.com/standardagents/t1bridge),
[Howdy](https://github.com/boltgolt/howdy) and the Wi-Fi NVRAM come from their own sources
(see [THIRD_PARTY.md](THIRD_PARTY.md)).

> **Status: v0.1.0, early.** Everything was run by hand on **one** machine, a MacBookPro13,2 on kernel 7.2.x.
> `install.sh` has only been verified in simulation (`--dry-run`), not run end to end.

## Which models

| Model | Status |
|---|---|
| **MacBookPro13,2** (13-inch 2016, Touch Bar) | **Tested** (the only one) |
| MacBookPro13,3 (15-inch 2016) | Probably compatible, **not tested** |
| MacBookPro14,2 (13-inch 2017, Touch Bar) | Probably compatible, **not tested** |
| MacBookPro14,3 (15-inch 2017) | Probably compatible, **not tested** |

`install.sh` refuses other models unless you pass `--force`.

## What works and what does not (MacBookPro13,2)

| Feature | Status | Notes |
|---|---|---|
| Touch Bar, F1-F12 by default | Works | t1bridge v0.1.12 + patch; Fn gives brightness / volume / media |
| Touch ID (fingerprint) | Works | enrolled with `fprintd-enroll`, offered by PAM |
| Face unlock (Howdy) | Works | GStreamer fallback, the camera only gives H.264 |
| Wi-Fi 2.4 GHz and 5 GHz (BCM43602) | Works | needs the NVRAM file with your MAC and the `swctrlmap_2g` line that `install.sh` sets; **requires a reboot after install**; both bands connect in the same boot (3 rounds, and it holds after a reboot) |
| Keyboard, trackpad, battery, SMC, NVMe | Works | |
| Power button = Touch ID sensor | Handled | logind ignores the key |
| Copy photos from an iPhone over USB | Works (one run) | `scripts/photos-iphone`, see below; 4154 files seen, 2643 copied, 0 errors, on the tested machine |
| Sleep / resume | **Known issue**, being tested | after a wake-up the 5 GHz band is lost until a reboot. Setting `d3cold_allowed=0` on the PCIe bridges prevents the wake-up: **do not do it** (only the NVMe rule is applied) |
| Sound (CS8409), camera outside Howdy | Not tested | |

## Install

```sh
git clone <this repository> && cd debian-macbook-t1
sudo ./install.sh --dry-run          # shows what would change
sudo ./install.sh --wifi-mac AA:BB:CC:DD:EE:FF --t1bridge-src /path/to/t1bridge
```

`install.sh` is written to be idempotent (run it again, it only changes what differs), but it has **only been verified in `--dry-run`** so far. Options:

| Option | Effect |
|---|---|
| `--dry-run` | print the changes, touch nothing |
| `--force` | go on even if the DMI model is not MacBookPro13,2 |
| `--wifi-mac MAC` | fetch the BCM43602 NVRAM, verify its sha256, write your MAC in and set the `swctrlmap_2g` line (read it from macOS with `ifconfig en0 | grep ether`) |
| `--t1bridge-src DIR` | apply the F1-F12 patch to a t1bridge v0.1.12 source tree (you build and install t1bridge yourself, following its documentation) |
| `--rename-owner OLD NEW` | re-attach an enrolled fingerprint to another Linux account |

What it sets up:

1. Packages: `gstreamer1.0-plugins-good/-bad/-libav`, `firmware-brcm80211`, `curl`, `patch`.
2. `/etc/modprobe.d/t1bridge.conf` and `/etc/modules-load.d/t1bridge.conf`: keep the legacy
   iBridge HID drivers away from t1bridge, load `t1_cfgsel`.
3. F1-F12 patch for the t1bridge sources (if `--t1bridge-src`).
4. Howdy GStreamer fallback, applied to any installed `recorders/video_capture.py`.
5. `logind` drop-in `HandlePowerKey=ignore`, `HandlePowerKeyLongPress=ignore`: the Touch ID
   sensor **is** the power button, a touch to authenticate must not power the machine off.
6. `ufw`: `61500/tcp` allowed from `fe80::/10`, **only** on the interface of the `apple_t1_ncm`
   driver (the private link to the T1, needed by xART / Touch ID). Skipped until that link exists.
7. udev rule: `d3cold_allowed=0` for the Apple NVMe (`0000:01:00.0`).
8. Wi-Fi NVRAM as above (2.4 and 5 GHz; reboot afterwards).
9. Fingerprint owner rename (`scripts/rename-fingerprint-owner.sh`): the owner name is stored
   in two places (t1bridge `identities.meta`, and the libfprint `FP3` print). The script
   edits both after a backup and restores it if its final check fails. It was run once by hand;
   the parametrised version in this repository was not re-run as is.

## Copy photos from an iPhone (USB)

`scripts/photos-iphone` copies the photos and videos of an iPhone into a folder, one click, no service and no udev rule
of its own. It mounts the phone with `ifuse` (usbmuxd, libimobiledevice), reads `DCIM`, and for each file:

- computes its md5 and **skips** it when that md5 is already known (the md5 list of your cloud folder read with
  `rclone md5sum`, plus a local cache updated on every run), so nothing is stored twice;
- names the copy `YYYY/YYYYMMDD_HHMMSS.ext` from the date taken (EXIF `DateTimeOriginal`; for a video, the QuickTime
  creation date), keeps `.heic` and `.mov` as they are, and adds `_1`, `_2` when a name is already taken on the disk **or**
  in the cloud folder with different content (it never overwrites);
- never deletes anything from the phone, always unmounts (also on Cancel), and shows a progress bar
  (pairing, mount, cloud list, reading, N of total) and a summary (copied, skipped, errors).

Install (Debian 13):

```sh
sudo apt install $(grep -v '^#' conf/photos-iphone.packages)
sudo install -m 755 scripts/photos-iphone /usr/local/bin/photos-iphone
sudo install -m 644 conf/photos-iphone.desktop /usr/share/applications/photos-iphone.desktop
```

Then start **Photos iPhone** from the application menu. The first time, unlock the phone and tap **Trust** when it asks
"Trust this computer?". Settings, optional, in `~/.config/photos-iphone.conf` (shell syntax):

| Variable | Default | Meaning |
|---|---|---|
| `PI_DEST` | `~/google/Foto/camera` | destination folder; the year folders go inside |
| `PI_RCLONE_REMOTE` | empty | rclone remote and folder holding your photos, e.g. `mydrive:Foto/camera`; empty = only the local cache |

On a T1 MacBook, Debian's `usbmuxd` udev rule (`39-usbmuxd.rules`) also matches the iBridge (`05ac:8600`) and puts it in
USB configuration 0, which removes the Touch Bar and camera interfaces (measured on the tested machine). Keep a copy of the rule in
`/etc/udev/rules.d/` without the iBridge product, so the phones still use usbmuxd and the Touch Bar is left alone.

Status: run once on the tested MacBookPro13,2 against one iPhone (4154 files seen, 2643 copied, 1511 skipped, 0 errors); Cancel,
name collisions and the progress bar were rehearsed on fake data. The messages of the tool are in French.

## Notes

- The T1 must be in configuration 2 (t1bridge does it with `t1_cfgsel`); the switch takes a reboot.
- macOS's EFI partition must stay: it holds the T1 firmware that t1bridge imports.
- Back out: remove the files `install.sh` printed, uninstall t1bridge, reboot.

## Licence

MIT, see [LICENSE](LICENSE). Third-party licences: [THIRD_PARTY.md](THIRD_PARTY.md).
