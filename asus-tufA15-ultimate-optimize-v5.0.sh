#!/bin/bash
# ==========================================================
# ASUS TUF A15 (Ryzen 7 6800H + RTX 3070)
# Smart Linux Optimization Script with logging
# Version: v5.2 by Kyrillos & Copilot
# Target: Manjaro / Arch (Kernel 6.12+)
# Log: /var/log/asus-optimizer.log
# ==========================================================

LOG="/var/log/asus-optimizer.log"
TIMESTAMP() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(TIMESTAMP)] $*" | tee -a "$LOG"; }

# 0 Root check
if [ "$EUID" -ne 0 ]; then
    echo "Run as root (sudo bash $0)"
    exit 1
fi

# Ensure log exists and is writable
touch "$LOG"
chmod 0644 "$LOG"
chown root:root "$LOG"

log "=============================================="
log "🧊 ASUS TUF A15 - Smart Optimization Script START"
log "=============================================="

USER_NAME="$(logname 2>/dev/null || echo root)"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6 || echo "/home/$USER_NAME")
log "Detected user: $USER_NAME"
log "User home: $USER_HOME"

# Redirect remaining stdout/stderr to log
exec > >(while IFS= read -r line; do echo "[$(TIMESTAMP)] $line" >> "$LOG"; done) 2>&1

log "[0] Start environment snapshot"
log "Kernel: $(uname -r)"
log "OS release: $(cat /etc/os-release 2>/dev/null | sed -n '1,5p' | tr '\n' ' | ')"

# helper: wait/clear pacman lock
_wait_pacman_unlock(){
  tries=0
  while fuser /var/lib/pacman/db.lck >/dev/null 2>&1; do
    log "[pkg] pacman db locked, waiting..."
    sleep 2
    tries=$((tries+1))
    if [ $tries -ge 15 ]; then
      log "[pkg][WARN] pacman lock persists, removing stale lock"
      rm -f /var/lib/pacman/db.lck || true
      break
    fi
  done
}

# 1 Update system
log "[1] Updating packages (pacman -Syyu)..."
_wait_pacman_unlock
pacman -Syyu --noconfirm || log "[1][WARN] pacman update returned non-zero exit code"

# 2 Check ASUS repo availability and install asusctl/supergfxctl
REPO_URL="https://download.opensuse.org/repositories/home:/luke_nukem:/asus-linux/Arch/x86_64/asus-linux.db"
log "[2] Checking ASUS Linux repository: $REPO_URL"
if curl -sfI "$REPO_URL" >/dev/null; then
    log "[2][OK] ASUS repo reachable. Installing asusctl supergfxctl"
    _wait_pacman_unlock
    pacman -S --noconfirm --needed asusctl supergfxctl || log "[2][WARN] pacman install returned non-zero"
else
    log "[2][WARN] ASUS repo not reachable. Falling back to AUR via yay"
    if ! command -v yay &>/dev/null; then
        log "[2] Installing yay prerequisites"
        _wait_pacman_unlock
        pacman -S --needed --noconfirm base-devel git || log "[2][WARN] pacman base-devel/git failed"
        sudo -u "$USER_NAME" bash -c 'rm -rf ~/yay && git clone https://aur.archlinux.org/yay.git ~/yay && cd ~/yay && makepkg -si --noconfirm' || log "[2][WARN] Building yay failed"
    else
        log "[2] yay already installed"
    fi
    if command -v yay &>/dev/null; then
      sudo -u "$USER_NAME" yay -S --noconfirm --needed asusctl-git supergfxctl-git || log "[2][WARN] yay install failed or interactive prompts occurred"
    else
      log "[2][WARN] yay not available; skipping AUR install"
    fi
fi

# 3 Dependencies - skip tlp install if power-profiles-daemon is present (Manjaro default)
log "[3] Installing dependencies: (powertop nvidia-utils auto-cpufreq) and tlp unless conflicting"
WAITED=0
_wait_pacman_unlock
pacman -S --noconfirm --needed powertop nvidia-utils || log "[3][WARN] pacman deps install returned non-zero"

# install auto-cpufreq (AUR or repo)
if ! pacman -Qs auto-cpufreq >/dev/null 2>&1; then
  if command -v yay >/dev/null 2>&1; then
    sudo -u "$USER_NAME" yay -S --noconfirm --needed auto-cpufreq || log "[3][WARN] yay auto-cpufreq failed"
  else
    log "[3][WARN] auto-cpufreq not available and yay missing"
  fi
fi

# decide tlp
if pacman -Qi power-profiles-daemon >/dev/null 2>&1; then
  log "[3] power-profiles-daemon exists; skipping tlp install to avoid conflict"
else
  _wait_pacman_unlock
  pacman -S --noconfirm --needed tlp || log "[3][WARN] pacman tlp install returned non-zero"
fi

# 4 Enable main services when available
log "[4] Enabling and starting services: auto-cpufreq, supergfxd, asusd, tlp (if present)"
for svc in auto-cpufreq supergfxd asusd tlp; do
  if systemctl list-unit-files | grep -q "^${svc}.service"; then
    systemctl enable --now "${svc}.service" && log "[4][OK] enabled/started ${svc}" || log "[4][WARN] enable/start ${svc} returned non-zero"
  else
    log "[4] ${svc}.service not present; skipping"
  fi
done

# 5 Default GPU -> Integrated
log "[5] Setting GPU mode -> Integrated using supergfxctl"
if command -v supergfxctl &>/dev/null; then
    if supergfxctl -g >/dev/null 2>&1; then
        supergfxctl -m Integrated && log "[5][OK] GPU set to Integrated" || log "[5][WARN] supergfxctl set returned non-zero"
    else
        log "[5][WARN] supergfxctl present but get failed"
    fi
else
    log "[5][WARN] supergfxctl not found"
fi

# 6 Fan and power profile via asusctl (use supported subcommands)
log "[6] Applying Quiet power profile via asusctl (if available)"
if command -v asusctl &>/dev/null; then
    if asusctl profile -P Quiet >/dev/null 2>&1 || asusctl profile Quiet >/dev/null 2>&1; then
        log "[6][OK] Power profile set to Quiet"
    else
        log "[6][WARN] asusctl profile set failed"
    fi
else
    log "[6][WARN] asusctl not found"
fi

# 7 Battery charge control: pick BAT1 or BAT0
log "[7] Configuring battery thresholds (safe)"
BAT_PATH=""
if [ -d /sys/class/power_supply/BAT1 ]; then BAT_PATH="/sys/class/power_supply/BAT1"
elif [ -d /sys/class/power_supply/BAT0 ]; then BAT_PATH="/sys/class/power_supply/BAT0"
fi

if [ -n "$BAT_PATH" ]; then
    SFILE="$BAT_PATH/charge_control_start_threshold"
    EFILE="$BAT_PATH/charge_control_end_threshold"
    if [ -e "$SFILE" ] && [ -w "$SFILE" ] 2>/dev/null; then
        echo 40 > "$SFILE" && log "[7][OK] Set charge_control_start_threshold to 40" || log "[7][WARN] Failed to write start threshold"
    else
        log "[7][WARN] start threshold file missing or not writable ($SFILE)"
    fi
    if [ -e "$EFILE" ] && [ -w "$EFILE" ] 2>/dev/null; then
        echo 60 > "$EFILE" && log "[7][OK] Set charge_control_end_threshold to 60" || log "[7][WARN] Failed to write end threshold"
    else
        log "[7][WARN] end threshold file missing or not writable ($EFILE)"
    fi
else
    log "[7][WARN] No BAT0/BAT1 found; skipping battery threshold config"
fi

# 8 Disable Turbo Boost / PMF mode and persist (fixed unit)
log "[8] Disabling CPU Turbo Boost / AMD PMF if available"
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
    echo 0 > /sys/devices/system/cpu/cpufreq/boost && log "[8][OK] Turbo boost disabled via cpufreq" || log "[8][WARN] failed to write cpufreq/boost"
elif [ -f /sys/devices/platform/amd-pmf/power_mode ]; then
    echo 0 > /sys/devices/platform/amd-pmf/power_mode && log "[8][OK] AMD PMF set to eco" || log "[8][WARN] failed to write amd-pmf/power_mode"
else
    log "[8][WARN] No boost or amd-pmf interface found; skipping"
fi

log "[8] Creating corrected disable-turbo.service"
cat > /etc/systemd/system/disable-turbo.service <<'EOF'
[Unit]
Description=Disable Turbo Boost on Boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then echo 0 > /sys/devices/system/cpu/cpufreq/boost; elif [ -f /sys/devices/platform/amd-pmf/power_mode ]; then echo 0 > /sys/devices/platform/amd-pmf/power_mode; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now disable-turbo.service || log "[8][WARN] enable/start disable-turbo returned non-zero"

# 9 NVIDIA Game Mode service (fixed ExecStartPost using /bin/sh -c)
log "[9] Creating corrected nvidia-game-mode.service"
cat > /etc/systemd/system/nvidia-game-mode.service <<'EOF'
[Unit]
Description=Enable NVIDIA GPU for Gaming (Hybrid Mode)
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/supergfxctl -m Hybrid
ExecStartPost=/bin/sh -c '/usr/bin/command -v nvidia-smi >/dev/null 2>&1 && /usr/bin/nvidia-smi -pl 100 || true'
ExecStartPost=/bin/sh -c '/usr/bin/command -v nvidia-smi >/dev/null 2>&1 && /usr/bin/nvidia-smi -lgc 300,1300 || true'
RemainAfterExit=yes
ExecStop=/usr/bin/supergfxctl -m Integrated
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
log "[9] Created/updated nvidia-game-mode.service (disabled by default)"

# 10 Create 'game' launcher (wrapper) — keep simple launcher but prefer using sudoers
log "[10] Creating 'game' launcher in $USER_HOME/.local/bin"
mkdir -p "$USER_HOME/.local/bin"
cat > "$USER_HOME/.local/bin/game" <<'EOF'
#!/bin/bash
echo "Activating NVIDIA GPU..."
sudo systemctl start nvidia-game-mode.service
sleep 2
"$@"
RC=$?
echo "Game finished (exit $RC), reverting to Integrated GPU..."
sudo systemctl stop nvidia-game-mode.service
exit $RC
EOF
chmod 755 "$USER_HOME/.local/bin/game"
chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME/.local/bin"
if ! sudo -u "$USER_NAME" grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$USER_HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
    log "[10] Added PATH export to $USER_HOME/.bashrc"
else
    log "[10] PATH export already present in bashrc"
fi

# 11 Power tuning with powertop (best-effort)
log "[11] Running powertop --auto-tune (best-effort)"
if command -v powertop &>/dev/null; then
    powertop --auto-tune || log "[11][WARN] powertop --auto-tune returned non-zero (may need battery run)"
else
    log "[11][WARN] powertop not installed"
fi

# Summary and verification outputs
log "----------------------------------------------"
log "SUMMARY: Checking service statuses and key files"
for svc in auto-cpufreq supergfxd asusd tlp disable-turbo nvidia-game-mode; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        log "Service ${svc}: enabled=$(systemctl is-enabled ${svc}.service 2>/dev/null || echo disabled) active=$(systemctl is-active ${svc}.service 2>/dev/null || echo inactive)"
    else
        log "Service ${svc}: not installed"
    fi
done

# GPU mode check using supported interface
if command -v supergfxctl >/dev/null 2>&1; then
    if supergfxctl -g >/dev/null 2>&1; then
        log "GPU mode: $(supergfxctl -g 2>/dev/null || echo unknown)"
    fi
else
    log "supergfxctl not available"
fi

if [ -n "$BAT_PATH" ]; then
    log "Battery: $BAT_PATH exists; start_threshold=$(cat $BAT_PATH/charge_control_start_threshold 2>/dev/null || echo N/A) end_threshold=$(cat $BAT_PATH/charge_control_end_threshold 2>/dev/null || echo N/A)"
else
    log "Battery: no BAT0/BAT1"
fi

log "----------------------------------------------"
log "✅ ASUS TUF A15 Optimization Completed!"
log "💻 GPU: Integrated by default"
log "🎮 Use: game <command> to run with NVIDIA GPU (ensure sudoers entry exists for systemctl start/stop)"
log "🔋 Battery thresholds attempt: start=40 end=60 (if supported)"
log "🧊 Turbo / PMF Boost: Disabled if interface existed"
log "🌀 Fan: Quiet (if supported)"
log "----------------------------------------------"
log "⚡ Reboot recommended to apply all persistent changes"

exit 0
