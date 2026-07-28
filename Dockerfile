ARG ARCH=
ARG IMAGE_BASE=20-alpine

#FROM ${ARCH}node:$IMAGE_BASE
FROM solengeu.jfrog.io/joern-docker-remote/${ARCH}node:$IMAGE_BASE
LABEL Name="Node.js Demo App" Version=4.9.9
LABEL org.opencontainers.image.source="https://github.com/benc-uk/nodejs-demoapp"
ENV NODE_ENV=production
WORKDIR /app

# The application (source + node_modules) is built once in CI, uploaded to Artifactory
# (joern-generic-local) and downloaded back into the build context. ADD auto-extracts the
# gzipped tarball into /app, so there is no second `npm install` / compile step here.
ADD app.tar.gz ./

# Port 3000 for our Express server
EXPOSE 3000
ENTRYPOINT ["npm", "start"]