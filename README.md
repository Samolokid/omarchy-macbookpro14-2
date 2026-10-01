# Omarchy on a MacBookPro14,2

Notes for running [Omarchy](https://omarchy.org) on the 2017 13" MacBook Pro
with Touch Bar (MacBookPro14,2: four Thunderbolt ports, T1 chip, Kaby Lake).
Everything below was tested on one machine, on Omarchy 4.0.4 with kernel
7.2.x, in September 2026.

| Hardware | Status | Section |
|---|---|---|
| Speakers | ✅ working | [Audio](#audio) |
| WiFi (BCM43602) | ✅ working, 2.4 + 5 GHz | [WiFi](#wifi) |
| Touch Bar | ✅ working | [T1 chip](#t1-chip-touch-bar-touch-id-camera) |
| Touch ID | ✅ sudo, polkit, lock screen | [Touch ID](#touch-id) |
| FaceTime camera | ✅ 720p, H.264 only | [Camera](#camera) |
| Suspend | ⚠️ works, but the T1 is dead after resume | [Suspend](#suspend) |
| Keyboard, trackpad | ✅ out of the box | [Keyboard](#keyboard) |

Check your model first:

```sh
cat /sys/class/dmi/id/product_name    # MacBookPro14,2
```

## Audio

**Symptom:** no sound from the speakers. Everything looks fine (sink unmuted,
volume up, `speaker-test` runs without errors), but you hear nothing. The mic
works.

**Cause:** the mainline `snd_hda_codec_cs8409` driver has no fixup that turns
on this model's speaker amp.

**Fix:** use the community driver
[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)
(AUR: `snd-hda-macbookpro-dkms-git`):

```sh
sudo pacman -S linux-headers
yay -S snd-hda-macbookpro-dkms-git
sudo reboot
speaker-test -c 2 -t sine -f 440 -l 1   # check
```

## WiFi

There are two separate problems. Fix both.

### 1. WiFi drops and won't reconnect until reboot

**Symptom** in `journalctl -u wpa_supplicant`:

```
Failed to create interface p2p-dev-wlp2s0: -12 (Cannot allocate memory)
CTRL-EVENT-SCAN-FAILED
```

**Cause:** the brcmfmac firmware leaks resources when NetworkManager keeps
recreating the WiFi-Direct (P2P) interface, for example on every scan with a
randomized MAC.

**Fix:** [`config/wifi-brcmfmac-stability.conf`](config/wifi-brcmfmac-stability.conf)
→ `/etc/NetworkManager/conf.d/`, then `sudo systemctl restart NetworkManager`.
If the Omarchy bar still shows WiFi as disconnected after that, run
`omarchy-restart-shell`. The connection itself is fine.

Omarchy also ships [`config/brcmfmac.conf`](config/brcmfmac.conf)
(`feature_disable=0x82000`). Keep it, or WPA handshakes fail with a "wrong
password" error.

### 2. No 5 GHz, weak signal, MAC starts with `00:90:4c`

**Cause:** the BCM43602 needs a board-specific NVRAM calibration file
(`brcmfmac43602-pcie.txt`). macOS has it; a fresh Linux install doesn't, so
the driver falls back to 2.4 GHz only with no RF calibration. (The
`no clm_blob available` kernel message is harmless and not the cause.)

**Fix:** use the NVRAM file for this board from
[nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1)
(`firmware/brcmfmac43602-pcie.txt`). The calibration is per board revision
(`boardtype=0x61b`, `boardrev=0x1421`), not per device.

1. Set `macaddr=` in the file to **your own** MAC. If you no longer know your
   real one, make up a locally administered one, starting with `02:`. Don't
   copy anyone else's.
2. `sudo install -m644 brcmfmac43602-pcie.txt /usr/lib/firmware/brcm/`
3. **Reboot.** NetworkManager keeps the module loaded, so `modprobe -r` won't
   work.

Check: `iw phy phy0 info` lists 5180+ MHz channels, and `nmcli dev wifi list`
shows 5 GHz networks. In my case the signal went from −72 dBm (2.4 GHz) to
−44 dBm (5 GHz).

Rollback: delete the file and reboot.

## T1 chip (Touch Bar, Touch ID, camera)

On the 14,2 the Touch Bar, Touch ID, FaceTime camera and ambient light sensor
**all** sit behind the T1 chip. So there's one problem to fix, not four.

**Why it's dead after installing Omarchy:** the installer formats the EFI
partition and deletes the T1 firmware that macOS put there
([omarchy#8271](https://github.com/omacom/omarchy/issues/8271)). The T1 then
stays in recovery mode:

```sh
lsusb | grep 05ac    # 05ac:1281 = recovery (broken), 05ac:8600 = iBridge (good)
```

Old drivers like `apple-ib-drv` / `apple_ibridge` can't fix that: the firmware
is missing, not the driver. **You don't need macOS or a second Mac.**

### Step 1: rebuild the firmware with t1-revive

[niconistal/t1-revive](https://github.com/niconistal/t1-revive) rebuilds the
T1 firmware from Linux over Apple's official restore protocol, using signed
data from Apple's servers. It has been confirmed on the 14,2.

```sh
git clone https://github.com/niconistal/t1-revive && cd t1-revive
bash build.sh                              # the AUR package didn't exist yet
sudo bin/t1-revive preflight --install     # installs acpi_call-dkms etc.
sudo bin/t1-revive backup --to ~/t1-backup
sudo bin/t1-revive regenerate              # ~5 min, keep the charger plugged in
```

If a step stalls: shut down, wait 20 s, power on, then continue with
`--from <step>`.

**Right after it works, back up `/boot/EFI/APPLE` to a USB stick**, encrypted
if you like. The next reinstall deletes it again, and the backup saves you the
whole procedure:

```sh
sudo tar cf efi-apple-backup.tar -C /boot/EFI APPLE
```

### Step 2: install T1Bridge

[standardagents/t1bridge](https://github.com/standardagents/t1bridge) is the
driver stack. Follow their [setup docs](https://linux.standardagents.ai) for
the pacman repo and signing key. Omarchy blocks plain `pacman -Syu`, so:

```sh
sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu --needed \
  linux-headers t1bridge t1bridge-dkms libfprint-t1bridge fprintd-t1bridge
sudo bin/t1-revive handover    # in the t1-revive folder
```

### Pitfalls I hit (check these if something stays dark)

On my install several units were **not enabled**, even though their presets
say they should be:

```sh
sudo systemctl enable --now t1-touchbar-hw.service
systemctl --user enable --now t1-touchbar.service
# for Touch ID:
sudo systemctl enable --now t1-touchid-auth.socket t1bridge-fingerprint.socket
```

- **Touch Bar dark although `touchbar: ready`:** log out and back in once. The
  `t1bridge` group is created during the install, and your session doesn't
  know about it yet.
- **`/var/lib/t1bridge/machine-data` empty:** `t1bridge-import.service` never
  ran. `--from /boot/EFI/APPLE/EMBEDDEDOS` failed for me; this auto-detection
  worked:
  ```sh
  sudo t1bridge --diagnostics machine-data import
  ```
- **Leftovers from `apple-ib-drv`:** if you tried that driver earlier, remove
  it or blacklist it (`blacklist apple_ibridge`). It conflicts with T1Bridge
  and breaks suspend through Thunderbolt (`tb_cfg_read: -108`, suspend-wake
  loop with the lid closed, and the laptop gets **hot in the bag**).

### Touch ID

1. Firewall: the T1 talks over a private IPv6 link (TCP 61500). Find the
   interface (`ip link`; the driver is `cdc_ncm`/`apple_t1_ncm`, and **the name
   can change between boots**):
   ```sh
   sudo ufw allow in on <iface> proto tcp from fe80::/10 port 61500
   ```
2. Enroll a finger: `fprintd-enroll`. My first attempt failed with
   `enroll-unknown-error` (known bootstrap issue). After
   `sudo systemctl restart t1bridge-fingerprint.socket` the second attempt
   worked.
3. Set up PAM with [`scripts/touchid-pam-setup.sh`](scripts/touchid-pam-setup.sh)
   for sudo, polkit and the lock screen. Has `--undo`. **Don't** use
   `omarchy-setup-security-fingerprint`: it replaces t1bridge's fprintd.

### Camera

It shows up as `/dev/video0` ("iBridge: FaceTime HD Camera"), 1280×720,
≤30 fps, **H.264 only** (no MJPEG/YUYV). Browsers and ffmpeg handle it. Apps
that need raw frames need an ffmpeg → `v4l2loopback` bridge.

### Omarchy Touch Bar on the T1

The context-aware [Omarchy Touch Bar](https://github.com/Chronicuser21/touch-bar)
(workspaces, browser tabs, sliders, dictation, …) was originally T2-only. A
T1Bridge backend for it is in review upstream:
[niraj-envision/touch-bar#10](https://github.com/niraj-envision/touch-bar/pull/10).
Until it is merged, install from the `t1bridge` branch of
[Samolokid/touch-bar](https://github.com/Samolokid/touch-bar/tree/t1bridge)
and follow the "T1 MacBooks" section of its README.

## Suspend

Suspend itself works (no wake-up loop once the old `apple_ibridge` driver is
gone). **But after resume the T1 is dead**: Touch Bar dark, Touch ID fails.
Restarting the services doesn't help, and neither does a reboot. **Only a full
shutdown + power-on brings it back.** This is a
[known upstream limitation](https://github.com/niconistal/t1-revive/blob/main/docs/faq.md)
("Does sleep and wake work? Not with the T1 stack, for anyone").

Options: shut down instead of suspending, or set up hibernate (needs a swap
file. Omarchy only has zram by default, and with LUKS + btrfs it takes some
setup; I haven't tested it yet).

## Keyboard

`hid_apple fnmode=2` ([`config/hid_apple.conf`](config/hid_apple.conf)) makes
F1–F12 the default and the media functions available via Fn. Omarchy already
ships this.

## Contributing

Same model and something works differently? Issues and PRs are welcome,
especially for hibernate and newer t1bridge versions.

## License

Text and scripts: [CC0](LICENSE). Do what you like with them. The linked
projects have their own licenses.
