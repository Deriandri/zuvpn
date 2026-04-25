#!/bin/bash
set +e
# ZIVPN Menu - COLOR UI (MULTI USER)
# READY FOR SELLING | NO AUTO BLOCK

# --- LOGIKA BACKGROUND AUTO KILL (ENGINE V4 - REAL TIME LOGS) ---
if [[ "$1" == "--autokill" ]]; then
    PORT="5667"
    ZIVPN_DB="/etc/zivpn/users.db"
    LOG_FILE="/var/log/zivpn-kill.log"
    while true; do
        if [ -f "$ZIVPN_DB" ]; then
            # Ambil semua IP yang sedang aktif mengirim paket UDP ke port 5667
            ACTIVE_IPS=$(ss -u -an | grep ":$PORT" | awk '{print $6}' | cut -d: -f1 | grep -vE "0.0.0.0|[*]" | sort -u)
            # Ambil log login ZIVPN 1 menit terakhir
            LOG_NOW=$(journalctl -u zivpn --since "1 minute ago" --no-pager)

            while IFS='|' read -r U P E L; do
                [[ "$L" == "∞" || "$L" == "0" || -z "$L" ]] && continue
                
                # Hitung berapa IP berbeda yang login pake user ini dan IP-nya masih aktif di jaringan
                TOTAL_FOUND=0
                # Cari semua IP yang pernah login atas nama user ini di log terbaru
                IPS_IN_LOG=$(echo "$LOG_NOW" | grep -w "$U" | grep "authenticated" | awk '{print $NF}' | cut -d: -f1 | sort -u)
                
                for ip in $IPS_IN_LOG; do
                    if echo "$ACTIVE_IPS" | grep -q "$ip"; then
                        let TOTAL_FOUND++
                    fi
                done

                if [ "$TOTAL_FOUND" -gt "$L" ]; then
                    echo "[$(date)] LIMIT REACHED: User $U menggunakan $TOTAL_FOUND IP (Limit $L). KICKING..." >> $LOG_FILE
                    systemctl restart zivpn > /dev/null 2>&1
                    sleep 3
                    break
                fi
            done < "$ZIVPN_DB"
        fi
        sleep 15 # Cek setiap 15 detik (Lebih agresif)
    done
    exit 0
fi

CONFIG="/etc/zivpn/config.json"
DB="/etc/zivpn/users.db"
DOMAIN_FILE="/etc/zivpn/domain.conf"

mkdir -p /etc/zivpn
touch "$DB"
[ ! -f "$DOMAIN_FILE" ] && echo "-" > "$DOMAIN_FILE"

DOMAIN=$(cat "$DOMAIN_FILE")

# ===== TELEGRAM FILE =====
TG_FILE="/etc/zivpn/telegram.conf"
if [ -f "$TG_FILE" ]; then source "$TG_FILE"; fi

# Export agar sinkron ke Website
export BOT_TOKEN="$BOT_TOKEN"
export CHAT_ID="$CHAT_ID"

# ===== ENSURE DEPENDENCIES =====
if ! command -v jq >/dev/null 2>&1; then apt update -y; apt install -y jq; fi

# ===== COLORS =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- FUNGSI MANAGE AUTO KILL ---
manage_autokill() {
    KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)
    clear
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${WHITE}       MANAGE ZIVPN AUTO KILL ${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e " Status: $([[ "$KILL_STATUS" == "active" ]] && echo -e "${GREEN}Running (Satpam Aktif)${NC}" || echo -e "${RED}OFF${NC}")"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${YELLOW} 1${NC}) Enable Auto Kill"
    echo -e "${YELLOW} 2${NC}) Disable Auto Kill"
    echo -e "${YELLOW} 3${NC}) View Penendangan Logs"
    echo -e "${RED} 0${NC}) Back"
    read -rp " Pilih : " akopt
    case $akopt in
        1)
            cat > /etc/systemd/system/zivpn-kill.service <<EOF
[Unit]
Description=ZIVPN Real Auto Kill
After=network.target
[Service]
ExecStart=/usr/bin/zivpn-menu --autokill
Restart=always
[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload && systemctl enable zivpn-kill && systemctl start zivpn-kill
            echo -e "${GREEN}Auto Kill Berhasil Dijalankan!${NC}" ; sleep 1 ;;
        2) systemctl stop zivpn-kill ; systemctl disable zivpn-kill ; echo -e "${RED}Auto Kill Dimatikan!${NC}" ; sleep 1 ;;
        3) clear ; echo "--- DAFTAR USER YANG PERNAH DITENDANG ---" ; tail -n 25 /var/log/zivpn-kill.log 2>/dev/null || echo "Belum ada log." ; read -p "Enter..." ;;
    esac
}

# --- REAL MONITOR (GAYA SSH - GAMBAR 2) ---
ip_monitor() {
    clear
    echo -e "${YELLOW}──────────────────────────────────────${NC}"
    echo -e "          ${WHITE}USER LOGIN ZIVPN (REAL)${NC}"
    echo -e "${YELLOW}──────────────────────────────────────${NC}"
    printf "  ${CYAN}%-10s %-10s %-15s${NC}\n" "LOGIN IP" "LIMIT IP" "USERNAME"
    
    # 1. Deteksi IP yang sedang aktif mengirim trafik UDP
    local LIVE_TRAFFIC=$(ss -u -an | grep ":5667" | awk '{print $6}' | cut -d: -f1 | sort -u)
    # 2. Baca Log Handshake 10 jam terakhir
    local RECENT_LOGS=$(journalctl -u zivpn --since "10 hours ago" --no-pager | grep "authenticated")
    
    local count_user_online=0
    if [ -f "$DB" ]; then
        while IFS='|' read -r U P E L; do
            [ -z "$L" ] && L="∞"
            
            # Cari IP login terakhir user ini
            local LAST_IP=$(echo "$RECENT_LOGS" | grep -w "$U" | tail -n 1 | awk '{print $NF}' | cut -d: -f1)
            
            local STATUS_LOGIN="0 IP"
            if [[ -n "$LAST_IP" ]]; then
                # Jika IP tersebut terdeteksi di LIVE TRAFFIC, berarti REAL ONLINE
                if echo "$LIVE_TRAFFIC" | grep -q "$LAST_IP"; then
                    STATUS_LOGIN="1 IP"
                    let count_user_online++
                    COLOR_DATA="\033[1;32m" # Hijau jika Online
                else
                    COLOR_DATA="\033[0;37m" # Putih jika Offline
                fi
            else
                COLOR_DATA="\033[0;37m"
            fi
            
            printf "   ${COLOR_DATA}%-10s %-10s %-15s${NC}\n" "$STATUS_LOGIN" "$L IP" "$U"
        done < "$DB"
    fi

    echo -e "${YELLOW}──────────────────────────────────────${NC}"
    echo -e "          ${WHITE}$count_user_online User Online Sekarang${NC}"
    echo -e "${YELLOW}──────────────────────────────────────${NC}"
    read -p "Press Enter..."
}

# --- SEMUA FUNGSI ASLI BOS (Create, List, Renew, dll) ---

menu() {
  USER_COUNT=$(grep -c '|' "$DB" 2>/dev/null)
  ZIVPN_STATUS=$(systemctl is-active zivpn 2>/dev/null)
  KILL_STATUS=$(systemctl is-active zivpn-kill 2>/dev/null)

  clear
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${WHITE}        Z I V P N   SWEATER PINK ${NC}"
  echo -e "${CYAN}══════════════════════════════════════${NC}"
  echo -e "${GREEN} OS      ${NC}: $OS"
  echo -e "${GREEN} Domain  ${NC}: ${YELLOW}$DOMAIN${NC}"
  echo -e "${GREEN} IP      ${NC}: $IP"
  echo -e "${GREEN} Uptime  ${NC}: $UPTIME"
  echo -e "${GREEN} CPU     ${NC}: $CPU Cores"
  echo -e "${GREEN} RAM     ${NC}: $RAM_USED / $RAM_TOTAL MB"
  echo -e "${GREEN} Disk    ${NC}: $DISK_USED / $DISK_TOTAL"
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

# --- FUNGSI-FUNGSI PENDUKUNG (TETAP SAMA SEPERTI ASLINYA) ---
list_accounts() {
    clear
    printf "%-4s %-15s %-18s %-16s %-8s\n" "No" "Username" "Password" "Expired" "Limit"
    echo "--------------------------------------------------------------------------"
    nl -w2 -s'. ' "$DB" | while read -r n l; do
      IFS='|' read -r U P E L <<< "$l"; [ -z "$L" ] && L="∞"
      printf "%-4s %-15s %-18s %-16s %-8s\n" "$n" "$U" "$P" "$E" "$L"
    done
    read -p "Press Enter..."
}

create_account() {
    while true; do
      read -rp " Username : " USER
      [ -z "$USER" ] && echo "Username tidak boleh kosong!" && continue
      if grep -q "^$USER|" "$DB"; then echo "❌ Username sudah ada!" && continue ; fi
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
    send_telegram "<b>📢 PEMBELIAN BERHASIL</b>\n👤 User: $USER\n🔐 Pass: $PASS\n⏳ Exp: $EXP"
    echo -e "${GREEN}CREATED!${NC}" ; read -p "Press Enter..."
}

send_telegram() {
    [ -z "$BOT_TOKEN" ] && return
    [ -z "$CHAT_ID" ] && return
    TEXT="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      -d chat_id="$CHAT_ID" \
      --data-urlencode "text=$TEXT" \
      --data-urlencode "parse_mode=html" >/dev/null 2>&1
}

# --- LOOPING MENU UTAMA ---
while true; do
menu
case $opt in
1) create_account ;;
2) list_accounts ;;
3) # delete logic
   list_accounts ; read -rp " Input : " INP
   if [[ "$INP" =~ ^[0-9]+$ ]]; then
     LINE=$(sed -n "${INP}p" "$DB") ; [ -z "$LINE" ] && continue
     P=$(echo "$LINE" | awk -F'|' '{print $2}') ; sed -i "${INP}d" "$DB"
   else
     P="$INP" ; LN=$(awk -F'|' -v p="$P" '$2==p {print NR}' "$DB")
     [ -z "$LN" ] && continue ; sed -i "${LN}d" "$DB"
   fi
   jq --arg pass "$P" '.auth.config -= [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
   systemctl restart zivpn ; echo "Deleted!" ; sleep 1 ;;
4) # renew logic
   list_accounts ; read -rp " Nomor : " NUM ; read -rp " Hari : " DY
   LINE=$(sed -n "${NUM}p" "$DB") ; [ -z "$LINE" ] && continue
   IFS='|' read -r U P E L <<< "$LINE" ; BASE=$(echo "$E" | cut -d' ' -f1)
   NEW=$(date -d "$BASE +$DY days +1 day" +"%Y-%m-%d 00:00")
   sed -i "${NUM}c\\$U|$P|$NEW|$L" "$DB" ; systemctl restart zivpn ; echo "Renewed!" ; sleep 1 ;;
5) systemctl restart zivpn ; echo "Restarted!" ; sleep 1 ;;
6) # delete expired
   NOW=$(date +"%Y-%m-%d %H:%M") ; TMP="/tmp/z-clean.db" ; > "$TMP"
   while IFS='|' read -r U P E L; do
     if [[ "$E" < "$NOW" ]]; then jq --arg pass "$P" '.auth.config -= [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
     else echo "$U|$P|$E|$L" >> "$TMP" ; fi
   done < "$DB" ; mv "$TMP" "$DB" ; systemctl restart zivpn ; echo "Cleaned!" ; sleep 1 ;;
7) ip_monitor ;;
8) # change domain
   read -rp " New Domain : " ND ; [ -z "$ND" ] && continue ; echo "$ND" > "$DOMAIN_FILE"
   openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj "/CN=$ND" -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt 2>/dev/null
   systemctl restart zivpn ; DOMAIN="$ND" ; echo "Updated!" ; sleep 1 ;;
9) # update menu
   exec /usr/bin/zivpn-menu ;;
10) # trial
    MIN=30 ; U="trial$(tr -dc 0-9 </dev/urandom | head -c 4)" ; P=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    EXP=$(date -d "+$MIN minutes" +"%Y-%m-%d %H:%M") ; L=1
    jq --arg pass "$P" '.auth.config += [$pass]' "$CONFIG" > /tmp/z.json && mv /tmp/z.json "$CONFIG"
    echo "$U|$P|$EXP|$L" >> "$DB" ; systemctl restart zivpn ; echo "Trial Created!" ; sleep 1 ;;
11) # telegram bot setup
    read -rp " Token : " BT ; read -rp " ID : " CI
    echo -e "BOT_TOKEN=\"$BT\"\nCHAT_ID=\"$CI\"" > "$TG_FILE" ; chmod 600 "$TG_FILE" ; source "$TG_FILE" ; echo "Saved!" ; sleep 1 ;;
12) # backup sent to telegram
    DATE=$(date +%Y%m%d-%H%M) ; FILE="/root/backup-$DATE.zip" ; zip -r "$FILE" /etc/zivpn/ >/dev/null 2>&1
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" -F chat_id="$CHAT_ID" -F document=@"$FILE" >/dev/null ; rm -f "$FILE" ; echo "Sent!" ; sleep 1 ;;
13) manage_autokill ;;
0) exit ;;
esac
done
