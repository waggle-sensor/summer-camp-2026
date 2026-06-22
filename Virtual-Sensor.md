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


1. Connect the Hardware


     **a.** Connect the GL.iNet router to the internet.  
      **b.** Connect the Reolink camera to a LAN port on the router using an ethernet cable.  
      **c.** Power on the camera.  
      **d.** Wait a few minutes for the camera to boot and establish a connection. Follow the Reolink camera's setup instructions to enable HTTPS access.

<!-- TODO: Is there a specific Reolink doc link or step you want to reference here for HTTPS setup? Adding one would help participants who haven't used Reolink before. -->




## Step 2: Add Cameras Using the Reolink App
Reolink cameras require initial setup through the **Reolink app**. You cannot configure them through a browser until after this step.


### 2a. Install the Reolink App


Download the Reolink app on your phone or computer:


    https://reolink.com/software-and-manual/


### 2b. Find the Camera UID


Each camera has a **UID** printed on a sticker on the back. Reolink UIDs typically begin with `9527` and consist of numbers and uppercase letters (e.g., `9527XXXXXXXXXXXX`).


### 2c. Add the Camera via UID


1. Open the Reolink app
2. Tap **+** to add a device
3. Select **UID**
4. Enter the UID from the camera's sticker. Skip to step 2d if you are unable to connect.
5. Log in with the camera credentials:


```
Username: admin
Password: Sysadmin25!!
```


### 2d. Add the Camera via IP


Follow these steps if you were unable to connect the camera via UID, otherwise skip to step 2e.


1. Connect the Reolink camera to the router through a LAN port using an ethernet cable.
2. Connect to the WireGuard VPN
3. Open the GL.iNet administration page: http://192.168.8.1
4. Navigate to the client list and record the Reolink camera's IP address under "Wired Device".
5. Open the Reolink app
6. Tap **+** to add a device
7. Select **IP/Domain** and paste in the camera's IP address
8. 5. Log in with the camera credentials:


```
Username: admin
Password: Sysadmin25!!
```


Required Screenshot


Filename: `00-reolink-app-cameras.png`


Must show:
- Cameras listed and online in the Reolink app






Required Screenshot


Filename:


    01-camera-detected.png


The screenshot must show:


- Reolink camera listed
- Assigned IP address
- Device status showing online


Example:


    Reolink-PTZ
    192.168.8.55
    Online




3. Create a Static DHCP Reservation


   To ensure the camera always receives the same IP address, configure a static DHCP reservation in the GL.iNet admin panel. This prevents the IP from changing after a reboot, which would break the port forwarding rule you'll set up next.
   
   *(MORE CONTEXT / IMAGE COMING LATER)*
   
   <!-- TODO: What are the exact steps in the GL.iNet UI to set a static reservation? (Usually under LAN > DHCP Reservations — confirm and fill in.) -->


Required Screenshot


Filename:


    02-static-dhcp.png


The screenshot must show:


- Camera MAC address
- Reserved IP address
- Reservation enabled




4. Verify Local Camera Access


Open:


    https://CSMERAS_IP_ADDRESS


Verify:


- Live video is visible
- PTZ controls function
- Camera settings are accessible


Required Screenshot


Filename:


    03-camera-live-view.png


The screenshot must show:


- Live video stream
- Camera name
- Date/time display if enabled




5. Configure Port Forwarding


   Set up a port forwarding rule on the GL.iNet router so that incoming traffic on a specific port gets directed to the camera. This makes the camera reachable through the WireGuard tunnel.


Settings → Network → Advanced → Server Settings
Turn on RTSP port 554 for video streaming access
Turn on HTTPS to access the camera on your browser


   
   *(ADD IMAGE HERE)*

   
   <!-- TODO: What port(s) are participants forwarding to? (e.g., 443 for HTTPS, or a custom RTSP port?) Adding the exact port number here would save participants from guessing. -->




Required Screenshot


Filename:


    04-port-forwarding.png


The screenshot must show:


- External port
- Internal IP address
- Internal port
- Rule enabled




6. Configure WireGuard on Jetson


6.a. First connect device to wifi 
Plug in a wifi dongle to the nano to be able to connect to the beryl wifi. Check if it is connected: 
Iwconfig


It should be recognized as wlan0 
Connect to beryl wifi now: 
`sudo nmcli dev wifi connect "GL-MT1300-7ec" password "goodlife"`


Save the IP address
`hostname -I`


Then ssh into the device based on the IP address from above
`ssh orin-nano@192.168.8.206




   6.b. Okay now connect to WireGuard


,








   Install the WireGuard configuration file provided by the Sage team, then enable the WireGuard tunnel on the GL.iNet router.
   
   > **Do not include any private keys** in screenshots, notes, or any files you submit or share.
   
   *(ADD IMAGE HERE)*




Required Screenshot


Filename:


    05-wireguard-config.png


The screenshot must show:


- Tunnel enabled
- Assigned VPN address
- Peer configured


Do not include private keys.




7. Submit Deployment Info to the Sage Team
   
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




7. Verify VPN Connectivity


   After the Sage team provisions the VPN connection, verify that the WireGuard tunnel is active and the camera is reachable through it.
   
   *(ADD IMAGE HERE)*
   
   <!-- TODO: What should participants actually check here? For example: ping the camera's LAN IP through the tunnel, confirm the tunnel shows "connected" in the GL.iNet UI, or try loading the camera's HTTPS stream? A specific command or UI check would make this step actionable. -->




Required Screenshot


Filename:


    06-wireguard-connected.png


The screenshot must show:


- Tunnel status connected
- Latest handshake
- Data sent and received


Example:


    Status: Connected
    Latest Handshake: 10 seconds ago
    Received: 12 MB
    Sent: 3 MB


---
#### Final Submission Checklist


Your deployment directory should contain the following before considering the deployment complete:


```
deployment/
├── 01-camera-detected.png
├── 02-static-dhcp.png
├── 03-camera-live-view.png
├── 04-port-forwarding.png
├── 05-wireguard-config.png
├── 06-wireguard-connected.png
└── deployment-notes.txt
```


Deployment is complete when all screenshots and the deployment notes file have been submitted and the Sage team can access the camera feed through the VPN.


#### Troubleshooting


| Problem | What to Check |
|---|---|
| Camera not found on client list | Camera power, ethernet cable, router LAN connection |
| Camera web interface not reachable | Camera IP address, static DHCP config, camera network settings |
| WireGuard tunnel not connecting | Internet connectivity, VPN config file, public key submission |
| Camera reachable locally but not through Sage | Port forwarding rule, WireGuard tunnel status, VPN provisioning status |


---





