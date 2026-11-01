import { describe, expect, it, vi } from 'vitest';

const writtenBatches = vi.hoisted(() => ({
  requests: [],
  locations: [],
  deliveries: [],
}));

vi.mock('../src/repositories/logRepository.js', () => ({
  default: {
    insertRequestLogs: vi.fn(async (batch) => {
      writtenBatches.requests.push(batch.length);
      return batch.length;
    }),
    insertLocationTelemetry: vi.fn(async (batch) => {
      writtenBatches.locations.push(batch.length);
      return batch.length;
    }),
    insertAlertDeliveries: vi.fn(async (batch) => {
      writtenBatches.deliveries.push(batch.length);
      return batch.length;
    }),
    acknowledgeDelivery: vi.fn(async () => 1),
  },
}));

process.env.NODE_ENV = 'test';
const telemetryService = await import('../src/services/telemetryService.js');

describe('telemetry batching under load', () => {
  it('drains all telemetry buckets at the configured batch rate without dropping records', async () => {
    vi.useFakeTimers();
    telemetryService.setEnabled(true);

    try {
      for (let i = 0; i < 600; i += 1) {
        telemetryService.recordRequest({ requestId: `request-${i}` });
        telemetryService.recordLocation({ pingId: `ping-${i}` });
        telemetryService.recordDelivery({ alertId: `alert-${i}` });
      }

      expect(telemetryService.status()).toMatchObject({ pending: 1800, dropped: 0 });

      await vi.advanceTimersByTimeAsync(1000);
      expect(writtenBatches).toEqual({
        requests: [500],
        locations: [500],
        deliveries: [500],
      });
      expect(telemetryService.status()).toMatchObject({ pending: 300, dropped: 0 });

      await vi.advanceTimersByTimeAsync(1000);
      expect(writtenBatches).toEqual({
        requests: [500, 100],
        locations: [500, 100],
        deliveries: [500, 100],
      });
      expect(telemetryService.status()).toMatchObject({ pending: 0, dropped: 0 });
    } finally {
      telemetryService.setEnabled(false);
      await telemetryService.flushAll();
      vi.useRealTimers();
    }
  });
});
