'use strict';

const Ping = require('../controllers/ping');

const Routes = {
  config: [
    { method: 'GET',  path: '/', config: { handler: Ping.show } }
  ]
};

module.exports = Routes;
