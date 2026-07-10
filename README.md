# Summer-Camp-2026

Welcome! This guide gets you set up for **Sage Grande: Summer of AI — Hack and Build AI@Edge**.

**Dates:** Monday, July 20 – Tuesday, July 28, 2026
**Location:** UIC Electronic Visualization Laboratory (EVL), Chicago, IL
**Format:** In-person, hands-on lab sessions

## Program Overview

This seven-day camp is a hands-on deep dive into building and deploying AI systems at the edge using the Sage platform. You'll work directly with real Sage nodes — moving past textbook concepts to build, test, and deploy working AI pipelines on live infrastructure.

The week moves from platform fundamentals through AI model deployment, data integration, sensor expansion, and autonomous agent design. By the end, you'll have shipped real code to real nodes, including new sensors, new AI models, and new automated workflows. Bring your own research ideas, sensors, and questions — you're encouraged to take an active role in expanding the Sage platform throughout the week.

## Prerequisite Skills

To get the most out of the week, come prepared with:

- General comfort with SSH and basic Linux command-line tools (navigating the filesystem, managing files, checking processes, etc.)
- Some hands-on experience running AI models locally (tools like Ollama or LM Studio are good starting points, but anything similar works)
- Working familiarity with Python, including writing simple scripts, using virtual environments, and installing packages
- Basic familiarity with containers (Docker or similar) is helpful but not required

Bring a laptop set up for local Python development — some exercises require running models and tools on your own machine in addition to the provided nodes.

## Daily Schedule

| Time | Activity |
|---|---|
| 8:00 AM – 9:30 AM | Open hacking / independent work |
| 9:30 AM – 12:30 PM | Morning session (3 hrs) |
| 12:30 PM – 1:30 PM | Lunch (on your own) |
| 1:30 PM – 4:30 PM | Afternoon session (3 hrs) |
| 4:30 PM – 6:00 PM | Open hacking / independent work |
| Evening | Dinner on your own; team hacking; optional after-hours activities |

## Agenda

- **Sun, Jul 19 — Check-in:** Informal welcome dinner.
- **Mon, Jul 20 — Sage Foundations & System Software:** Tour of the Sage stack (node architecture, Kubernetes orchestration, the `pluginctl` scheduler, data pipeline). Set up your dev environment, submit AI prompts to Sage nodes, and run a job against an existing inference service.
- **Tue AM, Jul 21 — Finalize Setup:** Configure your AI development toolchain (Cursor, Claude Code, MCP servers for Sage APIs) and complete the foundational Sage skill checkpoints. Start drafting your project plan.
- **Tue PM, Jul 21 — AI+Sage (Part 1):** Survey of models deployed across the fleet — BioClip2, YOLO variants, flood detection, cloud motion vectors, wildfire/smoke detection.
- **Wed, Jul 22 — AI+Sage (Parts 2 & 3):** Test model performance on real datasets, identify failure modes, adapt new models from Hugging Face, apply quantization for edge deployment, and submit models to the Edge Code Repository (ECR).
- **Thu AM, Jul 23 — AI+Sage (Part 4):** Wrap up AI exploration; advance your project with an AI coding agent.
- **Thu PM, Jul 23 — NRP/NDP and NSF Resources:** Connect Sage data and compute to NSF cyberinfrastructure (NDP, NRP, TACC, SDSC, NCSA) — querying Beehive data, integrating with NEON/NOAA/satellite data, publishing with DOIs/FAIR principles, and using the Pelican data federation.
- **Fri, Jul 24 — Sensors, Hardware & Physical Integration:** Hands-on sensor integration (infrasound, seismic, hyperspectral, HaLow cameras, LoRaWAN, actuators/robotics). Bring your own hardware. Goal: deploy at least one new sensor to a nearby node.
- **Sat, Jul 25 — Community Day:** Chicago River architecture tour, pizza, networking, and team hacking.
- **Sun, Jul 26 — Free Day:** Self-directed project work or rest.
- **Mon AM, Jul 27 — The Future:** AI agents and autonomous systems on Sage; finalize project plans.
- **Mon PM, Jul 27 — Hack Time:** Project work.
- **Tue AM, Jul 28 — Development, Testing & Prep**
- **Tue PM, Jul 28 — Project Presentations & Demos:** Show off your project, then dinner and farewell.

## Potential Hackathon Projects

Already have a project idea? Bring it. If not, here's an example to get you started:

**Image Search at the Edge** — Translate an NRP Kubernetes config into a `pluginctl` setup, swap in edge-friendly models (e.g., Gemma4), replace the vector database with an edge-compatible option (e.g., NVIDIA's NanoDB), and run benchmarks. Creative twist: pivot from "image search" to generating daily/weekly summaries of what the node sees.

More project topics will be announced based on participant interests.

## Baseline Deliverables

By the end of the week, every participant should have:

- Pushed new code to the ECR and run it on a deployed node
- Processed a batch of images using an LLM and written the results to Beehive
- Built and tested a data pipeline connecting two or more sensor streams

---

## Creating a Sage Account

1. Go to [sagecontinuum.org](https://sagecontinuum.org/) and click **Portal** in the top-right corner.

   <img width="1435" height="524" alt="Screenshot 2026-06-18 at 2 20 48 PM" src="https://github.com/user-attachments/assets/80f2d165-67bb-4158-b6f5-1be574e35f7f" />

2. You'll land on the Sage node status page. Click **Sign In** in the top-right corner, then create an account using your school credentials and fill out the remaining account details.

   <img width="1267" height="550" alt="Screenshot 2026-06-18 at 2 25 18 PM" src="https://github.com/user-attachments/assets/f4c8daab-fd94-4dce-a903-dbf97e8e050c" />

   Once your account is created, you'll be redirected to the Node Status page.

   <img width="1436" height="728" alt="Screenshot 2026-06-18 at 2 33 22 PM" src="https://github.com/user-attachments/assets/990d817e-b9b1-4190-8218-8c6987ec2435" />

3. Before you can access any nodes, you'll need to request access to the relevant devices:
   - Click your profile dropdown and select **Request Access**.
   - Choose **Request access to specific nodes or projects**.

   **a.** On Step 2 of the Sage Access Request form, open the **Projects (multiple allowed)** dropdown and search for **summer-camp-2026**. This covers all the devices you'll need for the hackathon.

   **b.** Select the following permissions:
   - Running apps (includes SageChat/LLMs)
   - Shell (SSH access)
   - File Access (downloading/viewing protected files) <!-- confirm: original text was "protectedChat/LLMS" — wasn't sure if this is the exact permission label, please double check against the form -->

   *(TABLE HERE + image here)*

   **c.** Fill in Section 3 **Project Information** based on your own and your PI's knowledge of the project.

4. Submit the request and allow up to 24 hours for it to be processed. Once approved, you'll be able to view your nodes under **My Nodes → My Nodes**.

   <img width="1433" height="733" alt="Screenshot 2026-06-18 at 2 53 31 PM" src="https://github.com/user-attachments/assets/804884f7-1c5f-44e0-9b3b-c6feac3c87d2" />

   You can now move on to **Sage Access Credentials** below.

---

## Sage Access Credentials

> You'll need a Sage account with approved node access (from the steps above) before starting this section. This walks you through generating SSH credentials so you can connect directly to nodes.

1. Go to your profile dropdown and click **Access Credentials**. Follow the prompts to generate an SSH key pair on your machine and upload the public key.

   <img width="1423" height="626" alt="Screenshot 2026-06-18 at 3 07 06 PM" src="https://github.com/user-attachments/assets/3e8a4f5f-85b8-4b01-aea2-088b9808cbdf" />

2. Once that's complete, follow the steps under **Finish Setup for Node Access**.

   <img width="1425" height="720" alt="Screenshot 2026-06-18 at 3 13 39 PM" src="https://github.com/user-attachments/assets/121013f6-1dd5-4525-b044-3f5146dba23d" />

3. You're now ready to SSH into a node:

   ```
   ssh waggle-dev-node-NODE_OF_CHOICE
   ```

---

## Setting up your Agent

To set up your personal agent, follow the instructions in the [Hermes Agent Setup Guide](hermes-agent.md).

---

## Sage Remote Sensors

A total of 4 devices act as remote sensors that are connected to Sage nodes via WireGuard.

## UIC Sage Blades

| Device Name | Location | Notes |
|---|---|---|
| UIC06 / H023 | TBD | TBD |
| UIC07 / H022 | TBD | TBD |
| UIC03 / H021 | TBD | TBD |
| UIC05 / H020 | TBD | TBD |
| UIC04 / H01F | TBD | TBD |
| UIC02 / H01E | TBD | TBD |
| UIC02 / H01D | TBD | TBD |

*(Access instructions TBD — likely handled through Sage.)*

## Tools / Devices

#### Devices
*(device table goes here)*

#### EdgeRunner
*(tutorial goes here)*

#### RPi Weather Station
*(access instructions go here)*

#### RPi USB Sensor
*(access instructions go here)*

#### WireGuard Remote Cameras
*(access instructions go here)*

#### 3D Printing
Fan / air circulation.
