/**
 * اسکریپت پاکسازی پایگاه داده پیش از شروع رسمی آزمایش میدانی.
 *
 * این اسکریپت تمامی ردیف‌های تستی ایجادشده در مرحله آزمون اولیه (بند ۴)
 * را از جداول داده‌ای پاک می‌کند، در حالی که ساختار جداول، مایگریشن‌ها
 * و حساب مدیر سامانه دست‌نخورده باقی می‌مانند.
 *
 * اجرا:
 *   npm run cleanup:pilot
 * یا با تایید خودکار:
 *   npm run cleanup:pilot -- --confirm
 */
import db from '../src/db/index.js';
import { ROLES } from '../src/config/constants.js';

async function cleanupPilotDatabase() {
  const isConfirmed = process.argv.includes('--confirm');

  console.log('═══════════════════════════════════════════════════════');
  console.log('  SafeStep: اسکریپت پاکسازی داده‌های پیش‌آزمون پایلوت   ');
  console.log('═══════════════════════════════════════════════════════\n');

  if (!isConfirmed) {
    console.warn('توجه: جهت اجرای قطعی، فلگ --confirm را اضافه کنید:');
    console.warn('  npm run cleanup:pilot -- --confirm\n');
  }

  try {
    await db.connect();

    // بررسی وجود مدیر سامانه
    const adminRes = await db.query(
      `SELECT id, phone, full_name, role FROM users WHERE role = $1 LIMIT 1`,
      [ROLES.ADMIN]
    );

    if (adminRes.rows.length === 0) {
      console.warn('هشدار: حساب مدیریتی در دیتابیس یافت نشد! ابتدا npm run create:admin را اجرا کنید.');
    } else {
      console.log(`حساب مدیر فعال: ${adminRes.rows[0].full_name} (${adminRes.rows[0].phone}) - حفظ می‌شود.`);
    }

    const tables = [
      'location_telemetry',
      'location_pings',
      'location_reference_samples',
      'location_references',
      'alert_deliveries',
      'alerts',
      'alert_reads',
      'fall_events',
      'sus_responses',
      'fcm_device_receipts',
      'devices',
      'guardianships',
      'safe_zones',
      'zone_states',
      'audit_logs',
      'request_logs',
    ];

    if (!isConfirmed) {
      console.log('گزارش وضعیت جداول پیش از پاکسازی:');
      for (const table of tables) {
        try {
          const countRes = await db.query(`SELECT count(*)::int as count FROM ${table}`);
          console.log(`  - ${table}: ${countRes.rows[0].count} ردیف`);
        } catch (e) {
          // در صورت عدم وجود جدول
        }
      }
      return;
    }

    console.log('\nدر حال اجرای پاکسازی تراکنشی...');

    await db.transaction(async (client) => {
      // پاکسازی لاگ‌ها و داده‌های تله‌متری آزمایشی
      await client.query(`TRUNCATE TABLE location_telemetry CASCADE;`);
      await client.query(`TRUNCATE TABLE location_pings CASCADE;`);
      await client.query(`TRUNCATE TABLE location_reference_samples CASCADE;`);
      await client.query(`TRUNCATE TABLE alert_deliveries CASCADE;`);
      await client.query(`TRUNCATE TABLE alerts CASCADE;`);
      await client.query(`TRUNCATE TABLE alert_reads CASCADE;`);
      await client.query(`TRUNCATE TABLE fall_events CASCADE;`);
      await client.query(`TRUNCATE TABLE sus_responses CASCADE;`);
      await client.query(`TRUNCATE TABLE fcm_device_receipts CASCADE;`);
      await client.query(`TRUNCATE TABLE devices CASCADE;`);
      await client.query(`TRUNCATE TABLE safe_zones CASCADE;`);
      await client.query(`TRUNCATE TABLE zone_states CASCADE;`);
      await client.query(`TRUNCATE TABLE guardianships CASCADE;`);

      // پاکسازی کاربران غیر ادمین (کاربران آزمایشی)
      await client.query(`DELETE FROM users WHERE role != $1;`, [ROLES.ADMIN]);

      // ثبت لاگ رخداد پاکسازی در لاگ بازرسی
      await client.query(
        `INSERT INTO audit_logs (actor_user_id, actor_role, action, entity_type, entity_id, metadata)
         VALUES ($1, $2, 'pilot_db_cleanup', 'system', $1, '{"status": "clean_for_pilot"}')`,
        [adminRes.rows[0]?.id || '00000000-0000-0000-0000-000000000000', ROLES.ADMIN]
      );
    });

    console.log('✓ پاکسازی با موفقیت انجام شد. پایگاه داده کاملاً آماده شروع پایلوت است.\n');

    console.log('وضعیت نهایی جداول پایلوت:');
    const checkTables = [
      'location_telemetry',
      'location_reference_samples',
      'alert_deliveries',
      'fall_events',
      'sus_responses',
      'users',
    ];
    for (const table of checkTables) {
      const countRes = await db.query(`SELECT count(*)::int as count FROM ${table}`);
      console.log(`  - ${table}: ${countRes.rows[0].count} ردیف`);
    }

  } catch (err) {
    console.error('خطا در پاکسازی دیتابیس:', err);
    process.exitCode = 1;
  } finally {
    await db.close();
  }
}

cleanupPilotDatabase();
