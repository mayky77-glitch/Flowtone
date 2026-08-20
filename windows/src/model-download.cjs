'use strict';

const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { Readable, Transform } = require('node:stream');
const { pipeline } = require('node:stream/promises');

const MODEL_REPO_ID = 'stabilityai/stable-audio-3-optimized';
const MODEL_REVISION = '2204d5086475bd5b7e6e2bd720772dd8e8160513';

const DEFAULT_MODEL_ASSETS = Object.freeze([
  Object.freeze({
    id: 'text-encoder', cacheID: '_shared', stageIndex: 1, stageCount: 2,
    stageTitle: 'Скачиваю текстовый модуль',
    relativePath: 'models/tflite/t5gemma/encoder_fp16.tflite',
    remotePath: 'tflite/t5gemma/encoder_fp16.tflite',
    bytes: 563818608,
    sha256: '8530d0b3e6b9b9dcf1239145c2a853fb749708eaddbb472ff8f0802b50059372',
  }),
  Object.freeze({
    id: 'music-dit', cacheID: 'small-efficient', stageIndex: 2, stageCount: 2,
    stageTitle: 'Скачиваю музыкальную модель',
    relativePath: 'models/tflite/sa3-sm-music/dit_w8a8-dyn.tflite',
    remotePath: 'tflite/sa3-sm-music/dit_w8a8-dyn.tflite',
    bytes: 467069712,
    sha256: '489f30a65c5f3be1a107420b9389043397352e3587a7b289982f8e210d1a4efd',
  }),
  Object.freeze({
    id: 'audio-decoder', cacheID: 'small-efficient', stageIndex: 2, stageCount: 2,
    stageTitle: 'Скачиваю музыкальную модель',
    relativePath: 'models/tflite/same-s/dec_w8a8-dyn.tflite',
    remotePath: 'tflite/same-s/dec_w8a8-dyn.tflite',
    bytes: 55724432,
    sha256: 'b477524497d92160605409b1999370fbeadb61ad17edce905d79b0eaced6785d',
  }),
]);

const DEFAULT_MODEL_TOTAL_BYTES = DEFAULT_MODEL_ASSETS.reduce((total, asset) => total + asset.bytes, 0);

function modelAssetURL(asset) {
  return `https://huggingface.co/${MODEL_REPO_ID}/resolve/${MODEL_REVISION}/${asset.remotePath}?download=true`;
}

function legacyHuggingFacePaths(modelsRoot, asset) {
  const blobs = path.join(
    modelsRoot,
    asset.cacheID,
    'HuggingFace',
    'hub',
    `models--${MODEL_REPO_ID.replace('/', '--')}`,
    'blobs',
  );
  return { complete: path.join(blobs, asset.sha256), partial: path.join(blobs, `${asset.sha256}.incomplete`) };
}

async function resumableVerifiedDownload({
  url,
  destination,
  partialPath = `${destination}.partial`,
  expectedBytes,
  expectedSHA256,
  signal,
  fetchImpl = fetch,
  onProgress = () => {},
}) {
  if (!Number.isSafeInteger(expectedBytes) || expectedBytes <= 0) throw new Error('Некорректный размер файла модели.');
  if (!/^[0-9a-f]{64}$/i.test(String(expectedSHA256))) throw new Error('Некорректная контрольная сумма модели.');
  await Promise.all([
    fsp.mkdir(path.dirname(destination), { recursive: true }),
    fsp.mkdir(path.dirname(partialPath), { recursive: true }),
  ]);

  if (await verifiedFile(destination, expectedBytes, expectedSHA256)) {
    onProgress({ fileBytes: expectedBytes, deltaBytes: 0, bytesPerSecond: 0, completed: true, reused: true });
    return { bytes: expectedBytes, resumedFrom: expectedBytes, reused: true };
  }
  await fsp.rm(destination, { force: true });

  let resumedFrom = Math.min(await fileSize(partialPath), expectedBytes);
  if (await fileSize(partialPath) > expectedBytes) {
    await fsp.rm(partialPath, { force: true });
    resumedFrom = 0;
  }
  if (resumedFrom === expectedBytes) {
    if (await verifiedFile(partialPath, expectedBytes, expectedSHA256)) {
      await fsp.rename(partialPath, destination);
      onProgress({ fileBytes: expectedBytes, deltaBytes: 0, bytesPerSecond: 0, completed: true, reused: true });
      return { bytes: expectedBytes, resumedFrom, reused: true };
    }
    await fsp.rm(partialPath, { force: true });
    resumedFrom = 0;
  }

  onProgress({ fileBytes: resumedFrom, deltaBytes: 0, bytesPerSecond: 0, completed: false, reused: resumedFrom > 0 });
  const headers = resumedFrom > 0 ? { Range: `bytes=${resumedFrom}-` } : {};
  const response = await fetchImpl(url, { redirect: 'follow', headers, signal });
  if (!response.ok || !response.body) throw new Error(`Сервер модели вернул HTTP ${response.status}.`);

  if (resumedFrom > 0 && response.status === 200) {
    await fsp.truncate(partialPath, 0);
    resumedFrom = 0;
    onProgress({ fileBytes: 0, deltaBytes: 0, bytesPerSecond: 0, completed: false, reused: false });
  } else if (resumedFrom > 0) {
    const contentRange = response.headers.get('content-range') || '';
    if (response.status !== 206 || !contentRange.startsWith(`bytes ${resumedFrom}-`)) {
      throw new Error('Сервер модели не подтвердил продолжение частичной загрузки.');
    }
  }

  let fileBytes = resumedFrom;
  let lastReportBytes = fileBytes;
  let lastReportAt = Date.now();
  const meter = new Transform({
    transform(chunk, encoding, callback) {
      fileBytes += chunk.length;
      if (fileBytes > expectedBytes) return callback(new Error('Файл модели оказался больше ожидаемого размера.'));
      const now = Date.now();
      if (now - lastReportAt >= 250 || fileBytes === expectedBytes) {
        const deltaBytes = fileBytes - lastReportBytes;
        const elapsedSeconds = Math.max((now - lastReportAt) / 1000, 0.001);
        onProgress({
          fileBytes,
          deltaBytes,
          bytesPerSecond: Math.max(0, deltaBytes) / elapsedSeconds,
          completed: false,
          reused: resumedFrom > 0,
        });
        lastReportBytes = fileBytes;
        lastReportAt = now;
      }
      callback(null, chunk);
    },
  });
  await pipeline(
    Readable.fromWeb(response.body),
    meter,
    fs.createWriteStream(partialPath, { flags: resumedFrom > 0 ? 'a' : 'w', mode: 0o600 }),
  );

  const finalSize = await fileSize(partialPath);
  if (finalSize !== expectedBytes) {
    if (finalSize > expectedBytes) await fsp.rm(partialPath, { force: true });
    throw new Error(`Файл модели загрузился не полностью: ${finalSize} из ${expectedBytes} байт.`);
  }
  if (!await verifiedFile(partialPath, expectedBytes, expectedSHA256)) {
    await fsp.rm(partialPath, { force: true });
    throw new Error('Контрольная сумма файла модели не совпала. Повреждённая часть удалена.');
  }
  await fsp.rename(partialPath, destination);
  onProgress({ fileBytes: expectedBytes, deltaBytes: 0, bytesPerSecond: 0, completed: true, reused: resumedFrom > 0 });
  return { bytes: expectedBytes, resumedFrom, reused: false };
}

async function verifiedFile(filePath, expectedBytes, expectedSHA256) {
  if (await fileSize(filePath) !== expectedBytes) return false;
  return await sha256(filePath) === expectedSHA256;
}

async function fileSize(filePath) {
  try {
    const stat = await fsp.stat(filePath);
    return stat.isFile() ? stat.size : 0;
  } catch {
    return 0;
  }
}

async function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  await pipeline(fs.createReadStream(filePath), hash);
  return hash.digest('hex');
}

module.exports = {
  DEFAULT_MODEL_ASSETS,
  DEFAULT_MODEL_TOTAL_BYTES,
  MODEL_REPO_ID,
  MODEL_REVISION,
  fileSize,
  legacyHuggingFacePaths,
  modelAssetURL,
  resumableVerifiedDownload,
  verifiedFile,
};
