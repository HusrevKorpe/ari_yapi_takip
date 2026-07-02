#!/usr/bin/env bash
#
# Yerel Firebase Emulator Suite'i baslatir (Firestore + Auth).
# Test verisi cikista ./emulator-data klasorune kaydedilir ve bir sonraki
# acilista geri yuklenir. Production projesine (ari-yapi-takip) DOKUNMAZ.
#
# Kullanim:
#   ./scripts/emulator.sh            # emulator'i baslat (bu terminali acik birak)
#
# Ayri bir terminalde uygulamayi emulator'a baglayarak calistir:
#   flutter run --dart-define=USE_EMULATOR=true
#
# Emulator arayuzu: http://127.0.0.1:4000
set -euo pipefail

# Proje koku (bu script scripts/ altinda)
cd "$(dirname "$0")/.."

DATA_DIR="emulator-data"
ARGS=(--only firestore,auth --export-on-exit="$DATA_DIR")

# Onceki testten kaydedilmis veri varsa geri yukle.
if [ -f "$DATA_DIR/firebase-export-metadata.json" ]; then
  ARGS+=(--import="$DATA_DIR")
  echo "↻ Onceki test verisi '$DATA_DIR' klasorunden geri yukleniyor..."
fi

exec firebase emulators:start "${ARGS[@]}"
