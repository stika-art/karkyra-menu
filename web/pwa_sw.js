self.addEventListener('install', (e) => {
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  return self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  // Пропускаем все сетевые запросы напрямую, чтобы всегда была актуальная версия.
  // Этого достаточно для активации PWA-кнопки в браузере.
  e.respondWith(
    fetch(e.request).catch(() => new Response('Требуется подключение к интернету.'))
  );
});
