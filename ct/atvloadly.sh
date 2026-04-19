#!/usr/bin/env bash
# shellcheck source=/dev/null
source <(curl -fsSL https://raw.githubusercontent.com/YKikAMooCow/ProxmoxVED/add/atvloadly/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: spathix
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bitxeno/atvloadly

APP="Atvloadly"
var_tags="${var_tags:-appletv;sideload}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/bin/atvloadly ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/bitxeno/atvloadly/releases/latest \
            | grep '"tag_name"' | awk -F\" '{print $4}')

  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop atvloadly
    msg_ok "Stopped ${APP}"

    msg_info "Updating ${APP} to ${RELEASE}"
    ARCH=$(dpkg --print-architecture)
    cd /tmp || exit
    curl -fsSL -o atvloadly.tar.gz \
      "https://github.com/bitxeno/atvloadly/releases/download/${RELEASE}/atvloadly-linux-${ARCH}.tar.gz"
    tar -xzf atvloadly.tar.gz -C /usr/bin/
    chmod +x /usr/bin/atvloadly
    rm -f atvloadly.tar.gz
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated ${APP} to ${RELEASE}"

    msg_info "Starting ${APP}"
    systemctl start atvloadly
    msg_ok "Started ${APP}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5533${CL}"
