// Reine Prüf- und Bereinigungslogik (ohne Datenbank), damit sie separat getestet werden kann.

export const CONSENT_VERSION = "pt-kontakt-2026-11-22";

const CHANNELS = ["landingpage", "instagram", "instagram_dm", "facebook", "whatsapp", "email"];

export type Intake = {
  request_id?: string; name?: string; phone?: string; email?: string; zip?: string;
  product?: string; customer_type?: string; contact_pref?: string; current_supplier?: string;
  consumption_kwh?: string | number; message?: string; consent_contact?: boolean; consent_marketing?: boolean;
  channel?: string; reel_id?: string; utm_source?: string; utm_medium?: string; utm_campaign?: string; utm_content?: string;
  website?: string;   // Honeypot: muss leer bleiben
  started_at?: number; // Zeitpunkt, zu dem das Formular geöffnet wurde (ms)
};

const clip = (v: unknown, n: number) => {
  const s = (v === null || v === undefined ? "" : String(v)).replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  return s ? s.slice(0, n) : null;
};
export const normPhone = (v: unknown): string | null => {
  let d = String(v ?? "").replace(/[^\d+]/g, "");
  if (!d) return null;
  if (d.startsWith("+")) d = d.slice(1);
  else if (d.startsWith("00")) d = d.slice(2);
  else if (d.startsWith("0")) d = "49" + d.slice(1);
  d = d.replace(/\D/g, "");
  return d.length >= 9 && d.length <= 15 ? "+" + d : null;
};
export const normEmail = (v: unknown): string | null => {
  const s = String(v ?? "").trim().toLowerCase();
  return /^[^\s@]{1,64}@[^\s@]+\.[a-z]{2,}$/.test(s) && s.length <= 200 ? s : null;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Prüft und bereinigt die Eingabe. Liefert entweder { error } oder { row } (ohne Service-Felder). */
export function validate(b: Intake, now = Date.now()): { error: string; spam?: boolean } | { row: Record<string, unknown> } {
  if (b.website) return { error: "spam", spam: true };
  if (typeof b.started_at === "number" && now - b.started_at < 3000) return { error: "spam", spam: true };
  const name = clip(b.name, 120);
  if (!name || name.length < 2) return { error: "Bitte gib deinen Namen an." };
  const phone = b.phone ? normPhone(b.phone) : null;
  if (b.phone && !phone) return { error: "Die Telefonnummer sieht nicht vollständig aus." };
  const email = b.email ? normEmail(b.email) : null;
  if (b.email && !email) return { error: "Die E-Mail-Adresse sieht nicht vollständig aus." };
  const pref = ["telefon", "whatsapp", "email"].includes(String(b.contact_pref)) ? String(b.contact_pref) : "telefon";
  if (!phone && !email) return { error: "Bitte gib eine Telefonnummer oder E-Mail-Adresse an." };
  if ((pref === "telefon" || pref === "whatsapp") && !phone) return { error: "Für einen Rückruf oder WhatsApp brauchen wir deine Telefonnummer." };
  if (pref === "email" && !email) return { error: "Für eine Antwort per E-Mail brauchen wir deine E-Mail-Adresse." };
  const zip = clip(b.zip, 5);
  if (!zip || !/^\d{5}$/.test(zip)) return { error: "Bitte gib eine gültige Postleitzahl an." };
  if (b.consent_contact !== true) return { error: "Bitte bestätige, dass wir dich zu deiner Anfrage kontaktieren dürfen." };
  const kwhRaw = clip(b.consumption_kwh, 12);
  const kwh = kwhRaw ? Number(kwhRaw.replace(/\./g, "").replace(",", ".")) : null;
  const t = new Date(now).toISOString();
  return {
    row: {
      request_id: b.request_id && UUID.test(b.request_id) ? b.request_id : null,
      channel: CHANNELS.includes(String(b.channel)) ? String(b.channel) : "landingpage",
      reel_id: clip(b.reel_id, 80), utm_source: clip(b.utm_source, 80), utm_medium: clip(b.utm_medium, 80),
      utm_campaign: clip(b.utm_campaign, 120), utm_content: clip(b.utm_content, 120),
      name, phone, email, zip,
      product: ["strom", "gas", "beides"].includes(String(b.product)) ? String(b.product) : "beides",
      customer_type: b.customer_type === "gewerbe" ? "gewerbe" : "privat",
      contact_pref: pref,
      current_supplier: clip(b.current_supplier, 120),
      consumption_kwh: kwh !== null && Number.isFinite(kwh) && kwh >= 0 && kwh < 1e9 ? kwh : null,
      message: clip(b.message, 1000),
      consent_contact: true, consent_contact_at: t,
      consent_marketing: b.consent_marketing === true, consent_marketing_at: b.consent_marketing === true ? t : null,
      consent_text_version: CONSENT_VERSION, consent_source: "Powertown-Tarifcheck-Formular",
      dedupe_key: phone || email,
    },
  };
}
