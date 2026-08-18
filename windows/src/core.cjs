'use strict';

const crypto = require('node:crypto');
const { PROFILE_CATALOG } = require('./genre-profiles.cjs');

const GENRES = [
  'Ambient', 'Lo-fi', 'Light Rave', 'Fantasy', 'Dark Empire', 'Pirate', 'Rock',
  'Space Rock', 'Metal', 'Thrash Metal', 'Cute', 'Chaos', 'Electronic', 'Synthwave',
  'House', 'Techno', 'Hard Techno', 'Industrial Techno', 'Hardcore', 'Psytrance',
  'Breakbeat', 'Drum and Bass', 'Cyberpunk', 'Hip-hop', 'Funk', 'Jazz', 'Classical',
  'Post-rock', 'Cinematic',
];

const GENRE_LABELS = {
  Ambient: 'Эмбиент', 'Lo-fi': 'Лоу-фай', 'Light Rave': 'Лёгкий рейв',
  Fantasy: 'Фэнтези', 'Dark Empire': 'Тёмная империя', Pirate: 'Пиратская',
  Rock: 'Рок', 'Space Rock': 'Космо-рок', Metal: 'Метал', 'Thrash Metal': 'Трэш-метал',
  Cute: 'Милая музыка', Chaos: 'Хаос', Electronic: 'Электроника', Synthwave: 'Синтвейв',
  House: 'Хаус', Techno: 'Техно', 'Hard Techno': 'Хард-техно',
  'Industrial Techno': 'Индастриал-техно', Hardcore: 'Хардкор', Psytrance: 'Псайтранс',
  Breakbeat: 'Брейкбит', 'Drum and Bass': 'Драм-н-бэйс', Cyberpunk: 'Киберпанк',
  'Hip-hop': 'Хип-хоп', Funk: 'Фанк', Jazz: 'Джаз', Classical: 'Классика',
  'Post-rock': 'Пост-рок', Cinematic: 'Кинематографичная',
};

const TEMPO_PROFILES = {
  Ambient: [[58, 64, 70, 76, 84], 50, 96, 6],
  'Lo-fi': [[68, 74, 80, 86, 92], 62, 100, 6],
  'Light Rave': [[112, 120, 128, 136, 144], 108, 150, 4],
  Fantasy: [[58, 68, 80, 96, 120], 50, 132, 8],
  'Dark Empire': [[100, 112, 128, 144, 160], 92, 168, 8],
  Pirate: [[104, 112, 120, 128, 136], 96, 144, 8],
  Rock: [[96, 112, 124, 136, 148], 84, 160, 8],
  'Space Rock': [[72, 88, 104, 120, 136], 64, 148, 8],
  Metal: [[104, 120, 136, 152, 168], 88, 184, 8],
  'Thrash Metal': [[150, 162, 174, 186, 198], 142, 210, 8],
  Cute: [[88, 100, 112, 124, 136], 80, 144, 6],
  Chaos: [[71, 97, 127, 157, 191], 55, 210, 10],
  Electronic: [[96, 108, 118, 124, 130], 84, 140, 6],
  Synthwave: [[86, 94, 102, 110, 118], 78, 126, 6],
  House: [[116, 120, 124, 126, 130], 115, 130, 2],
  Techno: [[120, 126, 130, 134, 140], 120, 140, 2],
  'Hard Techno': [[138, 142, 146, 150, 154], 136, 158, 2],
  'Industrial Techno': [[136, 144, 150, 156, 160], 132, 164, 4],
  Hardcore: [[160, 168, 174, 182, 190], 156, 196, 4],
  Psytrance: [[138, 142, 145, 148, 150], 136, 152, 2],
  Breakbeat: [[118, 126, 132, 138, 146], 112, 152, 4],
  'Drum and Bass': [[160, 166, 172, 176, 180], 160, 180, 2],
  Cyberpunk: [[96, 112, 124, 136, 160], 84, 176, 6],
  'Hip-hop': [[62, 72, 82, 92, 100], 60, 100, 4],
  Funk: [[92, 100, 106, 112, 120], 84, 126, 4],
  Jazz: [[72, 88, 104, 120, 144], 60, 168, 8],
  Classical: [[56, 66, 76, 92, 116], 48, 144, 8],
  'Post-rock': [[64, 76, 88, 100, 112], 58, 124, 6],
  Cinematic: [[56, 68, 80, 96, 116], 48, 132, 8],
};

const GENRE_PROMPTS = {
  Ambient: 'ambient instrumental, spacious natural reverb, slow harmonic movement, evolving analog pads, sparse felt piano, no drums',
  'Lo-fi': 'lo-fi instrumental, warm cassette texture, relaxed pocket, mellow Rhodes chords, rounded bass, intimate room sound',
  'Light Rave': 'instrumental Berlin rave and hard-dance continuum, elastic club low end, bright detailed top end, continuous dance-floor motion',
  Fantasy: 'instrumental historical fantasy score, modal melody, realistic acoustic orchestration, ancient world atmosphere',
  'Dark Empire': 'instrumental dark imperial fantasy, theatrical orchestral-rock production, chromatic minor harmony, regal menace',
  Pirate: 'instrumental lively sea-song and shanty folk, fiddle, concertina, tin whistle, deck-work pulse, small dry acoustic ensemble',
  Rock: 'instrumental live rock band, human dynamics, electric guitars, melodic bass and acoustic drum kit',
  'Space Rock': 'instrumental space rock, live psychedelic trio, analog synthesizers, reverberant guitar, hypnotic otherworldly texture',
  Metal: 'instrumental heavy metal, powerful bass, live drums, articulate distorted guitars, harmonized lead motif',
  'Thrash Metal': 'instrumental thrash metal, fast palm-muted riffs, sharp stops, galloping bass, aggressive live drums',
  Cute: 'cute playful instrumental, bright harmony, toy piano, pizzicato strings, glockenspiel, tiny drums',
  Chaos: 'controlled experimental instrumental chaos, polymetric drums, dissonant textures, recurring motif, structured tension and release',
  Electronic: 'instrumental electronic production, detailed stereo field, clean low end, evolving sound design, clear build and release',
  Synthwave: 'instrumental retro-futurist analog synth noir, memorable motif, wide dimensional reverb, tactile low-frequency design',
  House: 'instrumental house, four-on-the-floor kick, elastic bassline, crisp percussion, warm chord stabs, dance-floor continuity',
  Techno: 'instrumental techno, focused machine groove, rolling low end, precise percussion, hypnotic gradual development',
  'Hard Techno': 'instrumental hard techno, forceful clean kick, rumbling bass, sharp industrial percussion, controlled peak-time drive',
  'Industrial Techno': 'instrumental industrial techno, mechanical impacts, distorted low pressure, metallic texture, disciplined escalation',
  Hardcore: 'instrumental hardcore electronic, fast powerful kick pattern, bright attack, tense breakdown, decisive return',
  Psytrance: 'instrumental psytrance, rolling bass sequence, detailed percussion, evolving psychedelic arpeggio, coherent long-form motion',
  Breakbeat: 'instrumental breakbeat, chopped syncopated drums, moving sub bass, compact hook, energetic urban momentum',
  'Drum and Bass': 'instrumental drum and bass, fast precise breakbeat, deep controlled sub bass, atmospheric harmonic layer',
  Cyberpunk: 'instrumental cyberpunk, dark electronic pulse, granular bass, neon synthesizer motif, cinematic industrial detail',
  'Hip-hop': 'instrumental hip-hop, human boom-bap pocket, deep bass, sampled harmonic colors, no rapping',
  Funk: 'instrumental funk, syncopated bass guitar, tight live drums, clipped rhythm guitar, bright brass accents',
  Jazz: 'instrumental modern jazz ensemble, acoustic bass, human swing, expressive piano and horn interplay',
  Classical: 'instrumental classical chamber orchestra, realistic acoustic dynamics, clear thematic development, natural hall',
  'Post-rock': 'instrumental post-rock, delayed guitars, patient live-band crescendo, spacious drums, cathartic melodic release',
  Cinematic: 'instrumental cinematic score, realistic orchestration, clear narrative arc, strong recurring theme, no trailer voice',
};

const TITLE_SEEDS = {
  Ambient: ['Тихий горизонт', 'Воздушное течение', 'Между небом и сном'],
  'Lo-fi': ['Пыль на кассете', 'Поздний чай', 'Окно во двор'],
  Classical: ['Камерный свет', 'После старого бала', 'Тени в фойе'],
  Jazz: ['Дымный поворот', 'Синий час', 'Свободный столик'],
  Electronic: ['Город внутри схемы', 'Цифровое тепло', 'Контур без имени'],
  'Post-rock': ['Море антенн', 'Долгий подъём', 'Свет после бури'],
  'Light Rave': ['После последнего поезда', 'Город перед рассветом', 'Пока не включили свет'],
  Fantasy: ['Корона древних', 'Зов рун', 'Пламя героев', 'Тёмный перевал', 'Лесная легенда'],
  'Dark Empire': ['Корона бездны', 'Бал чёрного владыки', 'Триумф тёмной цитадели', 'Последний трон', 'Марш великого завоевания'],
  Rock: ['Пыль на трассе', 'До красной черты', 'Громче ветра'],
  'Space Rock': ['За орбитой молчания', 'Пыль на иллюминаторе', 'Свет далёкой станции', 'Пока Земля не взошла', 'Четвёртая луна'],
  Pirate: ['За чёрным парусом', 'До первой звезды', 'Гавань за горизонтом', 'Когда вернутся чайки', 'Последняя бочка рома'],
  Metal: ['Стальной прилив', 'Чёрное пламя', 'Тяжёлая звезда'],
  'Thrash Metal': ['Точка удара', 'Ржавый вихрь', 'За красной чертой'],
  Cute: ['Карамельное облако', 'Маленькая радость', 'Плюшевый день'],
  Chaos: ['Сломанная орбита', 'Непослушное эхо', 'Всё одновременно'],
  Synthwave: ['Пурпурное шоссе', 'Солнце из хрома', 'Ночной протокол', 'Память под дождём', 'Стеклянный архив', 'Тёплый неон', 'Над пустошью', 'Дамба под чёрным небом'],
  House: ['Последний этаж', 'Четыре окна напротив', 'Крыша на рассвете'],
  Techno: ['Глубже под городом', 'Машинная память', 'Туннель без конца'],
  'Hard Techno': ['Красная зона', 'Двери закрываются', 'До смены караула'],
  'Industrial Techno': ['После третьей смены', 'Сломанный конвейер', 'Холодный цех'],
  Hardcore: ['За аварийной чертой', 'Аварийный свет', 'Предел прочности'],
  Psytrance: ['Ночная спираль', 'Квантовый лес', 'Портал частот'],
  Breakbeat: ['Погоня по крышам', 'Сдвиг координат', 'Мосты в движении'],
  'Drum and Bass': ['Быстрая река', 'Ломаный свет', 'Выше берегов'],
  Cyberpunk: ['Хромовый квартал', 'Город без сна', 'Тёмное будущее'],
  'Hip-hop': ['Квартал после дождя', 'Двор старой школы', 'Тень на ступенях'],
  Funk: ['Медный полдень', 'Солнечный двор', 'Костюм цвета мёда'],
  Cinematic: ['Дальний кадр', 'Перед титрами', 'Большая дорога'],
};

const FALLBACK_TITLES = ['За линией горизонта', 'До первых лучей', 'Где гаснут огни'];

const ARRANGEMENTS = {
  steady: 'controlled radio arrangement, stable groove, patient development, restrained transitions',
  charged: 'vivid high-motion arrangement, firm rhythmic propulsion, human micro-variation, active bass movement, short fills at phrase boundaries, motif variation every eight bars, brief breakdown then decisive full-band return, punchy transient attack and a strong climax, stable tonal center and coherent recurring theme',
};
const UINT64_MASK = (1n << 64n) - 1n;

const ATMOSPHERES = {
  calm: {
    focused: ['до первых лучей', 'у линии воды', 'перед открытым окном'], warm: ['у домашнего огня', 'в мягком свете'],
    dreamy: ['за серебряной дымкой', 'на краю сна'], dark: ['в глубокой тени', 'под поздней луной'],
    uplifting: ['к тихому рассвету', 'навстречу свету'],
  },
  balanced: {
    focused: ['между делом и мечтой', 'у открытого окна', 'на полях старой карты'], warm: ['до тёплого вечера', 'в живом свете'],
    dreamy: ['над дальним берегом', 'между явью и сном'], dark: ['после полуночи', 'над тёмной водой'],
    uplifting: ['над новым рассветом', 'выше облаков'],
  },
  driving: {
    focused: ['за линией горизонта', 'где гаснут дальние огни', 'до последнего поворота', 'между башнями и небом', 'по ту сторону ночи', 'пока город не уснул'], warm: ['в сиянии большого города', 'до жаркого рассвета'],
    dreamy: ['сквозь звёздный поток', 'за краем облаков'], dark: ['сквозь ночную бурю', 'на краю бездны'],
    uplifting: ['на полном ходу', 'навстречу новому дню'],
  },
};

const VIBE_PHRASES = [
  [['дожд', 'rain'], ['в зеркалах пустых улиц', 'там где фонари размыты']],
  [['ноч', 'night'], ['когда окна давно погасли', 'до первых птиц']],
  [['маг', 'чар', 'magic'], ['за дверью без ключа', 'там где сбываются старые карты']],
  [['мор', 'ocean', 'sea'], ['за линией солёного ветра', 'там где кончается берег']],
  [['лес', 'forest'], ['под древними кронами', 'там где не бывает троп']],
  [['косм', 'space', 'star'], ['за краем звёзд', 'между дальними созвездиями']],
  [['город', 'неон', 'city', 'neon'], ['среди отражений на стекле', 'выше спящих кварталов']],
  [['тьм', 'тём', 'dark'], ['на обратной стороне света', 'там куда не смотрит день']],
  [['уют', 'тепл', 'cozy', 'warm'], ['когда за окном холода', 'там где всегда ждут']],
];

function normalizeText(value, maxLength = 500) {
  return String(value ?? '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, maxLength);
}

function numericSeed(value = crypto.randomBytes(6).readUIntBE(0, 6)) {
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : crypto.randomBytes(6).readUIntBE(0, 6);
}

function pickTempo(genre, energy, seed) {
  const [common, lower, upper, surpriseStep] = TEMPO_PROFILES[genre] || TEMPO_PROFILES.Ambient;
  const offset = energy === 'calm' ? -1 : energy === 'driving' ? 2 : 0;
  const index = Math.min(Math.max(Number(mix64(seed) % BigInt(common.length)) + offset, 0), common.length - 1);
  let result = common[index];
  if (mix64(BigInt(seed) + 0x9E3779B97F4A7C15n) % 11n === 0n) {
    result += (Number(mix64(BigInt(seed) + 0xD1B54A32D192ED03n) % 3n) - 1) * surpriseStep;
  }
  return Math.min(Math.max(result, lower), upper);
}

function chooseGenres(selectedGenres, mixEnabled, seed) {
  const source = selectedGenres?.filter((genre) => GENRES.includes(genre));
  const available = source?.length ? [...new Set(source)] : GENRES;
  if (!mixEnabled || available.length < 2) return [available[seed % available.length]];
  const maximum = Math.min(5, available.length);
  const count = 2 + Number(mix64(seed) % BigInt(maximum - 1));
  return available.map((genre) => ({ genre, score: mix64(BigInt(seed) ^ stableTextHash(genre)) }))
    .sort((left, right) => left.score === right.score ? left.genre.localeCompare(right.genre) : left.score < right.score ? -1 : 1)
    .slice(0, count).map((item) => item.genre);
}

function mix64(input) {
  let value = (BigInt(input) + 0x9E3779B97F4A7C15n) & UINT64_MASK;
  value = ((value ^ (value >> 30n)) * 0xBF58476D1CE4E5B9n) & UINT64_MASK;
  value = ((value ^ (value >> 27n)) * 0x94D049BB133111EBn) & UINT64_MASK;
  return (value ^ (value >> 31n)) & UINT64_MASK;
}

function genreProfile(genre, energy, seed) {
  const definition = PROFILE_CATALOG[genre] || PROFILE_CATALOG.Ambient;
  const archetype = definition.details[Number(mix64(seed) % BigInt(definition.details.length))];
  const arrangement = energy === 'calm' ? ARRANGEMENTS.steady
    : energy === 'driving' ? ARRANGEMENTS.charged
      : Number(mix64(BigInt(seed) + 0xD1B54A32D192ED03n) % 2n) === 0 ? ARRANGEMENTS.steady : ARRANGEMENTS.charged;
  return `${definition.base}, ${archetype}, ${arrangement}`;
}

function profileCount(genre) {
  return (PROFILE_CATALOG[genre] || PROFILE_CATALOG.Ambient).details.length * 2;
}

function composePrompt(configuration) {
  const genres = configuration.genres?.length ? configuration.genres : ['Ambient'];
  const energy = configuration.energy || 'balanced';
  const energyText = energy === 'calm'
    ? 'low energy, restrained dynamics'
    : energy === 'driving'
      ? 'very high energy, urgent forward momentum, assertive full-range dynamics, punchy transient attack, active bass movement and a clear peak while preserving tonal center and coherent form'
      : 'balanced energy, steady dynamics';
  const mood = {
    focused: 'focused and unobtrusive', warm: 'warm and reassuring', dreamy: 'dreamy and spacious',
    dark: 'dark and introspective', uplifting: 'uplifting and optimistic',
  }[configuration.mood] || 'focused and unobtrusive';
  const parts = [
    genres.join(' blended with '),
    genres.map((genre, index) => `${genre}: ${genreProfile(genre, energy, BigInt(configuration.seed) + BigInt(index))}`).join('; '),
    `${configuration.tempoBPM} BPM`, energyText, mood,
    'instrumental background music for deep work, strictly no lyrics and no voice',
    'coherent arrangement, smooth development, no abrupt ending',
  ];
  if (genres.length > 1) {
    parts.push('intentional fusion: the first genre leads rhythm and form, the remaining genres add compatible instrumentation and color');
  }
  const vibe = normalizeText(configuration.vibe, 180);
  if (vibe) parts.push(vibe);
  return parts.join(', ');
}

function generateTitle(configuration, seed) {
  const genres = configuration.genres?.length ? configuration.genres : ['Ambient'];
  const genre = genres[seed % genres.length];
  const candidates = TITLE_SEEDS[genre] || FALLBACK_TITLES;
  const energy = ATMOSPHERES[configuration.energy] ? configuration.energy : 'balanced';
  const mood = ATMOSPHERES[energy][configuration.mood] ? configuration.mood : 'focused';
  const vibe = normalizeText(configuration.vibe, 180);
  const semanticOffset = stableTextHash(`${genres.join('|')}|${mood}|${vibe}`);
  const energyOffset = energy === 'calm' ? 0n : energy === 'balanced' ? 1n : 2n;
  const titleIndex = Number((BigInt(seed) + semanticOffset + BigInt(Math.floor((configuration.tempoBPM || 0) / 4)) + energyOffset) % BigInt(candidates.length));
  const phrases = VIBE_PHRASES.find(([keywords]) => keywords.some((keyword) => vibe.toLowerCase().includes(keyword)))?.[1]
    || ATMOSPHERES[energy][mood];
  const atmosphereIndex = Number(stableTextHash(`${seed}|${semanticOffset}|atmosphere`) % BigInt(phrases.length));
  return `${candidates[titleIndex]} ${phrases[atmosphereIndex]}`.split(/\s+/).slice(0, 10).join(' ');
}

function stableTextHash(text) {
  let value = 1469598103934665603n;
  for (const byte of Buffer.from(String(text), 'utf8')) {
    value = ((value ^ BigInt(byte)) * 1099511628211n) & UINT64_MASK;
  }
  return value;
}

function createStationConfiguration(settings, seedInput) {
  const seed = numericSeed(seedInput);
  const genres = chooseGenres(settings.selectedGenres, settings.mixGenresEnabled, seed);
  return {
    genres,
    energy: ['calm', 'balanced', 'driving'].includes(settings.energy) ? settings.energy : 'calm',
    mood: ['focused', 'warm', 'dreamy', 'dark', 'uplifting'].includes(settings.mood) ? settings.mood : 'focused',
    vibe: normalizeText(settings.vibe, 180),
    tempoBPM: pickTempo(genres[0], settings.energy, seed),
    seed,
  };
}

function formatBytes(bytes) {
  const safe = Math.max(0, Number(bytes) || 0);
  if (safe < 1024) return `${safe} байт`;
  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  let value = safe / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit += 1; }
  return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} ${units[unit]}`;
}

module.exports = {
  GENRES, GENRE_LABELS, composePrompt, createStationConfiguration, formatBytes, generateTitle,
  genreProfile, normalizeText, pickTempo, profileCount,
};
