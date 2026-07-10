# Sage MCP Server Tools

Server: `https://mcp.sagecontinuum.org/mcp`
Auth: `Authorization: Bearer <token>` (from portal.sagecontinuum.org/account/access)

## Available Tools (30+)

### Data & Query
- Query sensor data by time range, node, measurement name
- Filter by VSN, plugin, sensor hardware
- Aggregate and summarize data streams

### Job Management
- Submit, monitor, cancel edge computing jobs
- View job status across nodes
- Inspect job logs and outputs

### Image Search
- Search camera images from edge nodes
- Filter by node, time range, camera position

### Plugin Discovery
- Browse Edge Code Repository (ECR)
- Search plugins by name, author, capability
- View plugin metadata and versions

### Node & Geo
- Look up node locations by VSN
- Query node hardware manifests
- Find nodes by geographic region or project

### Documentation
- Search Sage documentation
- Get quick-reference for APIs and tools

## Usage Pattern
The MCP server provides a convenient unified interface to most Sage platform capabilities. When available, prefer using MCP tools over raw API calls for complex multi-step workflows (e.g., "find nodes near Chicago with cameras, then query their recent images").

## Connection
Can be configured as a native MCP server in Hermes config (see native-mcp skill) or accessed via raw HTTP.
