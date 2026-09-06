# ارزیابی میدانی ماتریس درهم‌ریختگی

تعاریف پنل مدیریت:

- TP: مدل مثبت و بازخورد `confirmed` یا `no_response`
- FP: مدل مثبت و `false_alarm`
- FN: ردیف منفی که بعداً با `POST /falls/report-missed` تأیید شده (`detection_source = manual`)
- TN: منفی‌هایی که گزارش ازدست‌رفته ندارند

نمونه SQL:

```sql
SELECT
  COUNT(*) FILTER (WHERE classified_as_fall AND user_feedback IN ('confirmed','no_response')) AS tp,
  COUNT(*) FILTER (WHERE classified_as_fall AND user_feedback = 'false_alarm') AS fp,
  COUNT(*) FILTER (WHERE NOT classified_as_fall AND detection_source = 'manual') AS fn
FROM fall_events;
```
