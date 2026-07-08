#!/usr/bin/env bash
#
# Emulator'daki her Auth kullanicisi icin users/{uid}.organizationId ve
# organizations/{uid} dokumanlarini olusturur. SADECE localhost emulator'a yazar,
# production'a (ari-yapi-takip) DOKUNMAZ. Idempotent'tir; hicbir veriyi silmez.
#
# On kosul:
#   1) Baska bir terminalde ./scripts/emulator.sh calisiyor olmali.
#   2) Uygulamada en az bir kez kaydolmus/giris yapmis olmalisiniz
#      (flutter run --dart-define=USE_EMULATOR=true).
#
# Kullanim:
#   ./scripts/seed.sh                              # her kullanici kendi org'unun admin'i
#   SEED_ORG_ID=<admin1_uid> ./scripts/seed.sh     # tum kullanicilari tek org'a bagla
set -euo pipefail
cd "$(dirname "$0")/.."
exec dart run scripts/seed_emulator.dart "$@"
