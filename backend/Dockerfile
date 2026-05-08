FROM node:20-alpine

# Dependencias de compilación para better-sqlite3
RUN apk add --no-cache python3 make g++

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./

# Carpeta de datos persistida via volumen
RUN mkdir -p /app/data

EXPOSE 3000

CMD ["node", "server.js"]
