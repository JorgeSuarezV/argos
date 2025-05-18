# Dockerfile
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
COPY package*.json ./
RUN npm install

# Copy app source
COPY simple-broadcast-server.js .

# Expose WebSocket port
EXPOSE 8080

# Run the server
CMD ["node", "simple-broadcast-server.js"]
