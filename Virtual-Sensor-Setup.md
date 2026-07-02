# Reolink PTZ Camera Deployment + WireGaurd Guide for Sage

## Overview

This guide explains how to connect a Reolink PTZ camera to the Sage infrastructure using a GL.iNet router and a WireGuard WireGaurd connection.

> **Note:** These steps apply to both the GL.iNet Beryl AX and the Shadow router — the setup process is the same for both.

Follow each step in order and collect the required screenshots as evidence that the deployment was completed successfully.

---

## Hardware Required

- Reolink PTZ camera
- GL.iNet router (Beryl AX GL-MT1300 or Shadow)
- Internet connection
- Ethernet cable(s) — add a network switch if connecting multiple cameras
- Camera power supply
- A phone or computer with the Reolink app installed

---

## Step 0 — Configure the Router

1. Connect the GL.iNet router to the internet through the WAN port using an ethernet cable.
2. Connect your laptop to the router — either through a LAN port via ethernet, or via the router's Wi-Fi. The Wi-Fi password is on a sticker on the bottom of the router.
3. Open `http://192.168.8.1` in a browser to access the router's web admin panel.
4. Set a username and password for the admin panel.
5. Under **Internet**, configure the Ethernet settings. Contact CS IT to get the correct IP address, gateway, subnet mask, and DNS server.

### Optional — Enable Remote Access from Outside the Network

If you need to access the router from outside the local network, complete these additional steps:

6. In the side panel, go to **VPN → WireGuard Server** and press **Start**.
7. Click **View Status**, scroll down to the WireGuard section, and enable **Allow Remote Access LAN**.
8. Click **Apply** and exit.

*(ADD IMAGE: WireGuard server status screen showing Remote Access LAN enabled)*

---

## Step 1 — Connect the Camera

1. Connect the Reolink camera to a LAN port on the router using an ethernet cable. For multiple cameras, connect a network switch to the LAN port first, then connect cameras to the switch.
2. Power on the camera.
3. Wait a few minutes for the camera to fully boot.

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
Password: [see camp coordinator for password]
```

<!-- FLAG: The original has a hardcoded password here. Since this file will live on a public GitHub repo, I've replaced it with a placeholder — you should either keep it as a placeholder and share credentials separately, or confirm this repo is private. -->

**Required Screenshot — `01-reolink-app-cameras.png`**
Must show: cameras listed and online in the Reolink app.

### 2d. Add the Camera via IP (if UID connection failed)

If UID connection failed, follow these steps instead. Otherwise, skip to Step 3.

1. Confirm the Reolink camera is connected to the router via ethernet.
2. Connect to the WireGuard VPN or the router's Wi-Fi.
3. Open the GL.iNet admin page at `http://192.168.8.1`.
4. Navigate to the **Client List** in the left panel and record the camera's IP address.
5. Open the Reolink app.
6. Tap **+** to add a device.
7. Select **IP/Domain** and paste in the camera's IP address.
8. Log in with the camera credentials (same as above).

**Required Screenshot — `02-camera-detected.png`**
Must show:
- Reolink camera listed
- Assigned IP address

Example:
```
Reolink-PTZ
192.168.8.55
```

*(ADD IMAGE: GL.iNet client list with Reolink camera highlighted)*

---

## Step 3 — Configure Camera Settings

This step enables the camera stream to be visible via a web browser and RTSP.

1. In the Reolink app, tap the **settings gear icon** next to your camera.
2. Go to **Network → Advanced → Server Settings**.
3. Enable **HTTPS** and **RTSP**.
4. Save and exit.

**Required Screenshot — `03-camera-settings.png`**
Must show:
- HTTPS enabled
- RTSP enabled

*(ADD IMAGE: Reolink app server settings screen with HTTPS and RTSP toggled on)*

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

**Required Screenshot — `04-camera-live-view.png`**
Must show:
- Live video stream
- Camera name
- Date/time display (if enabled)

---

## Step 5 — Create a Static DHCP Reservation

To ensure the camera always receives the same IP address, configure a static DHCP reservation. This prevents the IP from changing after a reboot, which would break the port forwarding rule set up in the next step.

1. Open the GL.iNet admin page at `http://192.168.8.1`.
2. Open the **Network** dropdown on the right and select **LAN**.
3. Scroll down and click the blue **Add** button to create a static DHCP reservation.
4. Click the **MAC** dropdown and select your camera — the IP and description should auto-populate.
5. Save the reservation.

**Required Screenshot — `05-static-dhcp.png`**
Must show:
- Camera MAC address
- Reserved IP address
- Reservation enabled

*(ADD IMAGE: GL.iNet LAN settings showing the static DHCP reservation entry)*

---

## Step 6 — Configure the WireGuard Client (Connect to Sage VPN)

1. In the GL.iNet admin panel, go to **VPN → WireGuard Client**.
2. Click the blue **Add Configuration** button.
3. On a Linux machine, generate a WireGuard key pair:

```bash
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

4. View your public key — you'll share this with the Sage team:

```bash
cat client_public.key
```

5. Keep your private key secure. You'll paste it into the configuration in the next step.

6. Select **Manual Input** and enter the following, replacing the placeholder values with what you've received from the Sage team and CS IT:

```ini
[Interface]
Address = <IP address provided by Sage team>
PrivateKey = <your private key from step 5>
DNS = <DNS address from CS IT, or use 8.8.8.8>
MTU = 1420

[Peer]
AllowedIPs = 10.107.0.0/16
Endpoint = vpn.sagecontinuum.org:51821
PersistentKeepalive = 25
PublicKey = <Sage server public key — provided by Sage team>
```

<!-- FLAG: The original had the Sage server public key hardcoded here. Replaced with a placeholder — confirm whether it's okay to include in a public repo, or if it should stay as a placeholder. -->

7. Name the configuration and click **Apply**. The router is now connected to the Sage VPN.

8. Go to **VPN → VPN Dashboard**, click **Global Proxy**, and switch it to **Auto Detect**. This ensures only traffic intended for the Sage network goes through the VPN — all other traffic uses your regular internet connection.

9. Share your public key with the Sage development team.

**Required Screenshot — `06-wireguard-config.png`**
Must show:
- Tunnel enabled
- Assigned VPN address
- Peer configured

> **Do not include your private key** in any screenshot, notes, or submitted files.

*(ADD IMAGE: GL.iNet WireGuard client screen showing the active configuration)*

---

## Step 7 — Configure Port Forwarding

Set up a port forwarding rule so that incoming traffic through the WireGuard tunnel on a specific port is directed to the camera.

1. Open the GL.iNet admin page at `http://192.168.8.1`.
2. Open the **Network** dropdown and select **Firewall**.
3. Click the blue **+ Add** button and fill out the rule:

| Field | Value |
|---|---|
| Name | Reolink Camera Name |
| Protocol | TCP/UDP |
| External Zone | wgclient |
| External Port | `1000X` (assign a unique port per camera) |
| Internal Zone | LAN |
| Internal IP | Your camera's reserved IP address |
| Internal Port | `554` (RTSP) |

4. Click **Apply** and exit.

<!-- QUESTION: What does `1000X` mean exactly — is this a placeholder for a specific numbering scheme (e.g., 10001, 10002 per camera)? Clarifying this would help participants deploying multiple cameras. -->

**Required Screenshot — `07-port-forwarding.png`**
Must show:
- External port
- Internal IP address
- Internal port
- Rule enabled

*(ADD IMAGE: GL.iNet Firewall screen showing the completed port forwarding rule)*

---

## Step 8 — Test the Connection

Confirm the camera is reachable through the Sage blade.

1. Note the WireGuard IP address assigned by the Sage team (format: `10.107.x.x`).
2. Ping the camera through the tunnel:

```bash
ping 10.107.x.x
```

<!-- QUESTION: Should participants also try loading the RTSP stream or HTTPS camera page here to confirm full video access, or is a successful ping enough? -->

---

## Step 9 — Configure WireGuard on the Jetson (Optional)
 
This step connects the Jetson Orin Nano directly to the GL.iNet router over Wi-Fi and joins it to the Sage WireGuard network, so it can reach the camera locally and be reachable by the Sage team.
 
### 9a. Connect the Jetson to the Router's Wi-Fi
 
1. Plug a Wi-Fi dongle into the Jetson Orin Nano.
2. Verify it is recognized as `wlan0`:
```bash
iwconfig
```
 
3. Connect to the GL.iNet router's Wi-Fi:
```bash
sudo nmcli dev wifi connect "GL-MT1300-7ec" password "[router wifi password]"
```
 
<!-- FLAG: Original had the router Wi-Fi password hardcoded. Replaced with a placeholder — same concern as above if this is a public repo. -->
 
4. Note the Jetson's IP address:
```bash
hostname -I
```
 
5. SSH into the Jetson from your laptop, using the IP address from the previous step:
```bash
ssh orin-nano@<JETSON_IP>
```
 
### 9b. Connect the Jetson to the Sage WireGuard Network
 
1. Install WireGuard on the Jetson:
```bash
sudo apt install wireguard -y
```
 
2. Generate a WireGuard configuration for the Jetson through the router's admin panel:
   1. Open the GL.iNet admin page at `http://192.168.8.1`.
   2. Navigate to **VPN → WireGuard Server → Profiles**.
   3. Enter a name for the profile and click **Apply**.
   4. Click **Configuration File** and copy the generated configuration.
3. Create the config file on the Jetson:
```bash
sudo nano /etc/wireguard/wg0.conf
```
 
   Paste in the configuration copied in the previous step, then save and exit.
 
4. Set the WireGuard zone's forward policy to `accept` (required for peer-to-peer routing — this defaults to `drop`, which will silently block traffic):
   1. Open the GL.iNet admin page at `http://192.168.8.1`.
   2. Navigate to **More Settings → Advanced**.
   3. Click the blue link to open LuCI.
   4. At the top of the page, click **Network**.
   5. Edit the WireGuard zone and change **Forward** from `drop` to `accept`.
   6. Click **Save & Apply**.
5. Start the WireGuard tunnel on the Jetson:
```bash
sudo wg-quick up wg0
```
 
> **Do not include any private keys** in screenshots, notes, or any files you submit or share.
 
**Required Screenshot — `08-wireguard-jetson.png`**
Must show:
- Tunnel enabled
- Assigned VPN address
- Peer configured
*(ADD IMAGE: Jetson terminal or WireGuard status showing the tunnel active)*
 
---
 
## Step 10 — Submit Deployment Info to the Sage Team
 
Create a file named `deployment-notes.txt` in your deployment directory and fill in the following:
 
```
Site Name:
Camera Model:
Camera Serial Number:
Router Model:
Camera LAN IP:
Forwarded Port:
WireGuard Public Key:
```
 
Also provide the following directly to the Sage team:
 
- Camera model
- Camera serial number (optional)
- Router model
- Router WireGuard public key
---
 
## Step 11 — Verify VPN Connectivity
 
After the Sage team provisions the VPN connection, confirm the WireGuard tunnel is active and the camera is reachable through it.
 
1. **Check tunnel status.**
   Run:
```bash
   sudo wg show
```
   Confirm a recent handshake (within the last ~2 minutes) and nonzero data sent/received.
 
2. **Ping the camera through the tunnel.**
   From the Sage node (or your machine, if peered), ping the camera's LAN IP:
```bash
   ping 192.168.8.XXX
```
   A successful reply confirms the tunnel is routing traffic to the router's LAN.
 
3. **Pull the RTSP stream.**
   Test the stream directly with `ffplay` or VLC:
```bash
   ffplay rtsp://admin:<password>@<camera_LAN_IP>:554/h264Preview_01_main
```
   If this loads video, the camera is fully reachable through the VPN.
 
4. **Confirm in the GL.iNet UI.**
   Open `http://192.168.8.1` → **VPN → WireGuard** and check that the tunnel shows **Connected** with a recent handshake, matching what `wg show` reported.
**Required Screenshot — `09-wireguard-connected.png`**
Must show:
- Tunnel status: Connected
- Latest handshake
- Data sent and received
Take this from either the `sudo wg show` output or the GL.iNet WireGuard status panel.
 
Example:
```
Status: Connected
Latest Handshake: 10 seconds ago
Received: 12 MB
Sent: 3 MB
```

*(ADD IMAGE: WireGuard status screen or `wg show` output showing an active connection)*

---

## Final Submission Checklist

```
deployment/
├── 01-reolink-app-cameras.png
├── 02-camera-detected.png
├── 03-camera-settings.png
├── 04-camera-live-view.png
├── 05-static-dhcp.png
├── 06-wireguard-config.png
├── 07-port-forwarding.png
├── 08-wireguard-jetson.png       ← if Step 9 applies
├── 09-wireguard-connected.png
└── deployment-notes.txt
```

Deployment is complete when all screenshots and the deployment notes file have been submitted and the Sage team can access the camera feed through the VPN.

---

## Troubleshooting

| Problem | What to Check |
|---|---|
| Camera not found on client list | Camera power, ethernet cable, router LAN connection |
| Camera web interface not reachable | Camera IP address, static DHCP config, camera network settings |
| WireGuard tunnel not connecting | Internet connectivity, VPN config file, public key submitted to Sage team |
| Camera reachable locally but not through Sage | Port forwarding rule, WireGuard tunnel status, VPN provisioning status |
