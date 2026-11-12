const webViewProbeFixtureVersion = 1;
const webViewProbeHandler = 'otzariaWebViewResourceProbe';

const webViewProbeHtml = r'''<!doctype html>
<html lang="he" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Otzaria WebView resource fixture</title>
<style>body{margin:16px;font:20px sans-serif}textarea{width:80%}
#page{height:12000px;background:linear-gradient(#fff,#ddd)}</style>
</head><body><h1>תוסף מדידה מקומי</h1><textarea id="draft"></textarea>
<div id="page">תוכן קבוע לגלילה ולשחזור מצב</div><script>
(() => {
  const draft = document.getElementById('draft');
  let revision = 0, ticks = 0, frames = 0, interval = null, frame = null;
  function stop() {
    if (interval !== null) clearInterval(interval);
    if (frame !== null) cancelAnimationFrame(frame);
    interval = frame = null;
  }
  function heartbeat() {
    stop();
    interval = setInterval(() => ticks++, 100);
    const tick = () => { frames++; frame = requestAnimationFrame(tick); };
    frame = requestAnimationFrame(tick);
  }
  function snapshot() {
    return {schemaVersion: 1, revision, draft: draft.value,
      scrollY: window.scrollY, ticks, frames, visibility: document.visibilityState,
      userAgent: navigator.userAgent};
  }
  function reply(id, value, error) {
    const payload = JSON.stringify({id, value, error});
    window.flutter_inappwebview.callHandler('otzariaWebViewResourceProbe', payload);
  }
  window.otzariaWebViewProbe = {
    command(request) {
      const {id, action, value} = request;
      try {
        switch (action) {
          case 'snapshot': break;
          case 'draft': draft.value = value; revision++; break;
          case 'heartbeat': heartbeat(); break;
          case 'stop': stop(); break;
          case 'paint':
            requestAnimationFrame(() => requestAnimationFrame(() => reply(id, snapshot())));
            return;
          case 'restore':
            if (value.schemaVersion !== 1 || typeof value.draft !== 'string' ||
                !Number.isSafeInteger(value.revision) || value.revision < 0 ||
                !Number.isFinite(value.scrollY) || value.scrollY < 0) {
              throw new Error('Invalid fixture snapshot');
            }
            draft.value = value.draft; revision = value.revision;
            window.scrollTo(0, value.scrollY);
            requestAnimationFrame(() => requestAnimationFrame(() => reply(id, snapshot())));
            return;
          case 'scroll': {
            let remaining = 60;
            const step = () => {
              window.scrollBy(0, 24);
              if (--remaining > 0) requestAnimationFrame(step);
              else reply(id, snapshot());
            };
            requestAnimationFrame(step);
            return;
          }
          default: throw new Error('Unknown fixture command: ' + action);
        }
        reply(id, snapshot());
      } catch (error) {
        reply(id, null, String(error));
      }
    }
  };
  window.addEventListener('pagehide', stop);
})();
</script></body></html>''';
