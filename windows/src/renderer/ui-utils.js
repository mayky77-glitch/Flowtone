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

  return { settleControlChange, userMessage };
}));
