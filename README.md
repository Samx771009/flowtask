# Flowtask – kostenloses Cloud-Hosting

Diese Variante ist für ein kostenloses statisches Hosting mit Supabase als Cloud-Datenbank/Auth vorbereitet. Node.js wird für den Onlinebetrieb nicht benötigt.

## 1. Supabase
1. Erstelle ein kostenloses Supabase-Projekt.
2. Öffne SQL Editor und führe `schema.sql` komplett aus.
3. Kopiere Project URL und den `anon`/publishable Key aus den API-Einstellungen in `config.js`.
4. In Authentication > Providers muss E-Mail aktiviert sein. Wenn E-Mail-Bestätigung aktiviert ist, muss ein neuer Benutzer seine E-Mail zuerst bestätigen.

## 2. Lokal testen
Du kannst die `index.html` nicht zuverlässig per `file://` testen, weil Browser bei lokalen Dateien Module/Requests blockieren können. Nutze z.B. in diesem Ordner einen einfachen lokalen Server:

```cmd
npx serve .
```

oder lade die Datei direkt auf Render/GitHub Pages.

## 3. Online stellen
Am einfachsten: GitHub Repository erstellen, diese Dateien hochladen und auf Render als Static Site verbinden. Build Command leer lassen; Publish Directory `.`.

Wichtig: `config.js` enthält absichtlich nur den öffentlichen Supabase anon/publishable Key. Niemals den `service_role`/secret Key in den Browser oder ein öffentliches Repository stellen.
