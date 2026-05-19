'use strict';

const { canonicalizeForHash, sha256Hex, sha256PrefixHex } = require('./canonical-json');

function capabilityVersionForNormalizedInput(input) {
  return sha256PrefixHex(canonicalizeForHash(input), 12);
}

function capabilityHashForNormalizedInput(input) {
  return sha256Hex(canonicalizeForHash(input));
}

function payloadHashForNormalizedInput(input) {
  return sha256Hex(canonicalizeForHash(input));
}

module.exports = {
  capabilityVersionForNormalizedInput,
  capabilityHashForNormalizedInput,
  payloadHashForNormalizedInput
};
