const crypto = require('node:crypto');
const clamp = (x, lo = 0, hi = 100) => Math.min(hi, Math.max(lo, x));
const millis = value => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : Number(value) || 0);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const reportTime = report => millis(report.observedAt || report.lastUpdatedByUser || report.createdAt);
function validateReport(data) {
  if (!data || typeof data !== 'object') throw new Error('Invalid report.');
  for (const [key, max] of [['requestId', 128], ['roadId', 128], ['title', 200], ['description', 2000]]) {
    if (typeof data[key] !== 'string' || !data[key].trim() || data[key].length > max) throw new Error(`Invalid ${key}.`);
  }
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId) || data.roadId.includes('/')) throw new Error('Invalid report identifier.');
  if (!['Low', 'Medium', 'High'].includes(data.severity) || typeof data.isEmergency !== 'boolean') throw new Error('Invalid severity.');
  const {lat, lng} = data.location ?? {};
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) throw new Error('Invalid location.');
  const observedAt = data.observedAt == null ? null : Date.parse(data.observedAt);
  if (observedAt !== null && !Number.isFinite(observedAt)) throw new Error('Invalid observation time.');
  const location = {lat, lng};
  if (['gps', 'manual'].includes(data.location.source)) location.source = data.location.source;
  if (data.location.gpsAccuracyMeters != null) {
    if (!Number.isFinite(data.location.gpsAccuracyMeters) || data.location.gpsAccuracyMeters < 0) throw new Error('Invalid GPS accuracy.');
    location.gpsAccuracyMeters = data.location.gpsAccuracyMeters;
  }
  if (data.location.gpsCapturedAt != null) {
    const gpsTime = Date.parse(data.location.gpsCapturedAt);
    if (!Number.isFinite(gpsTime) || gpsTime > Date.now() + 60000) throw new Error('Invalid GPS timestamp.');
    location.gpsCapturedAt = data.location.gpsCapturedAt;
  }
  return {title: data.title.trim(), description: data.description.trim(), severity: data.severity,
    roadId: data.roadId, isEmergency: data.isEmergency, observedAt, location};
}
function points(value) {
  if (!value) return [];
  if (Array.isArray(value)) {
    if (value.length >= 2 && value.slice(0,2).every(Number.isFinite)) return [value.slice(0,2)];
    return value.flatMap(points);
  }
  const lng = value.lon ?? value.lng ?? value.longitude;
  const lat = value.lat ?? value.latitude;
  return Number.isFinite(lng) && Number.isFinite(lat) ? [[lng,lat]] : [];
}
function lines(geometry) {
  if (!geometry) return [];
  if (geometry.type === 'Feature') return lines(geometry.geometry);
  if (Array.isArray(geometry.segments)) return geometry.segments.map(s => points(s.points)).filter(s => s.length >= 2);
  if (geometry.type === 'MultiLineString') return (geometry.coordinates ?? []).map(points).filter(s => s.length >= 2);
  const line = points(geometry.coordinates);
  return line.length >= 2 ? [line] : [];
}
function distance(a, b) {
  const rad = Math.PI / 180, lat = (a[1] + b[1]) / 2 * rad;
  return Math.hypot((a[0] - b[0]) * rad * Math.cos(lat), (a[1] - b[1]) * rad) * 6371000;
}
function roadDistance(location, geometry) {
  const p = [location.lng, location.lat];
  let best = Infinity;
  for (const line of lines(geometry)) {
    for (let i = 0; i < line.length; i++) {
      const a = line[i], b = line[i + 1];
      best = Math.min(best, distance(p, a));
      if (!b) continue;
      const cos = Math.cos(p[1] * Math.PI / 180);
      const dx = (b[0] - a[0]) * cos, dy = b[1] - a[1];
      const t = clamp((((p[0] - a[0]) * cos) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy || 1), 0, 1);
      best = Math.min(best, distance(p, [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]));
    }
  }
  return best;
}
function confidence(report, roads, reports, weather, now) {
  const official = roads.find(r => r.id === report.roadId);
  const hours = Math.max(0, Math.trunc((now - reportTime(report)) / 60000) / 60);
  const decay = {lightRain: 16, moderateRain: 20, heavyRain: 28, typhoon: 36}[weather] ?? 12;
  const recency = clamp(100 - hours * 100 / decay);
  const multiplier = {lightRain: 1.05, moderateRain: 1.10, heavyRain: 1.15, typhoon: 1.25}[weather]
    ?? (weather === 'clear' && (!official || official.status === 'passable') ? 0.85 : 1);
  const users = new Map();
  for (const other of reports) {
    if (other.id === report.id || other.userId === report.userId || other.roadId !== report.roadId || (other.reportType === 'followup' && other.incidentReviewStatus === 'passable') || !['pending', 'under_review'].includes(other.status)) continue;
    if (now - reportTime(other) >= 86400000 || reportTime(other) > now + 60000) continue;
    if (Math.abs(reportTime(other) - reportTime(report)) >= 31 * 60000) continue;
    if (!users.has(other.userId) || reportTime(other) > reportTime(users.get(other.userId))) users.set(other.userId, other);
  }
  let consensus = users.size ? 50 : 0;
  for (const other of users.values()) consensus += (other.severity === report.severity ? 25 : -15) * clamp((other.authorityScore ?? 25) / 100, 0.2, 1);
  // Match existing confidence calculation: proximity uses road vertices.
  const d = report.location && official ? Math.min(Infinity,
    ...lines(official.geometry).flat().map(p => distance([report.location.lng, report.location.lat], p))) : Infinity;
  const proximity = Number.isFinite(d) ? d <= 50 ? 20 : d <= 500 ? 10 : d >= 2000 ? -20 : 0 : 0;
  return clamp(clamp(report.authorityScore ?? 25) * 0.5 + clamp(consensus) * multiplier * 0.3 + recency * 0.2 + proximity);
}
function calculateRisks(roads, reports, weather, now) {
  const previous = new Map(roads.map(r => [r.id, r.riskScore ?? 0]));
  const weatherMultiplier = {clear: 0, partlyCloudy: 0, lightRain: 0.2, moderateRain: 0.4, heavyRain: 0.7, typhoon: 1}[weather];
  if (weatherMultiplier === undefined) throw new Error('Unknown weather state');
  return roads.map(road => {
    const base = road.status === 'not_passable' ? 100 : road.status === 'partial' ? 50 : 0;
    let consensus = 0;
    const latestByUser = new Map();
    for (const r of reports.filter(r => r.roadId === road.id && !(r.reportType === 'followup' && r.incidentReviewStatus === 'passable') && ['pending', 'under_review'].includes(r.status) &&
      now - reportTime(r) < 86400000 && reportTime(r) <= now + 60000)) {
      const previous = latestByUser.get(r.userId);
      if (!previous || reportTime(r) > reportTime(previous) || (reportTime(r) === reportTime(previous) && r.id > previous.id)) latestByUser.set(r.userId, r);
    }
    for (const r of latestByUser.values()) {
      consensus += confidence(r, roads, reports, weather, now) * ({High: 0.8, Medium: 0.5, Low: 0.2}[r.severity] ?? 0);
    }
    consensus = clamp(consensus);
    let neighborRisk = 0, neighborId = null;
    for (const id of road.neighbors ?? []) if ((previous.get(id) ?? 0) > neighborRisk) { neighborRisk = previous.get(id); neighborId = id; }
    const propagation = Math.min(neighborRisk * weatherMultiplier * ({high: 1, medium: 0.5}[road.vulnerability] ?? 0.2), neighborRisk * 0.95);
    const total = clamp(base + consensus + propagation);
    const warningStartTime = total >= 60 ? millis(road.warningStartTime) || millis(road.updatedAt) || now : null;
    const minutes = warningStartTime === null ? 0 : Math.trunc((now - warningStartTime) / 60000);
    const bonus = total < 60 ? 0 : minutes > 120 ? -20 : minutes >= 60 ? 20 : minutes >= 30 ? 10 : 0;
    const caution = ['reported_flooding', 'under_verification', 'outdated', 'admin_confirmed'].includes(road.communityCondition);
    const riskScore = Math.max(caution ? 30 : 0, clamp(total + bonus));
    return {id: road.id, riskScore, riskCategory: riskScore >= 80 ? 'Critical' : riskScore >= 60 ? 'Warning' : riskScore >= 30 ? 'Watch' : 'Safe',
      warningStartTime, propagationSource: neighborRisk > base && neighborRisk > consensus ? neighborId : null};
  });
}
module.exports = {hash, millis, clamp, validateReport, lines, distance, roadDistance, confidence, calculateRisks};
