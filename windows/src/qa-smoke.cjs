'use strict';

const fsp = require('node:fs/promises');
const path = require('node:path');

async function runCISmoke(window, { outputPath, screenshotPath, expectedPlatform = 'win32' }) {
  await window.webContents.executeJavaScript(`new Promise((resolve, reject) => {
    const deadline = Date.now() + 15000;
    const check = () => {
      if (document.documentElement.dataset.platform && typeof updateModelProgress === 'function') return resolve();
      if (Date.now() >= deadline) return reject(new Error('Renderer bootstrap timeout'));
      setTimeout(check, 50);
    };
    check();
  })`);

  const result = await window.webContents.executeJavaScript(`(async () => {
    const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
    const rect = (selector) => {
      const value = document.querySelector(selector).getBoundingClientRect();
      return { x: value.x, y: value.y, width: value.width, height: value.height, right: value.right, bottom: value.bottom };
    };
    const geometry = () => ({
      shell: rect('.app-shell'), sidebar: rect('.sidebar'), stage: rect('.stage'),
      rootScrollX: window.scrollX, rootScrollY: window.scrollY,
      documentWidth: document.documentElement.scrollWidth,
      viewportWidth: document.documentElement.clientWidth,
      documentHeight: document.documentElement.scrollHeight,
      viewportHeight: document.documentElement.clientHeight,
      sidebarScrollTop: document.querySelector('.sidebar-scroll').scrollTop,
    });
    const stableRect = (left, right) => ['x', 'y', 'width', 'height'].every((key) => Math.abs(left[key] - right[key]) < 0.6);
    const baseline = geometry();
    const toggles = [];
    for (const id of ['shuffle-toggle', 'mix-toggle', 'generation-toggle']) {
      const input = document.querySelector('#' + id);
      input.scrollIntoView({ block: 'center', inline: 'nearest' });
      const before = geometry();
      const oldValue = input.checked;
      input.closest('label').click();
      await wait(250);
      const after = geometry();
      toggles.push({
        id, oldValue, newValue: input.checked, before, after,
        passed: input.checked !== oldValue
          && after.rootScrollX === 0 && after.rootScrollY === 0
          && after.documentWidth <= after.viewportWidth
          && after.documentHeight <= after.viewportHeight
          && stableRect(baseline.shell, after.shell)
          && stableRect(baseline.sidebar, after.sidebar)
          && stableRect(baseline.stage, after.stage),
      });
    }

    const rollbackInput = document.querySelector('#shuffle-toggle');
    const rollbackExpected = state.settings.shuffleEnabled;
    rollbackInput.checked = !rollbackExpected;
    const rollbackBefore = geometry();
    const rollbackOutcome = await window.FlowtoneUI.settleControlChange({
      commit: () => Promise.reject(new Error('qa rollback')),
      onFailure: () => renderControls(),
    });
    await wait(50);
    const rollbackAfter = geometry();
    const rollback = {
      outcomeOK: rollbackOutcome.ok,
      expectedValue: rollbackExpected,
      actualValue: rollbackInput.checked,
      before: rollbackBefore,
      after: rollbackAfter,
      passed: rollbackOutcome.ok === false
        && rollbackInput.checked === rollbackExpected
        && rollbackAfter.rootScrollX === 0 && rollbackAfter.rootScrollY === 0
        && rollbackAfter.documentWidth <= rollbackAfter.viewportWidth
        && rollbackAfter.documentHeight <= rollbackAfter.viewportHeight
        && stableRect(baseline.shell, rollbackAfter.shell)
        && stableRect(baseline.sidebar, rollbackAfter.sidebar)
        && stableRect(baseline.stage, rollbackAfter.stage),
    };

    openModal(document.querySelector('#model-modal'));
    updateModelProgress({
      phase: 'downloading-model', title: 'Скачиваю музыкальную модель · этап 2 из 2',
      detail: 'Полоса показывает точные байты трёх обязательных файлов.',
      fraction: .5, downloadBytes: 543306376, downloadTotalBytes: 1086612752,
      downloadBytesPerSecond: 3145728, downloadCompletedFiles: 1, downloadExpectedFiles: 3,
      downloadLastActivityAt: Date.now(),
    });
    await wait(100);
    const bar = document.querySelector('#model-progress-bar');
    const modal = rect('#model-modal');
    const progress = {
      value: bar.value,
      percent: document.querySelector('#model-progress-percent').value,
      ariaValueText: bar.getAttribute('aria-valuetext'),
      activity: document.querySelector('#model-progress-activity').innerText,
      modal,
      horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
      passed: Math.abs(bar.value - .5) < .000001
        && document.querySelector('#model-progress-percent').value === '50%'
        && /50%/.test(bar.getAttribute('aria-valuetext') || '')
        && /ДАННЫЕ ИДУТ/.test(document.querySelector('#model-progress-activity').innerText)
        && modal.x >= 0 && modal.y >= 0 && modal.right <= innerWidth && modal.bottom <= innerHeight
        && document.documentElement.scrollWidth <= document.documentElement.clientWidth,
    };
    const runtimePath = document.querySelector('#runtime-path').textContent;
    const platform = document.documentElement.dataset.platform;
    const passed = platform === ${JSON.stringify(expectedPlatform)}
      && /Учкук/.test(runtimePath)
      && toggles.every((toggle) => toggle.passed)
      && rollback.passed
      && progress.passed;
    return { passed, platform, runtimePath, baseline, toggles, rollback, progress };
  })()`);

  await Promise.all([
    fsp.mkdir(path.dirname(outputPath), { recursive: true }),
    fsp.mkdir(path.dirname(screenshotPath), { recursive: true }),
  ]);
  await fsp.writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
  const image = await window.webContents.capturePage();
  await fsp.writeFile(screenshotPath, image.toPNG());
  if (!result.passed) throw new Error(`Windows Electron smoke failed: ${JSON.stringify(result)}`);
  return result;
}

module.exports = { runCISmoke };
