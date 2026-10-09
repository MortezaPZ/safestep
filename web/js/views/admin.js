/**
 * پنل مدیریت سامانه — کاربران، دستگاه‌ها، لاگ‌ها و سنجه‌ها.
 *
 * ادمین اینجا سلامت سامانه را می‌بیند، نه موقعیت افراد. هیچ کارتی مختصات
 * نشان نمی‌دهد و هیچ درخواستی به مسیرهای موقعیت نمی‌زند.
 */
import api from '../api.js';
import { el, render, toast, skeleton, emptyState, errorState, dialog } from '../ui.js';
import { faNumber } from '../format.js';

const TABS = [
  { id: 'overview', label: 'نمای کلی' },
  { id: 'support', label: 'پیام پشتیبانی' },
  { id: 'documents', label: 'کل مدارک' },
  { id: 'pending', label: 'مدارک در انتظار' },
  { id: 'approved', label: 'مدارک تأییدشده' },
  { id: 'families', label: 'خانواده‌ها' },
  { id: 'alerts', label: 'هشدارها' },
  { id: 'falls', label: 'تشخیص سقوط' },
  { id: 'users', label: 'کاربران' },
  { id: 'devices', label: 'دستگاه‌ها' },
  { id: 'requests', label: 'لاگ درخواست‌ها' },
  { id: 'audit', label: 'لاگ حسابرسی' },
  { id: 'metrics', label: 'سنجه‌های ارزیابی' },
  { id: 'outbox', label: 'صف نوتیفیکیشن' },
];

const ROLE_FA = { primary: 'کاربر اصلی', guardian: 'مراقب', admin: 'مدیر سامانه' };
const STATUS_FA = { active: 'فعال', suspended: 'معلق', deleted: 'حذف‌شده' };

function csvEscape(value) {
  const s = String(value ?? '');
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

function downloadCsv(filename, headers, rows) {
  const lines = [headers.map(csvEscape).join(',')];
  for (const row of rows) lines.push(row.map(csvEscape).join(','));
  const blob = new Blob([`\uFEFF${lines.join('\n')}`], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename });
  document.body.append(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function statusClass(code) {
  if (code >= 500) return 'chip--danger';
  if (code >= 400) return 'chip--warning';
  return 'chip--ok';
}

export function mountAdmin(container) {
  let tab = 'overview';
  let destroyed = false;

  function paint(body) {
    if (destroyed) return;
    render(
      container,
      el('div.card.mb-4', {},
        el('div.card__body', {},
          el('h1.card__title', { text: 'مدیریت سامانه' }),
          el('p.muted', {
            text: 'این نما سلامت سامانه را نشان می‌دهد، نه موقعیت افراد.',
          }),
          el('div.chip-row.mt-4', { role: 'tablist', ariaLabel: 'بخش‌های مدیریت' },
            ...TABS.map((item) => el('button', {
              class: 'chip chip--button',
              type: 'button',
              role: 'tab',
              ariaSelected: String(item.id === tab),
              text: item.label,
              onClick: () => {
                tab = item.id;
                load();
              },
            })),
          ),
        ),
      ),
      el('div', { id: 'admin-body' }, body),
    );
  }

  function bodyEl() {
    return container.querySelector('#admin-body') ?? container;
  }

  function showLoading() {
    paint(el('div.card', {}, el('div.card__body', {}, ...skeleton('text', 6))));
  }

  function showError(err, retry) {
    paint(errorState({
      title: 'بارگذاری پنل ممکن نشد',
      text: err?.message ?? 'ارتباط با سرور برقرار نشد.',
      onRetry: retry,
    }));
  }

  async function load() {
    showLoading();
    try {
      if (tab === 'overview') await loadOverview();
      else if (tab === 'support') await loadSupport();
      else if (tab === 'documents') await loadDocuments('all');
      else if (tab === 'pending') await loadDocuments('pending');
      else if (tab === 'approved') await loadDocuments('approved');
      else if (tab === 'families') await loadFamilies();
      else if (tab === 'alerts') await loadAdminAlerts();
      else if (tab === 'falls') await loadFalls();
      else if (tab === 'users') await loadUsers();
      else if (tab === 'devices') await loadDevices();
      else if (tab === 'requests') await loadRequests();
      else if (tab === 'audit') await loadAudit();
      else if (tab === 'metrics') await loadMetrics();
      else await loadOutbox();
    } catch (err) {
      showError(err, load);
    }
  }

  async function loadOverview() {
    const data = await api.adminOverview();
    const stats = data.stats ?? {};
    const alerts = data.recentAlerts ?? [];
    paint(el('div', {},
      el('div.row.row--wrap.gap-3.mb-4', {},
        metricCard('کاربران', stats.users?.total),
        metricCard('فعال', stats.users?.active),
        metricCard('معلق', stats.users?.suspended),
        metricCard('دستگاه‌ها', stats.devicesActive),
        metricCard('هشدار ۲۴ساعت', stats.alerts24h),
      ),
      el('div.card', {},
        el('div.card__body', {},
          el('h2.card__title.mb-4', { text: 'هشدارهای اخیر (بدون مختصات)' }),
          alerts.length === 0
            ? emptyState({ title: 'هشداری نیست', text: 'هنوز هشداری ثبت نشده است.' })
            : table(
              ['نوع', 'زمان', 'وضعیت'],
              alerts.map((a) => [a.type, a.createdAt, a.severity ?? '']),
            ),
        ),
      ),
    ));
  }

  async function loadSupport() {
    const data = await api.adminSupport();
    const threads = data.threads ?? [];
    paint(el('div.card', {}, el('div.card__body', {},
      el('h2.card__title.mb-4', { text: 'پیام‌های پشتیبانی' }),
      threads.length === 0
        ? emptyState({ title: 'پیامی نیست', text: 'هنوز کسی به پشتیبانی پیام نداده است.' })
        : el('div', {}, ...threads.map((thread) => el('div.card.mb-3', {}, el('div.card__body', {},
          el('strong', { text: `${thread.fullName} — ${thread.phone}` }),
          el('p.muted', { text: `${thread.messageCount} پیام` }),
          el('button.btn.btn--secondary.btn--sm', {
            type: 'button',
            text: 'پاسخ',
            onClick: async () => {
              const text = window.prompt('پاسخ پشتیبانی');
              if (!text) return;
              await api.adminSupportReply(thread.userId, text);
              toast('پاسخ ثبت شد');
              load();
            },
          }),
        )))),
    )));
  }

  async function loadFamilies() {
    const data = await api.adminFamilies();
    const families = data.families ?? [];
    paint(el('div', {}, ...families.map((family) => el('div.card.mb-3', {}, el('div.card__body', {},
      el('h2.card__title', { text: family.primaryName }),
      el('p', { text: `وضعیت مدرک: ${family.verificationStatus ?? '—'}` }),
      family.healthCondition ? el('p', { text: `مشکل: ${family.healthCondition}` }) : null,
      el('p.muted', { text: family.guardians.map((g) => g.fullName).join('، ') || 'ناظری ثبت نشده' }),
    )))));
  }

  async function loadAdminAlerts() {
    const data = await api.adminAlerts();
    const alerts = data.alerts ?? [];
    const groups = new Map();
    for (const item of alerts) {
      const key = item.subjectName ?? 'خانواده';
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(item);
    }
    paint(el('div', {}, ...[...groups.entries()].map(([name, items]) => el('div.card.mb-3', {}, el('div.card__body', {},
      el('h2.card__title', { text: name }),
      ...items.map((item) => el('p', { text: `${item.title} — ${item.body}` })),
    )))));
  }

  async function loadFalls() {
    const data = await api.adminFalls();
    const falls = data.falls ?? [];
    paint(el('div.card', {}, el('div.card__body', {},
      el('h2.card__title.mb-4', { text: 'گزارش تشخیص سقوط' }),
      falls.length === 0
        ? emptyState({ title: 'گزارشی نیست', text: 'وقتی سقوطی تشخیص داده شود، اینجا بدون مختصات دیده می‌شود.' })
        : el('div', {}, ...falls.map((item) => el('p', {
          text: `${item.subjectName}: ${item.title}`,
        }))),
    )));
  }

  async function loadDocuments(status = 'pending') {
    const page = await api.adminDocuments({ status, limit: 50 });
    const documents = page.documents ?? page.items ?? [];
    paint(el('div.card', {},
      el('div.card__body', {},
        el('h2.card__title.mb-2', {
          text: status === 'approved' ? 'مدارک تأییدشده' : status === 'all' ? 'کل مدارک' : 'مدارک در انتظار تأیید',
        }),
        el('p.muted.mb-4', {
          text: status === 'approved'
            ? 'بعد از تأیید، مشکل سلامت شخص اینجا دیده می‌شود.'
            : 'تصویر مدرک را پیش از تأیید یا رد مشاهده کنید.',
        }),
        documents.length === 0
          ? emptyState({ title: 'مدرکی برای بررسی نیست', text: 'مدرک ارسال‌شده‌ای در انتظار بررسی وجود ندارد.' })
          : documentTable(documents),
      ),
    ));
  }

  function documentTable(documents) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {},
      ...['کاربر', 'نوع مدرک', 'زمان ارسال', 'کنش'].map((h) => el('th', { text: h })),
    )));
    const tbody = el('tbody');
    for (const item of documents) {
      tbody.append(el('tr', {},
        el('td', {},
          el('div', { text: item.userName ?? '—' }),
          item.userPhone ? el('div.phone-ltr', { text: item.userPhone }) : null,
          item.status === 'approved' && item.healthCondition
            ? el('div', { text: `مشکل: ${item.healthCondition}` })
            : null,
        ),
        el('td', { text: item.typeLabel ?? item.type ?? '—' }),
        el('td', { text: item.createdAt ?? '—' }),
        el('td', {}, el('div.row.row--wrap.gap-2', {},
          el('button.btn.btn--ghost.btn--sm', {
            type: 'button', text: 'مشاهده تصویر',
            onClick: () => viewDocument(item),
          }),
          el('button.btn.btn--secondary.btn--sm', {
            type: 'button', text: 'تأیید',
            onClick: () => updateDocument(item, 'approve'),
          }),
          el('button.btn.btn--ghost.btn--sm', {
            type: 'button', text: 'رد',
            onClick: () => updateDocument(item, 'reject'),
          }),
        )),
      ));
    }
    tbl.append(tbody); wrap.append(tbl); return wrap;
  }

  function viewDocument(item) {
    const imageUrl = item.imageUrl ?? item.fileUrl;
    dialog({
      title: `تصویر مدرک — ${item.userName ?? 'کاربر'}`,
      content: imageUrl
        ? el('img.document-preview', { src: imageUrl, alt: 'تصویر مدرک ارسالی', loading: 'eager' })
        : el('p.dialog__text', { text: 'تصویر این مدرک در دسترس نیست.' }),
    });
  }

  async function updateDocument(item, action) {
    try {
      if (action === 'approve') await api.adminApproveDocument(item.id);
      else {
        const reason = window.prompt('دلیل رد مدرک را بنویسید:');
        if (!reason) return;
        await api.adminRejectDocument(item.id, reason);
      }
      toast(action === 'approve' ? 'مدرک تأیید شد' : 'مدرک رد شد');
      await loadDocuments();
    } catch (err) {
      toast('عملیات انجام نشد', err.message, { severity: 'warning' });
    }
  }

  function metricCard(label, value) {
    return el('div.card', {},
      el('div.card__body', {},
        el('div.muted', { text: label }),
        el('div.stat', { text: faNumber(value ?? 0) }),
      ),
    );
  }

  function fallMetricsCard(fd) {
    const c = fd?.confusion ?? { tp: 0, fp: 0, tn: 0, fn: 0 };
    return el('div.card.mb-4', {},
      el('div.card__body', {},
        el('div.row.row--between.mb-3', {},
          el('h2.card__title', { text: 'ماتریس درهم‌ریختگی سقوط' }),
          el('button.btn.btn--ghost.btn--sm', {
            type: 'button',
            text: 'خروجی CSV',
            onClick: () => downloadCsv(
              'fall-confusion.csv',
              ['tp', 'fp', 'fn', 'tn', 'precision', 'recall', 'f1'],
              [[c.tp, c.fp, c.fn, c.tn, fd?.precision, fd?.recall, fd?.f1]],
            ),
          }),
        ),
        el('p.muted.mb-3', {
          text: `مدل ${fd?.modelVersion ?? '—'} · داده ${fd?.datasetKind ?? '—'}`,
        }),
        table(
          ['', 'سقوط واقعی', 'غیرسقوط'],
          [
            ['پیش‌بینی سقوط', c.tp, c.fp],
            ['پیش‌بینی غیرسقوط', c.fn, c.tn],
          ],
        ),
        el('div.row.row--wrap.gap-3.mt-4', {},
          metricCard('صحت', fd?.precision),
          metricCard('بازخوانی', fd?.recall),
          metricCard('F1', fd?.f1),
        ),
      ),
    );
  }

  async function loadUsers(query = {}) {
    const page = await api.adminUsers({ limit: 30, offset: 0, ...query });
    const users = page.users ?? [];
    const filters = { search: query.search ?? '', role: query.role ?? '', status: query.status ?? '' };

    paint(el('div.card', {},
      el('div.card__body', {},
        el('div.row.row--wrap.gap-2.mb-4', {},
          el('input.input', {
            type: 'search',
            placeholder: 'جست‌وجوی نام یا شماره',
            value: filters.search,
            onChange: (e) => { filters.search = e.target.value; },
          }),
          select('role', filters.role, [['', 'همه نقش‌ها'], ['primary', 'کاربر اصلی'], ['guardian', 'مراقب'], ['admin', 'مدیر']]),
          select('status', filters.status, [['', 'همه وضعیت‌ها'], ['active', 'فعال'], ['suspended', 'معلق'], ['deleted', 'حذف‌شده']]),
          el('button.btn.btn--secondary', {
            type: 'button',
            text: 'اعمال فیلتر',
            onClick: () => loadUsers({
              search: filters.search,
              role: document.getElementById('admin-role')?.value,
              status: document.getElementById('admin-status')?.value,
            }),
          }),
        ),
        users.length === 0
          ? emptyState({ title: 'کاربری یافت نشد', text: 'فیلتر را تغییر دهید.' })
          : userTable(users, () => loadUsers(query)),
        el('p.muted.mt-3', { text: `مجموع: ${faNumber(page.total ?? users.length)}` }),
      ),
    ));

    function select(id, value, options) {
      const node = el('select.input', { id: `admin-${id}` });
      for (const [v, label] of options) {
        const o = el('option', { value: v, text: label });
        if (v === value) o.selected = true;
        node.append(o);
      }
      return node;
    }
  }

  function userTable(users, reload) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {},
      ...['نام', 'شماره', 'نقش', 'وضعیت', 'کنش'].map((h) => el('th', { text: h })),
    )));
    const tbody = el('tbody');
    for (const user of users) {
      const row = el('tr', {},
        el('td', { text: user.fullName }),
        el('td', { text: user.phone }),
        el('td', { text: ROLE_FA[user.role] ?? user.role }),
        el('td', { text: STATUS_FA[user.status] ?? user.status }),
        el('td', {},
          el('div.row.row--wrap.gap-2', {},
            user.status === 'active'
              ? el('button.btn.btn--ghost.btn--sm', {
                  type: 'button',
                  text: 'تعلیق',
                  onClick: () => actUser('suspend', user, reload),
                })
              : el('button.btn.btn--ghost.btn--sm', {
                  type: 'button',
                  text: 'فعال‌سازی',
                  onClick: () => actUser('activate', user, reload),
                }),
            el('button.btn.btn--ghost.btn--sm', {
              type: 'button',
              text: 'تغییر نقش',
              onClick: () => actUser('role', user, reload),
            }),
            el('button.btn.btn--ghost.btn--sm', {
              type: 'button',
              text: 'حذف',
              onClick: () => actUser('delete', user, reload),
            }),
          ),
        ),
      );
      tbody.append(row);
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  async function actUser(kind, user, reload) {
    const snapshot = { ...user };
    try {
      if (kind === 'suspend') {
        const reason = window.prompt('دلیل تعلیق را بنویسید:');
        if (!reason) return;
        await api.adminSuspendUser(user.id, reason);
        toast('حساب معلق شد', user.fullName);
      } else if (kind === 'activate') {
        await api.adminActivateUser(user.id);
        toast('حساب فعال شد', user.fullName);
      } else if (kind === 'role') {
        const role = window.prompt('نقش جدید: primary یا guardian یا admin', user.role);
        if (!role || role === user.role) return;
        await api.adminChangeRole(user.id, role);
        toast('نقش تغییر کرد', ROLE_FA[role] ?? role);
      } else if (kind === 'delete') {
        if (!window.confirm(`حذف نرم «${user.fullName}»؟ این کار قابل بازگشت از این صفحه نیست.`)) return;
        await api.adminDeleteUser(user.id);
        toast('حساب حذف شد', user.fullName);
      }
      await reload();
    } catch (err) {
      toast('عملیات انجام نشد', err.message, { severity: 'warning' });
      await reload();
      void snapshot;
    }
  }

  async function loadDevices(query = {}) {
    const includeRevoked = Boolean(query.includeRevoked);
    const page = await api.adminDevices({
      platform: query.platform || undefined,
      includeRevoked: includeRevoked ? 'true' : undefined,
      limit: 50,
    });
    const devices = page.devices ?? [];
    paint(el('div.card', {},
      el('div.card__body', {},
        el('div.row.row--wrap.gap-2.mb-4', {},
          el('select.input', {
            id: 'admin-platform',
            onChange: (e) => loadDevices({ platform: e.target.value, includeRevoked }),
          },
            el('option', { value: '', text: 'همه سکوها' }),
            el('option', { value: 'android', text: 'اندروید' }),
            el('option', { value: 'ios', text: 'iOS' }),
            el('option', { value: 'web', text: 'وب' }),
          ),
          el('label.row.gap-2', {},
            el('input', {
              type: 'checkbox',
              checked: includeRevoked,
              onChange: (e) => loadDevices({
                platform: document.getElementById('admin-platform')?.value,
                includeRevoked: e.target.checked,
              }),
            }),
            el('span', { text: 'نمایش ابطال‌شده‌ها' }),
          ),
        ),
        devices.length === 0
          ? emptyState({ title: 'دستگاهی نیست', text: 'هنوز دستگاهی ثبت نشده است.' })
          : deviceTable(devices, () => loadDevices(query)),
      ),
    ));
  }

  function deviceTable(devices, reload) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {},
      ...['مالک', 'سکو', 'نام دستگاه', 'وضعیت', 'کنش'].map((h) => el('th', { text: h })),
    )));
    const tbody = el('tbody');
    for (const d of devices) {
      tbody.append(el('tr', {},
        el('td', { text: d.userName ?? d.userPhone ?? '—' }),
        el('td', { text: d.platform }),
        el('td', { text: d.deviceName ?? d.model ?? '—' }),
        el('td', { text: d.revokedAt ? 'ابطال‌شده' : 'فعال' }),
        el('td', {},
          d.revokedAt
            ? el('span.muted', { text: '—' })
            : el('button.btn.btn--ghost.btn--sm', {
                type: 'button',
                text: 'ابطال',
                onClick: async () => {
                  if (!window.confirm('این دستگاه دیگر هشدار دریافت نکند؟')) return;
                  try {
                    await api.adminRevokeDevice(d.id);
                    toast('دستگاه ابطال شد');
                    await reload();
                  } catch (err) {
                    toast('ابطال نشد', err.message, { severity: 'warning' });
                  }
                },
              }),
        ),
      ));
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  async function loadRequests() {
    const page = await api.adminRequestLogs({ limit: 80 });
    const logs = page.logs ?? page.items ?? [];
    paint(el('div.card', {},
      el('div.card__body', {},
        el('form.row.row--wrap.gap-2.mb-4', {
          onSubmit: (e) => {
            e.preventDefault();
            const fd = new FormData(e.target);
            loadRequestsFiltered(Object.fromEntries(fd.entries()));
          },
        },
          el('input.input', { name: 'route', placeholder: 'مسیر' }),
          el('input.input', { name: 'minStatus', placeholder: 'حداقل وضعیت', type: 'number' }),
          el('input.input', { name: 'userId', placeholder: 'شناسه کاربر' }),
          el('button.btn.btn--secondary', { type: 'submit', text: 'فیلتر' }),
        ),
        logs.length === 0
          ? emptyState({ title: 'لاگی نیست', text: 'هنوز درخواستی ثبت نشده یا فیلتر خالی است.' })
          : requestTable(logs),
      ),
    ));
  }

  async function loadRequestsFiltered(query) {
    showLoading();
    try {
      const page = await api.adminRequestLogs({
        limit: 80,
        route: query.route,
        minStatus: query.minStatus,
        userId: query.userId,
      });
      const logs = page.logs ?? page.items ?? [];
      paint(el('div.card', {}, el('div.card__body', {},
        logs.length === 0
          ? emptyState({ title: 'لاگی نیست', text: 'با این فیلتر نتیجه‌ای نیست.', action: { label: 'بازگشت', onClick: loadRequests } })
          : requestTable(logs),
      )));
    } catch (err) {
      showError(err, loadRequests);
    }
  }

  function requestTable(logs) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {},
      ...['روش', 'مسیر', 'وضعیت', 'تأخیر (ms)', 'زمان'].map((h) => el('th', { text: h })),
    )));
    const tbody = el('tbody');
    for (const row of logs) {
      tbody.append(el('tr', {},
        el('td', { text: row.method }),
        el('td', { text: row.route }),
        el('td', {}, el('span', { class: `chip ${statusClass(row.statusCode)}`, text: String(row.statusCode) })),
        el('td', { text: faNumber(row.latencyMs ?? 0) }),
        el('td', { text: row.createdAt }),
      ));
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  async function loadAudit() {
    const page = await api.adminAuditLogs({ limit: 80 });
    const logs = page.logs ?? page.items ?? [];
    paint(el('div.card', {},
      el('div.card__body', {},
        logs.length === 0
          ? emptyState({ title: 'رویدادی نیست', text: 'هنوز کنش حسابرسی ثبت نشده است.' })
          : auditTable(logs),
      ),
    ));
  }

  function auditTable(logs) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {},
      ...['کنش', 'عامل', 'فراداده', 'زمان'].map((h) => el('th', { text: h })),
    )));
    const tbody = el('tbody');
    for (const row of logs) {
      tbody.append(el('tr', {},
        el('td', { text: row.action }),
        el('td', { text: row.actorName ?? row.actorRole ?? '—' }),
        el('td', {}, el('code', { text: JSON.stringify(row.metadata ?? {}) })),
        el('td', { text: row.createdAt }),
      ));
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  async function loadMetrics() {
    const data = await api.adminMetrics();
    const loc = data.location ?? {};
    const req = data.requests ?? {};
    const acc = loc.accuracy ?? {};
    const lat = loc.latency ?? {};
    const deliveries = data.deliveries ?? [];

    paint(el('div', {},
      el('div.row.row--wrap.gap-3.mb-4', {},
        metricCard('دقت میانگین (m)', acc.avgM),
        metricCard('دقت p50', acc.p50M),
        metricCard('دقت p95', acc.p95M),
        metricCard('تأخیر سرور میانگین', req.avgMs),
        metricCard('تأخیر p50', req.p50Ms),
        metricCard('تأخیر p95', req.p95Ms),
        metricCard('تأخیر p99', req.p99Ms),
        metricCard('تأخیر سرتاسری میانگین', lat.avgE2eMs),
      ),
      fallMetricsCard(data.fallDetection),
      el('div.card.mb-4', {},
        el('div.card__body', {},
          el('div.row.row--between.mb-3', {},
            el('h2.card__title', { text: 'تحویل هشدار' }),
            el('button.btn.btn--ghost.btn--sm', {
              type: 'button',
              text: 'خروجی CSV',
              onClick: () => downloadCsv(
                'alert-delivery.csv',
                ['channel', 'total', 'failed', 'avgMs', 'p95Ms'],
                deliveries.map((d) => [d.channel, d.total, d.failed, d.avgMs, d.p95Ms]),
              ),
            }),
          ),
          deliveries.length === 0
            ? emptyState({ title: 'داده‌ای نیست', text: 'هنوز تحویلی ثبت نشده است.' })
            : table(
              ['کانال', 'تعداد', 'ناموفق', 'میانگین ms', 'p95'],
              deliveries.map((d) => [d.channel, d.total, d.failed, d.avgMs, d.p95Ms]),
            ),
        ),
      ),
      el('div.card', {},
        el('div.card__body', {},
          el('h2.card__title.mb-3', { text: 'پاک‌سازی لاگ' }),
          el('p.muted.mb-3', { text: 'لاگ‌های قدیمی‌تر از تعداد روز مشخص حذف می‌شوند. مختصات در این جداول نیست.' }),
          el('div.row.gap-2', {},
            el('input.input', { id: 'purge-days', type: 'number', min: '1', value: '90' }),
            el('button.btn.btn--secondary', {
              type: 'button',
              text: 'پاک‌سازی',
              onClick: purge,
            }),
          ),
        ),
      ),
    ));
  }

  async function purge() {
    const days = Number(document.getElementById('purge-days')?.value);
    if (!window.confirm(`لاگ‌های قدیمی‌تر از ${days} روز حذف شوند؟`)) return;
    if (!window.confirm('این کار برگشت‌پذیر نیست. ادامه می‌دهید؟')) return;
    try {
      const result = await api.adminPurgeLogs(days);
      toast('لاگ‌ها پاک شدند', `درخواست: ${faNumber(result.requestLogs ?? 0)}`);
      await loadMetrics();
    } catch (err) {
      toast('پاک‌سازی نشد', err.message, { severity: 'warning' });
    }
  }

  async function loadOutbox() {
    const page = await api.adminOutbox({ limit: 50 });
    const items = page.items ?? [];
    paint(el('div.card', {},
      el('div.card__body', {},
        el('h2.card__title.mb-3', { text: 'صف نوتیفیکیشن' }),
        el('p.muted.mb-3', {
          text: 'ارسال FCM از این صف با بازتلاش انجام می‌شود. اپ باز همان لحظه از WebSocket مطلع می‌شود.',
        }),
        items.length === 0
          ? emptyState({ title: 'صف خالی است', text: 'هنوز پیامی برای ارسال FCM در صف نیست.' })
          : outboxTable(items),
      ),
    ));
  }

  function outboxTable(items) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {},
      ...['شناسه', 'وضعیت', 'تلاش', 'خطا', 'کنش'].map((h) => el('th', { text: h })),
    )));
    const tbody = el('tbody');
    for (const row of items) {
      const retryBtn = el('button.btn.btn--ghost', {
        type: 'button',
        text: 'تلاش دوباره',
        disabled: row.status === 'pending' || row.status === 'sent',
        onClick: async () => {
          try {
            await api.adminRetryOutbox(row.id);
            toast('دوباره در صف قرار گرفت');
            await loadOutbox();
          } catch (err) {
            toast('تلاش دوباره نشد', err.message, { severity: 'warning' });
          }
        },
      });
      tbody.append(el('tr', {},
        el('td', { text: String(row.id) }),
        el('td', { text: row.status }),
        el('td', { text: faNumber(row.attempts) }),
        el('td', { text: row.lastError ?? '—' }),
        el('td', {}, retryBtn),
      ));
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  function table(headers, rows) {
    const wrap = el('div.table-wrap');
    const tbl = el('table.table');
    tbl.append(el('thead', {}, el('tr', {}, ...headers.map((h) => el('th', { text: h })))));
    const tbody = el('tbody');
    for (const row of rows) {
      tbody.append(el('tr', {}, ...row.map((c) => el('td', { text: c == null ? '—' : String(c) }))));
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  load();
  return () => {
    destroyed = true;
    void bodyEl;
  };
}
