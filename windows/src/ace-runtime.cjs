'use strict';

const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { Readable } = require('node:stream');
const { pipeline } = require('node:stream/promises');

const SOURCE_REVISION = '14c0211d5a0653b0f63e27686f4c3f151b4d8629';
const SOURCE_SHA256 = 'cdf69c060ed3a6bfddebbf21dd0c548ea7ddfdf0f3cebc20d2a572085970586e';
const UV_VERSION = '0.12.5';
const UV_WINDOWS_SHA256 = '4c4d49d8738847d9b71ba319e49a5688c93eac0fe6204b1df24e98528dddf39a';

class ACEStepRuntime {
  constructor(applicationSupportRoot, onProgress = () => {}) {
    this.applicationSupportRoot = applicationSupportRoot;
    this.runtimeRoot = path.join(applicationSupportRoot, 'Runtime', 'ACE-Step-1.5');
    this.modelRoot = path.join(applicationSupportRoot, 'Models', 'ACE-Step-1.5');
    this.checkpointsRoot = path.join(this.modelRoot, 'checkpoints');
    this.markersRoot = path.join(this.modelRoot, 'installed');
    this.huggingFaceRoot = path.join(this.modelRoot, 'HuggingFace');
    this.installerRoot = path.join(applicationSupportRoot, 'Installer', 'Windows', 'ACE-Step-1.5');
    this.downloadsRoot = path.join(this.installerRoot, 'Downloads');
    this.toolsRoot = path.join(this.installerRoot, 'Tools');
    this.pythonRoot = path.join(applicationSupportRoot, 'Runtime', 'ACE-Python-Windows');
    this.uvCacheRoot = path.join(applicationSupportRoot, 'Cache', 'uv-ace-step-windows');
    this.installLogPath = path.join(this.installerRoot, 'ace-step-install.log');
    this.onProgress = onProgress;
    this.activeProcess = null;
    this.activeDownloadAbort = null;
    this.cancelRequested = false;
  }

  async initialize() {
    await Promise.all([
      fsp.mkdir(this.downloadsRoot, { recursive: true }),
      fsp.mkdir(this.checkpointsRoot, { recursive: true }),
      fsp.mkdir(this.markersRoot, { recursive: true }),
      fsp.mkdir(this.huggingFaceRoot, { recursive: true }),
    ]);
  }

  isInstalled(profile) {
    if (!profile?.ace || !this.#runtimeIsReady()) return false;
    const core = ['acestep-v15-turbo', 'vae', 'Qwen3-Embedding-0.6B'];
    if (!core.every((name) => this.#populatedDirectory(path.join(this.checkpointsRoot, name)))) return false;
    if (profile.ace.lm && !this.#populatedDirectory(path.join(this.checkpointsRoot, profile.ace.lm))) return false;
    if (profile.ace.dit !== 'acestep-v15-turbo'
      && !this.#populatedDirectory(path.join(this.checkpointsRoot, profile.ace.dit))) return false;
    return fs.existsSync(this.#markerPath(profile.id));
  }

  async install(profile) {
    if (process.platform !== 'win32') throw new Error('Установка ACE-Step доступна только в Windows.');
    if (!profile?.ace) throw new Error('Неизвестная конфигурация ACE-Step.');
    this.cancelRequested = false;
    await this.#checkDisk(profile);
    if (!this.#runtimeIsReady()) await this.#installRuntime();
    await this.#downloadModels(profile);
    await fsp.mkdir(this.markersRoot, { recursive: true });
    await fsp.writeFile(this.#markerPath(profile.id), JSON.stringify({
      model: profile.id, sourceRevision: SOURCE_REVISION, installedAt: new Date().toISOString(),
    }), { encoding: 'utf8', mode: 0o600 });
    if (!this.isInstalled(profile)) throw new Error('Не все файлы ACE-Step прошли проверку.');
    this.#progress('completed', 'Модель установлена и подключена', profile.title, 1);
  }

  async uninstall(profile, remainingProfiles = []) {
    if (!profile?.ace) return;
    await fsp.rm(this.#markerPath(profile.id), { force: true });
    if (!remainingProfiles.length) {
      await this.#removeValidated(this.runtimeRoot, this.applicationSupportRoot);
      await this.#removeValidated(this.modelRoot, this.applicationSupportRoot);
      await this.#removeValidated(this.pythonRoot, this.applicationSupportRoot);
      await fsp.mkdir(this.checkpointsRoot, { recursive: true });
      await fsp.mkdir(this.markersRoot, { recursive: true });
      return;
    }
    const used = new Set(remainingProfiles.flatMap((item) => [item.ace.dit, item.ace.lm].filter(Boolean)));
    for (const optional of [profile.ace.dit, profile.ace.lm].filter(Boolean)) {
      if (optional === 'acestep-v15-turbo' || optional === 'acestep-5Hz-lm-1.7B' || used.has(optional)) continue;
      await this.#removeValidated(path.join(this.checkpointsRoot, optional), this.checkpointsRoot);
    }
  }

  async uninstallAll() {
    this.cancel();
    await this.#waitForProcessExit();
    for (const target of [this.runtimeRoot, this.modelRoot, this.pythonRoot]) {
      await this.#removeValidated(target, this.applicationSupportRoot);
    }
    await fsp.mkdir(this.checkpointsRoot, { recursive: true });
    await fsp.mkdir(this.markersRoot, { recursive: true });
  }

  async generate(profile, { prompt, negativePrompt, durationSeconds, seed, outputPath }) {
    if (!this.isInstalled(profile)) throw new Error('Выбранная модель ACE-Step не установлена.');
    this.cancelRequested = false;
    const args = [
      this.#bridgePath(),
      '--prompt', String(prompt),
      '--negative-prompt', String(negativePrompt),
      '--model', profile.ace.dit,
      '--lm', profile.ace.lm || 'none',
      '--seconds', String(Math.min(Math.max(Number(durationSeconds) || 120, 10), 120)),
      '--steps', '8',
      '--seed', String(seed),
      '--out', outputPath,
    ];
    try {
      await this.#run(this.#pythonExecutable(), args, {
        cwd: this.runtimeRoot,
        env: this.#runtimeEnvironment(true),
        stage: 'локальная генерация ACE-Step',
      });
      if (!fs.existsSync(outputPath) || (await fsp.stat(outputPath)).size < 44) {
        throw new Error('ACE-Step не создал корректный WAV-файл.');
      }
      return outputPath;
    } catch (error) {
      await fsp.rm(outputPath, { force: true }).catch(() => {});
      throw error;
    }
  }

  cancel() {
    this.cancelRequested = true;
    this.activeDownloadAbort?.abort();
    const child = this.activeProcess;
    if (!child || child.exitCode !== null) return;
    if (process.platform === 'win32') {
      const killer = spawn('taskkill.exe', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true });
      killer.unref();
    } else child.kill('SIGTERM');
  }

  async #installRuntime() {
    this.#progress('preparing', 'Подготавливаю ACE-Step 1.5', 'Все компоненты останутся в папке Flowtone.', 0.05);
    await Promise.all([
      fsp.mkdir(this.downloadsRoot, { recursive: true }),
      fsp.mkdir(this.toolsRoot, { recursive: true }),
      fsp.mkdir(this.pythonRoot, { recursive: true }),
    ]);
    const uvZip = path.join(this.downloadsRoot, `uv-${UV_VERSION}-windows-x64.zip`);
    const sourceZip = path.join(this.downloadsRoot, `ACE-Step-1.5-${SOURCE_REVISION}.zip`);
    await this.#downloadVerified(
      `https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-pc-windows-msvc.zip`,
      uvZip, UV_WINDOWS_SHA256, 'системный помощник uv', 0.1,
    );
    await this.#downloadVerified(
      `https://github.com/ace-step/ACE-Step-1.5/archive/${SOURCE_REVISION}.zip`,
      sourceZip, SOURCE_SHA256, 'официальный ACE-Step 1.5', 0.18,
    );

    const uvExtract = path.join(this.toolsRoot, `uv-${UV_VERSION}`);
    await this.#removeValidated(uvExtract, this.toolsRoot);
    await fsp.mkdir(uvExtract, { recursive: true });
    await this.#expandArchive(uvZip, uvExtract);
    const uv = path.join(uvExtract, 'uv.exe');
    if (!fs.existsSync(uv)) throw new Error('Архив uv имеет неожиданную структуру.');

    const extraction = path.join(this.installerRoot, 'ExtractedSource');
    await this.#removeValidated(extraction, this.installerRoot);
    await fsp.mkdir(extraction, { recursive: true });
    await this.#expandArchive(sourceZip, extraction);
    const extracted = path.join(extraction, `ACE-Step-1.5-${SOURCE_REVISION}`);
    if (!fs.existsSync(path.join(extracted, 'uv.lock'))) throw new Error('Архив ACE-Step имеет неожиданную структуру.');
    await this.#removeValidated(this.runtimeRoot, this.applicationSupportRoot);
    await fsp.mkdir(path.dirname(this.runtimeRoot), { recursive: true });
    await fsp.rename(extracted, this.runtimeRoot);
    await fsp.copyFile(path.join(__dirname, 'flowtone_ace_bridge.py'), this.#bridgePath());

    this.#progress('installing', 'Устанавливаю PyTorch и ACE-Step', 'Без изменения системного Python и PATH.', 0.3);
    const env = this.#runtimeEnvironment(false, uvExtract);
    await this.#run(uv, ['sync', '--project', this.runtimeRoot, '--frozen', '--no-dev'], {
      cwd: this.runtimeRoot, env, stage: 'установка ACE-Step',
    });
    if (!this.#runtimeIsReady()) throw new Error('Локальный ACE-Step runtime установился не полностью.');
  }

  async #downloadModels(profile) {
    this.#progress('downloading-model', `Скачиваю ${profile.title}`, `Около ${profile.estimatedGiB.toLocaleString('ru-RU')} ГБ.`, 0.48);
    const common = ['-m', 'acestep.model_downloader', '--dir', this.checkpointsRoot];
    const env = this.#runtimeEnvironment(false);
    await this.#run(this.#pythonExecutable(), [...common, '--model', 'main'], {
      cwd: this.runtimeRoot, env, stage: 'загрузка основных весов ACE-Step',
    });
    const extras = [];
    if (profile.ace.lm && profile.ace.lm !== 'acestep-5Hz-lm-1.7B') extras.push(profile.ace.lm);
    if (profile.ace.dit !== 'acestep-v15-turbo') extras.push(profile.ace.dit);
    for (const model of extras) {
      await this.#run(this.#pythonExecutable(), [...common, '--model', model, '--skip-main'], {
        cwd: this.runtimeRoot, env, stage: `загрузка ${model}`,
      });
    }
    this.#progress('validating', 'Проверяю файлы ACE-Step', 'После проверки модель подключится автоматически.', 0.94);
  }

  #runtimeIsReady() {
    return fs.existsSync(this.#pythonExecutable())
      && fs.existsSync(path.join(this.runtimeRoot, 'acestep', 'api_server.py'))
      && fs.existsSync(this.#bridgePath());
  }

  #pythonExecutable() { return path.join(this.runtimeRoot, '.venv', 'Scripts', 'python.exe'); }
  #bridgePath() { return path.join(this.runtimeRoot, 'flowtone_ace_bridge.py'); }
  #markerPath(modelId) { return path.join(this.markersRoot, `${modelId}.json`); }

  #runtimeEnvironment(offline, uvBin = null) {
    const env = { ...process.env };
    delete env.HF_TOKEN;
    delete env.HUGGING_FACE_HUB_TOKEN;
    return {
      ...env,
      PATH: uvBin ? `${uvBin};${env.PATH || ''}` : env.PATH,
      PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8', TOKENIZERS_PARALLELISM: 'false',
      UV_PROJECT_ENVIRONMENT: path.join(this.runtimeRoot, '.venv'),
      UV_PYTHON_INSTALL_DIR: this.pythonRoot,
      UV_CACHE_DIR: this.uvCacheRoot,
      UV_NO_MODIFY_PATH: '1', UV_NO_PROGRESS: '1', UV_LINK_MODE: 'copy',
      ACESTEP_CHECKPOINTS_DIR: this.checkpointsRoot,
      HF_HOME: this.huggingFaceRoot,
      HF_HUB_DISABLE_IMPLICIT_TOKEN: '1',
      HF_HUB_OFFLINE: offline ? '1' : '0',
      TRANSFORMERS_OFFLINE: offline ? '1' : '0',
    };
  }

  #populatedDirectory(directory) {
    if (!fs.existsSync(directory)) return false;
    const pending = [directory];
    while (pending.length) {
      const current = pending.pop();
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const candidate = path.join(current, entry.name);
        if (entry.isDirectory()) pending.push(candidate);
        else if (entry.isFile() && fs.statSync(candidate).size > 1024) return true;
      }
    }
    return false;
  }

  async #checkDisk(profile) {
    await fsp.mkdir(this.applicationSupportRoot, { recursive: true });
    try {
      const stat = await fsp.statfs(this.applicationSupportRoot);
      const available = Number(stat.bavail) * Number(stat.bsize);
      const required = Math.ceil(profile.requiredFreeGiB || profile.estimatedGiB * 1.45) * 1024 ** 3;
      if (available < required) throw new Error(`Недостаточно места: нужно около ${Math.ceil(required / 1024 ** 3)} ГБ.`);
    } catch (error) {
      if (/Недостаточно места/.test(error.message)) throw error;
    }
  }

  async #downloadVerified(url, destination, expectedHash, label, fraction) {
    if (fs.existsSync(destination) && await sha256(destination) === expectedHash) return;
    await fsp.rm(destination, { force: true });
    this.#progress('downloading-runtime', `Скачиваю ${label}`, 'Перед запуском Flowtone проверит SHA-256.', fraction);
    const controller = new AbortController();
    this.activeDownloadAbort = controller;
    try {
      const response = await fetch(url, { redirect: 'follow', signal: controller.signal });
      if (!response.ok || !response.body) throw new Error(`Не удалось скачать ${label}.`);
      await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(destination, { mode: 0o600 }));
    } catch (error) {
      await fsp.rm(destination, { force: true });
      if (this.cancelRequested) throw new Error('Операция отменена.');
      throw error;
    } finally {
      if (this.activeDownloadAbort === controller) this.activeDownloadAbort = null;
    }
    if (await sha256(destination) !== expectedHash) {
      await fsp.rm(destination, { force: true });
      throw new Error(`Проверка ${label} не пройдена. Файл удалён.`);
    }
  }

  async #expandArchive(archive, destination) {
    const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;
    await this.#run('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-Command',
      `Expand-Archive -LiteralPath ${quote(archive)} -DestinationPath ${quote(destination)} -Force`,
    ], { stage: 'распаковка архива' });
  }

  async #run(executable, args, options = {}) {
    await fsp.mkdir(this.installerRoot, { recursive: true });
    const log = fs.createWriteStream(this.installLogPath, { flags: 'a', mode: 0o600 });
    log.write(`\n[${new Date().toISOString()}] ${options.stage || 'операция'}\n`);
    return new Promise((resolve, reject) => {
      const child = spawn(executable, args, {
        cwd: options.cwd || this.installerRoot,
        env: options.env || process.env,
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      this.activeProcess = child;
      let stderr = '';
      let stdout = '';
      child.stdout.on('data', (chunk) => { stdout = `${stdout}${chunk}`.slice(-4000); log.write(chunk); });
      child.stderr.on('data', (chunk) => { stderr = `${stderr}${chunk}`.slice(-4000); log.write(chunk); });
      child.once('error', (error) => { log.end(); reject(error); });
      child.once('exit', (code) => {
        log.end();
        if (this.activeProcess === child) this.activeProcess = null;
        if (this.cancelRequested) return reject(new Error('Операция отменена.'));
        if (code === 0) return resolve(stdout);
        reject(new Error(`${options.stage || 'Операция'} завершилась с ошибкой: ${sanitize(stderr || stdout)}`));
      });
    });
  }

  async #waitForProcessExit() {
    const child = this.activeProcess;
    if (!child || child.exitCode !== null) return;
    await Promise.race([
      new Promise((resolve) => child.once('exit', resolve)),
      new Promise((resolve) => setTimeout(resolve, 5000)),
    ]);
  }

  async #removeValidated(target, allowedRoot) {
    const resolvedTarget = path.resolve(target);
    const resolvedRoot = path.resolve(allowedRoot);
    if (resolvedTarget === resolvedRoot || !resolvedTarget.startsWith(`${resolvedRoot}${path.sep}`)) {
      throw new Error('Небезопасный путь удаления заблокирован.');
    }
    await fsp.rm(resolvedTarget, { recursive: true, force: true });
  }

  #progress(phase, title, detail, fraction) {
    this.onProgress({ phase, title, detail, fraction });
  }
}

async function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  await pipeline(fs.createReadStream(filePath), hash);
  return hash.digest('hex');
}

function sanitize(value) {
  return String(value || '').replace(/hf_[A-Za-z0-9]{8,}/g, '[скрыто]').replace(/\s+/g, ' ').trim().slice(-900);
}

module.exports = { ACEStepRuntime, SOURCE_REVISION, SOURCE_SHA256 };
