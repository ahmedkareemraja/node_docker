## NODE BASE IMAGE:NODE-VERSION-ALPINE (Verify from docker hub)
FROM node:24.21.0-alpine

## COPY EVERYTHING FROM CURRENT DIRECTORY TO WORKDIR
WORKDIR /app
COPY ./package.json .

RUN npm install

COPY . .

CMD ["npm", "run", "dev"]