# Weather Station System Setup

## Overview

This guide explains how to set up a weather station using an industrial Raspberry Pi and supporting hardware to access weather data from ANL — including atmospheric temperature, pressure, humidity, wind speed, wind direction, and precipitation.

> **Note:** <!-- TODO: Fill in any prerequisites or important notes here before publishing (e.g., "Ensure you have SSH access to the Sage Thor node before starting.") -->

---

## Hardware Required

- IND 90W BT PoE Splitter (POE-SP02BTV)
- Industrial Raspberry Pi CM4 (ED-IPC2400)
- GbE 90W PoE++ Injector (POE-IN9001U)
- 2.5MM DC Plug to Free End 1000MM cable
- Access to a Sage Thor node
- ES-642 Remote Dust Monitor — measures: Particulate Concentration, Sample Relative Humidity, Ambient Barometric Pressure, Sample Temperature, Volumetric Flow Rate, and System Status Flags
- Lever wire connectors (optional but recommended)

---

## System Architecture

<img width="1920" height="1500" alt="System Architecture Diagram" src="https://github.com/user-attachments/assets/6c17cc54-9f8c-43af-a884-2938d233a5d2" />

---

## Part 1 — Connecting the RPi to the Weather Sensor

This section covers how to physically connect and wire all devices so they can communicate with each other before connecting to the Sage blades.

### Step 0 — Connect All Devices

Follow the system architecture diagram above for reference throughout this section.

**0.1.** Plug an ethernet cable from the Blade (Thor Rack) into the **Data In** port of the PoE Injector (POE-IN9001U).

**0.2.** Plug a CAT6 or higher ethernet cable from the PoE Injector's **Data Out** port into the **BT PoE Input** port of the PoE++ Splitter (POE-SP02BTV).

**0.3.** Connect the PoE++ Splitter's **Data Output** port to the ethernet port on the Industrial RPi (ED-IPC2400) using an RJ45 ethernet cable.

**0.4.** To power the Industrial RPi (ED-IPC2400):
   - Use the 2.5MM DC Plug to Free End cable.
   - Wire the **positive** and **negative** leads to the **Dual DC Outputs** — specifically the **3–36V DC Output** side.
   - Use the adjustment screw to the right of the output to set the voltage to **24V**.
   - Plug the DC connector end into the **DC In** port on the Industrial RPi.

**0.5.** To connect the RPi to the ES-642 weather sensor, locate the external cable (part number 80959) and strip the following wires:
   - **Red** — Power Input, 11–40 VDC (Pin 1)
   - **Black** — Ground (Pin 2)
   - **White** — RS-485 TX+/RX+ (Pin 3)
   - **Green** — RS-485 TX−/RX− (Pin 4)
   - **Orange** — Ground (Pin 5)
   - **Blue** — Ground (Pin 6)

<!-- QUESTION: How much should participants strip from each wire? A length (e.g., ~5mm) would help avoid under/over-stripping. -->

**0.6.** Using the RPi's Phoenix connector ports:
   - Connect the **White** wire to port **A4**.
   - Connect the **Green** wire to port **B4**.

**0.7.** Bundle the **Black**, **Orange**, and **Blue** wires together into a lever wire connector. Run a single black wire out of the connector and into the **24V DC Out Negative** port on the PoE++ Splitter.

**0.8.** Run a blue wire out of the lever wire connector into the **GND port** (located below B4) on the RPi using the Phoenix connector ports.

**0.9.** Connect the **Red** wire from the external cable (part number 80959) into the **24V DC Out Positive** port on the PoE++ Splitter.

Completed wiring should look like this:

<img width="2268" height="4032" alt="Wiring photo" src="https://github.com/user-attachments/assets/6164b190-ce08-4358-95df-1a681d5bef08" />

---

## Part 2 — Flashing and Configuring the Industrial RPi

### Step 1 — Flash the Industrial RPi (ED-IPC2400)

**1.1.** Flash the eMMC by following **Section 6.2 — Flashing to eMMC** in the ED-IPC2400 User Manual (page 27):

[ED-IPC2400 User Manual (PDF)](https://edatec.cn/docs/assets/ipc2400/ED-IPC2400-usermanual-en.pdf)

<img width="783" height="497" alt="Section 6.2 screenshot" src="https://github.com/user-attachments/assets/75809145-e651-4d7c-8903-8d127c73df7e" />

**1.2.** Install the firmware package by following **Section 6.3 — Installing Firmware Package** in the same manual (page 30):

<img width="789" height="420" alt="Section 6.3 screenshot" src="https://github.com/user-attachments/assets/55996ecd-69e0-4f8a-a8bf-0287285abc11" />

**1.3.** Install `picocom` to enable serial communication between the RPi and the weather sensor:

```bash
sudo apt-get install picocom
```

**1.4.** Test the serial connection by running:

```bash
picocom -b 9600 /dev/com4
```

<!-- FLAG: `/dev/com4` is unusual on Linux — serial ports are typically `/dev/ttyS0`, `/dev/ttyUSB0`, or `/dev/ttyAMA0`. This may be correct for the ED-IPC2400's specific port naming, but worth double-checking before participants run into errors. -->

A successful connection should look like this:

<img width="994" height="580" alt="Picocom connection screenshot" src="https://github.com/user-attachments/assets/6362a947-da1e-4e9c-b1fa-5a2f0e723ead" />

---

## Part 3 — Communicating Between the RPi and the Sage Blade

This section covers configuring the RPi to expose the weather sensor's serial data over the network so the Sage blade can read it.

### Step 2 — Configure ser2net on the RPi

**2.1.** Install `ser2net` on the RPi:

```bash
sudo apt update
sudo apt install ser2net
```

**2.2.** Open the `ser2net` configuration file:

```bash
sudo nano /etc/ser2net.yaml
```

**2.3.** Add the following connection profile to the bottom of the file. This defines the network accepter (the TCP port other devices connect to) and the serial connector (the physical port the sensor is on):

```yaml
connection: &met_one_sensor
    accepter: tcp,4000
    connector: serialdev,/dev/com4,9600N81,local
    options:
        kickolduser: true
```

> **Note:** Make sure port `4000` is not already in use on the RPi before adding this. You can use a different port number if needed.

**2.4.** Save and exit the file (`Ctrl+X`, then `Y`, then `Enter`), then restart the `ser2net` service to apply the changes:

```bash
sudo systemctl restart ser2net
```

**2.5.** Confirm the port is open and listening:

```bash
sudo ss -ltpn | grep 4000
```

<!-- QUESTION: What should the output of this command look like when it's working correctly? Adding an example output here (similar to the picocom screenshot) would help participants know whether their setup succeeded. -->

---

*More steps coming — work in progress.*

---

## Part 3 — Bridging the Weather Sensor to the Network with SerialMux

This section configures the RPi to broadcast the weather sensor's serial data over TCP using **SerialMux** — a lightweight serial-to-TCP multiplexer that allows multiple clients to read from and write to a single serial device simultaneously. Once set up, the Sage blade (and any other client) can connect to this RPi over the network and receive live weather data without needing a direct serial connection.

<!-- FLAG: The previous version of this guide used ser2net for this step. This version switches to SerialMux — confirm whether both are in use or if SerialMux fully replaces ser2net, so the older Part 3 can be removed if it's no longer needed. -->

> **Note:** In the steps below, the serial port is `/dev/com3`. This corresponds to the RS-485 connection wired through Phoenix connector pins **A3 and B3**.

<!-- FLAG: Step 0.6 in the wiring section says to connect the White and Green wires to **A4 and B4**, but this step references **A3 and B3** as the communication port. Please verify which pins are correct — this mismatch will cause the serial connection to fail if the wires and the port don't match. -->

### Step 2 — Install SerialMux

**2.1.** Go to the SerialMux releases page and find the latest release that matches your device architecture (e.g., `linux_arm64` for the Jetson/RPi CM4):

```
https://github.com/seanshahkarami/serialmux/releases
```

**2.2.** Copy the download link for the correct file, then download it on the RPi:

```bash
wget <paste-link-for-your-device-here>
```

Example (version and architecture will vary):
```bash
wget https://github.com/seanshahkarami/serialmux/releases/download/v0.2.0/serialmux_v0.2.0_linux_arm64.tar.gz
```

**2.3.** Extract the downloaded archive to the current directory:

```bash
tar -xvf <filename.tar.gz>
```

**2.4.** Navigate into the extracted directory:

```bash
cd serialmux_v0.2.0_<your-version>
```

> **Note:** There may be two SerialMux files inside the archive — make sure you `cd` into the versioned directory (e.g., `serialmux_v0.2.0_linux_arm64`), not a nested subfolder.

**2.5.** Before running SerialMux, confirm that port `20001` is not already in use:

```bash
sudo ss -ltpn | grep 20001
```

If no output appears, the port is free. If something is already using it, choose a different unused port and substitute it in the remaining steps.

**2.6.** Start SerialMux with the following flags:

```bash
./serialmux -crlf -dev /dev/com3 -debug -baud 9600 -addr :20001
```

| Flag | Purpose |
|---|---|
| `-crlf` | Adds carriage return + line feed to each line (required for RS-485 instruments like the ES-642) |
| `-dev /dev/com3` | The serial port connected to the weather sensor |
| `-debug` | Prints activity to the terminal so you can see what's happening |
| `-baud 9600` | Baud rate matching the ES-642's default serial speed |
| `-addr :20001` | The TCP port SerialMux will broadcast on |

If SerialMux starts successfully, you should see a line like this in the terminal:

```
2026/07/22 21:05:47 serialmux: /dev/com3 @ 9600 baud <-> :20001
```

<!-- FLAG: The `-crlf` flag behavior should be confirmed — on some serialmux builds this flag controls CRLF line-ending translation. If the ES-642 doesn't require it, removing it might clean up the output. Worth testing both ways. -->

---

### Step 3 — Verify the Connection with NetCat

With SerialMux running in one terminal, open a **second terminal** and use NetCat to connect to the broadcasted serial port and confirm data is flowing.

**3.1.** Install NetCat if it isn't already available:

```bash
sudo apt install netcat-openbsd
```

**3.2.** Connect to the SerialMux broadcast from the second terminal:

```bash
nc -C <RPi-IP-address> 20001
```

> The `-C` flag sends CRLF line endings to match what SerialMux expects from clients.

You can find your RPi's IP address by running `hostname -I` in the first terminal.

**3.3.** Once NetCat is connected, you should start seeing weather data stream in automatically. If no data appears, the sensor may be in a stopped state — enter communication mode by pressing **Enter** a few times until you see a `*` prompt, then type:

```
s 1
```

This sends the start command to the ES-642 and should trigger it to begin transmitting data.

<!-- IMAGE HERE: NetCat terminal showing incoming weather data from the ES-642 -->

**ES-642 Command Reference**

The following commands can be typed through the NetCat terminal while in communication mode (at the `*` prompt):

```
# Sampling
S 1          Start sampling
S 0          Stop sampling
ST 0         Set sample time to continuous/infinite collection
             (replace 0 with a number for a fixed sample count, e.g., ST 10)

# Status and Measurements
RQ           Display current measurement
OP           Display operation status
RV           Report firmware revision
ID           Set unit ID

# Calibration
CAL          Enter calibration mode
CAX          Exit calibration mode
RA <temp>    Set reference ambient temperature
RF <flow>    Set reference flow rate
RP <bp>      Set reference barometric pressure
RR <rh>      Set reference relative humidity

# Analog Output
AV <v>       Set analog voltage
AR <r>       Set analog range (in µg)

# Set Points
SPR          Set RH set point
SPA          Set concentration alarm set point

# Other
Q, X         Exit user mode
H, ?         Display help / command menu
```

> **How this works:** SerialMux sits between the weather sensor and the network — it reads the raw RS-485 serial data from `/dev/com3` and rebroadcasts it over TCP on port `20001`. NetCat (or any TCP client, including the Sage blade) can then connect to that port and receive the sensor stream as if it were connected directly to the serial port. The `-crlf` flags on both sides ensure line endings are handled correctly across the RS-485 and TCP protocols.

The connection is now set up. The Sage blade can connect to `<RPi-IP>:20001` to receive live weather data.

---

## Part 4 — Setting Up a USB-over-IP Microphone

USB-over-IP (USB/IP) allows a USB device physically connected to one machine (the RPi) to be accessed remotely over the network by another machine (the Sage blade), as if it were plugged in locally.

### Step 4 — Install and Configure USB/IP on the RPi

**4.1.** Install the USB/IP tools:

```bash
sudo apt update
sudo apt install usbip
```

<!-- FLAG: On some Debian/Ubuntu-based systems the package is part of `linux-tools-generic` or `linux-tools-$(uname -r)` rather than a standalone `usbip` package. If `sudo apt install usbip` returns "unable to locate package," try: `sudo apt install linux-tools-generic` -->

**4.2.** Load the required kernel modules:

```bash
sudo modprobe usbip-core
sudo modprobe usbip-host
```

**4.3.** To make these modules load automatically on every reboot, add them to `/etc/modules`:

```bash
echo "usbip-core" | sudo tee -a /etc/modules
echo "usbip-host" | sudo tee -a /etc/modules
```

**4.4.** Create a systemd service so the USB/IP daemon starts automatically on boot. Open a new service file:

```bash
sudo vim /etc/systemd/system/usbipd.service
```

Paste in the following:

```ini
[Unit]
Description=USB/IP Host Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/usbipd
Restart=always

[Install]
WantedBy=multi-user.target
```

Save and exit (`:wq` in vim).

**4.5.** Reload systemd and enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now usbipd.service
```

**4.6.** List the USB devices connected to the RPi to find the microphone's bus ID:

```bash
sudo usbip list -l
```

The output will look something like:

```
 - busid 1-1.4 (046d:0825)
   Logitech, Inc. : Webcam C270 (046d:0825)
```

Record the `busid` value (e.g., `1-1.4`) for the next step.

**4.7.** Bind the microphone to USB/IP using its bus ID:

```bash
sudo usbip bind -b <bus-id>
```

You should see a confirmation message indicating the device has been bound successfully.

<!-- QUESTION: What happens on the client (blade) side — does the blade also need usbip installed, and is there a corresponding `usbip attach` command to run there? If so, that step should be documented here as well. -->

---

*More steps coming — work in progress.*