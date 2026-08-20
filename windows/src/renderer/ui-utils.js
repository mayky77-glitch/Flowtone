(function exposeFlowtoneUI(root, factory) {
  const utilities = factory();
  if (typeof module === 'object' && module.exports) module.exports = utilities;
  else root.FlowtoneUI = utilities;
}(typeof globalThis === 'object' ? globalThis : this, () => {
  'use strict';

  const TOKENIZER_MESSAGE = 'Модель Stable Audio установлена не полностью. Откройте «Настроить модель» и нажмите «Восстановить».';
  const GENERATION_MESSAGE = 'Локальная модель завершила работу с ошибкой. Повторите попытку; если ошибка вернётся, восстановите модель.';
  const DOWNLOAD_MESSAGE = 'Не удалось скачать файлы модели. Проверьте интернет и повторите установку — уже загруженные данные сохранятся.';

  function userMessage(error) {
    const source = String(error?.message || error || 'Неизвестная ошибка')
      .replace(/^Error invoking remote method '[^']+':\s*/, '')
      .replace(/^Error:\s*/, '')
      .replace(/\s+/g, ' ')
      .trim();
    if (/tokenizer\.model|sentencepiece|LoadFromFile/i.test(source)) return TOKENIZER_MESSAGE;
    if (/fetch failed|network|ENOTFOUND|ECONNRESET|ETIMEDOUT|Не удалось скачать/i.test(source)) return DOWNLOAD_MESSAGE;
    if (/Traceback \(most recent call last\)|File "[^"]+", line \d+|RuntimeError:/i.test(source)) {
      return GENERATION_MESSAGE;
    }
    if (source.length <= 220) return source;
    return `${source.slice(0, 217).trimEnd()}…`;
  }

  async function settleControlChange({ commit, onSuccess = () => {}, onFailure = () => {} }) {
    try {
      const result = await commit();
      await onSuccess(result);
      return { ok: true, result };
    } catch (error) {
      await onFailure(error);
      return { ok: false, error };
    }
  }

  function formatDataSize(bytes) {
    const safe = Math.max(0, Number(bytes) || 0);
    if (safe < 1024) return `${Math.round(safe)} байт`;
    const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
    let value = safe / 1024;
    let index = 0;
    while (value >= 1024 && index < units.length - 1) { value /= 1024; index += 1; }
    return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} ${units[index]}`;
  }

  function downloadActivity(progress, now = Date.now()) {
    const bytes = Math.max(0, Number(progress?.downloadBytes) || 0);
    const speed = Math.max(0, Number(progress?.downloadBytesPerSecond) || 0);
    const total = Math.max(0, Number(progress?.downloadTotalBytes) || 0);
    const lastActivityAt = Number(progress?.downloadLastActivityAt) || now;
    const idleSeconds = Math.max(
      Number(progress?.downloadStalledForSeconds) || 0,
      Math.floor(Math.max(0, now - lastActivityAt) / 1000),
    );
    const completed = Math.max(0, Number(progress?.downloadCompletedFiles) || 0);
    const expected = Math.max(0, Number(progress?.downloadExpectedFiles) || 0);
    const parts = [`На диске ${formatDataSize(bytes)}`];
    if (speed > 0) parts.push(`${formatDataSize(speed)}/с`);
    if (total > 0) parts.push(`${Math.min(100, Math.floor(bytes / total * 100))}% файла`);
    if (expected > 0) parts.push(`готово файлов ${completed} из ${expected}`);

    if (speed > 0 && idleSeconds < 8) {
      return { state: 'active', label: 'ДАННЫЕ ИДУТ', text: parts.join(' · '), idleSeconds };
    }
    if (idleSeconds < 12) {
      return {
        state: 'waiting', label: bytes > 0 ? 'ПРОВЕРЯЮ ДАННЫЕ' : 'ПОДКЛЮЧЕНИЕ',
        text: `${parts.join(' · ')} · жду новые данные`, idleSeconds,
      };
    }
    if (idleSeconds < 60) {
      return {
        state: 'waiting', label: 'ОЖИДАНИЕ СЕТИ',
        text: `${parts.join(' · ')} · новых данных нет ${formatDuration(idleSeconds)}`, idleSeconds,
      };
    }
    return {
      state: 'stalled', label: 'ВОЗМОЖНО ЗАВИСЛО',
      text: `${parts.join(' · ')} · новых данных нет ${formatDuration(idleSeconds)}. Можно отменить и повторить — полученные файлы сохранятся.`,
      idleSeconds,
    };
  }

  function formatDuration(seconds) {
    const safe = Math.max(0, Math.floor(Number(seconds) || 0));
    return `${Math.floor(safe / 60)}:${String(safe % 60).padStart(2, '0')}`;
  }

  return { downloadActivity, formatDataSize, settleControlChange, userMessage };
}));
