#!/usr/bin/env bash
# After patch 0019: does the headset microphone come up by itself? (no sudo)
# Plug the headset in first. Shows what the kernel and PipeWire see, then records 6 s from the "Microphone"
# port of the built-in card twice, with 20 s of silence in between so the codec powers down, and plays both back.
#   ./headset-mic-test.sh
set -euo pipefail
export LC_ALL=C
src=alsa_input.pci-0000_00_1b.0.analog-stereo
p=/sys/module/snd_hda_codec_cs420x/parameters/headset_mic
[[ -r $p ]] || { echo "ERROR: this kernel has no patch 0019 ($p missing)" >&2; exit 1; }
echo "headset_mic parameter: $(<"$p")"
amixer -c PCH contents | grep -A2 -E "name='(Mic|Headphone) Jack'" | grep -E 'name=|: values' | paste - - | sed 's/numid=[0-9]*,iface=CARD,//'
awk '/^GPIO/ {p=1} p && /IO\[[045]\]/' /proc/asound/PCH/codec#0
pactl list sources | awk -v s="$src" '$1=="Name:" {p=($2==s)} p && /analog-input|Active Port/'
old=$(pactl list sources | awk -v s="$src" '$1=="Name:" {p=($2==s)} p && /Active Port:/ {print $3; exit}')
pactl list sources | awk -v s="$src" '$1=="Name:" {p=($2==s)} p' | grep -q 'analog-input-mic:.*not available' &&
  { echo "RESULT: the Microphone port is not available: the headset was not detected"; exit 1; }
out=$HOME/cs4208-mic-wav; mkdir -p "$out"
pactl set-source-port "$src" analog-input-mic
trap 'pactl set-source-port "$src" "$old" || true' EXIT
level() { python3 - "$1" <<'PY'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "rb"); rate = w.getframerate(); raw = w.readframes(w.getnframes()); w.close()
x = [f[0] / 32768 for f in struct.iter_unpack("<2h", raw)][2 * rate:]
m = sum(x) / max(len(x), 1)
r = math.sqrt(sum((v - m) ** 2 for v in x) / max(len(x), 1))
print("%.1f dBFS (below -60 = dead, digital silence = -180)" % (20 * math.log10(max(r, 1e-9))))
PY
}
rec() {
  echo ">>> $1: TALK into the headset microphone for 6 seconds"
  timeout 6 pw-record --target "$src" --rate 48000 --channels 2 --format s16 "$2" || true
  echo "    level in the last 4 s: $(level "$2")"
}
rec "recording 1" "$out/headset-0019-1.wav"
echo ">>> now stay QUIET for 20 s: the codec powers down (this is what killed the microphone before)"
sleep 20
rec "recording 2, after the power-down" "$out/headset-0019-2.wav"
echo ">>> playing both back"
pw-play "$out/headset-0019-1.wav"; pw-play "$out/headset-0019-2.wav"
echo "port before the test: $old (restored)"
