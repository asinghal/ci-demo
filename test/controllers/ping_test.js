'use strict';

const Code             = require('code');
const Lab              = require('lab');
const lab              = exports.lab = Lab.script();
const { describe, it } = lab;
const { expect }       = Code;

const Server  = require('../../');

describe('ping', () => {

  const options = {
    method: 'GET',
    url: '/'
  };

  it('response with success in case of valid token', (done) => {

    Server.inject(options, (response) => {

      const result = response.result;

      expect(response.statusCode).to.equal(200);
      expect(result).to.be.instanceof(Object);

      done();
    });
  });
});

