import api from '../api.js';
import { el, toast } from '../ui.js';

/** ارسال مدرک، مدارک تأییدشده، مشکل سلامت و پیام پشتیبانی. */
export function carePanel({ subjectUserId } = {}) {
  const docs = el('div');
  const thread = el('div');
  const file = el('input', { type: 'file', accept: 'image/*' });
  const condition = el('input.field__input', { placeholder: 'مثلاً بیماری قلبی یا سالمند' });
  const message = el('textarea.field__input', { rows: '3', placeholder: 'پیام به پشتیبانی' });

  async function refresh() {
    const [docPage, support] = await Promise.all([
      api.myDocuments().catch(() => ({ documents: [] })),
      api.mySupport().catch(() => ({ messages: [] })),
    ]);
    const list = (docPage.documents ?? []).filter((item) => !subjectUserId || item.userId === subjectUserId);
    docs.replaceChildren(
      list.length === 0
        ? el('p.muted', { text: 'مدرکی ارسال نشده است.' })
        : el('div', {}, ...list.map((item) => el('p', {
          text: `${item.status === 'approved' ? 'تأیید شده' : item.status === 'pending' ? 'در انتظار' : item.status}`
            + (item.healthCondition ? ` — مشکل: ${item.healthCondition}` : ''),
        }))),
    );
    const messages = support.messages ?? [];
    thread.replaceChildren(
      messages.length === 0
        ? el('p.muted', { text: 'پیامی نیست.' })
        : el('div', {}, ...messages.map((item) => el('p', {
          text: `${item.senderRole === 'admin' ? 'پشتیبانی' : 'شما'}: ${item.body}`,
        }))),
    );
  }

  file.addEventListener('change', async () => {
    const picked = file.files?.[0];
    if (!picked) return;
    const imageUrl = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(new Error('خواندن تصویر نشد'));
      reader.readAsDataURL(picked);
    });
    await api.sendDocument({
      documentType: 'identity',
      imageUrl,
      healthCondition: condition.value.trim() || undefined,
      subjectUserId,
    });
    toast('مدرک ارسال شد', 'پس از تأیید مدیر، مشکل سلامت نمایش داده می‌شود.');
    await refresh();
  });

  const root = el('div.card', {},
    el('div.card__body', {},
      el('h2.card__title', { text: 'مدارک و پشتیبانی' }),
      el('p.muted', { text: 'یکی از کاربر اصلی یا ناظر اصلی باید مدرک را بفرستد.' }),
      el('label.field__label', { text: 'مشکل شخص' }),
      condition,
      file,
      docs,
      el('h3.mt-4', { text: 'پیام به پشتیبانی' }),
      message,
      el('button.btn.btn--secondary.btn--sm', {
        type: 'button',
        text: 'ارسال پیام',
        onClick: async () => {
          if (!message.value.trim()) return;
          await api.sendSupport(message.value.trim());
          message.value = '';
          toast('پیام ارسال شد');
          await refresh();
        },
      }),
      thread,
    ),
  );

  refresh().catch(() => docs.replaceChildren(el('p.muted', { text: 'بارگذاری مدارک ممکن نشد.' })));
  return root;
}
