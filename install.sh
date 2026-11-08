#!/bin/bash
# Installer for the pieces proven on a MacBookPro13,2 (T1 chip) running Debian 13.
# Idempotent: every step checks the current state and only changes what differs.
# Run as root:   sudo ./install.sh [--dry-run] [--force] [--wifi-mac AA:BB:CC:DD:EE:FF]
#                                  [--t1bridge-src DIR] [--fprintd-src DIR] [--fprintd-debug]
#                                  [--rename-owner OLD NEW]
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SWCTRL="swctrlmap_2g=0x02020202,0x01010101,0x02020202,0x00000000,0x000000ff"
NVRAM_URL="https://bugzilla.kernel.org/attachment.cgi?id=29%30569"
# pinned sha256 of the NVRAM file, in 4 parts
NVRAM_SHA_1="a74cbb0abc4e8a43"
NVRAM_SHA_2="7e383442dd44a9"
NVRAM_SHA_3="6263079c102787"
NVRAM_SHA_4="fbe0758e67614ca79df2"
DRY=0; FORCE=0; WIFI_MAC=""; T1_SRC=""; FP_SRC=""; FP_DEBUG=0; REN_OLD=""; REN_NEW=""
CHANGED=0

usage() { sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) DRY=1 ;;
        --force) FORCE=1 ;;
        --wifi-mac) WIFI_MAC=${2:?--wifi-mac needs a value}; shift ;;
        --t1bridge-src) T1_SRC=${2:?--t1bridge-src needs a directory}; shift ;;
        --fprintd-src) FP_SRC=${2:?--fprintd-src needs a directory}; shift ;;
        --fprintd-debug) FP_DEBUG=1 ;;
        --rename-owner) REN_OLD=${2:?--rename-owner needs OLD NEW}; REN_NEW=${3:?--rename-owner needs OLD NEW}; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "unknown option: $1" >&2; usage 2 ;;
    esac
    shift
done

say()  { printf '%s\n' "$*"; }
act()  { CHANGED=1; if [ "$DRY" = 1 ]; then say "[dry-run] would: $*"; return 0; fi; say "do: $*"; }
skip() { say "ok (already): $*"; }

[ "$(id -u)" = 0 ] || [ "$DRY" = 1 ] || { echo "run as root" >&2; exit 2; }

# --- 0. model check -------------------------------------------------------------
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
if [ "$MODEL" != "MacBookPro13,2" ] && [ "$FORCE" != 1 ]; then
    echo "this is made for MacBookPro13,2, found: $MODEL (use --force to go on)" >&2
    exit 2
fi

# put FILE MODE SOURCE : install SOURCE as FILE when it differs
put() {
    local dst=$1 mode=$2 src=$3
    if [ -f "$dst" ] && cmp -s "$src" "$dst" && [ "$(stat -c %a "$dst")" = "$mode" ]; then skip "$dst"; return 0; fi
    act "install $dst"; PUT_CHANGED=1
    [ "$DRY" = 1 ] || install -D -m "$mode" "$src" "$dst"
}

# --- 1. packages ----------------------------------------------------------------
PKGS="gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav firmware-brcm80211 curl patch"
MISSING=""
for p in $PKGS; do dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"; done
if [ -n "$MISSING" ]; then
    act "apt-get install$MISSING"
    [ "$DRY" = 1 ] || DEBIAN_FRONTEND=noninteractive apt-get install -y $MISSING
else skip "packages"; fi

# --- 2. T1 modules: keep the legacy iBridge HID drivers away from t1bridge ---------
put /etc/modprobe.d/t1bridge.conf 644 "$HERE/conf/t1bridge.modprobe.conf"
put /etc/modules-load.d/t1bridge.conf 644 "$HERE/conf/t1bridge.modules-load.conf"

# --- 3. t1bridge sources: F1-F12 by default, and the Touch ID broker leaves after a refused SEP lease --------
# t1bridge itself is not shipped here: get v0.1.12 from its own repository (see README). Both patches apply to the
# same tree, in this order; you build and install t1bridge yourself afterwards.
# apply_patch DIR PATCH LABEL : apply PATCH in DIR unless it is already applied
apply_patch() {
    local dir=$1 p=$2 label=$3
    if patch -p1 -R --dry-run -s -d "$dir" < "$p" >/dev/null 2>&1; then skip "$label already applied in $dir"
    elif patch -p1 --dry-run -s -d "$dir" < "$p" >/dev/null 2>&1; then
        act "apply $label in $dir (then rebuild, see README)"
        [ "$DRY" = 1 ] || patch -p1 -s -d "$dir" < "$p"
    else echo "$label does not apply cleanly in $dir (wrong version? see README)" >&2; exit 1; fi
}
if [ -n "$T1_SRC" ]; then
    apply_patch "$T1_SRC" "$HERE/patches/t1bridge-touchbar-fkeys.patch" "t1bridge F1-F12 patch"
    apply_patch "$T1_SRC" "$HERE/patches/t1bridge-sep-lease.patch" "t1bridge SEP-lease patch"
else
    say "skip: no --t1bridge-src given, t1bridge patches not applied (patches/t1bridge-*.patch)"
fi
# The Touch ID broker waits for the import of Apple's machine data (drop-in, no rebuild needed).
PUT_CHANGED=0
put /etc/systemd/system/t1-touchid-auth.service.d/after-import.conf 644 "$HERE/conf/t1bridge-after-import.conf"

# --- 3b. fprintd sources: the old print is deleted only after a successful enrolment -------------------------
# Upstream fprintd deletes the existing print of the finger BEFORE the enrolment, so a failed enrolment leaves the finger
# erased. The patch is for fprintd 1.94.5 (commit b54a007); you build and install it yourself (README).
if [ -n "$FP_SRC" ]; then
    apply_patch "$FP_SRC" "$HERE/patches/fprintd-keep-print.patch" "fprintd keep-print patch"
else
    say "skip: no --fprintd-src given, fprintd patch not applied (patches/fprintd-keep-print.patch)"
fi
if [ "$FP_DEBUG" = 1 ]; then
    put /etc/systemd/system/fprintd.service.d/debug.conf 644 "$HERE/conf/fprintd-debug.conf"
else say "skip: fprintd debug log not asked (--fprintd-debug, optional)"; fi
if [ "$PUT_CHANGED" = 1 ] && [ "$DRY" != 1 ]; then systemctl daemon-reload; fi

# --- 4. Howdy: GStreamer fallback for the H.264-only camera -----------------------
FOUND=0
for f in $(find /usr/local /usr/lib/security /lib/security /opt -path '*/recorders/video_capture.py' 2>/dev/null | sort -u); do
    FOUND=1
    if grep -q '_v4l_lit' "$f"; then skip "Howdy fallback in $f"; else
        act "patch $f"
        [ "$DRY" = 1 ] || patch --forward --batch "$f" < "$HERE/patches/howdy-gstreamer.patch"
    fi
done
[ "$FOUND" = 1 ] || say "skip: Howdy (recorders/video_capture.py) not found; install Howdy, then run this again"

# --- 5. logind: the Touch ID sensor is the power button ---------------------------
put /etc/systemd/logind.conf.d/90-mac-touchid.conf 644 "$HERE/conf/90-touchid-power-key.conf"
# usbmuxd's own rule would put the T1 iBridge in USB configuration 0 (Touch Bar and camera interfaces gone); /etc wins over /lib
PUT_CHANGED=0
put /etc/udev/rules.d/39-usbmuxd.rules 644 "$HERE/conf/39-usbmuxd-sans-ibridge.rules"
if [ "$PUT_CHANGED" = 1 ] && [ "$DRY" != 1 ]; then udevadm control --reload; fi

# --- 6. ufw: xART (Touch ID) needs 61500/tcp on the private T1 link only ----------
LINK=""
for n in /sys/class/net/*; do
    [ -e "$n/device/driver" ] || continue
    [ "$(basename "$(readlink -f "$n/device/driver")")" = apple_t1_ncm ] && { LINK=$(basename "$n"); break; }
done
if ! command -v ufw >/dev/null 2>&1; then say "skip: ufw not installed (no firewall rule needed)"
elif [ -z "$LINK" ]; then say "skip: no network link on the apple_t1_ncm driver yet (T1 config 2 needs a reboot); run this again after"
elif ufw status 2>/dev/null | grep -qE "^61500/tcp +on $LINK +ALLOW( IN)? +fe80::/10"; then skip "ufw 61500/tcp on $LINK"
else
    act "ufw allow in on $LINK from fe80::/10 to any port 61500 proto tcp"
    [ "$DRY" = 1 ] || ufw allow in on "$LINK" from fe80::/10 to any port 61500 proto tcp comment 'xART T1 (t1bridge)'
fi

# --- 7. NVMe: no D3cold ----------------------------------------------------------
if put /etc/udev/rules.d/80-mac-nvme-d3cold.rules 644 "$HERE/conf/80-mac-nvme-d3cold.rules"; then
    [ "$DRY" = 1 ] || udevadm control --reload
fi

# --- 8. Wi-Fi BCM43602 NVRAM ------------------------------------------------------
# The file is not redistributed here (no licence stated at its source): it is fetched
# from the kernel bugzilla, checked against a pinned sha256, your own Wi-Fi MAC is written in, and its
# swctrlmap_2g line is set to the value that made 2.4 GHz and 5 GHz both connect on a MacBookPro13,2
# (added if missing, replaced if different). Reboot after the first install.
NV=/lib/firmware/brcm/brcmfmac43602-pcie.txt
if [ -z "$WIFI_MAC" ]; then say "skip: NVRAM (give your Wi-Fi MAC with --wifi-mac, read it from macOS: ifconfig en0 | grep ether)"
elif ! printf '%s' "$WIFI_MAC" | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then echo "bad MAC: $WIFI_MAC" >&2; exit 2
else
    if [ -f "$NV" ] && grep -qix "macaddr=$WIFI_MAC" "$NV" && grep -qxF "$SWCTRL" "$NV"; then skip "NVRAM $NV for $WIFI_MAC"
    else
        act "fetch $NVRAM_URL, verify sha256, write $NV with macaddr=$WIFI_MAC and $SWCTRL (reboot needed)"
        if [ "$DRY" != 1 ]; then
            TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
            curl -fsSL "$NVRAM_URL" -o "$TMP"
            GOT=$(sha256sum "$TMP" | cut -d' ' -f1)
            [ "$GOT" = "$NVRAM_SHA_1$NVRAM_SHA_2$NVRAM_SHA_3$NVRAM_SHA_4" ] || { echo "NVRAM sha256 mismatch, not installed" >&2; exit 1; }
            sed -i "s/^macaddr=.*/macaddr=$WIFI_MAC/" "$TMP"
            if grep -q '^swctrlmap_2g=' "$TMP"; then sed -i "s/^swctrlmap_2g=.*/$SWCTRL/" "$TMP"; else echo "$SWCTRL" >> "$TMP"; fi
            install -D -m 644 "$TMP" "$NV"
        fi
    fi
fi

# --- 9. fingerprint owner rename ---------------------------------------------------
if [ -n "$REN_OLD" ]; then
    act "rename fingerprint owner $REN_OLD -> $REN_NEW"
    [ "$DRY" = 1 ] || "$HERE/scripts/rename-fingerprint-owner.sh" "$REN_OLD" "$REN_NEW"
fi

if [ "$CHANGED" = 1 ]; then say "done, with changes. Reboot for the modules, logind and Wi-Fi firmware to take effect."
else say "done, nothing to change."; fi
