#!/bin/bash
set +e

# ==========================================
# ZIVPN Menu - PRO EDITION (ALL FUNCTIONS)
# Fitur: Multi User, Auto Kill, Telegram Sync
# ==========================================

# --- BACKGROUND WORKER (AUTO KILL LOGIC) ---
if [[ "$1" == "--autokill" ]]; then
    PORT="5667"
    LOG_FILE="/var/log/zivpn-kill.log"
    ZIVPN_DB="/etc/zivpn/users.db"
    while true; do
        if [ -f "$ZIVPN_DB" ]; then
            # Ambil limit tertinggi dari database untuk patokan penendangan
            MAX_LIMIT=$(awk -F'|' '{print $4}' "$ZIVPN_DB" | sort -nr | head -n1)
            [[ "$MAX_LIMIT" == "∞" || -z "$MAX_LIMIT" ]] && MAX_LIMIT=100
            
            IP_COUNT=$(ss -u -n state connected "( sport = :$PORT )" | grep -v "Local" | awk '{print $4}' | cut -d: -f1 | sort -u | wc -l)
            if [ "$IP_COUNT" -gt "$MAX_LIMIT" ]; then
                echo "[$(date)] Limit Exceeded ($IP_COUNT > $MAX_LIMIT). Restarting ZIVPN..." >> $LOG_FILE
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
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')

# ===== TELEGRAM FUNCTION (FIXED HTML) =====
send_telegram() {
  [ -z "$BOT_TOKEN" ] && return
  [ -z "$CHAT_ID" ] && return
  TEXT="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=$TEXT" \
    --data-urlencode "parse_mode=html" >/dev/null 2>&1
}

# ===== AUTO KILL MANAGER =====
manage_autokill() {
    KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${WHITE}       MANAGE ZIVPN AUTO KILL ${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e " Status: $([[ "$KILL_STATUS" == "active" ]] && echo -e "${GREEN}Running${NC}" || echo -e "${RED}Stopped${NC}")"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${YELLOW} 1${NC}) Enable Auto Kill"
    echo -e "${YELLOW} 2${NC}) Disable Auto Kill"
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
            echo -e "${GREEN}Auto Kill Enabled!${NC}" ; sleep 2 ;;
        2)
            systemctl stop zivpn-kill >/dev/null 2>&1
            systemctl disable zivpn-kill >/dev/null 2>&1
            echo -e "${RED}Auto Kill Disabled!${NC}" ; sleep 2 ;;
        3) clear ; echo "--- Latest Logs ---" ; tail -n 20 /var/log/zivpn-kill.log 2>/dev/null || echo "No logs." ; read -p "Press Enter..." ;;
    esac
}

# ===== ORIGINAL FUNCTIONS =====

list_accounts() {
    clear
    echo "--------------------------------------------------------------------------"
    printf "%-4s %-15s %-18s %-16s %-8s\n" "No" "Username" "Password" "Expired" "Limit"
    echo "--------------------------------------------------------------------------"
    nl -w2 -s'. ' "$DB" | while read -r n l; do
      IFS='|' read -r U P E L <<< "$l"
      [ -z "$L" ] && L="∞"
      printf "%-4s %-15s %-18s %-16s %-8s\n" "$n" "$U" "$P" "$E" "$L"
    done
    echo "--------------------------------------------------------------------------"
    read -p "Press Enter..."
}

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
    PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    EXP=$(date -d "$DAYS days +1 day" +"%Y-%m-%d 00:00")
    jq --arg pass "$PASS" '.auth.config += [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
    echo "$USER|$PASS|$EXP|$LIMIT" >> "$DB"
    systemctl restart zivpn
    send_telegram "<b>📢 PEMBELIAN BERHASIL</b>
────────────────────
👤 Username : $USER
🔐 Password : $PASS
⏳ Expired  : $EXP
📆 Aktif    : $DAYS Hari
📱 IP Limit : $LIMIT
────────────────────
✅ Type     : HARIAN"
    clear
    echo -e "${GREEN}ACCOUNT CREATED${NC}"
    echo " Username : $USER"
    echo " Password : $PASS"
    echo " Expired  : $EXP"
    read -p "Press Enter..."
}

create_trial() {
    read -rp " Trial duration (minutes): " MIN
    [[ -z "$MIN" || "$MIN" -le 0 ]] && return
    USER="trial$(tr -dc 0-9 </dev/urandom | head -c 4)"
    PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    EXP=$(date -d "+$MIN minutes" +"%Y-%m-%d %H:%M")
    LIMIT=1
    jq --arg pass "$PASS" '.auth.config += [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
    echo "$USER|$PASS|$EXP|$LIMIT" >> "$DB"
    systemctl restart zivpn
    send_telegram "<b>⏱ ZIVPN TRIAL ACCOUNT</b>
────────────────────
👤 Username : $USER
🔐 Password : $PASS
⏳ Expired  : $EXP
────────────────────
⚡ Type     : TRIAL (${MIN} Min)"
    clear
    echo -e "${GREEN}TRIAL CREATED${NC}"
    echo " Username : $USER"
    echo " Password : $PASS"
    read -p "Press Enter..."
}

change_domain() {
    read -rp " New Domain : " NEWDOMAIN
    [ -z "$NEWDOMAIN" ] && return
    echo "$NEWDOMAIN" > "$DOMAIN_FILE"
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=VPN/L=ZIVPN/O=ZIVPN/OU=ZIVPN/CN=$NEWDOMAIN" \
    -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt 2>/dev/null
    systemctl restart zivpn
    DOMAIN="$NEWDOMAIN"
    echo -e "${GREEN}Domain updated!${NC}" ; sleep 2
}

ip_monitor() {
    clear
    echo "USER USAGE MONITOR"
    echo "--------------------------------------------------"
    TOTAL_IP=$(ss -u -n state connected '( sport = :5667 )' | wc -l)
    while IFS='|' read -r U P E L; do
      [ -z "$L" ] && L="∞"
      STATUS=$([ "$TOTAL_IP" -gt 0 ] && echo "ONLINE" || echo "OFFLINE")
      printf "%-10s %-18s %-8s %-10s\n" "$U" "$P" "$L" "$STATUS"
    done < "$DB"
    echo "--------------------------------------------------"
    echo "Total IP Active: $TOTAL_IP"
    read -p "Press Enter..."
}

renew_account() {
    list_accounts
    read -rp " Renew number : " NUM
    read -rp " Extend days : " DAYS
    LINE=$(sed -n "${NUM}p" "$DB")
    [ -z "$LINE" ] && return
    IFS='|' read -r U P E L <<< "$LINE"
    BASE_DATE=$(echo "$E" | cut -d' ' -f1)
    NEWEXP=$(date -d "$BASE_DATE +$DAYS days +1 day" +"%Y-%m-%d 00:00")
    sed -i "${NUM}c\\$U|$P|$NEWEXP|$L" "$DB"
    systemctl restart zivpn
    echo -e "${GREEN}Renew Success!${NC}" ; sleep 2
}

delete_all_expired() {
    NOW=$(date +"%Y-%m-%d %H:%M")
    TMP="/tmp/zivpn-clean.db"
    > "$TMP"
    while IFS='|' read -r U P E L; do
      if [[ "$E" < "$NOW" ]]; then
        jq --arg pass "$P" '.auth.config -= [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
      else echo "$U|$P|$E|$L" >> "$TMP" ; fi
    done < "$DB"
    mv "$TMP" "$DB"
    systemctl restart zivpn
    echo -e "${GREEN}Cleaned!${NC}" ; sleep 2
}

delete_account() {
    list_accounts
    read -rp " Input No/Pass : " INPUT
    if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
      LINE=$(sed -n "${INPUT}p" "$DB")
      [ -z "$LINE" ] && return
      PASS=$(echo "$LINE" | awk -F'|' '{print $2}')
      sed -i "${INPUT}d" "$DB"
    else
      PASS="$INPUT"
      LINE_NUM=$(awk -F'|' -v p="$PASS" '$2==p {print NR}' "$DB")
      [ -z "$LINE_NUM" ] && return
      sed -i "${LINE_NUM}d" "$DB"
    fi
    jq --arg pass "$PASS" '.auth.config -= [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
    systemctl restart zivpn
    echo -e "${GREEN}Deleted!${NC}" ; sleep 2
}

telegram_setting() {
    clear
    read -rp " Bot Token : " BOT_TOKEN
    read -rp " Chat ID   : " CHAT_ID
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        echo -e "BOT_TOKEN=\"$BOT_TOKEN\"\nCHAT_ID=\"$CHAT_ID\"" > "$TG_FILE"
        chmod 600 "$TG_FILE"
        echo "Saved!" ; sleep 2
    fi
}

backup_restore_drive() {
    clear
    echo "1) Backup Now  2) Restore  3) Enable Auto Backup  4) Disable  0) Back"
    read -rp " Select : " br
    case $br in
        1) backup_zivpn_drive ;;
        2) restore_zivpn_drive ;;
        3) enable_autobackup ;;
        4) disable_autobackup ;;
    esac
}

enable_autobackup() {
    (crontab -l 2>/dev/null | grep -v zivpn-menu ; echo "0 3 * * * /usr/bin/zivpn-menu --autobackup") | crontab -
    echo "Enabled 03:00" ; sleep 2
}

disable_autobackup() {
    crontab -l 2>/dev/null | grep -v zivpn-menu | crontab -
    echo "Disabled" ; sleep 2
}

backup_zivpn_drive() {
    [ -z "$BOT_TOKEN" ] && echo "Bot not set!" && return
    DATE=$(date +%Y%m%d-%H%M)
    FILE="/root/zivpn-backup-$DATE.zip"
    zip -r "$FILE" /etc/zivpn/ /root/.config/rclone/rclone.conf >/dev/null 2>&1
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" -F chat_id="$CHAT_ID" -F document=@"$FILE" >/dev/null
    rm -f "$FILE"
    echo "Backup Sent!" ; sleep 2
}

restore_zivpn_drive() {
    read -rp " File Path Telegram : " FILE_PATH
    FILE="/root/restore.zip"
    wget -qO "$FILE" "https://api.telegram.org/file/bot$BOT_TOKEN/$FILE_PATH"
    [ -f "$FILE" ] && unzip -o "$FILE" -d / >/dev/null 2>&1 && rm -f "$FILE" && systemctl restart zivpn && echo "Restored!" ; sleep 2
}

# --- MAIN MENU UI ---
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
  echo -e "${YELLOW} 6${NC}) Delete All Expired"
  echo -e "${YELLOW} 7${NC}) Check Usage (IP Monitor)"
  echo -e "${YELLOW} 8${NC}) Change Domain"
  echo -e "${YELLOW} 9${NC}) Update Menu"
  echo -e "${YELLOW}10${NC}) Create Trial"
  echo -e "${YELLOW}11${NC}) Telegram Bot Setting"
  echo -e "${YELLOW}12${NC}) Backup & Restore"
  echo -e "${WHITE}13${NC}) ${CYAN}Manage Auto Kill IP${NC}"
  echo -e "${RED} 0${NC}) Exit"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  read -rp " Select Menu : " opt
}

# --- CRON AUTO BACKUP ---
if [[ "$1" == "--autobackup" ]]; then backup_zivpn_drive ; exit 0 ; fi

# --- EXECUTION LOOP ---
while true; do
menu
case $opt in
  1) create_account ;;
  2) list_accounts ;;
  3) delete_account ;;
  4) renew_account ;;
  5) systemctl restart zivpn ; echo "Restarted" ; sleep 1 ;;
  6) delete_all_expired ;;
  7) ip_monitor ;;
  8) change_domain ;;
  9) echo "Updating..." ; sleep 1 ; exec /usr/bin/zivpn-menu ;;
  10) create_trial ;;
  11) telegram_setting ;;
  12) backup_restore_drive ;;
  13) manage_autokill ;;
  0) exit ;;
esac
done
