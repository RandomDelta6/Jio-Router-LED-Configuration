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

chmod +x /etc/init.d/internet_led
/etc/init.d/internet_led enable
/etc/init.d/internet_led start