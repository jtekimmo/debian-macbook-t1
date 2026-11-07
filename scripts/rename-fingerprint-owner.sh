#!/bin/bash
# Re-attach an enrolled T1 fingerprint to another Linux account (for example after
# the account was renamed). Run as root, on the Mac.
#
#   rename-fingerprint-owner.sh OLD_USER NEW_USER
#
# Two places carry the owner name:
#   1. /var/lib/t1bridge/touch-id/catacombs/pair-*/identities.meta  (clear text, "T1IM" format)
#   2. /var/lib/fprint/NEW_USER/t1bridge/0/7                         (libfprint "FP3" print)
# Both are rewritten (the FP3 one through libfprint itself), after a full copy of the
# state under /var/backups/t1-fingerprint-owner. If the check at the end fails, the
# copies are put back. Needs python3-gi and gir1.2-fprint-2.0.
# Origin: run once by hand on a MacBookPro13,2; this parametrised version was not re-run as is.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
[ $# = 2 ] || { echo "usage: $0 OLD_USER NEW_USER"; exit 2; }
OLD=$1; NEW=$2
B=/var/backups/t1-fingerprint-owner; T=/var/lib/t1bridge/touch-id; F=/var/lib/fprint/$NEW
M=$(ls "$T"/catacombs/pair-*/identities.meta 2>/dev/null | head -1); P=$F/t1bridge/0/7
UNITS=$(systemctl list-units --no-legend --plain --all "t1*" "fprintd*" | awk '$3=="active"{print $1}')
echo "active units: $(echo $UNITS | tr '\n' ' ')"
stop_all() { systemctl stop fprintd.service 2>/dev/null; for u in $(echo "$UNITS" | tac); do systemctl stop "$u" 2>/dev/null; done; }
start_all() { for u in $UNITS; do systemctl start "$u" 2>/dev/null; done; }
restore() {
    stop_all
    rm -rf --one-file-system "$T" && cp -a "$B/touch-id" "$T" && rm -rf --one-file-system "$F" && cp -a "$B/fprint-user" "$F"
    start_all; echo "ROLLED BACK"; sleep 6
    fprintd-list "$NEW" 2>&1 | tail -2
}
[ -n "$M" ] && [ -f "$M" ] && [ -f "$P" ] || { echo "files missing (identities.meta or $P); is the print under /var/lib/fprint/$NEW ?"; exit 2; }
python3 -I -c 'import gi; gi.require_version("FPrint","2.0")' 2>&1 || { echo "gi FPrint unavailable (apt install python3-gi gir1.2-fprint-2.0)"; exit 2; }
mkdir -p "$B" && chmod 700 "$B"
stop_all
rm -rf --one-file-system "$B/touch-id" "$B/fprint-user"
cp -a "$T" "$B/touch-id" && cp -a "$F" "$B/fprint-user" || { echo "backup failed"; start_all; exit 2; }
echo "backup: $(find "$B" -type f | wc -l) files in $B"
python3 -I - "$M" "$P" "$OLD" "$NEW" <<'PY'
import sys, os, gi
gi.require_version("FPrint", "2.0")
from gi.repository import FPrint
M, P, OLD, NEW = sys.argv[1:5]
def write(path, data):
    st = os.stat(path); tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, st.st_mode & 0o7777)
    os.write(fd, data); os.fsync(fd); os.close(fd)
    os.chown(tmp, st.st_uid, st.st_gid); os.chmod(tmp, st.st_mode & 0o7777); os.replace(tmp, path)
# identities.meta: "T1IM", version, count, reserved(2), name length (1 byte), name, entries
d = open(M, "rb").read()
assert d[:4] == b"T1IM" and d[4] == 1 and d[6:8] == b"\0\0", "unexpected format"
n = d[8]; name = d[9:9 + n]
new = NEW.encode()
assert len(new) < 256
if name == OLD.encode():
    nd = d[:8] + bytes([len(new)]) + new + d[9 + n:]
    write(M, nd); print("identities.meta:", OLD, "->", NEW)
else:
    print("identities.meta: owner already", name.decode())
p = FPrint.Print.deserialize(open(P, "rb").read())
print("FP3 before:", p.get_username(), p.get_finger(), p.get_driver())
if p.get_username() != NEW:
    p.set_username(NEW)
    out = bytes(p.serialize())
    q = FPrint.Print.deserialize(out)
    assert q.get_username() == NEW and q.get_finger() == p.get_finger() and q.get_driver() == p.get_driver()
    write(P, out); print("FP3: username ->", NEW)
PY
RC=$?
[ $RC = 0 ] || { echo "edit failed rc=$RC"; restore; exit 1; }
start_all; sleep 8
OUT=$(fprintd-list "$NEW" 2>&1); echo "$OUT" | tail -4
ST=$(t1bridge status 2>&1); echo "$ST" | grep -E "touchbar|keybag|broker"
ERR=$(journalctl --since "-3min" --no-pager 2>/dev/null | grep -i -E "OwnerMismatch|owner mismatch|integrity|IdentitySetMismatch|InvalidMetadata" | head -3)
echo "journal errors: ${ERR:-none}"
if echo "$OUT" | grep -qE '#[0-9]+: .*-finger' && echo "$ST" | grep -q "touchbar: ready" && [ -z "$ERR" ]; then
    echo "CHECK OK"
else
    echo "CHECK FAILED"; restore; exit 1
fi
