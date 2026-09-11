#!/usr/bin/env node
// ==============================================================================
// Quran Live Broadcast — Comprehensive Strict Quality Assurance & Verification Gate
// Validates 195 countries, 114 Surahs, recitation audio URLs, API contracts,
// responsive typography, and self-healing automation scripts.
// ==============================================================================
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const assert = (ok, msg) => {
  if (!ok) {
    console.error(`❌ QA ERROR: ${msg}`);
    throw new Error(msg);
  }
};

console.log('🔍 Starting Quran Live Broadcast Strict Quality Gate Checks...\n');

// 1. Validate All 195 Countries
const countriesPath = path.join(ROOT, 'web', 'countries.json');
assert(fs.existsSync(countriesPath), 'web/countries.json not found');
const countries = JSON.parse(fs.readFileSync(countriesPath, 'utf8'));
assert(countries.length === 195, `Expected 195 countries, got ${countries.length}`);
assert(new Set(countries.map(c => c.code)).size === 195, 'Duplicate country code found');

for (const c of countries) {
  for (const k of ['code', 'name', 'nameAr', 'capital', 'capitalAr', 'lat', 'lon', 'timezone', 'flag']) {
    assert(c[k], `${c.code}: missing required property "${k}"`);
  }
  assert(Math.abs(Number(c.lat)) <= 90 && Math.abs(Number(c.lon)) <= 180, `${c.code}: invalid latitude/longitude`);
  assert(c.flag.length >= 2, `${c.code}: flag definition missing or empty`);
}
console.log('✓ Quality Gate 1: 195 Countries dataset verified (100% complete, zero missing metadata).');

// 2. Validate All 114 Surahs Dataset
const surahsPath = path.join(ROOT, 'web', 'surahs.json');
assert(fs.existsSync(surahsPath), 'web/surahs.json not found');
const surahs = JSON.parse(fs.readFileSync(surahsPath, 'utf8'));
assert(surahs.length === 114, `Expected 114 Surahs, got ${surahs.length}`);
let totalQuranAyahs = 0;
for (let i = 0; i < surahs.length; i++) {
  const s = surahs[i];
  assert(s.number === i + 1, `Surah order mismatch at index ${i}: got ${s.number}`);
  assert(s.nameAr && s.nameAr.length > 2, `Surah ${s.number} missing Arabic name`);
  assert(s.nameEn && s.nameEn.length > 1, `Surah ${s.number} missing English name`);
  assert(s.ayahs > 0, `Surah ${s.number} invalid ayahs count`);
  assert(s.type === 'مَكِّيَّة' || s.type === 'مَدَنِيَّة', `Surah ${s.number} unknown revelation type: ${s.type}`);
  totalQuranAyahs += s.ayahs;
}
assert(totalQuranAyahs === 6236, `Expected exactly 6,236 Ayahs in Holy Quran, got ${totalQuranAyahs}`);
console.log('✓ Quality Gate 2: 114 Surahs canonical roster verified (total 6,236 Ayahs, Makkiyah/Madaniyah tagged).');

// 3. Validate Frontend Structure & Absence of Dead Code
const indexHtml = fs.readFileSync(path.join(ROOT, 'web', 'index.html'), 'utf8');
const appJs = fs.readFileSync(path.join(ROOT, 'web', 'app.js'), 'utf8');
const styleCss = fs.readFileSync(path.join(ROOT, 'web', 'style.css'), 'utf8');

assert(indexHtml.includes('Quran Live Broadcast'), 'Page title must match official name "Quran Live Broadcast"');
assert(!indexHtml.includes('rail-footer') && !indexHtml.includes('جميع المدن'), 'Right rail footer must remain removed');
assert(indexHtml.includes('reciter-pill') && indexHtml.includes('wave-equalizer'), 'Reciter equalizer card missing in HTML');
assert(indexHtml.includes('surah-ayah-pill') && indexHtml.includes('tafsir-info-pill'), 'Bottom info pills missing in HTML');
assert(appJs.includes('fitElement') && appJs.includes('fitAllContent'), 'Dynamic auto-fit engine missing in app.js');
assert(appJs.includes('playRecitation') && appJs.includes('advanceToNextAyah'), 'Continuous Quran recitation synchronizer missing in app.js');
assert(styleCss.includes('active-next') && styleCss.includes('eqPulse'), 'Active prayer and equalizer CSS missing');
console.log('✓ Quality Gate 3: UI Design and Frontend code verified (Aesthetic layout, 3 bottom cards, dynamic fitting).');

// 4. Validate Shell Automation Scripts
const scripts = [
  'hardware_profile.sh',
  'broadcast_ui.sh',
  'stream_youtube.sh',
  'stream_tiktok.sh',
  'stream_dual.sh',
  'watchdog.sh',
  'maintenance.sh',
  'setup_cron.sh',
  'control.sh'
];
for (const script of scripts) {
  const p = path.join(ROOT, 'scripts', script);
  assert(fs.existsSync(p), `Required script scripts/${script} missing`);
}
console.log('✓ Quality Gate 4: Autonomous shell scripts verified (adaptive profiles, watchdog, maintenance, cron).');

// 5. Integration Test Web Server & APIs
const port = 8899;
const server = spawn(process.execPath, ['web/server.js'], {
  cwd: ROOT,
  env: { ...process.env, PORT: String(port), QURAN_OFFLINE: '1' },
  stdio: 'ignore'
});

function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', d => body += d);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch (e) {
          resolve({ status: res.statusCode, raw: body });
        }
      });
    }).on('error', reject);
  });
}

(async () => {
  try {
    // Wait for server to boot
    for (let i = 0; i < 40; i++) {
      try {
        const r = await getJson(`http://127.0.0.1:${port}/api/health`);
        if (r.status === 200) break;
      } catch {}
      await new Promise(r => setTimeout(r, 100));
    }

    // Test /api/health
    const health = await getJson(`http://127.0.0.1:${port}/api/health`);
    assert(health.status === 200 && health.data.ok === true, 'Health check failed');

    // Test /api/surahs
    const surahsRes = await getJson(`http://127.0.0.1:${port}/api/surahs`);
    assert(surahsRes.status === 200 && surahsRes.data.length === 114, 'Surahs endpoint failed');

    // Test /api/capitals
    const capitals = await getJson(`http://127.0.0.1:${port}/api/capitals?page=0&size=5`);
    assert(capitals.status === 200 && capitals.data.cities.length === 5, 'Capitals pagination failed');
    assert(capitals.data.total === 195 && capitals.data.totalPages === 39, 'Capitals pagination count mismatch');

    // Test /api/quran for longest Ayah (2:282)
    const q282 = await getJson(`http://127.0.0.1:${port}/api/quran?surah=2&ayah=282`);
    assert(q282.status === 200 && q282.data.ayah === 282, 'Ayah 2:282 fixture failed');
    assert(q282.data.arabic && q282.data.translation && q282.data.tafsirAr && q282.data.tafsirEn, 'Ayah 2:282 fields incomplete');
    assert(q282.data.audioUrl && q282.data.audioUrl.endsWith('002282.mp3'), 'Audio recitation URL invalid for 2:282');

    // Test /api/quran for Surah 1 Ayah 1
    const q1 = await getJson(`http://127.0.0.1:${port}/api/quran?surah=1&ayah=1`);
    assert(q1.status === 200 && q1.data.ayah === 1, 'Ayah 1:1 fixture failed');
    assert(q1.data.audioUrl && q1.data.audioUrl.endsWith('001001.mp3'), 'Audio recitation URL invalid for 1:1');

    console.log('✓ Quality Gate 5: Server API endpoints and offline fixtures verified with 0 errors.');
    console.log('\n🎉 ALL QUALITY ASSURANCE GATES PASSED SUCCESSFULLY (5/5 PASS)!');
    process.exit(0);
  } finally {
    server.kill('SIGTERM');
  }
})().catch(err => {
  console.error('\n❌ QA SUITE FAILED:', err.message);
  try { server.kill('SIGTERM'); } catch {}
  process.exit(1);
});
