'use strict';

const Hapi          = require('hapi');
const Routes        = require('./lib/routes/');

// Create a server with a host and port
const server = new Hapi.Server();

// Server config
server.connection({ port: 3000 });

// Add the routes
server.route(Routes.config);

// Start the server
server.start(() => {

  console.log('Server running at:', server.info.uri);
});

module.exports = server;

