'use strict';

const path = require('node:path');
const { spawnSync } = require('node:child_process');

function shouldReplaceInstalledFlowtone(platform, isPackaged, executablePath) {
  return platform === 'win32' && !isPackaged
    && path.basename(String(executablePath || '')).toLowerCase() !== 'flowtone.exe';
}

function terminateInstalledFlowtone({
  platform = process.platform,
  isPackaged = false,
  executablePath = process.execPath,
  run = spawnSync,
} = {}) {
  if (!shouldReplaceInstalledFlowtone(platform, isPackaged, executablePath)) return false;
  const result = run('taskkill.exe', ['/IM', 'Flowtone.exe', '/T', '/F'], {
    windowsHide: true,
    encoding: 'utf8',
    timeout: 5000,
  });
  return result.status === 0;
}

module.exports = { shouldReplaceInstalledFlowtone, terminateInstalledFlowtone };
