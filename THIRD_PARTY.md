# Third-party pieces

Nothing below is copied wholesale into this repository except two small patches
and two one-line configuration files, all derived from MIT-licensed projects
(MIT permits this, with the notice kept). Licences were read at the source.

| Piece | Origin | Licence | What this repository holds |
|---|---|---|---|
| t1bridge v0.1.12 | https://github.com/standardagents/t1bridge (tag `v0.1.12`) | MIT, "Copyright (c) 2026 T1Bridge contributors" (`LICENSE` at the tag) | A patch for its sources (`patches/t1bridge-touchbar-fkeys.patch`) and two configuration files taken from its packaging (`conf/t1bridge.*.conf`). Not t1bridge itself: get it from the link above. |
| Howdy | https://github.com/boltgolt/howdy | MIT, "Copyright (c) 2018 boltgolt" | A patch for `recorders/video_capture.py` (`patches/howdy-gstreamer.patch`). Not Howdy itself. |
| Broadcom BCM43602 NVRAM | https://bugzilla.kernel.org/attachment.cgi?id=29%30569 (kernel bugzilla, the Broadcom 43602 bug this attachment belongs to, the version with both bands working on a MacBookPro13,2) | None stated at the source | Nothing. `install.sh` downloads it, checks its sha256, writes your own Wi-Fi MAC into it and sets one line (`swctrlmap_2g`). |

## Getting the pieces yourself

```sh
git clone --branch v0.1.12 https://github.com/standardagents/t1bridge.git
git clone https://github.com/boltgolt/howdy.git
curl -fsSL -o brcmfmac43602-pcie.txt 'https://bugzilla.kernel.org/attachment.cgi?id=29%30569'
```

## MIT notices that must travel with the patches

t1bridge: MIT License, Copyright (c) 2026 T1Bridge contributors.
Howdy: MIT License, Copyright (c) 2018 boltgolt.
The full MIT text is in `LICENSE` (same wording).
