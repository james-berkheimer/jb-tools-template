# JB Tools Template

Template for building lightweight LXC and Docker containers designed to run Python utility applications.

## Structure

- `lxc/` — Scripts and environment template for creating LXC containers.
- `docker/` — Dockerfile and scripts for building Docker containers (coming soon).
- `common/` — Shared helper scripts (optional for future use).

## Quick Start (LXC)

1. Copy `lxc/env-template` to `lxc/env` and edit your environment settings.
2. Run the LXC create script:

```bash
cd lxc
sudo ./create.sh
```
