/** Bound permission prompts as well as GPS acquisition; SOS must proceed on timeout. */
export function getSosLocation(geolocation, timeoutMs = 4000) {
  return new Promise((resolve) => {
    if (!geolocation) return resolve(null);
    let done = false;
    const finish = (value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => finish(null), timeoutMs);
    try {
      geolocation.getCurrentPosition(({ coords }) => {
        const { latitude, longitude, accuracy } = coords ?? {};
        if (![latitude, longitude, accuracy].every(Number.isFinite) ||
            Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || accuracy < 0 || accuracy > 10000) {
          return finish(null);
        }
        return finish({ lat: latitude, lng: longitude, accuracyM: accuracy });
      }, () => finish(null), { enableHighAccuracy: true, maximumAge: 0, timeout: timeoutMs });
    } catch { finish(null); }
  });
}
