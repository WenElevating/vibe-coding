'use strict';

const productVersion = '1.3.0';
const apiVersion = 'agent-control.v1';
const schemaVersion = 5;

function versionInfo({ mode = 'dev' } = {}) {
  return {
    product: 'flutter-lan-ai-cli-control',
    daemonVersion: productVersion,
    apiVersion,
    schemaVersion,
    mode,
    minMobileVersion: '1.3.0',
    supportedMobileVersions: ['1.3.x'],
    releaseChannel: mode === 'release' ? 'local-release' : 'local-dev'
  };
}

module.exports = { productVersion, apiVersion, schemaVersion, versionInfo };
