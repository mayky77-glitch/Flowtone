'use strict';

const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { Readable } = require('node:stream');
const { pipeline } = require('node:stream/promises');
const { ACEStepRuntime } = require('./ace-runtime.cjs');

const SOURCE_REVISION = 'a0b57f5483c4588f827f3552b7d5c6ca2a9687be';
const SOURCE_SHA256 = '57c5f639e4e55ec2357cd193cc40ebf7749e4478dc01ef26ce2c541ed1ece380';
const UV_VERSION = '0.12.5';
const UV_WINDOWS_SHA256 = '4c4d49d8738847d9b71ba319e49a5688c93eac0fe6204b1df24e98528dddf39a';
const TOKENIZER_RELATIVE_PATH = 'models/tokenizer.model';
const TOKENIZER_SHA256 = '61a7b147390c64585d6c3543dd6fc636906c9af3865a5548f27f31aee1d4c8e2';
const TOKENIZER_REMOTE_URL = `https://raw.githubusercontent.com/Stability-AI/stable-audio-3/${SOURCE_REVISION}/optimized/tflite/${TOKENIZER_RELATIVE_PATH}`;
const TOKENIZER_COMPATIBILITY_MARKER = 'LoadFromSerializedProto(model_path.read_bytes())';
const DEFAULT_MODEL_ID = 'small-efficient';

const MODEL_PROFILES = {
  'small-efficient': {
    id: 'small-efficient', title: 'Stable Audio 3 Small · экономная',
    detail: 'Для 8–12 ГБ памяти и небольшого числа ядер',
    family: 'stable-audio', group: 'compact', dit: 'sm-music', decoder: 'same-s',
    precision: 'w8a8-dyn', estimatedGiB: 1.2, requiredFreeGiB: 4,
    better: 'База: самая экономная и предсказуемая для фоновой работы.',
    worse: 'Проще аранжировки и меньше деталей, чем у тяжёлых моделей.',
  },
  'small-quality': {
    id: 'small-quality', title: 'Stable Audio 3 Small · точная',
    detail: 'Для среднего ПК с 12–24 ГБ памяти',
    family: 'stable-audio', group: 'balanced', dit: 'sm-music', decoder: 'same-s',
    precision: 'fp32', estimatedGiB: 2.9, requiredFreeGiB: 6,
    better: 'Лучше экономной: чище детали и меньше потерь от квантования.',
    worse: 'Хуже экономной: медленнее и требует больше RAM.',
  },
  'medium-balanced': {
    id: 'medium-balanced', title: 'Stable Audio 3 Medium · оптимальная',
    detail: 'Для мощного ПК с 24+ ГБ памяти и 12+ потоками CPU',
    family: 'stable-audio', group: 'powerful', dit: 'medium', decoder: 'same-l',
    precision: 'w8a32', estimatedGiB: 3.2, requiredFreeGiB: 7,
    better: 'Лучше Small: плотнее слои, пространство и длинное развитие.',
    worse: 'Хуже Small: заметно медленнее и тяжелее для CPU.',
  },
  'medium-max': {
    id: 'medium-max', title: 'Stable Audio 3 Medium · максимум',
    detail: 'Для ПК с 32+ ГБ памяти и 16+ потоками CPU',
    family: 'stable-audio', group: 'powerful', dit: 'medium', decoder: 'same-l',
    precision: 'fp32', estimatedGiB: 8.8, requiredFreeGiB: 13,
    better: 'Лучше оптимальной: максимум точности без квантования.',
    worse: 'Хуже оптимальной: самая медленная Stable-конфигурация.',
  },
  'ace-turbo': {
    id: 'ace-turbo', title: 'ACE-Step 1.5 Turbo · без LM',
    detail: 'Амбициозная полная форма для 8+ ГБ RAM; CPU/GPU с offload',
    family: 'ace-step', group: 'compact', estimatedGiB: 10, requiredFreeGiB: 16,
    ambitious: true, ace: { dit: 'acestep-v15-turbo', lm: null },
    better: 'Лучше базы: длиннее форма и смелее жанровые переходы.',
    worse: 'Хуже базы: загрузка намного больше, первый старт дольше.',
  },
  'ace-lite': {
    id: 'ace-lite', title: 'ACE-Step 1.5 Turbo · LM 0,6B',
    detail: 'Для 16+ ГБ RAM или GPU от 6 ГБ',
    family: 'ace-step', group: 'balanced', estimatedGiB: 11.5, requiredFreeGiB: 18,
    ambitious: true, ace: { dit: 'acestep-v15-turbo', lm: 'acestep-5Hz-lm-0.6B' },
    better: 'Лучше базы: точнее понимает идею, темп и строение композиции.',
    worse: 'Хуже базы: тяжелее, медленнее и может использовать offload.',
  },
  'ace-pro': {
    id: 'ace-pro', title: 'ACE-Step 1.5 Turbo · LM 1,7B',
    detail: 'Для 24+ ГБ RAM или GPU от 12 ГБ',
    family: 'ace-step', group: 'powerful', estimatedGiB: 14, requiredFreeGiB: 21,
    ambitious: true, ace: { dit: 'acestep-v15-turbo', lm: 'acestep-5Hz-lm-1.7B' },
    better: 'Лучше базы: сложнее структура и выразительнее развитие.',
    worse: 'Хуже базы: дольше генерация и выше фоновая нагрузка.',
  },
  'ace-max': {
    id: 'ace-max', title: 'ACE-Step 1.5 XL · LM 4B',
    detail: 'Для 32+ ГБ RAM и GPU от 24 ГБ',
    family: 'ace-step', group: 'powerful', estimatedGiB: 27, requiredFreeGiB: 38,
    ambitious: true, ace: { dit: 'acestep-v15-xl-turbo', lm: 'acestep-5Hz-lm-4B' },
    better: 'Лучше базы: максимум структуры, деталей и следования задумке.',
    worse: 'Хуже базы: огромная модель; требует мощную GPU и много времени.',
  },
};

const MODEL_GROUPS = [
  { id: 'compact', title: 'КОМПАКТНЫЙ ПК', requirement: '8–15 ГБ RAM', modelIds: ['small-efficient', 'small-quality', 'ace-turbo'] },
  { id: 'balanced', title: 'СБАЛАНСИРОВАННЫЙ ПК', requirement: '16–23 ГБ RAM', modelIds: ['small-quality', 'ace-turbo', 'ace-lite'] },
  { id: 'powerful', title: 'МОЩНЫЙ ПК', requirement: '24+ ГБ RAM / производительная GPU', modelIds: ['medium-balanced', 'medium-max', 'ace-pro', 'ace-max'] },
];

function recommendGroup(hardware) {
  const memory = Number(hardware.memoryGiB) || 0;
  if (memory >= 24) return 'powerful';
  if (memory >= 16) return 'balanced';
  return 'compact';
}

function recommendModel(hardware) {
  const memory = Number(hardware.memoryGiB) || 0;
  const threads = Number(hardware.logicalCores) || 0;
  const gpuMemory = Number(hardware.gpuMemoryGiB) || 0;
  const nvidia = /nvidia/i.test(String(hardware.gpu || ''));
  if (nvidia && memory >= 32 && gpuMemory >= 24) return 'ace-max';
  if (nvidia && memory >= 24 && gpuMemory >= 12) return 'ace-pro';
  if (nvidia && memory >= 16 && gpuMemory >= 6) return 'ace-lite';
  if (memory >= 32 && threads >= 16) return 'medium-max';
  if (memory >= 24 && threads >= 12) return 'medium-balanced';
  if (memory >= 12 && threads >= 6) return 'small-quality';
  return 'small-efficient';
}

class StableAudioRuntime {
  constructor(applicationSupportRoot, onProgress = () => {}) {
    this.applicationSupportRoot = applicationSupportRoot;
    this.runtimeRoot = path.join(applicationSupportRoot, 'Runtime', 'stable-audio-3-tflite');
    this.modelsRoot = path.join(applicationSupportRoot, 'Models', 'Windows');
    this.installerRoot = path.join(applicationSupportRoot, 'Installer', 'Windows');
    this.downloadsRoot = path.join(this.installerRoot, 'Downloads');
    this.toolsRoot = path.join(this.installerRoot, 'Tools');
    this.pythonRoot = path.join(applicationSupportRoot, 'Runtime', 'Python-Windows');
    this.manifestPath = path.join(this.installerRoot, 'runtime-manifest.json');
    this.onProgress = onProgress;
    this.activeProcess = null;
    this.activeDownloadAbort = null;
    this.installing = false;
    this.generating = false;
    this.cancelRequested = false;
    this.hardware = null;
    this.stableRuntimeRepairError = null;
    this.aceRuntime = new ACEStepRuntime(applicationSupportRoot, onProgress);
  }

  async initialize(hardware) {
    this.hardware = hardware;
    await Promise.all([
      fsp.mkdir(this.downloadsRoot, { recursive: true }),
      fsp.mkdir(this.modelsRoot, { recursive: true }),
    ]);
    try {
      await this.#repairStableRuntimeCompatibility();
      this.stableRuntimeRepairError = null;
    } catch (error) {
      this.stableRuntimeRepairError = sanitizeProcessError(error?.message || error);
    }
    return this.status();
  }

  async status(preference = 'auto') {
    const hardware = this.hardware || basicHardwareProfile();
    const defaultProfile = MODEL_PROFILES[DEFAULT_MODEL_ID];
    const installedModels = this.#profileIsInstalled(defaultProfile) ? [DEFAULT_MODEL_ID] : [];
    const connectedModel = installedModels.includes(DEFAULT_MODEL_ID) ? DEFAULT_MODEL_ID : null;
    const stableRuntime = stableRuntimeHealth(this.runtimeRoot, this.#pythonExecutable());
    return {
      supported: process.platform === 'win32',
      runtimeReady: connectedModel !== null,
      recommendedModel: DEFAULT_MODEL_ID,
      connectedModel,
      installedModels,
      models: [defaultProfile],
      modelGroups: [{
        id: 'default', title: 'ДЕФОЛТНАЯ МОДЕЛЬ', requirement: 'экономный локальный режим', modelIds: [DEFAULT_MODEL_ID],
      }],
      recommendedGroup: 'default',
      installing: this.installing,
      generating: this.generating,
      runtimePath: this.runtimeRoot,
      stableRuntimeRepairNeeded: stableRuntime.repairNeeded || Boolean(this.stableRuntimeRepairError),
      stableRuntimeRepairDetail: this.stableRuntimeRepairError || stableRuntime.missingFiles.join(', '),
      hardware,
    };
  }

  async installModel(modelId) {
    const profile = MODEL_PROFILES[modelId];
    if (!profile) throw new Error('Неизвестный профиль модели.');
    if (modelId !== DEFAULT_MODEL_ID) {
      throw new Error('В этой версии Flowtone доступна только минимальная Stable Audio 3 Small.');
    }
    if (process.platform !== 'win32') throw new Error('Установка Windows-модели доступна только в Windows.');
    if (this.installing || this.generating) throw new Error('Другая операция с моделью уже выполняется.');
    this.installing = true;
    this.cancelRequested = false;
    try {
      if (profile.family === 'ace-step') {
        await this.aceRuntime.install(profile);
        this.#progress('completed', 'Модель установлена и подключена', profile.title, 1);
        return this.status(modelId);
      }
      await this.#checkDisk(profile);
      if (!this.#runtimeIsReady()) await this.#installRuntime();
      await this.#downloadModel(profile);
      if (!this.#profileIsInstalled(profile)) throw new Error('Не все файлы модели прошли проверку.');
      await this.#writeManifest();
      this.#progress('completed', 'Модель установлена и подключена', profile.title, 1);
      return this.status(modelId);
    } finally {
      this.installing = false;
      this.activeProcess = null;
      this.activeDownloadAbort = null;
    }
  }

  async uninstallModel(modelId) {
    const profile = MODEL_PROFILES[modelId];
    if (!profile) throw new Error('Неизвестный профиль модели.');
    if (modelId !== DEFAULT_MODEL_ID) {
      throw new Error('В этой версии можно удалить только дефолтную модель.');
    }
    this.cancel();
    await this.#waitForProcessExit();
    if (profile.family === 'ace-step') {
      const remaining = Object.values(MODEL_PROFILES).filter((item) =>
        item.family === 'ace-step' && item.id !== modelId && this.aceRuntime.isInstalled(item));
      await this.aceRuntime.uninstall(profile, remaining);
      await this.#writeManifest();
      return this.status('auto');
    }
    for (const relativePath of this.#requiredRelativePaths(profile)) {
      if (relativePath.includes('/t5gemma/') && this.#otherInstalledModels(modelId).length) continue;
      await this.#removeValidated(path.join(this.runtimeRoot, ...relativePath.split('/')), this.runtimeRoot);
    }
    await this.#removeValidated(path.join(this.modelsRoot, modelId), this.modelsRoot);
    if (!this.#otherInstalledModels(modelId).length) {
      await this.#removeValidated(path.join(this.modelsRoot, '_shared'), this.modelsRoot);
    }
    await this.#writeManifest();
    return this.status('auto');
  }

  async uninstallAllModels() {
    this.cancel();
    await this.#waitForProcessExit();
    for (const profile of Object.values(MODEL_PROFILES).filter((item) => item.family === 'stable-audio')) {
      for (const relativePath of this.#requiredRelativePaths(profile)) {
        await this.#removeValidated(path.join(this.runtimeRoot, ...relativePath.split('/')), this.runtimeRoot);
      }
    }
    await this.#removeValidated(this.modelsRoot, this.applicationSupportRoot);
    await fsp.mkdir(this.modelsRoot, { recursive: true });
    await this.aceRuntime.uninstallAll();
    await this.#writeManifest();
    return this.status('auto');
  }

  async generate({ modelId, prompt, negativePrompt, durationSeconds, seed, outputPath }) {
    const profile = MODEL_PROFILES[modelId];
    if (modelId !== DEFAULT_MODEL_ID) {
      throw new Error('Текущая версия Flowtone генерирует только через Stable Audio 3 Small.');
    }
    if (!profile || !this.#profileIsInstalled(profile)) throw new Error('Выбранная модель не установлена.');
    if (this.generating || this.installing) throw new Error('Модель уже занята.');
    if (os.freemem() < 1.25 * 1024 ** 3) throw new Error('Генерация отложена: Windows не хватает свободной памяти.');
    this.generating = true;
    this.cancelRequested = false;
    if (profile.family === 'ace-step') {
      try {
        return await this.aceRuntime.generate(profile, {
          prompt, negativePrompt, durationSeconds, seed, outputPath,
        });
      } finally {
        this.generating = false;
      }
    }
    const python = this.#pythonExecutable();
    const script = path.join(this.runtimeRoot, 'scripts', 'sa3_tflite.py');
    const threads = Math.min(8, Math.max(2, Math.floor((this.hardware?.logicalCores || os.cpus().length) / 2)));
    try {
      await this.#run(python, [
        script,
        '--prompt', String(prompt),
        '--negative-prompt', String(negativePrompt),
        '--dit', profile.dit,
        '--decoder', profile.decoder,
        '--precision', profile.precision,
        '--seconds', String(Math.min(Math.max(Number(durationSeconds) || 120, 1), 120)),
        '--steps', '8',
        '--seed', String(seed),
        '--threads', String(threads),
        '--free-models',
        '--out', outputPath,
      ], {
        cwd: this.runtimeRoot,
        env: this.#runtimeEnvironment(modelId, true),
        stage: 'локальная генерация',
      });
      if (!fs.existsSync(outputPath) || (await fsp.stat(outputPath)).size < 44) {
        throw new Error('Движок не создал корректный WAV-файл.');
      }
      return outputPath;
    } catch (error) {
      await fsp.rm(outputPath, { force: true }).catch(() => {});
      throw error;
    } finally {
      this.generating = false;
      this.activeProcess = null;
    }
  }

  cancelGeneration() {
    if (!this.generating) return false;
    this.#cancelActiveOperation();
    return true;
  }

  cancelInstallation() {
    if (!this.installing) return false;
    this.#cancelActiveOperation();
    return true;
  }

  cancel() {
    this.#cancelActiveOperation();
    return true;
  }

  #cancelActiveOperation() {
    this.cancelRequested = true;
    this.activeDownloadAbort?.abort();
    this.aceRuntime.cancel();
    const child = this.activeProcess;
    if (!child || child.exitCode !== null) return;
    if (process.platform === 'win32') {
      const killer = spawn('taskkill.exe', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true });
      killer.unref();
    } else {
      child.kill('SIGTERM');
    }
  }

  async #installRuntime() {
    this.#progress('preparing', 'Подготавливаю локальный движок', 'Все файлы останутся в папке Flowtone.', 0.05);
    await Promise.all([
      fsp.mkdir(this.downloadsRoot, { recursive: true }), fsp.mkdir(this.toolsRoot, { recursive: true }),
      fsp.mkdir(this.pythonRoot, { recursive: true }),
    ]);
    const uvZip = path.join(this.downloadsRoot, `uv-${UV_VERSION}-windows-x64.zip`);
    const sourceZip = path.join(this.downloadsRoot, `stable-audio-3-${SOURCE_REVISION}.zip`);
    await this.#downloadVerified(
      `https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-pc-windows-msvc.zip`,
      uvZip, UV_WINDOWS_SHA256, 'системный помощник uv', 0.1,
    );
    await this.#downloadVerified(
      `https://github.com/Stability-AI/stable-audio-3/archive/${SOURCE_REVISION}.zip`,
      sourceZip, SOURCE_SHA256, 'официальный Stable Audio 3', 0.22,
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
    const sourceTflite = path.join(extraction, `stable-audio-3-${SOURCE_REVISION}`, 'optimized', 'tflite');
    if (!fileHasContent(path.join(sourceTflite, 'scripts', 'sa3_tflite.py'))
      || !fileHasContent(path.join(sourceTflite, TOKENIZER_RELATIVE_PATH))) {
      throw new Error('Архив Stable Audio 3 имеет неожиданную структуру.');
    }
    await this.#removeValidated(this.runtimeRoot, this.applicationSupportRoot);
    await fsp.mkdir(path.dirname(this.runtimeRoot), { recursive: true });
    await fsp.rename(sourceTflite, this.runtimeRoot);
    await this.#removeValidated(extraction, this.installerRoot);
    await this.#patchTokenizerLoading();

    this.#progress('installing', 'Устанавливаю Python и LiteRT', 'Без изменения системного Python и PATH.', 0.34);
    const env = {
      ...process.env,
      UV_PYTHON_INSTALL_DIR: this.pythonRoot,
      UV_CACHE_DIR: path.join(this.applicationSupportRoot, 'Cache', 'uv-windows'),
      UV_NO_MODIFY_PATH: '1', UV_NO_PROGRESS: '1', UV_LINK_MODE: 'copy',
    };
    const venv = path.join(this.runtimeRoot, '.venv');
    await this.#run(uv, ['venv', '--seed', '--python', '3.11', venv], { env, stage: 'подготовка Python' });
    await this.#run(uv, ['pip', 'install', '--python', this.#pythonExecutable(), '-r', path.join(this.runtimeRoot, 'requirements.txt')], {
      env, stage: 'установка LiteRT',
    });
    if (!this.#runtimeIsReady()) throw new Error('Локальный LiteRT runtime установился не полностью.');
  }

  async #downloadModel(profile) {
    this.#progress('downloading-model', `Скачиваю ${profile.title}`, `Около ${profile.estimatedGiB.toLocaleString('ru-RU')} ГБ; загрузку можно отменить и продолжить позже.`, 0.48);
    const required = this.#requiredRelativePaths(profile);
    await this.#downloadModelFiles(required.filter((item) => item.includes('/t5gemma/')), '_shared');
    await this.#downloadModelFiles(required.filter((item) => !item.includes('/t5gemma/')), profile.id);
    this.#progress('validating', 'Проверяю файлы модели', 'После проверки модель подключится автоматически.', 0.94);
  }

  async #downloadModelFiles(items, cacheID) {
    const scripts = JSON.stringify(path.join(this.runtimeRoot, 'scripts'));
    const pythonCode = [
      'import sys',
      `sys.path.insert(0,${scripts})`,
      'from weights import ensure_local',
      `items=[${items.map((item) => JSON.stringify(item)).join(',')}]`,
      '[ensure_local(item) for item in items]',
      'print("FLOWTONE_MODEL_READY")',
    ].join(';');
    await this.#run(this.#pythonExecutable(), ['-c', pythonCode], {
      cwd: this.runtimeRoot,
      env: this.#runtimeEnvironment(cacheID, false),
      stage: 'загрузка весов модели',
    });
  }

  #requiredRelativePaths(profile) {
    if (profile.family !== 'stable-audio') return [];
    const ditDirectory = profile.dit === 'medium' ? 'sa3-m' : 'sa3-sm-music';
    return [
      'models/tflite/t5gemma/encoder_fp16.tflite',
      `models/tflite/${ditDirectory}/dit_${profile.precision}.tflite`,
      `models/tflite/${profile.decoder}/dec_${profile.precision}.tflite`,
    ];
  }

  #profileIsInstalled(profile) {
    if (profile.family === 'ace-step') return this.aceRuntime.isInstalled(profile);
    return this.#runtimeIsReady() && this.#requiredRelativePaths(profile)
      .every((relative) => {
        const candidate = path.join(this.runtimeRoot, ...relative.split('/'));
        try { return fs.statSync(candidate).size > 0; } catch { return false; }
      });
  }

  #otherInstalledModels(excludingId) {
    return Object.values(MODEL_PROFILES).filter((profile) =>
      profile.family === 'stable-audio' && profile.id !== excludingId && this.#profileIsInstalled(profile));
  }

  #runtimeIsReady() {
    return stableRuntimeHealth(this.runtimeRoot, this.#pythonExecutable()).ready;
  }

  #pythonExecutable() {
    return path.join(this.runtimeRoot, '.venv', 'Scripts', 'python.exe');
  }

  #runtimeEnvironment(modelId, offline) {
    const modelRoot = path.join(this.modelsRoot, modelId);
    const environment = { ...process.env };
    delete environment.HF_TOKEN;
    delete environment.HUGGING_FACE_HUB_TOKEN;
    return {
      ...environment,
      PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8',
      HF_HOME: path.join(modelRoot, 'HuggingFace'),
      HF_HUB_DISABLE_IMPLICIT_TOKEN: '1',
      HF_HUB_DISABLE_PROGRESS_BARS: '0',
      HF_HUB_OFFLINE: offline ? '1' : '0',
      TRANSFORMERS_OFFLINE: offline ? '1' : '0',
      TOKENIZERS_PARALLELISM: 'false',
    };
  }

  async #repairStableRuntimeCompatibility() {
    const pipelinePath = path.join(this.runtimeRoot, 'models', 'defs', 'tflite_pipeline.py');
    if (!fileHasContent(pipelinePath)) return;
    await this.#patchTokenizerLoading();

    const tokenizerPath = path.join(this.runtimeRoot, TOKENIZER_RELATIVE_PATH);
    if (fileHasContent(tokenizerPath) || !this.#runtimeCanRepairTokenizer()) return;
    this.#progress('repairing-runtime', 'Восстанавливаю текстовый модуль', 'Докачиваю обязательный файл Stable Audio 3.', 0.18);
    await fsp.mkdir(path.dirname(tokenizerPath), { recursive: true });
    const temporary = `${tokenizerPath}.download`;
    await this.#downloadVerified(
      TOKENIZER_REMOTE_URL, temporary, TOKENIZER_SHA256, 'официальный tokenizer Stable Audio 3', 0.22,
    );
    await fsp.rm(tokenizerPath, { force: true });
    await fsp.rename(temporary, tokenizerPath);
  }

  async #patchTokenizerLoading() {
    const pipelinePath = path.join(this.runtimeRoot, 'models', 'defs', 'tflite_pipeline.py');
    if (!fileHasContent(pipelinePath)) return;
    const source = await fsp.readFile(pipelinePath, 'utf8');
    if (source.includes(TOKENIZER_COMPATIBILITY_MARKER)) return;
    const original = '        self.sp = spm.SentencePieceProcessor()\n        self.sp.LoadFromFile(str(model_path))';
    if (!source.includes(original)) {
      throw new Error('Не удалось применить совместимость tokenizer для Windows. Переустановите модель.');
    }
    const replacement = `        self.sp = spm.SentencePieceProcessor()\n        self.sp.${TOKENIZER_COMPATIBILITY_MARKER}`;
    const temporary = `${pipelinePath}.flowtone-new`;
    await fsp.writeFile(temporary, source.replace(original, replacement), { encoding: 'utf8', mode: 0o600 });
    await fsp.rm(pipelinePath, { force: true });
    await fsp.rename(temporary, pipelinePath);
  }

  #runtimeCanRepairTokenizer() {
    return [
      this.#pythonExecutable(),
      path.join(this.runtimeRoot, 'scripts', 'sa3_tflite.py'),
      path.join(this.runtimeRoot, 'models', 'defs', 'tflite_pipeline.py'),
    ].every(fileHasContent);
  }

  async #downloadVerified(url, destination, expectedHash, label, fraction) {
    if (fs.existsSync(destination) && await sha256(destination) === expectedHash) return;
    await fsp.rm(destination, { force: true });
    this.#progress('downloading-runtime', `Скачиваю ${label}`, 'Перед запуском Flowtone проверит SHA-256.', fraction);
    const controller = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; controller.abort(); }, 10 * 60 * 1000);
    timeout.unref();
    this.activeDownloadAbort = controller;
    try {
      const response = await fetch(url, { redirect: 'follow', signal: controller.signal });
      if (!response.ok || !response.body) throw new Error(`Не удалось скачать ${label}.`);
      await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(destination, { mode: 0o600 }));
    } catch (error) {
      await fsp.rm(destination, { force: true });
      if (this.cancelRequested) throw new Error('Операция отменена.');
      if (timedOut) throw new Error(`Не удалось скачать ${label}: превышено время ожидания.`);
      throw error;
    } finally {
      clearTimeout(timeout);
      if (this.activeDownloadAbort === controller) this.activeDownloadAbort = null;
    }
    if (await sha256(destination) !== expectedHash) {
      await fsp.rm(destination, { force: true });
      throw new Error(`Проверка ${label} не пройдена. Файл удалён.`);
    }
  }

  async #expandArchive(archive, destination) {
    const literal = (value) => `'${value.replaceAll("'", "''")}'`;
    await this.#run('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command',
      `Expand-Archive -LiteralPath ${literal(archive)} -DestinationPath ${literal(destination)} -Force`,
    ], { stage: 'распаковка архива' });
  }

  async #checkDisk(profile) {
    const available = await freeDiskBytes(this.applicationSupportRoot);
    const required = Math.ceil((profile.estimatedGiB + (this.#runtimeIsReady() ? 1 : 3)) * 1024 ** 3);
    if (available !== null && available < required) {
      throw new Error(`Для установки нужно около ${(required / 1024 ** 3).toFixed(1)} ГБ свободного места.`);
    }
  }

  async #run(executable, args, options = {}) {
    if (this.cancelRequested) throw new Error('Операция отменена.');
    return new Promise((resolve, reject) => {
      const child = spawn(executable, args, {
        cwd: options.cwd,
        env: options.env || process.env,
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      this.activeProcess = child;
      let stderr = '';
      let stdout = '';
      child.stdout.on('data', (chunk) => { stdout = `${stdout}${chunk}`.slice(-4000); });
      child.stderr.on('data', (chunk) => { stderr = `${stderr}${chunk}`.slice(-4000); });
      child.once('error', (error) => reject(new Error(`Не удалось запустить этап «${options.stage || 'подготовка'}»: ${error.message}`)));
      child.once('exit', (code) => {
        if (this.cancelRequested) return reject(new Error('Операция отменена.'));
        if (code === 0) return resolve(stdout);
        const message = sanitizeProcessError(stderr || stdout);
        reject(new Error(`Этап «${options.stage || 'подготовка'}» завершился с ошибкой${message ? `: ${message}` : '.'}`));
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

  async #writeManifest() {
    await fsp.mkdir(this.installerRoot, { recursive: true });
    const manifest = {
      schema: 1, sourceRevision: SOURCE_REVISION, uvVersion: UV_VERSION,
      installedModels: Object.values(MODEL_PROFILES).filter((profile) => this.#profileIsInstalled(profile)).map((profile) => profile.id),
      updatedAt: new Date().toISOString(),
    };
    const temp = `${this.manifestPath}.tmp`;
    await fsp.writeFile(temp, JSON.stringify(manifest, null, 2), { encoding: 'utf8', mode: 0o600 });
    await fsp.rename(temp, this.manifestPath);
  }

  #progress(phase, title, detail, fraction) {
    this.onProgress({ phase, title, detail, fraction });
  }
}

function basicHardwareProfile() {
  return {
    memoryGiB: Math.max(1, Math.round(os.totalmem() / 1024 ** 3)),
    logicalCores: os.cpus().length,
    cpu: os.cpus()[0]?.model?.trim() || 'Неизвестный CPU',
    gpu: 'Видеоадаптер определяется',
  };
}

async function sha256(filePath) {
  const hash = crypto.createHash('sha256');
  await pipeline(fs.createReadStream(filePath), hash);
  return hash.digest('hex');
}

async function freeDiskBytes(target) {
  try {
    const stat = await fsp.statfs(target);
    return Number(stat.bavail) * Number(stat.bsize);
  } catch {
    return null;
  }
}

function sanitizeProcessError(value) {
  return String(value || '').replace(/hf_[A-Za-z0-9]{8,}/g, '[скрыто]')
    .replace(/\s+/g, ' ').trim().slice(-900);
}

function fileHasContent(filePath) {
  try { return fs.statSync(filePath).isFile() && fs.statSync(filePath).size > 0; } catch { return false; }
}

function stableRuntimeHealth(runtimeRoot, pythonExecutable = path.join(runtimeRoot, '.venv', 'Scripts', 'python.exe')) {
  const required = [
    ['Python', pythonExecutable],
    ['скрипт генерации', path.join(runtimeRoot, 'scripts', 'sa3_tflite.py')],
    ['tokenizer.model', path.join(runtimeRoot, TOKENIZER_RELATIVE_PATH)],
    ['модуль tokenizer', path.join(runtimeRoot, 'models', 'defs', 'tflite_pipeline.py')],
  ];
  const missingFiles = required.filter(([, filePath]) => !fileHasContent(filePath)).map(([label]) => label);
  const pipelinePath = path.join(runtimeRoot, 'models', 'defs', 'tflite_pipeline.py');
  if (!missingFiles.includes('модуль tokenizer')) {
    try {
      if (!fs.readFileSync(pipelinePath, 'utf8').includes(TOKENIZER_COMPATIBILITY_MARKER)) {
        missingFiles.push('совместимость пути Windows');
      }
    } catch {
      missingFiles.push('совместимость пути Windows');
    }
  }
  return {
    ready: missingFiles.length === 0,
    repairNeeded: fs.existsSync(runtimeRoot) && missingFiles.length > 0,
    missingFiles,
  };
}

module.exports = {
  DEFAULT_MODEL_ID, MODEL_GROUPS, MODEL_PROFILES, StableAudioRuntime, basicHardwareProfile, recommendGroup, recommendModel,
  stableRuntimeHealth,
};
