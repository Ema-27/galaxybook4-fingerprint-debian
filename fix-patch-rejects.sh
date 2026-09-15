#!/usr/bin/env bash
# Fix manuale per l'hunk della patch focaltech-ft9365.patch che fallisce
# sempre (la patch contiene due revisioni storiche sovrapposte della
# stessa modifica alla tabella degli ID del driver).
#
# Uso: lanciare dalla cartella libfprint/ DOPO aver applicato la patch
# principale con: patch -Np1 -i focaltech-ft9365.patch || true

set -e

FILE="libfprint/drivers/focaltech_moc/focaltech_moc.c"

if [ ! -f "$FILE" ]; then
    echo "Errore: $FILE non trovato. Esegui questo script dalla cartella libfprint/"
    exit 1
fi

if grep -q "0x6553" "$FILE"; then
    echo "Il PID 0x6553 è già presente in $FILE, niente da fare."
    exit 0
fi

# Trova la riga con 'static void' immediatamente precedente a
# fpi_device_focaltech_moc_samsung_class_init
LINE=$(grep -n "fpi_device_focaltech_moc_samsung_class_init" "$FILE" | head -1 | cut -d: -f1)

if [ -z "$LINE" ]; then
    echo "Errore: impossibile trovare fpi_device_focaltech_moc_samsung_class_init in $FILE"
    echo "La patch principale potrebbe non essersi applicata correttamente."
    exit 1
fi

# La riga 'static void' è quella subito sopra
INSERT_LINE=$((LINE - 1))

sed -i "${INSERT_LINE}i static const FpIdEntry id_table_samsung[] = {\n  { .vid = 0x2808, .pid = 0x6553, .driver_data = FOCALTECH_QUIRK_SINGLE_SLOT },\n  { .vid = 0, .pid = 0 }\n};\n" "$FILE"

if grep -q "0x6553" "$FILE"; then
    echo "Fix applicato correttamente. Verifica il contesto con:"
    echo "  grep -n -B5 -A10 id_table_samsung $FILE"
else
    echo "Il fix automatico non ha funzionato. Applica manualmente:"
    echo "  vedi README.md, sezione 'Fix manuale'"
    exit 1
fi
