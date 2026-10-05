// Pulls Roblox's own numbers into Neon (every 6 h on Render, or GET /sync): what happens before a
// player joins (impressions -> clicks -> plays, Recommended For You), Roblox's retention, revenue
// and stability, plus Ads Manager campaign status. Failures are logged to sync_log, never thrown.
import { query } from "./db.js";

// [metric, breakdown dimensions]
export const METRICS = [
  ["UniqueUsersWithImpressions", []],
  ["UniqueUsersWithClicks", []],
  ["UniqueUsersWithPlaySessions", []],
  ["ImpressionCVR", []],
  ["ClickCVR", []],
  ["EndToEndCVR", []],
  ["QualifiedEndToEndCVR", []],
  ["RFYPlayThroughRate", []],
  ["RFYQualifiedPTR", []],
  ["RFYDeepEngagementRate", []],
  ["DailyActiveUsers", []],
  ["Visits", []],
  ["AverageSessionLengthMinutes", []],
  ["AveragePlayTimeMinutesPerDAU", []],
  ["PeakConcurrentPlayers", []],
  ["ForwardD1Retention", []],
  ["ForwardD7Retention", []],
  ["DailyRevenue", []],
  ["PayingUsers", []],
  ["PayingUsersCVR", []],
  ["AverageRevenuePerUser", []],
  ["ClientCrashRate15m", []],
  ["ClientFpsP10", []],
  ["UniqueUsersWithImpressions", ["AcquisitionSource"]],
  ["UniqueUsersWithPlaySessions", ["AcquisitionSource"]],
  ["ForwardD1Retention", ["AcquisitionSource"]],
  ["ForwardD1Retention", ["Platform"]],
];

async function log(job, ok, detail) {
  await query(`insert into sync_log (job, ok, detail) values ($1, $2, $3)`, [job, ok, String(detail).slice(0, 500)]);
}

export async function syncMetrics(rb, universeId, { days = 10, pace = 2200 } = {}) {
  let rows = 0;
  let failed = 0;
  for (const [metric, breakdown] of METRICS) {
    try {
      const series = await rb.metric(universeId, metric, { days, breakdown });
      for (const s of series) {
        const dim = (s.breakdowns || []).map((b) => b.dimension).join("+");
        const value = (s.breakdowns || []).map((b) => b.displayValue || b.value).join("+");
        for (const point of s.dataPoints || []) {
          if (typeof point.value !== "number" || !Number.isFinite(point.value)) continue;
          await query(
            `insert into roblox_metrics (day, metric, dim, value, v, synced_at) values ($1, $2, $3, $4, $5, now())
             on conflict (day, metric, dim, value) do update set v = excluded.v, synced_at = now()`,
            [String(point.time).slice(0, 10), metric, dim, value, point.value],
          );
          rows++;
        }
      }
    } catch (err) {
      failed++;
      await log(`metric ${metric}${breakdown.length ? ` by ${breakdown.join("+")}` : ""}`, false, err.message);
    }
    if (pace) await new Promise((r) => setTimeout(r, pace)); // 30 queries/min per key owner
  }
  await log("metrics", failed === 0, `${rows} data points, ${failed} metrics failed`);
  return { rows, failed };
}

export async function syncCampaigns(rb) {
  try {
    const campaigns = await rb.listCampaigns();
    for (const c of campaigns) {
      await query(
        `insert into ad_campaigns (id, name, status, delivery, reasons, budget_usd, budget_type, objective, universe_id, start_time,
           duration_days, targeting, updated_at, synced_at)
         values ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9, $10, $11, $12::jsonb, $13, now())
         on conflict (id) do update set name = excluded.name, status = excluded.status, delivery = excluded.delivery,
           reasons = excluded.reasons, budget_usd = excluded.budget_usd, budget_type = excluded.budget_type,
           objective = excluded.objective, start_time = excluded.start_time, duration_days = excluded.duration_days,
           targeting = excluded.targeting, updated_at = excluded.updated_at, synced_at = now()`,
        [
          c.id,
          c.name || "",
          c.status || "",
          c.deliveryStatus || "",
          JSON.stringify(c.deliveryStatusReasons || []),
          c.budget?.amountMicros ? Number(c.budget.amountMicros) / 1e6 : null,
          c.budget?.type || null,
          c.objective || null,
          c.targetUniverseId || null,
          c.schedule?.startTime || null,
          c.schedule?.durationInDays ?? null,
          JSON.stringify(c.targeting || {}),
          c.updateTime || null,
        ],
      );
    }
    await log("campaigns", true, `${campaigns.length} campaigns`);
    return campaigns.length;
  } catch (err) {
    await log("campaigns", false, err.message);
    return -1;
  }
}

export async function syncAll(rb, universeId, options) {
  const metrics = await syncMetrics(rb, universeId, options);
  const campaigns = await syncCampaigns(rb);
  return { ...metrics, campaigns };
}
