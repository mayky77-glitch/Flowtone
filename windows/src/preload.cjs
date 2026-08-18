'use strict';

const { contextBridge, ipcRenderer } = require('electron');

function listener(channel, callback) {
  const wrapped = (_event, value) => callback(value);
  ipcRenderer.on(channel, wrapped);
  return () => ipcRenderer.removeListener(channel, wrapped);
}

contextBridge.exposeInMainWorld('flowtone', Object.freeze({
  bootstrap: () => ipcRenderer.invoke('bootstrap'),
  updateSettings: (patch) => ipcRenderer.invoke('settings:update', patch),
  refreshLibrary: () => ipcRenderer.invoke('library:refresh'),
  scratchPreview: (trackId, positionSeconds, direction) => ipcRenderer.invoke('audio:preview', trackId, positionSeconds, direction),
  markPlayed: (trackId) => ipcRenderer.invoke('library:mark-played', trackId),
  setLiked: (trackId, liked) => ipcRenderer.invoke('library:like', trackId, liked),
  deleteTrack: (trackId) => ipcRenderer.invoke('library:delete', trackId),
  cleanupLibrary: (protectedIds) => ipcRenderer.invoke('library:cleanup', protectedIds),
  pruneTransient: (protectedIds) => ipcRenderer.invoke('library:prune-transient', protectedIds),
  generateTrack: (settings) => ipcRenderer.invoke('generation:create', settings),
  cancelGeneration: () => ipcRenderer.invoke('generation:cancel'),
  acknowledgeTerms: () => ipcRenderer.invoke('model:acknowledge-terms'),
  modelStatus: () => ipcRenderer.invoke('model:status'),
  installModel: (modelId) => ipcRenderer.invoke('model:install', modelId),
  cancelModelInstallation: () => ipcRenderer.invoke('model:cancel-install'),
  uninstallModel: (modelId) => ipcRenderer.invoke('model:uninstall', modelId),
  uninstallAllModels: () => ipcRenderer.invoke('model:uninstall-all'),
  openExternal: (url) => ipcRenderer.invoke('external:open', url),
  setPlaybackState: (state) => ipcRenderer.send('playback:state', state),
  audioURL: (trackId) => `flowtone-audio://${encodeURIComponent(trackId)}`,
  onModelProgress: (callback) => listener('model-progress', callback),
  onRuntimeChanged: (callback) => listener('runtime-changed', callback),
  onWindowVisibility: (callback) => listener('window-visibility', callback),
  onSystemAction: (callback) => listener('system-action', callback),
  onSystemStatus: (callback) => listener('system-status', callback),
}));
