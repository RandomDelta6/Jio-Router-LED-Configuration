# Script for ARGB LED control on Jio AX6000
Supports JIDU AX6000 6J01 and 6J11 device family Jio Airfiber AX6000 Wifi Routers running OpenWRT

Supports only GPIO mode, PWM mode is currently unsupported for status monitoring

Configurable options in terminal during installation

LED Color script based on internet connectivity. Runs every 30s using cronjob

***Login to router using SSH and add these packages***

    apk update && apk add curl bash
***Run this command in SSH***

    curl -L https://raw.githubusercontent.com/RandomDelta6/Jio-Router-LED-Configuration/refs/heads/main/ledconfig.sh | bash
