#!/bin/sh

echo "Starting Unified LED Script Installation..."

# 1. Write the background monitoring script to /usr/bin/internet_led.sh
echo "Writing monitoring script to /usr/bin/internet_led.sh..."
cat << 'EOF' > /usr/bin/internet_led.sh
#!/bin/sh

RED_LED="/sys/class/leds/red:status"
GREEN_LED="/sys/class/leds/green:status"
BLUE_LED="/sys/class/leds/blue:status"

PING_TARGET="1.1.1.1"
CHECK_INTERVAL=5

NIGHT_START=23
NIGHT_END=6

set_led_raw() {
    [ -d "$RED_LED" ] && echo "$1" > "$RED_LED/brightness"
    [ -d "$GREEN_LED" ] && echo "$2" > "$GREEN_LED/brightness"
    [ -d "$BLUE_LED" ] && echo "$3" > "$BLUE_LED/brightness"
}

set_color() {
    case "$1" in
        "off")   set_led_raw 0 0 0 ;;
        "red")   set_led_raw 1 0 0 ;;
        "green") set_led_raw 0 1 0 ;;
        "blue")  set_led_raw 0 0 1 ;;
        "violet") set_led_raw 1 0 1 ;;
    esac
}

blink_violet() {
    for i in 1 2 3 4 5; do
        set_color "violet"
        sleep 0.2
        set_color "off"
        sleep 0.2
    done
}

# Ensure sysfs trigger is unmapped once at startup
[ -d "$RED_LED" ] && echo "none" > "$RED_LED/trigger" 2>/dev/null
[ -d "$GREEN_LED" ] && echo "none" > "$GREEN_LED/trigger" 2>/dev/null
[ -d "$BLUE_LED" ] && echo "none" > "$BLUE_LED/trigger" 2>/dev/null

while true; do
    # 1. Handle USB Storage Blink Trigger
    if [ -f "/tmp/usb_storage_blink" ]; then
        rm -f /tmp/usb_storage_blink
        blink_violet
    fi

    # 2. Check Night Mode
    CURRENT_HOUR=$(date +%H | sed 's/^0//')
    [ -z "$CURRENT_HOUR" ] && CURRENT_HOUR=0

    IS_NIGHT=0
    if [ "$NIGHT_START" -gt "$NIGHT_END" ]; then
        [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] || [ "$CURRENT_HOUR" -lt "$NIGHT_END" ] && IS_NIGHT=1
    else
        [ "$CURRENT_HOUR" -ge "$NIGHT_START" ] && [ "$CURRENT_HOUR" -lt "$NIGHT_END" ] && IS_NIGHT=1
    fi

    if [ "$IS_NIGHT" -eq 1 ]; then
        set_color "off"
    else
        WAN_DEV=$(uci -q get network.wan.device || uci -q get network.wan.ifname)
        WAN_ONLINE=0
        USB_ONLINE=0

        # Check physical carrier on WAN first (zero CPU cost)
        if [ -n "$WAN_DEV" ] && [ "$(cat /sys/class/net/$WAN_DEV/carrier 2>/dev/null)" = "1" ]; then
            # Verify actual internet routing via WAN
            if ping -c 1 -W 2 -I "$WAN_DEV" "$PING_TARGET" >/dev/null 2>&1; then
                WAN_ONLINE=1
            fi
        fi

        if [ "$WAN_ONLINE" -eq 1 ]; then
            # Primary WAN working -> Route via WAN (Green)
            set_color "green"
        else
            # WAN down or no internet -> Fallback to USB Tethering
            if [ -d "/sys/class/net/usb0" ] && [ "$(cat /sys/class/net/usb0/carrier 2>/dev/null)" = "1" ]; then
                if ping -c 1 -W 2 -I "usb0" "$PING_TARGET" >/dev/null 2>&1; then
                    USB_ONLINE=1
                fi
            fi

            if [ "$USB_ONLINE" -eq 1 ]; then
                set_color "blue"   # Failover active via USB
            else
                set_color "red"    # Neither WAN nor USB internet available
            fi
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
EOF

chmod +x /usr/bin/internet_led.sh

# 2. Write the Procd Init Script to /etc/init.d/internet_led
echo "Writing procd init service to /etc/init.d/internet_led..."
cat << 'EOF' > /etc/init.d/internet_led
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/internet_led.sh
    procd_set_param respawn
    procd_close_instance
}
EOF

# 3. Set Permissions and Enable Service
chmod +x /etc/init.d/internet_led
 /etc/init.d/internet_led enable
 /etc/init.d/internet_led start

echo "Installation complete! The LED monitor is now running as a managed system service."