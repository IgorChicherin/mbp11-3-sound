# mbp-11-3-sound

Separate tweeter and woofer streams for the internal speakers of the MacBook Pro 11,3 (A1398, late 2013) on
Linux, and its headset microphone. Russian version: [README.ru.md](README.ru.md).

**Status (2026-10-13):** both parts work on a MacBookPro11,3 with Linux 6.18.55. Speakers: the two pairs play
two PCM devices independently and the PipeWire crossover runs on top; the owner rates the sound as excellent
with `BASS_GAIN=2 PREAMP=0 LOUD=6` and the limiter. Headset microphone: works in the system and in Discord.

## The problem

The machine has four speaker drivers on a Cirrus CS4208 codec (subsystem `106b:5e00`, kernel fixup `mbp11`):

| Kernel name | DAC | Pin | Plays (by ear, one output at a time) | Role |
|---|---|---|---|---|
| `Speaker` | `0x03` | `0x12` | 400 Hz – 12.8 kHz | tweeters |
| `Bass Speaker` | `0x04` | `0x13` | 200 Hz – 6.4 kHz | woofers |
| `Headphone` | `0x02` | `0x10` | | jack |

In stereo the driver copies the same left/right signal to both pairs, so there is no crossover and no
per-driver correction. The "Analog Surround 4.0" profile, which should address the pairs separately, is
completely silent, also with raw ALSA (`hw:1,0`, 4 channels).


## The patch

`patches/0001-cs4208-split-speakers.patch` (against Linux 6.18, `sound/hda/codecs/cirrus/cs420x.c`) adds a
module parameter:

```
options snd_hda_codec_cs420x split_speakers=1
```

- **Off (default):** nothing changes.
- **On:** the main PCM (`hw:PCH,0`) feeds DAC `0x03` (tweeters) and the headphone DAC `0x02`. DAC `0x04`
  (woofers) gets its own PCM, `CS4208 Alt Analog` (`hw:PCH,2`), through the generic parser's alternate
  playback device.

With the split on and no crossover in userspace, desktop sound comes from the tweeters only.

## Use

1. Apply both patches to a 6.18 kernel tree with the one script of this repo, then build and install the
   kernel your usual way:

   ```
   ./apply-patches.sh --check /path/to/linux    # what would happen, changes nothing
   ./apply-patches.sh /path/to/linux
   ```

   It applies `patches/*.patch` in order, skips what is already in the tree, and changes nothing unless the
   whole series goes in. `--reverse` takes the patches out again. To build them into the `linux-lts-mbp`
   package of the [reclocked fork](https://github.com/IgorChicherin/reclocked) (dGPU patches for the same
   machine), pass this repo's `patches/` to its generator: `./mkpkgbuild.sh --extra-patches=<this repo>/patches`.
2. Turn the speaker split on (the headset part needs no option) and reboot:

   ```
   echo 'options snd_hda_codec_cs420x split_speakers=1' | sudo tee /etc/modprobe.d/cs4208-split.conf
   ```

3. `tools/speaker-split-test.sh` (no sudo): high tone on device 0, low tone on device 2, then both. Expected:
   tweeters, woofers, both. Then set up the crossover below.

## PipeWire crossover

`pipewire/setup.sh` (no sudo) installs `~/.local/bin/mbp-speakers` and the user unit `mbp-speakers.service`.
`pipewire/setup.sh undo` removes them. The unit starts only on a kernel where `split_speakers` is `Y`; on any
other kernel the plain stereo output is left alone.

What the service builds:

| Node | What it is |
|---|---|
| `mbp_speakers` "MacBook Speakers" | the output to use: stereo in, crossover, 4 channels out |
| `mbp_quad` | 4-channel sink (combine-stream): FL FR to the tweeters, RL RR to the woofers; hidden |
| `mbp_woofers` | ALSA sink on `hw:PCH,2`, created by the service; hidden |
| `alsa_output.pci-0000_00_1b.0.analog-stereo` | PipeWire's own sink on `hw:PCH,0`: tweeters and the headphone jack |

The two hidden nodes have `media.class = "Audio/Sink/Internal"`: PipeWire links to them by name, but desktop
volume controls do not list them. They still show in `pw-top` and `wpctl status`.

Filter per channel: tweeters get a 4th-order Linkwitz-Riley high-pass; woofers get a low-shelf boost, a
high-pass against sub-bass and the matching low-pass, all PipeWire builtin filters. If `swh-plugins` is
installed (`sudo pacman -S swh-plugins`), each pair also ends in a lookahead limiter
(`fast_lookahead_limiter_1913`); without it `LOUD` and `LIMIT` are ignored and the headroom is the fixed preamp.

Tuning (saved in `~/.config/mbp-speakers/params`, restarts the service):

```
mbp-speakers show
mbp-speakers tune BASS_GAIN=8 XOVER=1200
```

| Key | Default | Meaning |
|---|---|---|
| `XOVER` | 1000 | crossover, Hz |
| `SUB_HP` | 70 | woofer high-pass, Hz |
| `BASS_FREQ` / `BASS_GAIN` | 200 / 2 | low-shelf corner, Hz / boost, dB |
| `WOOFER_GAIN`, `TWEETER_GAIN` | 0 | level trims, dB |
| `PREAMP` | 0 | attenuation before the limiter, dB; without the limiter use -2 |
| `LOUD` | 6 | gain into the limiter, dB: louder, less dynamics |
| `LIMIT` | -1 | limiter ceiling, dBFS |

The defaults are the values tuned by ear on this machine with the limiter installed; they are not measured. `tune` refuses values outside fixed ranges
(`XOVER` 700–2500, `SUB_HP` 50–150, `BASS_GAIN` -6–9, trims and `PREAMP` -12–0, `LOUD` 0–9, `LIMIT` -6 to -0.5).

Checked on the 4-channel bus with `LOUD=6`: a quiet signal comes out 6 dB louder, a full-scale one peaks at
-1.0 dBFS on both pairs.

**Speaker safety.** The amplifier's peak output is fixed by the hardware, and nothing here raises it. What
`LOUD` raises is the average power, which is what heats the voice coils. The thermal limits of these drivers
are not known and not measured, so there is no guarantee; the ranges above are a conservative guess. Relative
to the stock driver, which sends the full range to all four drivers, the tweeters now get nothing below the
crossover and the woofers nothing below `SUB_HP`. Rattle or harsh distortion means: turn it down.

**Headphones:** while the jack port is active the service makes the plain output the default (full range to
the headphone DAC; PipeWire mutes both speaker pairs) and switches back on unplug. It only touches the default
when it is one of these two outputs. Seen working in both directions (2026-10-13).

**Sync:** both PCMs share one clock name, so PipeWire runs them in one graph without resampling. Measured with
the internal microphone (chirp on the tweeters, then on the woofers, three cold starts): the woofers arrive
0.40-0.49 ms after the tweeters, 0.08 ms spread between starts. That figure includes the path difference to
the microphone.

## Headset microphone

**Status (2026-10-13):** works. The owner confirms the headset microphone in the system and in Discord on the
current patch. Measured on the way: the detection at plug-in, the two FET lines, the level on the microphone
pin, and that the audio chip sleeps again once the headset is unplugged.

A headset microphone in the combo jack never works on this model in stock Linux: `Mic Jack` stays off, and
forcing the capture path to the microphone pin (`0x18`) gives only noise. There were two separate causes.

**Cause 1: the microphone contact is grounded.** The CS4208 has a headset block that the driver does not use.
Two FETs, controlled by GPIO5 and GPIO4, ground the two possible microphone contacts while their GPIO is low.
The driver leaves both undriven, so the microphone is always shorted.

| State | Level on pin `0x18` |
|---|---|
| stock driver | -68 dBFS, no change between talking and silence |
| both GPIOs high, type detection run | codec answers "headset with microphone" |
| then GPIO5 high, GPIO4 low | -35 dBFS talking, -46 dBFS silence (top gain) |
| then GPIO5 low, GPIO4 high | -67 dBFS |

How macOS drives the block was read from AppleHDA 10.13.6 (class `AppleHDAMikeyInternalCS4208` and layout 94,
which belongs to subsystem `106b:5e00`), then each step was verified with `hda-verb`.

**Cause 2: the input amplifier of the headset's ADC is muted.** ADC `0x07` has three inputs but one amplifier.
`cs4208_probe()` does not set `single_adc_amp` (the CS4206/4207 probe does), so the kernel keeps three cached
amplifier values, `Capture` drives one and the other two stay at their initial mute. Every cache sync writes all
three and the chip keeps the last one, a mute: recordings are digital silence although `Capture` shows "on".
This is a driver bug for every CS4208 machine, not only this model; nobody noticed because the path was never
used.

**The patch.** `patches/0002-cs4208-mbp11-headset-mic.patch` (on top of 0001):

- When something is plugged into the jack, the driver runs the codec's type detection, sets the two GPIOs by
  the answer and reports the result as the presence of pin `0x18`. `Mic Jack` and the automatic microphone
  switching then work as for any jack, and PipeWire selects the "Microphone" port by itself.
- The codec's headset block loses its state when the codec powers down (measured: -68 dBFS afterwards, -42 dBFS
  after a new detection). So the driver keeps the codec powered while a headset with a microphone is plugged
  in, as macOS has to do for the headset buttons. Plain headphones do not hold it up.
- `single_adc_amp` is set for the CS4208.

```
options snd_hda_codec_cs420x headset_mic=0     # turns the headset part off; the default is on
```

Limits:

- The headset part is only for subsystem `106b:5e00` (MacBookPro11,2/11,3): the values are those of Apple's
  layout for it.
- Verified with a CTIA headset (detector type 0). The other pinout (type 1) follows AppleHDA and is untested.
- The headset buttons are not handled.
- The audio chip does not sleep while a headset with a microphone is plugged in. The extra power draw is not
  measured.

**Use.** Nothing beyond the patched kernel (`./apply-patches.sh`, see "Use" above). Plug the headset in and run `tools/headset-mic-test.sh` (no sudo): it shows what the kernel and PipeWire see, records
6 s twice with 20 s of silence in between, prints both levels and plays both back. It records the way
applications do and selects no port.

**Two approaches that did not work,** kept here so nobody repeats them:

- Running the detection again when a recording starts, instead of keeping the codec powered: it passed the
  test script but a voice chat got no input.
- Re-syncing the ADC node from the kernel's cache when a recording starts: that sync is exactly what mutes the
  amplifier (cause 2).

## Not done yet

- Speaker tuning is by ear, not measured.
- Headset: the buttons, the second pinout (type 1), and the power cost of keeping the codec awake.

Start after a reboot is confirmed (several reboots on 2026-10-13). An earlier version of the service failed
there: its start check ran `aplay -l` 0.7 s before logind granted the session access to `/dev/snd`, saw no cards
and the unit was skipped. The check now reads `/proc/asound` and the service waits up to 60 s for device access.

## Sources

- [iMac16,2, CS4208, four-speaker PipeWire DSP](https://github.com/monofasesrl/imac-linux-audio-dsp)
- [ALSA: hda/cs420x: CS4208 fixup for iMac16,1](https://ratatoskr.run/lkml/2026/05/17033263/t)
- [MacBookPro12,1: 4.0 silent, unsolved](https://github.com/omacom/omarchy/issues/12217)
- [Ubuntu bug 1410618: TRRS headset mic not working, CS4208 (lists a MacBookPro11,3)](https://bugs.launchpad.net/ubuntu/+source/alsa-driver/+bug/1410618)
- [Kernel bug 155601: external mic/headset not detected, MacBookPro12,1](https://bugzilla.kernel.org/show_bug.cgi?id=155601)
- [OpenCore Legacy Patcher](https://github.com/dortania/OpenCore-Legacy-Patcher): its binaries image carries the AppleHDA that was read
