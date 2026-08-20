'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const http = require('node:http');
const { GENRES, composePrompt, createStationConfiguration, generateTitle, genreProfile, pickTempo, profileCount } = require('../src/core.cjs');
const { DEFAULT_MODEL_ID, MODEL_GROUPS, MODEL_PROFILES, StableAudioRuntime, recommendGroup, recommendModel, stableRuntimeHealth } = require('../src/runtime.cjs');
const {
  DEFAULT_MODEL_ASSETS, DEFAULT_MODEL_TOTAL_BYTES, MODEL_REVISION, legacyHuggingFacePaths, resumableVerifiedDownload,
} = require('../src/model-download.cjs');
const { TrackLibrary } = require('../src/library.cjs');
const { shouldReplaceInstalledFlowtone, terminateInstalledFlowtone } = require('../src/instance-guard.cjs');
const { downloadActivity, measuredProgress, settleControlChange, userMessage } = require('../src/renderer/ui-utils.js');

test('dormant future catalog keeps hardware routing data for the postponed idea', () => {
  assert.equal(recommendModel({ memoryGiB: 8, logicalCores: 4 }), 'small-efficient');
  assert.equal(recommendModel({ memoryGiB: 16, logicalCores: 8 }), 'small-quality');
  assert.equal(recommendModel({ memoryGiB: 24, logicalCores: 12 }), 'medium-balanced');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24 }), 'medium-max');
});

test('dormant future catalog keeps GPU routing data without exposing it to the product', () => {
  assert.equal(recommendModel({ memoryGiB: 16, logicalCores: 8, gpu: 'NVIDIA RTX 3060', gpuMemoryGiB: 6 }), 'ace-lite');
  assert.equal(recommendModel({ memoryGiB: 24, logicalCores: 12, gpu: 'NVIDIA RTX 4070', gpuMemoryGiB: 12 }), 'ace-pro');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24, gpu: 'NVIDIA RTX 5090', gpuMemoryGiB: 32 }), 'ace-max');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24, gpu: 'AMD Radeon', gpuMemoryGiB: 24 }), 'medium-max');
});

test('postponed model groups remain internally well-formed for possible reactivation', () => {
  assert.equal(recommendGroup({ memoryGiB: 8 }), 'compact');
  assert.equal(recommendGroup({ memoryGiB: 16 }), 'balanced');
  assert.equal(recommendGroup({ memoryGiB: 24 }), 'powerful');
  for (const group of MODEL_GROUPS) {
    assert.ok(group.modelIds.length >= 3);
    for (const modelId of group.modelIds) {
      const model = MODEL_PROFILES[modelId];
      assert.ok(model);
      assert.ok(model.better && model.worse);
    }
  }
});

test('public Windows runtime exposes and routes only the default minimum model', async () => {
  const runtime = new StableAudioRuntime(path.join(os.tmpdir(), 'flowtone-single-model-contract'));
  runtime.hardware = { memoryGiB: 64, logicalCores: 32, gpu: 'NVIDIA RTX 5090', gpuMemoryGiB: 32 };
  const status = await runtime.status('ace-max');
  assert.equal(DEFAULT_MODEL_ID, 'small-efficient');
  assert.deepEqual(status.models.map((model) => model.id), [DEFAULT_MODEL_ID]);
  assert.equal(status.recommendedModel, DEFAULT_MODEL_ID);
  assert.equal(status.connectedModel, null);
  await assert.rejects(runtime.installModel('ace-max'), /только минимальная Stable Audio 3 Small/);
});

test('default model manifest pins three exact files, sizes and hashes', () => {
  assert.match(MODEL_REVISION, /^[0-9a-f]{40}$/);
  assert.equal(DEFAULT_MODEL_ASSETS.length, 3);
  assert.equal(DEFAULT_MODEL_TOTAL_BYTES, 1086612752);
  assert.deepEqual(DEFAULT_MODEL_ASSETS.map((asset) => asset.bytes), [563818608, 467069712, 55724432]);
  for (const asset of DEFAULT_MODEL_ASSETS) assert.match(asset.sha256, /^[0-9a-f]{64}$/);
  const legacy = legacyHuggingFacePaths('C:\\Users\\Учкук\\Flowtone\\Models', DEFAULT_MODEL_ASSETS[0]);
  assert.match(legacy.partial, /\.incomplete$/);
});

test('verified downloader resumes a partial file under a Cyrillic path with real byte callbacks', async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'Flowtone-Загрузка-'));
  const payload = Buffer.alloc(96 * 1024);
  for (let index = 0; index < payload.length; index += 1) payload[index] = index % 251;
  const expectedSHA256 = crypto.createHash('sha256').update(payload).digest('hex');
  let requestedRange = null;
  const server = http.createServer((request, response) => {
    requestedRange = request.headers.range || null;
    const start = requestedRange ? Number(requestedRange.match(/^bytes=(\d+)-$/)?.[1]) : 0;
    response.writeHead(start > 0 ? 206 : 200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': payload.length - start,
      ...(start > 0 ? { 'Content-Range': `bytes ${start}-${payload.length - 1}/${payload.length}` } : {}),
    });
    response.end(payload.subarray(start));
  });
  try {
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const destination = path.join(root, 'готовая модель', 'weights.bin');
    const partialPath = path.join(root, 'частичная загрузка', 'weights.partial');
    const resumedFrom = 17 * 1024;
    await writeRuntimeFile(partialPath, payload.subarray(0, resumedFrom));
    const samples = [];
    const address = server.address();
    const result = await resumableVerifiedDownload({
      url: `http://127.0.0.1:${address.port}/weights.bin`, destination, partialPath,
      expectedBytes: payload.length, expectedSHA256, onProgress: (sample) => samples.push(sample),
    });
    assert.equal(requestedRange, `bytes=${resumedFrom}-`);
    assert.equal(result.resumedFrom, resumedFrom);
    assert.deepEqual(await fsp.readFile(destination), payload);
    assert.equal(samples[0].fileBytes, resumedFrom);
    assert.equal(samples.at(-1).fileBytes, payload.length);
    assert.equal(samples.at(-1).completed, true);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test('verified downloader deletes a completed corrupt partial instead of reporting success', async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'Flowtone-Corrupt-'));
  const payload = Buffer.alloc(4096, 7);
  const expectedSHA256 = crypto.createHash('sha256').update(Buffer.alloc(4096, 8)).digest('hex');
  const server = http.createServer((_request, response) => {
    response.writeHead(200, { 'Content-Length': payload.length }); response.end(payload);
  });
  try {
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    const destination = path.join(root, 'model.bin');
    const partialPath = `${destination}.partial`;
    await assert.rejects(resumableVerifiedDownload({
      url: `http://127.0.0.1:${address.port}/corrupt.bin`, destination, partialPath,
      expectedBytes: payload.length, expectedSHA256,
    }), /Контрольная сумма/);
    await assert.rejects(fsp.stat(destination));
    await assert.rejects(fsp.stat(partialPath));
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test('download status distinguishes active transfer, network wait and a probable stall', () => {
  const now = Date.parse('2026-08-20T12:00:00Z');
  const base = {
    downloadBytes: 64 * 1024 ** 2, downloadTotalBytes: 128 * 1024 ** 2,
    downloadCompletedFiles: 1, downloadExpectedFiles: 3,
  };
  const active = downloadActivity({ ...base, downloadBytesPerSecond: 2 * 1024 ** 2, downloadLastActivityAt: now - 1000 }, now);
  assert.equal(active.state, 'active');
  assert.match(active.text, /2\.0 МБ\/с/);
  assert.match(active.text, /50% загрузки/);
  const waiting = downloadActivity({ ...base, downloadLastActivityAt: now - 25000 }, now);
  assert.equal(waiting.label, 'ОЖИДАНИЕ СЕТИ');
  assert.match(waiting.text, /0:25/);
  const stalled = downloadActivity({ ...base, downloadLastActivityAt: now - 65000 }, now);
  assert.equal(stalled.state, 'stalled');
  assert.match(stalled.text, /отменить и повторить/);
});

test('measured progress maps exact bytes to clamped 0, 50 and 100 percent', () => {
  assert.deepEqual(measuredProgress(0, 1000), { ratio: 0, percent: 0 });
  assert.deepEqual(measuredProgress(500, 1000), { ratio: 0.5, percent: 50 });
  assert.deepEqual(measuredProgress(1000, 1000), { ratio: 1, percent: 100 });
  assert.deepEqual(measuredProgress(1500, 1000), { ratio: 1, percent: 100 });
  assert.equal(measuredProgress(500, 0), null);
});

test('old Stable Audio runtime without tokenizer is rejected even under a Cyrillic Windows profile', async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'Flowtone-Учкук-'));
  try {
    const runtimeRoot = path.join(root, 'Runtime', 'stable-audio-3-tflite');
    const python = path.join(runtimeRoot, '.venv', 'Scripts', 'python.exe');
    await writeRuntimeFile(python, 'python');
    await writeRuntimeFile(path.join(runtimeRoot, 'scripts', 'sa3_tflite.py'), 'main');
    await writeRuntimeFile(
      path.join(runtimeRoot, 'models', 'defs', 'tflite_pipeline.py'),
      'self.sp.LoadFromSerializedProto(model_path.read_bytes())',
    );
    const broken = stableRuntimeHealth(runtimeRoot, python);
    assert.equal(broken.ready, false);
    assert.equal(broken.repairNeeded, true);
    assert.ok(broken.missingFiles.includes('tokenizer.model'));

    await writeRuntimeFile(path.join(runtimeRoot, 'models', 'tokenizer.model'), 'tokenizer');
    assert.equal(stableRuntimeHealth(runtimeRoot, python).ready, true);
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test('legacy filename-based tokenizer loader requires the Unicode-safe compatibility patch', async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'flowtone-runtime-'));
  try {
    const python = path.join(root, '.venv', 'Scripts', 'python.exe');
    await writeRuntimeFile(python, 'python');
    await writeRuntimeFile(path.join(root, 'scripts', 'sa3_tflite.py'), 'main');
    await writeRuntimeFile(path.join(root, 'models', 'tokenizer.model'), 'tokenizer');
    await writeRuntimeFile(path.join(root, 'models', 'defs', 'tflite_pipeline.py'), 'self.sp.LoadFromFile(str(model_path))');
    assert.ok(stableRuntimeHealth(root, python).missingFiles.includes('совместимость пути Windows'));
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test('initialization migrates the legacy tokenizer loader without a network download', async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'Flowtone-Ирина-'));
  try {
    const runtimeRoot = path.join(root, 'Runtime', 'stable-audio-3-tflite');
    const python = path.join(runtimeRoot, '.venv', 'Scripts', 'python.exe');
    await writeRuntimeFile(python, 'python');
    await writeRuntimeFile(path.join(runtimeRoot, 'scripts', 'sa3_tflite.py'), 'main');
    await writeRuntimeFile(path.join(runtimeRoot, 'models', 'tokenizer.model'), 'tokenizer');
    await writeRuntimeFile(
      path.join(runtimeRoot, 'models', 'defs', 'tflite_pipeline.py'),
      '        self.sp = spm.SentencePieceProcessor()\n        self.sp.LoadFromFile(str(model_path))\n',
    );
    const runtime = new StableAudioRuntime(root);
    await runtime.initialize({ memoryGiB: 16, logicalCores: 8 });
    assert.equal(stableRuntimeHealth(runtimeRoot, python).ready, true);
    assert.match(
      await fsp.readFile(path.join(runtimeRoot, 'models', 'defs', 'tflite_pipeline.py'), 'utf8'),
      /LoadFromSerializedProto\(model_path\.read_bytes\(\)\)/,
    );
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

test('Windows development launch replaces the stale installed copy before taking the shared lock', () => {
  assert.equal(shouldReplaceInstalledFlowtone('win32', false, 'C:\\tools\\electron.exe'), true);
  assert.equal(shouldReplaceInstalledFlowtone('win32', true, 'C:\\Program Files\\Flowtone\\Flowtone.exe'), false);
  assert.equal(shouldReplaceInstalledFlowtone('darwin', false, '/Applications/Electron.app/Electron'), false);
  let invocation = null;
  const stopped = terminateInstalledFlowtone({
    platform: 'win32', isPackaged: false, executablePath: 'C:\\tools\\electron.exe',
    run(command, args) { invocation = { command, args }; return { status: 0 }; },
  });
  assert.equal(stopped, true);
  assert.deepEqual(invocation, { command: 'taskkill.exe', args: ['/IM', 'Flowtone.exe', '/T', '/F'] });
});

test('technical runtime traces become short actionable Russian messages', () => {
  const tokenizer = userMessage(new Error('Traceback (most recent call last): File "C:\\Users\\Учкук\\Runtime\\sa3.py", line 55 RuntimeError: NOT_FOUND: models\\tokenizer.model'));
  assert.equal(tokenizer, 'Модель Stable Audio установлена не полностью. Откройте «Настроить модель» и нажмите «Восстановить».');
  assert.doesNotMatch(tokenizer, /Traceback|C:\\Users/);
  const generic = userMessage(`Traceback (most recent call last): ${'internal details '.repeat(100)}`);
  assert.equal(generic, 'Локальная модель завершила работу с ошибкой. Повторите попытку; если ошибка вернётся, восстановите модель.');
  assert.equal(
    userMessage(new TypeError('fetch failed')),
    'Не удалось скачать файлы модели. Проверьте интернет и повторите установку — уже загруженные данные сохранятся.',
  );
  assert.ok(userMessage('x'.repeat(500)).length <= 220);
});

test('generation and model installation cancellation stay isolated', () => {
  const runtime = new StableAudioRuntime(path.join(os.tmpdir(), 'flowtone-cancel-scope-test'));
  let aborts = 0;
  let aceCancels = 0;
  runtime.activeDownloadAbort = { abort() { aborts += 1; } };
  runtime.aceRuntime.cancel = () => { aceCancels += 1; };
  runtime.installing = true;
  assert.equal(runtime.cancelGeneration(), false);
  assert.equal(aborts, 0);
  assert.equal(aceCancels, 0);
  assert.equal(runtime.cancelInstallation(), true);
  assert.equal(aborts, 1);
  assert.equal(aceCancels, 1);
});

test('failed toggle persistence returns an explicit rollback outcome', async () => {
  let rolledBack = false;
  const failure = new Error('settings IPC failed');
  const outcome = await settleControlChange({
    commit: async () => { throw failure; },
    onFailure: async (error) => { rolledBack = error === failure; },
  });
  assert.equal(outcome.ok, false);
  assert.equal(outcome.error, failure);
  assert.equal(rolledBack, true);
});

test('station configuration stays deterministic for explicit seed', () => {
  const settings = { selectedGenres: ['Ambient', 'Rock', 'Jazz'], mixGenresEnabled: true, energy: 'driving', mood: 'warm', vibe: 'ночной город' };
  assert.deepEqual(createStationConfiguration(settings, 123456), createStationConfiguration(settings, 123456));
  const genres = createStationConfiguration(settings, 123456).genres;
  assert.ok(genres.length >= 2 && genres.length <= 5);
  assert.equal(new Set(genres).size, genres.length);
});

test('tempo stays in genre range and driving is not slower for common seed', () => {
  for (let seed = 1; seed < 80; seed += 1) {
    const calm = pickTempo('Techno', 'calm', seed);
    const driving = pickTempo('Techno', 'driving', seed);
    assert.ok(calm >= 120 && calm <= 140);
    assert.ok(driving >= calm);
  }
});

test('prompt is instrumental and includes selected controls', () => {
  const configuration = createStationConfiguration({ selectedGenres: ['Synthwave'], energy: 'balanced', mood: 'focused', vibe: 'дождь', mixGenresEnabled: false }, 91);
  const prompt = composePrompt(configuration);
  assert.match(prompt, /Synth|synth/i);
  assert.match(prompt, /strictly no lyrics and no voice/);
  assert.match(prompt, /дождь/);
});

test('Windows mirrors all 350 macOS production profiles', () => {
  assert.equal(GENRES.reduce((total, genre) => total + profileCount(genre), 0), 350);
  assert.equal(profileCount('Synthwave'), 30);
  assert.equal(profileCount('Pirate'), 16);
  assert.equal(profileCount('Space Rock'), 16);
  assert.match(genreProfile('Rock', 'driving', 42n), /strong climax/);
  assert.equal(genreProfile('Ambient', 'calm', 7n), genreProfile('Ambient', 'calm', 7n));
});

test('Russian title never exceeds ten words', () => {
  const configuration = createStationConfiguration({ selectedGenres: ['Space Rock'], energy: 'driving', mood: 'dreamy', vibe: '', mixGenresEnabled: false }, 51);
  assert.ok(generateTitle(configuration, 51).split(/\s+/).length <= 10);
});

test('library imports, likes, protects paths and removes files', async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), 'flowtone-library-'));
  try {
    const library = new TrackLibrary(root);
    await library.load();
    const source = path.join(library.incomingDirectory, 'generated.wav');
    await fsp.writeFile(source, testWave());
    const configuration = createStationConfiguration({ selectedGenres: ['Ambient'], energy: 'calm', mood: 'focused', vibe: '', mixGenresEnabled: false }, 7);
    const track = await library.importGeneratedAudio(source, configuration, { durationSeconds: 120 });
    assert.equal(library.statistics().trackCount, 1);
    await library.setLiked(track.id, true);
    assert.equal(library.statistics().likedTrackCount, 1);
    const preview = await library.wavePreview(track.id, 0.01, -1, 0.01);
    assert.equal(preview.sampleRate, 44100);
    assert.equal(preview.channels, 2);
    assert.ok(preview.frameCount > 0 && preview.pcm16.length === preview.frameCount * 4);
    assert.throws(() => library.audioPath('../outside'));
    await library.removeTrack(track.id);
    assert.equal(library.statistics().trackCount, 0);
  } finally {
    await fsp.rm(root, { recursive: true, force: true });
  }
});

function testWave(frameCount = 2205) {
  const dataSize = frameCount * 4;
  const output = Buffer.alloc(44 + dataSize);
  output.write('RIFF', 0); output.writeUInt32LE(36 + dataSize, 4); output.write('WAVE', 8);
  output.write('fmt ', 12); output.writeUInt32LE(16, 16); output.writeUInt16LE(1, 20);
  output.writeUInt16LE(2, 22); output.writeUInt32LE(44100, 24); output.writeUInt32LE(176400, 28);
  output.writeUInt16LE(4, 32); output.writeUInt16LE(16, 34); output.write('data', 36); output.writeUInt32LE(dataSize, 40);
  for (let offset = 44; offset < output.length; offset += 2) output.writeInt16LE((offset * 97) % 32767, offset);
  return output;
}

async function writeRuntimeFile(filePath, contents) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
  await fsp.writeFile(filePath, contents);
}
