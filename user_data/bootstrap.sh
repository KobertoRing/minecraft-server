#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

BUCKET="${bucket_name}"
MINECRAFT_VERSION="${minecraft_version}"
FABRIC_LOADER_VERSION="${fabric_loader}"
FABRIC_INSTALLER_VERSION="${fabric_installer}"

# Paths
MC_ROOT="/opt/minecraft"
MC_SERVER_DIR="${MC_ROOT}/server"
MC_MODS_DIR="${MC_ROOT}/mods"
MC_CONFIG_DIR="${MC_ROOT}/config"
MC_WORLD_DIR="${MC_ROOT}/world"
MC_LOGS_DIR="${MC_ROOT}/logs"
MC_SCRIPTS_DIR="${MC_ROOT}/scripts"
MC_USER="minecraft"

# Install packages
apt-get update
apt-get install -y \
  openjdk-21-jre-headless \
  awscli \
  curl \
  jq

# Create service user if missing
if ! id -u "${MC_USER}" >/dev/null 2>&1; then
  useradd --system --home "${MC_ROOT}" --shell /usr/sbin/nologin "${MC_USER}"
fi

# Create directories
mkdir -p \
  "${MC_SERVER_DIR}" \
  "${MC_MODS_DIR}" \
  "${MC_CONFIG_DIR}" \
  "${MC_WORLD_DIR}" \
  "${MC_LOGS_DIR}" \
  "${MC_SCRIPTS_DIR}"

chown -R "${MC_USER}:${MC_USER}" "${MC_ROOT}"

# Pull persisted assets from S3 if they exist
aws s3 sync "s3://${BUCKET}/mods/"   "${MC_MODS_DIR}/"   || true
aws s3 sync "s3://${BUCKET}/config/" "${MC_CONFIG_DIR}/" || true
aws s3 sync "s3://${BUCKET}/world/"  "${MC_WORLD_DIR}/"  || true

# Download Fabric installer
cd /tmp
curl -fLo fabric-installer.jar "https://meta.fabricmc.net/v2/versions/installer/${FABRIC_INSTALLER_VERSION}/server/jar"

# Install Fabric server into the server directory
mkdir -p "${MC_SERVER_DIR}"
cd "${MC_SERVER_DIR}"

java -jar /tmp/fabric-installer.jar server \
  -mcversion "${MINECRAFT_VERSION}" \
  -loader "${FABRIC_LOADER_VERSION}" \
  -downloadMinecraft

# Accept EULA if not already present
if [ ! -f "${MC_SERVER_DIR}/eula.txt" ]; then
  echo "eula=true" > "${MC_SERVER_DIR}/eula.txt"
fi

# Link shared directories into the server directory
rm -rf "${MC_SERVER_DIR}/mods" "${MC_SERVER_DIR}/config" "${MC_SERVER_DIR}/world" || true
ln -s "${MC_MODS_DIR}"   "${MC_SERVER_DIR}/mods"
ln -s "${MC_CONFIG_DIR}" "${MC_SERVER_DIR}/config"
ln -s "${MC_WORLD_DIR}"  "${MC_SERVER_DIR}/world"

# Start script
cat > "${MC_SCRIPTS_DIR}/start.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
cd /opt/minecraft/server

# Fabric normally generates either fabric-server-launch.jar or server.jar style launch files
if [ -f fabric-server-launch.jar ]; then
  exec java -Xms2G -Xmx4G -jar fabric-server-launch.jar nogui
fi

if [ -f server.jar ]; then
  exec java -Xms2G -Xmx4G -jar server.jar nogui
fi

echo "No Fabric server launch jar found"
exit 1
EOF

# Backup script
cat > "${MC_SCRIPTS_DIR}/backup.sh" <<EOF
#!/bin/bash
set -euo pipefail
aws s3 sync "${MC_WORLD_DIR}/"  "s3://${BUCKET}/world/"  --delete
aws s3 sync "${MC_MODS_DIR}/"   "s3://${BUCKET}/mods/"   --delete
aws s3 sync "${MC_CONFIG_DIR}/" "s3://${BUCKET}/config/" --delete
EOF

chmod +x "${MC_SCRIPTS_DIR}/start.sh" "${MC_SCRIPTS_DIR}/backup.sh"
chown -R "${MC_USER}:${MC_USER}" "${MC_ROOT}"

# systemd unit
cat > /etc/systemd/system/minecraft.service <<'EOF'
[Unit]
Description=Minecraft Fabric Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStart=/opt/minecraft/scripts/start.sh
ExecStop=/opt/minecraft/scripts/backup.sh
TimeoutStopSec=300
Restart=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minecraft.service
systemctl start minecraft.service