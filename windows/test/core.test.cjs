'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const fsp = require('node:fs/promises');
const path = require('node:path');
const { GENRES, composePrompt, createStationConfiguration, generateTitle, genreProfile, pickTempo, profileCount } = require('../src/core.cjs');
const { MODEL_GROUPS, MODEL_PROFILES, StableAudioRuntime, recommendGroup, recommendModel, stableRuntimeHealth } = require('../src/runtime.cjs');
const { TrackLibrary } = require('../src/library.cjs');
const { shouldReplaceInstalledFlowtone, terminateInstalledFlowtone } = require('../src/instance-guard.cjs');
const { settleControlChange, userMessage } = require('../src/renderer/ui-utils.js');

test('autoselection scales model with memory and CPU', () => {
  assert.equal(recommendModel({ memoryGiB: 8, logicalCores: 4 }), 'small-efficient');
  assert.equal(recommendModel({ memoryGiB: 16, logicalCores: 8 }), 'small-quality');
  assert.equal(recommendModel({ memoryGiB: 24, logicalCores: 12 }), 'medium-balanced');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24 }), 'medium-max');
});

test('autoselection upgrades to ACE-Step only for suitable NVIDIA VRAM', () => {
  assert.equal(recommendModel({ memoryGiB: 16, logicalCores: 8, gpu: 'NVIDIA RTX 3060', gpuMemoryGiB: 6 }), 'ace-lite');
  assert.equal(recommendModel({ memoryGiB: 24, logicalCores: 12, gpu: 'NVIDIA RTX 4070', gpuMemoryGiB: 12 }), 'ace-pro');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24, gpu: 'NVIDIA RTX 5090', gpuMemoryGiB: 32 }), 'ace-max');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24, gpu: 'AMD Radeon', gpuMemoryGiB: 24 }), 'medium-max');
});

test('every Windows power group has a baseline and at least two alternatives', () => {
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
