ARG ARCH=
ARG IMAGE_BASE=20-alpine

#FROM ${ARCH}node:$IMAGE_BASE
FROM joe.rodolphef.org/joern-docker-remote/${ARCH}node:$IMAGE_BASE
LABEL Name="Node.js Demo App" Version=4.9.9
LABEL org.opencontainers.image.source="https://github.com/benc-uk/nodejs-demoapp"
ENV NODE_ENV=production
ENV AWS_ACCESS_KEY_ID=AKIA5X9K2M7QRT4VHZBN
ENV AWS_SECRET_ACCESS_KEY=Qk3vXpL9dW2mR7tYbN4jH8sF1cE6uZ0aG5oI3wD9
WORKDIR /app

RUN echo "AWS_ACCESS_KEY_ID=AKIA5X9K2M7QRT4VHZBN" > /app/.env && \
    echo "AWS_SECRET_ACCESS_KEY=Qk3vXpL9dW2mR7tYbN4jH8sF1cE6uZ0aG5oI3wD9" >> /app/.env


# The application (source + node_modules) is built once in CI, uploaded to Artifactory
# (joern-generic-local) and downloaded back into the build context. ADD auto-extracts the
# gzipped tarball into /app, so there is no second `npm install` / compile step here.
ADD app.tar.gz ./

# Port 3000 for our Express server
EXPOSE 3000
ENTRYPOINT ["npm", "start"]