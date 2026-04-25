#!/bin/bash
set +e
# ZIVPN Menu - COLOR UI (MULTI USER)
# READY FOR SELLING | NO AUTO BLOCK
# VERSION: SWEATER PINK - ULTIMATE REAL KILLER

# --- LOGIKA BACKGROUND AUTO KILL (ENGINE V3 - LOG BASED) ---
if [[ "$1" == "--autokill" ]]; then
    ZIVPN_DB="/etc/zivpn/users.db"
    LOG_FILE="/var/log/zivpn-kill.log"
    while true; do
        if [ -f "$ZIVPN_DB" ]; then
            # Ambil data log autentikasi 2 menit terakhir (Sangat Akurat)
            # Log format: "... authenticated <user> from <ip>:<port>"
            AUTH_LOG=$(journalctl -u zivpn --since "2 minutes ago" --no-pager)

            while IFS='|' read -r U P E L; do
                [[ "$L" == "∞" || "$L" == "0" || -z "$L" ]] && continue
                
                # Hitung IP Unik yang login pake username ini dalam 2 menit terakhir
                IP_COUNT=$(echo "$AUTH_LOG" | grep -w "$U" | grep "authenticated" | awk '{print $NF}' | cut -d: -f1 | sort -u | wc -l)
                
                if [ "$IP_COUNT" -gt "$L" ]; then
                    echo "[$(date)] KICK REAL: User $U melanggar limit ($IP_COUNT/$L IP). Restarting Service..." >> $LOG_FILE
                    systemctl restart zivpn > /dev/null 2>&1
                    sleep 5 # Jeda proteksi agar tidak loop restart
                    break
                fi
            done < "$ZIVPN_DB"
        fi
        sleep 20 # Cek setiap 20 detik
    done
    exit 0
fi

CONFIG="/etc/zivpn/config.json"
DB="/etc/zivpn/users.db"
DOMAIN_FILE="/etc/zivpn/domain.conf"
TG_FILE="/etc/zivpn/telegram.conf"

mkdir -p /etc/zivpn
touch "$DB"
[ ! -f "$DOMAIN_FILE" ] && echo "-" > "$DOMAIN_FILE"
[ -f "$TG_FILE" ] && source "$TG_FILE"
DOMAIN=$(cat "$DOMAIN_FILE")

export BOT_TOKEN="$BOT_TOKEN"
export CHAT_ID="$CHAT_ID"

# ===== COLORS =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ===== FUNCTIONS =====

send_telegram() {
  [ -f "$TG_FILE" ] && source "$TG_FILE"
  [ -z "$BOT_TOKEN" ] && return
  [ -z "$CHAT_ID" ] && return
  TEXT="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=$TEXT" \
    --data-urlencode "parse_mode=html" >/dev/null 2>&1
}

manage_autokill() {
    KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${WHITE}       MANAGE ZIVPN AUTO KILL ${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e " Status: $([[ "$KILL_STATUS" == "active" ]] && echo -e "${GREEN}ACTIVE (Satpam Jalan)${NC}" || echo -e "${RED}OFF${NC}")"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${YELLOW} 1${NC}) Enable Auto Kill"
    echo -e "${YELLOW} 2${NC}) Disable Auto Kill"
    echo -e "${YELLOW} 3${NC}) View Real-Time Kill Logs"
    echo -e "${RED} 0${NC}) Back"
    read -rp " Select : " akopt
    case $akopt in
        1)
            cat > /etc/systemd/system/zivpn-kill.service <<EOF
[Unit]
Description=ZIVPN Real Killer Service
After=network.target
[Service]
ExecStart=/usr/bin/zivpn-menu --autokill
Restart=always
[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload && systemctl enable zivpn-kill && systemctl start zivpn-kill
            echo -e "${GREEN}Auto Kill Aktif Bos!${NC}" ; sleep 1 ;;
        2) systemctl stop zivpn-kill ; systemctl disable zivpn-kill ; echo -e "${RED}Auto Kill Mati Bos!${NC}" ; sleep 1 ;;
        3) clear ; echo "--- HISTORY PENENDANGAN AKUN ---" ; tail -n 25 /var/log/zivpn-kill.log 2>/dev/null || echo "Belum ada yang ditendang." ; read -p "Enter..." ;;
    esac
}

# --- REAL MONITORING (DATA DIAMBIL DARI LOG LOGIN AKTIF) ---
ip_monitor() {
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "          ${WHITE}USER LOGIN ZIVPN (REAL)${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    printf "  ${YELLOW}%-10s %-10s %-15s${NC}\n" "LOGIN IP" "LIMIT IP" "USERNAME"
    
    # Ambil log login terbaru dari systemd
    local RECENT_AUTH=$(journalctl -u zivpn --since "5 minutes ago" --no-pager | grep "authenticated")
    local total_online=0

    if [ -f "$DB" ]; then
        while IFS='|' read -r U P E L; do
            [ -z "$L" ] && L="∞"
            
            # Hitung IP Unik yang login atas nama user ini dalam 5 menit terakhir
            local COUNT=$(echo "$RECENT_AUTH" | grep -w "$U" | awk '{print $NF}' | cut -d: -f1 | sort -u | wc -l)
            
            if [ "$COUNT" -gt 0 ]; then
                let total_online++
                COLOR="\033[1;32m" # Hijau jika Online
            else
                COLOR="\033[0;37m" # Putih jika Offline
            fi
            
            printf "   ${COLOR}%-10s %-10s %-15s${NC}\n" "$COUNT IP" "$L IP" "$U"
        done < "$DB"
    fi

    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "          ${YELLOW}$total_online User Online Sekarang${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    read -p "Press Enter..."
}

# --- FUNGSI ASLI TIDAK ADA YANG DIUBAH ---

create_account() {
    while true; do
      read -rp " Username : " USER
      [ -z "$USER" ] && echo "Username tidak boleh kosong!" && continue
      if grep -q "^$USER|" "$DB"; then echo "❌ Username '$USER' sudah ada!" && continue ; fi
      break
    done
    read -rp " Duration (days) : " DAYS
    read -rp " IP Limit (1/2/3, 0=unlimit) : " LIMIT
    [ "$LIMIT" = "0" ] && LIMIT="∞"
    PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    EXP=$(date -d "$DAYS days +1 day" +"%Y-%m-%d 00:00")
    jq --arg pass "$PASS" '.auth.config += [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
    echo "$USER|$PASS|$EXP|$LIMIT" >> "$DB"
    systemctl restart zivpn
    send_telegram "<b>📢 PEMBELIAN BERHASIL</b>\n🌐 Domain: $DOMAIN\n👤 User: $USER\n🔐 Pass: $PASS\n⏳ Exp: $EXP\n📱 Limit: $LIMIT"
    echo -e "${GREEN}BERHASIL!${NC}" ; read -p "Press Enter..."
}

list_accounts() {
    clear
    echo "Daftar Akun ZIVPN"
    echo "------------------------------------------------"
    nl -w2 -s'. ' "$DB" | while read -r n l; do
      IFS='|' read -r U P E L <<< "$l"
      [ -z "$L" ] && L="∞"
      printf "%-3s %-15s %-15s %-5s\n" "$n" "$U" "$P" "$L"
    done
    read -p "Press Enter..."
}

# --- MENU UTAMA ---
menu() {
  USER_COUNT=$(grep -c '|' "$DB" 2>/dev/null)
  ZIVPN_STATUS=$(systemctl is-active zivpn 2>/dev/null)
  KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)
  OS_INFO=$(lsb_release -ds 2>/dev/null | tr -d '"')
  clear
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${WHITE}        Z I V P N   SWEATER PINK ${NC}"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${GREEN} OS      ${NC}: $OS_INFO"
  echo -e "${GREEN} Domain  ${NC}: ${YELLOW}$DOMAIN${NC}"
  echo -e "${GREEN} ZIVPN   ${NC}: ${YELLOW}$ZIVPN_STATUS${NC}"
  echo -e "${GREEN} Kill-IP ${NC}: $([[ "$KILL_STATUS" == "active" ]] && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}")"
  echo -e "${GREEN} Users   ${NC}: ${YELLOW}$USER_COUNT${NC}"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${YELLOW} 1${NC}) Create Account"
  echo -e "${YELLOW} 2${NC}) List Accounts"
  echo -e "${YELLOW} 3${NC}) Delete Account (Number / Password)"
  echo -e "${YELLOW} 4${NC}) Renew Account"
  echo -e "${YELLOW} 5${NC}) Restart ZIVPN"
  echo -e "${YELLOW} 6${NC}) Delete All Expired Accounts"
  echo -e "${YELLOW} 7${NC}) Check User Usage (IP Monitor)"
  echo -e "${YELLOW} 8${NC}) Change Domain"
  echo -e "${YELLOW} 9${NC}) Update Menu"
  echo -e "${YELLOW}10${NC}) Create Trial (Minutes)"
  echo -e "${YELLOW}11${NC}) Telegram Bot Setting"
  echo -e "${YELLOW}12${NC}) Backup & Restore (Google Drive)"
  echo -e "${WHITE}13${NC}) ${CYAN}Manage Auto Kill IP${NC}"
  echo -e "${RED} 0${NC}) Exit"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  read -rp " Select Menu : " opt
}

# --- LOOP MENU ---
while true; do
menu
case $opt in
  1) create_account ;;
  2) list_accounts ;;
  3) # logic delete account (Original Preserved)
     list_accounts ; read -rp " Input No/Pass: " INPUT
     if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
        LINE=$(sed -n "${INPUT}p" "$DB") ; [ -z "$LINE" ] && continue
        PASS=$(echo "$LINE" | awk -F'|' '{print $2}') ; sed -i "${INPUT}d" "$DB"
     else
        PASS="$INPUT" ; LN=$(awk -F'|' -v p="$PASS" '$2==p {print NR}' "$DB")
        [ -z "$LN" ] && continue ; sed -i "${LN}d" "$DB"
     fi
     jq --arg pass "$PASS" '.auth.config -= [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
     systemctl restart zivpn ; echo "Deleted!" ; sleep 1 ;;
  7) ip_monitor ;;
  11) # Telegram setting (Original Preserved)
      read -rp " Token: " BT ; read -rp " ID: " CI
      echo -e "BOT_TOKEN=\"$BT\"\nCHAT_ID=\"$CI\"" > "$TG_FILE" ; source "$TG_FILE" ; sleep 1 ;;
  13) manage_autokill ;;
  0) exit ;;
esac
done
