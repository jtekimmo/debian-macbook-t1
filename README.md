# Debian on MacBook Pro 2016 with Touch Bar (T1): MacBookPro13,2 scripts

**Debian 13 (trixie) on the MacBook Pro 13-inch 2016 with Touch Bar (MacBookPro13,2, Apple T1 chip):**
Touch Bar with F1-F12 by default, Touch ID fingerprint login, Howdy face unlock with the H.264-only
camera, Wi-Fi 2.4 GHz and 5 GHz (Broadcom BCM43602 `brcmfmac` NVRAM), power-button handling and firewall rule for
the T1 link. Scripts and small patches only; [t1bridge](https://github.com/standardagents/t1bridge),
[Howdy](https://github.com/boltgolt/howdy) and the Wi-Fi NVRAM come from their own sources
(see [THIRD_PARTY.md](THIRD_PARTY.md)).

> **Status: v0.2.0, early.** Everything was run by hand on **one** machine, a MacBookPro13,2 on kernel 7.2.x.
> `install.sh` has only been verified in simulation (`--dry-run`), not run end to end. Each fix below says how far it was
> tested; several were exercised **once**, and two cannot be shown to work until a real fingerprint enrolment is redone.

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
| Touch ID (fingerprint) | Works, with caveats | enrolled with `fprintd-enroll`, offered by PAM; see [Touch ID fixes](#touch-id-fixes-v020) for what was fixed and what is still unproven |
| Face unlock (Howdy) | Works | GStreamer fallback, the camera only gives H.264 |
| Wi-Fi 2.4 GHz and 5 GHz (BCM43602) | Works | needs the NVRAM file with your MAC and the `swctrlmap_2g` line that `install.sh` sets; **requires a reboot after install**; both bands connect in the same boot (3 rounds, and it holds after a reboot) |
| Keyboard, trackpad, battery, SMC, NVMe | Works | |
| Power button = Touch ID sensor | Handled | logind ignores the key; on Xfce also set `power-button-action` to 0 (see below) |
| Copy photos from an iPhone over USB | Works (one run) | `scripts/photos-iphone`, see below; 4154 files seen, 2643 copied, 0 errors, on the tested machine |
| Sleep / resume | **Does not work reliably** | see [Known issues](#known-issues) |
| Sound (CS8409), camera outside Howdy | Not tested | |

## Touch ID fixes (v0.2.0)

All of this was run on the one tested machine. What was **not** shown is said in each item.

1. **The broker waits for the import of Apple's machine data.** `t1-touchid-auth.service` now has `Wants=` and `After=` on
   `t1bridge-import.service` (`conf/t1bridge-after-import.conf`, a drop-in). The import takes 0.22 s (the unit run once by hand on the tested machine). `Wants=`, not
   `Requires=`: if the import fails the broker still starts. Drop-in installed and reread with `systemctl cat` after `daemon-reload` on the tested machine; **not yet checked across
   a reboot**.
2. **The broker leaves after a refused SEP lease** (`patches/t1bridge-sep-lease.patch`, for t1bridge v0.1.12). Without it,
   a lease refused with status -103 (`Cancelled`, `sep.rs:102`) left the broker running until its 30 s idle timeout
   (`auth_daemon.rs:470-490`), so the next attempt talked to a broker in a bad state. With the patch it exits with a failure once
   nothing is running, and the next attempt gets a fresh one. It was built **on the tested machine** and its unit test passed there (the test fails without the
   patch); the patched broker was then installed, checked by its sha256. **A refused lease was not provoked afterwards**, so the exit itself has not been seen
   on the real hardware.
3. **fprintd keeps the old print until the new enrolment succeeds** (`patches/fprintd-keep-print.patch`, for fprintd 1.94.5,
   commit `b54a007`). Upstream deletes the existing print of the same finger *before* the enrolment starts
   (`src/device.c`), so a failed enrolment left the finger erased: this happened on the tested machine (a left index finger
   was lost that way). The patch deletes it in `enroll_cb`, only after a successful enrolment. It was built on the tested machine and installed (sha256 checked); the daemon starts
   with it and `fprintd-list` still shows the remaining print; **the case it exists for (re-enrolling a finger that is already enrolled, then failing or succeeding) has not been
   tested yet**. If the T1 itself refuses a duplicate, the enrolment fails and the old print stays.
4. **Power button.** The Touch ID sensor is the power button. logind ignoring it (`conf/90-touchid-power-key.conf`) was not enough: on
   Xfce, `xfce4-power-manager` itself turned the machine off during a fingerprint enrolment. Per user:
   ```sh
   xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/power-button-action -n -t int -s 0   # 0 = do nothing
   ```
   Set and read back as 0 on the tested machine; the enrolment that shut the machine down has not been repeated since.
5. **Optional debug log of fprintd** (`conf/fprintd-debug.conf`, `install.sh --fprintd-debug`): sets `G_MESSAGES_DEBUG=all`
   for `fprintd.service`. It only exists to find the cause below; remove it afterwards. The daemon start was seen in the journal with the
   debug lines, on the tested machine.
6. **iBridge USB rule.** Debian's `usbmuxd` rule would put the T1 iBridge in USB configuration 0 (Touch Bar and camera
   interfaces gone). `conf/39-usbmuxd-sans-ibridge.rules` is a copy without the iBridge; `install.sh` puts it in
   `/etc/udev/rules.d/`. The loss of the interfaces with Debian's rule was measured on the tested machine; the copy without the iBridge is the one in use there.

**Cause of the failed enrolments: not proven.** On the tested machine fingerprint enrolments failed with `sep-lease` status
-103 several times in a day. Nothing in the journal shows who cancelled the lease (no timeout, no service stop). The most
likely candidate is a client-side cancellation, but that is a guess; the debug log above is meant to settle it at the next enrolment.

## Face unlock that retries (pam-any)

Optional, **not run by `install.sh`**. The default PAM stack tries the face (Howdy) and only afterwards the fingerprint, so the finger is
not read while the camera works. [pam-any](https://github.com/ChocolateLoverRaj/pam-any) runs the face, the fingerprint and the
password sub-stacks at the same time; the first that succeeds wins. `patches/pam-any-retry.patch` (for commit `c239b82d48b0`, upstream
PR #17) adds: the prompt is read by the module on a terminal and withdrawn when the face or the finger wins, losing sub-stacks are
stopped before returning, and the option `"retry_secs": 30`, which silently relaunches the face sub-stack for up to 30 s, **only for
the services listed in `"retry_services"` (here `lightdm`)**; sudo, su, polkit and the screen locker get a single face attempt and the
password can be typed at once. Files: `conf/pam-any/` (three sub-stacks and a `pam-auth-update` profile).

Measured on the tested MacBookPro13,2, with the PAM stacks **replayed by hand with nobody in front of the machine**
(not through the real screens): under `xfce4-screensaver`, one silent face attempt and the password prompt at 7.0 s (Howdy's 5 s timeout
plus opening the camera; not under 6 s); a real `sudo`, the password prompt at 0.0 s; `lightdm`, 5 retries and the prompt at
34.7 s, no message shown. **Not yet seen on the real login screen (LightDM) or the real screen saver.** You build pam-any
yourself (`cargo build --release --locked`) and adjust the path of `pam_howdy.so` in `conf/pam-any/pam-any-howdy`.

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
| `--t1bridge-src DIR` | apply the F1-F12 patch and the SEP-lease patch to a t1bridge v0.1.12 source tree (you build and install t1bridge yourself, following its documentation) |
| `--fprintd-src DIR` | apply the keep-print patch to an fprintd 1.94.5 source tree (commit `b54a007`); you build and install it yourself, and hold `fprintd` and `libfprint-2-2` in apt so an upgrade does not replace it |
| `--fprintd-debug` | optional debug-log drop-in for fprintd (see above) |
| `--rename-owner OLD NEW` | re-attach an enrolled fingerprint to another Linux account |

What it sets up:

1. Packages: `gstreamer1.0-plugins-good/-bad/-libav`, `firmware-brcm80211`, `curl`, `patch`.
2. `/etc/modprobe.d/t1bridge.conf` and `/etc/modules-load.d/t1bridge.conf`: keep the legacy
   iBridge HID drivers away from t1bridge, load `t1_cfgsel`.
3. F1-F12 patch and SEP-lease patch for the t1bridge sources (if `--t1bridge-src`); drop-in `after-import.conf` for
   `t1-touchid-auth.service`; keep-print patch for the fprintd sources (if `--fprintd-src`); debug drop-in (if `--fprintd-debug`).
4. Howdy GStreamer fallback, applied to any installed `recorders/video_capture.py`.
5. `logind` drop-in `HandlePowerKey=ignore`, `HandlePowerKeyLongPress=ignore`: the Touch ID
   sensor **is** the power button, a touch to authenticate must not power the machine off.
6. `/etc/udev/rules.d/39-usbmuxd.rules`: the usbmuxd rule without the iBridge (Touch ID fixes, item 6).
   `ufw`: `61500/tcp` allowed from `fe80::/10`, **only** on the interface of the `apple_t1_ncm`
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
`/etc/udev/rules.d/` without the iBridge product, so the phones still use usbmuxd and the Touch Bar is left alone (`install.sh` now does this).

Status: run once on the tested MacBookPro13,2 against one iPhone (4154 files seen, 2643 copied, 1511 skipped, 0 errors); Cancel,
name collisions and the progress bar were rehearsed on fake data. The messages of the tool are in French.

## Known issues

- **Wi-Fi:** 2.4 GHz and 5 GHz both connect on the tested machine (see the table). It needs the NVRAM file and a reboot after install.
- **Sleep / resume does not work reliably.** A few early tries woke up, with errors at resume (the Touch Bar driver returning `-74`, PCIe /
  Thunderbolt errors); those were not systematically measured. The last try, with a sleep hook that unloaded and reloaded the Wi-Fi
  driver (`rtcwake -m mem -s 40`): the machine **never woke up** (neither the RTC nor a key), and had to be powered off; the journal of
  that boot stops at the start of the suspend, with no trace of the hook. The hook was removed. **Cause not found.**
  A USB-C Ethernet adapter was plugged in during that try; that it is the cause is a **hypothesis, not proven** (no try was made
  without it). Setting `d3cold_allowed=0` on the PCIe bridges prevented waking up in an earlier test: **do not do it** (only the NVMe
  rule is applied). Do not rely on suspend; only one wake-up was tried per configuration listed here.
- **Fingerprint enrolment** can fail with `sep-lease` -103; the cause is **not proven** (see above). Enrol with a fresh broker (after
  `t1bridge-import.service`), and check `fprintd-list <user>` afterwards.
- **Sound (CS8409)** and the camera outside Howdy: not tested.
- Everything else in this repository was verified on **one** machine, a MacBookPro13,2.

## Notes

- The T1 must be in configuration 2 (t1bridge does it with `t1_cfgsel`); the switch takes a reboot.
- macOS's EFI partition must stay: it holds the T1 firmware that t1bridge imports.
- Back out: remove the files `install.sh` printed, uninstall t1bridge, reboot.

## Changes followed from the source scripts

<!-- mac-github:start -->
Written automatically each time the source scripts change something for the MacBook Pro. Messages are copied from the commits of the source scripts (in French). A change listed here is not proof that it was tested on a Mac: see the table above and Known issues.

| Release | Date | Source tag | What changed (messages of the source commits) | Files |
|---|---|---|---|---|
| v0.3.0 | 2026-11-08 | v2.122 | Mac, couvercle ferme = arret sur batterie seulement, ecran eteint sur secteur | `scripts/mac-power-settings.sh` |
<!-- mac-github:end -->

## Licence

MIT, see [LICENSE](LICENSE). Third-party licences: [THIRD_PARTY.md](THIRD_PARTY.md).
