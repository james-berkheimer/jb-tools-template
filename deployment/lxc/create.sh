#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

set -e

ENV_FILE="$(dirname "$0")/env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing environment file: $ENV_FILE"
  exit 1
fi

source "$ENV_FILE"

if [ -z "$TEMPLATE_DIR" ]; then
  echo "Missing TEMPLATE_DIR variable in env file."
  exit 1
fi

echo "=== Checking if container ID $CT_ID already exists ==="
if pct status $CT_ID &>/dev/null; then
  echo "Error: Container ID $CT_ID already exists. Exiting."
  exit 1
fi

echo "=== Checking LXC Template ==="
pveam update
TEMPLATE_NAME="$TEMPLATE"

if ! pveam list local | grep -q "$TEMPLATE_NAME"; then
  echo "Downloading LXC template $TEMPLATE_NAME..."
  pveam download local "$TEMPLATE_NAME"
fi

echo "=== Creating LXC container ID: $CT_ID ==="
pct create $CT_ID $TEMPLATE \
  --hostname "$CT_HOSTNAME" \
  --cores "$CORES" \
  --memory "$RAM" \
  --rootfs "$CT_STORAGE" \
  --net0 name=eth0,bridge="$BRIDGE0",ip="$CT_IP0",gw="$GATEWAY" \
  --net1 name=eth1,bridge="$BRIDGE1",ip="$CT_IP1",mtu="$MTU1" \
  --ostype ubuntu \
  --nameserver "8.8.8.8"

echo "=== Binding host directories into container ==="

index=0
for mount_pair in "${MOUNTS[@]}"; do
  host_path="${mount_pair%%:*}"
  container_path="${mount_pair##*:}"
  if [ -d "$host_path" ]; then
  pct set $CT_ID -mp${index} "${host_path},mp=${container_path}"
  index=$((index + 1))
else
  echo "Warning: Host path $host_path does not exist. Skipping mount."
fi

done

echo "=== Starting container $CT_ID ==="
pct start $CT_ID
sleep 5

echo "=== Configuring network in container ==="

# Configure eth0
pct exec $CT_ID -- ip link set dev eth0 up
pct exec $CT_ID -- ip addr add "$CT_IP0" dev eth0
pct exec $CT_ID -- ip route add default via "$GATEWAY"

# Configure eth1 (10GbE)
pct exec $CT_ID -- ip link set dev eth1 up
pct exec $CT_ID -- ip addr add "$CT_IP1" dev eth1


echo "=== Installing Python $PYTHON_VERSION and core utilities ==="
pct exec $CT_ID -- bash -c "
  apt update &&
  apt install -y software-properties-common &&
  add-apt-repository -y ppa:deadsnakes/ppa &&
  apt update &&
  apt install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python3-pip openssh-server sudo curl vim nano git
"

echo "=== Enabling and configuring SSH ==="
pct exec $CT_ID -- systemctl enable ssh
pct exec $CT_ID -- systemctl restart ssh
pct exec $CT_ID -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
pct exec $CT_ID -- sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
pct exec $CT_ID -- systemctl restart ssh

echo "=== Setting root password ==="
pct exec $CT_ID -- bash -c "echo root:$ROOT_PASSWORD | chpasswd"

echo "=== Installing ifupdown and configuring /etc/network/interfaces ==="
pct exec $CT_ID -- apt install -y ifupdown

pct exec $CT_ID -- bash -c "cat > /etc/network/interfaces << EOF
# interfaces(5) file used by ifup(8) and ifdown(8)

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $CT_IP0
    netmask 255.255.255.0
    gateway $GATEWAY
    dns-nameservers 8.8.8.8

auto eth1
iface eth1 inet static
    address $CT_IP1
    netmask 255.255.255.0
EOF"

pct exec $CT_ID -- systemctl enable networking


echo "=== Setting up system defaults ==="
pct exec $CT_ID -- bash -c "chmod -x /etc/update-motd.d/*"

echo "=== Setting up custom MOTD ==="
if [ -f "$TEMPLATE_DIR/motd-template" ]; then
  pct push $CT_ID "$TEMPLATE_DIR/motd-template" /tmp/motd-template
  pct exec $CT_ID -- bash -c '
    TOOLS=$(ls /opt | tr "\n" " " | sed "s/ \$//")
    sed "s/__TOOL_LIST__/$TOOLS/" /tmp/motd-template > /etc/motd
  '

else
  echo "Warning: motd-template not found. Skipping custom MOTD."
fi

echo "=== Setting up bash configuration ==="
if [ -f "$TEMPLATE_DIR/bashrc-template" ]; then
  pct push $CT_ID "$TEMPLATE_DIR/bashrc-template" /root/.bashrc
else
  echo "Warning: bashrc-template not found. Skipping .bashrc setup."
fi

if [ -f "$TEMPLATE_DIR/bash_aliases-template" ]; then
  pct push $CT_ID "$TEMPLATE_DIR/bash_aliases-template" /root/.bash_aliases
else
  echo "Warning: bash_aliases-template not found. Skipping .bash_aliases setup."
fi

pct exec $CT_ID -- chown root:root /root/.bashrc /root/.bash_aliases
pct exec $CT_ID -- chmod 644 /root/.bashrc /root/.bash_aliases

echo "=== Adding persistent dynamic tools list ==="
pct exec $CT_ID -- bash -c '
cat > /etc/profile.d/jb-tools.sh << EOF
#!/bin/bash
# Display installed JB tools after MOTD on SSH login

if [ -n "\$SSH_TTY" ]; then
  TOOLS=\$(ls /opt | tr "\n" " " | sed "s/ \$//")
  if [ -n "\$TOOLS" ]; then
    echo -e "\nInstalled tools: \$TOOLS\n"
  fi
fi

alias list-tools='\''ls /opt | tr "\n" " " | sed "s/ \$//"; echo'\''
EOF
chmod +x /etc/profile.d/jb-tools.sh
'

echo "=== Disabling pam_systemd.so to prevent SSH login delays ==="
pct exec $CT_ID -- sed -i 's/^session[[:space:]]\+optional[[:space:]]\+pam_systemd.so/# &/' /etc/pam.d/common-session

echo "=== Container $CT_ID created and configured ==="
echo "➡ Connect: ssh root@${CT_IP0%%/*}"
echo "=== Done ==="
