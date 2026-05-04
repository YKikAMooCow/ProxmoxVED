#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: joshuaventer (joshuaventer)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/usetrmnl/terminus

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git \
  libpq-dev \
  libssl-dev \
  libyaml-dev \
  libreadline-dev \
  zlib1g-dev \
  libffi-dev \
  redis-server \
  chromium \
  fonts-noto-cjk \
  imagemagick \
  libjemalloc2
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
RUBY_VERSION="4.0.3" setup_ruby
PG_VERSION="17" setup_postgresql
PG_DB_NAME="terminus" PG_DB_USER="terminus" setup_postgresql_db

fetch_and_deploy_gh_release "terminus" "usetrmnl/terminus" "tarball"

msg_info "Setting up Git Version Info"
cd /opt/terminus
$STD git init -q
TERMINUS_VERSION=$(cat ~/.terminus)
$STD git add -A
$STD git commit -q -m "v${TERMINUS_VERSION}" --allow-empty
$STD git tag "${TERMINUS_VERSION}"
msg_ok "Set up Git Version Info"

msg_info "Configuring Terminus"
SECRET_KEY=$(openssl rand -hex 40)
cat <<EOF >/opt/terminus/.env
HANAMI_ENV=production
RACK_ENV=production
HANAMI_PORT=2300
HANAMI_SERVE_ASSETS=true
API_URI=http://${LOCAL_IP}:2300
APP_SECRET=${SECRET_KEY}
DATABASE_URL=postgres://terminus:${PG_DB_PASS}@127.0.0.1:5432/terminus
KEYVALUE_URL=redis://localhost:6379/0
EOF
msg_ok "Configured Terminus"

msg_info "Building Application (Patience)"
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
msg_ok "Built Application"

msg_info "Enabling Redis"
systemctl enable -q --now redis-server
msg_ok "Enabled Redis"

msg_info "Creating Services"
JEMALLOC_PATH=$(find /usr/lib -name "libjemalloc.so.2" -print -quit 2>/dev/null)
cat <<EOF >/etc/systemd/system/terminus.service
[Unit]
Description=Terminus Web
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/terminus
EnvironmentFile=/opt/terminus/.env
Environment=LD_PRELOAD=${JEMALLOC_PATH}
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=BUNDLE_GEMFILE=/opt/terminus/Gemfile
Environment=BUNDLE_WITHOUT=development:quality:test:tools
ExecStart=/root/.rbenv/shims/bundle exec puma --config /opt/terminus/config/puma.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/terminus-worker.service
[Unit]
Description=Terminus Sidekiq Worker
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/terminus
EnvironmentFile=/opt/terminus/.env
Environment=LD_PRELOAD=${JEMALLOC_PATH}
Environment=PATH=/root/.rbenv/shims:/root/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=BUNDLE_GEMFILE=/opt/terminus/Gemfile
Environment=BUNDLE_WITHOUT=development:quality:test:tools
ExecStart=/root/.rbenv/shims/bundle exec sidekiq -r ./config/sidekiq.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now terminus terminus-worker
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
