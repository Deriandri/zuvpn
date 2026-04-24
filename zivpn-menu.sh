#!/bin/bash
set +e

# ==========================================
# ZIVPN Menu - ALL IN ONE (WITH AUTO KILL)
# Fitur: Multi User, Auto Kill, Telegram Sync
# ==========================================

# --- BACKGROUND WORKER (SATURASI AUTO KILL) ---
# Dijalankan saat script dipanggil dengan: zivpn-menu --autokill
if [[ "$1" == "--autokill" ]]; then
    PORT="5667"
    LOG_FILE="/var/log/zivpn-kill.log"
    ZIVPN_DB="/etc/zivpn/users.db"
    
    while true; do
        if [ -f "$ZIVPN_DB" ]; then
            # Ambil limit tertinggi dari user yang aktif untuk patokan global kick
            MAX_LIMIT=$(awk -F'|' '{print $4}' "$ZIVPN_DB" | sort -nr | head -n1)
            [[ "$MAX_LIMIT" == "∞" || -z "$MAX_LIMIT" ]] && MAX_LIMIT=100
            
            # Hitung IP unik yang masuk ke port UDP
            IP_COUNT=$(ss -u -n state connected "( sport = :$PORT )" | grep -v "Local" | awk '{print $4}' | cut -d: -f1 | sort -u | wc -l)

            if [ "$IP_COUNT" -gt "$MAX_LIMIT" ]; then
                echo "[$(date)] Limit Terlampaui ($IP_COUNT > $MAX_LIMIT). Restarting Service..." >> $LOG_FILE
                systemctl restart zivpn > /dev/null 2>&1
                sleep 5
            fi
        fi
        sleep 30
    done
    exit 0
fi

# --- CONFIGURATION ---
CONFIG="/etc/zivpn/config.json"
DB="/etc/zivpn/users.db"
DOMAIN_FILE="/etc/zivpn/domain.conf"
TG_FILE="/etc/zivpn/telegram.conf"

mkdir -p /etc/zivpn
touch "$DB"
[ ! -f "$DOMAIN_FILE" ] && echo "-" > "$DOMAIN_FILE"
[ -f "$TG_FILE" ] && source "$TG_FILE"

DOMAIN=$(cat "$DOMAIN_FILE")

# ===== COLORS =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ===== SYSTEM INFO =====
OS=$(lsb_release -ds 2>/dev/null | tr -d '"')
IP=$(curl -s ifconfig.me)
UPTIME=$(uptime -p)
CPU=$(nproc)
ZIVPN_STATUS=$(systemctl is-active zivpn 2>/dev/null)
KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)

# ===== FUNCTIONS =====

send_telegram() {
  [ -z "$BOT_TOKEN" ] && return
  [ -z "$CHAT_ID" ] && return
  TEXT="$1"
  # FIX: HTML MODE agar kebal terhadap underscore (_)
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=$TEXT" \
    --data-urlencode "parse_mode=html" >/dev/null 2>&1
}

manage_autokill() {
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${WHITE}       MANAGE ZIVPN AUTO KILL ${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e " Status: $([[ "$KILL_STATUS" == "active" ]] && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped${NC}")"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${YELLOW} 1${NC}) Enable/Start Auto Kill"
    echo -e "${YELLOW} 2${NC}) Disable/Stop Auto Kill"
    echo -e "${YELLOW} 3${NC}) View Kill Logs"
    echo -e "${RED} 0${NC}) Back"
    read -rp " Select : " akopt
    case $akopt in
        1)
            cat > /etc/systemd/system/zivpn-kill.service <<EOF
[Unit]
Description=ZIVPN Auto Kill Service
After=network.target

[Service]
ExecStart=/usr/bin/zivpn-menu --autokill
Restart=always

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable zivpn-kill >/dev/null 2>&1
            systemctl start zivpn-kill >/dev/null 2>&1
            echo -e "${GREEN}Auto Kill Enabled!${NC}"
            sleep 2
            ;;
        2)
            systemctl stop zivpn-kill >/dev/null 2>&1
            systemctl disable zivpn-kill >/dev/null 2>&1
            echo -e "${RED}Auto Kill Disabled!${NC}"
            sleep 2
            ;;
        3)
            clear
            echo "--- Latest Kill Logs ---"
            tail -n 20 /var/log/zivpn-kill.log 2>/dev/null || echo "No logs yet."
            read -p "Press Enter..."
            ;;
    esac
}

create_account() {
    while true; do
        read -rp " Username : " USER
        [ -z "$USER" ] && echo "Username tidak boleh kosong!" && continue
        if grep -q "^$USER|" "$DB"; then
            echo "❌ Username '$USER' sudah ada!"
            continue
        fi
        break
    done

    read -rp " Duration (days) : " DAYS
    read -rp " IP Limit (1/2/3, 0=unlimit) : " LIMIT
    [ "$LIMIT" = "0" ] && LIMIT="∞"

    PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    EXP=$(date -d "$DAYS days +1 day" +"%Y-%m-%d 00:00")

    jq --arg pass "$PASS" '.auth.config += [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
    echo "$USER|$PASS|$EXP|$LIMIT" >> "$DB"
    systemctl restart zivpn

    MSG="<b>📢 PEMBELIAN BERHASIL</b>
────────────────────
👤 Username : $USER
🔐 Password : $PASS
⏳ Expired  : $EXP
📱 IP Limit : $LIMIT
────────────────────
✅ Type     : HARIAN"
    send_telegram "$MSG"

    clear
    echo -e "${GREEN}ACCOUNT CREATED${NC}"
    echo " Username : $USER"
    echo " Password : $PASS"
    echo " Expired  : $EXP"
    read -p "Press Enter..."
}

# --- MAIN MENU ---

menu() {
  USER_COUNT=$(grep -c '|' "$DB" 2>/dev/null)
  ZIVPN_STATUS=$(systemctl is-active zivpn 2>/dev/null)
  KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)

  clear
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${WHITE}        Z I V P N   MANAGER PRO ${NC}"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${GREEN} OS      ${NC}: $OS"
  echo -e "${GREEN} Domain  ${NC}: ${YELLOW}$DOMAIN${NC}"
  echo -e "${GREEN} ZIVPN   ${NC}: ${YELLOW}$ZIVPN_STATUS${NC}"
  echo -e "${GREEN} Kill-IP ${NC}: $([[ "$KILL_STATUS" == "active" ]] && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}")"
  echo -e "${GREEN} Users   ${NC}: ${YELLOW}$USER_COUNT${NC}"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${YELLOW} 1${NC}) Create Account"
  echo -e "${YELLOW} 2${NC}) List Accounts"
  echo -e "${YELLOW} 3${NC}) Delete Account"
  echo -e "${YELLOW} 4${NC}) Renew Account"
  echo -e "${YELLOW} 5${NC}) Restart ZIVPN"
  echo -e "${YELLOW} 6${NC}) Delete Expired"
  echo -e "${YELLOW} 7${NC}) IP Monitor"
  echo -e "${YELLOW} 8${NC}) Change Domain"
  echo -e "${YELLOW} 9${NC}) Update Menu"
  echo -e "${YELLOW}10${NC}) Create Trial"
  echo -e "${YELLOW}11${NC}) Telegram Bot"
  echo -e "${YELLOW}12${NC}) Backup & Restore"
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
2) clear; echo "LIST ACCOUNTS"; printf "%-15s %-15s %-15s %-5s\n" "User" "Pass" "Exp" "Lim"; echo "------------------------------------------------"; while IFS='|' read -r U P E L; do printf "%-15s %-15s %-15s %-5s\n" "$U" "$P" "$E" "$L"; done < "$DB"; read -p "Enter..." ;;
3) # logic delete account sama spt sebelumnya
   ;;
11) # telegram_setting function
   ;;
13) manage_autokill ;;
0) exit ;;
*) # biarkan menu jalan normal untuk opsi lainnya
   ;;
esac
done
