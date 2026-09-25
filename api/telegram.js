// Vercel Serverless Function: Telegram Webhook for Waiters & Orders
// Handles Telegram bot updates (@altynkazyk_bot)

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://vgzdpbwcenckmjtgfvfw.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZnemRwYndjZW5ja21qdGdmdmZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2NDkxODAsImV4cCI6MjA5MjIyNTE4MH0.pFmPP9A9Tov4b6URS-LP5b3lYyB0fVXTKDvLY_MR120';
const DEFAULT_TG_TOKEN = process.env.TELEGRAM_TOKEN || '8874121083:AAH0YfzG_M-VZ-E_oFBmDe1FhgUY3wLcA_A';

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

async function getAdminChatId() {
  try {
    const res = await supabaseFetch('/admin_settings?key=eq.telegram_chat_id&select=value');
    if (res && res[0] && res[0].value) {
      return res[0].value;
    }
  } catch (_) {}
  return null;
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

// Helpers: Stored Telegram messages for group + waiter sync
async function getStoredTgMessages(key) {
  try {
    const res = await supabaseFetch(`/admin_settings?key=eq.${key}&select=value`);
    if (res && res[0] && res[0].value) {
      const parsed = JSON.parse(res[0].value);
      if (Array.isArray(parsed)) return parsed;
    }
  } catch (_) {}
  return [];
}

async function removeStoredTgMessages(key) {
  try {
    await supabaseFetch(`/admin_settings?key=eq.${key}`, { method: 'DELETE' });
  } catch (_) {}
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

// Persistent Waiter Menu Keyboard
function getMainKeyboard() {
  return {
    keyboard: [
      [{ text: '🪑 Мои столы' }, { text: '🔔 Активные вызовы' }],
      [{ text: '🍽 Текущие заказы' }, { text: '🚪 Выйти / Сдать смену' }]
    ],
    resize_keyboard: true
  };
}

// Persistent Admin Menu Keyboard
function getAdminKeyboard() {
  return {
    keyboard: [
      [{ text: '📊 Сводка за день' }, { text: '🪑 Все столы' }],
      [{ text: '🍽 Все заказы' }, { text: '🔔 Активные вызовы' }],
      [{ text: '🛵 Доставка' }, { text: '📅 Брони' }],
      [{ text: '👥 Официанты на смене' }, { text: '🔄 Обновить статус' }],
      [{ text: '🚪 Выйти из админки' }]
    ],
    resize_keyboard: true
  };
}

// Admin: Map of all tables with assigned waiter names and active order/call status
async function buildAdminTablesOverview() {
  const [tables, allWaiters, activeCalls, activeOrders] = await Promise.all([
    supabaseFetch('/restaurant_tables?select=*'),
    supabaseFetch('/waiters?select=id,name'),
    supabaseFetch('/waiter_calls?status=in.(pending,accepted)&select=table_id,status'),
    supabaseFetch('/orders_new?status=in.(confirmed,processing,served)&select=table_id')
  ]);

  if (!tables) return { text: 'Ошибка загрузки столов из базы данных.', reply_markup: { inline_keyboard: [] } };

  const waitersMap = {};
  if (allWaiters) {
    for (const w of allWaiters) {
      waitersMap[w.id] = w.name;
    }
  }

  const callingTableIds = new Set((activeCalls || []).map(c => String(c.table_id).replace(/[^0-9]/g, '')));
  const activeOrderTableIds = new Set((activeOrders || []).map(o => String(o.table_id).replace(/[^0-9]/g, '')));

  const sorted = sortTables(tables);
  let occupiedCount = 0;
  let text = '🪑 <b>Карта столов ресторана Altyn Kazyk</b>\n\n';

  for (const t of sorted) {
    const cleanNum = (t.label || '').replace(/[^0-9]/g, '');
    const waiterName = t.waiter_id ? (waitersMap[t.waiter_id] || 'Официант') : null;
    const isCalling = callingTableIds.has(cleanNum) || callingTableIds.has(t.id);
    const hasOrder = activeOrderTableIds.has(cleanNum) || activeOrderTableIds.has(t.id);

    let statusEmoji = '⚪';
    let info = 'Свободен';

    if (waiterName) {
      occupiedCount++;
      statusEmoji = '🟢';
      info = `Официант: <b>${waiterName}</b>`;
    }

    if (hasOrder) {
      info += ' • 🍽 <i>Заказ активен</i>';
    }
    if (isCalling) {
      info += ' • 🔔 <b>ВЫЗОВ!</b>';
    }

    text += `${statusEmoji} <b>${t.label}</b>: ${info}\n`;
  }

  text += `\n📊 <b>Итого:</b> Закреплено столов: <b>${occupiedCount} из ${sorted.length}</b>`;

  const inlineKeyboard = [
    [
      { text: '🔄 Обновить столы', callback_data: 'admin_refresh_tables' },
      { text: '❌ Освободить все столы', callback_data: 'admin_clear_all_tables' }
    ]
  ];

  return { text, reply_markup: { inline_keyboard: inlineKeyboard } };
}

// Admin: Daily Stats
async function buildAdminDailyStats() {
  const now = new Date();
  const bishkekOffsetMs = 6 * 60 * 60 * 1000;
  const bishkekNow = new Date(now.getTime() + bishkekOffsetMs);
  const yyyy = bishkekNow.getUTCFullYear();
  const mm = String(bishkekNow.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(bishkekNow.getUTCDate()).padStart(2, '0');
  const todayStartUtc = new Date(Date.UTC(yyyy, bishkekNow.getUTCMonth(), bishkekNow.getUTCDate()) - bishkekOffsetMs).toISOString();

  const [orders, menuItems, deliveryOrders, calls, tables, waiters] = await Promise.all([
    supabaseFetch(`/orders_new?created_at=gte.${todayStartUtc}&select=id,table_id,menu_item_id,quantity,status`),
    supabaseFetch('/menu_items_db?select=id,title,price'),
    supabaseFetch(`/delivery_orders?created_at=gte.${todayStartUtc}&select=id,total,status`),
    supabaseFetch('/waiter_calls?status=in.(pending,accepted)&select=id,status'),
    supabaseFetch('/restaurant_tables?select=id,waiter_id'),
    supabaseFetch('/waiters?is_active=neq.false&select=id,name,telegram_chat_id')
  ]);

  const menuMap = {};
  if (menuItems) {
    for (const m of menuItems) {
      menuMap[m.id] = Number(m.price) || 0;
    }
  }

  let tableRevenue = 0;
  let activeTableDishesCount = 0;
  const completedTableSets = new Set();

  if (orders) {
    for (const o of orders) {
      const price = menuMap[o.menu_item_id] || 0;
      const sum = (Number(o.quantity) || 1) * price;
      if (o.status === 'completed') {
        tableRevenue += sum;
        if (o.table_id) completedTableSets.add(o.table_id);
      } else if (['confirmed', 'processing', 'served'].includes(o.status)) {
        activeTableDishesCount++;
      }
    }
  }

  let deliveryRevenue = 0;
  let completedDeliveryCount = 0;
  if (deliveryOrders) {
    for (const d of deliveryOrders) {
      if (d.status === 'delivered' || d.status === 'completed') {
        deliveryRevenue += Number(d.total) || 0;
        completedDeliveryCount++;
      }
    }
  }

  const totalRevenue = tableRevenue + deliveryRevenue;
  const totalCompletedChecks = completedTableSets.size + completedDeliveryCount;
  const avgCheck = totalCompletedChecks > 0 ? Math.round(totalRevenue / totalCompletedChecks) : 0;

  const totalTables = tables ? tables.length : 0;
  const busyTables = tables ? tables.filter(t => t.waiter_id).length : 0;
  const activeWaiters = waiters ? waiters.filter(w => w.telegram_chat_id).length : 0;
  const pendingCalls = calls ? calls.filter(c => c.status === 'pending').length : 0;

  return `📊 <b>Сводка за день (${dd}.${mm}.${yyyy})</b>\n` +
    `🏛 <b>Ресторан Altyn Kazyk</b>\n\n` +
    `💰 <b>Общая выручка:</b> <b>${totalRevenue.toLocaleString('ru-RU')} сом</b>\n` +
    `🍽 Зал: ${tableRevenue.toLocaleString('ru-RU')} сом | 🛵 Доставка: ${deliveryRevenue.toLocaleString('ru-RU')} сом\n` +
    `🧾 <b>Оплаченных счетов:</b> <b>${totalCompletedChecks}</b>\n` +
    `📈 <b>Средний чек:</b> <b>${avgCheck.toLocaleString('ru-RU')} сом</b>\n\n` +
    `─── <b>Текущая обстановка:</b> ───\n` +
    `🍽 <b>Активных блюд в процессе:</b> ${activeTableDishesCount}\n` +
    `🔔 <b>Ожидают официанта:</b> ${pendingCalls}\n` +
    `🪑 <b>Столов на смене:</b> ${busyTables} из ${totalTables}\n` +
    `👥 <b>Официантов онлайн в TG:</b> ${activeWaiters} из ${(waiters || []).length}\n\n` +
    `<i>Данные обновлены в реальном времени.</i>`;
}

// Admin: Waiters on duty
async function buildAdminWaitersList(showAll = false) {
  const [waiters, tables] = await Promise.all([
    supabaseFetch('/waiters?select=*&order=name.asc'),
    supabaseFetch('/restaurant_tables?select=id,label,waiter_id')
  ]);

  if (!waiters || waiters.length === 0) {
    return {
      text: '👥 <b>Сотрудники не найдены.</b>\nДобавьте официантов в веб-панели администратора.',
      reply_markup: { inline_keyboard: [] }
    };
  }

  const waiterTables = {};
  if (tables) {
    for (const t of tables) {
      if (t.waiter_id) {
        if (!waiterTables[t.waiter_id]) waiterTables[t.waiter_id] = [];
        waiterTables[t.waiter_id].push(t.label);
      }
    }
  }

  const activeWaiters = waiters.filter(w => w.telegram_chat_id || (waiterTables[w.id] && waiterTables[w.id].length > 0));
  const actionButtons = [];
  let text = '';

  if (!showAll) {
    if (activeWaiters.length === 0) {
      text = '👥 <b>Официанты на смене:</b>\n\n' +
        '⚪ <b>Сейчас на смене никого нет.</b>\n' +
        'Все официанты сдали смену или не подключены.\n';
    } else {
      text = `👥 <b>Официанты на смене (${activeWaiters.length}):</b>\n\n`;
      for (const w of activeWaiters) {
        const tablesList = (waiterTables[w.id] && waiterTables[w.id].length > 0)
          ? waiterTables[w.id].join(', ')
          : 'столы ещё не выбраны';
        const pin = w.pin || 'нет';

        text += `🟢 👤 <b>${w.name}</b> (Онлайн)\n` +
          `   🪑 Столы: <b>${tablesList}</b>\n` +
          `   🔐 ПИН-код: <code>${pin}</code>\n\n`;

        actionButtons.push([
          { text: `🚪 Снять со смены: ${w.name}`, callback_data: `admin_unbind:${w.id}` }
        ]);
      }
    }

    actionButtons.push([
      { text: `📋 Все сотрудники (${waiters.length})`, callback_data: 'admin_waiters_all' },
      { text: '🔄 Обновить', callback_data: 'admin_refresh_waiters' }
    ]);
  } else {
    text = `👥 <b>Все сотрудники ресторана (${waiters.length}):</b>\n\n`;
    for (const w of waiters) {
      const isLinked = !!w.telegram_chat_id;
      let shiftStatus = '';
      if (w.is_active === false) {
        shiftStatus = '🚫 Деактивирован';
      } else if (isLinked) {
        shiftStatus = '🟢 На смене';
      } else {
        shiftStatus = '⚪ Смена сдана (Вышел)';
      }

      const tgStatus = isLinked ? `🟢 Привязан (ID: <code>${w.telegram_chat_id}</code>)` : `⚪ Не в сети (вышел)`;
      const tablesList = (waiterTables[w.id] && waiterTables[w.id].length > 0)
        ? waiterTables[w.id].join(', ')
        : 'нет закрепленных столов';
      const pin = w.pin || 'нет';

      text += `👤 <b>${w.name}</b> — <b>${shiftStatus}</b>\n` +
        `   📱 Telegram: ${tgStatus}\n` +
        `   🔐 ПИН-код: <code>${pin}</code>\n` +
        `   🪑 Столы: ${tablesList}\n\n`;

      if (isLinked) {
        actionButtons.push([
          { text: `🚪 Снять со смены: ${w.name}`, callback_data: `admin_unbind:${w.id}` }
        ]);
      }
    }

    actionButtons.push([
      { text: '👥 Только на смене', callback_data: 'admin_waiters_active' },
      { text: '🔄 Обновить', callback_data: 'admin_waiters_all' }
    ]);
  }

  return { text, reply_markup: { inline_keyboard: actionButtons } };
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

      const adminChatId = await getAdminChatId();
      const adminIds = (adminChatId || '').split(',').map(s => s.trim()).filter(Boolean);
      const isAdminChat = adminIds.includes(String(chatId)) || adminIds.includes(String(fromUser?.id));
      const isGroupChat = cq.message?.chat?.type === 'group' || cq.message?.chat?.type === 'supergroup' || (chatId && Number(chatId) < 0);
      const isAuthorized = (waiter && waiter.is_active !== false) || isAdminChat || isGroupChat;

      // Action: Select Waiter profile during auth
      if (data.startsWith('auth_select:')) {
        const waiterId = data.replace('auth_select:', '');
        const targetWaiters = await supabaseFetch(`/waiters?id=eq.${waiterId}&is_active=neq.false&select=*`);
        const target = targetWaiters && targetWaiters[0];
        if (!target) {
          await answerCallbackQuery(cqId, 'Официант не найден или деактивирован.', true);
          return res.status(200).json({ ok: true });
        }

        if (target.telegram_chat_id && target.telegram_chat_id !== chatId.toString()) {
          await answerCallbackQuery(cqId, '⚠️ Этот профиль уже привязан к другому телефону!', true);
          await sendTgMessage(chatId, `⚠️ Профиль официанта <b>${target.name}</b> уже привязан к другому Telegram-аккаунту.\n\nЕсли вы сменили устройство или потеряли телефон, обратитесь к администратору для сброса привязки.`);
          return res.status(200).json({ ok: true });
        }

        // Wait for PIN
        pendingAuth[chatId] = { waiterId: target.id, waiterName: target.name };
        await answerCallbackQuery(cqId, `Введите ПИН-код для ${target.name}`);
        await sendTgMessage(chatId, `🔐 Введите 4-значный ПИН-код для подтверждения (официант: <b>${target.name}</b>):`);
        return res.status(200).json({ ok: true });
      }

      // SECURITY CHECK: Разрешено официантам, администратору и участникам рабочего чата ресторана!
      if (!isAuthorized) {
        await answerCallbackQuery(cqId, '🚫 Доступ заблокирован. Вы не являетесь сотрудником ресторана.', true);
        await sendTgMessage(chatId, '🚫 <b>Доступ запрещен</b>\n\nВы не авторизованы в системе ресторана.\nДля работы обратитесь к администратору или отправьте /start.', {
          reply_markup: { remove_keyboard: true }
        });
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

      // Action: Admin clear all tables
      if (data === 'admin_clear_all_tables') {
        if (!isAdminChat) {
          await answerCallbackQuery(cqId, 'Доступно только администратору.', true);
          return res.status(200).json({ ok: true });
        }
        await supabaseFetch('/restaurant_tables?waiter_id=not.is.null', {
          method: 'PATCH',
          body: JSON.stringify({ waiter_id: null })
        });
        await answerCallbackQuery(cqId, 'Все столы освобождены от официантов! 🧹', true);
        const tbData = await buildAdminTablesOverview();
        await editTgMessage(chatId, messageId, tbData.text, { reply_markup: tbData.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Admin refresh tables
      if (data === 'admin_refresh_tables') {
        await answerCallbackQuery(cqId, 'Карта столов обновлена!');
        const tbData = await buildAdminTablesOverview();
        await editTgMessage(chatId, messageId, tbData.text, { reply_markup: tbData.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Admin refresh waiters list (only active on shift by default)
      if (data === 'admin_refresh_waiters' || data === 'admin_waiters_active') {
        await answerCallbackQuery(cqId, 'Официанты на смене');
        const wl = await buildAdminWaitersList(false);
        await editTgMessage(chatId, messageId, wl.text, { reply_markup: wl.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Admin view all restaurant waiters
      if (data === 'admin_waiters_all') {
        await answerCallbackQuery(cqId, 'Все сотрудники ресторана');
        const wl = await buildAdminWaitersList(true);
        await editTgMessage(chatId, messageId, wl.text, { reply_markup: wl.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Admin unbind waiter
      if (data.startsWith('admin_unbind:')) {
        if (!isAdminChat) {
          await answerCallbackQuery(cqId, 'Доступно только администратору.', true);
          return res.status(200).json({ ok: true });
        }
        const waiterId = data.replace('admin_unbind:', '');
        const targetRes = await supabaseFetch(`/waiters?id=eq.${waiterId}&select=*`);
        const target = targetRes && targetRes[0];
        if (!target) {
          await answerCallbackQuery(cqId, 'Официант не найден.', true);
          return res.status(200).json({ ok: true });
        }

        // Notify waiter in their personal Telegram chat if linked
        if (target.telegram_chat_id) {
          try {
            await sendTgMessage(target.telegram_chat_id, '🔒 <b>Администратор сбросил вашу привязку к Telegram.</b>\n\nСмена завершена. Для повторного входа обратитесь к администратору или отправьте /start.', {
              reply_markup: { remove_keyboard: true }
            });
          } catch (_) {}
        }

        // 1. Release tables
        await supabaseFetch(`/restaurant_tables?waiter_id=eq.${waiterId}`, {
          method: 'PATCH',
          body: JSON.stringify({ waiter_id: null })
        });
        // 2. Clear telegram_chat_id
        await supabaseFetch(`/waiters?id=eq.${waiterId}`, {
          method: 'PATCH',
          body: JSON.stringify({ telegram_chat_id: null })
        });

        await answerCallbackQuery(cqId, `Официант ${target.name} отвязан и снят со столов! ✅`, true);
        const wl = await buildAdminWaitersList();
        await editTgMessage(chatId, messageId, wl.text, { reply_markup: wl.reply_markup });
        return res.status(200).json({ ok: true });
      }

      // Action: Accept Waiter Call ("Иду к столу!")
      if (data.startsWith('call_accept:')) {
        const parts = data.split(':');
        const callId = parts[1];
        const tableId = parts[2] || '';
        const cleanNum = tableId.replace(/[^0-9]/g, '') || tableId;

        // Update database: status = 'accepted'
        await supabaseFetch(`/waiter_calls?id=eq.${callId}`, {
          method: 'PATCH',
          body: JSON.stringify({ status: 'accepted' })
        });

        // Also if waiter is known, bind table to them if unassigned
        if (waiter && cleanNum) {
          await supabaseFetch(`/restaurant_tables?label=ilike.%25${cleanNum}%25&waiter_id=is.null`, {
            method: 'PATCH',
            body: JSON.stringify({ waiter_id: waiter.id })
          });
        }

        const waiterName = waiter ? waiter.name : (isAdminChat ? 'Администратор' : (fromUser?.first_name || 'Официант'));
        await answerCallbackQuery(cqId, `🏃‍♂️ Вы приняли вызов стола №${tableId}! Гость видит: «Официант уже идет».`, true);

        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
        
        // Find all linked messages (both admin group and waiter personal chat)
        let msgList = await getStoredTgMessages(`tg_call_${callId}`);
        if (!msgList.some(m => String(m.chat_id) === String(chatId) && Number(m.message_id) === Number(messageId))) {
          msgList.push({ chat_id: chatId, message_id: messageId, original_text: cq.message?.text });
        }

        const nextButtons = [
          [{ text: `✅ Обслужен (Стол №${tableId})`, callback_data: `call_done:${callId}:${cleanNum}` }]
        ];

        for (const m of msgList) {
          const mChatId = m.chat_id;
          const mMessageId = m.message_id;
          const isClicker = String(mChatId) === String(chatId);
          const baseText = m.original_text || cq.message?.text || `🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>\n\n🪑 Стол: <b>№${tableId}</b>`;
          const cleanText = baseText.replace(/\n\n🏃‍♂️.*$/gs, '');
          const statusText = isClicker
            ? `\n\n🏃‍♂️ <b>ВЫ ПРИНЯЛИ ВЫЗОВ (идете к столу) в ${nowStr}</b>`
            : `\n\n🏃‍♂️ <b>ПРИНЯТ (${waiterName} идет к столу) в ${nowStr}</b>`;

          await editTgMessage(mChatId, mMessageId, cleanText + statusText, {
            reply_markup: { inline_keyboard: nextButtons }
          });
        }

        return res.status(200).json({ ok: true });
      }

      // Action: Complete Waiter Call ("Обслужен")
      if (data.startsWith('call_done:')) {
        const parts = data.split(':');
        const callId = parts[1];
        const tableId = parts[2] || '';
        const cleanNum = tableId.replace(/[^0-9]/g, '') || tableId;

        await supabaseFetch(`/waiter_calls?id=eq.${callId}`, {
          method: 'PATCH',
          body: JSON.stringify({ status: 'completed' })
        });

        const waiterName = waiter ? waiter.name : (isAdminChat ? 'Администратор' : (fromUser?.first_name || 'Официант'));
        await answerCallbackQuery(cqId, `✅ Вызов со стола №${tableId} обслужен!`);

        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
        
        let msgList = await getStoredTgMessages(`tg_call_${callId}`);
        if (!msgList.some(m => String(m.chat_id) === String(chatId) && Number(m.message_id) === Number(messageId))) {
          msgList.push({ chat_id: chatId, message_id: messageId, original_text: cq.message?.text });
        }

        for (const m of msgList) {
          const mChatId = m.chat_id;
          const mMessageId = m.message_id;
          const baseText = m.original_text || cq.message?.text || `🔔 <b>ВЫЗОВ ОФИЦИАНТА!</b>\n\n🪑 Стол: <b>№${tableId}</b>`;
          const cleanText = baseText.replace(/\n\n🏃‍♂️.*$/gs, '');
          const statusText = `\n\n✅ <b>ОБСЛУЖЕН (${waiterName}) в ${nowStr}</b>`;

          await editTgMessage(mChatId, mMessageId, cleanText + statusText, {
            reply_markup: { inline_keyboard: [] }
          });
        }

        await removeStoredTgMessages(`tg_call_${callId}`);
        return res.status(200).json({ ok: true });
      }

      // Action: Change Order Status
      if (data.startsWith('order_status:')) {
        const parts = data.split(':');
        const tableId = parts[1];
        const newStatus = parts[2];
        const cleanNum = tableId.replace(/[^0-9]/g, '') || tableId;

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

        const waiterName = waiter ? waiter.name : (isAdminChat ? 'Администратор' : (fromUser?.first_name || 'Официант'));
        const statusRu = newStatus === 'processing' 
          ? `👨‍🍳 Готовится (Принял: ${waiterName})` 
          : `🍽 Подано (${waiterName})`;
        await answerCallbackQuery(cqId, `Статус заказа: ${statusRu}`);

        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });

        const nextButtons = newStatus === 'processing'
          ? [
              [{ text: '🍽 Подано', callback_data: `order_status:${cleanNum}:served` }],
              [{ text: '🧾 Расчёт / Освободить стол', callback_data: `table_clear:${cleanNum}` }]
            ]
          : [
              [{ text: '🧾 Расчёт / Освободить стол', callback_data: `table_clear:${cleanNum}` }]
            ];

        let msgList = await getStoredTgMessages(`tg_order_${cleanNum}`);
        if (!msgList.some(m => String(m.chat_id) === String(chatId) && Number(m.message_id) === Number(messageId))) {
          msgList.push({ chat_id: chatId, message_id: messageId, original_text: cq.message?.text });
        }

        for (const m of msgList) {
          const mChatId = m.chat_id;
          const mMessageId = m.message_id;
          const baseText = m.original_text || cq.message?.text || `🍽 <b>Новый заказ!</b>\n\n🪑 Стол: <b>№${tableId}</b>`;
          const cleanText = baseText.replace(/\n\n📌 <b>Статус:.*$/gs, '');
          const statusText = `\n\n📌 <b>Статус: ${statusRu} в ${nowStr}</b>`;

          await editTgMessage(mChatId, mMessageId, cleanText + statusText, {
            reply_markup: { inline_keyboard: nextButtons }
          });
        }

        return res.status(200).json({ ok: true });
      }

      // Action: Table Clear (Завершить чек и очистить стол)
      if (data.startsWith('table_clear:')) {
        const tableId = data.replace('table_clear:', '');
        const cleanNum = tableId.replace(/[^0-9]/g, '') || tableId;

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

        const waiterName = waiter ? waiter.name : (isAdminChat ? 'Администратор' : (fromUser?.first_name || 'Официант'));
        await answerCallbackQuery(cqId, `Стол №${tableId} рассчитан и освобождён! 🎉`, true);
        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });

        let msgList = await getStoredTgMessages(`tg_order_${cleanNum}`);
        if (!msgList.some(m => String(m.chat_id) === String(chatId) && Number(m.message_id) === Number(messageId))) {
          msgList.push({ chat_id: chatId, message_id: messageId, original_text: cq.message?.text });
        }

        for (const m of msgList) {
          const mChatId = m.chat_id;
          const mMessageId = m.message_id;
          const baseText = m.original_text || cq.message?.text || `🍽 <b>Новый заказ!</b>\n\n🪑 Стол: <b>№${tableId}</b>`;
          const cleanText = baseText.replace(/\n\n📌 <b>Статус:.*$/gs, '');
          const statusText = `\n\n🧾 <b>СТОЛ РАССЧИТАН И ЗАКРЫТ (${waiterName} в ${nowStr})</b>`;

          await editTgMessage(mChatId, mMessageId, cleanText + statusText, {
            reply_markup: { inline_keyboard: [] }
          });
        }

        await removeStoredTgMessages(`tg_order_${cleanNum}`);
        return res.status(200).json({ ok: true });
      }

      // Action: Delivery Status Update
      if (data.startsWith('deliv_status:')) {
        const parts = data.split(':');
        const orderId = parts[1];
        const newStatus = parts[2];

        await supabaseFetch(`/delivery_orders?id=eq.${orderId}`, {
          method: 'PATCH',
          body: JSON.stringify({ status: newStatus })
        });

        const actorName = waiter ? waiter.name : (isAdminChat ? 'Администратор' : (fromUser?.first_name || 'Сотрудник'));
        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });

        let statusText = '';
        let nextButtons = [];

        if (newStatus === 'processing') {
          statusText = `\n\n📌 <b>Статус: 👨‍🍳 ПРИНЯТО, ГОТОВИМ (${actorName} в ${nowStr})</b>`;
          nextButtons = [
            [{ text: '🛵 Отправлено курьером', callback_data: `deliv_status:${orderId}:delivering` }],
            [{ text: '❌ Отменить заказ', callback_data: `deliv_status:${orderId}:cancelled` }]
          ];
          await answerCallbackQuery(cqId, 'Доставка принята в готовку! 👨‍🍳');
        } else if (newStatus === 'delivering') {
          statusText = `\n\n📌 <b>Статус: 🛵 ОТПРАВЛЕНО КУРЬЕРУ (${actorName} в ${nowStr})</b>`;
          nextButtons = [
            [{ text: '✅ Доставлен (Завершить)', callback_data: `deliv_status:${orderId}:delivered` }]
          ];
          await answerCallbackQuery(cqId, 'Заказ передан курьеру! 🛵');
        } else if (newStatus === 'delivered' || newStatus === 'done') {
          statusText = `\n\n📌 <b>Статус: ✅ ЗАКАЗ ДОСТАВЛЕН И ОПЛАЧЕН (${actorName} в ${nowStr})</b>`;
          nextButtons = [];
          await answerCallbackQuery(cqId, 'Доставка успешно завершена! 🎉');
        } else if (newStatus === 'cancelled') {
          statusText = `\n\n📌 <b>Статус: ❌ ЗАКАЗ ДОСТАВКИ ОТМЕНЁН (${actorName} в ${nowStr})</b>`;
          nextButtons = [];
          await answerCallbackQuery(cqId, 'Заказ отменён.');
        }

        const baseText = cq.message?.text || `🛵 <b>Заказ на доставку #${orderId.slice(0, 8)}</b>`;
        const cleanText = baseText.replace(/\n\n📌 <b>Статус:.*$/gs, '');

        await editTgMessage(chatId, messageId, cleanText + statusText, {
          reply_markup: { inline_keyboard: nextButtons }
        });
        return res.status(200).json({ ok: true });
      }

      // Action: Booking Status Update
      if (data.startsWith('book_status:')) {
        const parts = data.split(':');
        const bookingId = parts[1];
        const action = parts[2];

        // Fetch booking to find table_id
        const bRes = await supabaseFetch(`/bookings?id=eq.${bookingId}&select=*`);
        const b = bRes && bRes[0];

        const actorName = waiter ? waiter.name : (isAdminChat ? 'Администратор' : (fromUser?.first_name || 'Сотрудник'));
        const nowStr = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });

        let statusText = '';
        let nextButtons = [];

        if (action === 'accept') {
          await supabaseFetch(`/bookings?id=eq.${bookingId}`, {
            method: 'PATCH',
            body: JSON.stringify({ status: 'accepted' })
          });
          statusText = `\n\n📌 <b>Статус: ✅ БРОНЬ ПОДТВЕРЖДЕНА (${actorName} в ${nowStr})</b>`;
          nextButtons = [
            [{ text: '🪑 Освободить стол / Завершить', callback_data: `book_status:${bookingId}:done` }]
          ];
          await answerCallbackQuery(cqId, 'Бронь подтверждена! ✅');
        } else if (action === 'cancel') {
          await supabaseFetch(`/bookings?id=eq.${bookingId}`, {
            method: 'PATCH',
            body: JSON.stringify({ status: 'cancelled' })
          });
          if (b && b.table_id) {
            await supabaseFetch(`/restaurant_tables?id=eq.${b.table_id}`, {
              method: 'PATCH',
              body: JSON.stringify({ is_booked: false })
            });
          }
          statusText = `\n\n📌 <b>Статус: ❌ БРОНЬ ОТКЛОНЕНА (${actorName} в ${nowStr})</b>`;
          nextButtons = [];
          await answerCallbackQuery(cqId, 'Бронь отклонена.');
        } else if (action === 'done') {
          await supabaseFetch(`/bookings?id=eq.${bookingId}`, {
            method: 'PATCH',
            body: JSON.stringify({ status: 'completed' })
          });
          if (b && b.table_id) {
            await supabaseFetch(`/restaurant_tables?id=eq.${b.table_id}`, {
              method: 'PATCH',
              body: JSON.stringify({ is_booked: false })
            });
          }
          statusText = `\n\n📌 <b>Статус: 🪑 БРОНЬ ЗАВЕРШЕНА, СТОЛ СВОБОДЕН (${actorName} в ${nowStr})</b>`;
          nextButtons = [];
          await answerCallbackQuery(cqId, 'Стол успешно освобожден! 🧹');
        }

        const baseText = cq.message?.text || `📅 <b>Бронь стола</b>`;
        const cleanText = baseText.replace(/\n\n📌 <b>Статус:.*$/gs, '');

        await editTgMessage(chatId, messageId, cleanText + statusText, {
          reply_markup: { inline_keyboard: nextButtons }
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

      // Always reset any pending auth on /start
      if (text === '/start') {
        delete pendingAuth[chatId];
      }

      const adminChatId = await getAdminChatId();
      const adminIds = (adminChatId || '').split(',').map(s => s.trim()).filter(Boolean);
      const isAdmin = adminIds.includes(String(chatId)) || adminIds.includes(String(msg.from?.id));
      let waiter = await getWaiterByChatId(chatId);

      // Check for Admin password entry or /admin command
      const adminPassRes = await supabaseFetch('/admin_settings?key=eq.admin_password&select=value');
      const adminPassword = (adminPassRes && adminPassRes[0]?.value) || '2026';

      if (text === `/admin ${adminPassword}` || text === adminPassword || text.toLowerCase() === '/admin') {
        if (text.toLowerCase() === '/admin') {
          pendingAuth[chatId] = { role: 'admin' };
          await sendTgMessage(chatId, '🔐 Введите ключ доступа:');
          return res.status(200).json({ ok: true });
        }

        delete pendingAuth[chatId];
        const currentAdminSetting = await supabaseFetch('/admin_settings?key=eq.telegram_chat_id&select=value');
        const currentVal = (currentAdminSetting && currentAdminSetting[0]?.value) || '';
        const ids = currentVal.split(',').map(s => s.trim()).filter(Boolean);
        if (!ids.includes(String(chatId))) {
          ids.push(String(chatId));
          await supabaseFetch('/admin_settings?key=eq.telegram_chat_id', {
            method: 'PATCH',
            body: JSON.stringify({ value: ids.join(',') })
          });
        }

        await sendTgMessage(chatId, `👑 <b>Авторизация Администратора успешна!</b>\n\nЭтот Telegram аккаунт привязан как главный Администратор ресторана Altyn Kazyk.\n\nВам доступен полный контроль над заказами, столами и персоналом.`, {
          reply_markup: getAdminKeyboard()
        });
        return res.status(200).json({ ok: true });
      }

      // A. Check if user is typing a PIN or password for pending auth
      if (pendingAuth[chatId]) {
        const pending = pendingAuth[chatId];

        // 1. Pending Admin Auth
        if (pending.role === 'admin') {
          if (text === adminPassword) {
            delete pendingAuth[chatId];
            const currentAdminSetting = await supabaseFetch('/admin_settings?key=eq.telegram_chat_id&select=value');
            const currentVal = (currentAdminSetting && currentAdminSetting[0]?.value) || '';
            const ids = currentVal.split(',').map(s => s.trim()).filter(Boolean);
            if (!ids.includes(String(chatId))) {
              ids.push(String(chatId));
              await supabaseFetch('/admin_settings?key=eq.telegram_chat_id', {
                method: 'PATCH',
                body: JSON.stringify({ value: ids.join(',') })
              });
            }

            await sendTgMessage(chatId, `👑 <b>Авторизация Администратора успешна!</b>\n\nЭтот Telegram аккаунт привязан как главный Администратор ресторана Altyn Kazyk.\n\nВам доступен полный контроль над заказами, столами и персоналом.`, {
              reply_markup: getAdminKeyboard()
            });
            return res.status(200).json({ ok: true });
          } else {
            delete pendingAuth[chatId];
            await sendTgMessage(chatId, '❌ Неверный ключ доступа.');
            return res.status(200).json({ ok: true });
          }
        }

        // 2. Pending Waiter PIN
        const target = await supabaseFetch(`/waiters?id=eq.${pending.waiterId}&select=*`);
        if (target && target[0] && target[0].pin === text) {
          delete pendingAuth[chatId];
          await supabaseFetch(`/waiters?id=eq.${pending.waiterId}`, {
            method: 'PATCH',
            body: JSON.stringify({ telegram_chat_id: chatId.toString() })
          });

          // Уведомляем администратора в общий чат о новой привязке устройства
          const adminChat = await getAdminChatId();
          if (adminChat) {
            const senderUser = msg.from?.username ? `@${msg.from.username}` : (msg.from?.first_name || 'Пользователь');
            await sendTgMessage(adminChat, `🛡 <b>Безопасность:</b> Официант <b>${target[0].name}</b> успешно привязал Telegram (${senderUser}, Chat ID: <code>${chatId}</code>).`);
          }

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

      // =============================================================
      // B. ADMIN COMMANDS & BUTTONS
      // =============================================================
      if (isAdmin) {
        if (text === '/start' || text === '🔄 Обновить статус' || text === '🔄 Главное меню' || text === '/menu') {
          const welcomeText = `👑 <b>Панель Администратора — Altyn Kazyk</b>\n\n` +
            `Здравствуйте! Вы авторизованы как <b>Администратор ресторана</b>.\n\n` +
            `📊 <b>Сводка за день</b> — выручка, чеки и загрузка зала\n` +
            `🪑 <b>Все столы</b> — статус каждого стола и официантов\n` +
            `🍽 <b>Все заказы</b> — заказы в зале и статус (принят/готовится/подан)\n` +
            `🔔 <b>Активные вызовы</b> — вызовы гостей со всех столов\n` +
            `🛵 <b>Доставка</b> — заказы на доставку и подтверждение\n` +
            `📅 <b>Брони</b> — бронирование столов и подтверждение\n` +
            `👥 <b>Официанты на смене</b> — статус персонала и ПИН-коды\n\n` +
            `<i>Нажимайте кнопки внизу для управления:</i>`;
          await sendTgMessage(chatId, welcomeText, { reply_markup: getAdminKeyboard() });
          return res.status(200).json({ ok: true });
        }

        if (text === '📊 Сводка за день' || text === '/stats') {
          const statsText = await buildAdminDailyStats();
          await sendTgMessage(chatId, statsText, { reply_markup: getAdminKeyboard() });
          return res.status(200).json({ ok: true });
        }

        if (text === '🪑 Все столы' || text === '/tables') {
          const overview = await buildAdminTablesOverview();
          await sendTgMessage(chatId, overview.text, { reply_markup: overview.reply_markup });
          return res.status(200).json({ ok: true });
        }

        if (text === '🔔 Активные вызовы' || text === '/calls') {
          const calls = await supabaseFetch('/waiter_calls?status=in.(pending,accepted)&order=created_at.desc&limit=10');
          if (!calls || calls.length === 0) {
            await sendTgMessage(chatId, '🔔 Нет активных вызовов официанта. Все столы обслужены! 👍', {
              reply_markup: getAdminKeyboard()
            });
            return res.status(200).json({ ok: true });
          }

          const [tables, allWaiters] = await Promise.all([
            supabaseFetch('/restaurant_tables?select=id,label,waiter_id'),
            supabaseFetch('/waiters?select=id,name')
          ]);
          const waitersMap = {};
          if (allWaiters) allWaiters.forEach(w => waitersMap[w.id] = w.name);
          const tableWaiterMap = {};
          if (tables) {
            tables.forEach(t => {
              const cleanNum = (t.label || '').replace(/[^0-9]/g, '');
              if (t.waiter_id && waitersMap[t.waiter_id]) {
                tableWaiterMap[cleanNum] = waitersMap[t.waiter_id];
                tableWaiterMap[t.id] = waitersMap[t.waiter_id];
                tableWaiterMap[t.label] = waitersMap[t.waiter_id];
              }
            });
          }

          for (const c of calls) {
            const tId = c.table_id || '';
            const cleanNum = String(tId).replace(/[^0-9]/g, '') || tId;
            const assignedName = tableWaiterMap[cleanNum] || tableWaiterMap[tId] || 'не назначен';
            const time = new Date(c.created_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
            const statusText = c.status === 'accepted' ? '🏃‍♂️ Официант идет' : '⏳ Ожидает';

            const msgText = `🔔 <b>Вызов со стола №${tId}</b>\n` +
              `⏰ Время: ${time}\n` +
              `👤 Закреплен: <b>${assignedName}</b>\n` +
              `Статус: <b>${statusText}</b>`;

            const buttons = c.status === 'accepted'
              ? [[{ text: `✅ Завершить (Стол №${tId})`, callback_data: `call_done:${c.id}:${cleanNum}` }]]
              : [
                  [
                    { text: `🏃‍♂️ Я подойду! (Стол №${tId})`, callback_data: `call_accept:${c.id}:${cleanNum}` },
                    { text: `✅ Обслужен`, callback_data: `call_done:${c.id}:${cleanNum}` }
                  ]
                ];

            await sendTgMessage(chatId, msgText, { reply_markup: { inline_keyboard: buttons } });
          }
          return res.status(200).json({ ok: true });
        }

        if (text === '🍽 Все заказы' || text === '🍽 Текущие заказы' || text === '/orders') {
          const [rawOrders, menuItems, tables, allWaiters] = await Promise.all([
            supabaseFetch('/orders_new?status=in.(confirmed,processing,served)&order=created_at.desc'),
            supabaseFetch('/menu_items_db?select=id,title,price'),
            supabaseFetch('/restaurant_tables?select=id,label,waiter_id'),
            supabaseFetch('/waiters?select=id,name')
          ]);

          if (!rawOrders || rawOrders.length === 0) {
            await sendTgMessage(chatId, '🍽 Активных заказов в зале сейчас нет.', {
              reply_markup: getAdminKeyboard()
            });
            return res.status(200).json({ ok: true });
          }

          const menuMap = {};
          if (menuItems) menuItems.forEach(m => menuMap[m.id] = { title: m.title, price: Number(m.price) || 0 });

          const waitersMap = {};
          if (allWaiters) allWaiters.forEach(w => waitersMap[w.id] = w.name);
          const tableWaiterMap = {};
          if (tables) {
            tables.forEach(t => {
              const cleanNum = (t.label || '').replace(/[^0-9]/g, '');
              if (t.waiter_id && waitersMap[t.waiter_id]) {
                tableWaiterMap[cleanNum] = waitersMap[t.waiter_id];
                tableWaiterMap[t.id] = waitersMap[t.waiter_id];
                tableWaiterMap[t.label] = waitersMap[t.waiter_id];
              }
            });
          }

          const grouped = {};
          for (const ord of rawOrders) {
            const tid = ord.table_id || 'Без стола';
            if (!grouped[tid]) {
              grouped[tid] = { items: [], total: 0, status: ord.status, createdAt: ord.created_at };
            }
            const itemInfo = menuMap[ord.menu_item_id] || { title: 'Блюдо', price: 0 };
            const qty = Number(ord.quantity) || 1;
            const subtotal = qty * itemInfo.price;
            grouped[tid].items.push(`• ${itemInfo.title} x${qty} — ${subtotal.toLocaleString('ru-RU')} сом`);
            grouped[tid].total += subtotal;
          }

          for (const [tId, ordData] of Object.entries(grouped)) {
            const cleanNum = String(tId).replace(/[^0-9]/g, '') || tId;
            const assignedWaiter = tableWaiterMap[cleanNum] || tableWaiterMap[tId] || 'Не назначен';
            const time = new Date(ordData.createdAt).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
            
            let statusBadge = '';
            let buttons = [];

            if (ordData.status === 'confirmed') {
              statusBadge = '⏳ <b>НЕ ПРИНЯТ</b> (Ожидает подтверждения)';
              buttons = [
                [
                  { text: '👨‍🍳 Принять заказ (Готовится)', callback_data: `order_status:${cleanNum}:processing` },
                  { text: '🍽 Подано', callback_data: `order_status:${cleanNum}:served` }
                ],
                [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${cleanNum}` }]
              ];
            } else if (ordData.status === 'processing') {
              statusBadge = '👨‍🍳 <b>ПРИНЯТ (Готовится)</b>';
              buttons = [
                [{ text: '🍽 Подано', callback_data: `order_status:${cleanNum}:served` }],
                [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${cleanNum}` }]
              ];
            } else if (ordData.status === 'served') {
              statusBadge = '🍽 <b>ПОДАНО</b>';
              buttons = [
                [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${cleanNum}` }]
              ];
            } else {
              statusBadge = `📌 ${ordData.status}`;
              buttons = [
                [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${cleanNum}` }]
              ];
            }

            const msgText = `🍽 <b>Заказ стола №${tId}</b> (${time})\n` +
              `👤 Официант стола: <b>${assignedWaiter}</b>\n` +
              `Статус: ${statusBadge}\n\n` +
              `${ordData.items.join('\n')}\n\n` +
              `💰 <b>Итого: ${ordData.total.toLocaleString('ru-RU')} сом</b>`;

            await sendTgMessage(chatId, msgText, {
              reply_markup: {
                inline_keyboard: buttons
              }
            });
          }
          return res.status(200).json({ ok: true });
        }

        if (text === '🛵 Доставка' || text === '/delivery') {
          const deliveries = await supabaseFetch('/delivery_orders?status=in.(new,processing,delivering)&order=created_at.desc&limit=15');
          if (!deliveries || deliveries.length === 0) {
            await sendTgMessage(chatId, '🛵 <b>Активных заказов на доставку сейчас нет.</b>\n\nВсе заказы доставлены или отсутствуют 👍', {
              reply_markup: getAdminKeyboard()
            });
            return res.status(200).json({ ok: true });
          }

          for (const d of deliveries) {
            const time = new Date(d.created_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
            let itemsText = '';
            if (Array.isArray(d.items)) {
              itemsText = d.items.map(it => `• ${it.title} x${it.qty} — ${((Number(it.price) || 0) * (Number(it.qty) || 1)).toLocaleString('ru-RU')} сом`).join('\n');
            } else if (d.items) {
              itemsText = String(d.items);
            }

            let statusRu = '';
            let buttons = [];
            const shortId = d.id ? d.id.slice(0, 8) : '';

            if (d.status === 'new') {
              statusRu = '⏳ <b>НОВЫЙ (Ожидает подтверждения)</b>';
              buttons = [
                [
                  { text: '👨‍🍳 Принять доставку', callback_data: `deliv_status:${d.id}:processing` },
                  { text: '❌ Отклонить', callback_data: `deliv_status:${d.id}:cancelled` }
                ],
                [
                  { text: '🛵 Отправить курьером', callback_data: `deliv_status:${d.id}:delivering` }
                ]
              ];
            } else if (d.status === 'processing') {
              statusRu = '👨‍🍳 <b>ПРИНЯТО, ГОТОВИТСЯ</b>';
              buttons = [
                [
                  { text: '🛵 Отправить курьером', callback_data: `deliv_status:${d.id}:delivering` },
                  { text: '❌ Отменить заказ', callback_data: `deliv_status:${d.id}:cancelled` }
                ]
              ];
            } else if (d.status === 'delivering') {
              statusRu = '🛵 <b>В ПУТИ (У курьера)</b>';
              buttons = [
                [
                  { text: '✅ Заказ доставлен (Завершить)', callback_data: `deliv_status:${d.id}:delivered` },
                  { text: '❌ Отменить заказ', callback_data: `deliv_status:${d.id}:cancelled` }
                ]
              ];
            } else {
              statusRu = d.status;
            }

            const total = Number(d.total || 0).toLocaleString('ru-RU');
            const msgText = `🛵 <b>Заказ на доставку #${shortId}</b> (${time})\n\n` +
              `👤 Клиент: <b>${d.customer_name || 'Не указано'}</b>\n` +
              `📞 Контакты/Адрес: <b>${d.customer_phone || 'Не указано'}</b>\n` +
              `📌 Статус: ${statusRu}\n\n` +
              `${itemsText ? itemsText + '\n\n' : ''}` +
              `💰 <b>Итого: ${total} сом</b>`;

            await sendTgMessage(chatId, msgText, {
              reply_markup: { inline_keyboard: buttons }
            });
          }
          return res.status(200).json({ ok: true });
        }

        if (text === '📅 Брони' || text === '/bookings') {
          const [bookings, tables] = await Promise.all([
            supabaseFetch('/bookings?status=in.(confirmed,accepted)&order=created_at.desc&limit=15'),
            supabaseFetch('/restaurant_tables?select=id,label')
          ]);

          if (!bookings || bookings.length === 0) {
            await sendTgMessage(chatId, '📅 <b>Активных броней столов сейчас нет.</b> 👍', {
              reply_markup: getAdminKeyboard()
            });
            return res.status(200).json({ ok: true });
          }

          const tableMap = {};
          if (tables) {
            tables.forEach(t => tableMap[t.id] = t.label);
          }

          for (const b of bookings) {
            const tableLabel = tableMap[b.table_id] || (`Стол №${b.table_id}`);
            const timeRange = b.end_time ? `${b.booking_time} — ${b.end_time}` : (b.booking_time || 'Время не указано');
            const preorder = b.preorder_details || b.preorder_type || '';

            let statusRu = '';
            let buttons = [];

            if (b.status === 'confirmed') {
              statusRu = '⏳ <b>ОЖИДАЕТ ПОДТВЕРЖДЕНИЯ</b>';
              buttons = [
                [
                  { text: '✅ Подтвердить бронь', callback_data: `book_status:${b.id}:accept` },
                  { text: '❌ Отклонить бронь', callback_data: `book_status:${b.id}:cancel` }
                ]
              ];
            } else if (b.status === 'accepted') {
              statusRu = '✅ <b>ПОДТВЕРЖДЕНА</b>';
              buttons = [
                [
                  { text: '🪑 Освободить стол / Завершить', callback_data: `book_status:${b.id}:done` },
                  { text: '❌ Отменить бронь', callback_data: `book_status:${b.id}:cancel` }
                ]
              ];
            } else {
              statusRu = b.status;
            }

            const msgText = `📅 <b>Бронь стола: ${tableLabel}</b>\n\n` +
              `👤 Гость: <b>${b.customer_name || 'Не указано'}</b>\n` +
              `📞 Телефон: <b>${b.customer_phone || 'Не указано'}</b>\n` +
              `👥 Гостей: <b>${b.guests_count || 1} чел.</b>\n` +
              `⏰ Время брони: <b>${timeRange}</b>\n` +
              `📌 Статус: ${statusRu}` +
              (preorder ? `\n🍽 Предзаказ: <i>${preorder}</i>` : '');

            await sendTgMessage(chatId, msgText, {
              reply_markup: { inline_keyboard: buttons }
            });
          }
          return res.status(200).json({ ok: true });
        }

        if (text === '👥 Официанты на смене' || text === '/waiters') {
          const wl = await buildAdminWaitersList();
          await sendTgMessage(chatId, wl.text, { reply_markup: wl.reply_markup });
          return res.status(200).json({ ok: true });
        }

        if (text === '🚪 Выйти из админки' || text === '/admin_logout' || text === '/logout') {
          const currentAdminSetting = await supabaseFetch('/admin_settings?key=eq.telegram_chat_id&select=value');
          const currentVal = (currentAdminSetting && currentAdminSetting[0]?.value) || '';
          const ids = currentVal.split(',').map(s => s.trim()).filter(id => id && id !== String(chatId));
          await supabaseFetch('/admin_settings?key=eq.telegram_chat_id', {
            method: 'PATCH',
            body: JSON.stringify({ value: ids.join(',') })
          });

          await sendTgMessage(chatId, '🚪 <b>Вы успешно вышли из панели администратора.</b>\n\nПривязка этого телефона аннулирована.', {
            reply_markup: { remove_keyboard: true }
          });
          return res.status(200).json({ ok: true });
        }

        // Fallback for Admin
        await sendTgMessage(chatId, `👑 <b>Панель Администратора Altyn Kazyk</b>\n\nИспользуйте кнопки меню внизу для быстрого доступа:`, {
          reply_markup: getAdminKeyboard()
        });
        return res.status(200).json({ ok: true });
      }

      // =============================================================
      // C. WAITER COMMANDS & BUTTONS
      // =============================================================

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

        // Показываем свободных активных официантов
        const allWaiters = await supabaseFetch('/waiters?is_active=neq.false&select=*&order=name.asc');
        const unassigned = (allWaiters || []).filter(w => !w.telegram_chat_id);

        const buttons = unassigned.map(w => ([
          { text: `👤 ${w.name}`, callback_data: `auth_select:${w.id}` }
        ]));

        await sendTgMessage(chatId, `👋 <b>Добро пожаловать в Altyn Kazyk!</b>\n\n<b>Выберите ваш профиль официанта для входа:</b>`, {
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
        const myTableCleanNums = (myTables || []).map(t => (t.label || '').replace(/[^0-9]/g, ''));

        // Fetch pending or accepted calls
        const calls = await supabaseFetch('/waiter_calls?status=in.(pending,accepted)&order=created_at.desc&limit=10');

        if (!calls || calls.length === 0) {
          await sendTgMessage(chatId, '🔔 Нет активных вызовов официанта. Все столы обслужены! 👍');
          return res.status(200).json({ ok: true });
        }

        for (const c of calls) {
          const tId = c.table_id || '';
          const cleanNum = String(tId).replace(/[^0-9]/g, '') || tId;
          const isMine = myTableCleanNums.includes(cleanNum) || myTables?.some(mt => mt.id === tId);
          const time = new Date(c.created_at).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
          const statusText = c.status === 'accepted' ? '🏃‍♂️ Официант идет' : '⏳ Ожидает';

          const msgText = `🔔 <b>Вызов со стола №${tId}</b>\n⏰ Время: ${time}\nСтатус: <b>${statusText}</b>${isMine ? ' (Ваш стол)' : ''}`;
          const buttons = c.status === 'accepted'
            ? [[{ text: `✅ Завершить (Стол №${tId})`, callback_data: `call_done:${c.id}:${cleanNum}` }]]
            : [
                [
                  { text: `🏃‍♂️ Иду к столу №${tId}!`, callback_data: `call_accept:${c.id}:${cleanNum}` },
                  { text: `✅ Обслужен`, callback_data: `call_done:${c.id}:${cleanNum}` }
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

        const [myTables, rawOrders, menuItems] = await Promise.all([
          supabaseFetch(`/restaurant_tables?waiter_id=eq.${waiter.id}&select=id,label`),
          supabaseFetch('/orders_new?status=in.(confirmed,processing,served)&order=created_at.desc&limit=25'),
          supabaseFetch('/menu_items_db?select=id,title,price')
        ]);

        const myTableCleanNums = (myTables || []).map(t => (t.label || '').replace(/[^0-9]/g, ''));
        const menuMap = {};
        if (menuItems) menuItems.forEach(m => menuMap[m.id] = { title: m.title, price: Number(m.price) || 0 });

        if (!rawOrders || rawOrders.length === 0) {
          await sendTgMessage(chatId, '🍽 Активных заказов нет.');
          return res.status(200).json({ ok: true });
        }

        // Group by table
        const grouped = {};
        for (const ord of rawOrders) {
          const tid = ord.table_id || '';
          const cleanNum = String(tid).replace(/[^0-9]/g, '') || tid;
          // Filter only my tables (or all if waiter has no tables yet)
          if (myTableCleanNums.length > 0 && !myTableCleanNums.includes(cleanNum) && !myTables?.some(mt => mt.id === tid)) {
            continue;
          }

          if (!grouped[cleanNum]) {
            grouped[cleanNum] = { items: [], total: 0, status: ord.status, createdAt: ord.created_at };
          }
          const itemInfo = menuMap[ord.menu_item_id] || { title: 'Блюдо', price: 0 };
          const qty = Number(ord.quantity) || 1;
          const subtotal = qty * itemInfo.price;
          grouped[cleanNum].items.push(`• ${itemInfo.title} x${qty} — ${subtotal} сом`);
          grouped[cleanNum].total += subtotal;
        }

        const tableEntries = Object.entries(grouped);
        if (tableEntries.length === 0) {
          await sendTgMessage(chatId, '🍽 На ваших столах сейчас нет активных заказов.');
          return res.status(200).json({ ok: true });
        }

        for (const [tId, ordData] of tableEntries.slice(0, 5)) {
          const time = new Date(ordData.createdAt).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bishkek' });
          let statusRu = '';
          let buttons = [];

          if (ordData.status === 'confirmed') {
            statusRu = '⏳ <b>НЕ ПРИНЯТ (Новый заказ)</b>';
            buttons = [
              [
                { text: '👨‍🍳 Принять заказ (Готовится)', callback_data: `order_status:${tId}:processing` },
                { text: '🍽 Подано', callback_data: `order_status:${tId}:served` }
              ],
              [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${tId}` }]
            ];
          } else if (ordData.status === 'processing') {
            statusRu = '👨‍🍳 <b>ПРИНЯТ (Готовится)</b>';
            buttons = [
              [{ text: '🍽 Подано', callback_data: `order_status:${tId}:served` }],
              [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${tId}` }]
            ];
          } else if (ordData.status === 'served') {
            statusRu = '🍽 <b>ПОДАНО</b>';
            buttons = [
              [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${tId}` }]
            ];
          } else {
            statusRu = ordData.status;
            buttons = [
              [{ text: '🧾 Расчёт / Освободить', callback_data: `table_clear:${tId}` }]
            ];
          }

          const msgText = `🍽 <b>Заказ стола №${tId}</b> (${time})\n\n` +
            `${ordData.items.join('\n')}\n\n` +
            `💰 <b>Итого: ${ordData.total.toLocaleString('ru-RU')} сом</b>\n` +
            `📌 <b>Статус: ${statusRu}</b>`;

          await sendTgMessage(chatId, msgText, {
            reply_markup: {
              inline_keyboard: buttons
            }
          });
        }
        return res.status(200).json({ ok: true });
      }

      // Command: /logout or button "🚪 Выйти / Сдать смену"
      if (text === '/logout' || text === '🚪 Выйти / Сдать смену' || text === '🚪 Выйти' || text === '🚪 Сменить официанта') {
        if (waiter) {
          // 1. Освобождаем все столы, закрепленные за этим официантом
          await supabaseFetch(`/restaurant_tables?waiter_id=eq.${waiter.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ waiter_id: null })
          });
          // 2. Сбрасываем привязку Telegram
          await supabaseFetch(`/waiters?id=eq.${waiter.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ telegram_chat_id: null })
          });
        }
        delete pendingAuth[chatId];
        await sendTgMessage(chatId, '🚪 <b>Смена завершена. Вы успешно вышли из системы.</b>\n\nВсе ваши столы освобождены для коллег.\n\n<i>Чтобы снова выйти на смену, отправьте /start</i>', {
          reply_markup: { remove_keyboard: true }
        });
        return res.status(200).json({ ok: true });
      }

      // Default fallback
      if (!waiter || waiter.is_active === false) {
        await sendTgMessage(chatId, '👋 Нажмите /start для авторизации.', {
          reply_markup: { remove_keyboard: true }
        });
      } else {
        await sendTgMessage(chatId, `👋 Официант: <b>${waiter.name}</b>\n\nИспользуйте кнопки меню внизу:\n🪑 <b>Мои столы</b> — выбор столов на смену\n🔔 <b>Активные вызовы</b> — вызовы гостей\n🍽 <b>Текущие заказы</b> — заказы на ваших столах\n🚪 <b>Выйти / Сдать смену</b> — завершение смены`, {
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
