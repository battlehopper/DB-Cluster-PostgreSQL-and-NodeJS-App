FROM node:20-alpine

ARG DD_SERVICE=movida-reservas-api
ARG DD_VERSION=1.0.0

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

ENV NODE_ENV=production
ENV DD_SERVICE=${DD_SERVICE}
ENV DD_VERSION=${DD_VERSION}

LABEL com.datadoghq.tags.service="${DD_SERVICE}"
LABEL com.datadoghq.tags.version="${DD_VERSION}"

EXPOSE 3000

CMD ["node", "src/server.js"]
