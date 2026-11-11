# PHD Inventory Manager — single file, with login

**`index.html` is the whole app**: cover page → login → dashboard, all in one file.
Click *Enter Dashboard* → you land on the login screen → sign in → you're taken to your unit's dashboard.
Logout returns to the login screen.

The file holds no inventory records. All data lives in Supabase, and **the database itself** (Row Level Security)
decides which unit's rows each login can read or change — so keeping everything in one file does not weaken the separation.

| Sign-in | Password (initial) | Unit |
|---|---|---|
| `IT_Admin` | `Password12345` | IT Unit |
| `HR_Admin` | `Admin12345` | Admin Unit |

> Both passwords are weak. Fine to start; **set stronger ones before go-live** (step 3).

## Setup (about 30 minutes)
1. **Supabase project** → supabase.com. Copy the *Project URL* and the *anon / publishable key* (Project Settings → API).
   Also note the *secret / service_role key* — keep it private. Then Authentication → Sign In / Providers → Email →
   turn **off "Allow new users to sign up"**. Authentication → URL Configuration → Site URL = `https://inventory.phdnigeria.com`.
2. **Database** → SQL Editor → run `supabase/01_schema.sql`, then `supabase/02_seed.sql` (loads your existing records,
   each into its own unit). Optional: `supabase/03_isolation_test.sql` (26 checks, rolls back).
3. **Accounts** → on your computer (Node 18+):

       SUPABASE_URL=https://YOURREF.supabase.co SUPABASE_SECRET_KEY=<secret key> \
       IT_PASSWORD='strong-one' HR_PASSWORD='another-strong-one' node scripts/create-users.mjs

   (No Node? Create the two users in Authentication → Users — `it_admin@inventory.phdnigeria.com`,
   `hr_admin@inventory.phdnigeria.com`, tick *Auto Confirm* — then in the SQL Editor:
   `update auth.users set raw_app_meta_data = raw_app_meta_data || '{"unit":"it"}' where email='it_admin@inventory.phdnigeria.com';`
   and `'{"unit":"admin"}'` for `hr_admin@…`.)
4. **Configure the file** → open `index.html` in a text editor; at the very top, replace the two values in `PHD_CONFIG`
   (URL + anon key; safe to commit). Never paste the secret key here.
5. **GitHub** → create a **private** repo, push this folder (`.gitignore` keeps `supabase/02_seed.sql` out — it contains
   staff names/emails). Settings → Pages → Deploy from branch → `main` / root; custom domain `inventory.phdnigeria.com`
   (the `CNAME` file is included); tick *Enforce HTTPS*. Pages from a private repo needs a paid GitHub plan.
6. **DNS** → add CNAME: host `inventory` → `<your-github-org>.github.io`.
7. **Check** → open the site, sign in as each user, confirm each sees only its own unit, then Logout.

## Behaviour & limits
* Until a verified session exists, none of the dashboard is displayed and no data is requested. Refreshing while signed in
  returns you to your dashboard; logout and expiry reload the page so nothing stays in memory.
* Session lives in the browser tab (closes with the tab); auto sign-out after 30 min idle. Logout ends this browser's session
  only, so colleagues sharing a login are not kicked out. Access tokens last 1 hour and refresh while the tab is open.
* Changes save automatically ("Saved" badge). If two people edit the same unit at once, the later save is refused and
  the screen reloads with the latest data.
* Free-tier Supabase projects pause after about a week idle — sign-in fails until un-paused. Use a paid plan for daily use.
* Supabase rate-limits sign-ins but has no per-account lockout; consider enabling CAPTCHA (Authentication → Attack Protection).
* GitHub Pages can't set security headers, so a Content-Security-Policy is set inside the file. The app still builds some
  screens from record text without escaping (as the original did) — treat bulk Excel uploads as trusted-source only.
* Shared logins mean history can't show which person made a change.
