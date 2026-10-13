#!/usr/bin/env bash
# Install linux-lts-mbp with patch 0018 (CS4208 split_speakers) and turn the split on. Asks for sudo.
#   ./install-0018.sh          # install + enable split_speakers=1
#   ./install-0018.sh undo     # turn the split off again (kernel stays), then reboot
# With the split on and no PipeWire crossover yet, desktop sound comes from the first speaker pair only.
set -euo pipefail
conf=/etc/modprobe.d/cs4208-split.conf
if [[ ${1:-} == undo ]]; then
  sudo rm -f "$conf" && echo "ok   removed $conf; reboot to get both pairs on one stream again"
  exit 0
fi
d=${PKGDIR:-$HOME/Projects/reclocked/pkgbuild/linux-lts-mbp}   # where makepkg left the kernel packages
pkgs=("$d"/linux-lts-mbp-[0-9]*.pkg.tar.zst "$d"/linux-lts-mbp-headers-*.pkg.tar.zst)
ls -l "${pkgs[@]}"
sudo -v
snap=zroot/arch0/root@pre-0018-$(date +%Y%m%d-%H%M%S)
sudo zfs snapshot "$snap" && echo "ok   snapshot $snap"
# Before the package: the initramfs rebuilt by the kernel install then already carries the option.
printf '%s\n' '# CS4208 on MacBookPro11,x: second speaker pair on its own PCM (hw:PCH,2), for the PipeWire crossover.' \
  'options snd_hda_codec_cs420x split_speakers=1' | sudo tee "$conf" >/dev/null && echo "ok   $conf"
sudo pacman -U "${pkgs[@]}"
kver=$(for m in /usr/lib/modules/*/; do [[ $(cat "$m/pkgbase" 2>/dev/null) == linux-lts-mbp ]] && basename "$m"; done)
echo "== DKMS for $kver"
dkms status
ok=1
for mod in zfs broadcom-wl; do
  dkms status | grep -E "^$mod/.*$kver.*: installed" >/dev/null || { echo "FAIL: $mod is not built for $kver"; ok=0; }
done
modinfo -k "$kver" snd_hda_codec_cs420x | grep -q split_speakers && echo "ok   module has split_speakers" || { echo "FAIL: module lacks split_speakers"; ok=0; }
if (( ok )); then echo "OK to reboot into linux-lts-mbp, then run $(dirname "$(realpath "$0")")/tools/speaker-split-test.sh"; else echo "DO NOT REBOOT"; exit 1; fi
