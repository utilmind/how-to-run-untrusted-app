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
