# How to run an untrusted React/Node.js project via Docker

This guide describes a **safe, repeatable process** for running React +
Node.js projects from *untrusted or unknown sources* using Docker, so
that:

-   Node scripts and `postinstall` hooks run **inside an isolated
    container**, not on your host.
-   The project does **not** get access to your home directory, SSH
    keys, or other sensitive files.
-   You can still build and run the app, and even use a dev setup with
    hot reload, without sacrificing safety.

The examples below are written for projects using **pnpm** and **Node
22** on **Windows + Docker Desktop**, but the same ideas work on macOS /
Linux with small path adjustments.

------------------------------------------------------------------------

## 1. Threat model (what we are protecting against)

When you run:

-   `pnpm install` / `npm install`
-   `pnpm dev` / `npm run dev`
-   other scripts from `package.json`

you are allowing arbitrary JavaScript to run on your machine with the
permissions of your user account. A malicious dependency or script can:

-   read/write files in your home directory,
-   exfiltrate tokens/keys/configs over the network,
-   run arbitrary OS-level commands.

**Goal:** make sure all of that executes inside a **Docker container**,
with access only to the project directory and nothing else. Your browser
access is also limited via a dedicated, "sandboxed" browser profile.

------------------------------------------------------------------------

## 2. Prerequisites

### 2.1. Tools

-   Docker Desktop installed and running.
-   Git (optional, but common in real projects).
-   A browser that supports multiple profiles (Chrome, Edge, Firefox,
    etc.).

### 2.2. Project layout assumptions

We assume this (or similar) project structure:

-   `package.json` + `pnpm-lock.yaml`
-   a `build` script in `package.json` that:
    -   runs `vite build` (or similar) for the client,
    -   builds a Node.js server entry point to something like
        `dist/index.js`.

You can adapt the steps for npm/yarn if needed, but the examples here
assume `pnpm`.

------------------------------------------------------------------------

## 3. One-time: create a production Dockerfile

In the root of the project, create a file named `Dockerfile` with:

``` dockerfile
# 1) Build stage: install deps and build the app inside an isolated container
FROM node:22-alpine AS build

# Enable pnpm via Corepack (official way to use pnpm without global install)
RUN corepack enable

# Workdir inside the container
WORKDIR /app

# Copy only dependency manifests first (leverages Docker layer cache)
COPY package.json pnpm-lock.yaml ./

# Copy patches, so pnpm will be able to apply them
COPY patches ./patches

# Install dependencies strictly from the lockfile
# (any postinstall scripts will run INSIDE the container, not on your host)
RUN pnpm install --frozen-lockfile

# Now copy the rest of the project files
COPY . .

# Build both frontend (Vite) and backend bundle (as defined in package.json "build" script)
RUN pnpm build


# 2) Runtime stage: a small, production-only image to run the server
FROM node:22-alpine

# Workdir for the runtime container
WORKDIR /app

# Create a non-privileged user to run the app
RUN adduser -D appuser
USER appuser

# Copy build artifacts and any runtime files from the builder stage
COPY --from=build /app /app

# Production mode for Node.js
ENV NODE_ENV=production

# Expose the server port (adjust to your app’s actual port if different)
# Common choices are 3000 or 8080; this Dockerfile assumes 3000.
EXPOSE 3000

# Start the Node server (entrypoint compiled by your build script)
CMD ["node", "dist/index.js"]
```

**Security note:** all postinstall scripts run inside Docker.

------------------------------------------------------------------------

## 4. (Optionally) One-time: create .dockerignore

Usually docker is trying to package the entire project directory (including `node_modules`) into the build context and can encounters some kind of unreadable or broken binary/special file inside some directory not related fo sources. Let's restrict Docker accessing to the following directories/files.

`node_modules` and other miscellaneous directories should not be in the Docker build context.

``` dockerignore
node_modules
.pnpm-store
.git
.gitignore
.vscode
.idea
npm-debug.log*
yarn-error.log*
pnpm-lock.yaml.backup
dist
build
.tmp
*.log
```

### 4.1 Delete existing node_modules before the first build

Completely **delete `node_modules` directory** before the first build. Dangerous/malicious files can be inside of the `node_modules`. Let's rebuild them from scratch later. (In the Docker environment.)

------------------------------------------------------------------------

## 5. Optional: env file with safe values

Create a file such as `env.local-dev`:

    OAUTH_SERVER_URL=http://localhost:4000
    VITE_APP_TITLE=Untrusted App (local dev)
    VITE_APP_LOGO=/logo.png

    VITE_ANALYTICS_ENDPOINT=/analytics
    VITE_ANALYTICS_WEBSITE_ID=local-dev

    VITE_OAUTH_PORTAL_URL=http://localhost:4000
    VITE_APP_ID=local-dev-app

Rules:

-   Values must be valid, but **not real credentials**.
-   Avoid pointing to real external services.

------------------------------------------------------------------------

## 6. Build & run the project safely

### 6.1 Build the Docker image

``` bash
docker build -t untrusted-app .
```

### 6.2 Run the container

``` bash
docker run --rm   -p 3000:3000   --security-opt=no-new-privileges   --name untrusted-app   untrusted-app
```

With env:

``` bash
docker run --rm   -p 3000:3000   --security-opt=no-new-privileges   --env-file env.local-dev   --name untrusted-app   untrusted-app
```

💡 The running app will appear in your Docker Desktop
<img width="3647" height="865" alt="image" src="https://github.com/user-attachments/assets/a9701f68-e734-42b8-aef7-84f3d0c53b00" />

------------------------------------------------------------------------

## 7. Use a dedicated sandboxed browser profile

-   Create a new browser profile: **Untrusted Apps**.
-   Do **not** sign in.
-   Disable password storage.
-   Do not log into important services.
-   Use only test/demo credentials.

Do not sign in with your dedicated “untrusted” profile.

<img style="max-width: 742; height: 1140px; height: 500px;" alt="image" src="https://github.com/user-attachments/assets/a9b44446-c96d-4289-b06a-76bf2ba231fc" />

Open (only using your dedicated “untrusted” browser profile):

    http://localhost:3000

------------------------------------------------------------------------

## 8. Opening the project in VS Code safely

-   Open the folder.
-   When asked "Do you trust the authors?", choose **No** → Restricted
    Mode.
-   Avoid running npm/pnpm/node on host.
-   All scripts should run only in Docker.

------------------------------------------------------------------------

## 9. Optional: development mode with hot reload

### 9.1 Dev Dockerfile

Create `Dockerfile.dev`:

``` dockerfile
FROM node:22-alpine
WORKDIR /app

RUN corepack enable

COPY package.json pnpm-lock.yaml ./
COPY patches ./patches 2>/dev/null || true

RUN pnpm install --frozen-lockfile

ENV NODE_ENV=development

CMD ["pnpm", "dev"]
```

Build:

``` bash
docker build -f Dockerfile.dev -t untrusted-app-dev .
```

### 9.2 Install dependencies into bind-mounted project

``` bash
docker run --rm -it   --security-opt=no-new-privileges   --env-file env.local-dev   -v D:\path\to\project:/app   untrusted-app-dev sh
```

Inside:

    cd /app
    pnpm install --frozen-lockfile
    exit

### 9.3 Dev scripts

``` json
"scripts": {
  "dev:server": "NODE_ENV=development tsx watch server/_core/index.ts",
  "dev:client": "vite --host 0.0.0.0 --port 5173",
  "dev:full": "concurrently -n server,client "pnpm:dev:server" "pnpm:dev:client""
}
```

### 9.4 Run dev mode with hot reload

``` bash
docker run --rm   -p 3000:3000   -p 5173:5173   --security-opt=no-new-privileges   --env-file env.local-dev   -e CHOKIDAR_USEPOLLING=1   -e WATCHPACK_POLLING=true   -v D:\path\to\project:/app   untrusted-app-dev pnpm dev:full
```

Open (in special user profile):

    http://localhost:5173

------------------------------------------------------------------------

## 10. Summary

-   Never run install or dev scripts from untrusted projects on your
    host.
-   Use Docker for installation, build, prod, and dev.
-   Restrict container access; never mount your home directory.
-   Use a sandbox browser profile.
-   Use VS Code in Restricted Mode for such projects.
