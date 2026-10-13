#!/usr/bin/env bash
# Install linux-lts-mbp with patch 0019 (CS4208 headset microphone on MacBookPro11,2/11,3). Asks for sudo.
# The speaker split of patch 0018 and /etc/modprobe.d/cs4208-split.conf stay as they are.
#   ./install-0019.sh          # snapshot + install
#   ./install-0019.sh off      # keep the kernel, turn the headset code off (headset_mic=0), then reboot
#   ./install-0019.sh on       # turn it on again, then reboot
set -euo pipefail
conf=/etc/modprobe.d/cs4208-headset.conf
case ${1:-} in
  off) echo 'options snd_hda_codec_cs420x headset_mic=0' | sudo tee "$conf" >/dev/null && echo "ok   $conf written; reboot"; exit 0 ;;
  on)  sudo rm -f "$conf" && echo "ok   $conf removed; reboot"; exit 0 ;;
esac
d=${PKGDIR:-$HOME/Projects/reclocked/pkgbuild/linux-lts-mbp}
pkgs=("$d"/linux-lts-mbp-[0-9]*.pkg.tar.zst "$d"/linux-lts-mbp-headers-*.pkg.tar.zst)
ls -l "${pkgs[@]}"
sudo -v
snap=zroot/arch0/root@pre-0019-$(date +%Y%m%d-%H%M%S)
sudo zfs snapshot "$snap" && echo "ok   snapshot $snap"
sudo pacman -U "${pkgs[@]}"
kver=$(for m in /usr/lib/modules/*/; do [[ $(cat "$m/pkgbase" 2>/dev/null) == linux-lts-mbp ]] && basename "$m"; done)
echo "== DKMS for $kver"
dkms status
ok=1
for mod in zfs broadcom-wl; do
  dkms status | grep -E "^$mod/.*$kver.*: installed" >/dev/null || { echo "FAIL: $mod is not built for $kver"; ok=0; }
done
modinfo -k "$kver" snd_hda_codec_cs420x | grep -q headset_mic && echo "ok   module has headset_mic" || { echo "FAIL: module lacks headset_mic"; ok=0; }
modinfo -k "$kver" snd_hda_codec_cs420x | grep -q split_speakers && echo "ok   module has split_speakers" || { echo "FAIL: module lacks split_speakers"; ok=0; }
if (( ok )); then echo "OK to reboot into linux-lts-mbp, then run $(dirname "$(realpath "$0")")/tools/headset-mic-test.sh"; else echo "DO NOT REBOOT"; exit 1; fi
