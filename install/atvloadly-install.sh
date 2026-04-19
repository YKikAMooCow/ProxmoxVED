#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: spathix
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bitxeno/atvloadly

# shellcheck source=/dev/null
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  unzip \
  avahi-daemon \
  libavahi-compat-libdnssd-dev \
  libavahi-compat-libdnssd1 \
  tzdata
$STD systemctl enable --now avahi-daemon
msg_ok "Installed Dependencies"

# Architecture mapping:
#   usbmuxd2 / PlumeImpactor tarballs use x86_64 / aarch64
#   Apple Music APK uses x86_64 / arm64-v8a
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) PKG_ARCH=x86_64;  APK_ARCH=x86_64 ;;
  arm64) PKG_ARCH=aarch64; APK_ARCH=arm64-v8a ;;
  *) msg_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

msg_info "Installing usbmuxd2"
mkdir -p /tmp/usbmuxd2
cd /tmp || exit
$STD curl -fsSLO "https://github.com/bitxeno/usbmuxd2/releases/download/v0.0.6/usbmuxd2-ubuntu-${PKG_ARCH}.tar.gz"
tar -zxf "usbmuxd2-ubuntu-${PKG_ARCH}.tar.gz" -C /tmp/usbmuxd2
# Install in dependency order; glob patterns handle any internal version bumps
$STD dpkg -i /tmp/usbmuxd2/libusb_*.deb
$STD dpkg -i /tmp/usbmuxd2/libgeneral_*.deb
$STD dpkg -i /tmp/usbmuxd2/libplist_*.deb
$STD dpkg -i /tmp/usbmuxd2/libtatsu_*.deb
$STD dpkg -i /tmp/usbmuxd2/libimobiledevice-glue_*.deb
$STD dpkg -i /tmp/usbmuxd2/libusbmuxd_*.deb
$STD dpkg -i /tmp/usbmuxd2/libimobiledevice_*.deb
$STD dpkg -i /tmp/usbmuxd2/usbmuxd2_*.deb
rm -rf /tmp/usbmuxd2 /tmp/usbmuxd2-ubuntu-*.tar.gz
msg_ok "Installed usbmuxd2"

msg_info "Installing PlumeImpactor"
cd /tmp || exit
$STD curl -fsSLO "https://github.com/bitxeno/PlumeImpactor/releases/download/v2.2.3-patch.1/plumesign-linux-${PKG_ARCH}.tar.gz"
tar -zxf "plumesign-linux-${PKG_ARCH}.tar.gz"
install -m 0755 "plumesign-linux-${PKG_ARCH}" /usr/bin/plumesign
rm -f /tmp/plumesign-linux-*.tar.gz "plumesign-linux-${PKG_ARCH}"
msg_ok "Installed PlumeImpactor"

msg_info "Fetching Anisette Libraries"
mkdir -p /data/PlumeImpactor/lib
cd /tmp || exit
$STD curl -fsSLO https://apps.mzstatic.com/content/android-apple-music-apk/applemusic.apk
unzip -jo applemusic.apk \
  "lib/${APK_ARCH}/libstoreservicescore.so" \
  "lib/${APK_ARCH}/libCoreADI.so" \
  -d /data/PlumeImpactor/lib/
rm -f /tmp/applemusic.apk
mkdir -p /root/.config
ln -sf /data/PlumeImpactor /root/.config/PlumeImpactor
msg_ok "Fetched Anisette Libraries"

msg_info "Installing Atvloadly"
RELEASE=$(curl -fsSL https://api.github.com/repos/bitxeno/atvloadly/releases/latest \
          | grep '"tag_name"' | awk -F\" '{print $4}')
cd /tmp || exit
$STD curl -fsSL -o atvloadly.tar.gz \
  "https://github.com/bitxeno/atvloadly/releases/download/${RELEASE}/atvloadly-linux-${ARCH}.tar.gz"
tar -xzf atvloadly.tar.gz
install -m 0755 "atvloadly-linux-${ARCH}" /usr/bin/atvloadly
rm -f "atvloadly-linux-${ARCH}" atvloadly.tar.gz

# Persistent data layout — mirrors the upstream Docker entrypoint
mkdir -p /data/lockdown
rm -rf /var/lib/lockdown
ln -s /data/lockdown /var/lib/lockdown

$STD curl -fsSL -o /data/config.yaml \
  https://raw.githubusercontent.com/bitxeno/atvloadly/master/doc/config.yaml.example

echo "${RELEASE}" >/opt/Atvloadly_version.txt
msg_ok "Installed Atvloadly ${RELEASE}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/atvloadly.service
[Unit]
Description=Atvloadly sideload server
After=network-online.target avahi-daemon.service
Wants=network-online.target avahi-daemon.service

[Service]
Environment=HOME=/root
ExecStart=/usr/bin/atvloadly server -p 5533 -c /data/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now atvloadly
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
