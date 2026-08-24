const { connect } = require('./pg-client');
const fs = require('fs');
const REPO = process.env.PHASE86_REPO || require('path').resolve(__dirname, '../..');
const FILES = [
  '2026-08-20-phase86-legacy-entity-maps.sql',
  '2026-08-20-phase86-legacy-imports-job.sql',
  '2026-08-20-phase86-users-must-change-password.sql',
  '2026-08-20-phase86-legacy-alerts.sql',
  '2026-08-20-phase86-sales-source-legacy.sql',
  '2026-08-20-phase86-legacy-ingresos.sql',
  '2026-08-20-phase86-legacy-import-leases.sql',
];
(async () => {
  const c = await connect();
  if (process.argv[2] === 'bootstrap') {
    await c.query(fs.readFileSync(require('path').resolve(__dirname, 'bootstrap-schema.sql'), 'utf8'));
    console.log('bootstrap OK');
    await c.end(); return;
  }
  let fail = 0;
  for (const f of FILES) {
    const sql = fs.readFileSync(`${REPO}/api-ventago/migrations/${f}`, 'utf8');
    try {
      const r = await c.query(sql);
      const last = Array.isArray(r) ? r[r.length - 1] : r;
      console.log(`✔ ${f}`);
      if (last && last.rows && last.rows.length) console.log('   →', JSON.stringify(last.rows[0]));
    } catch (e) {
      fail++;
      console.log(`✘ ${f}\n   ${e.message}${e.position ? ' @pos ' + e.position : ''}`);
      try { await c.query('ROLLBACK'); } catch (_) {}
    }
  }
  console.log(fail ? `\nFAILED: ${fail}` : '\nALL MIGRATIONS OK');
  await c.end();
  process.exit(fail ? 1 : 0);
})();
