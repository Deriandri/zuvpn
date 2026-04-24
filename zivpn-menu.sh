#!/bin/bash
set +e
# ZIVPN Menu - COLOR UI (MULTI USER)

CONFIG="/etc/zivpn/config.json"
DB="/etc/zivpn/users.db"
DOMAIN_FILE="/etc/zivpn/domain.conf"
TG_FILE="/etc/zivpn/telegram.conf"

mkdir -p /etc/zivpn
[ -f "$TG_FILE" ] && source "$TG_FILE"
DOMAIN=$(cat "$DOMAIN_FILE" 2>/dev/null || echo "localhost")

# Pastikan variabel bot tersedia untuk sub-process
export BOT_TOKEN="$BOT_TOKEN"
export CHAT_ID="$CHAT_ID"

# ... (Kode lainnya tetap sama sampai fungsi send_telegram) ...

send_telegram() {
  [ -z "$BOT_TOKEN" ] && return
  [ -z "$CHAT_ID" ] && return

  TEXT="$1"
  # FIX: Gunakan parse_mode=html agar karakter underscore (_) tidak error
  # Menghilangkan & agar perintah ini ditunggu sampai selesai sebelum script exit
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=$TEXT" \
    --data-urlencode "parse_mode=html" >/dev/null 2>&1
}

create_account() {
  # ... (Bagian input tetap sama) ...
  
  # Update tampilan pesan ke HTML agar sinkron dengan fungsi di atas
  MSG="<b>📢 PEMBELIAN BERHASIL</b>
────────────────────
🌐 Domain : $DOMAIN
👤 Username : $USER
🔐 Password : $PASS
⏳ Expired : $EXP
📱 IP Limit : $LIMIT
────────────────────
✅ Type : HARIAN"

  send_telegram "$MSG"

  clear
  echo -e "ACCOUNT CREATED"
  echo " Username      : $USER"
  echo " Password      : $PASS"
  echo " Expired       : $EXP"
  read -p "Press Enter..."
}

# ... (Sisa kode script VPS Bos tetap sama sampai akhir) ...
