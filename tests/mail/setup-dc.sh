#!/bin/bash
# dc makinesinde: posta testinin kullanıcılarını açar. Yalnızca test parolaları.
set -euo pipefail
user() { # <ad> <parola> <adres>
    samba-tool user show "$1" >/dev/null 2>&1 && return
    samba-tool user create "$1" "$2" --mail-address="$3"
    samba-tool user setexpiry "$1" --noexpiry
}
user ali  'Ali-Parola-2026!'  ali@ornek.test
user ayse 'Ayse-Parola-2026!' ayse@ornek.test
samba-tool user disable ayse
