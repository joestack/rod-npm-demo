# myapp-image — Docker Quick Start

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Access credentials for `solengeu.jfrog.io` (username + API key)

---

## 1. Login to Artifactory

```bash
docker login solengeu.jfrog.io -u <username> -p <api-key>
```

> **Tip:** Use your JFrog API key instead of your password. Generate one in JFrog → User Profile → API Key.

---

## 2. Pull the Image

```bash
docker pull solengeu.jfrog.io/joern-docker-local/myapp-image:17
```

To check which tags are available:

```bash
curl -u <username>:<api-key> \
  https://solengeu.jfrog.io/artifactory/api/docker/joern-docker-local/v2/myapp-image/tags/list
```

---

## 3. Run the Image

**Basic run:**
```bash
docker run solengeu.jfrog.io/joern-docker-local/myapp-image:17
```

**Run in the background with a port mapping:**
```bash
docker run -d \
  --name myapp \
  -p 3000:3000 \
  solengeu.jfrog.io/joern-docker-local/myapp-image:17
```

**Run with environment variables:**
```bash
docker run -d \
  --name myapp \
  -p 3000:3000 \
  -e ENV_VAR=value \
  solengeu.jfrog.io/joern-docker-local/myapp-image:17
```

**Run with a volume mount:**
```bash
docker run -d \
  --name myapp \
  -p 3000:3000 \
  -v /host/path:/container/path \
  solengeu.jfrog.io/joern-docker-local/myapp-image:17
```

---

## 4. Manage the Container

```bash
docker ps               # list running containers
docker logs myapp       # view container logs
docker stop myapp       # stop the container
docker rm myapp         # remove the container
```

---

## Common Options Reference

| Option | Description |
|--------|-------------|
| `-d` | Run in background (detached) |
| `-it` | Run interactively with a terminal |
| `--name <name>` | Assign a name to the container |
| `-p <host>:<container>` | Map a port |
| `-e KEY=VALUE` | Set an environment variable |
| `-v <host>:<container>` | Mount a volume |
