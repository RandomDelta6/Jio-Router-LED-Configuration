#!/bin/sh

echo "Starting LED Status Monitor Installation..."

# Change directory to /root
cd /root || { echo "Failed to change directory to /root. Exiting."; exit 1; }
echo "Working directory changed to $(pwd)"
echo ""

# Color Prompt Helper Function
prompt_color() {
    local p_text="$1"
    local d_val="$2"
    local d_name="$3"
    printf "%s\n[1=Blue 2=Green 3=Red 4=Yellow 5=Cyan 6=Magenta 7=White] (Default: %s): " "$p_text" "$d_name" >&2
    read -r c < /dev/tty
    [ -z "$c" ] && c=$d_val
    case "$c" in
        1) echo "blue" ;; 2) echo "green" ;; 3) echo "red" ;; 4) echo "yellow" ;;
        5) echo "cyan" ;; 6) echo "magenta" ;; 7) echo "white" ;; *) echo "blue" ;;
    esac
}

# --- Master Installation Menu ---
echo "=========================================="
echo " Connection & Monitoring Mode"
echo "=========================================="
echo "1) Ethernet WAN Primary + USB Tethering Failover"
echo "   -> Prefers Ethernet WAN; switches to USB Tethering (usb0) only if WAN loses internet."
echo ""
echo "2) Universal Mode (Auto-Pilot)"
echo "   -> Best for Single WAN, Access Points, Repeaters, & USB Tethering."
echo ""
echo "3) Strict Dual-WAN Mode"
echo "   -> Assign specific LED colors to specific WAN interfaces."
echo ""
echo "4) Cancel / Abort"
printf "Choose an option [1/2/3/4] (Default: 1): "
read -r mode_choice < /dev/tty
[ -z "$mode_choice" ] && mode_choice="1"

if [ "$mode_choice" = "4" ]; then
    echo "Installation cancelled. Exiting."
    exit 0
fi

# Initialize default vars
MONITOR_MODE="wan_usb_failover"
WAN1_NAME=""; WAN2_NAME=""
WAN1_COLOR="green"; WAN2_COLOR="blue"; ALL_UP_COLOR="cyan"
NET_COLOR="blue"
ENABLE_WARN=1
WARN_COLOR="red"

# Night Mode Variables
ENABLE_NIGHT_MODE=1
NIGHT_START=23
NIGHT_END=6

echo ""
echo "=========================================="
echo " LED Color & Priority Configuration"
echo "=========================================="
if [ "$mode_choice" = "1" ]; then
    MONITOR_MODE="wan_usb_failover"
    echo "Configuring WAN Primary (Green) + USB Tethering Failover (Blue)..."
    WAN1_COLOR=$(prompt_color "Color when Ethernet WAN is active" "2" "2=Green")
    WAN2_COLOR=$(prompt_color "Color when USB Tethering (Failover) is active" "1" "1=Blue")
elif [ "$mode_choice" = "3" ]; then
    MONITOR_MODE="strict_dual"
    
    echo "Detecting WAN interfaces (ignoring VPNs)..."
    DETECTED_WANS=""
    for zone in $(uci show firewall 2>/dev/null | grep "\.masq='1'" | cut -d. -f2); do
        for net in $(uci -q get firewall.$zone.network); do
            case "$net" in *6|loopback) continue ;; esac
            if echo "$net" | grep -qiE '(vpn|wg|tun|tap|tailscale|zerotier|zt)'; then continue; fi
            if echo "$(uci -q get network.$net.proto)" | grep -qiE '(wireguard|openvpn|tun|tap)'; then continue; fi
            DETECTED_WANS="$DETECTED_WANS $net"
        done
    done
    DETECTED_WANS=$(echo "$DETECTED_WANS" | tr ' ' '\n' | sort -u | xargs)
    [ -z "$DETECTED_WANS" ] && DETECTED_WANS="wan wanb"
    
    echo "Detected WANs: [ $DETECTED_WANS ]"
    printf "Type the two WAN interfaces to monitor (e.g. 'wan wanb'): "
    read -r user_wans < /dev/tty
    [ -z "$user_wans" ] && user_wans="$DETECTED_WANS"
    
    WAN1_NAME=$(echo "$user_wans" | awk '{print $1}')
    WAN2_NAME=$(echo "$user_wans" | awk '{print $2}')
    
    WAN1_COLOR=$(prompt_color "Color to FLASH when ONLY [$WAN1_NAME] is active" "1" "1=Blue")
    WAN2_COLOR=$(prompt_color "Color to FLASH when ONLY [$WAN2_NAME] is active" "2" "2=Green")
    ALL_UP_COLOR=$(prompt_color "Color for SOLID ON when BOTH are active" "5" "5=Cyan")
else
    MONITOR_MODE="universal"
    NET_COLOR=$(prompt_color "Which LED color should indicate the Internet is WORKING?" "1" "1=Blue")
fi
echo "=========================================="
echo ""

# --- Night Mode Schedule Prompt ---
echo "=========================================="
echo " Night Mode Configuration (LEDs Off)"
echo "=========================================="
printf "Enable Night Mode to turn off LEDs at night? [y/n] (Default: y): "
read -r night_choice < /dev/tty
if [ "$night_choice" = "n" ] || [ "$night_choice" = "N" ]; then
    ENABLE_NIGHT_MODE=0
    echo "-> Night Mode DISABLED."
else
    ENABLE_NIGHT_MODE=1
    printf "Enter start hour for Night Mode [0-23] (Default: 23 for 11 PM): "
    read -r user_start < /dev/tty
    [ -n "$user_start" ] && NIGHT_START="$user_start"

    printf "Enter end hour for Night Mode [0-23] (Default: 6 for 6 AM): "
    read -r user_end < /dev/tty
    [ -n "$user_end" ] && NIGHT_END="$user_end"

    echo "-> Night Mode ENABLED ($NIGHT_START:00 to $NIGHT_END:00)."
fi
echo "=========================================="
echo ""

# --- 100M Warning Prompt ---
echo "=========================================="
echo " 100M Port Warning Feature"
echo "=========================================="
printf "Enable 100M port warning? [y/n] (Default: y): "
read -r warn_choice < /dev/tty
if [ "$warn_choice" = "n" ] || [ "$warn_choice" = "N" ]; then
    ENABLE_WARN=0
    echo "-> 100M Port Warnings DISABLED."
else
    ENABLE_WARN=1
    WARN_COLOR=$(prompt_color "Color to FLASH for 100M Speed Warning" "3" "3=Red")
fi
echo "=========================================="
echo ""

# --- Script Location Prompt ---
SCRIPT_PATH="/root/led_status.sh"

# Ensure the target directory exists
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
mkdir -p "$SCRIPT_DIR"

# 2. Clean up default Router Startup LED behaviors
echo "Cleaning up default startup LED behaviors to prevent conflicts..."

if [ -f "/etc/init.d/wan-led" ]; then
    /etc/init.d/wan-led disable >/dev/null 2>&1
    /etc/init.d/wan-led stop >/dev/null 2>&1
    chmod -x /etc/init.d/wan-led
    
    for color in red green blue; do
        if [ -d "/sys/class/leds/${color}:status" ]; then
            echo none > "/sys/class/leds/${color}:status/trigger" 2>/dev/null
            echo 0 > "/sys/class/leds/${color}:status/brightness" 2>/dev/null
        fi
    done
fi

while uci -q show system | grep -E "\.sysfs='?(blue:status|red:status|green:status)'?" >/dev/null; do
    cfg=$(uci -q show system | grep -E "\.sysfs='?(blue:status|red:status|green:status)'?" | head -n 1 | cut -d. -f2)
    uci delete "system.$cfg"
done
uci commit system
/etc/init.d/led reload >/dev/null 2>&1

# Apply UCI Network Metrics for Failover Priority if Option 1 Selected
if [ "$MONITOR_MODE" = "wan_usb_failover" ]; then
    echo "Updating OpenWrt UCI network metrics (WAN=10, Tethering=20)..."
    uci set network.wan.metric='10' 2>/dev/null
    uci set network.tethering=interface 2>/dev/null
    uci set network.tethering.proto='dhcp' 2>/dev/null
    uci set network.tethering.device='usb0' 2>/dev/null
    uci set network.tethering.metric='20' 2>/dev/null
    uci commit network
    /etc/init.d/network reload >/dev/null 2>&1
fi

# 3. Install Dependencies
if command -v opkg > /dev/null 2>&1; then
    opkg update >/dev/null 2>&1
    opkg install coreutils-timeout >/dev/null 2>&1
elif command -v apk > /dev/null 2>&1; then
    apk update >/dev/null 2>&1
    apk add coreutils >/dev/null 2>&1
fi

# 4. Write the script payload
echo "Writing payload to $SCRIPT_PATH..."

cat << EOF > "$SCRIPT_PATH"
#!/bin/sh
# --- User Configured Variables ---
MONITOR_MODE="${MONITOR_MODE}"
WAN1_NAME="${WAN1_NAME}"
WAN2_NAME="${WAN2_NAME}"
WAN1_COLOR="${WAN1_COLOR}"
WAN2_COLOR="${WAN2_COLOR}"
ALL_UP_COLOR="${ALL_UP_COLOR}"
NET_COLOR="${NET_COLOR}"
ENABLE_WARN=${ENABLE_WARN}
WARN_COLOR="${WARN_COLOR}"
ENABLE_NIGHT_MODE=${ENABLE_NIGHT_MODE}
NIGHT_START=${NIGHT_START}
NIGHT_END=${NIGHT_END}
EOF

cat << 'EOF' >> "$SCRIPT_PATH"
# --- Core Logic ---
PORT_WARNING=0

# Hardware RGB mixing function
set_led() {
    local color="$1"
    local state="$2" # solid, flash, off
    
    if [ "$state" = "off" ] || [ "$color" = "off" ]; then
        for c in red green blue; do
            echo none > "/sys/class/leds/$c:status/trigger" 2>/dev/null
            echo 0 > "/sys/class/leds/$c:status/brightness" 2>/dev/null
        done
        return
    fi
    
    local r=0; local g=0; local b=0
    case "$color" in
        red) r=1 ;; green) g=1 ;; blue) b=1 ;;
        yellow|amber) r=1; g=1 ;; cyan) g=1; b=1 ;;
        magenta|purple) r=1; b=1 ;; white) r=1; g=1; b=1 ;;
    esac
    
    for c in red green blue; do
        local c_val=0
        [ "$c" = "red" ] && c_val=$r
        [ "$c" = "green" ] && c_val=$g
        [ "$c" = "blue" ] && c_val=$b
        
        if [ "$c_val" -eq 1 ]; then
            if [ "$state" = "flash" ]; then
                echo timer > "/sys/class/leds/$c:status/trigger" 2>/dev/null
            elif [ "$state" = "solid" ]; then
                echo none > "/sys/class/leds/$c:status/trigger" 2>/dev/null
                echo 255 > "/sys/class/leds/$c:status/brightness" 2>/dev/null
            fi
        else
            echo none > "/sys/class/leds/$c:status/trigger" 2>/dev/null
            echo 0 > "/sys/class/leds/$c:status/brightness" 2>/dev/null
        fi
    done
}

# --- Night Mode Evaluation ---
if [ "$ENABLE_NIGHT_MODE" -eq 1 ]; then
    CURRENT_HOUR=$(date +%H | sed 's/^0//')
    [ -z "$CURRENT_HOUR" ] && CURRENT_HOUR=0

    IS_NIGHT=0
    if [ "$NIGHT_START" -gt "$NIGHT_END" ]; then
        if [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] || [ "$CURRENT_HOUR" -lt "$NIGHT_END" ]; then
            IS_NIGHT=1
        fi
    else
        if [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] && [ "$CURRENT_HOUR" -lt "$NIGHT_END" ]; then
            IS_NIGHT=1
        fi
    fi

    if [ "$IS_NIGHT" -eq 1 ]; then
        STATE_FILE="/tmp/router_led_state"
        if [ "$(cat "$STATE_FILE" 2>/dev/null)" != "off_off" ]; then
            set_led "off" "off"
            echo "off_off" > "$STATE_FILE"
        fi
        exit 0
    fi
fi

# --- Cache mwan3 status to save CPU time ---
MWAN_STATUS=""
if command -v mwan3 >/dev/null 2>&1; then
    MWAN_STATUS=$(mwan3 status 2>/dev/null)
fi

# --- UNIVERSAL CHECK (AP, Repeater, USB, Single WAN) ---
global_internet_check() {
    if ping -c 1 -W 2 "1.1.1.1" >/dev/null 2>&1; then return 0; fi
    if ping -c 1 -W 2 "8.8.8.8" >/dev/null 2>&1; then return 0; fi
    return 1
}

# --- STRICT DUAL-WAN / INTERFACE CHECK ---
check_wan() {
    local logical_if="$1"
    
    # 1. Ask MultiWAN Manager (mwan3) memory cache
    if [ -n "$MWAN_STATUS" ]; then
        if echo "$MWAN_STATUS" | grep -q "interface $logical_if is online"; then
            return 0
        fi
        if echo "$MWAN_STATUS" | grep -q "interface $logical_if is"; then
            return 1
        fi
    fi
    
    # 2. Fallback to manual ping
    local phys_dev="$logical_if"
    if [ ! -d "/sys/class/net/$logical_if" ]; then
        phys_dev=$(ubus call network.interface.$logical_if status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
        [ -z "$phys_dev" ] && phys_dev=$(ubus call network.interface.$logical_if status 2>/dev/null | jsonfilter -e '@.device' 2>/dev/null)
        if [ -z "$phys_dev" ]; then
            proto=$(uci -q get network.$logical_if.proto)
            if [ "$proto" = "pppoe" ]; then
                phys_dev="pppoe-$logical_if"
            else
                phys_dev=$(uci -q get network.$logical_if.device)
                [ -z "$phys_dev" ] && phys_dev=$(uci -q get network.$logical_if.ifname)
            fi
        fi
    fi
    
    if [ -n "$phys_dev" ] && [ -d "/sys/class/net/$phys_dev" ]; then
        if ping -c 1 -W 2 -I "$phys_dev" "1.1.1.1" >/dev/null 2>&1; then return 0; fi
        if ping -c 1 -W 2 -I "$phys_dev" "8.8.8.8" >/dev/null 2>&1; then return 0; fi
    fi
    return 1
}

if [ "$ENABLE_WARN" -eq 1 ]; then
    PORTS="wan lan1 lan2 lan3 lan4"
    for port in $PORTS; do
        if [ -d "/sys/class/net/$port" ]; then
            SPEED=$(cat "/sys/class/net/$port/speed" 2>/dev/null)
            OPERSTATE=$(cat "/sys/class/net/$port/operstate" 2>/dev/null)
            if [ "$OPERSTATE" = "up" ] && [ "$SPEED" = "100" ]; then
                PORT_WARNING=1
                break
            fi
        fi
    done
fi

TARGET_COLOR="red"
TARGET_MODE="flash"

if [ "$PORT_WARNING" -eq 1 ]; then
    TARGET_COLOR="$WARN_COLOR"
    TARGET_MODE="flash"
else
    if [ "$MONITOR_MODE" = "wan_usb_failover" ]; then
        # --- WAN Primary with USB Tethering Failover ---
        WAN_ONLINE=0
        USB_ONLINE=0
        
        WAN_DEV=$(uci -q get network.wan.device || uci -q get network.wan.ifname)
        [ -z "$WAN_DEV" ] && WAN_DEV="wan"

        if [ -d "/sys/class/net/$WAN_DEV" ] && [ "$(cat /sys/class/net/$WAN_DEV/carrier 2>/dev/null)" = "1" ]; then
            if ping -c 1 -W 2 -I "$WAN_DEV" "1.1.1.1" >/dev/null 2>&1; then
                WAN_ONLINE=1
            fi
        fi

        if [ "$WAN_ONLINE" -eq 1 ]; then
            TARGET_COLOR="$WAN1_COLOR" # WAN Online (Default: Green)
            TARGET_MODE="solid"
        else
            if [ -d "/sys/class/net/usb0" ] && [ "$(cat /sys/class/net/usb0/carrier 2>/dev/null)" = "1" ]; then
                if ping -c 1 -W 2 -I "usb0" "1.1.1.1" >/dev/null 2>&1; then
                    USB_ONLINE=1
                fi
            fi

            if [ "$USB_ONLINE" -eq 1 ]; then
                TARGET_COLOR="$WAN2_COLOR" # USB Failover Active (Default: Blue)
                TARGET_MODE="solid"
            else
                TARGET_COLOR="red"         # No Internet on WAN or USB
                TARGET_MODE="flash"
            fi
        fi

    elif [ "$MONITOR_MODE" = "strict_dual" ]; then
        # --- Strict Dual WAN Logic ---
        WAN1_UP=0; WAN2_UP=0
        check_wan "$WAN1_NAME" && WAN1_UP=1
        check_wan "$WAN2_NAME" && WAN2_UP=1
        
        if [ "$WAN1_UP" -eq 1 ] && [ "$WAN2_UP" -eq 1 ]; then
            TARGET_COLOR="$ALL_UP_COLOR"; TARGET_MODE="solid"
        elif [ "$WAN1_UP" -eq 1 ]; then
            TARGET_COLOR="$WAN1_COLOR"; TARGET_MODE="flash"
        elif [ "$WAN2_UP" -eq 1 ]; then
            TARGET_COLOR="$WAN2_COLOR"; TARGET_MODE="flash"
        else
            TARGET_COLOR="red"; TARGET_MODE="flash"
        fi
    else
        # --- Universal Logic ---
        if [ -n "$MWAN_STATUS" ] && [ "$(echo "$MWAN_STATUS" | grep -c 'interface.*is')" -gt 1 ]; then
            EXPECTED_WANS=$(echo "$MWAN_STATUS" | grep -c "interface.*is")
            ACTIVE_WANS=$(echo "$MWAN_STATUS" | grep -c "interface.*is online")
            if [ "$ACTIVE_WANS" -eq "$EXPECTED_WANS" ]; then
                TARGET_COLOR="$NET_COLOR"; TARGET_MODE="solid"
            elif [ "$ACTIVE_WANS" -gt 0 ]; then
                TARGET_COLOR="$NET_COLOR"; TARGET_MODE="flash"
            else
                TARGET_COLOR="red"; TARGET_MODE="flash"
            fi
        else
            if global_internet_check; then
                TARGET_COLOR="$NET_COLOR"; TARGET_MODE="solid"
            else
                TARGET_COLOR="red"; TARGET_MODE="flash"
            fi
        fi
    fi
fi

# --- STATE MEMORY: Update hardware only on state changes ---
STATE_FILE="/tmp/router_led_state"
NEW_STATE="${TARGET_COLOR}_${TARGET_MODE}"
OLD_STATE=$(cat "$STATE_FILE" 2>/dev/null)

if [ "$NEW_STATE" != "$OLD_STATE" ]; then
    for c in blue green red; do
        echo none > "/sys/class/leds/$c:status/trigger" 2>/dev/null
        echo 0 > "/sys/class/leds/$c:status/brightness" 2>/dev/null
    done
    
    set_led "$TARGET_COLOR" "$TARGET_MODE"
    echo "$NEW_STATE" > "$STATE_FILE"
fi
EOF

# 5. Set Permissions
chmod +x "$SCRIPT_PATH"
echo "Set $SCRIPT_PATH as executable."

# 6. Apply Crontab Entries
echo "Configuring cron schedules (2x per minute)..."
TMP_CRON="/tmp/led_cron_tmp"

crontab -l 2>/dev/null | \
  sed '/# --- BEGIN LED MONITOR ---/,/# --- END LED MONITOR ---/d' | \
  grep -v "$SCRIPT_PATH" > "$TMP_CRON"

echo "# --- BEGIN LED MONITOR ---" >> "$TMP_CRON"
echo "* * * * * timeout 25 /bin/sh $SCRIPT_PATH >/dev/null 2>&1" >> "$TMP_CRON"
echo "* * * * * sleep 30 && timeout 25 /bin/sh $SCRIPT_PATH >/dev/null 2>&1" >> "$TMP_CRON"
echo "# --- END LED MONITOR ---" >> "$TMP_CRON"

crontab "$TMP_CRON"
rm "$TMP_CRON"

if [ -x "/etc/init.d/cron" ]; then
    /etc/init.d/cron restart >/dev/null 2>&1
fi

/bin/sh "$SCRIPT_PATH" &

echo "Installation complete! The script is now safely monitoring your connection every 30 seconds."