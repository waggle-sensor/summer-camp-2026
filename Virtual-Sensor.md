# Reolink PTZ Camera Deployment Guide for Sage

## Overview

This guide explains how to connect a Reolink PTZ camera to the Sage infrastructure using a GL.iNet Beryl AX router and a WireGuard VPN connection.

Follow each step in order and collect the required screenshots as evidence that the deployment was completed successfully.

---

## Hardware Required

- Reolink PTZ camera
- GL.iNet Beryl AX router (this guide uses the GL-MT1300)
- Internet connection
- Ethernet cable
- Camera power supply
- A phone or computer with the Reolink app installed

---

## Step 1 — Connect the Hardware

**a.** Connect the GL.iNet router to the internet.  
**b.** Connect the Reolink camera to a LAN port on the router using an ethernet cable.  
**c.** Power on the camera.  
**d.** Wait a few minutes for the camera to boot and establish a connection.

---

## Step 2 — Add the Camera Using the Reolink App

Reolink cameras require initial setup through the **Reolink app**. You cannot configure them through a browser until after this step.

### 2a. Install the Reolink App

Download the Reolink app on your phone or computer:

```
https://reolink.com/software-and-manual/
```

### 2b. Find the Camera UID

Each camera has a **UID** printed on a sticker on the back. Reolink UIDs typically begin with `9527` and consist of numbers and uppercase letters (e.g., `9527XXXXXXXXXXXX`).

### 2c. Add the Camera via UID

1. Open the Reolink app.
2. Tap **+** to add a device.
3. Select **UID**.
4. Enter the UID from the camera's sticker. If you're unable to connect, skip to step 2d.
5. Log in with the camera credentials:

```
Username: admin
Password: Sysadmin25!!
```

**Required Screenshot — `00-reolink-app-cameras.png`**
Must show: cameras listed and online in the Reolink app.

### 2d. Add the Camera via IP (if UID connection failed)

If you were unable to connect via UID, follow these steps instead. Otherwise, skip to Step 3.

1. Ensure the Reolink camera is connected to the router via ethernet.
2. Connect to the WireGuard VPN.
3. Open the GL.iNet admin page at `http://192.168.8.1`.
4. Navigate to the client list and record the Reolink camera's IP address under **Wired Device**.
5. Open the Reolink app.
6. Tap **+** to add a device.
7. Select **IP/Domain** and paste in the camera's IP address.
8. Log in with the camera credentials:

```
Username: admin
Password: Sysadmin25!!
```

**Required Screenshot — `01-camera-detected.png`**  
Must show:
- Reolink camera listed
- Assigned IP address
- Device status showing online

Example:
```
Reolink-PTZ
192.168.8.55
Online
```

---

## Step 3 — Create a Static DHCP Reservation

To ensure the camera always receives the same IP address, configure a static DHCP reservation in the GL.iNet admin panel. This prevents the IP from changing after a reboot, which would break the port forwarding rule set up in the next step.

*(IMAGE COMING LATER)*

**Required Screenshot — `02-static-dhcp.png`**  
Must show:
- Camera MAC address
- Reserved IP address
- Reservation enabled

---

## Step 4 — Verify Local Camera Access

In a browser, navigate to:

```
https://CAMERA_IP_ADDRESS
```

Verify:
- Live video is visible
- PTZ controls function
- Camera settings are accessible

**Required Screenshot — `03-camera-live-view.png`**  
Must show:
- Live video stream
- Camera name
- Date/time display (if enabled)

---

## Step 5 — Configure Port Forwarding

Set up a port forwarding rule on the GL.iNet router so that incoming traffic on a specific port is directed to the camera. This makes the camera reachable through the WireGuard tunnel.

In the camera's settings, go to **Settings → Network → Advanced → Server Settings** and enable the following:

- **RTSP** on port `554` — for video streaming
- **HTTPS** on port `443` — for browser access

*(IMAGE COMING LATER)*

**Required Screenshot — `04-port-forwarding.png`**  
Must show:
- External port
- Internal IP address
- Internal port
- Rule enabled

---

## Step 6 — Connect the Jetson to the Router via WireGuard

### 6a. Connect the Jetson to the Router's Wi-Fi

Plug a Wi-Fi dongle into the Jetson Orin Nano, then verify it's recognized:

```bash
iwconfig
```

It should appear as `wlan0`. Connect to the GL.iNet router's Wi-Fi network:

```bash
sudo nmcli dev wifi connect "GL-MT1300-7ec" password "goodlife"
```

Note the Jetson's IP address for the next step:

```bash
hostname -I
```

Then SSH into the device:

```bash
ssh orin-nano@<JETSON_IP>
```

### 6b. Install the WireGuard Configuration

Install the WireGuard configuration file provided by the Sage team, then enable the WireGuard tunnel on the GL.iNet router.

> ⚠️ **Do not include any private keys** in screenshots, notes, or any files you submit or share.

*(IMAGE COMING LATER)*

**Required Screenshot — `05-wireguard-config.png`**  
Must show:
- Tunnel enabled
- Assigned VPN address
- Peer configured

Do not include private keys in the screenshot.

---

## Step 7 — Submit Deployment Info to the Sage Team

Create a file named `deployment-notes.txt` in your deployment directory and fill it out:

```
Site Name:
Camera Model:
Camera Serial Number:
Router Model:
Camera LAN IP:
Forwarded Port:
WireGuard Public Key:
```

---

## Step 8 — Verify VPN Connectivity

After the Sage team provisions the VPN connection, confirm that the WireGuard tunnel is active and the camera is reachable through it.

*(IMAGE COMING LATER)*

**Required Screenshot — `06-wireguard-connected.png`**  
Must show:
- Tunnel status: Connected
- Latest handshake
- Data sent and received

Example:
```
Status: Connected
Latest Handshake: 10 seconds ago
Received: 12 MB
Sent: 3 MB
```

---

## Final Submission Checklist

Your deployment directory should contain the following before the deployment is considered complete:

```
deployment/
├── 00-reolink-app-cameras.png
├── 01-camera-detected.png
├── 02-static-dhcp.png
├── 03-camera-live-view.png
├── 04-port-forwarding.png
├── 05-wireguard-config.png
├── 06-wireguard-connected.png
└── deployment-notes.txt
```

Deployment is complete when all screenshots and the deployment notes file have been submitted and the Sage team can access the camera feed through the VPN.

---

## Troubleshooting

| Problem | What to Check |
|---|---|
| Camera not found on client list | Camera power, ethernet cable, router LAN connection |
| Camera web interface not reachable | Camera IP address, static DHCP config, camera network settings |
| WireGuard tunnel not connecting | Internet connectivity, VPN config file, public key submission |
| Camera reachable locally but not through Sage | Port forwarding rule, WireGuard tunnel status, VPN provisioning status |
