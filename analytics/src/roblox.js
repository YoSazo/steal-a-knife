// Roblox Open Cloud (apis.roblox.com), the parts we use. Shapes come from Roblox's OpenAPI spec
// (github.com/Roblox/creator-docs content/en-us/reference/cloud/openapi.json).
//   - Analytics Query API (universe.analytics:read): Roblox's own numbers, incl. impressions -> plays
//   - Developer products / game passes (developer-product:read+write, game-pass:read+write)
//   - Secrets store (universe.secret:read+write): the game's ingest_key
//   - Ads Manager (ad.campaign:read, user-owned key): campaign status (no spend reporting yet)
const BASE = "https://apis.roblox.com";

export class RobloxError extends Error {
  constructor(status, body, what) {
    super(`${what}: HTTP ${status} ${typeof body === "string" ? body.slice(0, 300) : JSON.stringify(body).slice(0, 300)}`);
    this.status = status;
    this.body = body;
  }
}

export function client({ apiKey, fetchImpl = fetch }) {
  async function call(method, path, { json, form, what } = {}) {
    for (let attempt = 1; ; attempt++) {
      const headers = { "x-api-key": apiKey };
      let body;
      if (json !== undefined) {
        headers["Content-Type"] = "application/json";
        body = JSON.stringify(json);
      } else if (form) {
        body = new FormData();
        for (const [key, value] of Object.entries(form)) {
          if (value instanceof Blob) body.append(key, value, `${key}.png`);
          else if (value !== undefined && value !== null) body.append(key, String(value));
        }
      }
      const res = await fetchImpl(BASE + path, { method, headers, body });
      const text = await res.text();
      let data = text;
      try {
        data = text ? JSON.parse(text) : {};
      } catch {}
      // Rate limited (Analytics: 30 queries/min): wait it out
      if ((res.status === 429 || res.status >= 500) && attempt < 5) {
        await new Promise((r) => setTimeout(r, Math.min(30000, 2000 * attempt * attempt)));
        continue;
      }
      if (!res.ok) throw new RobloxError(res.status, data, what || `${method} ${path}`);
      return { status: res.status, data };
    }
  }

  async function all(path, field) {
    const out = [];
    let token = "";
    do {
      const sep = path.includes("?") ? "&" : "?";
      const { data } = await call("GET", `${path}${sep}pageSize=50${token ? `&pageToken=${encodeURIComponent(token)}` : ""}`);
      out.push(...(data[field] || []));
      token = data.nextPageToken || "";
    } while (token);
    return out;
  }

  return {
    call,

    // Public: which universe a place belongs to
    async universeOf(placeId) {
      const res = await fetchImpl(`${BASE}/universes/v1/places/${placeId}/universe`);
      if (!res.ok) throw new RobloxError(res.status, await res.text(), "universe lookup");
      return (await res.json()).universeId;
    },

    // Analytics Query API: one metric, daily, optional breakdown. Polls until done.
    async metric(universeId, metric, { days = 7, breakdown = [], granularity = "OneDay" } = {}) {
      const end = new Date();
      end.setUTCHours(0, 0, 0, 0);
      end.setUTCDate(end.getUTCDate() + 1);
      const start = new Date(end.getTime() - days * 864e5);
      let { data } = await call("POST", `/analytics-query-api/v1/universes/${universeId}/metrics`, {
        json: { metric, granularity, startTime: start.toISOString(), endTime: end.toISOString(), breakdown },
        what: `metric ${metric}`,
      });
      for (let i = 0; !data.done && i < 60; i++) {
        await new Promise((r) => setTimeout(r, 1500));
        // The returned path names the operation; build the documented GET from its id
        const operationId = String(data.path || "").split("/").pop();
        const path = `/analytics-query-api/v1/universes/${universeId}/operations/metrics/${operationId}`;
        ({ data } = await call("GET", path, { what: `metric ${metric} (poll)` }));
      }
      if (!data.done) throw new Error(`metric ${metric}: still running after 90 s`);
      return data.response?.values || [];
    },

    listProducts: (universeId) => all(`/developer-products/v2/universes/${universeId}/developer-products/creator`, "developerProducts"),
    listPasses: (universeId) => all(`/game-passes/v1/universes/${universeId}/game-passes/creator`, "gamePasses"),
    createProduct: (universeId, form) =>
      call("POST", `/developer-products/v2/universes/${universeId}/developer-products`, { form, what: `create product ${form.name}` }),
    updateProduct: (universeId, id, form) =>
      call("PATCH", `/developer-products/v2/universes/${universeId}/developer-products/${id}`, { form, what: `update product ${id}` }),
    createPass: (universeId, form) =>
      call("POST", `/game-passes/v1/universes/${universeId}/game-passes`, { form, what: `create pass ${form.name}` }),
    updatePass: (universeId, id, form) =>
      call("PATCH", `/game-passes/v1/universes/${universeId}/game-passes/${id}`, { form, what: `update pass ${id}` }),

    secretsPublicKey: (universeId) => call("GET", `/cloud/v2/universes/${universeId}/secrets/public-key`, { what: "secrets public key" }),
    listSecrets: (universeId) => call("GET", `/cloud/v2/universes/${universeId}/secrets`, { what: "list secrets" }),
    createSecret: (universeId, secret) => call("POST", `/cloud/v2/universes/${universeId}/secrets`, { json: secret, what: "create secret" }),
    updateSecret: (universeId, id, secret) =>
      call("PATCH", `/cloud/v2/universes/${universeId}/secrets/${id}`, { json: secret, what: "update secret" }),

    // Experience Notifications (user.user-notification:write): one "come back" message to one player.
    // parameters: { name: "value" } -> the notification string's {name} placeholders
    sendNotification: ({ userId, universeId, messageId, parameters = {}, launchData = "", category = "" }) =>
      call("POST", `/cloud/v2/users/${userId}/notifications`, {
        json: {
          source: { universe: `universes/${universeId}` },
          payload: {
            message_id: messageId,
            type: "MOMENT",
            parameters: Object.fromEntries(Object.entries(parameters).map(([k, v]) => [k, { string_value: String(v) }])),
          },
          join_experience: { launch_data: launchData },
          analytics_data: { category },
        },
        what: "send notification",
      }),

    async listCampaigns() {
      const out = [];
      let token = "";
      do {
        const { data } = await call("GET", `/ads-management/v1/campaigns?maxPageSize=100${token ? `&pageToken=${encodeURIComponent(token)}` : ""}`, {
          what: "list campaigns",
        });
        out.push(...(data.campaigns || []));
        token = data.nextPageToken || "";
      } while (token);
      return out;
    },
  };
}
