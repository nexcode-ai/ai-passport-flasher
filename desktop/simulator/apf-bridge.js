    (() => {
      const post = (message) => { try { window.webkit.messageHandlers.apf.postMessage(message); } catch (_) {} };
      HTMLDialogElement.prototype.showModal = function () {
        if (this.id === 'firmware-guidance') {
          const error = document.getElementById('firmware-upload-error');
          post({ type: 'error', message: error ? error.textContent : '' });
        }
      };
      const byId = (id) => document.getElementById(id);
      const text = (id) => ((byId(id) || {}).textContent || '').trim();
      const snapshot = () => {
        const recording = byId('recording-toggle');
        post({
          type: 'state',
          state: (byId('runtime-light') || { dataset: {} }).dataset.state || 'waiting',
          detail: text('runtime-state'),
          stage: text('loading-stage'),
          loadingDetail: text('loading-detail'),
          percent: parseInt(text('loading-percent'), 10) || 0,
          failed: !!(byId('screen-overlay') && byId('screen-overlay').classList.contains('is-error')),
          audio: !!byId('audio-enable') && byId('audio-enable').getAttribute('aria-pressed') === 'true',
          mic: !!byId('microphone-toggle') && byId('microphone-toggle').getAttribute('aria-pressed') === 'true',
          recording: !!recording && recording.getAttribute('aria-pressed') === 'true',
          recordingAvailable: !!recording && !recording.disabled,
        });
      };
      let timer = null;
      const schedule = () => { if (timer) return; timer = setTimeout(() => { timer = null; snapshot(); }, 90); };
      window.__apf = {
        click(id) { const element = byId(id); if (element) element.click(); },
        loadPreset(id) {
          const button = document.querySelector('.firmware-preset[data-firmware-id="' + id + '"]');
          if (button) button.click();
        },
        loadCommunity(id) {
          const input = byId('community-play-url');
          if (!input) return;
          input.value = 'https://ai-passport.folotoy.cn/plays/' + id + '/';
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        },
        downloadRecording() {
          const link = byId('recording-download');
          if (link && !link.hidden && link.href) link.click();
        },
        screenRect() {
          const rect = byId('qemu-display').getBoundingClientRect();
          return [rect.x, rect.y, rect.width, rect.height];
        },
        probe() {
          const root = document.querySelector('.emulator');
          return {
            styles: document.styleSheets.length,
            theme: [...document.styleSheets].some((sheet) => (sheet.href || '').endsWith('/apf-theme.css')),
            root: !!root,
            toolbarHidden: getComputedStyle(document.querySelector('.toolbar')).display === 'none',
            libraryHidden: getComputedStyle(document.querySelector('.try-panel')).display === 'none',
            physicalKeys: document.querySelectorAll('.hardware-key.apf-physical-key').length,
            holdRings: document.querySelectorAll('.hardware-key .apf-hold-ring').length,
            state: (byId('runtime-light') || { dataset: {} }).dataset.state,
          };
        },
      };
      document.addEventListener('DOMContentLoaded', () => {
        const shell = document.querySelector('.passport-shell');
        if (shell && !shell.querySelector('.apf-shell-content')) {
          const content = document.createElement('div');
          content.className = 'apf-shell-content';
          while (shell.firstChild) content.appendChild(shell.firstChild);
          shell.appendChild(content);
        }
        const keyVisuals = {
          POWER: { label: 'POWER', title: '电源 · P · 长按 2 秒', hold: 2000 },
          UP: { label: 'UP', title: '向上 · 键盘 ↑', hold: 0 },
          DOWN: { label: 'DOWN', title: '向下 · 键盘 ↓', hold: 0 },
          OK: { label: 'OK', title: '确认 · Return · 长按 0.5 秒', hold: 500 },
        };
        const keyButtons = new Map();
        const activeHolds = new Map();
        const stopHold = (key, completed = false) => {
          const active = activeHolds.get(key);
          if (active) cancelAnimationFrame(active.frame);
          activeHolds.delete(key);
          const button = keyButtons.get(key);
          if (!button) return;
          button.classList.remove('apf-holding');
          if (completed) {
            button.classList.add('apf-long-ready');
            setTimeout(() => {
              button.classList.remove('apf-long-ready');
              const path = button.querySelector('.apf-hold-ring circle');
              if (path) path.style.strokeDashoffset = '1';
            }, 260);
          } else {
            const path = button.querySelector('.apf-hold-ring circle');
            if (path) path.style.strokeDashoffset = '1';
          }
        };
        const startHold = (key) => {
          const visual = keyVisuals[key];
          const button = keyButtons.get(key);
          if (!button || !visual || !visual.hold || activeHolds.has(key)) return;
          const path = button.querySelector('.apf-hold-ring circle');
          const started = performance.now();
          button.classList.remove('apf-long-ready');
          button.classList.add('apf-holding');
          const tick = (now) => {
            const progress = Math.min(1, (now - started) / visual.hold);
            if (path) path.style.strokeDashoffset = String(1 - progress);
            if (progress >= 1) {
              activeHolds.delete(key);
              button.classList.remove('apf-holding');
              button.classList.add('apf-long-ready');
              return;
            }
            const active = activeHolds.get(key);
            if (active) active.frame = requestAnimationFrame(tick);
          };
          activeHolds.set(key, { frame: requestAnimationFrame(tick) });
        };
        for (const button of document.querySelectorAll('.hardware-key[data-key]')) {
          const key = button.dataset.key;
          const visual = keyVisuals[key];
          if (!visual) continue;
          keyButtons.set(key, button);
          button.classList.add('apf-physical-key');
          button.title = visual.title;
          button.setAttribute('aria-label', visual.title);
          button.replaceChildren();

          const face = document.createElement('span');
          face.className = 'apf-key-face';
          const label = document.createElement('span');
          label.className = 'apf-key-label';
          label.textContent = visual.label;
          button.append(face, label);

          if (visual.hold) {
            const ring = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            ring.classList.add('apf-hold-ring');
            ring.setAttribute('viewBox', '0 0 32 32');
            ring.setAttribute('aria-hidden', 'true');
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            path.setAttribute('cx', '16');
            path.setAttribute('cy', '16');
            path.setAttribute('r', '14');
            path.setAttribute('pathLength', '1');
            ring.append(path);
            button.append(ring);
            button.addEventListener('pointerdown', () => startHold(key));
            button.addEventListener('pointerup', () => stopHold(key, button.classList.contains('apf-long-ready')));
            button.addEventListener('pointercancel', () => stopHold(key));
          }
        }
        const shortcutKeys = { Enter: 'OK', p: 'POWER', P: 'POWER' };
        document.addEventListener('keydown', (event) => {
          const key = shortcutKeys[event.key];
          if (key && !event.repeat) startHold(key);
        });
        document.addEventListener('keyup', (event) => {
          const key = shortcutKeys[event.key];
          if (key) stopHold(key, keyButtons.get(key)?.classList.contains('apf-long-ready'));
        });
        window.addEventListener('blur', () => {
          for (const key of activeHolds.keys()) stopHold(key);
        });
        const watched = ['runtime-light', 'runtime-state', 'loading-stage', 'loading-percent', 'loading-detail',
          'screen-overlay', 'audio-enable', 'microphone-toggle', 'recording-toggle', 'recording-download'];
        const observer = new MutationObserver(schedule);
        for (const id of watched) {
          const element = byId(id);
          if (element) observer.observe(element, { attributes: true, childList: true, characterData: true, subtree: true });
        }
        snapshot();
        post({ type: 'ready' });
      });
    })();
    