# mbp-11-3-sound

Separate tweeter and woofer streams for the internal speakers of the MacBook Pro 11,3 (A1398, late 2013) on
Linux. Russian version: [README.ru.md](README.ru.md).

**Status (2026-10-13):** the kernel patch is booted and works: the two pairs play two PCM devices
independently. The PipeWire crossover runs and both pairs play through it; the owner rates the sound as
excellent with `BASS_GAIN=2 PREAMP=0 LOUD=6` and the limiter. Start after a reboot is **not tested yet**.

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

`patches/0018-cs4208-split-speakers.patch` (against Linux 6.18, `sound/hda/codecs/cirrus/cs420x.c`) adds a
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

1. Apply the patch to a 6.18 kernel tree (`patch -p1 < patches/0018-cs4208-split-speakers.patch`) and build.
   The number 0018 is its place in the `linux-lts-mbp` patch series of the
   [reclocked fork](https://github.com/IgorChicherin/reclocked).
2. `./install-0018.sh` — for that setup only (Arch, ZFS root, `linux-lts-mbp` built with `makepkg`): takes a ZFS
   snapshot, writes `/etc/modprobe.d/cs4208-split.conf`, installs the packages, checks DKMS and that the
   module has the parameter. Set `PKGDIR` if the packages are elsewhere. `./install-0018.sh undo` removes the
   option.
3. Reboot, then `tools/speaker-split-test.sh` (no sudo): high tone on device 0, low tone on device 2, then
   both. Expected: tweeters, woofers, both.

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
when it is one of these two outputs. Seen working on plug-in (2026-10-13); the switch back on unplug is not
confirmed yet.

**Sync:** both PCMs share one clock name, so PipeWire runs them in one graph without resampling. Measured with
the internal microphone (chirp on the tweeters, then on the woofers, three cold starts): the woofers arrive
0.40-0.49 ms after the tweeters, 0.08 ms spread between starts. That figure includes the path difference to
the microphone.

## Not done yet

- Tuning by ear.
- Headphone unplug check; behaviour after a PipeWire restart and after a reboot.

## Sources

- [iMac16,2, CS4208, four-speaker PipeWire DSP](https://github.com/monofasesrl/imac-linux-audio-dsp)
- [ALSA: hda/cs420x: CS4208 fixup for iMac16,1](https://ratatoskr.run/lkml/2026/05/17033263/t)
- [MacBookPro12,1: 4.0 silent, unsolved](https://github.com/omacom/omarchy/issues/12217)
