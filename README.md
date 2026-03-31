# Shield Phalanx — Integration Test Suite

SHIELD Phalanx is a comprehensive integration test suite for the [SHIELD](https://github.com/shieldproject/shield) backup and restore platform. It tests backup/restore operations against multiple target databases.

## Targets Tested

- PostgreSQL (backup/restore all databases and single database)

- MariaDB/MySQL (backup/restore all databases and single database)

- MongoDB (backup/restore)

- Consul (backup/restore with and without TLS)

- etcd (backup/restore with and without TLS)

## Prerequisites

- Docker and Docker Compose (v2+)

## Quick Start (Docker)

1. Run the tests:
   ```bash
   cd docker/
   make test
   ```

   No credentials or `.env` file required — tests use a built-in RustFS
   container for S3-compatible storage.

   The `make build` step automatically clones SHIELD source from the `develop`
   branch. To use a different branch:
   ```bash
   SHIELD_BRANCH=main make test
   ```

   To test on Ubuntu Noble (24.04) instead of Jammy (22.04):
   ```bash
   UBUNTU_RELEASE=noble make test
   ```

   Or step by step:
   ```bash
   make build    # Build Docker images
   make up       # Start all services
   make shell    # Debug: open shell in test container
   make down     # Tear down
   ```

## Architecture

Phalanx deploys the following services in Docker containers:

| Service | Purpose | Image |
|---------|---------|-------|
| core | SHIELD daemon + Vault | Custom (built from source) |
| agent | SHIELD agent + backup plugins | Custom (built from source) |
| postgres | PostgreSQL 16 target | postgres:16-bookworm |
| mariadb | MariaDB 11.4 target | mariadb:11.4 |
| mongodb | MongoDB 7.0 target | mongo:7.0 |
| consul | Consul target | hashicorp/consul:1.22 |
| etcd | etcd target (no TLS) | quay.io/coreos/etcd:v3.6.9 |
| etcd-tls | etcd target (with TLS) | quay.io/coreos/etcd:v3.6.9 |
| rustfs | S3-compatible object store | rustfs/rustfs:latest |
| cert-init | TLS certificate generator | Custom (cfssl) |
| tests | Test runner (errand) | Custom |

## Test Flow

For each target database:

1. Initialize test data

2. Configure SHIELD target and backup job

3. Run backup job, verify archive created in S3

4. Verify backup archive is encrypted

5. Corrupt/destroy the data

6. Restore from backup

7. Verify restored data matches original

## BOSH Deployment (Legacy)

Phalanx is also a BOSH release that can be deployed via:

```bash
bosh create-release --force
bosh upload-release
bosh deploy ci/manifest.yml
bosh run-errand phalanx-tests
```

See `ci/manifest.yml` for the deployment manifest.

> **Note:** AWS S3 credentials are only required for BOSH-based testing
> (the `ci/manifest.yml` deployment). Docker-based tests use RustFS.

## Development

### Project Structure

```
docker/                    # Docker-based test infrastructure
  docker-compose.yml       # Service definitions
  Makefile                 # Build/test/clean targets
  images/                  # Dockerfiles and entrypoints
  configs/                 # Static configuration files

jobs/                      # BOSH jobs (legacy)
packages/                  # BOSH packages (legacy)
config/                    # BOSH release config (legacy)
ci/                        # CI scripts and manifests
```

## License

Shield is open source software.
