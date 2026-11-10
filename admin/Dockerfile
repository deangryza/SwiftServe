FROM node:22-bookworm-slim AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

# Vite bakes these into the bundle, so Railway must pass them at build time.
ARG VITE_API_BASE_URL
ARG VITE_FIREBASE_API_KEY
ARG VITE_FIREBASE_AUTH_DOMAIN
ARG VITE_FIREBASE_PROJECT_ID
ARG VITE_FIREBASE_STORAGE_BUCKET
ARG VITE_FIREBASE_MESSAGING_SENDER_ID
ARG VITE_FIREBASE_APP_ID

RUN npm run build

FROM node:22-bookworm-slim

WORKDIR /app
RUN npm install -g serve@14.2.4
COPY --from=build /app/dist ./dist

# -s sends unknown paths to index.html so React Router links survive a refresh.
CMD serve -s dist -l $PORT
