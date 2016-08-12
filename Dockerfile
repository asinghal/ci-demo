FROM node:6

RUN mkdir /app
WORKDIR /app

COPY package.json /app/

RUN npm install --production

ADD . /app

EXPOSE 3000
CMD ["node", "index.js"]

