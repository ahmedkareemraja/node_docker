## NODE BASE IMAGE:NODE-VERSION-ALPINE (Verify from docker hub)
FROM node:24.21.0-alpine

## COPY EVERYTHING FROM CURRENT DIRECTORY TO WORKDIR
WORKDIR /app
COPY ./ .

RUN npm install

CMD ["npm", "run", "dev"]