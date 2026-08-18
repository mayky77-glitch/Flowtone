'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const fsp = require('node:fs/promises');
const path = require('node:path');
const { GENRES, composePrompt, createStationConfiguration, generateTitle, genreProfile, pickTempo, profileCount } = require('../src/core.cjs');
const { recommendModel } = require('../src/runtime.cjs');
const { TrackLibrary } = require('../src/library.cjs');

test('autoselection scales model with memory and CPU', () => {
  assert.equal(recommendModel({ memoryGiB: 8, logicalCores: 4 }), 'small-efficient');
  assert.equal(recommendModel({ memoryGiB: 16, logicalCores: 8 }), 'small-quality');
  assert.equal(recommendModel({ memoryGiB: 24, logicalCores: 12 }), 'medium-balanced');
  assert.equal(recommendModel({ memoryGiB: 64, logicalCores: 24 }), 'medium-max');
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
