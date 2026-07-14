# Sage documentation index (URL catalog)

Scraped from [sagecontinuum.org/docs](https://sagecontinuum.org/docs/getting-started) (sitemap) on **2026-07-14**.

## How to use this file

1. Skim the summaries below to find the page that answers the question.
2. **Fetch the live page** at the listed URL when you need full content (steps, commands, screenshots). Do not invent details from the summary alone.
3. Prefer camp skill refs (`pluginctl-camp-guide.md`, `sesctl-ecr-validation.md`, etc.) for Thor-specific CLI quirks — they may be newer than the website.
4. Optional helpers: Sage MCP `search_sage_docs` / `ask_sage_docs`, or `curl -sL '<url>'`.

**Pages indexed:** 27

Source website repo (markdown): [waggle-sensor/sage-website](https://github.com/waggle-sensor/sage-website)

## Getting started

### Getting Started with Sage

- **URL:** https://sagecontinuum.org/docs/getting-started
- **Summary:** This guide can help you get started based on your specific needs and expertise. Sage is a national AI research platform that brings artificial intelligence to the edge—right where data is collected in real time. Built around powerful, sensor-equipped nodes deployed in natural and urban environments, Sage allows scientists, students, and community partners to run AI directly in the field.
- **Sections:** What is Sage?; Creating an account; Choose your path; 🤖 AI Developers; 📊 AI Users; 🎓 Educators; ⚙️ AI Infrastructure & Operations; Common first steps

## About

### Architecture

- **URL:** https://sagecontinuum.org/docs/about/architecture
- **Summary:** The cyberinfrastructure consists of coordinating hardware and software services enabling AI at the edge. Below is a quick summary of the different infrastructure pieces, starting at the highest-level and zooming into each component to understand the relationships and role each plays. There are 2 main components of the cyberinfrastructure:
- **Sections:** High-Level Infrastructure; Beekeeper; Beehive; Beehive Infrastructure; Data Repository (DR); Edge Scheduler (ES); Edge Code Repository (ECR); Lambda Triggers (LT)

### Sage: A distributed software-defined sensor network.

- **URL:** https://sagecontinuum.org/docs/about/overview
- **Summary:** What is Sage? The Sage Grande Testbed (SGT)–an extension to the Sage NSF MSRI-1 project–will offer powerful tools like SageChat for natural language interaction, supports privacy-aware and trustworthy AI exploration, and provides a hands-on education pipeline through camps, workshops, and hackathons. As an open testbed funded by the NSF, Sage Grande invites researchers, educators, and community partners to build, test, and deploy AI applications that tackle urgent scientific and societal challenges.
- **Sections:** What is Sage?; How do I use the platform?; Who are the users?; How is the cyberinfrastructure architected?

### About (category)

- **URL:** https://sagecontinuum.org/docs/category/about
- **Summary:** Index of about pages: platform overview and cyberinfrastructure architecture (Beekeeper, Beehive, ECR, ES, DR, Lambda Triggers).

## Tutorials — accounts & platform

### Tutorials (category)

- **URL:** https://sagecontinuum.org/docs/category/tutorials
- **Summary:** Index of all Sage tutorials: accounts, edge apps, job scheduling, data access, sensors, cloud/HPC, build-your-own Waggle, Sage MCP.

### Create an account

- **URL:** https://sagecontinuum.org/docs/tutorials/create-an-account
- **Summary:** How to create and get an approved Sage portal account. Required for submitting jobs, accessing development nodes, and many write operations (public data query needs no account).

## Tutorials — edge apps

### Edge apps (category)

- **URL:** https://sagecontinuum.org/docs/category/edge-apps
- **Summary:** Four-part tutorial series index: Intro → Creating → Testing → Publishing to ECR. Start here for plugin/app development onboarding.

### Part 1: Intro to edge apps

- **URL:** https://sagecontinuum.org/docs/tutorials/edge-apps/intro-to-edge-apps
- **Summary:** What are edge apps? A basic example of an app is one which reads and publishes a value from a sensor every minute. A more complex example could publish the number of birds in a scene using a deep learning model.
- **Sections:** What are edge apps?; Exploring existing edge apps; Next steps

### Part 2: Creating an edge app

- **URL:** https://sagecontinuum.org/docs/tutorials/edge-apps/creating-an-edge-app
- **Summary:** Hands-on plugin writing: bootstrap from a template, install deps, access a camera, publish results, view run logs.
- **Sections:** Prerequisites; Development workflow; A driving example; Bootstrapping our app from a template; Installing the dependencies; Accessing a camera; Publishing results; Viewing run logs

### Part 3: Testing an edge app

- **URL:** https://sagecontinuum.org/docs/tutorials/edge-apps/testing-an-edge-app
- **Summary:** On-node testing: SSH to development nodes, create the app repo, `pluginctl` build/run, inspect output, then next steps toward ECR.
- **Sections:** Accessing development nodes; Creating a repo for our app; Building our app; Running our app; Viewing our output; Next steps

### Part 4: Publishing to ECR

- **URL:** https://sagecontinuum.org/docs/tutorials/edge-apps/publishing-to-ecr
- **Summary:** Register and publish the finished app to the Edge Code Repository (ECR) after local/on-node testing.
- **Sections:** Preparing our app; Publishing our app; Conclusion

## Tutorials — jobs, data, sensors, cloud, MCP

### Access Waggle sensors

- **URL:** https://sagecontinuum.org/docs/tutorials/access-waggle-sensors
- **Summary:** Physical and software-defined Waggle sensors; how edge apps sample them (e.g. camera images); bringing your own sensor onto Waggle.
- **Sections:** Waggle physical sensors; Waggle software-defined sensors; Access to Waggle sensors; Example: sampling images from camera; Bring your own sensor to Waggle

### Access and use data

- **URL:** https://sagecontinuum.org/docs/tutorials/accessing-data
- **Summary:** How data moves from edge plugins to Beehive; querying via sage-data-client and the HTTP Data API; accessing file uploads; notes on protected data.
- **Sections:** Data API; Using Sage data client; Using HTTP API; Accessing file uploads; Protected data

### Cloud compute & HPC on edge data

- **URL:** https://sagecontinuum.org/docs/tutorials/cloud-compute
- **Summary:** Waggle provides a number of interfaces which other computing and HPC systems can build on top of. In this section, we explore some of the most common applications of Waggle. A common application is monitoring data from the edge and triggering actions when values exceed a threshold or an unusual event is detected.
- **Sections:** Triggering on data from the edge

### Building your own Waggle device

- **URL:** https://sagecontinuum.org/docs/tutorials/create-waggle
- **Summary:** Build/design your own Waggle device for teaching or local plugin development; optionally register it to upload into a shared development environment.
- **Sections:** Getting Started; Registering your Waggle device

### Sage MCP Server

- **URL:** https://sagecontinuum.org/docs/tutorials/sage-mcp
- **Summary:** Overview of the Sage Model Context Protocol server: what it is, setup/prerequisites, first query, and conversational tutorials (find nodes, cameras, etc.).
- **Sections:** What is Sage MCP?; Getting started; Prerequisites; Configuration; Your first query; Tutorial: Exploring Sage through conversation; Step 1: Finding nodes by location; Step 2: Understanding what cameras see

### Submit your job

- **URL:** https://sagecontinuum.org/docs/tutorials/schedule-jobs
- **Summary:** End-to-end SES job tutorial: create/upload/submit a job, check status, access data, clean up. Requires a portal account; job *submission* permission may need a contact-us request. Deeper `sesctl` tutorials linked.
- **Sections:** Create a job; Upload your job to the scheduler; Submit the job; Check status of jobs; Access to data; Clean it up; More tutorials using sesctl; Creating job description with advanced science rules for supporting realistic science mission

## Reference guides

### Reference guides (category)

- **URL:** https://sagecontinuum.org/docs/category/reference-guides
- **Summary:** Index of reference docs: pluginctl, sesctl, LoRaWAN, trigger examples, developer quick reference.

### Developer quick reference

- **URL:** https://sagecontinuum.org/docs/reference-guides/dev-quick-reference
- **Summary:** Copy-paste oriented plugin developer checklist: app components, Dockerizing, ECR configs, SSH access to nodes, testing with pluginctl, schedule/debug tips. Not a full tutorial — use Edge Apps series for that.
- **Sections:** Disclaimer; Tips; Components of a plugin; 1. An application; 2. Dockerizing the app; 3. ECR configs and docs; Getting access to the node; Testing plugins on the nodes

### LoRaWAN

- **URL:** https://sagecontinuum.org/docs/reference-guides/lorawan
- **Summary:** What is LoRaWAN? LoRaWAN is a powerful technology that offers several advantages for all sorts of applications, particularly in scenarios where long-range communication and low power consumption are essential. Here are some key benefits of using LoRaWAN:
- **Sections:** What is LoRaWAN?; Why use LoRaWAN?; Capabilities; Signal Range; Lorawan Device Compatibility; Device Examples; Lorawan Device Profile Templates; How to get started?

### pluginctl: a tool to develop and test plugins on a node

- **URL:** https://sagecontinuum.org/docs/reference-guides/pluginctl
- **Summary:** On-node plugin develop/test tool: build container → run in WES/k3s → inspect results, before ECR registration. Pre-installed on Waggle nodes; typically `sudo pluginctl`. Full tutorials live in the edge-scheduler repo.

### sesctl: a tool to schedule jobs in Waggle edge computing

- **URL:** https://sagecontinuum.org/docs/reference-guides/sesctl
- **Summary:** The tool sesctl is a command-line tool that communicates with an Edge scheduler in the cloud to manage user jobs. Users can create, edit, submit, suspend, and remove jobs via the tool. The tool can be downloaded from the edge scheduler repository and be run on person's desktop or laptop.
- **Sections:** Installation; Submit a job; For more tutorials

### Trigger Examples

- **URL:** https://sagecontinuum.org/docs/reference-guides/triggers
- **Summary:** This page provides a few examples of triggers within Sage. Triggers are programs which generally use data and events from the edge or cloud to automatically drive or notify other behavior in the system. Cloud-to-edge triggers are programs running in the cloud which monitor events or external data sources and then, in response, change some behavior on the nodes.
- **Sections:** Cloud-to-Edge Examples; Severe Weather Trigger; Wildfire Trigger; Edge-to-Cloud Examples; Sage Data Client Batch Trigger; Sage Data Client Stream Trigger

## Events & training

### Sage Grande: Summer of AI (2026 hackathon)

- **URL:** https://sagecontinuum.org/docs/events/2026-Sage-Summer-Hackathon
- **Summary:** 2026 Summer of AI / hackathon event page: program overview, prerequisite skills, schedule, agenda, project ideas, baseline deliverables, interest form.
- **Sections:** Hack and Build AI@Edge; Program Overview; Prerequisite Skills; Daily Schedule; Agenda:; Potential Hackathon Projects; Baseline Deliverables for All Participants; Interest Form

### Sage Office Hours

- **URL:** https://sagecontinuum.org/docs/events/office-hours
- **Summary:** Recurring Sage office hours (expert Q&A). Register to receive the Zoom link.

## Node install & contact

### Contact us

- **URL:** https://sagecontinuum.org/docs/contact-us
- **Summary:** How to reach the Sage team: email, Slack, and office-hours Zoom registration.
- **Sections:** Email; Office Hours; Join us on Slack

### Node install & deploy manuals

- **URL:** https://sagecontinuum.org/docs/node-installation-manuals
- **Summary:** Downloadable PDFs for provisioning hardware: Thor-blade deployment guide, HPE blade bring-up for remote OS install, and legacy Wild Sage Node (WSN) manuals.
- **Sections:** Node installation & deployment manuals; Sage Grande Testbed (new); Sage Legacy Nodes

