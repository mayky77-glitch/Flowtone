'use strict';

const api = window.flowtone;

const state = {
  settings: null,
  tracks: [],
  statistics: { trackCount: 0, likedTrackCount: 0, byteSize: 0, genres: [] },
  runtime: null,
  hardware: null,
  genres: [],
  genreLabels: {},
  currentTrackId: null,
  readyTrackIds: [],
  history: [],
  historyIndex: -1,
  isGenerating: false,
  isWindowVisible: true,
  libraryFilter: 'all',
  libraryTab: 'tracks',
  visualAngleOffset: 0,
  draggingVinyl: false,
  dragAngle: null,
  dragVisualAngle: 0,
  dragPosition: 0,
  sliderDragging: false,
  lastFrameAt: 0,
  lastMarqueeAt: 0,
  lastMediaSessionAt: 0,
  marqueeOffset: 0,
  marqueeDirection: -1,
  marqueePauseUntil: 0,
  animationFrame: null,
  generationTimer: null,
  lastScratchAt: 0,
  scratchRequest: 0,
  confirmResolver: null,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const elements = {
  genreGrid: $('#genre-grid'),
  shuffle: $('#shuffle-toggle'),
  mix: $('#mix-toggle'),
  mood: $('#mood-select'),
  vibe: $('#vibe-input'),
  generation: $('#generation-toggle'),
  modelBadge: $('#model-badge'),
  modelName: $('#model-name'),
  modelStatus: $('#model-status'),
  librarySummary: $('#library-summary'),
  likedSummary: $('#liked-summary'),
  vinylScene: $('#vinyl-scene'),
  vinylRecord: $('#vinyl-record'),
  vinylGenre: $('#vinyl-genre'),
  tonearm: $('#tonearm'),
  title: $('#track-title'),
  status: $('#status-text'),
  airLabel: $('#air-label'),
  position: $('#position-slider'),
  currentTime: $('#time-current'),
  duration: $('#time-duration'),
  play: $('#play-button'),
  previous: $('#previous-button'),
  next: $('#next-button'),
  like: $('#like-button'),
  deleteCurrent: $('#delete-current'),
  generate: $('#generate-button'),
  volume: $('#volume-slider'),
  storageFooter: $('#storage-footer'),
  memoryFooter: $('#memory-footer'),
  backdrop: $('#modal-backdrop'),
  libraryModal: $('#library-modal'),
  modelModal: $('#model-modal'),
  confirmModal: $('#confirm-modal'),
  toast: $('#toast'),
};

class AudioDeck {
  constructor(onTransition, onEnded) {
    this.context = null;
    this.master = null;
    this.current = null;
    this.next = null;
    this.playing = false;
    this.crossfadeStarted = false;
    this.crossfadeSeconds = 6;
    this.onTransition = onTransition;
    this.onEnded = onEnded;
    this.monitor = null;
    this.volume = 0.72;
    this.scratchSources = [];
  }

  get currentTime() { return this.current?.audio.currentTime || 0; }
  get duration() { return Number.isFinite(this.current?.audio.duration) ? this.current.audio.duration : (this.current?.track.durationSeconds || 0); }
  get currentId() { return this.current?.track.id || null; }

  async ensureContext() {
    if (!this.context) {
      this.context = new AudioContext({ latencyHint: 'playback' });
      this.master = this.context.createGain();
      this.master.gain.value = this.volume;
      this.master.connect(this.context.destination);
    }
    if (this.context.state === 'suspended') await this.context.resume();
  }

  createSlot(track) {
    const audio = new Audio(api.audioURL(track.id));
    audio.preload = 'auto';
    audio.crossOrigin = 'anonymous';
    const source = this.context.createMediaElementSource(audio);
    const gain = this.context.createGain();
    gain.gain.value = 1;
    source.connect(gain).connect(this.master);
    return { track, audio, source, gain };
  }

  async load(track, nextTrack = null, autoplay = true) {
    await this.ensureContext();
    this.clear();
    this.current = this.createSlot(track);
    this.current.audio.addEventListener('ended', () => this.finishCurrent(), { once: true });
    if (nextTrack) this.setNext(nextTrack);
    if (autoplay) await this.play();
  }

  setNext(track) {
    if (!this.context || !this.current || track?.id === this.current.track.id) return;
    if (this.next?.track.id === track.id) return;
    this.disposeSlot(this.next);
    this.next = this.createSlot(track);
    this.next.gain.gain.value = 0;
    this.next.audio.load();
    this.crossfadeStarted = false;
  }

  async play() {
    if (!this.current) return;
    await this.ensureContext();
    await this.current.audio.play();
    this.playing = true;
    this.startMonitor();
    updatePlaybackUI();
  }

  pause() {
    if (!this.current) return;
    this.resetCrossfade();
    this.current.audio.pause();
    this.playing = false;
    this.stopMonitor();
    updatePlaybackUI();
  }

  async toggle() { if (this.playing) this.pause(); else await this.play(); }

  seek(seconds) {
    if (!this.current) return;
    this.resetCrossfade();
    this.current.audio.currentTime = clamp(seconds, 0, Math.max(this.duration - 0.02, 0));
  }

  setVolume(value) {
    this.volume = clamp(Number(value), 0, 1);
    if (this.master && this.context) this.master.gain.setTargetAtTime(this.volume, this.context.currentTime, .02);
  }

  playScratchPreview(preview, direction) {
    if (!this.context || !this.master || !preview?.pcm16 || !preview.frameCount) return;
    const sourceBytes = preview.pcm16 instanceof Uint8Array
      ? preview.pcm16 : new Uint8Array(preview.pcm16.data || preview.pcm16);
    const channels = clamp(Math.round(preview.channels), 1, 2);
    const frames = Math.min(Math.round(preview.frameCount), Math.floor(sourceBytes.byteLength / (channels * 2)));
    if (!frames) return;
    const audioBuffer = this.context.createBuffer(channels, frames, preview.sampleRate);
    const view = new DataView(sourceBytes.buffer, sourceBytes.byteOffset, sourceBytes.byteLength);
    const envelopeFrames = Math.max(1, Math.round(preview.sampleRate * 0.012));
    for (let channel = 0; channel < channels; channel += 1) {
      const output = audioBuffer.getChannelData(channel);
      for (let frame = 0; frame < frames; frame += 1) {
        const sourceFrame = direction < 0 ? frames - frame - 1 : frame;
        const offset = (sourceFrame * channels + channel) * 2;
        const envelope = Math.min(1, frame / envelopeFrames, (frames - frame - 1) / envelopeFrames);
        output[frame] = view.getInt16(offset, true) / 32768 * Math.max(0, envelope) * 0.7;
      }
    }
    while (this.scratchSources.length >= 2) {
      try { this.scratchSources.shift().stop(); } catch {}
    }
    const source = this.context.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(this.master);
    this.scratchSources.push(source);
    source.onended = () => { this.scratchSources = this.scratchSources.filter((item) => item !== source); };
    source.start();
  }

  stopScratchPreviews() {
    for (const source of this.scratchSources) { try { source.stop(); } catch {} }
    this.scratchSources = [];
  }

  startMonitor() {
    this.stopMonitor();
    this.monitor = setInterval(() => this.checkCrossfade(), 200);
  }

  stopMonitor() { if (this.monitor) clearInterval(this.monitor); this.monitor = null; }

  async checkCrossfade() {
    if (!this.playing || !this.current || !this.next || this.crossfadeStarted) return;
    const duration = this.duration;
    if (!duration || this.currentTime < duration - this.crossfadeSeconds) return;
    this.crossfadeStarted = true;
    const seconds = Math.min(this.crossfadeSeconds, duration / 4, (this.next.track.durationSeconds || 120) / 4);
    const now = this.context.currentTime;
    const points = 96;
    const outgoing = new Float32Array(points);
    const incoming = new Float32Array(points);
    for (let index = 0; index < points; index += 1) {
      const progress = index / (points - 1);
      outgoing[index] = Math.cos(progress * Math.PI / 2);
      incoming[index] = Math.sin(progress * Math.PI / 2);
    }
    this.current.gain.gain.cancelScheduledValues(now);
    this.next.gain.gain.cancelScheduledValues(now);
    this.current.gain.gain.setValueAtTime(1, now);
    this.next.gain.gain.setValueAtTime(0, now);
    this.current.gain.gain.setValueCurveAtTime(outgoing, now, seconds);
    this.next.gain.gain.setValueCurveAtTime(incoming, now, seconds);
    try { await this.next.audio.play(); } catch { this.resetCrossfade(); }
  }

  resetCrossfade() {
    if (!this.crossfadeStarted || !this.context) return;
    const now = this.context.currentTime;
    this.current?.gain.gain.cancelScheduledValues(now);
    this.next?.gain.gain.cancelScheduledValues(now);
    if (this.current) this.current.gain.gain.value = 1;
    if (this.next) {
      this.next.audio.pause();
      this.next.audio.currentTime = 0;
      this.next.gain.gain.value = 0;
    }
    this.crossfadeStarted = false;
  }

  finishCurrent() {
    const outgoing = this.current;
    if (this.next) {
      const incoming = this.next;
      this.current = incoming;
      this.next = null;
      this.crossfadeStarted = false;
      this.current.gain.gain.cancelScheduledValues(this.context.currentTime);
      this.current.gain.gain.value = 1;
      this.current.audio.addEventListener('ended', () => this.finishCurrent(), { once: true });
      this.disposeSlot(outgoing);
      this.onTransition(incoming.track.id);
      return;
    }
    this.playing = false;
    this.stopMonitor();
    this.onEnded();
  }

  clear() {
    this.stopMonitor();
    this.stopScratchPreviews();
    this.disposeSlot(this.current);
    this.disposeSlot(this.next);
    this.current = null;
    this.next = null;
    this.playing = false;
    this.crossfadeStarted = false;
  }

  disposeSlot(slot) {
    if (!slot) return;
    slot.audio.pause();
    slot.audio.removeAttribute('src');
    slot.audio.load();
    try { slot.source.disconnect(); slot.gain.disconnect(); } catch {}
  }
}

const deck = new AudioDeck(handleTransition, handlePlaybackEnded);

async function bootstrap() {
  try {
    const data = await api.bootstrap();
    document.documentElement.dataset.platform = data.app.platform;
    Object.assign(state, {
      settings: data.settings,
      tracks: data.tracks,
      statistics: data.statistics,
      runtime: data.runtime,
      hardware: data.hardware,
      genres: data.genres,
      genreLabels: data.genreLabels,
    });
    deck.setVolume(state.settings.volume);
    bindEvents();
    renderAll();
    startVisualLoop();
    const initial = selectCandidate([]);
    if (initial) {
      await playTrack(initial.id);
      setStatus('Станция запущена из локальной коллекции');
      scheduleAutomaticGeneration();
    } else {
      setStatus(state.runtime.connectedModel ? 'Коллекция пуста · создайте первую запись' : 'Коллекция пуста · установите модель');
    }
  } catch (error) {
    setStatus(userMessage(error));
    showToast(userMessage(error));
  }
}

function bindEvents() {
  $$('[data-storage-mode]').forEach((button) => button.addEventListener('click', async () => {
    await saveSettings({ storageMode: button.dataset.storageMode });
    if (state.settings.storageMode === 'live') await pruneTransient();
  }));
  elements.shuffle.addEventListener('change', () => saveSettings({ shuffleEnabled: elements.shuffle.checked }));
  elements.mix.addEventListener('change', () => saveSettings({ mixGenresEnabled: elements.mix.checked }));
  $$('[data-energy]').forEach((button) => button.addEventListener('click', () => saveSettings({ energy: button.dataset.energy })));
  elements.mood.addEventListener('change', () => saveSettings({ mood: elements.mood.value }));
  let vibeTimer;
  elements.vibe.addEventListener('input', () => {
    clearTimeout(vibeTimer);
    vibeTimer = setTimeout(() => saveSettings({ vibe: elements.vibe.value }), 350);
  });
  elements.generation.addEventListener('change', async () => {
    await saveSettings({ generationEnabled: elements.generation.checked });
    if (!elements.generation.checked) {
      if (state.generationTimer) clearTimeout(state.generationTimer);
      state.generationTimer = null;
      await api.cancelGeneration();
    }
    else scheduleAutomaticGeneration();
  });
  $('#genres-all').addEventListener('click', () => saveSettings({ selectedGenres: state.genres }));
  $('#genres-none').addEventListener('click', () => saveSettings({ selectedGenres: [], mixGenresEnabled: false }));

  elements.modelBadge.addEventListener('click', () => openModal(elements.modelModal));
  $('#open-library').addEventListener('click', () => { state.libraryFilter = 'all'; openLibrary(); });
  $('#open-liked').addEventListener('click', () => { state.libraryFilter = 'liked'; openLibrary(); });
  $$('.close-modal').forEach((button) => button.addEventListener('click', closeModals));
  elements.backdrop.addEventListener('click', closeModals);

  $('#seek-start').addEventListener('click', () => deck.seek(0));
  $('#seek-end').addEventListener('click', () => deck.seek(Math.max(0, deck.duration - .05)));
  $('#back-button').addEventListener('click', () => deck.seek(deck.currentTime - 15));
  $('#forward-button').addEventListener('click', () => deck.seek(deck.currentTime + 15));
  elements.play.addEventListener('click', togglePlayback);
  elements.previous.addEventListener('click', previousTrack);
  elements.next.addEventListener('click', nextTrack);
  elements.like.addEventListener('click', toggleCurrentLike);
  elements.deleteCurrent.addEventListener('click', requestCurrentDeletion);
  elements.generate.addEventListener('click', () => requestGeneration(true));
  elements.position.addEventListener('pointerdown', () => { state.sliderDragging = true; });
  elements.position.addEventListener('input', () => deck.seek(Number(elements.position.value)));
  elements.position.addEventListener('change', () => { state.sliderDragging = false; });
  elements.volume.addEventListener('input', () => {
    deck.setVolume(elements.volume.value);
    state.settings.volume = Number(elements.volume.value);
  });
  elements.volume.addEventListener('change', () => saveSettings({ volume: Number(elements.volume.value) }));

  elements.vinylScene.addEventListener('pointerdown', vinylPointerDown);
  elements.vinylScene.addEventListener('pointermove', vinylPointerMove);
  elements.vinylScene.addEventListener('pointerup', vinylPointerUp);
  elements.vinylScene.addEventListener('pointercancel', vinylPointerUp);
  elements.vinylScene.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
      event.preventDefault();
      deck.seek(deck.currentTime + (event.key === 'ArrowRight' ? 2 : -2));
    }
  });

  $$('[data-library-tab]').forEach((button) => button.addEventListener('click', () => {
    state.libraryTab = button.dataset.libraryTab;
    renderLibrary();
  }));
  $$('[data-library-filter]').forEach((button) => button.addEventListener('click', () => {
    state.libraryFilter = button.dataset.libraryFilter;
    renderLibrary();
  }));
  $('#cleanup-library').addEventListener('click', requestCleanup);
  $('#storage-limit').addEventListener('change', () => saveSettings({ storageLimitGiB: Number($('#storage-limit').value) }));

  $('#model-preference').addEventListener('change', async () => {
    const result = await saveSettings({ modelPreference: $('#model-preference').value });
    state.runtime = result.runtime;
    renderModelManager();
  });
  $$('.link-buttons button').forEach((button) => button.addEventListener('click', () => api.openExternal(button.dataset.url)));
  $('#acknowledge-terms').addEventListener('click', async () => {
    await api.acknowledgeTerms();
    state.settings.termsAcknowledged = true;
    renderModelManager();
  });
  $('#cancel-model-operation').addEventListener('click', () => api.cancelGeneration());

  document.addEventListener('keydown', keyboardShortcuts);
  api.onModelProgress(updateModelProgress);
  api.onRuntimeChanged((runtime) => { state.runtime = runtime; renderModelManager(); renderBadges(); });
  api.onWindowVisibility((visible) => {
    state.isWindowVisible = visible;
    if (visible) {
      updateVisualFrame(performance.now());
      startVisualLoop();
    } else stopVisualLoop();
  });
  api.onSystemAction((action) => {
    if (action === 'play-pause') togglePlayback();
    if (action === 'previous') previousTrack();
    if (action === 'next') nextTrack();
  });
  api.onSystemStatus((event) => { if (event.message) setStatus(event.message); });
  setupMediaSession();
}

async function saveSettings(patch) {
  Object.assign(state.settings, patch);
  const result = await api.updateSettings(patch);
  state.settings = result.settings;
  state.runtime = result.runtime;
  renderControls();
  renderBadges();
  return result;
}

function renderAll() {
  renderGenres();
  renderControls();
  renderBadges();
  renderPlayback();
  renderModelManager();
  renderLibrary();
}

function renderGenres() {
  elements.genreGrid.replaceChildren(...state.genres.map((genre) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'genre-chip';
    button.textContent = state.genreLabels[genre] || genre;
    button.dataset.genre = genre;
    button.addEventListener('click', async () => {
      const selected = new Set(state.settings.selectedGenres);
      if (selected.has(genre)) selected.delete(genre); else selected.add(genre);
      await saveSettings({ selectedGenres: [...selected] });
    });
    return button;
  }));
}

function renderControls() {
  $$('[data-storage-mode]').forEach((button) => button.classList.toggle('active', button.dataset.storageMode === state.settings.storageMode));
  $('#storage-mode-help').textContent = state.settings.storageMode === 'live'
    ? 'Новые треки временные. Flowtone хранит текущий, предыдущий и очередь; лайк защищает трек.'
    : 'Каждый новый трек остаётся в локальной коллекции до ручной очистки.';
  elements.shuffle.checked = state.settings.shuffleEnabled;
  $('#shuffle-help').textContent = state.settings.shuffleEnabled
    ? 'Записи из коллекции играют в случайном порядке без близких повторов'
    : 'Записи играются от давно не звучавших к более недавним';
  $$('.genre-chip').forEach((button) => button.classList.toggle('active', state.settings.selectedGenres.includes(button.dataset.genre)));
  elements.mix.checked = state.settings.mixGenresEnabled;
  elements.mix.disabled = state.settings.selectedGenres.length === 1;
  $('#mix-help').textContent = elements.mix.disabled ? 'Для микса выберите минимум два жанра' : 'Flowtone сам сочетает несколько активных жанров в новом треке';
  $$('[data-energy]').forEach((button) => button.classList.toggle('active', button.dataset.energy === state.settings.energy));
  $('#energy-help').textContent = {
    calm: 'Мягкое звучание и сдержанный ритм без резких перепадов',
    balanced: 'Уверенное ровное движение с живыми, но не резкими поворотами',
    driving: 'Бодрящий темп, сильная ритм-секция и более яркие кульминации',
  }[state.settings.energy];
  elements.mood.value = state.settings.mood;
  $('#mood-help').textContent = {
    focused: 'Сдержанная атмосфера, которая не отвлекает от работы', warm: 'Уютные тембры и мягкая, спокойная гармония',
    dreamy: 'Воздушное, мечтательное звучание с большим пространством', dark: 'Мрачная окраска, минорная гармония и глубокие тембры',
    uplifting: 'Светлая гармония и ощущение подъёма без лишней суеты',
  }[state.settings.mood];
  if (document.activeElement !== elements.vibe) elements.vibe.value = state.settings.vibe;
  elements.generation.checked = state.settings.generationEnabled;
  $('#generation-help').textContent = state.settings.generationEnabled
    ? 'Flowtone создаёт по одному треку в фоне'
    : 'Генерация остановлена, процесс модели завершён и память освобождена';
  elements.storageFooter.textContent = state.settings.storageMode === 'live'
    ? '◷ Временные треки удаляются автоматически'
    : '▣ Записи остаются на этом компьютере';
}

function renderBadges() {
  const model = state.runtime?.models.find((item) => item.id === state.runtime.connectedModel);
  const recommended = state.runtime?.models.find((item) => item.id === state.runtime.recommendedModel);
  elements.modelName.textContent = state.settings.modelPreference === 'auto'
    ? `Авто · ${recommended?.title || 'подбор модели'}` : (model?.title || 'Модель не установлена');
  elements.modelStatus.textContent = model ? `${model.title} готова · локальная генерация`
    : `Рекомендуется ${recommended?.title || 'Stable Audio 3'} · требуется установка`;
  elements.librarySummary.textContent = `${state.statistics.trackCount} ${plural(state.statistics.trackCount, 'трек', 'трека', 'треков')} · ${formatBytes(state.statistics.byteSize)}`;
  elements.likedSummary.textContent = `${state.statistics.likedTrackCount} ${plural(state.statistics.likedTrackCount, 'любимый', 'любимых', 'любимых')}`;
  elements.memoryFooter.textContent = `${state.hardware.memoryGiB} ГБ памяти`;
}

function renderPlayback() {
  const track = currentTrack();
  elements.title.textContent = track?.title || 'Тишина перед эфиром';
  elements.vinylGenre.textContent = currentGenreLabel();
  elements.position.max = Math.max(deck.duration || track?.durationSeconds || 1, 1);
  elements.play.textContent = deck.playing ? '❚❚' : '▶';
  elements.play.setAttribute('aria-label', deck.playing ? 'Пауза' : 'Воспроизвести');
  elements.like.textContent = track?.isLiked ? '♥' : '♡';
  elements.like.classList.toggle('liked', Boolean(track?.isLiked));
  elements.like.disabled = !track;
  elements.deleteCurrent.disabled = !track;
  elements.previous.disabled = previousHistoryIndex() < 0;
  elements.next.disabled = !track && !state.runtime?.connectedModel;
  elements.generate.disabled = !state.settings.generationEnabled || !state.runtime?.connectedModel || state.isGenerating;
  elements.generate.classList.toggle('loading', state.isGenerating);
  elements.generate.querySelector('b').textContent = state.isGenerating ? 'Создаю запись…' : (track ? 'Создать ещё' : 'Создать первую');
  elements.airLabel.textContent = state.isGenerating ? 'СОЗДАЁТСЯ НОВАЯ ЗАПИСЬ' : 'СЕЙЧАС В ЭФИРЕ';
  elements.volume.value = state.settings.volume;
  updateMediaMetadata();
  api.setPlaybackState({ isPlaying: deck.playing });
}

function updatePlaybackUI() {
  renderPlayback();
  if (shouldAnimateVisuals()) startVisualLoop();
  else {
    updateVisualFrame(performance.now());
    stopVisualLoop();
  }
  if ('mediaSession' in navigator) navigator.mediaSession.playbackState = deck.playing ? 'playing' : 'paused';
}

function renderLibrary(force = false) {
  if (!state.settings) return;
  if (elements.libraryModal.hidden && !force) return;
  $$('[data-library-tab]').forEach((button) => button.classList.toggle('active', button.dataset.libraryTab === state.libraryTab));
  $$('[data-library-filter]').forEach((button) => button.classList.toggle('active', button.dataset.libraryFilter === state.libraryFilter));
  $('#library-tracks-view').hidden = state.libraryTab !== 'tracks';
  $('#library-statistics-view').hidden = state.libraryTab !== 'statistics';
  const filtered = state.tracks.filter((track) => state.libraryFilter !== 'liked' || track.isLiked);
  const list = $('#track-list');
  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-library';
    empty.textContent = state.libraryFilter === 'liked' ? 'Любимых записей пока нет' : 'Локальная коллекция пока пуста';
    list.replaceChildren(empty);
  } else {
    list.replaceChildren(...filtered.map(trackRow));
  }
  $('#metric-tracks').textContent = state.statistics.trackCount;
  $('#metric-liked').textContent = state.statistics.likedTrackCount;
  $('#metric-size').textContent = formatBytes(state.statistics.byteSize);
  $('#storage-limit').value = state.settings.storageLimitGiB;
  $('#genre-statistics').replaceChildren(...state.statistics.genres.map((item) => {
    const article = document.createElement('article');
    const title = document.createElement('span');
    title.textContent = state.genreLabels[item.genre] || item.genre;
    const value = document.createElement('span');
    value.textContent = `${item.trackCount} · ${formatBytes(item.byteSize)}`;
    article.append(title, value);
    return article;
  }));
}

function trackRow(track) {
  const row = document.createElement('article');
  row.className = `track-row${track.id === state.currentTrackId ? ' current' : ''}`;
  const play = document.createElement('button');
  play.type = 'button'; play.className = 'row-play'; play.textContent = track.id === state.currentTrackId && deck.playing ? '❚❚' : '▶';
  play.setAttribute('aria-label', `Воспроизвести ${track.title}`);
  play.addEventListener('click', () => track.id === state.currentTrackId ? togglePlayback() : playTrack(track.id));
  const info = document.createElement('div'); info.className = 'track-info';
  const title = document.createElement('strong'); title.textContent = track.title;
  const genre = document.createElement('small'); genre.textContent = track.genres.map((item) => state.genreLabels[item] || item).join(' + ');
  info.append(title, genre);
  const date = document.createElement('span'); date.className = 'track-meta'; date.textContent = new Intl.DateTimeFormat('ru', { day: '2-digit', month: 'short', year: 'numeric' }).format(trackDate(track.createdAt));
  const size = document.createElement('span'); size.className = 'track-meta'; size.textContent = formatBytes(track.byteSize);
  const actions = document.createElement('div'); actions.className = 'track-actions';
  const like = document.createElement('button'); like.type = 'button'; like.textContent = track.isLiked ? '♥' : '♡'; like.classList.toggle('liked', track.isLiked);
  like.setAttribute('aria-label', track.isLiked ? 'Убрать из любимых' : 'Добавить в любимые');
  like.addEventListener('click', () => setTrackLiked(track.id, !track.isLiked));
  const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = '⌫'; remove.setAttribute('aria-label', 'Удалить запись');
  remove.addEventListener('click', () => requestTrackDeletion(track));
  actions.append(like, remove);
  row.append(play, info, date, size, actions);
  return row;
}

function renderModelManager() {
  if (!state.runtime || !state.settings) return;
  $('#hardware-memory').textContent = `${state.hardware.memoryGiB} ГБ`;
  $('#hardware-cpu').textContent = `${state.hardware.logicalCores} потоков · ${state.hardware.cpu}`;
  $('#hardware-cpu').title = state.hardware.cpu;
  $('#hardware-gpu').textContent = state.hardware.gpu;
  $('#hardware-gpu').title = state.hardware.gpu;
  const preference = $('#model-preference');
  const currentOptions = new Set([...preference.options].map((option) => option.value));
  for (const model of state.runtime.models) {
    if (currentOptions.has(model.id)) continue;
    const option = document.createElement('option'); option.value = model.id; option.textContent = model.title; preference.append(option);
  }
  preference.value = state.settings.modelPreference;
  const recommended = state.runtime.models.find((model) => model.id === state.runtime.recommendedModel);
  $('#recommendation-text').textContent = `Автоподбор рекомендует «${recommended?.title}». Flowtone определил GPU, но официальный Windows runtime использует оптимизированный CPU-путь LiteRT, поэтому выбор основан на RAM и CPU.`;
  $('#acknowledge-terms').hidden = state.settings.termsAcknowledged;
  $('#terms-confirmed').hidden = !state.settings.termsAcknowledged;
  $('#runtime-path').textContent = state.runtime.runtimePath;
  $('#model-list').replaceChildren(...state.runtime.models.map((model) => {
    const installed = state.runtime.installedModels.includes(model.id);
    const option = document.createElement('article');
    option.className = `model-option${model.id === state.runtime.recommendedModel ? ' recommended' : ''}`;
    const info = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = model.title;
    if (model.id === state.runtime.recommendedModel) { const tag = document.createElement('em'); tag.textContent = 'РЕКОМЕНДОВАНА'; title.append(tag); }
    const detail = document.createElement('p'); detail.textContent = `${model.detail} · около ${model.estimatedGiB.toLocaleString('ru-RU')} ГБ`;
    info.append(title, detail);
    const action = document.createElement('button'); action.type = 'button';
    action.textContent = installed ? 'Удалить' : 'Установить';
    if (installed) action.classList.add('uninstall');
    action.addEventListener('click', () => installed ? requestModelUninstall(model) : installModel(model.id));
    info.dataset.installed = installed;
    option.append(info, action);
    return option;
  }));
  const busy = state.runtime.installing || state.runtime.generating;
  $('#model-preference').disabled = busy;
  $('#model-list').querySelectorAll('button').forEach((button) => { button.disabled = busy; });
}

function openLibrary() { openModal(elements.libraryModal); renderLibrary(true); }

function openModal(modal) {
  closeModals();
  elements.backdrop.hidden = false;
  modal.hidden = false;
  modal.focus({ preventScroll: true });
}

function closeModals() {
  if (state.confirmResolver) {
    const resolve = state.confirmResolver;
    state.confirmResolver = null;
    resolve(false);
  }
  elements.backdrop.hidden = true;
  elements.libraryModal.hidden = true;
  elements.modelModal.hidden = true;
  elements.confirmModal.hidden = true;
}

function confirmAction({ title, message, actionLabel = 'Удалить' }) {
  return new Promise((resolve) => {
    $('#confirm-title').textContent = title;
    $('#confirm-message').textContent = message;
    $('#confirm-action').textContent = actionLabel;
    elements.backdrop.hidden = false;
    elements.confirmModal.hidden = false;
    const finish = (value) => {
      $('#confirm-cancel').removeEventListener('click', cancel);
      $('#confirm-action').removeEventListener('click', accept);
      elements.confirmModal.hidden = true;
      if (elements.libraryModal.hidden && elements.modelModal.hidden) elements.backdrop.hidden = true;
      state.confirmResolver = null;
      resolve(value);
    };
    const cancel = () => finish(false);
    const accept = () => finish(true);
    state.confirmResolver = cancel;
    $('#confirm-cancel').addEventListener('click', cancel);
    $('#confirm-action').addEventListener('click', accept);
    $('#confirm-cancel').focus();
  });
}

async function playTrack(trackId, historyDestination = null) {
  const track = findTrack(trackId);
  if (!track) return;
  state.currentTrackId = track.id;
  if (historyDestination === null) recordHistory(track.id); else state.historyIndex = historyDestination;
  fillQueue();
  const next = findTrack(state.readyTrackIds[0]);
  try {
    await deck.load(track, next, true);
    const updated = await api.markPlayed(track.id);
    applyLibrarySnapshot(updated);
    setStatus('Станция в эфире');
  } catch (error) { setStatus(userMessage(error)); }
  renderPlayback(); renderLibrary();
  scheduleAutomaticGeneration();
}

function fillQueue() {
  state.readyTrackIds = state.readyTrackIds.filter((id) => id !== state.currentTrackId && findTrack(id));
  while (state.readyTrackIds.length < 2) {
    const recent = state.history.slice(-3);
    let candidate = selectCandidate([state.currentTrackId, ...state.readyTrackIds, ...recent]);
    if (!candidate) candidate = selectCandidate([state.currentTrackId, ...state.readyTrackIds]);
    if (!candidate) break;
    state.readyTrackIds.push(candidate.id);
  }
  const next = findTrack(state.readyTrackIds[0]);
  if (next && deck.currentId === state.currentTrackId) deck.setNext(next);
}

function selectCandidate(excluding) {
  const excluded = new Set(excluding.filter(Boolean));
  const selected = new Set(state.settings.selectedGenres);
  let candidates = state.tracks.filter((track) => !excluded.has(track.id)
    && (selected.size === 0 || track.genres.some((genre) => selected.has(genre))));
  if (!candidates.length) candidates = state.tracks.filter((track) => !excluded.has(track.id));
  if (!candidates.length) return null;
  if (state.settings.shuffleEnabled) return candidates[Math.floor(Math.random() * candidates.length)];
  return candidates.sort((left, right) => String(left.lastPlayedAt || left.createdAt).localeCompare(String(right.lastPlayedAt || right.createdAt)))[0];
}

async function handleTransition(incomingId) {
  state.readyTrackIds = state.readyTrackIds.filter((id) => id !== incomingId);
  state.currentTrackId = incomingId;
  recordHistory(incomingId);
  fillQueue();
  const next = findTrack(state.readyTrackIds[0]);
  if (next) deck.setNext(next);
  try { applyLibrarySnapshot(await api.markPlayed(incomingId)); } catch {}
  if (state.settings.storageMode === 'live') await pruneTransient();
  setStatus('Плавный переход · станция в эфире');
  renderPlayback(); renderLibrary();
  scheduleAutomaticGeneration();
}

async function handlePlaybackEnded() {
  fillQueue();
  const replacement = findTrack(state.readyTrackIds.shift()) || selectCandidate([state.currentTrackId]);
  if (replacement) await playTrack(replacement.id);
  else if (state.runtime.connectedModel) await requestGeneration(true);
}

async function togglePlayback() {
  if (!deck.current) {
    const candidate = selectCandidate([]);
    if (candidate) await playTrack(candidate.id);
    else await requestGeneration(true);
    return;
  }
  try { await deck.toggle(); setStatus(deck.playing ? 'Станция в эфире' : 'Пауза'); } catch (error) { setStatus(userMessage(error)); }
}

function previousHistoryIndex() {
  for (let index = state.historyIndex - 1; index >= 0; index -= 1) if (findTrack(state.history[index])) return index;
  return -1;
}

function nextHistoryIndex() {
  for (let index = state.historyIndex + 1; index < state.history.length; index += 1) if (findTrack(state.history[index])) return index;
  return -1;
}

async function previousTrack() { const index = previousHistoryIndex(); if (index >= 0) await playTrack(state.history[index], index); }
async function nextTrack() {
  const historyIndex = nextHistoryIndex();
  if (historyIndex >= 0) return playTrack(state.history[historyIndex], historyIndex);
  fillQueue();
  const id = state.readyTrackIds.shift();
  if (id) return playTrack(id);
  const candidate = selectCandidate([state.currentTrackId]);
  if (candidate) return playTrack(candidate.id);
  return requestGeneration(true);
}

function recordHistory(trackId) {
  if (state.history[state.historyIndex] === trackId) return;
  if (state.historyIndex + 1 < state.history.length) state.history.splice(state.historyIndex + 1);
  state.history.push(trackId);
  state.historyIndex = state.history.length - 1;
}

async function requestGeneration(playWhenReady, automatic = false) {
  if (state.isGenerating || !state.settings.generationEnabled || !state.runtime.connectedModel) {
    if (!automatic && !state.runtime.connectedModel) { openModal(elements.modelModal); showToast('Установите рекомендованную модель.'); }
    return;
  }
  state.isGenerating = true;
  renderPlayback();
  setStatus('Создаю новую локальную запись…');
  try {
    const result = await api.generateTrack(state.settings);
    applyLibrarySnapshot(result);
    state.runtime = result.runtime;
    if (playWhenReady || !state.currentTrackId) await playTrack(result.track.id);
    else {
      if (state.readyTrackIds.length >= 2) state.readyTrackIds.pop();
      state.readyTrackIds.push(result.track.id);
      fillQueue();
      setStatus('Новая запись готова и добавлена в очередь');
    }
    if (state.settings.storageMode === 'live') await pruneTransient();
  } catch (error) {
    const message = userMessage(error);
    setStatus(message);
    if (!automatic) showToast(message);
  } finally {
    state.isGenerating = false;
    renderAll();
    if (state.currentTrackId && state.readyTrackIds.length < 2) scheduleAutomaticGeneration();
  }
}

function scheduleAutomaticGeneration() {
  if (!state.settings.generationEnabled || !state.runtime.connectedModel || state.isGenerating
    || !state.currentTrackId || state.readyTrackIds.length >= 2 || state.generationTimer) return;
  state.generationTimer = setTimeout(() => {
    state.generationTimer = null;
    requestGeneration(false, true);
  }, 450);
}

async function toggleCurrentLike() { const track = currentTrack(); if (track) await setTrackLiked(track.id, !track.isLiked); }
async function setTrackLiked(trackId, liked) {
  try { applyLibrarySnapshot(await api.setLiked(trackId, liked)); setStatus(liked ? 'Запись сохранена в любимых' : 'Запись убрана из любимых'); renderAll(); }
  catch (error) { showToast(userMessage(error)); }
}

async function requestCurrentDeletion() {
  const track = currentTrack();
  if (!track) return;
  const confirmed = await confirmAction({ title: 'Удалить текущий трек?', message: `«${track.title}» будет безвозвратно удалён с компьютера. Flowtone сразу включит соседний трек.` });
  if (!confirmed) return;
  deck.clear();
  state.readyTrackIds = state.readyTrackIds.filter((id) => id !== track.id);
  state.currentTrackId = null;
  try {
    applyLibrarySnapshot(await api.deleteTrack(track.id));
    state.history = state.history.filter((id) => id !== track.id); state.historyIndex = state.history.length - 1;
    const replacement = findTrack(state.readyTrackIds.shift()) || selectCandidate([]);
    if (replacement) await playTrack(replacement.id); else await requestGeneration(true);
  } catch (error) { showToast(userMessage(error)); }
}

async function requestTrackDeletion(track) {
  if (track.id === state.currentTrackId) return requestCurrentDeletion();
  const confirmed = await confirmAction({ title: 'Удалить запись?', message: `«${track.title}» будет безвозвратно удалён с компьютера.` });
  if (!confirmed) return;
  try { applyLibrarySnapshot(await api.deleteTrack(track.id)); state.readyTrackIds = state.readyTrackIds.filter((id) => id !== track.id); renderAll(); }
  catch (error) { showToast(userMessage(error)); }
}

async function requestCleanup() {
  const confirmed = await confirmAction({ title: 'Удалить все записи без лайка?', message: 'Любимые и активные записи останутся. Остальные аудиофайлы будут удалены безвозвратно.' });
  if (!confirmed) return;
  try {
    const result = await api.cleanupLibrary(protectedTrackIds());
    applyLibrarySnapshot(result); renderAll(); showToast(`Удалено записей: ${result.report.removedTrackCount}`);
  } catch (error) { showToast(userMessage(error)); }
}

async function pruneTransient() {
  try { applyLibrarySnapshot(await api.pruneTransient(protectedTrackIds())); renderBadges(); renderLibrary(); } catch {}
}

function protectedTrackIds() { return [state.currentTrackId, ...state.readyTrackIds, state.history[state.historyIndex - 1]].filter(Boolean); }

async function installModel(modelId) {
  if (!state.settings.termsAcknowledged) { showToast('Сначала откройте и прочитайте официальные условия.'); return; }
  $('#model-error').hidden = true;
  state.runtime.installing = true;
  renderModelManager();
  try {
    state.runtime = await api.installModel(modelId);
    await saveSettings({ modelPreference: modelId });
    showToast('Модель установлена и подключена.');
    scheduleAutomaticGeneration();
  } catch (error) {
    $('#model-error').textContent = userMessage(error); $('#model-error').hidden = false;
  } finally {
    state.runtime.installing = false;
    $('#model-progress').hidden = true;
    renderModelManager(); renderBadges();
  }
}

async function requestModelUninstall(model) {
  const confirmed = await confirmAction({ title: 'Удалить модель с устройства?', message: `${model.title} и её веса будут удалены. Локальные треки останутся. Если есть другая совместимая модель, Flowtone подключит её автоматически.` });
  if (!confirmed) return;
  try {
    state.runtime = await api.uninstallModel(model.id);
    if (state.settings.modelPreference === model.id) await saveSettings({ modelPreference: 'auto' });
    renderModelManager(); renderBadges(); showToast('Модель удалена.');
  }
  catch (error) { showToast(userMessage(error)); }
}

function updateModelProgress(progress) {
  $('#model-progress').hidden = false;
  $('#model-progress-title').textContent = progress.title;
  $('#model-progress-detail').textContent = progress.detail;
  $('#model-progress-bar').value = progress.fraction;
}

function vinylPointerDown(event) {
  if (!deck.current) return;
  const position = pointerPolar(event);
  if (!position || position.radius < position.size * .1) return;
  elements.vinylScene.setPointerCapture(event.pointerId);
  state.draggingVinyl = true;
  state.dragAngle = position.angle;
  state.dragPosition = deck.currentTime;
  state.dragVisualAngle = deck.currentTime * 18 + state.visualAngleOffset;
  state.wasPlayingBeforeDrag = deck.playing;
  state.lastScratchAt = 0;
  state.scratchRequest += 1;
  deck.stopScratchPreviews();
  if (deck.playing) deck.pause();
  elements.vinylScene.classList.add('dragging');
  $('#scratch-label').textContent = 'СКРЕТЧ';
}

function vinylPointerMove(event) {
  if (!state.draggingVinyl) return;
  const position = pointerPolar(event);
  if (!position || position.radius < position.size * .1) return;
  let delta = position.angle - state.dragAngle;
  if (delta > Math.PI) delta -= 2 * Math.PI;
  if (delta < -Math.PI) delta += 2 * Math.PI;
  delta = clamp(delta, -Math.PI / 6, Math.PI / 6);
  if (Math.abs(delta) < .001) return;
  state.dragPosition = clamp(state.dragPosition + delta / (2 * Math.PI) * 8, 0, deck.duration);
  state.dragVisualAngle += delta * 180 / Math.PI;
  state.dragAngle = Math.atan2(Math.sin(state.dragAngle + delta), Math.cos(state.dragAngle + delta));
  deck.seek(state.dragPosition);
  elements.vinylRecord.style.setProperty('--vinyl-angle', `${state.dragVisualAngle}deg`);
  const now = performance.now();
  if (now - state.lastScratchAt >= 50) {
    state.lastScratchAt = now;
    const request = ++state.scratchRequest;
    api.scratchPreview(state.currentTrackId, state.dragPosition, Math.sign(delta)).then((preview) => {
      if (state.draggingVinyl && request >= state.scratchRequest - 1) deck.playScratchPreview(preview, Math.sign(delta));
    }).catch(() => {});
  }
}

async function vinylPointerUp(event) {
  if (!state.draggingVinyl) return;
  if (elements.vinylScene.hasPointerCapture(event.pointerId)) elements.vinylScene.releasePointerCapture(event.pointerId);
  state.visualAngleOffset = state.dragVisualAngle - state.dragPosition * 18;
  state.draggingVinyl = false; state.dragAngle = null;
  state.scratchRequest += 1;
  deck.stopScratchPreviews();
  elements.vinylScene.classList.remove('dragging');
  $('#scratch-label').textContent = 'Проведите по пластинке';
  if (state.wasPlayingBeforeDrag) await deck.play();
  else {
    updateVisualFrame(performance.now());
    stopVisualLoop();
  }
}

function pointerPolar(event) {
  const rect = elements.vinylRecord.getBoundingClientRect();
  const x = event.clientX - (rect.left + rect.width / 2);
  const y = event.clientY - (rect.top + rect.height / 2);
  return { angle: Math.atan2(y, x), radius: Math.hypot(x, y), size: rect.width };
}

function startVisualLoop() {
  if (!shouldAnimateVisuals() || state.animationFrame) return;
  const frame = (now) => {
    state.animationFrame = null;
    if (!shouldAnimateVisuals()) return;
    if (now - state.lastFrameAt >= 1000 / 60 - .5) {
      state.lastFrameAt = now;
      updateVisualFrame(now);
    }
    state.animationFrame = requestAnimationFrame(frame);
  };
  state.animationFrame = requestAnimationFrame(frame);
}

function stopVisualLoop() { if (state.animationFrame) cancelAnimationFrame(state.animationFrame); state.animationFrame = null; }

function shouldAnimateVisuals() { return state.isWindowVisible && (deck.playing || state.draggingVinyl); }

function updateVisualFrame(now) {
  const position = deck.currentTime;
  const duration = deck.duration;
  if (!state.draggingVinyl) elements.vinylRecord.style.setProperty('--vinyl-angle', `${position * 18 + state.visualAngleOffset}deg`);
  const progress = duration > 0 ? clamp(position / duration, 0, 1) : 0;
  elements.tonearm.style.setProperty('--tonearm-angle', `${currentTrack() ? 10 + progress * 12 : -7}deg`);
  if (!state.sliderDragging) elements.position.value = position;
  elements.position.max = Math.max(duration, 1);
  elements.currentTime.textContent = formatTime(position);
  elements.duration.textContent = formatTime(duration);
  elements.vinylScene.setAttribute('aria-valuenow', String(Math.round(position)));
  if (now - state.lastMarqueeAt >= 1000 / 15) { state.lastMarqueeAt = now; updateMarquee(now); }
  if ('mediaSession' in navigator && deck.current && now - state.lastMediaSessionAt >= 250) {
    state.lastMediaSessionAt = now;
    try { navigator.mediaSession.setPositionState({ duration: Math.max(duration, 1), playbackRate: 1, position: clamp(position, 0, Math.max(duration - .01, 0)) }); } catch {}
  }
}

function updateMarquee(now) {
  const viewport = elements.title.parentElement;
  const overflow = elements.title.scrollWidth - viewport.clientWidth;
  if (!deck.playing || overflow <= 0) { state.marqueeOffset = 0; elements.title.style.setProperty('--marquee-x', '0px'); return; }
  if (now < state.marqueePauseUntil) return;
  state.marqueeOffset += state.marqueeDirection * .8;
  if (state.marqueeOffset <= -overflow) { state.marqueeOffset = -overflow; state.marqueeDirection = 1; state.marqueePauseUntil = now + 1500; }
  if (state.marqueeOffset >= 0) { state.marqueeOffset = 0; state.marqueeDirection = -1; state.marqueePauseUntil = now + 1500; }
  elements.title.style.setProperty('--marquee-x', `${state.marqueeOffset}px`);
}

function setupMediaSession() {
  if (!('mediaSession' in navigator)) return;
  navigator.mediaSession.setActionHandler('play', () => deck.play());
  navigator.mediaSession.setActionHandler('pause', () => deck.pause());
  navigator.mediaSession.setActionHandler('previoustrack', previousTrack);
  navigator.mediaSession.setActionHandler('nexttrack', nextTrack);
  navigator.mediaSession.setActionHandler('seekbackward', (details) => deck.seek(deck.currentTime - (details.seekOffset || 15)));
  navigator.mediaSession.setActionHandler('seekforward', (details) => deck.seek(deck.currentTime + (details.seekOffset || 15)));
  navigator.mediaSession.setActionHandler('seekto', (details) => deck.seek(details.seekTime));
}

function updateMediaMetadata() {
  if (!('mediaSession' in navigator)) return;
  const track = currentTrack();
  navigator.mediaSession.metadata = track ? new MediaMetadata({ title: track.title, artist: currentGenreLabel(), album: 'Flowtone' }) : null;
}

function keyboardShortcuts(event) {
  if (event.key === 'Escape') { closeModals(); return; }
  if (event.target.matches('input, select, button, textarea')) return;
  if (event.code === 'Space') { event.preventDefault(); togglePlayback(); }
  if (event.key === 'ArrowLeft') deck.seek(deck.currentTime - 5);
  if (event.key === 'ArrowRight') deck.seek(deck.currentTime + 5);
}

function applyLibrarySnapshot(snapshot) {
  if (snapshot.tracks) state.tracks = snapshot.tracks;
  if (snapshot.statistics) state.statistics = snapshot.statistics;
  renderBadges();
}

function currentTrack() { return findTrack(state.currentTrackId); }
function findTrack(id) { return state.tracks.find((track) => track.id === id) || null; }
function currentGenreLabel() {
  let genres = currentTrack()?.genres;
  if (!genres) {
    const selected = state.settings?.selectedGenres || [];
    genres = state.settings?.mixGenresEnabled ? selected : state.genres.filter((genre) => selected.includes(genre)).slice(0, 1);
  }
  if (!genres.length) return 'Все жанры';
  const labels = genres.map((genre) => state.genreLabels[genre] || genre);
  return labels.length > 1 ? `Микс · ${labels.slice(0, 2).join(' + ')}` : labels[0];
}

function setStatus(message) { elements.status.textContent = message; }
function showToast(message) {
  elements.toast.textContent = message; elements.toast.hidden = false;
  clearTimeout(showToast.timer); showToast.timer = setTimeout(() => { elements.toast.hidden = true; }, 5000);
}

function formatTime(seconds) { const safe = Math.max(0, Math.floor(Number(seconds) || 0)); return `${Math.floor(safe / 60)}:${String(safe % 60).padStart(2, '0')}`; }
function trackDate(value) {
  if (typeof value === 'number') return new Date((value + 978307200) * 1000);
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? new Date(0) : parsed;
}
function formatBytes(bytes) {
  const safe = Math.max(0, Number(bytes) || 0); if (safe < 1024) return `${safe} байт`;
  const units = ['КБ', 'МБ', 'ГБ', 'ТБ']; let value = safe / 1024; let index = 0;
  while (value >= 1024 && index < units.length - 1) { value /= 1024; index += 1; }
  return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} ${units[index]}`;
}
function plural(value, one, few, many) { const n = Math.abs(value) % 100; const n1 = n % 10; if (n > 10 && n < 20) return many; if (n1 > 1 && n1 < 5) return few; if (n1 === 1) return one; return many; }
function clamp(value, lower, upper) { return Math.min(Math.max(Number(value) || 0, lower), upper); }
function userMessage(error) { return String(error?.message || error || 'Неизвестная ошибка').replace(/^Error invoking remote method '[^']+':\s*/, '').replace(/^Error:\s*/, ''); }

bootstrap();
