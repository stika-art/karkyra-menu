// Vercel Serverless Function: Telegram Webhook for Waiters & Orders
// Handles Telegram bot updates (@karkyra_ordersbot)

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://vgzdpbwcenckmjtgfvfw.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZnemRwYndjZW5ja21qdGdmdmZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2NDkxODAsImV4cCI6MjA5MjIyNTE4MH0.pFmPP9A9Tov4b6URS-LP5b3lYyB0fVXTKDvLY_MR120';
const DEFAULT_TG_TOKEN = process.env.TELEGRAM_TOKEN || '8714026573:AAG2XKdmJKvvk8UWYcKg6Z9dc4Ucgm4pqa0';

// In-memory state for pending auth pins: { [chatId]: { waiterId, waiterName } }
const pendingAuth = {};

async function getTelegramToken() {
  try {
    const res = await supabaseFetch('/admin_settings?key=eq.telegram_token&select=value');
    if (res && res[0] && res[0].value) {
      return res[0].value;
    }
  } catch (_) {}
  return DEFAULT_TG_TOKEN;
}

async function supabaseFetch(path, options = {}) {
  const url = `${SUPABASE_URL}/rest/v1${path}`;
  const headers = {
    'apikey': SUPABASE_KEY,
    'Authorization': `Bearer ${SUPABASE_KEY}`,
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...(options.headers || {})
  };
  const res = await fetch(url, { ...options, headers });
  if (!res.ok) {
    const errText = await res.text();
    console.error(`Supabase error [${res.status}]: ${errText}`);
    return null;
  }
  try {
    return await res.json();
  } catch (_) {
    return null;
  }
}

async function callTgApi(method, payload) {
  const token = await getTelegramToken();
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    return await res.json();
  } catch (err) {
    console.error(`Telegram API error (${method}):`, err);
    return null;
  }
}

// Helper: answer callback query
async function answerCallbackQuery(cqId, text, showAlert = false) {
  return await callTgApi('answerCallbackQuery', {
    callback_query_id: cqId,
    text: text || '',
    show_alert: showAlert
  });
}

// Helper: send message
async function sendTgMessage(chatId, text, extra = {}) {
  return await callTgApi('sendMessage', {
    chat_id: chatId,
    text: text,
    parse_mode: 'HTML',
    ...extra
  });
}

// Helper: edit message text
async function editTgMessage(chatId, messageId, text, extra = {}) {
  return await callTgApi('editMessageText', {
    chat_id: chatId,
    message_id: messageId,
    text: text,
    parse_mode: 'HTML',
    ...extra
  });
}

// Helper: edit reply markup
async function editTgReplyMarkup(chatId, messageId, replyMarkup) {
  return await callTgApi('editMessageReplyMarkup', {
    chat_id: chatId,
    message_id: messageId,
    reply_markup: replyMarkup
  });
}

// Find waiter by chatId
async function getWaiterByChatId(chatId) {
  if (!chatId) return null;
  const waiters = await supabaseFetch(`/waiters?telegram_chat_id=eq.${chatId}&select=*`);
  return waiters && waiters.length > 0 ? waiters[0] : null;
}

// Natural sort for table labels: "Стол 1", "Стол 2", ..., "Стол 10"
function sortTables(tables) {
  return [...tables].sort((a, b) => {
    const numA = parseInt((a.label || '').replace(/[^0-9]/g, '')) || 0;
    const numB = parseInt((b.label || '').replace(/[^0-9]/g, '')) || 0;
    if (numA !== numB) return numA - numB;
    return (a.label || '').localeCompare(b.label || '');
  });
}

// Generate the tables inline keyboard
async function buildTablesKeyboard(currentWaiter) {
  const [tables, allWaiters] = await Promise.all([
    supabaseFetch('/restaurant_tables?select=*'),
    supabaseFetch('/waiters?select=id,name')
  ]);

  if (!tables) return { text: 'Ошибка загрузки столов из базы данных.', reply_markup: { inline_keyboard: [] } };

  const waitersMap = {};
  if (allWaiters) {
    for (const w of allWaiters) {
      waitersMap[w.id] = w.name;
    }
  }

  const sorted = sortTables(tables);
  const rows = [];
  let currentRow = [];

  for (const table of sorted) {
    const isMine = currentWaiter && table.waiter_id === currentWaiter.id;
    const isFree = !table.waiter_id;
    let btnText = '';
    let cbData = '';

    const labelClean = table.label.replace(/^Стол\s*/i, '№');

    if (isMine) {
      btnText = `🟢 ${labelClean} (Мой)`;
      cbData = `tbl_toggle:${table.id}`;
    } else if (isFree) {
      btnText = `⚪ ${labelClean}`;
      cbData = `tbl_toggle:${table.id}`;
    } else {
      const otherName = waitersMap[table.waiter_id] || 'Занят';
      btnText = `🔒 ${labelClean} (${otherName})`;
      cbData = `tbl_locked:${table.id}`;
    }

    currentRow.push({ text: btnText, callback_data: cbData });
    if (currentRow.length === 2) {
      rows.push(currentRow);
      currentRow = [];
    }
  }
  if (currentRow.length > 0) {
    rows.push(currentRow);
  }

  // Action buttons at the bottom
  rows.push([
    { text: '🔄 Обновить столы', callback_data: 'tbl_refresh' },
    { text: '❌ Снять все мои столы', callback_data: 'tbl_release_all' }
  ]);

  const myTables = sorted.filter(t => currentWaiter && t.waiter_id === currentWaiter.id);
  const myTablesText = myTables.length > 0 
    ? myTables.map(t => t.label).join(', ') 
    : 'нет закрепленных столов';

  const text = `🪑 <b>Управление столами: ${currentWaiter ? currentWaiter.name : 'Официант'}</b>\n\n` +
    `🟢 — Закреплен за вами\n` +
    `⚪ — Свободен (нажмите, чтобы взять)\n` +
    `🔒 — Занят другим официантом\n\n` +
    `📌 <b>Ваши активные столы:</b> ${myTablesText}\n\n` +
    `<i>Нажимайте на кнопки столов ниже для выбора:</i>`;

  return { text, reply_markup: { inline_keyboard: rows } };
}

// Persistent Menu Keyboard
function getMainKeyboard() {
  return {
    keyboard: [
      [{ text: '🪑 Мои столы' }, { text: '🔔 Активные вызовы' }],
      [{ text: '🍽 Текущие заказы' }, { text: '🚪 Сменить официанта' }]
    ],
    resize_keyboard: true
  };
}

module.exports = async function handler(req, res) {
  // Support GET for health-check and webhook installation
  if (req.method === 'GET') {
    const { setup_webhook } = req.query || {};
    if (setup_webhook) {
      const host = req.headers['x-forwarded-host'] || req.headers.host || 'altyn-kazyk.vercel.app';
      const proto = req.headers['x-forwarded-proto'] || 'https';
      const webhookUrl = `${proto}://${host}/api/telegram`;
      const token = await getTelegramToken();
      const r = await fetch(`https://api.telegram.org/bot${token}/setWebhook?url=${encodeURIComponent(webhookUrl)}`);
      const info = await r.json();
      return res.status(200).json({ setup: true, webhookUrl, telegramResponse: info });
    }
    return res.status(200).json({
      status: 'ok',
      service: 'Altyn Kazyk Waiter Bot',
      timestamp: new Date().toISOString()
    });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Parse body
  let body = req.body;
  if (typeof body === 'string') {
    try {
      body = JSON.parse(body);
    } catch (_) {}
  }
  if (!body) {
    return res.status(200).json({ ok: true });
  }

  try {
    // -------------------------------------------------------------
    // 1. Handle CALLBACK QUERY (Inline buttons)
    // -------------------------------------------------------------
    if (body.callback_query) {
      const cq = body.callback_query;
      const cqId = cq.id;
      const data = cq.data || '';
      const chatId = cq.message?.chat?.id;
      const messageId = cq.message?.message_id;
      const fromUser = cq.from;

      let waiter = await getWaiterByChatId(chatId);
      // If triggered from a group chat, also check by user id
      if (!waiter && fromUser?.id) {
        waiter = await getWaiterByChatId(fromUser.id);
      }

      // Action: Select Waiter profile during auth
      if (data.startsWith('auth_select:')) {
        const waiterId = data.replace('auth_select:', '');
        const targetWaiters = await supabaseFetch(`/waiters?id=eq.${waiterId}&select=*`);
        const target = targetWaiters && targetWaiters[0];
        if (!target) {
          await answerCallbackQuery(cqId, 'Официант не найден.', true);
          return res.status(200).json({ ok: true });
        }

        // If waiter has no PIN or empty PIN, bind immediately
        if (!target.pin || target.pin === '0000' || target.pin === '1234') {
          await supabaseFetch(`/waiters?id=eq.${target.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ telegram_chat_id: chatId.toString() })
          });
          await answerCallbackQuery(cqId, `Успешно! Вы вошли как ${target.name}`);
          const kbData = await buildTablesKeyboard(target);
          await sendTgMessage(chatId, `🎉 <b>Добро пожаловать, ${target.name}!</b>\n\nВы успешно привязали Telegram. Теперь выберите ваши столы:`, {
            reply_markup: getMainKeyboard()
          });
          await sendTgMessage(chatId, kbData.text, { reply_markup: kbData.reply_markup });
          return res.status(200).json({ ok: true });
        }

        // Wait for PIN
        pendingAuth[chatId] = { waiterId: target.id, waiterName: target.name };
        await answerCallbackQuery(cqId, `Введите ПИН-код для ${target.name}`);
        await sendTgMessage(chatId, `🔐 Введите 4-значный ПИН-код для подтверждения (официант: <b>${target.name}</b>):`);
        return res.status(200).json({ ok: true });
      }

      // Action: Table locked by another waiter
      if (data.startsWith('tbl_locked:')) {
        const tableId = data.replace('tbl_locked:', '');
        const t = await supabaseFetch(`/restaurant_tables?id=eq.${tableId}&select=label,waiters(name)`);
        const name = t && t[0]?.waiters?.name ? t[0].waiters.name : 'другим официантом';
        await answerCallbackQuery(cqId, `⚠️ Стол уже обслуживает ${name}`, true);
        return res.status(200).json({ ok: true });
      }

      // Action: Toggle Table (take or release)
      if (data.startsWith('tbl_toggle:')) {
        if (!waiter) {
          await answerCallbackQuery(cqId, 'Сначала авторизуйтесь через /start', true);
          return res.status(200).json({ ok: true });
        }

        const tableId = data.replace('tbl_toggle:', '');
        const tables = await supabaseFetch(`/restaurant_tables?id=eq.${tableId}&select=*`);
        const table = tables && tables[0];
        if (!table) {
          await answerCallbackQuery(cqId, 'Стол не найден.', true);
          return res.status(200).json({ ok: true });
        }

        if (table.waiter_id === waiter.id) {
          // Release
          await supabaseFetch(`/restaurant_tables?id=eq.${tableId}`, {
            method: 'PATCH',
            body: JSON.stringify({ waiter_id: null })
          });
          await answerCallbackQuery(cqId, `Стол ${table.label} освобождён`);
        } else if (!table.waiter_id) {
          // Claim
          await supabaseFetch(`/restaurant_tables?id=eq.${tableId}`, {
            method: 'PATCH',
            body: JSON.stringify({ waiter_id: waiter.id })
          });
          await answerCallbackQuery(cqId, `Стол ${table.label} взят вами! ✅`);
        } else {
          await answerCallbackQuery(cqId, '⚠️ Этот стол только что занял другой официант.', true);
        }

        // Re-render table keyboard
        const kbData = await buildTablesKeyboard(waiter);
        await editTgMessage(chatId, messageId, kbData.text, { reply_markup: kbData.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Release All My Tables
      if (data === 'tbl_release_all') {
        if (!waiter) {
          await answerCallbackQuery(cqId, 'Сначала авторизуйтесь через /start', true);
          return res.status(200).json({ ok: true });
        }
        await supabaseFetch(`/restaurant_tables?waiter_id=eq.${waiter.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ waiter_id: null })
        });
        await answerCallbackQuery(cqId, 'Все ваши столы освобождены!');
        const kbData = await buildTablesKeyboard(waiter);
        await editTgMessage(chatId, messageId, kbData.text, { reply_markup: kbData.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Refresh Tables
      if (data === 'tbl_refresh') {
        await answerCallbackQuery(cqId, 'Столы обновлены!');
        const kbData = await buildTablesKeyboard(waiter);
        await editTgMessage(chatId, messageId, kbData.text, { reply_markup: kbData.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Accept Waiter Call ("Иду к столу!")
      if (data.startsWith('call_accept:')) {
        const parts = data.split(':');
        const callId = parts[1];
        const tableId = parts[2] || '';

        // Update database: status = 'accepted'
        await supabaseFetch(`/waiter_calls?id=eq.${callId}`, {
          method: 'PATCH',
          body: JSON.stringify({ status: 'accepted' })
        });

        // Also if waiter is known, we can bind table to them if unassigned
        if (waiter && tableId) {
          const cleanNum = tableId.replace(/[^0-9]/g, '');
          if (cleanNum) {
            await supabaseFetch(`/restaurant_tables?label=ilike.%25${cleanNum}%25&waiter_id=is.null`, {
              method: 'PATCH',
              body: JSON.stringify({ waiter_id: waiter.id })
            });
          }
        }

        const waiterName = waiter ? waiter.name : (fromUser?.first_name || 'Официант');
        await answerCallbackQuery(cqId, `🏃‍♂️ Вы приняли вызов стола №${tableId}! Гость видит: «Официант уже идет».`, true);

        // Edit message with action done
        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
        const oldText = cq.message?.text || `🔔 ВЫЗОВ ОФИЦИАНТА! Стол №${tableId}`;
        const newText = `${oldText}\n\n🏃‍♂️ <b>ПРИНЯТ (${waiterName} идет к столу) в ${nowStr}</b>`;

        await editTgMessage(chatId, messageId, newText, {
          reply_markup: {
            inline_keyboard: [
              [{ text: `✅ Обслужен (Стол №${tableId})`, callback_data: `call_done:${callId}:${tableId}` }]
            ]
          }
        });
        return res.status(200).json({ ok: true });
      }

      // Action: Complete Waiter Call ("Обслужен")
      if (data.startsWith('call_done:')) {
        const parts = data.split(':');
        const callId = parts[1];
        const tableId = parts[2] || '';

        await supabaseFetch(`/waiter_calls?id=eq.${callId}`, {
          method: 'PATCH',
          body: JSON.stringify({ status: 'completed' })
        });

        const waiterName = waiter ? waiter.name : (fromUser?.first_name || 'Официант');
        await answerCallbackQuery(cqId, `✅ Вызов со стола №${tableId} обслужен!`);

        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
        const oldText = cq.message?.text || `🔔 ВЫЗОВ ОФИЦИАНТА! Стол №${tableId}`;
        const cleanOld = oldText.replace(/\n\n🏃‍♂️.*$/g, '');
        const newText = `${cleanOld}\n\n✅ <b>ОБСЛУЖЕН (${waiterName}) в ${nowStr}</b>`;

        await editTgMessage(chatId, messageId, newText, {
          reply_markup: { inline_keyboard: [] }
        });
        return res.status(200).json({ ok: true });
      }

      // Action: Change Order Status
      if (data.startsWith('order_status:')) {
        const parts = data.split(':');
        const tableId = parts[1];
        const newStatus = parts[2];

        const cleanNum = tableId.replace(/[^0-9]/g, '');
        await supabaseFetch(`/orders_new?table_id=eq.${tableId}`, {
          method: 'PATCH',
          body: JSON.stringify({ status: newStatus })
        });
        if (cleanNum && cleanNum !== tableId) {
          await supabaseFetch(`/orders_new?table_id=eq.${cleanNum}`, {
            method: 'PATCH',
            body: JSON.stringify({ status: newStatus })
          });
        }

        const statusRu = newStatus === 'processing' ? '👨‍🍳 Готовится' : '🍽 Подано';
        await answerCallbackQuery(cqId, `Статус заказа: ${statusRu}`);

        const oldText = cq.message?.text || '';
        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
        const updatedText = `${oldText}\n\n📌 <b>Статус: ${statusRu} (${nowStr})</b>`;

        const nextButtons = newStatus === 'processing'
          ? [
              [{ text: '🍽 Подано', callback_data: `order_status:${tableId}:served` }],
              [{ text: '🧾 Расчёт / Освободить стол', callback_data: `table_clear:${tableId}` }]
            ]
          : [
              [{ text: '🧾 Расчёт / Освободить стол', callback_data: `table_clear:${tableId}` }]
            ];

        await editTgMessage(chatId, messageId, updatedText, {
          reply_markup: { inline_keyboard: nextButtons }
        });
        return res.status(200).json({ ok: true });
      }

      // Action: Table Clear (Завершить чек и очистить стол)
      if (data.startsWith('table_clear:')) {
        const tableId = data.replace('table_clear:', '');
        const cleanNum = tableId.replace(/[^0-9]/g, '');

        // 1. Mark orders completed for analytics
        await supabaseFetch(`/orders_new?table_id=eq.${tableId}&status=neq.completed`, {
          method: 'PATCH',
          body: JSON.stringify({ status: 'completed' })
        });
        // 2. Delete active session & participants
        await supabaseFetch(`/table_sessions?table_id=eq.${tableId}`, { method: 'DELETE' });
        await supabaseFetch(`/table_participants?table_id=eq.${tableId}`, { method: 'DELETE' });

        if (cleanNum && cleanNum !== tableId) {
          await supabaseFetch(`/orders_new?table_id=eq.${cleanNum}&status=neq.completed`, {
            method: 'PATCH',
            body: JSON.stringify({ status: 'completed' })
          });
          await supabaseFetch(`/table_sessions?table_id=eq.${cleanNum}`, { method: 'DELETE' });
          await supabaseFetch(`/table_participants?table_id=eq.${cleanNum}`, { method: 'DELETE' });
        }

        await answerCallbackQuery(cqId, `Стол №${tableId} рассчитан и освобождён! 🎉`, true);
        const oldText = cq.message?.text || '';
        await editTgMessage(chatId, messageId, `${oldText}\n\n🧾 <b>СТОЛ РАССЧИТАН И ЗАКРЫТ</b>`, {
          reply_markup: { inline_keyboard: [] }
        });
        return res.status(200).json({ ok: true });
      }

      await answerCallbackQuery(cqId);
      return res.status(200).json({ ok: true });
    }

    // -------------------------------------------------------------
    // 2. Handle TEXT MESSAGES & COMMANDS
    // -------------------------------------------------------------
    if (body.message) {
      const msg = body.message;
      const chatId = msg.chat.id;
      const text = (msg.text || '').trim();

      let waiter = await getWaiterByChatId(chatId);

      // A. Check if user is typing a PIN for pending auth
      if (pendingAuth[chatId]) {
        const pending = pendingAuth[chatId];
        const target = await supabaseFetch(`/waiters?id=eq.${pending.waiterId}&select=*`);
        if (target && target[0] && target[0].pin === text) {
          delete pendingAuth[chatId];
          await supabaseFetch(`/waiters?id=eq.${pending.waiterId}`, {
            method: 'PATCH',
            body: JSON.stringify({ telegram_chat_id: chatId.toString() })
          });
          const kbData = await buildTablesKeyboard(target[0]);
          await sendTgMessage(chatId, `🎉 <b>Успешно!</b> Вы вошли как <b>${target[0].name}</b>.\n\nТеперь выберите столы, которые вы обслуживаете:`, {
            reply_markup: getMainKeyboard()
          });
          await sendTgMessage(chatId, kbData.text, { reply_markup: kbData.reply_markup });
          return res.status(200).json({ ok: true });
        } else {
          await sendTgMessage(chatId, `❌ Неверный ПИН-код для <b>${pending.waiterName}</b>. Попробуйте еще раз или выберите другого официанта через /start:`);
          return res.status(200).json({ ok: true });
        }
      }

      // Direct PIN input without prior selection (e.g. user just typed "0000" or "1234")
      if (/^\d{4}$/.test(text) && !waiter) {
        const matches = await supabaseFetch(`/waiters?pin=eq.${text}&select=*`);
        if (matches && matches.length === 1) {
          const matchedWaiter = matches[0];
          await supabaseFetch(`/waiters?id=eq.${matchedWaiter.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ telegram_chat_id: chatId.toString() })
          });
          const kbData = await buildTablesKeyboard(matchedWaiter);
          await sendTgMessage(chatId, `🎉 <b>Успешно!</b> Вы вошли как <b>${matchedWaiter.name}</b>.\n\nВыберите ваши столы:`, {
            reply_markup: getMainKeyboard()
          });
          await sendTgMessage(chatId, kbData.text, { reply_markup: kbData.reply_markup });
          return res.status(200).json({ ok: true });
        }
      }

      // Command: /start
      if (text === '/start') {
        if (waiter) {
          const kbData = await buildTablesKeyboard(waiter);
          await sendTgMessage(chatId, `👋 Здравствуйте, <b>${waiter.name}</b>!\nВы авторизованы как официант Altyn Kazyk.`, {
            reply_markup: getMainKeyboard()
          });
          await sendTgMessage(chatId, kbData.text, { reply_markup: kbData.reply_markup });
          return res.status(200).json({ ok: true });
        }

        // Waiter not authorized -> show list of waiters
        const allWaiters = await supabaseFetch('/waiters?is_active=neq.false&select=*&order=name.asc');
        if (!allWaiters || allWaiters.length === 0) {
          await sendTgMessage(chatId, '❌ В системе нет зарегистрированных официантов. Обратитесь к администратору ресторана.');
          return res.status(200).json({ ok: true });
        }

        const buttons = allWaiters.map(w => ([
          { text: `👤 ${w.name}`, callback_data: `auth_select:${w.id}` }
        ]));

        await sendTgMessage(chatId, `👋 <b>Добро пожаловать в Altyn Kazyk!</b>\n\nЭтот бот предназначен для официантов ресторана: приём вызовов, заказов и управление столами.\n\n<b>Пожалуйста, выберите ваше имя из списка:</b>`, {
          reply_markup: { inline_keyboard: buttons }
        });
        return res.status(200).json({ ok: true });
      }

      // Command: /tables or button "🪑 Мои столы"
      if (text === '/tables' || text === '🪑 Мои столы') {
        if (!waiter) {
          await sendTgMessage(chatId, '⚠️ Вы еще не авторизованы. Нажмите /start, чтобы выбрать свой профиль официанта.');
          return res.status(200).json({ ok: true });
        }
        const kbData = await buildTablesKeyboard(waiter);
        await sendTgMessage(chatId, kbData.text, { reply_markup: kbData.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Command: /calls or button "🔔 Активные вызовы"
      if (text === '/calls' || text === '🔔 Активные вызовы') {
        if (!waiter) {
          await sendTgMessage(chatId, '⚠️ Вы еще не авторизованы. Нажмите /start.');
          return res.status(200).json({ ok: true });
        }

        const myTables = await supabaseFetch(`/restaurant_tables?waiter_id=eq.${waiter.id}&select=id,label`);
        const myTableIds = myTables ? myTables.map(t => t.id) : [];

        // Fetch pending or accepted calls
        const calls = await supabaseFetch('/waiter_calls?status=in.(pending,accepted)&order=created_at.desc&limit=10');

        if (!calls || calls.length === 0) {
          await sendTgMessage(chatId, '🔔 Нет активных вызовов официанта. Все столы обслужены! 👍');
          return res.status(200).json({ ok: true });
        }

        for (const c of calls) {
          const tId = c.table_id || '';
          const isMine = myTableIds.includes(tId) || myTables?.some(mt => mt.label?.includes(tId));
          const time = new Date(c.created_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
          const statusText = c.status === 'accepted' ? '🏃‍♂️ Официант идет' : '⏳ Ожидает';

          const msgText = `🔔 <b>Вызов со стола №${tId}</b>\n⏰ Время: ${time}\nСтатус: <b>${statusText}</b>${isMine ? ' (Ваш стол)' : ''}`;
          const buttons = c.status === 'accepted'
            ? [[{ text: `✅ Завершить (Стол №${tId})`, callback_data: `call_done:${c.id}:${tId}` }]]
            : [
                [
                  { text: `🏃‍♂️ Иду к столу №${tId}!`, callback_data: `call_accept:${c.id}:${tId}` },
                  { text: `✅ Обслужен`, callback_data: `call_done:${c.id}:${tId}` }
                ]
              ];

          await sendTgMessage(chatId, msgText, { reply_markup: { inline_keyboard: buttons } });
        }
        return res.status(200).json({ ok: true });
      }

      // Command: /orders or button "🍽 Текущие заказы"
      if (text === '/orders' || text === '🍽 Текущие заказы') {
        if (!waiter) {
          await sendTgMessage(chatId, '⚠️ Вы еще не авторизованы. Нажмите /start.');
          return res.status(200).json({ ok: true });
        }

        const myTables = await supabaseFetch(`/restaurant_tables?waiter_id=eq.${waiter.id}&select=id,label`);
        const myTableIds = myTables ? myTables.map(t => t.id) : [];

        const activeOrders = await supabaseFetch('/orders_new?status=in.(confirmed,processing,served)&order=created_at.desc&limit=15');
        if (!activeOrders || activeOrders.length === 0) {
          await sendTgMessage(chatId, '🍽 Активных заказов нет.');
          return res.status(200).json({ ok: true });
        }

        // Filter for my tables or show all if none assigned
        const filtered = myTableIds.length > 0
          ? activeOrders.filter(o => myTableIds.includes(o.table_id) || myTables?.some(mt => mt.label?.includes(o.table_id)))
          : activeOrders;

        if (filtered.length === 0) {
          await sendTgMessage(chatId, '🍽 На ваших столах сейчас нет активных заказов.');
          return res.status(200).json({ ok: true });
        }

        for (const ord of filtered.slice(0, 5)) {
          const items = Array.isArray(ord.items) ? ord.items : [];
          const itemLines = items.map(it => `• ${it.title} x${it.qty || 1} — ${it.price} сом`).join('\n');
          const time = new Date(ord.created_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });

          const msgText = `🍽 <b>Заказ стола №${ord.table_id}</b> (${time})\n\n${itemLines}\n\n💰 <b>Итого: ${ord.total_amount || 0} сом</b>\nСтатус: <b>${ord.status}</b>`;

          await sendTgMessage(chatId, msgText, {
            reply_markup: {
              inline_keyboard: [
                [
                  { text: '👨‍🍳 Готовится', callback_data: `order_status:${ord.table_id}:processing` },
                  { text: '🍽 Подано', callback_data: `order_status:${ord.table_id}:served` }
                ],
                [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${ord.table_id}` }]
              ]
            }
          });
        }
        return res.status(200).json({ ok: true });
      }

      // Command: /logout or button "🚪 Сменить официанта"
      if (text === '/logout' || text === '🚪 Сменить официанта' || text === '🚪 Выйти') {
        if (waiter) {
          await supabaseFetch(`/waiters?id=eq.${waiter.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ telegram_chat_id: null })
          });
        }
        delete pendingAuth[chatId];
        await sendTgMessage(chatId, '🚪 Вы вышли из профиля официанта.\n\nЧтобы войти снова, нажмите /start.', {
          reply_markup: { remove_keyboard: true }
        });
        return res.status(200).json({ ok: true });
      }

      // Default fallback
      if (!waiter) {
        await sendTgMessage(chatId, '👋 Нажмите /start для выбора профиля официанта.');
      } else {
        await sendTgMessage(chatId, `👋 Официант: <b>${waiter.name}</b>\n\nИспользуйте меню внизу или команды:\n/tables — Мои столы\n/calls — Вызовы гостей\n/orders — Заказы\n/logout — Сменить профиль`, {
          reply_markup: getMainKeyboard()
        });
      }
      return res.status(200).json({ ok: true });
    }

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('Webhook error:', err);
    return res.status(200).json({ ok: true, error: err.message });
  }
};
