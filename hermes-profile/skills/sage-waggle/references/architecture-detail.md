# Sage/Waggle Architecture Detail

## Three-Tier System

### Edge Nodes
- **Hardware**: Nvidia Jetson Xavier NX (ARM64) primary, some x86. Wild Waggle Nodes (outdoor) and Sage Blades (indoor/rack).
- **Software stack**: Waggle Edge Stack (WES) — k3s cluster, plugin scheduler, data pipeline, reverse SSH tunnel to Beekeeper.
- **Sensors**: BME680 (temp/humidity/pressure/gas), RG-15 (rain gauge), cameras (top/bottom), microphones. Software-defined sensors (AI inference outputs).
- **Node IDs**: VSN format like W030, W09E, W0A0 (short hex). Full node ID is longer UUID.
- **OS**: Custom Linux image, updated via Beekeeper.

### Beehive (Cloud Services)
- **Message bus**: RabbitMQ — all data flows through here
- **Time-series DB**: Stores scalar measurements (temperature, humidity, counts)
- **Object store**: Open Storage Network (S3-compatible) for large files (images, audio, video)
- **Data API**: `data.sagecontinuum.org/api/v1/query` — public, no auth needed
- **Lambda Triggers**: Cloud functions triggered by incoming data patterns

### Beekeeper (Management)
- **Purpose**: Node identity, provisioning, registration, firmware updates
- **Connectivity**: Reverse SSH tunnels from each node
- **Manifests API**: `auth.sagecontinuum.org/manifests/` (all) and `/manifests/<vsn>` (one) — rich hardware + sensor URIs + GPS. Flatter beta twin: `/api/v-beta/nodes/` and `/api/v-beta/nodes/<vsn>`. Details: `references/auth-api-manifests-and-nodes.md` (source app: [waggle-auth-app](https://github.com/waggle-sensor/waggle-auth-app)).

## Node Deployment Statistics (as of research session)
- 287 total manifests, 184 deployed
- Projects: SAGE (125), SGT (16), APIARY (15), DAWN (14), VTO (11), None (2), Wildebeest (1)

## Edge Scheduler
- Runs on each node as part of WES
- Central scheduler at `es.sagecontinuum.org`
- Jobs specify: plugin images, target nodes, science rules (cron expressions), success criteria (wall clock, data thresholds)
- Plugins run as k3s pods — isolated containers with resource limits

## Plugin Lifecycle
1. Develop locally (use `virtual-waggle` for testing)
2. Build Docker image (`pluginctl build`)
3. Register in ECR (`portal.sagecontinuum.org/apps`)
4. Submit job via `sesctl submit job.yaml`
5. Edge scheduler pulls image, runs on target nodes
6. Plugin publishes data via pywaggle → RabbitMQ → Beehive

## Data Flow
```
Sensor → Plugin (app.py) → pywaggle publish → WES data pipeline → RabbitMQ → Beehive
                                                                              ↓
                                                           Time-series DB + Object Store
                                                                              ↓
                                                           data.sagecontinuum.org API → Users
```

## Key Docker Base Images (waggle/plugin-base on Docker Hub)
| Tag | Use case | Size (approx) | Arch |
|-----|----------|---------------|------|
| `1.1.1-base` | Minimal Python, no ML | ~280MB | multi-arch (arm64+amd64) |
| `1.1.1-ml` | ML with CUDA | ~1.6GB arm64 / ~3.5GB amd64 | multi-arch |
| `1.1.1-ml-torch1.9.0` | PyTorch 1.9 | ~2.6GB arm64 / ~5.3GB amd64 | multi-arch |
| `1.1.1-ml-tensorflow2.3-arm64` | TensorFlow 2.3 | ~1.2GB | arm64 only |
| `1.1.1-ml-tensorflow2.3-amd64` | TensorFlow 2.3 | ~2.6GB | amd64 only |
| `1.1.1-ml-dev` | Dev/debug ML | ~1.6GB | arm64 |
| `1.0.0-ml-cuda10.2-l4t` | CUDA 10.2 L4T | varies | arm64 |
| `1.1.1-ros2-foxy` | ROS2 robotics | varies | varies |
