# Atheros AR9271 (ath9k_htc) no M5Stack CardputerZero

Guia completo e script automatizado para fazer o adaptador Wi-Fi USB Atheros AR9271 funcionar no **M5Stack CardputerZero** (Raspberry Pi Compute Module 0 / BCM2837, Debian 13 Trixie, Kernel 6.x) com alimentação elétrica estável e inicialização automática em **Modo Monitor**.

---

## ⚡ Instalação Rápida (One-Liner)

Se você já está com o Cardputer conectado à internet via Wi-Fi interno (`wlan0`), basta rodar no terminal do Cardputer:

```bash
curl -sSL https://raw.githubusercontent.com/ChacalDeOZ/CardputerZero-AR9271/main/setup_ar9271.sh | sudo bash
```

Após o término da execução, reinicie o Cardputer:
```bash
sudo reboot
```

---

## 🔌 1. Hardware Utilizado e Topologia de Alimentação

O chip Atheros AR9271 consome picos de até **500mA a 5V** durante a calibração do rádio (RF PA). O circuito interno da bateria do Cardputer não suporta esse pico de corrente, causando queda de tensão e erro de timeout no barramento USB (`device descriptor read/64, error -110`).

### 📡 1.1. Adaptador Wi-Fi Testado e Homologado:
* **Modelo Oficial:** [Adaptador Wi-Fi USB Atheros AR9271 10dBi Pentest (Mercado Livre)](https://www.mercadolivre.com.br/adaptador-wi-fi-usb-atheros-ar9271-10dbi-pentest-kali-linux/p/MLB2093400683)
* **Chipset:** Qualcomm Atheros Communications AR9271 (USB ID: `0cf3:9271`)
* **Driver Linux:** `ath9k_htc` (Firmware: `htc_9271-1.4.0.fw`)
* **Antena:** 10 dBi destacável com alto ganho
* **Recursos:** Suporte nativo a Modo Monitor (Monitor Mode) e Injeção de Pacotes (Packet Injection)

### 📦 1.2. Hub USB Testado e Homologado:
* **Modelo Oficial:** [UGREEN Hub USB-C 5 em 1 - Modelo 10919 (Amazon)](https://www.amazon.com.br/dp/B08HZ1GGH9)
* **Portas do Hub:**
  * 1x Porta USB-C com suporte a **Power Delivery (PD 100W)** *(entrada de energia)*
  * 2x Portas USB-A 3.0 *(dados e alimentação para a placa Atheros)*
  * 1x Porta Gigabit Ethernet RJ45 (1000 Mbps)
  * 1x Porta HDMI 4K @ 60Hz
* **Chips Internos Identificados pelo Sistema:**
  * Controlador USB Hub: Genesys Logic USB 2.1 Hub (`05e3:0610`)
  * Controlador Power Delivery / Billboard: Fresco Logic FL7102 (`1d5c:7102`)
  * Controlador Gigabit Ethernet: ASIX AX88179A (`0b95:1790`)

> [!NOTE]
> Outros modelos de hubs USB-C multiportas alimentados também funcionarão, desde que possuam entrada USB-C Power Delivery e que a regra de isolamento de canais da Seção 2.4 esteja ativa para evitar concorrência no barramento.

---

### 🔌 1.3. Ordem de Conexão Física (Obrigatória):
1. Conecte um carregador USB-C na porta de alimentação (**PD**) do hub UGREEN.
2. Conecte o adaptador **Atheros AR9271** em uma das portas USB-A do hub.
3. Conecte o cabo do hub na porta USB do **Cardputer**.

> [!IMPORTANT]
> O carregador USB-C precisa estar conectado ao hub para suprir a energia necessária. Sem alimentação externa no hub, o chip reinicia por subtensão (brownout).

---

## 🛠️ 2. O que o Script Configura no Sistema

Caso prefira fazer manualmente, estas são todas as alterações necessárias:

### 2.1. Driver USB Nativo do Raspberry Pi (`/boot/firmware/config.txt`)
A imagem padrão ativa o driver genérico `dwc2`, que falha com transações divididas (*split-transactions*) em hubs cascateados, gerando o erro fatal `dwc2_hc_halt() Channel can't be halted`.
* **Solução:** Comentar a linha no `/boot/firmware/config.txt`:
  ```ini
  #dtoverlay=dwc2
  ```
  Isso faz o kernel carregar o driver nativo **`dwc_otg`** do Raspberry Pi, que possui aceleração por hardware **FIQ** e FSM de split-transactions.

### 2.2. Trilho de 5V Contínuo (`/etc/systemd/system/ext5v.service`)
Garante que a saída do conversor boost de 5V da porta do Cardputer fique no nível máximo (255) em todo boot:
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

### 2.3. Parâmetros do Módulo Atheros (`/etc/modprobe.d/ath9k_htc.conf`)
Desativa a suspensão de energia agressiva do chip (`ps_enable=0`), impedindo que o firmware durma durante a injeção ou captura de pacotes:
```text
options ath9k_htc ps_enable=0
```

### 2.4. Isolamento de Conflito de Canais do Hub (`/etc/udev/rules.d/60-disable-hub-extra.rules`)
O hub UGREEN possui chips internos Gigabit Ethernet (ASIX `0b95:1790`) e Billboard (`1d5c:7102`) que saturam os 8 canais de hardware do SoC. Esta regra desautoriza esses chips extras para dedicar 100% dos canais USB à placa Atheros:
```udev
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1d5c", ATTR{idProduct}=="7102", ATTR{authorized}="0"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b95", ATTR{idProduct}=="1790", ATTR{authorized}="0"
```

### 2.5. Prevenção de Conflito com NetworkManager (`/etc/NetworkManager/conf.d/99-unmanaged-wlan1.conf`)
Impede que o NetworkManager escaneie redes na `wlan1`, o que travava o kernel (`rtnl_lock`) ao ativar o modo monitor:
```ini
[keyfile]
unmanaged-devices=interface-name:wlan1
```

### 2.6. Automação do Modo Monitor (Boot & Hotplug)
Cria o serviço `/etc/systemd/system/ath9k-monitor.service` e a regra de udev `/etc/udev/rules.d/70-ath9k-monitor.rules` para colocar a interface `wlan1` em **Modo Monitor automaticamente** toda vez que for conectada ou que o sistema iniciar.

---

## 🎮 3. Comandos Úteis

* **Ativar Modo Monitor manualmente:**
  ```bash
  sudo monitor-on
  ```
* **Desativar Modo Monitor (voltar para modo cliente normal):**
  ```bash
  sudo monitor-off
  ```
* **Escanear redes com salto de canais (Aircrack suite):**
  ```bash
  sudo airodump-ng wlan1
  ```
* **Captura direta de pacotes brutos (RadioTap / 802.11):**
  ```bash
  sudo tcpdump -i wlan1 -c 10 -n -e
  ```

---

## 📜 Licença
Distribuído sob a licença MIT.
