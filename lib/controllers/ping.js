'use strict';

class Ping {

  show(request, response) {

    response({ message: 'ok' });
  }

}

module.exports = new Ping();

