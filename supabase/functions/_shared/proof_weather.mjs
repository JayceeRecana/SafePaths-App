import { assertBackendProfile, TEST_BACKEND } from "./backend_profile.mjs";
import { millis, ProofError, serverTime, sha256 } from "./proof_common.mjs";

export const weatherStates = [
  "clear",
  "partlyCloudy",
  "lightRain",
  "moderateRain",
  "heavyRain",
  "typhoon",
];
export function weatherState(code, rain = 0, wind = 0) {
  return wind > 30 || rain > 50
    ? "typhoon"
    : code >= 95 || [65, 67].includes(code) || rain > 15
    ? "heavyRain"
    : [61, 63].includes(code) || rain > 2
    ? "moderateRain"
    : code >= 51 && code <= 57 || rain > 0
    ? "lightRain"
    : [1, 2, 3].includes(code)
    ? "partlyCloudy"
    : "clear";
}
const bounded = (value, low, high) =>
  Number.isFinite(value) && value >= low && value <= high;
export function usableWeather(data, now, profile = TEST_BACKEND) {
  if (
    !data || data.studyArea !== profile.area ||
    !weatherStates.includes(data.currentState)
  ) return false;
  if (data.isOverrideMode) {
    return millis(data.overrideExpiresAt) > now &&
      millis(data.overrideExpiresAt) <= now + 31 * 60000;
  }
  const age = now - millis(data.observedAt);
  return data.available === true && data.source === "open-meteo" &&
    age >= -60000 && age <= 30 * 60000;
}
export function parseWeather(body, now, profile = TEST_BACKEND) {
  const c = body?.current, u = body?.current_units;
  if (
    !c || u?.time !== "unixtime" || u?.interval !== "seconds" ||
    u?.precipitation !== "mm" ||
    u?.wind_speed_10m !== "m/s" || u?.temperature_2m !== "°C" ||
    u?.relative_humidity_2m !== "%" ||
    !bounded(c.interval, 60, 3600) || !Number.isInteger(c.time) ||
    now - c.time * 1000 < -60000 || now - c.time * 1000 > 30 * 60000 ||
    !bounded(c.precipitation, 0, 300) || !bounded(c.wind_speed_10m, 0, 100) ||
    !bounded(c.temperature_2m, -50, 60) ||
    !bounded(c.relative_humidity_2m, 0, 100) ||
    !Number.isInteger(c.weather_code) || !bounded(c.weather_code, 0, 99)
  ) throw new Error("weather-invalid");
  // The current amount covers current.interval seconds; the application uses mm/h.
  const rain = c.precipitation * 3600 / c.interval;
  const h = body.hourly, hu = body.hourly_units, forecast = [];
  if (
    h && hu?.time === "unixtime" && hu?.temperature_2m === "°C" &&
    hu?.precipitation_probability === "%"
  ) {
    for (let i = 0; i < Math.min(12, h.time?.length ?? 0); i++) {
      const time = h.time[i] * 1000,
        temperature = h.temperature_2m?.[i],
        chance = h.precipitation_probability?.[i],
        code = h.weather_code?.[i];
      if (
        time < now - 3600000 || time > now + 7 * 3600000 ||
        !bounded(temperature, -50, 60) || !bounded(chance, 0, 100) ||
        !Number.isInteger(code) || !bounded(code, 0, 99)
      ) continue;
      forecast.push({
        time: new Date(time),
        temperature,
        rainChance: chance,
        state: weatherState(code),
      });
      if (forecast.length === 6) break;
    }
  }
  return {
    studyArea: profile.area,
    sparkManaged: true,
    available: true,
    source: "open-meteo",
    observedAt: new Date(c.time * 1000),
    currentState: weatherState(c.weather_code, rain, c.wind_speed_10m),
    precipitationIntensity: rain,
    windSpeed: c.wind_speed_10m,
    temperature: c.temperature_2m,
    humidity: c.relative_humidity_2m,
    forecast,
    isOverrideMode: false,
    overrideExpiresAt: null,
  };
}
export function createWeather({ db, clock = Date.now, fetcher = fetch, profile: backendProfile = TEST_BACKEND }) {
  assertBackendProfile(backendProfile);
  async function refresh() {
    const previous = await db.get("system/weather"), now = clock();
    if (usableWeather(previous.data, now, backendProfile) && previous.data.isOverrideMode) {
      return previous;
    }
    if (
      usableWeather(previous.data, now, backendProfile) &&
      now - millis(previous.data.lastFetched) < 8 * 60000
    ) return previous;
    let live;
    try {
      const url =
        `https://api.open-meteo.com/v1/forecast?latitude=${backendProfile.latitude}&longitude=${backendProfile.longitude}&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m&hourly=temperature_2m,precipitation_probability,weather_code&forecast_hours=6&wind_speed_unit=ms&temperature_unit=celsius&precipitation_unit=mm&timeformat=unixtime&timezone=UTC`;
      const response = await fetcher(url, {
        signal: AbortSignal.timeout(8000),
        redirect: "error",
      });
      if (!response.ok) throw new Error("weather-unavailable");
      const text = await response.text();
      if (text.length > 64000) throw new Error("weather-invalid");
      live = parseWeather(JSON.parse(text), clock(), backendProfile);
    } catch (_) {
      await db.transaction(async (tx) => {
        const latest = await tx.get("system/weather");
        if (usableWeather(latest.data, clock(), backendProfile) && latest.data.isOverrideMode) {
          return;
        }
        tx.set(latest.path, {
          available: false,
          sparkManaged: true,
          studyArea: backendProfile.area,
          lastFailure: serverTime,
          error: "weather-unavailable",
          isOverrideMode: false,
          overrideExpiresAt: null,
        }, { merge: true });
      });
      throw new Error("weather-unavailable");
    }
    await db.transaction(async (tx) => {
      const latest = await tx.get("system/weather");
      if (usableWeather(latest.data, clock(), backendProfile) && latest.data.isOverrideMode) {
        return;
      }
      tx.set(latest.path, { ...live, lastFetched: serverTime, error: null }, {
        merge: true,
      });
    });
    return db.get("system/weather");
  }
  async function override(uid, data) {
    if (
      !data || !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "") ||
      typeof data.enable !== "boolean" ||
      data.enable &&
        (!weatherStates.includes(data.state) ||
          !Number.isInteger(data.minutes) || data.minutes < 5 ||
          data.minutes > 30)
    ) {
      throw new ProofError(
        "invalid-argument",
        "Choose a drill of 5 to 30 minutes.",
      );
    }
    const id = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(
        JSON.stringify({
          enable: data.enable,
          state: data.enable ? data.state : null,
          minutes: data.enable ? data.minutes : null,
        }),
      );
    return db.transaction(async (tx) => {
      const [profile, receipt, current] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`weather_requests/${id}`),
        tx.get("system/weather"),
      ]);
      if (profile.data.role !== "admin") {
        throw new ProofError(
          "permission-denied",
          "Administrator access required.",
          403,
        );
      }
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          throw new ProofError(
            "already-exists",
            "Different drill request.",
            409,
          );
        }
        return { saved: true, replay: true };
      }
      const stats = {
        clear: [0, 1.5, 33, 58],
        partlyCloudy: [0, 2.5, 31, 65],
        lightRain: [2.2, 4, 30.5, 75],
        moderateRain: [7.5, 8.5, 28, 85],
        heavyRain: [22, 14, 26.5, 92],
        typhoon: [65, 35, 25, 98],
      };
      const [rain, wind, temperature, humidity] = stats[data.state] ??
        stats.clear;
      tx.set(current.path, {
        sparkManaged: true,
        studyArea: backendProfile.area,
        isOverrideMode: data.enable,
        overrideExpiresAt: data.enable
          ? new Date(clock() + data.minutes * 60000)
          : null,
        // Disabling simulation waits for real observations; it never invents clear weather.
        available: data.enable,
        source: data.enable ? "admin-drill" : "unavailable",
        error: null,
        ...(data.enable
          ? {
            currentState: data.state,
            precipitationIntensity: rain,
            windSpeed: wind,
            temperature,
            humidity,
            observedAt: new Date(clock()),
            forecast: [],
          }
          : {}),
      }, { merge: true });
      tx.set(`weather_requests/${id}`, { fingerprint, createdAt: serverTime }, {
        create: true,
      });
      return { saved: true, replay: false };
    });
  }
  return { refresh, override };
}
