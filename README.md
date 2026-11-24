# Atheros AR9271 (ath9k_htc) on M5Stack CardputerZero

A comprehensive guide and automated setup script to run the **Qualcomm Atheros AR9271** USB Wi-Fi adapter on the **M5Stack CardputerZero** (Raspberry Pi Compute Module 0 / BCM2837, Debian 13 Trixie, Linux Kernel 6.x) with stable electrical power and automatic initialization into **Monitor Mode**.

---

## ⚡ Quick Start (One-Liner Installation)

If your Cardputer is already connected to the internet via internal Wi-Fi (`wlan0`), execute this single command directly in the Cardputer terminal:

```bash
curl -sSL https://raw.githubusercontent.com/ChacalDeOZ/CardputerZero-AR9271/main/setup_ar9271.sh | sudo bash
```

Once execution finishes, reboot the Cardputer:
```bash
sudo reboot
```

---

## 🔌 1. Tested Hardware & Power Topology

The Atheros AR9271 chipset consumes current spikes of up to **500mA at 5V** during radio frequency (RF PA) calibration. The Cardputer's internal battery and boost converter cannot sustain this sudden surge when plugged in directly, causing a voltage droop and a USB bus timeout error (`device descriptor read/64, error -110`).

### 📡 1.1. Tested & Verified Wi-Fi Adapter:
* **Product:** [Atheros AR9271 10dBi High-Gain USB Wi-Fi Adapter](https://www.mercadolivre.com.br/adaptador-wi-fi-usb-atheros-ar9271-10dbi-pentest-kali-linux/p/MLB2093400683)
* **Chipset:** Qualcomm Atheros AR9271 (USB ID: `0cf3:9271`)
* **Linux Driver:** `ath9k_htc` (Firmware: `htc_9271-1.4.0.fw`)
* **Antenna:** Detachable 10 dBi high-gain omnidirectional antenna
* **Capabilities:** Native Monitor Mode, Packet Injection, and AP Mode

### 📦 1.2. Tested & Verified USB Hub:
* **Product:** [UGREEN 5-in-1 USB-C Hub - Model 10919 (Amazon)](https://www.amazon.com.br/dp/B08HZ1GGH9)
* **Ports:**
  * 1x USB-C Power Delivery input port (**PD 100W**) *(power input)*
  * 2x USB-A 3.0 ports *(data and power pass-through to Atheros adapter)*
  * 1x Gigabit Ethernet RJ45 port (1000 Mbps)
  * 1x HDMI 4K @ 60Hz port
* **Internal Chipsets Identified by System:**
  * USB Hub Controller: Genesys Logic USB 2.1 Hub (`05e3:0610`)
  * Power Delivery / Billboard Controller: Fresco Logic FL7102 (`1d5c:7102`)
  * Gigabit Ethernet Controller: ASIX AX88179A (`0b95:1790`)

> [!NOTE]
> Other powered USB-C multiport hubs will also work, provided they feature a dedicated USB-C Power Delivery input port and that the USB channel isolation rule (Section 2.4) is enabled to prevent host channel starvation.

---

### 🔌 1.3. Connection Sequence (Mandatory):
1. Connect a USB-C charger to the **PD power input port** of the UGREEN hub.
2. Plug the **Atheros AR9271** adapter into one of the USB-A ports on the hub.
3. Plug the hub's host cable into the USB port of the **Cardputer**.

> [!IMPORTANT]
> The USB-C charger must remain connected to the hub's PD port to deliver continuous, clean 5V power. Operating without external power causes brownouts during RF calibration.

---

## 🛠️ 2. System Configurations Explained

For manual setup or reference, here is the full breakdown of all required system modifications:

### 2.1. Native Raspberry Pi USB Host Driver (`/boot/firmware/config.txt`)
The default OS image loads the generic `dwc2` driver, which lacks hardware FIQ acceleration and fails on split transactions across cascaded hubs, resulting in fatal channel lockups: `dwc2_hc_halt() Channel can't be halted`.
* **Fix:** Disable `dwc2` in `/boot/firmware/config.txt` by commenting it out:
  ```ini
  #dtoverlay=dwc2
  ```
  This instructs the kernel to load the native Raspberry Pi **`dwc_otg`** host driver, which features **hardware FIQ acceleration** and a split-transaction finite state machine (FSM).

### 2.2. Continuous 5V Boost Rail (`/etc/systemd/system/ext5v.service`)
Ensures the Cardputer's external boost regulator is persistently set to maximum output (255) on boot:
```ini
[Unit]
Description=Enable 5V Boost Rail on USB/Grove
DefaultDependencies=no
After=systemd-modules-load.service
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 255 > /sys/class/leds/ext_5v_out/brightness'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
```

### 2.3. Atheros Module Parameters (`/etc/modprobe.d/ath9k_htc.conf`)
Disables aggressive power-saving sleep transitions (`ps_enable=0`), preventing firmware lockups during packet injection or interface state changes:
```text
options ath9k_htc ps_enable=0
```

### 2.4. Hub Channel Isolation (`/etc/udev/rules.d/60-disable-hub-extra.rules`)
The UGREEN hub includes onboard Gigabit Ethernet (ASIX `0b95:1790`) and Billboard (`1d5c:7102`) chips that consume host channels on the SoC's 8-channel USB controller. This rule deauthorizes those extra endpoints so 100% of host channels are dedicated to the AR9271:
```udev
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d5c", ATTR{idProduct}=="7102", ATTR{authorized}="0"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b95", ATTR{idProduct}=="1790", ATTR{authorized}="0"
```

### 2.5. NetworkManager Conflict Prevention (`/etc/NetworkManager/conf.d/99-unmanaged-wlan1.conf`)
Prevents NetworkManager from attempting to scan on `wlan1`, which otherwise acquires `rtnl_lock` and freezes network operations when entering monitor mode:
```ini
[keyfile]
unmanaged-devices=interface-name:wlan1
```

### 2.6. Automated Monitor Mode (Boot & Hotplug)
Deploys `/etc/systemd/system/ath9k-monitor.service` and udev rule `/etc/udev/rules.d/70-ath9k-monitor.rules` to automatically bring `wlan1` into **Monitor Mode** whenever the adapter is attached or the device boots.

---

## 🎮 3. Useful Commands

* **Enable Monitor Mode manually:**
  ```bash
  sudo monitor-on
  ```
* **Disable Monitor Mode (switch back to managed/client mode):**
  ```bash
  sudo monitor-off
  ```
* **Check interface mode and transmission power:**
  ```bash
  iw dev wlan1 info
  ```
* **Real-time network reconnaissance (Aircrack suite):**
  ```bash
  sudo airodump-ng wlan1
  ```
* **Raw 802.11 / RadioTap frame capture:**
  ```bash
  sudo tcpdump -i wlan1 -c 10 -n -e
  ```

---

## 📜 License
Released under the [MIT License](LICENSE).
