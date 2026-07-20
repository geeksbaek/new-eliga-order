FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ENV VITE_BASE=/
ENV VITE_USE_PROXY=true
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3456
COPY --from=build /app/dist ./dist
COPY server.mjs ./server.mjs
EXPOSE 3456
CMD ["node", "server.mjs"]
