# Samsung Galaxy Book 4 — Fingerprint Fix for Debian

Enables the FocalTech FT9365 fingerprint sensor (USB ID `2808:6553`) on
Samsung Galaxy Book 4 devices (Pro, Ultra, 360) running **Debian** (tested
on Debian 13 "trixie").

*[Leggi questo README in italiano](README.md)*

## The problem

libfprint's `focaltech_moc` driver supports several FocalTech PIDs, but
**not** the `0x6553` used by the Galaxy Book 4. An upstream patch exists
but hasn't been merged yet ([Merge Request #554](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/554)
by Sid1803), however:

- The precompiled `.deb` packages floating around online are built for
  **Ubuntu** and fail on Debian with a missing-symbol error:
  ```
  /lib/x86_64-linux-gnu/libgusb.so.2: version `LIBGUSB_0.2.8' not found
  ```
  (ABI mismatch between the two distros' `libgusb` versions)
- The `merge-requests/554/head` git ref is **not fetchable** directly from
  GitLab for this project (not every project exposes refs for external MRs)

The fix: compile libfprint from source locally, applying the patch by
hand. Building locally links the resulting binary against *your own*
system libraries — no ABI mismatch.

## Check your hardware

```bash
lsusb | grep "2808:6553"
```

If nothing shows up, this guide isn't for you.

## Procedure

### 1. Build dependencies

```bash
sudo apt install build-essential meson ninja-build git \
  libglib2.0-dev libgusb-dev libnss3-dev libpixman-1-dev \
  libgirepository1.0-dev gtk-doc-tools libgudev-1.0-dev libcairo2-dev \
  python3-cairo python3-gi libssl-dev libudev-dev
```

### 2. Source and patch

```bash
git clone https://gitlab.freedesktop.org/libfprint/libfprint.git
cd libfprint
git checkout v1.94.10

# Get the patch from the libfprint-ft9365 AUR package (it ships the
# MR #554 patch as a downloadable file, working around the GitLab ref issue)
git clone https://aur.archlinux.org/libfprint-ft9365.git /tmp/ft9365-aur
cp /tmp/ft9365-aur/focaltech-ft9365.patch .
patch -Np1 -i focaltech-ft9365.patch || true
```

**Note:** the patch will apply almost every hunk cleanly, but will fail on
one hunk related to the driver's ID table (the patch file contains two
overlapping historical revisions of the same change). The manual fix is
in `fix-patch-rejects.sh`, included in this repository.

```bash
bash ../fix-patch-rejects.sh
```

Verify it worked:

```bash
grep -c '0x6553' libfprint/drivers/focaltech_moc/focaltech_moc.c
# should print: 1
```

### 3. Build

```bash
meson setup builddir --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu \
  -Dudev_rules_dir=/lib/udev/rules.d \
  -Dudev_hwdb_dir=/lib/udev/hwdb.d
ninja -C builddir
```

**Note:** without explicitly setting `-Dudev_rules_dir` and
`-Dudev_hwdb_dir`, meson looks for a pkg-config package literally named
`udev`, which doesn't exist on Debian (it's called `libudev`), causing a
build error.

### 4. Install

```bash
sudo systemctl stop fprintd
sudo ninja -C builddir install
sudo ldconfig
sudo systemctl restart fprintd
```

Verify:

```bash
systemctl status fprintd.service    # should be "active (running)"
ldd /usr/libexec/fprintd | grep fprint
# should show: libfprint-2.so.2 => /lib/x86_64-linux-gnu/libfprint-2.so.2
```

### 5. Enroll your fingerprint

```bash
fprintd-enroll
fprintd-verify
```

### 6. Enable fingerprint only for sudo (recommended)

On GNOME/GDM, login and the lock screen share the same PAM file
(`/etc/pam.d/gdm-fingerprint`), independent from `common-auth`: **they
cannot be cleanly separated**. Enabling fingerprint everywhere via
`pam-auth-update` also comes with a known annoyance: after logging in
with a fingerprint, the GNOME keyring (saved passwords, WiFi, etc.)
doesn't unlock automatically, because its encryption key is derived from
the password that fingerprint login bypasses — resulting in an extra
"Unlock Login Keyring" popup every time.

For this reason, the recommended approach is to **limit fingerprint to
`sudo` only**, keeping regular password login for the login/lock screens
(which also unlocks the keyring with no extra popup):

```bash
# Disable fingerprint for login and lock screen
sudo mv /etc/pam.d/gdm-fingerprint /etc/pam.d/gdm-fingerprint.disabled

# Enable fingerprint ONLY for sudo
sudo sed -i '1i auth sufficient pam_fprintd.so' /etc/pam.d/sudo
```

Test:

```bash
sudo -k
sudo ls
```

It should prompt for your fingerprint. Login and lock screen will keep
asking for the password only.

#### Alternative: fingerprint everywhere

If you'd rather have fingerprint for login/lock screen too (and accept
the extra keyring popup, or work around it by choosing "sign in with
password" when you want to avoid it):

```bash
sudo pam-auth-update
```

Check **"Fingerprint authentication"**, while keeping
**"Unix authentication"** checked too (password stays available as a
fallback — never disable it).

## After a kernel/system update

A future `apt upgrade` might reinstall the system `libfprint-2-2`,
overwriting your build. If the sensor stops working after an update, just
re-run steps 3 and 4.

## Credits

- FocalTech MoC driver for Galaxy Book 4: [Merge Request #554](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/554) by Sid1803 (not yet merged upstream)
- Patch sourced from the [`libfprint-ft9365`](https://aur.archlinux.org/packages/libfprint-ft9365) AUR package by xCaptaiN09
- Debian adaptation and build troubleshooting: this repository

## Disclaimer

This procedure replaces a system library (`libfprint-2-2`) with a
manually built version. Never disable password authentication as a
fallback. Use at your own risk.
