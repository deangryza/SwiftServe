# Full image on purpose: it has the compiler that canvas falls back to when no
# prebuilt Linux binary can be downloaded.
FROM node:22-bookworm

RUN apt-get update \
  && apt-get install -y --no-install-recommends libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .
# Model weights are not committed; the server refuses to start without them.
RUN npm run models:download

ENV NODE_ENV=production
CMD ["node", "--use-system-ca", "server.js"]
