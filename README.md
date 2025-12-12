# How to Safely Run an Untrusted React/Node.js Project Using Docker

This guide describes a **safe, repeatable workflow** for running React + Node.js projects from *untrusted or unknown sources* using Docker.  
All Node.js scripts (including `postinstall`) will run **inside Docker** (isolated container), not on your host machine.

Key goals:
- Prevent untrusted code from accessing your home directory, SSH keys, or sensitive files.
- Preserve isolation while still supporting development workflows like **hot reload**.
- Provide a documented workflow suitable for teams working on Windows/macOS/Linux.

---

## 1. Threat Model: What We Are Protecting Against

Running commands such as:

- `pnpm install` / `npm install`
- `pnpm dev` / `npm run dev`
- anything inside `package.json` scripts

executes arbitrary JavaScript with your user account privileges.  
A malicious dependency may:

- read/write any user-accessible files,
- leak credentials or tokens,
- run arbitrary OS commands.

**Solution:** run all dependency installation, builds, and dev servers inside **isolated Docker containers**.

Your browser access is also sandboxed through a dedicated browser profile.

---

## 2. Prerequisites

### 2.1 Required Tools

- Docker Desktop
- (Optional) Git
- A browser supporting multiple profiles (Chrome/Edge/Firefox)

### 2.2 Expected Project Layout

We assume:

- `package.json` + `pnpm-lock.yaml`
- A `build` script that:
  - runs `vite build` (or similar),
  - compiles a Node.js server to `dist/index.js`.

Examples use **pnpm**, but the logic is the same for npm/yarn.

---

## 3. Production Dockerfile (One-Time Setup)

> For development with hot reload, see **Section 9**.

Create a file named `Dockerfile`:

```dockerfile
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

# Install deps inside Docker (safe)
RUN pnpm install --frozen-lockfile

# Copy rest of the project
COPY . .

# Build frontend & backend
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

**Security:** all installation scripts run inside an isolated container.

---

## 4. `.dockerignore` (Recommended)

Prevents Docker from copying unnecessary or unsafe files:

```dockerignore
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

### 4.1 Delete Local `node_modules`
Remove `node_modules` before the first Docker build.  
They will be recreated inside Docker.

---

## 5. Environment Variables

Create `env.local-dev` with **safe, non-sensitive values**:

```
OAUTH_SERVER_URL=http://localhost:4000
VITE_APP_TITLE=Untrusted App (local dev)
VITE_APP_LOGO=/logo.png

VITE_ANALYTICS_ENDPOINT=/analytics
VITE_ANALYTICS_WEBSITE_ID=local-dev

VITE_OAUTH_PORTAL_URL=http://localhost:4000
VITE_APP_ID=local-dev-app
```

⚠️ Use variables **actually used by your project**.  
Do **not** put real credentials in this file.

---

## 6. Build & Run the App Safely

Change `untrusted-app` to the name of your real app.

### 6.1 Build

```bash
docker build -t untrusted-app .
```

### 6.2 Run

```bash
docker run --rm   -p 3000:3000   --security-opt=no-new-privileges   --name untrusted-app   untrusted-app
```

With env file:

```bash
docker run --rm   -p 3000:3000   --security-opt=no-new-privileges   --env-file env.local-dev   --name untrusted-app   untrusted-app
```
ATTN! `untrusted-app` is the name of container. And the image name is also `untrusted-app`.
You may skip specifying `--name [container-name]`, so the Docker will assign random name for the container.

💡 The running app will appear in your Docker Desktop
<img width="3647" height="865" alt="image" src="https://github.com/user-attachments/assets/a9701f68-e734-42b8-aef7-84f3d0c53b00" />

### 6.3 Stop (when you finish working with app)

```bash
docker stop untrusted-app
```
Or other container name. Please check out the exact app name in the list of running containers of Docker Desktop.

---

## 7. Use a Dedicated “Untrusted Apps” Browser Profile

- Create a new browser profile: **Untrusted Apps**.
- **Do not sign in.**
- Disable password storage.
- Do not log into important services.
- Use only test/demo credentials.

**Do not sign in** with your dedicated “untrusted” profile. Let it displaying “sign in” button.

<img style="max-width: 742; height: 1140px; height: 500px;" alt="image" src="https://github.com/user-attachments/assets/a9b44446-c96d-4289-b06a-76bf2ba231fc" />

Open (only using your dedicated “untrusted” browser profile):
```
http://localhost:3000
```

If errors appear, they likely relate to app configuration, not Docker.
Maybe because `.env` file (with environment variables) has not found (in this case re-read previous steps,
particularly [how to point environment variables to the Docker](#5-optional-env-file-with-safe-values)).

---

## 8. Opening the Project in VS Code (Safely)

- Open the folder.
- When asked “Do you trust the authors?” → **No** → Restricted Mode.
- Avoid running pnpm/npm/node on the host.
- Use Docker for all commands.

---

## 9. Optional: Development Mode with Hot Reload

### 9.1 Dev Dockerfile

Create `Dockerfile.dev`:

```dockerfile
FROM node:22-alpine
WORKDIR /app

# Enable pnpm via corepack
RUN corepack enable

# Copy only package.json + lock + patches
COPY package.json pnpm-lock.yaml ./
COPY patches ./patches

# Install deps once during image build
RUN pnpm install --frozen-lockfile

# NO COPY! To let it be rebuilt on the fly on any changes.
# COPY . .

ENV NODE_ENV=development

# This is example. Change if your dev server listens another port.
# Backend (Express / tsx) typically: 3000
# Frontend (Vite dev server) typically: 5173
EXPOSE 3000 5173

# Run the commands
CMD ["pnpm", "dev"]
```

Build:

``` bash
docker build -f Dockerfile.dev -t untrusted-app-dev .
```

### 9.2 Install Dependencies into the Mounted Project Directory

Your `node_modules` should live **on the host filesystem**,  
but should be **installed from inside Docker** (safe).

⚠️ Replace `D:\path\to\project` to the path to your app in the following command!

```bash
docker run --rm -it   --security-opt=no-new-privileges   --env-file env.local-dev   -v D:\path\to\project:/app   untrusted-app-dev sh
```

Inside the container type and submit line by line. `ls` is just to make sure that `package.json` is present in the `/app` directory.

```
cd /app
ls -la
pnpm install --frozen-lockfile
pnpm add -D concurrently
exit
```

### 9.3 Update `package.json` Dev Scripts

Open `package.json` and add to the "scripts" section the following modes:

```json
"scripts": {
  "dev:server": "NODE_ENV=development tsx watch server/_core/index.ts",
  "dev:client": "vite --host 0.0.0.0 --port 5173",
  "dev:full": "concurrently -n server,client \"pnpm:dev:server\" \"pnpm:dev:client\""
}
```


### 9.4 Run Dev Mode (with hot reload)

⚠️ Replace `D:\path\to\project` to the path to your app in the following command!

```bash
docker run --rm   -p 3000:3000   -p 5173:5173   --security-opt=no-new-privileges   --env-file env.local-dev   -e CHOKIDAR_USEPOLLING=1   -e WATCHPACK_POLLING=true   -v D:\path\to\project:/app   --name untrusted-app-dev   untrusted-app-dev pnpm dev:full
```

### 9.5 Open the App in Dev Mode (only in special user profile of your browser)

After running the dev container, you can open two ports, but they behave differently:

Primary entry point (recommended):

```
http://localhost:3000
```

This is the full application (frontend + backend API).
Most real behavior, including API calls and error messages, will appear here.
Use this for testing, verification, demos, and realistic debugging.

Optional Vite dev server (frontend-only):

```
http://localhost:5173
```

This is the raw Vite HMR server, useful only for frontend-development workflows.
Because it does not proxy API requests, it may show errors like:
```
404 /api/...
Unexpected token '<'
failed JSON parsing
```
These are normal for Vite when the API lives on a different port.

If in doubt — always use port 3000:

```
http://localhost:3000
```

---

## 10. Summary

- **Never** run install/build/dev scripts from untrusted projects on your host.
- **Use Docker for everything**: install → build → prod → dev.
- Never mount your home directory into a container.
- Use a sandbox browser profile.
- Use VS Code in Restricted Mode.
