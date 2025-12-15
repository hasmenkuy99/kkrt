#!/bin/bash
set -e

### VARIABLES ###
SWAPSIZE=2G
SERVICE_NAME="sgr1"

### ADD SWAP ###
add_swap() {
    if swapon --show | grep -q "/swapfile"; then
        echo "Swap already enabled."
        return
    fi

    echo "Adding ${SWAPSIZE} swap..."
    sudo fallocate -l ${SWAPSIZE} /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    grep -q "/swapfile" /etc/fstab || \
      echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab

    echo "Swap enabled."
}

### ULIMIT ###
increase_ulimit() {
    echo "Setting file descriptor limits..."

    sudo sed -i '/fs.file-max/d' /etc/sysctl.conf
    echo "fs.file-max = 100000" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p

    sudo sed -i '/nofile/d' /etc/security/limits.conf
    cat <<EOF | sudo tee -a /etc/security/limits.conf
* soft nofile 4096
* hard nofile 4096
EOF
}

### AUDIT ###
configure_audit() {
    sudo apt-get update
    sudo apt-get install -y auditd

    cat <<EOF | sudo tee /etc/audit/rules.d/kill.rules
-w /usr/bin/kill -p x -k kill_logs
EOF

    sudo augenrules --load
    sudo systemctl restart auditd
}

### SYSTEMD ###
configure_systemd() {
    sudo mkdir -p /etc/systemd/system/${SERVICE_NAME}.service.d

    cat <<EOF | sudo tee /etc/systemd/system/${SERVICE_NAME}.service.d/limits.conf
[Service]
LimitNOFILE=4096
EOF

    sudo systemctl daemon-reexec
}

### CORE DUMPS ###
enable_core_dumps() {
    sudo sed -i '/kernel.core_pattern/d' /etc/sysctl.conf
    echo "kernel.core_pattern=/var/lib/systemd/coredump/core.%e.%p.%h.%t" \
      | sudo tee -a /etc/sysctl.conf

    sudo sysctl -p

    grep -q "ulimit -c unlimited" /etc/profile || \
      echo "ulimit -c unlimited" | sudo tee -a /etc/profile
}

### SIGNAL HANDLER DEMO ###
handle_signals() {
cat <<'EOF' > signal_handler_example.py
import signal, time, sys

def handler(sig, frame):
    print("Graceful shutdown")
    sys.exit(0)

signal.signal(signal.SIGTERM, handler)

while True:
    time.sleep(1)
EOF
}

### MAIN ###
main() {
    add_swap
    increase_ulimit
    configure_audit
    configure_systemd
    enable_core_dumps
    handle_signals
    echo "All configurations applied safely."
}

main
