FROM node:18

WORKDIR /app

# Copy package files first for caching
COPY package*.json ./
RUN npm install

# Copy application code
COPY . .

# Expose port inside container
EXPOSE 8080

# Health check (optional, ensures container is ready)
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=5 \
  CMD curl -f http://localhost:8080/ || exit 1

# Start the app
CMD ["npm", "start"]
