'use strict';

const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { generateTitle } = require('./core.cjs');

class TrackLibrary {
  constructor(rootDirectory) {
    this.rootDirectory = rootDirectory;
    this.audioDirectory = path.join(rootDirectory, 'Audio');
    this.incomingDirectory = path.join(rootDirectory, 'Incoming');
    this.indexPath = path.join(rootDirectory, 'library-v1.json');
    this.tracks = [];
    this.waveMetadata = new Map();
    this.loaded = false;
    this.writeChain = Promise.resolve();
  }

  async load() {
    await this.#prepareDirectories();
    await this.removeOrphanedIncomingAudio();
    try {
      const parsed = JSON.parse(await fsp.readFile(this.indexPath, 'utf8'));
      const records = Array.isArray(parsed.tracks) ? parsed.tracks : [];
      this.tracks = records
        .filter((track) => this.#validRecord(track))
        .filter((track) => fs.existsSync(path.join(this.audioDirectory, track.fileName)))
        .map((track) => ({ ...track, isTransient: Boolean(track.isTransient), isLiked: Boolean(track.isLiked) }));
    } catch (error) {
      if (error.code !== 'ENOENT') await this.#preserveCorruptIndex();
      this.tracks = [];
    }
    this.loaded = true;
    await this.#persist();
    return this.allTracks();
  }

  allTracks() {
    this.#ensureLoaded();
    return [...this.tracks].sort((left, right) =>
      String(right.createdAt).localeCompare(String(left.createdAt)) || left.id.localeCompare(right.id));
  }

  statistics() {
    this.#ensureLoaded();
    const byGenre = new Map();
    for (const track of this.tracks) {
      for (const genre of new Set(track.genres)) {
        const current = byGenre.get(genre) || { trackCount: 0, byteSize: 0 };
        current.trackCount += 1;
        current.byteSize += Number(track.byteSize) || 0;
        byGenre.set(genre, current);
      }
    }
    return {
      trackCount: this.tracks.length,
      likedTrackCount: this.tracks.filter((track) => track.isLiked).length,
      byteSize: this.tracks.reduce((sum, track) => sum + (Number(track.byteSize) || 0), 0),
      genres: [...byGenre.entries()].map(([genre, values]) => ({ genre, ...values }))
        .sort((left, right) => left.genre.localeCompare(right.genre, 'ru')),
    };
  }

  audioPath(trackId) {
    this.#ensureLoaded();
    const track = this.tracks.find((item) => item.id === trackId);
    if (!track) throw new Error('Запись не найдена в локальной библиотеке.');
    const candidate = path.join(this.audioDirectory, track.fileName);
    if (path.dirname(candidate) !== this.audioDirectory || !fs.existsSync(candidate)) {
      throw new Error('Аудиофайл записи не найден.');
    }
    return candidate;
  }

  async wavePreview(trackId, positionSeconds, direction = 1, durationSeconds = 0.11) {
    const audioPath = this.audioPath(trackId);
    let metadata = this.waveMetadata.get(trackId);
    const handle = await fsp.open(audioPath, 'r');
    try {
      if (!metadata) {
        metadata = await readWaveMetadata(handle);
        if (!metadata) return null;
        this.waveMetadata.set(trackId, metadata);
      }
      const requestedFrames = Math.max(1, Math.min(Math.round(metadata.sampleRate * durationSeconds), metadata.sampleRate));
      const centerFrame = Math.min(Math.max(Math.round(Number(positionSeconds) * metadata.sampleRate), 0), metadata.totalFrames);
      const startFrame = Number(direction) < 0 ? Math.max(0, centerFrame - requestedFrames) : Math.min(centerFrame, Math.max(0, metadata.totalFrames - requestedFrames));
      const availableFrames = Math.min(requestedFrames, metadata.totalFrames - startFrame);
      if (availableFrames <= 0) return null;
      const pcm16 = Buffer.allocUnsafe(availableFrames * metadata.blockAlign);
      const { bytesRead } = await handle.read(pcm16, 0, pcm16.length, metadata.dataOffset + startFrame * metadata.blockAlign);
      const frameCount = Math.floor(bytesRead / metadata.blockAlign);
      if (!frameCount) return null;
      return {
        sampleRate: metadata.sampleRate,
        channels: metadata.channels,
        frameCount,
        pcm16: pcm16.subarray(0, frameCount * metadata.blockAlign),
      };
    } finally {
      await handle.close();
    }
  }

  compatibleTracks(genres = [], excluding = []) {
    this.#ensureLoaded();
    const genreSet = new Set(genres);
    const excluded = new Set(excluding);
    return this.tracks.filter((track) => !excluded.has(track.id)
      && (genreSet.size === 0 || track.genres.some((genre) => genreSet.has(genre))));
  }

  nextCompatibleTrack({ genres = [], excluding = [], shuffle = true } = {}) {
    let candidates = this.compatibleTracks(genres, excluding);
    if (!candidates.length && genres.length) candidates = this.compatibleTracks([], excluding);
    if (!candidates.length) return null;
    if (shuffle) return candidates[crypto.randomInt(candidates.length)];
    return candidates.sort((left, right) => {
      const leftDate = left.lastPlayedAt || left.createdAt;
      const rightDate = right.lastPlayedAt || right.createdAt;
      return String(leftDate).localeCompare(String(rightDate)) || left.playCount - right.playCount;
    })[0];
  }

  async importGeneratedAudio(audioPath, configuration, metadata = {}) {
    this.#ensureLoaded();
    const extension = path.extname(audioPath).toLowerCase() || '.wav';
    if (!['.wav', '.flac', '.mp3', '.m4a', '.ogg'].includes(extension)) {
      throw new Error('Движок вернул неподдерживаемый формат аудио.');
    }
    const id = crypto.randomUUID();
    const fileName = `${id.toLowerCase()}${extension}`;
    const destination = path.join(this.audioDirectory, fileName);
    await fsp.rename(audioPath, destination);
    const stat = await fsp.stat(destination);
    const track = {
      id,
      title: generateTitle(configuration, configuration.seed),
      fileName,
      genres: configuration.genres,
      createdAt: new Date().toISOString(),
      lastPlayedAt: null,
      playCount: 0,
      isLiked: false,
      isTransient: Boolean(metadata.isTransient),
      durationSeconds: Number(metadata.durationSeconds) || 120,
      byteSize: stat.size,
      engineID: metadata.engineID || 'stable-audio-3-small-cpu',
      seed: configuration.seed,
    };
    this.tracks.push(track);
    try {
      await this.#persist();
    } catch (error) {
      this.tracks = this.tracks.filter((item) => item.id !== id);
      await fsp.rm(destination, { force: true });
      throw error;
    }
    return { ...track };
  }

  async markPlayed(trackId) {
    const track = this.#find(trackId);
    track.lastPlayedAt = new Date().toISOString();
    track.playCount = (Number(track.playCount) || 0) + 1;
    await this.#persist();
    return { ...track };
  }

  async setLiked(trackId, liked) {
    const track = this.#find(trackId);
    track.isLiked = Boolean(liked);
    await this.#persist();
    return { ...track };
  }

  async removeTrack(trackId) {
    const track = this.#find(trackId);
    await fsp.rm(path.join(this.audioDirectory, track.fileName), { force: true });
    this.tracks = this.tracks.filter((item) => item.id !== trackId);
    this.waveMetadata.delete(trackId);
    await this.#persist();
    return { ...track };
  }

  async removeAllUnliked(protectedTrackIds = []) {
    return this.#removeWhere((track) => !track.isLiked, protectedTrackIds);
  }

  async removeUnlikedTransient(protectedTrackIds = []) {
    return this.#removeWhere((track) => track.isTransient && !track.isLiked, protectedTrackIds);
  }

  async removeOrphanedIncomingAudio() {
    await this.#prepareDirectories();
    const entries = await fsp.readdir(this.incomingDirectory, { withFileTypes: true });
    let removed = 0;
    for (const entry of entries) {
      if (!entry.isFile()) continue;
      await fsp.rm(path.join(this.incomingDirectory, entry.name), { force: true });
      removed += 1;
    }
    return removed;
  }

  async #removeWhere(predicate, protectedTrackIds) {
    this.#ensureLoaded();
    const protectedSet = new Set(protectedTrackIds);
    const candidates = this.tracks.filter((track) => predicate(track) && !protectedSet.has(track.id));
    let removedByteSize = 0;
    for (const track of candidates) {
      await fsp.rm(path.join(this.audioDirectory, track.fileName), { force: true });
      removedByteSize += Number(track.byteSize) || 0;
    }
    const ids = new Set(candidates.map((track) => track.id));
    this.tracks = this.tracks.filter((track) => !ids.has(track.id));
    for (const id of ids) this.waveMetadata.delete(id);
    if (candidates.length) await this.#persist();
    return { removedTrackCount: candidates.length, removedByteSize };
  }

  #find(trackId) {
    this.#ensureLoaded();
    const track = this.tracks.find((item) => item.id === trackId);
    if (!track) throw new Error('Запись не найдена в локальной библиотеке.');
    return track;
  }

  #validRecord(track) {
    return track && typeof track.id === 'string' && typeof track.fileName === 'string'
      && path.basename(track.fileName) === track.fileName && Array.isArray(track.genres);
  }

  #ensureLoaded() {
    if (!this.loaded) throw new Error('Локальная библиотека ещё загружается.');
  }

  async #prepareDirectories() {
    await Promise.all([
      fsp.mkdir(this.audioDirectory, { recursive: true }),
      fsp.mkdir(this.incomingDirectory, { recursive: true }),
    ]);
  }

  async #persist() {
    const payload = `${JSON.stringify({ version: 1, tracks: this.allTracks() })}\n`;
    const tempPath = `${this.indexPath}.${process.pid}.tmp`;
    this.writeChain = this.writeChain.then(async () => {
      await fsp.writeFile(tempPath, payload, { encoding: 'utf8', mode: 0o600 });
      await fsp.rename(tempPath, this.indexPath);
    });
    await this.writeChain;
  }

  async #preserveCorruptIndex() {
    const backup = `${this.indexPath}.corrupt-${Date.now()}`;
    await fsp.rename(this.indexPath, backup).catch(() => {});
  }
}

async function readWaveMetadata(handle) {
  const stat = await handle.stat();
  const header = Buffer.alloc(Math.min(stat.size, 256 * 1024));
  const { bytesRead } = await handle.read(header, 0, header.length, 0);
  if (bytesRead < 44 || header.toString('ascii', 0, 4) !== 'RIFF' || header.toString('ascii', 8, 12) !== 'WAVE') return null;
  let format = null;
  let dataOffset = null;
  let dataSize = null;
  for (let offset = 12; offset + 8 <= bytesRead;) {
    const id = header.toString('ascii', offset, offset + 4);
    const size = header.readUInt32LE(offset + 4);
    const body = offset + 8;
    if (id === 'fmt ' && size >= 16 && body + 16 <= bytesRead) {
      format = {
        audioFormat: header.readUInt16LE(body), channels: header.readUInt16LE(body + 2),
        sampleRate: header.readUInt32LE(body + 4), blockAlign: header.readUInt16LE(body + 12),
        bitsPerSample: header.readUInt16LE(body + 14),
      };
    }
    if (id === 'data') { dataOffset = body; dataSize = Math.min(size, Math.max(0, stat.size - body)); break; }
    offset = body + size + (size % 2);
  }
  if (!format || format.audioFormat !== 1 || format.bitsPerSample !== 16 || ![1, 2].includes(format.channels)
    || format.blockAlign !== format.channels * 2 || !format.sampleRate || dataOffset === null) return null;
  return { ...format, dataOffset, totalFrames: Math.floor(dataSize / format.blockAlign) };
}

module.exports = { TrackLibrary };
