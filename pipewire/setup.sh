#!/usr/bin/env bash
# Install the speaker crossover for the current user (no sudo). Needs kernel patch 0018 with split_speakers=1.
#   ./setup.sh          install + start; "MacBook Speakers" becomes the default output
#   ./setup.sh undo     stop and remove; sound goes back to the plain output (tweeters only while the split is on)
set -euo pipefail
here=$(dirname "$(realpath "$0")")
bin=$HOME/.local/bin/mbp-speakers
unit=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/mbp-speakers.service
if [[ ${1:-} == undo ]]; then
  systemctl --user disable --now mbp-speakers.service 2>/dev/null || true
  rm -f "$bin" "$unit"
  systemctl --user daemon-reload
  echo "removed (tuning values kept in ~/.config/mbp-speakers/params)"
  exit 0
fi
command -v pactl pw-cli pipewire aplay >/dev/null || { echo "ERROR: need pipewire, pipewire-pulse (pactl), alsa-utils" >&2; exit 1; }
[[ -r /usr/lib/ladspa/fast_lookahead_limiter_1913.so ]] ||
  echo "NOTE: swh-plugins is not installed: no limiter, LOUD is ignored. Install it, or run: mbp-speakers tune PREAMP=-2"
install -Dm755 "$here/mbp-speakers" "$bin"
install -Dm644 "$here/mbp-speakers.service" "$unit"
systemctl --user daemon-reload
systemctl --user enable mbp-speakers.service
systemctl --user restart mbp-speakers.service
sleep 3
"$bin" show
systemctl --user --no-pager -n 5 status mbp-speakers.service | tail -8
