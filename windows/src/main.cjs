'use strict';

const { app, BrowserWindow, ipcMain, nativeImage, net, powerMonitor, protocol, shell } = require('electron');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { TrackLibrary } = require('./library.cjs');
const { GENRES, GENRE_LABELS, composePrompt, createStationConfiguration } = require('./core.cjs');
const { MODEL_PROFILES, StableAudioRuntime, basicHardwareProfile } = require('./runtime.cjs');

app.setName('Flowtone');
if (!app.isPackaged && process.env.FLOWTONE_USER_DATA) {
  const override = path.resolve(process.env.FLOWTONE_USER_DATA);
  if (override !== path.parse(override).root && override !== os.homedir()) app.setPath('userData', override);
}
if (process.platform === 'win32') app.setAppUserModelId('ru.flowtone.app');
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

protocol.registerSchemesAsPrivileged([{ scheme: 'flowtone-audio', privileges: { secure: true, standard: true, stream: true, supportFetchAPI: true } }]);

const singleInstance = app.requestSingleInstanceLock();
if (!singleInstance) app.quit();

let mainWindow = null;
let library = null;
let runtime = null;
let hardware = basicHardwareProfile();
let settings = null;
let memoryTimer = null;
let generationCursor = 0;

const DEFAULT_SETTINGS = {
  schema: 1,
  selectedGenres: ['Ambient', 'Lo-fi'],
  mixGenresEnabled: false,
  storageMode: 'recording',
  shuffleEnabled: true,
  energy: 'calm',
  mood: 'focused',
  vibe: '',
  generationEnabled: true,
  modelPreference: 'auto',
  volume: 0.72,
  storageLimitGiB: 5,
  termsAcknowledged: false,
};

function supportRoot() { return app.getPath('userData'); }
function settingsPath() { return path.join(supportRoot(), 'settings-v1.json'); }

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1080,
    height: 720,
    minWidth: 960,
    minHeight: 640,
    show: false,
    backgroundColor: '#130d0b',
    icon: path.join(__dirname, '..', 'resources', 'AppIcon.png'),
    title: 'Flowtone',
    titleBarStyle: process.platform === 'win32' ? 'hidden' : 'hiddenInset',
    titleBarOverlay: process.platform === 'win32' ? { color: '#1b110d', symbolColor: '#efd8b8', height: 32 } : false,
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      backgroundThrottling: true,
      spellcheck: false,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isAllowedExternalURL(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (url !== mainWindow.webContents.getURL()) event.preventDefault();
  });
  mainWindow.on('show', () => mainWindow.webContents.send('window-visibility', true));
  mainWindow.on('hide', () => mainWindow.webContents.send('window-visibility', false));
  mainWindow.on('minimize', () => mainWindow.webContents.send('window-visibility', false));
  mainWindow.on('restore', () => mainWindow.webContents.send('window-visibility', true));
  mainWindow.on('focus', () => mainWindow.webContents.send('window-visibility', true));
  mainWindow.on('closed', () => { mainWindow = null; });
  mainWindow.webContents.once('did-finish-load', () => {
    updateThumbarButtons(false);
    mainWindow.show();
  });
  await mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

async function initialize() {
  await fsp.mkdir(supportRoot(), { recursive: true });
  settings = await readSettings();
  library = new TrackLibrary(path.join(supportRoot(), 'Library'));
  await library.load();
  hardware = await probeHardware();
  runtime = new StableAudioRuntime(supportRoot(), (progress) => {
    if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('model-progress', progress);
  });
  await runtime.initialize(hardware);

  protocol.handle('flowtone-audio', async (request) => {
    try {
      const id = decodeURIComponent(new URL(request.url).hostname || new URL(request.url).pathname.replace(/^\//, ''));
      if (!/^[0-9a-f-]{36}$/i.test(id)) return new Response('Invalid track', { status: 400 });
      const audioPath = library.audioPath(id);
      return net.fetch(pathToFileURL(audioPath).toString());
    } catch {
      return new Response('Track not found', { status: 404 });
    }
  });

  registerIPC();
  registerPowerEvents();
  await createWindow();
}

function registerIPC() {
  ipcMain.handle('bootstrap', async () => snapshot());
  ipcMain.handle('settings:update', async (_event, patch) => {
    settings = sanitizeSettings({ ...settings, ...patch });
    await writeSettings();
    return { settings, runtime: await runtime.status(settings.modelPreference) };
  });
  ipcMain.handle('library:refresh', async () => librarySnapshot());
  ipcMain.handle('audio:preview', async (_event, trackId, positionSeconds, direction) =>
    library.wavePreview(String(trackId), Math.min(Math.max(Number(positionSeconds) || 0, 0), 120), Number(direction) < 0 ? -1 : 1));
  ipcMain.handle('library:mark-played', async (_event, trackId) => {
    await library.markPlayed(trackId);
    return librarySnapshot();
  });
  ipcMain.handle('library:like', async (_event, trackId, liked) => {
    await library.setLiked(trackId, liked);
    if (settings.storageMode === 'live') await library.removeUnlikedTransient([]);
    return librarySnapshot();
  });
  ipcMain.handle('library:delete', async (_event, trackId) => {
    await library.removeTrack(trackId);
    return librarySnapshot();
  });
  ipcMain.handle('library:cleanup', async (_event, protectedIds) => {
    const report = await library.removeAllUnliked(Array.isArray(protectedIds) ? protectedIds : []);
    return { report, ...librarySnapshot() };
  });
  ipcMain.handle('library:prune-transient', async (_event, protectedIds) => {
    const report = await library.removeUnlikedTransient(Array.isArray(protectedIds) ? protectedIds : []);
    return { report, ...librarySnapshot() };
  });
  ipcMain.handle('generation:create', async (_event, rawSettings) => createTrack(rawSettings));
  ipcMain.handle('generation:cancel', async () => { runtime.cancel(); return true; });
  ipcMain.handle('model:acknowledge-terms', async () => {
    settings.termsAcknowledged = true;
    await writeSettings();
    return true;
  });
  ipcMain.handle('model:status', async () => runtime.status(settings.modelPreference));
  ipcMain.handle('model:install', async (_event, modelId) => {
    if (!settings.termsAcknowledged) throw new Error('Сначала откройте и прочитайте официальные условия.');
    const status = await runtime.installModel(modelId);
    mainWindow?.webContents.send('runtime-changed', status);
    return status;
  });
  ipcMain.handle('model:uninstall', async (_event, modelId) => {
    const status = await runtime.uninstallModel(modelId);
    mainWindow?.webContents.send('runtime-changed', status);
    return status;
  });
  ipcMain.handle('model:uninstall-all', async () => {
    const status = await runtime.uninstallAllModels();
    mainWindow?.webContents.send('runtime-changed', status);
    return status;
  });
  ipcMain.handle('external:open', async (_event, url) => {
    if (!isAllowedExternalURL(url)) throw new Error('Ссылка заблокирована.');
    await shell.openExternal(url);
    return true;
  });
  ipcMain.on('playback:state', (_event, state) => updateThumbarButtons(Boolean(state?.isPlaying)));
}

async function snapshot() {
  return {
    app: { version: app.getVersion(), platform: process.platform },
    settings,
    genres: GENRES,
    genreLabels: GENRE_LABELS,
    hardware,
    runtime: await runtime.status(settings.modelPreference),
    ...librarySnapshot(),
  };
}

function librarySnapshot() {
  return { tracks: library.allTracks(), statistics: library.statistics() };
}

async function createTrack(rawSettings) {
  const runtimeStatus = await runtime.status(settings.modelPreference);
  if (!settings.generationEnabled) throw new Error('Локальная генерация выключена.');
  if (!runtimeStatus.connectedModel) throw new Error('Сначала установите рекомендованную модель.');
  const stationSettings = sanitizeSettings({ ...settings, ...rawSettings });
  if (!stationSettings.mixGenresEnabled) {
    const selected = new Set(stationSettings.selectedGenres);
    const cycle = selected.size ? GENRES.filter((genre) => selected.has(genre)) : GENRES;
    stationSettings.selectedGenres = [cycle[generationCursor % cycle.length]];
    generationCursor = (generationCursor + 1) % cycle.length;
  }
  const station = createStationConfiguration(stationSettings);
  const stats = library.statistics();
  const estimatedBytes = 120 * 44100 * 2 * 2 + 44;
  const limit = settings.storageLimitGiB * 1024 ** 3;
  if (stats.byteSize + estimatedBytes > limit) {
    throw new Error('Хранилище Flowtone заполнено. Удалите часть архива или увеличьте лимит.');
  }
  const outputPath = path.join(library.incomingDirectory, `flowtone-${station.seed}.wav`);
  await runtime.generate({
    modelId: runtimeStatus.connectedModel,
    prompt: composePrompt(station),
    negativePrompt: 'vocals, singing, spoken word, speech, advertisement, audio logo, harsh clipping, long silence',
    durationSeconds: 120,
    seed: station.seed,
    outputPath,
  });
  const activeProfile = runtimeStatus.models.find((model) => model.id === runtimeStatus.connectedModel);
  const track = await library.importGeneratedAudio(outputPath, station, {
    durationSeconds: 120,
    engineID: activeProfile?.family === 'ace-step'
      ? `ace-step-1.5-${runtimeStatus.connectedModel}`
      : `stable-audio-3-tflite-${runtimeStatus.connectedModel}`,
    isTransient: settings.storageMode === 'live',
  });
  return { track, station, runtime: await runtime.status(settings.modelPreference), ...librarySnapshot() };
}

function registerPowerEvents() {
  powerMonitor.on('suspend', () => {
    runtime?.cancel();
    mainWindow?.webContents.send('system-status', { kind: 'suspend', message: 'Генерация остановлена: Windows переходит в сон.' });
  });
  powerMonitor.on('resume', () => mainWindow?.webContents.send('system-status', { kind: 'resume' }));
  memoryTimer = setInterval(() => {
    if (os.freemem() < 768 * 1024 ** 2 && runtime?.generating) {
      runtime.cancel();
      mainWindow?.webContents.send('system-status', { kind: 'memory-pressure', message: 'Генерация остановлена: Windows срочно нужна память.' });
    }
  }, 5000);
  memoryTimer.unref();
}

async function probeHardware() {
  const profile = basicHardwareProfile();
  if (process.platform !== 'win32') return profile;
  try {
    const output = await capture('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      'Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM,DriverVersion | ConvertTo-Json -Compress']);
    const parsed = JSON.parse(output.trim());
    const adapters = (Array.isArray(parsed) ? parsed : [parsed]).filter(Boolean);
    if (adapters.length) {
      profile.gpu = adapters.map((item) => item.Name).filter(Boolean).join(' + ');
      profile.gpuMemoryGiB = Math.max(...adapters.map((item) => Math.round((Number(item.AdapterRAM) || 0) / 1024 ** 3)), 0);
    }
  } catch {}
  try {
    const output = await capture('nvidia-smi.exe', ['--query-gpu=name,memory.total,driver_version', '--format=csv,noheader,nounits']);
    const [name, memory, driver] = output.trim().split(',').map((value) => value.trim());
    if (name) profile.gpu = name;
    if (memory) profile.gpuMemoryGiB = Math.round(Number(memory) / 1024);
    profile.nvidiaDriver = driver || null;
  } catch {}
  try {
    const gpuInfo = await app.getGPUInfo('basic');
    profile.gpuDevices = Array.isArray(gpuInfo?.gpuDevice) ? gpuInfo.gpuDevice.length : undefined;
  } catch {}
  return profile;
}

function capture(executable, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.once('error', reject);
    child.once('exit', (code) => code === 0 ? resolve(stdout) : reject(new Error(`exit ${code}`)));
  });
}

async function readSettings() {
  try {
    return sanitizeSettings({ ...DEFAULT_SETTINGS, ...JSON.parse(await fsp.readFile(settingsPath(), 'utf8')) });
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

async function writeSettings() {
  const temporary = `${settingsPath()}.${process.pid}.tmp`;
  await fsp.writeFile(temporary, `${JSON.stringify(settings, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
  await fsp.rename(temporary, settingsPath());
}

function sanitizeSettings(value) {
  const selectedGenres = Array.isArray(value.selectedGenres)
    ? [...new Set(value.selectedGenres.filter((genre) => GENRES.includes(genre)))] : DEFAULT_SETTINGS.selectedGenres;
  return {
    schema: 1,
    selectedGenres,
    mixGenresEnabled: Boolean(value.mixGenresEnabled) && (selectedGenres.length === 0 || selectedGenres.length >= 2),
    storageMode: value.storageMode === 'live' ? 'live' : 'recording',
    shuffleEnabled: value.shuffleEnabled !== false,
    energy: ['calm', 'balanced', 'driving'].includes(value.energy) ? value.energy : 'calm',
    mood: ['focused', 'warm', 'dreamy', 'dark', 'uplifting'].includes(value.mood) ? value.mood : 'focused',
    vibe: String(value.vibe || '').replace(/[\r\n\t]+/g, ' ').slice(0, 180),
    generationEnabled: value.generationEnabled !== false,
    modelPreference: ['auto', ...Object.keys(MODEL_PROFILES)].includes(value.modelPreference)
      ? value.modelPreference : 'auto',
    volume: Math.min(Math.max(Number(value.volume) || 0, 0), 1),
    storageLimitGiB: Math.min(Math.max(Math.round(Number(value.storageLimitGiB) || 5), 1), 500),
    termsAcknowledged: Boolean(value.termsAcknowledged),
  };
}

function isAllowedExternalURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && [
      'github.com', 'huggingface.co', 'stability.ai', 'ai.google.dev',
    ].some((host) => url.hostname === host || url.hostname.endsWith(`.${host}`));
  } catch { return false; }
}

function thumbarIcon(symbol) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><circle cx="16" cy="16" r="15" fill="#251811"/><text x="16" y="22" text-anchor="middle" font-family="Segoe UI Symbol" font-size="18" fill="#efd8b8">${symbol}</text></svg>`;
  return nativeImage.createFromDataURL(`data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`);
}

function updateThumbarButtons(isPlaying) {
  if (process.platform !== 'win32' || !mainWindow || mainWindow.isDestroyed()) return;
  mainWindow.setThumbarButtons([
    { tooltip: 'Предыдущий трек', icon: thumbarIcon('⏮'), click: () => mainWindow.webContents.send('system-action', 'previous') },
    { tooltip: isPlaying ? 'Пауза' : 'Воспроизвести', icon: thumbarIcon(isPlaying ? '⏸' : '▶'), click: () => mainWindow.webContents.send('system-action', 'play-pause') },
    { tooltip: 'Следующий трек', icon: thumbarIcon('⏭'), click: () => mainWindow.webContents.send('system-action', 'next') },
  ]);
}

app.on('second-instance', () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
});
app.on('activate', () => { if (!mainWindow) createWindow(); else mainWindow.show(); });
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('before-quit', () => { runtime?.cancel(); if (memoryTimer) clearInterval(memoryTimer); });
app.whenReady().then(initialize).catch((error) => {
  const logPath = path.join(app.getPath('temp'), `flowtone-startup-${crypto.randomUUID()}.log`);
  fs.writeFileSync(logPath, String(error?.stack || error));
  app.quit();
});
