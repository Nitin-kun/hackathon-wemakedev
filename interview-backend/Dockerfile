FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

RUN mkdir -p /app/uploads

EXPOSE 7880

CMD ["node", "src/server.js"]
