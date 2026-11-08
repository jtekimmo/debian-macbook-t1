# Third-party pieces

Nothing below is copied wholesale into this repository except small patches
and a few small configuration files, each derived from a project with its own licence
(MIT and Apache-2.0 permit this with the notice kept; a patch to GPL code follows the GPL). Licences were read at the source.

| Piece | Origin | Licence | What this repository holds |
|---|---|---|---|
| t1bridge v0.1.12 | https://github.com/standardagents/t1bridge (tag `v0.1.12`) | MIT, "Copyright (c) 2026 T1Bridge contributors" (`LICENSE` at the tag) | Patches for its sources (`patches/t1bridge-touchbar-fkeys.patch`, `patches/t1bridge-sep-lease.patch`) and two configuration files taken from its packaging (`conf/t1bridge.*.conf`). Not t1bridge itself: get it from the link above. |
| Howdy | https://github.com/boltgolt/howdy | MIT, "Copyright (c) 2018 boltgolt" | A patch for `recorders/video_capture.py` (`patches/howdy-gstreamer.patch`). Not Howdy itself. |
| Broadcom BCM43602 NVRAM | https://bugzilla.kernel.org/attachment.cgi?id=29%30569 (kernel bugzilla, the Broadcom 43602 bug this attachment belongs to, the version with both bands working on a MacBookPro13,2) | None stated at the source | Nothing. `install.sh` downloads it, checks its sha256, writes your own Wi-Fi MAC into it and sets one line (`swctrlmap_2g`). |
| fprintd 1.94.5 (commit `b54a007`) | https://gitlab.freedesktop.org/libfprint/fprintd | GPL-2.0-or-later (see `COPYING` at the commit) | A patch (`patches/fprintd-keep-print.patch`), which follows the licence of the code it patches. Not fprintd itself. |
| pam-any (commit `c239b82d48b0`) | https://github.com/ChocolateLoverRaj/pam-any | Apache-2.0 (`LICENSE` of the repository) | A patch (`patches/pam-any-retry.patch`) that modifies `src/lib.rs`, `build.rs` and `Cargo.toml`/`Cargo.lock`; the changes are marked in the patch. Not pam-any itself. |
| usbmuxd udev rule | Debian package `usbmuxd` 1.1.1-6+deb13u1 (`/lib/udev/rules.d/39-usbmuxd.rules`) | that of the package (see its copyright file) | `conf/39-usbmuxd-sans-ibridge.rules`: a copy of the rule without the Apple iBridge product, header rewritten. |

## Getting the pieces yourself

```sh
git clone --branch v0.1.12 https://github.com/standardagents/t1bridge.git
git clone https://github.com/boltgolt/howdy.git
git clone https://gitlab.freedesktop.org/libfprint/fprintd.git && git -C fprintd checkout b54a007
git clone https://github.com/ChocolateLoverRaj/pam-any.git && git -C pam-any checkout c239b82d48b0
curl -fsSL -o brcmfmac43602-pcie.txt 'https://bugzilla.kernel.org/attachment.cgi?id=29%30569'
```

## MIT notices that must travel with the patches

t1bridge: MIT License, Copyright (c) 2026 T1Bridge contributors.
Howdy: MIT License, Copyright (c) 2018 boltgolt.
The full MIT text is in `LICENSE` (same wording).
