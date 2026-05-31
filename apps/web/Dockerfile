FROM node:20-alpine

WORKDIR /app

# Install production dependencies (cached unless package files change).
COPY package*.json ./
RUN npm install --omit=dev

COPY . .

ENV PORT=3000
EXPOSE 3000

# Drop privileges (the node image ships a non-root `node` user).
USER node

CMD ["node", "server.js"]
