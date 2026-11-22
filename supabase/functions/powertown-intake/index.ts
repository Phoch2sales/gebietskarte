// Supabase Edge Function: powertown-intake
// Nimmt Tarifcheck-Anfragen der Powertown-Landingpage entgegen und legt sie im Powertown-Leadpool ab.
//
// Sicherheit:
//  * Anonyme Besucher haben KEINEN direkten Datenbankzugriff. Nur diese Funktion schreibt (Service-Rolle).
//  * Erlaubte Herkunftsseiten über ALLOWED_ORIGINS (Komma-Liste), Honeypot-Feld, Mindest-Ausfüllzeit,
//    Ratenbegrenzung pro IP-Hash (IP wird nie im Klartext gespeichert).
//  * Doppelte Absendung (gleiche request_id) erzeugt keinen zweiten Datensatz.
//  * Gleiche Person (Telefon/E-Mail) mit offener Anfrage → kein neuer Lead, sondern Eintrag "erneute Anfrage".
//  * Keine automatische Nachricht an den Kunden, keine Weitergabe an Dritte.
//
// Geheimnisse (nur als Function-Secrets, nie im Repository):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (stellt Supabase automatisch bereit)
//   ALLOWED_ORIGINS  z. B. "https://phoch2sales.github.io,https://www.phoch2sales.de"
//   IP_HASH_SALT     beliebige lange Zufallszeichenkette
//
// Bereitstellen:  supabase functions deploy powertown-intake --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

import { validate, type Intake } from "./validate.ts";

const OPEN = ["neu", "bestaetigt", "kontaktieren", "info_fehlt", "vergleich", "angebot", "wiedervorlage"];

async function sha256(s: string) {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function cors(origin: string | null) {
  const allowed = (Deno.env.get("ALLOWED_ORIGINS") || "").split(",").map((s) => s.trim()).filter(Boolean);
  const ok = !!origin && allowed.includes(origin);
  return {
    ok,
    headers: {
      ...(ok ? { "Access-Control-Allow-Origin": origin! } : {}),
      "Vary": "Origin",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "content-type, apikey, authorization, x-client-info",
      "Content-Type": "application/json; charset=utf-8",
    },
  };
}

Deno.serve(async (req) => {
  const c = cors(req.headers.get("origin"));
  const out = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: c.headers });
  if (req.method === "OPTIONS") return new Response(null, { status: c.ok ? 204 : 403, headers: c.headers });
  if (req.method !== "POST") return out(405, { ok: false, error: "Nur POST." });
  if (!c.ok) return out(403, { ok: false, error: "Herkunft nicht erlaubt." });
  if (Number(req.headers.get("content-length") || 0) > 8000) return out(413, { ok: false, error: "Anfrage zu groß." });

  let body: Intake;
  try { body = await req.json(); } catch { return out(400, { ok: false, error: "Ungültige Anfrage." }); }
  const v = validate(body);
  if ("error" in v) return v.spam ? out(200, { ok: true }) : out(422, { ok: false, error: v.error }); // Bots bekommen keine Rückmeldung

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // Ratenbegrenzung: max. 5 Anfragen pro IP-Hash und Stunde
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "unbekannt";
  const ipHash = await sha256((Deno.env.get("IP_HASH_SALT") || "") + ip);
  const since = new Date(Date.now() - 3600_000).toISOString();
  const hits = await db.from("powertown_intake_hits").select("id", { count: "exact", head: true }).eq("ip_hash", ipHash).gte("created_at", since);
  if ((hits.count || 0) >= 5) return out(429, { ok: false, error: "Zu viele Anfragen. Bitte versuche es später noch einmal." });
  await db.from("powertown_intake_hits").insert({ ip_hash: ipHash });

  const row = v.row;
  // Doppelte Absendung desselben Formulars
  if (row.request_id) {
    const same = await db.from("powertown_leads").select("id").eq("request_id", row.request_id).maybeSingle();
    if (same.data) return out(200, { ok: true });
  }
  // Gleiche Person mit noch offener Anfrage → kein neuer Datensatz
  const prev = await db.from("powertown_leads").select("id,status").eq("dedupe_key", row.dedupe_key).in("status", OPEN)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (prev.data) {
    await db.from("powertown_lead_events").insert({ lead_id: prev.data.id, kind: "erneute_anfrage", channel: row.channel as string,
      note: `Erneute Anfrage über ${row.channel}${row.reel_id ? " (Reel " + row.reel_id + ")" : ""}${row.message ? ": " + row.message : ""}`, created_by: null });
    await db.from("powertown_leads").update({ updated_at: new Date().toISOString(), ...(row.consent_marketing ? { consent_marketing: true, consent_marketing_at: row.consent_marketing_at } : {}) }).eq("id", prev.data.id);
    return out(200, { ok: true });
  }

  const ins = await db.from("powertown_leads").insert(row).select("id").single();
  if (ins.error) {
    if (ins.error.code === "23505") return out(200, { ok: true }); // request_id gleichzeitig zweimal: schon gespeichert
    console.error("powertown-intake insert", ins.error.code); // keine Personendaten ins Protokoll
    return out(500, { ok: false, error: "Deine Anfrage konnte gerade nicht gespeichert werden. Bitte versuche es gleich noch einmal oder schreib uns per E-Mail." });
  }
  await db.from("powertown_lead_events").insert({ lead_id: ins.data.id, kind: "eingang", channel: row.channel as string,
    note: [row.reel_id && "Reel " + row.reel_id, row.utm_campaign && "Kampagne " + row.utm_campaign].filter(Boolean).join(" · ") || null, created_by: null });
  return out(200, { ok: true });
});
