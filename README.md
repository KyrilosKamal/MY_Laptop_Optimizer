# ASUS TUF A15 Smart Optimization Script

A reproducible, scenario-based Linux optimization script tailored for ASUS TUF A15 (Ryzen 7 6800H + RTX 3070) running Manjaro or Arch Linux. It automates GPU switching, power management, fan profiles, battery thresholds, and game mode activation — all with detailed logging and safe fallbacks.

---

## 🧠 Features

- ✅ GPU switching via `supergfxctl` (Integrated by default, Hybrid on demand)
- 🎮 Game mode service with NVIDIA power tuning (`nvidia-game-mode.service`)
- 🔋 Battery charge thresholds (start=40%, end=60%) if supported
- 🌀 Fan and power profile via `asusctl` (Quiet mode)
- 🚫 Turbo Boost / AMD PMF disabled for thermal efficiency
- ⚙️ Auto-enable services: `auto-cpufreq`, `supergfxd`, `asusd`, `tlp` (if compatible)
- 📦 Fallback to AUR via `yay` if ASUS repo is unreachable
- 🧾 Full timestamped logging to `/var/log/asus-optimizer.log`
- 🧩 Creates a simple `game` launcher for GPU-activated gaming sessions

---

## 📦 Requirements

- Manjaro or Arch Linux (Kernel 6.12+ recommended)
- ASUS TUF A15 (Ryzen 7 6800H + RTX 3070)
- `asusctl`, `supergfxctl`, `auto-cpufreq`, `powertop`, `nvidia-utils`
- Optional: `tlp` (skipped if `power-profiles-daemon` is present)
- Optional: `yay` for AUR fallback

---

## 🚀 Usage

```bash
sudo bash asus-optimizer.sh
```
---
## 🎮 Game Mode Launcher
After running the script, use the ```game``` launcher to run any game with NVIDIA GPU activated:
```bash
game /path/to/game-binary
```
Requires ```sudoers``` entry to allow ```systemctl start/stop nvidia-game-mode.service``` without password.

---

### 🔐 Sudoers Configuration (Optional)
To avoid password prompts when launching games:
```bash
sudo visudo
```
Add this line (replace ```username``` with your actual username):
```bash
username ALL=(root) NOPASSWD: /bin/systemctl start nvidia-game-mode.service, /bin/systemctl stop nvidia-game-mode.service
```
---

###🧪 Tested Scenarios
✅ GPU switches correctly between Integrated and Hybrid
✅ Battery thresholds applied if supported
✅ Turbo/PMF disabled and persisted via systemd
✅ Game mode activates NVIDIA GPU and applies power limits
✅ Services auto-enabled and verified
---
###📁 Log File

All actions are logged with timestamps to:
```bash
/var/log/asus-optimizer.log
```
---
###🛠️ Troubleshooting
- Mouse freeze after GPU switch?
  * Try disabling autosuspend for I2C HID devices via udev rule.
tlp``` conflict```?
Check with:
```bash
journalctl -xeu nvidia-game-mode.service
```
Script skips it if ```power-profiles-daemon``` is installed.
```nvidia-game-mode.service``` fails?
Check with:
```bash
journalctl -xeu nvidia-game-mode.service
```

---
###📜 License
MIT — use, modify, and share freely.
---
###🤝 Credits

Script by **Kyrillos** Optimized for reproducibility, clarity, and safe automation.
