# Samsung Galaxy Book 4 — Fingerprint Fix per Debian

*[Read this README in English](README.en.md)*

Abilita il sensore di impronte digitali FocalTech FT9365 (USB ID `2808:6553`)
sui Samsung Galaxy Book 4 (Pro, Ultra, 360) su **Debian** (testato su Debian
13 "trixie").

## Il problema

Il driver `focaltech_moc` di libfprint supporta diversi PID FocalTech, ma
**non** il `0x6553` usato dal Galaxy Book 4. Esiste una patch upstream non
ancora mergiata ([Merge Request #554](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/554)
di Sid1803), ma:

- I `.deb` precompilati circolanti online sono pensati per **Ubuntu** e
  falliscono su Debian con un errore di simboli mancanti:
  ```
  /lib/x86_64-linux-gnu/libgusb.so.2: version `LIBGUSB_0.2.8' not found
  ```
  (incompatibilità ABI tra le versioni di `libgusb` delle due distro)
- Il ref `merge-requests/554/head` **non è fetchabile** direttamente da
  GitLab per questo progetto (non tutti i progetti espongono i ref delle MR
  esterne)

La soluzione: compilare libfprint da sorgente in locale, applicando la patch
a mano. Compilando in locale, il binario risultante è linkato contro *le
tue* librerie di sistema — zero problemi di ABI.

## Verifica hardware

```bash
lsusb | grep "2808:6553"
```

Se non vedi nulla, questa guida non fa per te.

## Procedura

### 1. Dipendenze di build

```bash
sudo apt install build-essential meson ninja-build git \
  libglib2.0-dev libgusb-dev libnss3-dev libpixman-1-dev \
  libgirepository1.0-dev gtk-doc-tools libgudev-1.0-dev libcairo2-dev \
  python3-cairo python3-gi libssl-dev libudev-dev
```

### 2. Sorgenti e patch

```bash
git clone https://gitlab.freedesktop.org/libfprint/libfprint.git
cd libfprint
git checkout v1.94.10

# Scarica la patch dal pacchetto AUR libfprint-ft9365 (contiene la patch
# della MR #554 come file scaricabile, aggirando il problema del ref GitLab)
git clone https://aur.archlinux.org/libfprint-ft9365.git /tmp/ft9365-aur
cp /tmp/ft9365-aur/focaltech-ft9365.patch .
patch -Np1 -i focaltech-ft9365.patch || true
```

**Nota:** la patch applicherà quasi tutti gli hunk correttamente, ma
fallirà su un hunk relativo alla tabella degli ID del driver (perché il
patch file contiene due revisioni storiche sovrapposte della stessa
modifica). Il fix manuale è nello script `fix-patch-rejects.sh` incluso in
questo repository.

```bash
bash ../fix-patch-rejects.sh
```

Verifica che sia andato a buon fine:

```bash
grep -c '0x6553' libfprint/drivers/focaltech_moc/focaltech_moc.c
# deve stampare: 1
```

### 3. Compilazione

```bash
meson setup builddir --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu \
  -Dudev_rules_dir=/lib/udev/rules.d \
  -Dudev_hwdb_dir=/lib/udev/hwdb.d
ninja -C builddir
```

**Nota:** senza specificare `-Dudev_rules_dir` e `-Dudev_hwdb_dir`
esplicitamente, `meson` cerca un pacchetto pkg-config chiamato `udev`
che su Debian non esiste (si chiama `libudev`), causando un errore.

### 4. Installazione

```bash
sudo systemctl stop fprintd
sudo ninja -C builddir install
sudo ldconfig
sudo systemctl restart fprintd
```

Verifica:

```bash
systemctl status fprintd.service    # deve essere "active (running)"
ldd /usr/libexec/fprintd | grep fprint
# deve mostrare: libfprint-2.so.2 => /lib/x86_64-linux-gnu/libfprint-2.so.2
```

### 5. Registra l'impronta

```bash
fprintd-enroll
fprintd-verify
```

### 6. Abilita l'impronta SOLO per sudo (consigliato)

Su GNOME/GDM, il login e il lock screen usano lo stesso file PAM
(`/etc/pam.d/gdm-fingerprint`), indipendente da `common-auth`: **non è
possibile separarli** in modo pulito. Abilitare l'impronta ovunque tramite
`pam-auth-update` comporta anche un fastidio noto: dopo il login con
impronta, il portachiavi di GNOME (password salvate, WiFi, ecc.) non si
sblocca automaticamente, perché la sua chiave di cifratura è derivata
dalla password che l'impronta bypassa — risultato: un popup extra
"Unlock Login Keyring" ogni volta.

Per questo motivo, l'approccio consigliato è **limitare l'impronta al solo
`sudo`**, lasciando password normale per login e lock screen (che sblocca
anche il portachiavi senza popup extra):

```bash
# Disabilita l'impronta per login e lock screen
sudo mv /etc/pam.d/gdm-fingerprint /etc/pam.d/gdm-fingerprint.disabled

# Abilita l'impronta SOLO per sudo
sudo sed -i '1i auth sufficient pam_fprintd.so' /etc/pam.d/sudo
```

Testa:

```bash
sudo -k
sudo ls
```

Deve chiederti l'impronta. Login e lock screen continueranno invece a
chiedere solo la password.

#### In alternativa: impronta ovunque

Se preferisci comunque avere l'impronta anche per login/lock screen (e
accetti il popup extra del portachiavi, o lo gestisci scegliendo "accedi
con password" quando ti serve evitarlo):

```bash
sudo pam-auth-update
```

Spunta **"Fingerprint authentication"**, lasciando **attiva anche
"Unix authentication"** (la password resta sempre disponibile come
fallback — non disabilitarla mai).

## Dopo un aggiornamento del kernel/sistema

Un `apt upgrade` potrebbe in futuro reinstallare la `libfprint-2-2` di
sistema, sovrascrivendo la tua build. Se il sensore smette di funzionare
dopo un aggiornamento, rilancia semplicemente i passi 3 e 4.

## Crediti

- Driver FocalTech MoC per Galaxy Book 4: [Merge Request #554](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/554) di Sid1803 (non ancora mergiata upstream)
- Patch reperita dal pacchetto AUR [`libfprint-ft9365`](https://aur.archlinux.org/packages/libfprint-ft9365) di xCaptaiN09
- Adattamento per Debian e risoluzione dei problemi di build: questo repository

## Disclaimer

Questa procedura sostituisce una libreria di sistema (`libfprint-2-2`) con
una versione compilata manualmente. Non disabilitare mai la password come
metodo di autenticazione di fallback. Usa a tuo rischio.
