# Jio AX6000 ARGB Status LED Control
A lightweight, automated system service for JIDU AX6000 6J01 and 6J11 device family Jio Airfiber AX6000 Wifi Routers running OpenWRT that provides real-time LED status indication based on active internet connectivity, automatic Ethernet-to-USB-tethering failover, and a scheduled night-mode blackout.

# Features

Smart Failover Monitoring:

🟢 Green: Primary Ethernet WAN is connected and routing traffic.

🔵 Blue: Primary WAN is down; failover active via USB Tethering.

🔴 Red: Neither Ethernet WAN nor USB tethering has internet access.

Night Mode: Automatically turns off all status LEDs during specified night hours (Default: 23:00 to 06:00).

USB Activity Trigger: Provides a visual notification (blinking violet) when /tmp/usb_storage_blink is created.

# Installation

Openwrt 25.12+ expected.Run the following command in your OpenWrt SSH terminal to download, configure, and start the service automatically:

*Login to router using SSH and run the following commands*

    apk update 
    
    apk add curl bash

    apk upgrade
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/RandomDelta6/Jio-Router-LED-Configuration/refs/heads/main/installerscript.sh)"