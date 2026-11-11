// Creates (or resets) the two sign-in accounts in Supabase Auth and stamps each with its unit.
// Run LOCALLY, once. The secret key is read from your environment and is never stored in the repo.
//
//   SUPABASE_URL=https://xxxx.supabase.co \
//   SUPABASE_SECRET_KEY=<service_role or sb_secret_... key> \
//   IT_PASSWORD='...' HR_PASSWORD='...' \
//   node scripts/create-users.mjs
//
// app_metadata.unit can only be written with this admin key — users cannot change it themselves.
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';
if (!URL_ || !KEY) { console.error('Set SUPABASE_URL and SUPABASE_SECRET_KEY (the service_role / secret key).'); process.exit(1); }
const USERS = [
  { email: 'it_admin@inventory.phdnigeria.com', unit: 'it',    password: process.env.IT_PASSWORD || 'Password12345' },
  { email: 'hr_admin@inventory.phdnigeria.com', unit: 'admin', password: process.env.HR_PASSWORD || 'Admin12345' },
];
const headers = { 'Content-Type': 'application/json', apikey: KEY, ...(KEY.startsWith('eyJ') ? { Authorization: `Bearer ${KEY}` } : {}) };
async function call(method, path, body) {
  const r = await fetch(URL_ + '/auth/v1/admin' + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text(); let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { status: r.status, json };
}
for (const u of USERS) {
  const payload = { email: u.email, password: u.password, email_confirm: true, app_metadata: { unit: u.unit } };
  let r = await call('POST', '/users', payload);
  if (r.status === 422 || /already/i.test(JSON.stringify(r.json))) {          // exists → find it and update
    let id; for (let page = 1; page < 20 && !id; page++) {
      const l = await call('GET', `/users?page=${page}&per_page=100`);
      id = (l.json.users || []).find((x) => x.email === u.email)?.id; if (!(l.json.users || []).length) break;
    }
    if (!id) { console.error('✗ could not find existing user', u.email); process.exit(1); }
    r = await call('PUT', `/users/${id}`, payload);
  }
  if (r.status >= 300) { console.error('✗', u.email, r.status, JSON.stringify(r.json)); process.exit(1); }
  console.log(`✓ ${u.email}  →  unit "${u.unit}"`);
}
console.log('\nDone. Passwords above are the ones you supplied (defaults if you did not). Change weak defaults before go-live.');
