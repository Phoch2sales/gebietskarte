# Powertown-Leadpool – Einrichtung (Entwurf, noch nicht live)

Nichts davon ist aktiv, bevor Florian es ausdrücklich freigibt.

## Was dieser Branch enthält
| Teil | Datei | Zweck |
|---|---|---|
| Datenbank | `supabase/powertown_leads.sql` | Tabellen für Leads, Verlauf, Exportprotokoll, Einstellungen (Not-Aus), Aktionsprotokoll; Zugriff nur Admin |
| Formular-Eingang | `supabase/functions/powertown-intake/` | Edge Function: prüft und speichert Anfragen, Dublettenprüfung, Spam-/Ratenschutz |
| Tarifcheck-Seite | `tarifcheck/index.html` | Mobile Landingpage für den Link in der Instagram-Bio |
| MultiTool | `index.html` → Leads → Reiter „Powertown“ | Eingang, Pipeline, Alle, Rückrufe, Auswertung, Einstellungen |

## Regeln, die technisch erzwungen werden
- Nur Admins sehen Powertown-Leads (Datenbank-Regeln, nicht nur Oberfläche). Vertreter/Teamleiter: kein Zugriff.
- Anonyme Besucher können nichts lesen; Anfragen kommen nur über die Edge Function.
- Keine automatische Weitergabe. Export an einen Leadverteiler nur einzeln, mit Empfänger, Zweck und Rechtsgrundlage, und nur wenn in den Einstellungen freigeschaltet (Standard: gesperrt). Jede Übergabe wird unveränderlich protokolliert.
- Keine automatischen Nachrichten an Kunden.
- `publishing_enabled` = zentraler Not-Aus für spätere Meta-Veröffentlichungen (Standard: aus).
- Einwilligung zur Rückmeldung und Einwilligung in Werbung werden getrennt mit Zeitpunkt und Textfassung gespeichert.
- Löschfrist: 365 Tage (einstellbar), Löschen per Knopf oder optional per pg_cron.

## Schritte zur Inbetriebnahme (erst nach Freigabe)
1. Supabase → SQL Editor → Inhalt von `supabase/powertown_leads.sql` ausführen (darf mehrfach laufen, ändert keine bestehenden Tabellen).
2. Edge Function bereitstellen: `supabase functions deploy powertown-intake --no-verify-jwt`
3. Function-Secrets setzen (nie ins Repository):
   - `ALLOWED_ORIGINS` = Adresse(n), unter der die Tarifcheck-Seite läuft
   - `IP_HASH_SALT` = lange Zufallszeichenkette
4. Datenschutzhinweise auf der Tarifcheck-Seite anwaltlich prüfen lassen und Platzhalter ([Region], [Hosting]) füllen.
5. End-to-End-Test mit einer erfundenen Anfrage: erscheint genau einmal im Reiter „Powertown“, Status ändern, Kontakt dokumentieren, löschen.
6. Erst danach den Link in die Instagram-Bio, z. B. `…/tarifcheck/?utm_source=instagram&utm_campaign=folge1&reel=F1`

## Bekannte offene Punkte
- Benachrichtigung bei neuer Anfrage (E-Mail/Push) ist noch nicht eingebaut – Anfragen sind im MultiTool sichtbar.
- Hosting-Adresse der Tarifcheck-Seite festlegen (eigene Subdomain empfohlen, z. B. tarifcheck.phoch2sales.de).
- Instagram-/WhatsApp-Nachrichten werden nicht automatisch übernommen („noch nicht verbunden“); solche Leads manuell anlegen.
