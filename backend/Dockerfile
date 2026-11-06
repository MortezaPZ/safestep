# Build from the repository root so the backend and web dashboard are included.
FROM node:22-alpine

RUN apk add --no-cache tini

WORKDIR /app

COPY backend/package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund

COPY backend/src ./src
COPY backend/scripts/falls/generate_synthetic.js ./scripts/falls/generate_synthetic.js
COPY web /web

ENV NODE_ENV=production
ENV PORT=4080
ENV WEB_ROOT=/web
ENV DEMO_MODE=false
EXPOSE 4080

USER node

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/server.js"]
