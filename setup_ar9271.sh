#!/bin/bash
# ==============================================================================
# Script de Configuração Automatizada para Atheros AR9271 no M5Stack CardputerZero
# ==============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "[-] Execute este script como root (sudo bash $0)"
  exit 1
fi

echo "[*] 1. Configurando driver nativo dwc_otg em /boot/firmware/config.txt..."
if grep -q "^dtoverlay=dwc2" /boot/firmware/config.txt 2>/dev/null; then
  sed -i "s/^dtoverlay=dwc2/#dtoverlay=dwc2/" /boot/firmware/config.txt
  echo "[+] dtoverlay=dwc2 desativado."
fi

echo "[*] 2. Configurando servico de alimentacao de 5V (ext5v.service)..."
cat << 'EOF' > /etc/systemd/system/ext5v.service
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
EOF
systemctl daemon-reload
systemctl enable ext5v.service
echo 255 > /sys/class/leds/ext_5v_out/brightness 2>/dev/null || true

echo "[*] 3. Configurando parametros do modulo ath9k_htc..."
cat << 'EOF' > /etc/modprobe.d/ath9k_htc.conf
options ath9k_htc ps_enable=0
EOF

echo "[*] 4. Configurando isolamento de dispositivos extras do hub USB..."
cat << 'EOF' > /etc/udev/rules.d/60-disable-hub-extra.rules
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d5c", ATTR{idProduct}=="7102", ATTR{authorized}="0"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b95", ATTR{idProduct}=="1790", ATTR{authorized}="0"
EOF

echo "[*] 5. Configurando NetworkManager para ignorar wlan1..."
mkdir -p /etc/NetworkManager/conf.d
cat << 'EOF' > /etc/NetworkManager/conf.d/99-unmanaged-wlan1.conf
[keyfile]
unmanaged-devices=interface-name:wlan1
EOF
systemctl reload NetworkManager 2>/dev/null || true

echo "[*] 6. Criando comandos de controle rapido do modo monitor..."
cat << 'EOF' > /usr/local/bin/monitor-on
#!/bin/bash
ip link set wlan1 down 2>/dev/null
iw dev wlan1 set type monitor 2>/dev/null
ip link set wlan1 up 2>/dev/null
EOF
chmod +x /usr/local/bin/monitor-on

cat << 'EOF' > /usr/local/bin/monitor-off
#!/bin/bash
ip link set wlan1 down 2>/dev/null
iw dev wlan1 set type managed 2>/dev/null
ip link set wlan1 up 2>/dev/null
EOF
chmod +x /usr/local/bin/monitor-off

echo "[*] 7. Configurando inicializacao automatica do modo monitor..."
cat << 'EOF' > /etc/systemd/system/ath9k-monitor.service
[Unit]
Description=Auto-enable monitor mode on wlan1
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "sleep 1 && /usr/local/bin/monitor-on"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ath9k-monitor.service

cat << 'EOF' > /etc/udev/rules.d/70-ath9k-monitor.rules
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ath9k-monitor.service"
EOF
udevadm control --reload-rules 2>/dev/null || true

echo "[+] Concluido com sucesso! Reinicie o Cardputer para aplicar as configuracoes do barramento USB."
EOF