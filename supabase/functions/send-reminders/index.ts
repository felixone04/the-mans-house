// Promemoria WhatsApp 24 ore e 1 ora prima dell'appuntamento.
// Invocata ogni 5 minuti da pg_cron (vedi supabase/reminders_cron.sql).
//
// Variabili d'ambiente (supabase secrets set ...):
//   REMINDER_SECRET            segreto condiviso con il cron
//   WHATSAPP_PROVIDER          "meta" (default) oppure "twilio"
//   -- Meta WhatsApp Cloud API
//   META_WA_TOKEN, META_WA_PHONE_NUMBER_ID
//   META_WA_TEMPLATE_24H, META_WA_TEMPLATE_1H, META_WA_LANG (default "it")
//   -- Twilio
//   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM (es. +14155238886)
//   TWILIO_CONTENT_SID_24H, TWILIO_CONTENT_SID_1H
//
// Il modello di messaggio deve avere 4 variabili:
//   {{1}} nome cliente, {{2}} servizio, {{3}} data e ora, {{4}} barbiere

import { createClient } from "npm:@supabase/supabase-js@2";

type Kind = "24h" | "1h";

interface Row {
  id: string;
  user_id: string | null;
  start_at: string;
  service_name: string;
  customer_name: string;
  customer_phone: string;
  barbers: { name: string } | null;
  profiles: { whatsapp_opt_in: boolean } | null;
}

const env = (k: string, d = "") => Deno.env.get(k) ?? d;

const supabase = createClient(
  env("SUPABASE_URL"),
  env("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { persistSession: false } },
);

function normalizePhone(raw: string): string | null {
  let p = raw.replace(/[\s\-().]/g, "");
  if (p.startsWith("00")) p = "+" + p.slice(2);
  if (!p.startsWith("+")) p = "+39" + p.replace(/^0+(?=3)/, "");
  return /^\+\d{8,15}$/.test(p) ? p : null;
}

function formatWhen(iso: string, tz: string): string {
  const d = new Date(iso);
  const day = new Intl.DateTimeFormat("it-IT", {
    timeZone: tz, weekday: "long", day: "numeric", month: "long",
  }).format(d);
  const time = new Intl.DateTimeFormat("it-IT", {
    timeZone: tz, hour: "2-digit", minute: "2-digit",
  }).format(d);
  return `${day} alle ${time}`;
}

async function sendMeta(to: string, kind: Kind, params: string[]) {
  const template = kind === "24h" ? env("META_WA_TEMPLATE_24H") : env("META_WA_TEMPLATE_1H");
  const res = await fetch(
    `https://graph.facebook.com/v21.0/${env("META_WA_PHONE_NUMBER_ID")}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env("META_WA_TOKEN")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: to.replace("+", ""),
        type: "template",
        template: {
          name: template,
          language: { code: env("META_WA_LANG", "it") },
          components: [{
            type: "body",
            parameters: params.map((text) => ({ type: "text", text })),
          }],
        },
      }),
    },
  );
  if (!res.ok) throw new Error(`Meta ${res.status}: ${await res.text()}`);
}

async function sendTwilio(to: string, kind: Kind, params: string[]) {
  const sid = env("TWILIO_ACCOUNT_SID");
  const contentSid = kind === "24h" ? env("TWILIO_CONTENT_SID_24H") : env("TWILIO_CONTENT_SID_1H");
  const vars: Record<string, string> = {};
  params.forEach((p, i) => (vars[String(i + 1)] = p));
  const body = new URLSearchParams({
    From: `whatsapp:${env("TWILIO_WHATSAPP_FROM")}`,
    To: `whatsapp:${to}`,
    ContentSid: contentSid,
    ContentVariables: JSON.stringify(vars),
  });
  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: "Basic " + btoa(`${sid}:${env("TWILIO_AUTH_TOKEN")}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  if (!res.ok) throw new Error(`Twilio ${res.status}: ${await res.text()}`);
}

async function process(kind: Kind, tz: string, shopName: string) {
  const now = Date.now();
  const column = kind === "24h" ? "reminder_24h_sent_at" : "reminder_1h_sent_at";
  const windowEnd = new Date(now + (kind === "24h" ? 24 : 1) * 3600_000).toISOString();
  const windowStart = new Date(now + (kind === "24h" ? 2 * 3600_000 : 0)).toISOString();

  const { data, error } = await supabase
    .from("appointments")
    .select("id,user_id,start_at,created_at,service_name,customer_name,customer_phone,barbers(name),profiles(whatsapp_opt_in)")
    .eq("status", "confirmed")
    .is(column, null)
    .gt("start_at", windowStart)
    .lte("start_at", windowEnd)
    .limit(200);
  if (error) throw error;

  let sent = 0;
  const failures: string[] = [];
  for (const row of (data ?? []) as unknown as (Row & { created_at: string })[]) {
    // Il promemoria 24h ha senso solo se la prenotazione e' stata fatta prima
    if (kind === "24h" &&
        new Date(row.created_at).getTime() > new Date(row.start_at).getTime() - 23 * 3600_000) {
      continue;
    }
    if (row.profiles && row.profiles.whatsapp_opt_in === false) continue;
    const phone = normalizePhone(row.customer_phone ?? "");
    if (!phone) continue;

    const params = [
      row.customer_name || "cliente",
      row.service_name,
      formatWhen(row.start_at, tz),
      row.barbers?.name ?? shopName,
    ];
    // Segna l'invio PRIMA di spedire, solo se ancora libero: due esecuzioni
    // sovrapposte o un aggiornamento fallito non producono messaggi doppi.
    const { data: claimed, error: claimError } = await supabase
      .from("appointments")
      .update({ [column]: new Date().toISOString() })
      .eq("id", row.id)
      .is(column, null)
      .select("id");
    if (claimError) {
      failures.push(`${row.id}: ${claimError.message}`);
      continue;
    }
    if (!claimed || claimed.length === 0) continue;

    try {
      if (env("WHATSAPP_PROVIDER", "meta") === "twilio") {
        await sendTwilio(phone, kind, params);
      } else {
        await sendMeta(phone, kind, params);
      }
      sent++;
    } catch (e) {
      failures.push(`${row.id}: ${(e as Error).message}`);
      // invio fallito: si libera il promemoria per riprovare al prossimo giro
      await supabase.from("appointments").update({ [column]: null }).eq("id", row.id);
    }
  }
  return { sent, failures };
}

Deno.serve(async (req) => {
  const secret = env("REMINDER_SECRET");
  const auth = req.headers.get("x-reminder-secret") ?? "";
  if (!secret || auth !== secret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { data: settings } = await supabase
    .from("shop_settings").select("name,timezone,reminders_enabled").eq("id", 1).single();
  if (settings && settings.reminders_enabled === false) {
    return Response.json({ skipped: "reminders disabled" });
  }
  const tz = settings?.timezone ?? "Europe/Rome";
  const name = settings?.name ?? "The Man's House";

  try {
    const r24 = await process("24h", tz, name);
    const r1 = await process("1h", tz, name);
    if (r24.failures.length || r1.failures.length) {
      console.error("WhatsApp failures", r24.failures, r1.failures);
    }
    return Response.json({ "24h": r24, "1h": r1 });
  } catch (e) {
    console.error(e);
    return new Response((e as Error).message, { status: 500 });
  }
});
