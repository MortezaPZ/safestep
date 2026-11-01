/**
 * صفحه‌ی تاریخچه‌ی مسیر.
 *
 * مسیر با گرادیان زمانی رسم می‌شود: قدیمی کم‌رنگ و نازک، تازه پررنگ و
 * ضخیم. بدون این گرادیان، یک خط یکنواخت نمی‌گوید کاربر از کجا به کجا رفته
 * و بیننده باید حدس بزند.
 *
 * دکمه‌ی حذف تاریخچه واقعاً داده را از دیتابیس پاک می‌کند. این را در
 * دیالوگ تأیید صریح می‌گوییم، چون تعهد محصول است نه ادعای بازاریابی.
 */
import api from '../api.js';
import SafeMap from '../map.js';
import { el, render, toast, confirmDialog, skeleton, emptyState, errorState } from '../ui.js';
import {
  faDate, faTime, faDayLabel, faDistance, faDuration, faNumber, faSpeed, faPercent,
} from '../format.js';

function tehranMidnight(dayValue) {
  const match = String(dayValue).match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) throw new Error('تاریخ روز معتبر نیست.');
  const [, yearText, monthText, dayText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const targetLocalAsUtc = Date.UTC(year, month - 1, day);
  let utc = targetLocalAsUtc;
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Tehran',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  });
  for (let i = 0; i < 2; i += 1) {
    const parts = Object.fromEntries(formatter.formatToParts(new Date(utc))
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, Number(part.value)]));
    const observedLocalAsUtc = Date.UTC(
      parts.year, parts.month - 1, parts.day,
      parts.hour, parts.minute, parts.second,
    );
    utc += targetLocalAsUtc - observedLocalAsUtc;
  }
  return new Date(utc);
}

function tehranDayBounds(dayValue) {
  const start = tehranMidnight(dayValue);
  const nextCalendarDay = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  const nextParts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Tehran', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(nextCalendarDay)
    .filter((part) => part.type !== 'literal')
    .map((part) => [part.type, part.value]));
  const nextStart = tehranMidnight(nextParts.year + '-' + nextParts.month + '-' + nextParts.day);
  return { from: start, to: new Date(nextStart.getTime() - 1) };
}

function distanceMeters(a, b) {
  const radians = (degrees) => (degrees * Math.PI) / 180;
  const dLat = radians(b.lat - a.lat);
  const dLng = radians(b.lng - a.lng);
  const lat1 = radians(a.lat);
  const lat2 = radians(b.lat);
  const haversine = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(haversine)));
}

export function mountHistory(container, ctx, params = {}) {
  let subjectId = params.userId ?? ctx.user.id;
  let isOwn = subjectId === ctx.user.id;
  let watchedPrimaries = [];

  let days = [];
  let selectedDay = null;
  let points = [];
  let stats = null;
  let hidden = false;
  let map = null;
  let destroyed = false;

  /* ─────────────────────── انتخاب روز ─────────────────────── */

  function renderDayPicker() {
    if (days.length === 0) return null;

    return el('div.chip-row.mb-4', { role: 'group', ariaLabel: 'انتخاب روز' },
      ...days.slice(0, 14).map((day) =>
        el('button', {
          class: 'chip chip--button',
          type: 'button',
          ariaPressed: String(selectedDay === day.day),
          text: `${faDayLabel(day.day)} (${faNumber(day.pingCount)} نقطه)`,
          onClick: () => {
            selectedDay = day.day;
            loadDay();
          },
        }),
      ),
    );
  }

  function renderSubjectPicker() {
    if (ctx.user.role !== 'guardian' || watchedPrimaries.length < 2) return null;
    const options = watchedPrimaries.map((item) => {
      const user = item.primaryUser ?? {};
      const id = item.primaryUserId ?? user.id;
      return el('option', {
        value: id,
        selected: String(id) === String(subjectId),
        text: user.fullName ?? item.primaryName ?? item.nickname ?? 'کاربر اصلی',
      });
    });
    return el('label.field.mb-4', {},
      el('span.field__label', { text: 'تاریخچهٔ کاربر اصلی' }),
      el('select.input', {
        value: subjectId,
        ariaLabel: 'انتخاب کاربر برای نمایش تاریخچه',
        onChange: (event) => {
          subjectId = event.target.value;
          isOwn = subjectId === ctx.user.id;
          days = [];
          selectedDay = null;
          points = [];
          stats = null;
          hidden = false;
          load();
        },
      }, ...options),
    );
  }

  /* ─────────────────────── آمار روز ─────────────────────── */

  function renderStats() {
    if (!stats || stats.pingCount === 0) return null;

    // طول مسیر از روی نقاط محاسبه می‌شود، چون سرور آن را ذخیره نمی‌کند
    let totalMeters = 0;
    for (let i = 1; i < points.length; i += 1) {
      const a = points[i - 1];
      const b = points[i];
      totalMeters += distanceMeters(a, b);
    }

    const durationMinutes =
      stats.firstAt && stats.lastAt
        ? (new Date(stats.lastAt) - new Date(stats.firstAt)) / 60_000
        : 0;

    return el('div.stat-grid.mb-4', {},
      el('div.stat', {},
        el('div.stat__value.tabular', { text: faDistance(totalMeters) }),
        el('div.stat__label', { text: 'مسافت طی‌شده' }),
      ),
      el('div.stat', {},
        el('div.stat__value.tabular', { text: faDuration(durationMinutes) }),
        el('div.stat__label', { text: 'بازه‌ی فعالیت' }),
      ),
      el('div.stat', {},
        el('div.stat__value.tabular', { text: faNumber(stats.pingCount) }),
        el('div.stat__label', { text: 'نقطه‌ی ثبت‌شده' }),
      ),
      el('div.stat', {},
        el('div.stat__value.tabular', {
          text: stats.firstAt ? faTime(stats.firstAt) : '—',
        }),
        el('div.stat__label', { text: 'اولین ثبت' }),
      ),
      el('div.stat', {},
        el('div.stat__value.tabular', {
          text: stats.lastAt ? faTime(stats.lastAt) : '—',
        }),
        el('div.stat__label', { text: 'آخرین ثبت' }),
      ),
      stats.minBattery !== null
        ? el('div.stat', {},
            el('div.stat__value.tabular', { text: faPercent(stats.minBattery) }),
            el('div.stat__label', { text: 'کمترین باتری' }),
          )
        : null,
    );
  }

  /* ─────────────────────── نقشه ─────────────────────── */

  function renderMapCard() {
    const mapEl = el('div.map', { role: 'application', ariaLabel: 'نقشه‌ی مسیر طی‌شده' });

    queueMicrotask(() => {
      if (destroyed || !document.body.contains(mapEl)) return;

      map?.destroy();
      map = new SafeMap(mapEl, { zoom: 14 });
      map.setTrack(points);

      if (params.focus?.lat && params.focus?.lng) {
        map.setUserMarker('focus', params.focus, { status: 'sos', label: params.focus.title });
      }

      map.fitAll({ force: true });
      map.invalidate();
    });

    const hasSimulated = points.some((p) => p.isSimulated);

    return el('div.map-wrap', {},
      mapEl,
      el('div.map-overlay.map-overlay--top', {},
        el('span.map-badge', { text: `📍 ${faNumber(points.length)} نقطه` }),
        hasSimulated ? el('span.map-badge', { text: '🎬 شامل داده‌ی حالت نمایش' }) : null,
      ),
      el('div.map-overlay.map-overlay--bottom', {},
        el('span.map-badge', { text: 'کم‌رنگ = قدیمی‌تر · پررنگ = تازه‌تر' }),
      ),
    );
  }

  /* ─────────────────────── حذف تاریخچه ─────────────────────── */

  async function deleteHistory() {
    const confirmed = await confirmDialog({
      title: 'حذف تاریخچه‌ی مسیر؟',
      message:
        'تمام نقاط ثبت‌شده‌ی این روز برای همیشه از دیتابیس پاک می‌شوند — نه اینکه فقط مخفی شوند. این کار قابل بازگشت نیست.',
      confirmLabel: 'بله، پاک کن',
    });

    if (!confirmed) return;

    try {
      const { from, to } = tehranDayBounds(selectedDay);

      const result = await api.deleteHistory(from, to);
      toast('حذف شد', `${faNumber(result.deleted)} نقطه پاک شد.`);
      await load();
    } catch (error) {
      toast('حذف ناموفق بود', error.message, { severity: 'warning' });
    }
  }

  /* ─────────────────────── چیدمان ─────────────────────── */

  function renderAll() {
    if (destroyed) return;

    if (hidden) {
      render(container,
        el('div.card', {}, el('div.card__body', {},
          el('div.hidden-location', {},
            el('div', { text: '🙈', style: { fontSize: '2rem' } }),
            el('h3.state-block__title', { text: 'تاریخچه در دسترس نیست' }),
            el('p.state-block__text', {
              text: 'کاربر اشتراک‌گذاری موقعیت را خاموش کرده است.',
            }),
          ),
        )),
      );
      return;
    }

    if (days.length === 0) {
      render(container,
        el('div.card', {}, el('div.card__body', {},
          emptyState({
            icon: '🗺️',
            title: 'تاریخچه‌ای ثبت نشده',
            text: isOwn
              ? 'وقتی موقعیت شما ثبت شود، مسیر روزانه اینجا نمایش داده می‌شود.'
              : 'برای این کاربر هنوز مسیری ثبت نشده است.',
          }),
        )),
      );
      return;
    }

    render(
      container,
      el('div.card', {},
        el('div.card__header', {},
          el('h2.card__title', { text: 'تاریخچه‌ی مسیر' }),
          el('div.header-spacer'),
          isOwn && points.length > 0
            ? el('button.btn.btn--ghost.btn--sm', {
                type: 'button',
                text: '🗑️ حذف تاریخچه‌ی این روز',
                onClick: deleteHistory,
              })
            : null,
        ),
        el('div.card__body', {},
          renderSubjectPicker(),
          renderDayPicker(),
          renderStats(),
          points.length > 0
            ? renderMapCard()
            : emptyState({
                icon: '📭',
                title: 'برای این روز نقطه‌ای ثبت نشده',
                text: 'روز دیگری را انتخاب کنید.',
              }),
        ),
      ),
    );
  }

  /* ─────────────────────── داده ─────────────────────── */

  async function loadDay() {
    if (!selectedDay) return;

    const { from, to } = tehranDayBounds(selectedDay);

    try {
      const result = await api.history(subjectId, from, to, 3000);

      hidden = Boolean(result.hidden);
      points = result.points ?? [];
      stats = result.stats ?? null;

      renderAll();
    } catch (error) {
      if (points.length > 0 || days.length > 0) {
        toast('بارگذاری مسیر ناموفق بود', error.message, { severity: 'warning' });
        return;
      }
      render(container, errorState({ text: error.message, onRetry: loadDay }));
    }
  }

  async function load() {
    if (container.childElementCount === 0) {
      render(container, el('div.skeleton.skeleton--title'), el('div.skeleton.skeleton--map'));
    }

    try {
      if (ctx.user.role === 'guardian') {
        const links = await api.guardianships();
        watchedPrimaries = (links.primaries ?? links.watching ?? []).filter((item) =>
          item.primaryUserId ?? item.primaryUser?.id,
        );
        const requestedId = params.userId && watchedPrimaries.some((item) =>
          String(item.primaryUserId ?? item.primaryUser?.id) === String(params.userId),
        ) ? params.userId : null;
        const selectedStillValid = watchedPrimaries.some((item) =>
          String(item.primaryUserId ?? item.primaryUser?.id) === String(subjectId),
        );
        const mainSupervisorLink = watchedPrimaries.find((item) => item.isMainSupervisor);
        const defaultPrimary = mainSupervisorLink ?? watchedPrimaries[0];
        const firstId = defaultPrimary?.primaryUserId ?? defaultPrimary?.primaryUser?.id;
        subjectId = requestedId ?? (selectedStillValid ? subjectId : firstId) ?? null;
        isOwn = false;
        if (!subjectId) {
          render(container, emptyState({
            icon: '🗺️',
            title: 'کاربر اصلی‌ای برای نمایش تاریخچه نیست',
            text: 'پس از پیوند با کاربر اصلی، تاریخچهٔ مجاز او از این صفحه در دسترس است.',
          }));
          return;
        }
      }
      const result = await api.historyDays(subjectId);
      days = result.days ?? [];

      if (days.length > 0) {
        selectedDay = days[0].day;
        await loadDay();
      } else {
        renderAll();
      }
    } catch (error) {
      render(container, errorState({ text: error.message, onRetry: load }));
    }
  }

  load();

  return () => {
    destroyed = true;
    map?.destroy();
  };
}

export default mountHistory;
