#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: joshuaventer (joshuaventer)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/usetrmnl/terminus

APP="Terminus"
var_tags="${var_tags:-iot;display}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/terminus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "terminus" "usetrmnl/terminus"; then
    msg_info "Stopping Services"
    systemctl stop terminus terminus-worker
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/terminus/.env /opt/terminus.env.bak
    [[ -d /opt/terminus/public/uploads ]] && cp -r /opt/terminus/public/uploads /opt/terminus_uploads.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "terminus" "usetrmnl/terminus"

    msg_info "Restoring Data"
    mv /opt/terminus.env.bak /opt/terminus/.env
    [[ -d /opt/terminus_uploads.bak ]] && mv /opt/terminus_uploads.bak /opt/terminus/public/uploads
    msg_ok "Restored Data"

    msg_info "Building Application"
    cd /opt/terminus
    export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
    eval "$(rbenv init - bash)" 2>/dev/null || true
    set -a
    source /opt/terminus/.env
    set +a
    $STD bundle config set --local deployment 'true'
    $STD bundle config set --local without 'development:quality:test:tools'
    $STD bundle install -j"$(nproc)"
    $STD npm ci
    $STD bundle exec hanami assets compile
    $STD bundle exec hanami db migrate
    TERMINUS_VERSION=$(cat ~/.terminus)
    cd /opt/terminus
    git tag "${TERMINUS_VERSION}" 2>/dev/null
    msg_ok "Built Application"

    msg_info "Starting Services"
    systemctl start terminus terminus-worker
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2300${CL}"
