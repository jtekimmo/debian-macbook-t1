# debian-macbook-t1

Scripts and small patches that make a **MacBookPro13,2** (2016 13-inch with Touch Bar,
Apple **T1** chip, PCI Wi-Fi BCM43602) work under **Debian 13 (trixie)**.
Everything here was run by hand on one machine of that model, with kernel 7.2.x;
nothing is claimed for other models.

This repository holds scripts and patches only. t1bridge, Howdy and the Wi-Fi NVRAM are
fetched from their own sources (see [THIRD_PARTY.md](THIRD_PARTY.md)).

## What works (measured on the machine)

- **Touch Bar** through [t1bridge](https://github.com/standardagents/t1bridge) v0.1.12:
  Esc + F1-F12 shown **by default**, brightness / volume / media while Fn is held
  (patch in `patches/`; the t1bridge test suite passes with it: 95 tests).
- **Touch ID** (enrolled with `fprintd-enroll`, offered by PAM next to face and password).
- **Face unlock with Howdy**: the built-in camera only delivers H.264, so V4L2 cannot read
  it; the patch adds a GStreamer fallback (a 720x1280 frame in under a second).
- **Wi-Fi 5 GHz** (BCM43602) once a NVRAM file carrying the card's own MAC is installed.
- Keyboard and trackpad (applespi), battery and SMC, NVMe disk.

## Known issues (under test, no conclusion yet)

- **Wi-Fi 2.4 GHz**: networks are seen but the association does not complete (the 4-way
  handshake fails with the NVRAM above). The same symptom is reported in the kernel bugzilla
  thread that holds the NVRAM attachment. Tests are in progress; nothing here fixes it.
- **Sleep / resume**: not reliable yet. Tests are in progress (PCIe D3cold on bridges, Thunderbolt and
  Wi-Fi). Only the NVMe D3cold rule is applied by `install.sh`.
- Sound (Cirrus CS8409) and the camera outside Howdy were not part of these tests.

## Install

```sh
git clone <this repository> && cd debian-macbook-t1
sudo ./install.sh --dry-run          # shows what would change
sudo ./install.sh --wifi-mac AA:BB:CC:DD:EE:FF --t1bridge-src /path/to/t1bridge
```

`install.sh` is idempotent (run it again, it only changes what differs). Options:

| Option | Effect |
|---|---|
| `--dry-run` | print the changes, touch nothing |
| `--force` | go on even if the DMI model is not MacBookPro13,2 |
| `--wifi-mac MAC` | fetch the BCM43602 NVRAM, verify its sha256, write your MAC in (read it from macOS with `ifconfig en0 | grep ether`) |
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
8. Wi-Fi NVRAM as above.
9. Fingerprint owner rename (`scripts/rename-fingerprint-owner.sh`): the owner name is stored
   in two places (t1bridge `identities.meta`, and the libfprint `FP3` print). The script
   edits both after a backup and restores it if its final check fails. It was run once by hand;
   the parametrised version in this repository was not re-run as is.

## Notes

- The T1 must be in configuration 2 (t1bridge does it with `t1_cfgsel`); the switch takes a reboot.
- macOS's EFI partition must stay: it holds the T1 firmware that t1bridge imports.
- Back out: remove the files `install.sh` printed, uninstall t1bridge, reboot.

## Licence

MIT, see [LICENSE](LICENSE). Third-party licences: [THIRD_PARTY.md](THIRD_PARTY.md).
