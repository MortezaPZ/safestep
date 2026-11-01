import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import request from 'supertest';

process.env.PGLITE_DATA_DIR = 'memory';
process.env.DB_DRIVER = 'pglite';
process.env.NODE_ENV = 'test';
process.env.NOTIFICATION_DRIVER = 'local';

const { createApp } = await import('../src/app.js');
const { default: db } = await import('../src/db/index.js');
const { runMigrations } = await import('../src/db/migrate.js');
const { createAdmin } = await import('../src/db/createAdmin.js');
const { default: hub } = await import('../src/realtime/hub.js');
const { raiseAlert } = await import('../src/services/alertService.js');
const { ALERT_TYPES, WS_EVENTS } = await import('../src/config/constants.js');

const PASSWORD = 'Test@1234';
let app;
let adminId;
let subjectId;

beforeAll(async () => {
  await db.connect();
  await runMigrations();
  app = createApp();

  const admin = await createAdmin({
    phone: '09148880001',
    fullName: 'ادمین آزمون حریم خصوصی',
    password: 'Admin@12345',
  });
  adminId = admin.user.id;

  const subject = await request(app).post('/api/v1/auth/register').send({
    phone: '09148880002',
    password: PASSWORD,
    fullName: 'کاربر آزمون حریم خصوصی',
    role: 'primary',
  });
  expect(subject.status).toBe(201);
  subjectId = subject.body.user.id;
});

afterEach(() => {
  hub.setTransport(null);
});

afterAll(async () => {
  hub.setTransport(null);
  await db.close();
});

describe('حریم خصوصی پیام هشدار سقوط ادمین', () => {
  it('مختصات را از کل payload وب‌سوکت حذف و فقط metadata مجاز را نگه می‌دارد', async () => {
    const emissions = [];
    hub.setTransport({
      emit(userIds, event, payload) {
        emissions.push({ userIds, event, payload });
      },
      isUserOnline: () => false,
    });

    await raiseAlert({
      userId: subjectId,
      type: ALERT_TYPES.FALL_DETECTED,
      location: { lat: 35.7219, lng: 51.3347 },
      context: { confidence: 0.96 },
      metadata: {
        fallEventId: 'fall-event-1',
        confidence: 0.96,
        feedback: 'no_response',
        manualReport: false,
        location: { lat: 35.7219, lng: 51.3347 },
        coordinates: [35.7219, 51.3347],
        nested: { latitude: 35.7219, longitude: 51.3347 },
      },
    });

    const adminEvent = emissions.find(
      ({ userIds, event }) => userIds.includes(adminId) && event === WS_EVENTS.ALERT_NEW,
    );
    const subjectEvent = emissions.find(
      ({ userIds, event }) => userIds.includes(subjectId) && event === WS_EVENTS.ALERT_NEW,
    );

    expect(adminEvent).toBeDefined();
    expect(adminEvent.payload.lat).toBeNull();
    expect(adminEvent.payload.lng).toBeNull();
    expect(adminEvent.payload.location).toBeNull();
    expect(adminEvent.payload.metadata).toEqual({
      fallEventId: 'fall-event-1',
      confidence: 0.96,
      feedback: 'no_response',
      manualReport: false,
    });
    expect(adminEvent.payload).not.toHaveProperty('coordinates');
    expect(adminEvent.payload).not.toHaveProperty('nested');

    expect(subjectEvent.payload.lat).toBeCloseTo(35.7219);
    expect(subjectEvent.payload.lng).toBeCloseTo(51.3347);
  });
});
