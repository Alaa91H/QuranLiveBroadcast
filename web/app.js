// Quran Live Stream - Controller & Recitation Synchronizer
const state = {
  page: 0,
  perPage: 6,
  totalPages: 33,
  rotationSeconds: 35,
  rotationLeft: 35,
  cityData: [],
  surahs: [],
  currentSurah: 1,
  currentAyah: 1,
  quran: null,
  audio: null,
  isPlaying: false,
  fallbackTimer: null,
  isQa: new URLSearchParams(location.search).get('qa') === '1' || new URLSearchParams(location.search).get('test') === 'longest'
};

const $ = id => document.getElementById(id);

// Reference cities data with max/min temps, Hijri & Gregorian dates, and 6 prayer times
const defaultCities = [
  {
    code: 'SA',
    nameAr: 'المملكة العربية السعودية',
    capitalAr: 'مكة المكرمة',
    flag: '/assets/flag_sa.png',
    landmark: '/assets/makkah.jpg',
    timezone: 'Asia/Riyadh',
    weather: { temp: '32°C', icon: '☀️', desc: 'مشمس', max: '36°', min: '24°' },
    isMakkah: true,
    dateHijri: '12 شعبان 1447 هـ',
    dateGreg: '26 فبراير 2025 م',
    prayers: [
      { name: 'الفجر', time: '4:36' },
      { name: 'الشروق', time: '5:58' },
      { name: 'الظهر', time: '12:27' },
      { name: 'العصر', time: '3:51', next: true },
      { name: 'المغرب', time: '6:15' },
      { name: 'العشاء', time: '7:45' }
    ]
  },
  {
    code: 'TR',
    nameAr: 'تركيا',
    capitalAr: 'إسطنبول',
    flag: '/assets/flag_tr.png',
    landmark: '/assets/istanbul.jpg',
    timezone: 'Europe/Istanbul',
    weather: { temp: '18°C', icon: '⛅', max: '21°', min: '14°' },
    timeDisplay: '9:15 AM',
    dateHijri: '12 شعبان 1447 هـ',
    dateGreg: '26 فبراير 2025 م',
    prayers: [
      { name: 'الفجر', time: '5:55' },
      { name: 'الشروق', time: '7:18' },
      { name: 'الظهر', time: '12:49' },
      { name: 'العصر', time: '4:18', next: true },
      { name: 'المغرب', time: '7:32' },
      { name: 'العشاء', time: '9:03' }
    ]
  },
  {
    code: 'EG',
    nameAr: 'مصر',
    capitalAr: 'القاهرة',
    flag: '/assets/flag_eg.png',
    landmark: '/assets/cairo.jpg',
    timezone: 'Africa/Cairo',
    weather: { temp: '28°C', icon: '☀️', max: '31°', min: '22°' },
    timeDisplay: '8:15 AM',
    dateHijri: '12 شعبان 1447 هـ',
    dateGreg: '26 فبراير 2025 م',
    prayers: [
      { name: 'الفجر', time: '4:12' },
      { name: 'الشروق', time: '5:54' },
      { name: 'الظهر', time: '12:06' },
      { name: 'العصر', time: '3:42', next: true },
      { name: 'المغرب', time: '6:19' },
      { name: 'العشاء', time: '7:48' }
    ]
  },
  {
    code: 'GB',
    nameAr: 'المملكة المتحدة',
    capitalAr: 'لندن',
    flag: '/assets/flag_gb.png',
    landmark: '/assets/london.jpg',
    timezone: 'Europe/London',
    weather: { temp: '12°C', icon: '☁️', max: '16°', min: '9°' },
    timeDisplay: '8:15 AM',
    dateHijri: '12 شعبان 1447 هـ',
    dateGreg: '26 فبراير 2025 م',
    prayers: [
      { name: 'الفجر', time: '6:12' },
      { name: 'الشروق', time: '7:45' },
      { name: 'الظهر', time: '12:58' },
      { name: 'العصر', time: '3:43', next: true },
      { name: 'المغرب', time: '6:52' },
      { name: 'العشاء', time: '8:37' }
    ]
  },
  {
    code: 'US',
    nameAr: 'الولايات المتحدة الأمريكية',
    capitalAr: 'نيويورك',
    flag: '/assets/flag_us.png',
    landmark: '/assets/newyork.jpg',
    timezone: 'America/New_York',
    weather: { temp: '20°C', icon: '☀️', max: '23°', min: '16°' },
    timeDisplay: '3:15 AM',
    dateHijri: '12 شعبان 1447 هـ',
    dateGreg: '26 فبراير 2025 م',
    prayers: [
      { name: 'الفجر', time: '5:24' },
      { name: 'الشروق', time: '6:58' },
      { name: 'الظهر', time: '1:26' },
      { name: 'العصر', time: '5:12', next: true },
      { name: 'المغرب', time: '8:58' },
      { name: 'العشاء', time: '10:37' }
    ]
  },
  {
    code: 'PS',
    nameAr: 'فلسطين',
    capitalAr: 'القدس الشريف',
    flag: '/assets/flags/ps.png',
    landmark: '/assets/makkah.jpg',
    timezone: 'Asia/Jerusalem',
    weather: { temp: '22°C', icon: '☀️', max: '26°', min: '17°' },
    timeDisplay: '8:15 AM',
    dateHijri: '12 شعبان 1447 هـ',
    dateGreg: '26 فبراير 2025 م',
    prayers: [
      { name: 'الفجر', time: '4:45' },
      { name: 'الشروق', time: '6:08' },
      { name: 'الظهر', time: '12:35' },
      { name: 'العصر', time: '4:02', next: true },
      { name: 'المغرب', time: '6:42' },
      { name: 'العشاء', time: '8:05' }
    ]
  }
];

const prayerNamesList = [
  ['Fajr', 'الفجر'],
  ['Sunrise', 'الشروق'],
  ['Dhuhr', 'الظهر'],
  ['Asr', 'العصر'],
  ['Maghrib', 'المغرب'],
  ['Isha', 'العشاء']
];

// BMP text glyphs ONLY (no VS16 emoji): headless servers lack color-emoji
// fonts, which rendered tofu boxes. DejaVu Sans covers this whole set.
const weatherGlyphs = {
  0: '☀', 1: '☀', 2: '☁', 3: '☁', 45: '☁', 48: '☁',
  51: '☂', 53: '☂', 55: '☔', 61: '☂', 63: '☔', 65: '☔',
  71: '❄', 73: '❄', 75: '❄', 80: '☂', 81: '☔', 82: '☔',
  95: '⚡'
};

function formatPrayerTime(t) {
  const m = String(t || '').match(/(\d{1,2}):(\d{2})/);
  if (!m) return '--:--';
  const d = new Date(2000, 0, 1, Number(m[1]), Number(m[2]));
  return new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }).format(d);
}

function parseMinutes(t) {
  const m = String(t || '').match(/^(\d{1,2}):(\d{2})/);
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

function getLocalMinutes(tz) {
  try {
    const p = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: false, timeZone: tz || 'UTC' }).formatToParts(new Date());
    return Number(p.find(x => x.type === 'hour')?.value || 0) * 60 + Number(p.find(x => x.type === 'minute')?.value || 0);
  } catch {
    return 0;
  }
}

function getNextPrayerKey(timings, tz) {
  const now = getLocalMinutes(tz);
  const ordered = prayerNamesList.map(([key]) => ({ key, mins: parseMinutes(timings?.[key]) })).filter(x => x.mins != null);
  const found = ordered.find(x => x.mins > now);
  return (found || ordered[0] || { key: 'Asr' }).key;
}

function getCityDates(tz) {
  try {
    const d = new Date();
    const greg = new Intl.DateTimeFormat('ar', { day: 'numeric', month: 'long', year: 'numeric', timeZone: tz || 'UTC' }).format(d);
    let hijri = new Intl.DateTimeFormat('ar-SA-u-ca-islamic-umalqura', { day: 'numeric', month: 'long', year: 'numeric', timeZone: tz || 'UTC' }).format(d);
    hijri = hijri.replace(/\s*هـ?\s*$/g, '').trim() + ' هـ';
    return { greg, hijri };
  } catch {
    return { greg: '26 فبراير 2025 م', hijri: '12 شعبان 1447 هـ' };
  }
}

function formatClockTime(tz) {
  try {
    return new Intl.DateTimeFormat('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
      timeZone: tz || 'UTC'
    }).format(new Date());
  } catch {
    return '--:--';
  }
}

function getCityDayName(tz) {
  try {
    return new Intl.DateTimeFormat('ar-SA', { weekday: 'long', timeZone: tz || 'UTC' }).format(new Date());
  } catch {
    return 'الجمعة';
  }
}

// Next-prayer countdown target (epoch ms) from a "h:MM AM/PM" time + timezone.
// Wall-clock -> epoch via the locale-string offset trick (DST-safe). 0 = unknown.
function nextPrayerTs(timeStr, tz) {
  try {
    const m = String(timeStr || '').match(/(\d{1,2}):(\d{2})\s*(AM|PM)?/i);
    if (!m) return 0;
    let h = Number(m[1]) % 12;
    if (/pm/i.test(m[3] || '')) h += 12;
    const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: tz || 'UTC', year: 'numeric', month: '2-digit', day: '2-digit' });
    const parts = fmt.format(new Date()).split('-').map(Number);
    const guess = Date.UTC(parts[0], parts[1] - 1, parts[2], h, Number(m[2]), 0);
    const tzWall = new Date(new Date(guess).toLocaleString('en-US', { timeZone: tz || 'UTC' })).getTime();
    const utcWall = new Date(new Date(guess).toLocaleString('en-US')).getTime();
    let target = guess + (utcWall - tzWall);
    if (target <= Date.now()) target += 86400000;
    return target;
  } catch {
    return 0;
  }
}

function renderCityCard(c) {
  const timings = c.prayer?.timings || null;
  const nextKey = timings ? getNextPrayerKey(timings, c.timezone) : (c.prayers?.find(x => x.next)?.name === 'العصر' ? 'Asr' : 'Asr');
  const dates = (c.dateHijri && c.dateGreg) ? { hijri: c.dateHijri, greg: c.dateGreg } : getCityDates(c.timezone);
  const dayName = getCityDayName(c.timezone);
  
  const tempVal = c.weather?.temp || (c.weather?.temperature_2m != null ? `${Math.round(c.weather.temperature_2m)}°C` : '24°C');
  const tempMax = c.weather?.max || (c.weather?.temperature_2m_max != null ? `${Math.round(c.weather.temperature_2m_max)}°` : '28°');
  const tempMin = c.weather?.min || (c.weather?.temperature_2m_min != null ? `${Math.round(c.weather.temperature_2m_min)}°` : '18°');
  const icon = c.weather?.icon || weatherGlyphs[c.weather?.weather_code] || '☀️';
  
  const landmark = c.landmark || '/assets/makkah.jpg';
  const flagSrc = (c.code && c.code.length === 2)
    ? `/assets/flags/${c.code.toLowerCase()}.png`
    : (c.flag?.startsWith('/') ? c.flag : '/assets/flag_sa.png');
  const flagEmoji = c.flag && !c.flag.startsWith('/') ? c.flag : '🏳️';

  let prayersList = [];
  if (c.prayers) {
    prayersList = c.prayers;
  } else if (timings) {
    prayersList = prayerNamesList.map(([key, label]) => ({
      name: label,
      time: formatPrayerTime(timings[key]),
      next: key === nextKey
    }));
  } else {
    prayersList = prayerNamesList.map(([, label]) => ({ name: label, time: '--:--', next: label === 'العصر' }));
  }

  // Active prayer is highlighted with golden border, NO text label "الوقت القادم"
  const prayersHtml = prayersList.map(p => `
    <div class="p-col ${p.next ? 'active-next' : ''}">
      <span class="p-name">${p.name}</span>
      <span class="p-time">${p.time}</span>
    </div>
  `).join('');
  const nextPrayer = prayersList.find(p => p.next);
  const nextTs = nextPrayerTs(nextPrayer ? nextPrayer.time : '', c.timezone);

  const timeDisplay = c.timeDisplay || formatClockTime(c.timezone);

  return `
    <article class="city-card" data-code="${c.code || ''}">
      <div class="city-card-bg" style="background-image: url('${landmark}')"></div>
      
      <div class="subcards-row">
        <!-- 1. Day & Time Subcard (Far Right in RTL) + next-prayer countdown -->
        <div class="meta-subcard time-day-subcard">
          <span class="sc-day" data-day-tz="${c.timezone || ''}">${dayName}</span>
          <strong class="sc-time" data-tz="${c.timezone || ''}">${timeDisplay}</strong>
          <span class="sc-count" data-next-ts="${nextTs || ''}"></span>
        </div>

        <!-- 2. Hijri & Gregorian Dates Subcard -->
        <div class="meta-subcard dates-subcard">
          <span class="sc-hijri">${dates.hijri}</span>
          <span class="sc-greg">${dates.greg}</span>
        </div>

        <!-- 3. Weather Subcard: High/Low stacked on right, Temp & Icon on left -->
        <div class="meta-subcard weather-subcard">
          <div class="sc-hilo-stack">
            <span class="sc-hi">${tempMax}</span>
            <span class="sc-lo">${tempMin}</span>
          </div>
          <div class="sc-temp-group">
            <span class="sc-wx-icon">${icon}</span>
            <strong class="sc-temp-val">${tempVal}</strong>
          </div>
        </div>

        <!-- 4. Flag & City/Country Identity Subcard (names RIGHT, flag LEFT in RTL) -->
        <div class="meta-subcard identity-subcard">
          <div class="city-name-col">
            <h3 class="city-name">${c.capitalAr || c.capital || ''}</h3>
            <span class="city-country">${c.nameAr || c.name || ''}</span>
          </div>
          <div class="city-flag-box" title="${c.nameAr || c.name || ''}">
            <img src="${flagSrc}" alt="${c.code || ''}" class="city-flag-img" onerror="this.style.display='none'; if(this.nextElementSibling) this.nextElementSibling.style.display='flex';">
            <span class="city-flag-emoji" style="display:none;">${flagEmoji}</span>
          </div>
        </div>
      </div>

      <div class="prayer-times-row">
        ${prayersHtml}
      </div>
    </article>
  `;
}

function renderCities(cities) {
  const container = $('city-cards-container');
  if (!container) return;
  container.innerHTML = cities.map(renderCityCard).join('');
  // Single-line names: shrink-to-fit so every name shows FULLY on one line
  container.querySelectorAll('.city-name, .city-country').forEach(fitTextWidth);
}

// Width auto-fit: reduces font until the text fits ONE line (never overflows,
// never truncates). Range derived from the CSS size down to a 9px floor.
function fitTextWidth(el, minPx = 9, step = 0.5) {
  if (!el) return;
  let size = parseFloat(getComputedStyle(el).fontSize) || 14;
  let guard = 0;
  el.style.whiteSpace = 'nowrap';
  while (guard++ < 40 && size > minPx && el.scrollWidth > el.clientWidth + 1) {
    size -= step;
    el.style.fontSize = `${size}px`;
  }
}

// Dynamic Auto-Fit Algorithm: prevents overflow, clipping, or overlaps on any screen resolution or long verses
function fitElement(el, minPx, maxPx, step = 1) {
  if (!el) return;
  let size = maxPx;
  el.style.fontSize = `${size}px`;
  let guard = 0;
  while (guard++ < 50 && size > minPx && el.scrollHeight > el.clientHeight + 1) {
    size -= step;
    el.style.fontSize = `${size}px`;
  }
}

function fitAllContent() {
  const ayahEl = $('ayah-ar');
  const trEl = $('ayah-en');
  const tafArEl = $('tafsir-ar');
  const tafEnEl = $('tafsir-en');
  if (!ayahEl) return;

  const q = state.quran;
  const arLen = (q?.arabic || ayahEl.textContent || '').trim().length;
  const trLen = (q?.translation || trEl?.textContent || '').trim().length;
  const tafArLen = (q?.tafsirAr || tafArEl?.textContent || '').trim().length;
  const tafEnLen = (q?.tafsirEn || tafEnEl?.textContent || '').trim().length;

  // Dynamic typography range based on text volume
  let ayahMax = 58, ayahMin = 22;
  if (arLen < 70) { ayahMax = 62; ayahMin = 46; }
  else if (arLen < 180) { ayahMax = 52; ayahMin = 34; }
  else if (arLen < 380) { ayahMax = 40; ayahMin = 26; }
  else { ayahMax = 26; ayahMin = 17; } // Longest verse 2:282

  let trMax = 23, trMin = 14;
  if (trLen < 120) { trMax = 25; trMin = 19; }
  else if (trLen < 320) { trMax = 21; trMin = 15; }
  else { trMax = 17; trMin = 12.5; }

  let tafArMax = 19, tafArMin = 13;
  if (tafArLen < 160) { tafArMax = 21; tafArMin = 16; }
  else if (tafArLen < 380) { tafArMax = 18.5; tafArMin = 14; }
  else { tafArMax = 14.5; tafArMin = 11.5; }

  let tafEnMax = 17.5, tafEnMin = 12;
  if (tafEnLen < 160) { tafEnMax = 19.5; tafEnMin = 15; }
  else if (tafEnLen < 380) { tafEnMax = 17; tafEnMin = 13; }
  else { tafEnMax = 13.5; tafEnMin = 11; }

  fitElement(ayahEl, ayahMin, ayahMax, 1);
  fitElement(trEl, trMin, trMax, 0.5);
  fitElement(tafArEl, tafArMin, tafArMax, 0.5);
  fitElement(tafEnEl, tafEnMin, tafEnMax, 0.5);
}

// 24-hour persistent storage check
function getStoredCache(key) {
  try {
    const raw = localStorage.getItem('quranls_' + key);
    if (!raw) return null;
    const item = JSON.parse(raw);
    if (Date.now() - item.time < 24 * 60 * 60 * 1000) {
      return item.data;
    }
  } catch {}
  return null;
}

function setStoredCache(key, data) {
  try {
    localStorage.setItem('quranls_' + key, JSON.stringify({ time: Date.now(), data }));
  } catch {}
}

async function loadCapitalsPage() {
  try {
    // v2: roster order changed (Arab/Islamic first) — old cached pages ignored
    const cacheKey = `capitals_v2_p${state.page}`;
    let data = getStoredCache(cacheKey);

    if (!data) {
      const r = await fetch(`/api/capitals?page=${state.page}&size=${state.perPage}`, { cache: 'default' });
      if (r.ok) {
        data = await r.json();
        setStoredCache(cacheKey, data);
      }
    }

    if (data && data.cities && data.cities.length > 0) {
      state.cityData = data.cities;
      state.totalPages = data.totalPages || 39;
      renderCities(state.cityData);
    } else {
      renderCities(defaultCities);
    }
  } catch {
    renderCities(defaultCities);
  }
}

async function loadSurahs() {
  try {
    const cached = getStoredCache('surahs_list');
    if (cached && Array.isArray(cached) && cached.length === 114) {
      state.surahs = cached;
      return;
    }
    const r = await fetch('/api/surahs');
    if (r.ok) {
      state.surahs = await r.json();
      setStoredCache('surahs_list', state.surahs);
    }
  } catch {}
}

function getAudioUrl(surah, ayah) {
  const s = String(surah).padStart(3, '0');
  const a = String(ayah).padStart(3, '0');
  const cached = getStoredCache(`quran_s${surah}_a${ayah}`);
  if (cached && cached.audioUrl) return cached.audioUrl;
  return `/assets/audio/${s}${a}.mp3`;
}

function initAudio() {
  if (state.audio) return state.audio;
  const a = document.getElementById('quran-audio') || new Audio();
  a.preload = 'auto';
  a.autoplay = true;
  a.muted = false;
  a.volume = 1.0;

  a.addEventListener('play', () => {
    state.isPlaying = true;
    const pill = document.querySelector('.reciter-pill');
    if (pill) {
      pill.classList.remove('paused');
      pill.classList.add('playing');
    }
  });

  a.addEventListener('pause', () => {
    state.isPlaying = false;
    const pill = document.querySelector('.reciter-pill');
    if (pill) {
      pill.classList.remove('playing');
      pill.classList.add('paused');
    }
  });

  a.addEventListener('ended', () => {
    onAyahFinished();
  });

  a.addEventListener('error', e => {
    // Seamless fallback to EveryAyah CDN if local file is not yet cached
    if (a.src && a.src.includes('/assets/audio/')) {
      const match = a.src.match(/(\d{6})\.mp3/);
      if (match) {
        a.src = `https://everyayah.com/data/Alafasy_128kbps/${match[1]}.mp3`;
        a.play().catch(() => {});
        return;
      }
    }
    console.warn('Audio recitation load notice, advancing via fallback:', e);
    scheduleFallbackAdvance(3500);
  });

  state.audio = a;
  return a;
}

function scheduleFallbackAdvance(ms = 12000) {
  if (state.fallbackTimer) clearTimeout(state.fallbackTimer);
  state.fallbackTimer = setTimeout(() => {
    onAyahFinished();
  }, ms);
}

function onAyahFinished() {
  if (state.fallbackTimer) {
    clearTimeout(state.fallbackTimer);
    state.fallbackTimer = null;
  }

  // In QA test mode, keep verse static
  if (state.isQa) return;

  advanceToNextAyah();
}

function advanceToNextAyah() {
  const surahMeta = state.surahs.find(s => s.number === state.currentSurah);
  const maxAyahs = surahMeta ? surahMeta.ayahs : (state.quran?.totalAyahs || 286);

  if (state.currentAyah < maxAyahs) {
    state.currentAyah++;
  } else {
    if (state.currentSurah < 114) {
      state.currentSurah++;
      state.currentAyah = 1;
    } else {
      // Loop complete Quran continuously 24/7 (1:1 to 114:6)
      state.currentSurah = 1;
      state.currentAyah = 1;
    }
  }

  setStoredCache('current_position', { surah: state.currentSurah, ayah: state.currentAyah });
  loadQuranVerse(state.currentSurah, state.currentAyah);
}

function playRecitation(q) {
  if (state.isQa) return;
  const audio = initAudio();
  const audioUrl = q.audioUrl || getAudioUrl(q.surah, q.ayah);

  if (state.fallbackTimer) {
    clearTimeout(state.fallbackTimer);
    state.fallbackTimer = null;
  }

  // Safety fallback timer based on text length to prevent any broadcast hang
  const wordCount = (q.arabic || '').split(/\s+/).length;
  const estimatedSeconds = Math.max(7, Math.min(240, wordCount * 2.8 + 4));
  scheduleFallbackAdvance(estimatedSeconds * 1000);

  audio.src = audioUrl;
  audio.muted = false;
  audio.volume = 1.0;
  
  const playPromise = audio.play();
  if (playPromise !== undefined) {
    playPromise.then(() => {
      // Recitation audio playing smoothly
    }).catch(err => {
      console.warn('Autoplay waiting for unmuted policy:', err.message);
      audio.muted = false;
      audio.play().catch(() => {});
    });
  }
}

function preloadNextAyah(surah, ayah, count = 3) {
  let curS = surah;
  let curA = ayah;

  for (let step = 1; step <= count; step++) {
    const surahMeta = state.surahs.find(s => s.number === curS);
    const maxAyahs = surahMeta ? surahMeta.ayahs : (state.quran?.totalAyahs || 286);
    curA++;
    if (curA > maxAyahs) {
      curS = curS < 114 ? curS + 1 : 1;
      curA = 1;
    }

    const sTarget = curS;
    const aTarget = curA;
    const cacheKey = `quran_s${sTarget}_a${aTarget}`;

    // Pre-fetch API into cache
    if (!getStoredCache(cacheKey)) {
      fetch(`/api/quran?surah=${sTarget}&ayah=${aTarget}`, { cache: 'default' })
        .then(r => r.json())
        .then(data => {
          if (data) setStoredCache(cacheKey, data);
        })
        .catch(() => {});
    }

    // Pre-load audio track into browser buffer
    const nextAudio = new Audio();
    nextAudio.preload = 'auto';
    nextAudio.src = getAudioUrl(sTarget, aTarget);
  }
}

// Basmala standalone line: shown above ayah 1 of every surah except
// Al-Fatiha (the verse IS the basmala) and At-Tawbah (no basmala).
// If the API text starts with an inline basmala it is split off so the line
// never duplicates.
function updateBasmalaLine(arabic, surah, ayah) {
  const el = $('basmala-line');
  if (!el) return;
  let text = String(arabic || '');
  let show = (Number(surah) !== 1 && Number(surah) !== 9 && Number(ayah) === 1);
  if (show) {
    const m = text.match(/^([\s\S]{0,90}?(?:ٱ?لرَّحِيمِ|الرحيم))([\s\u06D6-\u06ED]*)([\s\S]*)$/);
    if (m && /بِسْمِ|بسم/.test(m[1]) && (m[3] || '').trim().length > 0) {
      text = m[3].trim();
      if ($('ayah-ar')) $('ayah-ar').textContent = text;
    }
  }
  el.style.display = show ? '' : 'none';
}

// Khatma progress: overall position across all 6236 ayahs (bar via scaleX =
// compositor-only, no layout cost)
function updateKhatmaProgress(surah, ayah) {
  try {
    const list = state.surahs;
    if (!Array.isArray(list) || list.length !== 114) return;
    const total = list.reduce((a, s) => a + (Number(s.ayahs) || 0), 0) || 6236;
    let cum = 0;
    for (const s of list) {
      if (Number(s.number) < Number(surah)) cum += Number(s.ayahs) || 0;
      else break;
    }
    cum += Number(ayah) || 0;
    const pct = Math.min(1, Math.max(0, cum / total));
    const fill = $('khatma-fill');
    if (fill) fill.style.transform = `scaleX(${pct})`;
    if ($('meta-surah-count')) $('meta-surah-count').textContent = `${surah}/114`;
  } catch {}
}

async function loadQuranVerse(surah, ayah) {
  if (!surah) surah = state.currentSurah;
  if (!ayah) ayah = state.currentAyah;

  // Verse crossfade: fade the block out (async fetch below yields a paint),
  // restored in `finally` for a 350ms fade-in (opacity-only, compositor cheap)
  const wrap = $('quran-content-wrapper');
  if (wrap) wrap.style.opacity = '0';
  if (!surah) surah = state.currentSurah;
  if (!ayah) ayah = state.currentAyah;

  try {
    const cacheKey = `quran_s${surah}_a${ayah}`;
    let q = getStoredCache(cacheKey);

    if (!q) {
      const r = await fetch(`/api/quran?surah=${surah}&ayah=${ayah}`, { cache: 'default' });
      if (r.ok) {
        q = await r.json();
        setStoredCache(cacheKey, q);
      }
    }

    if (q) {
      state.quran = q;
      state.currentSurah = q.surah || surah;
      state.currentAyah = q.ayah || ayah;

      if ($('ayah-ar')) {
        $('ayah-ar').textContent = q.arabic || '';
        const endMark = document.createElement('span');
        endMark.className = 'ayah-end';
        endMark.textContent = ' ۝';
        $('ayah-ar').appendChild(endMark);
      }
      if ($('ayah-en')) $('ayah-en').textContent = q.translation || '';
      if ($('tafsir-ar')) $('tafsir-ar').textContent = q.tafsirAr || '';
      if ($('tafsir-en')) $('tafsir-en').textContent = q.tafsirEn || '';
      updateBasmalaLine(q.arabic || '', q.surah || surah, q.ayah || ayah);
      
      // Update metadata in bottom cards
      if ($('meta-surah-title')) {
        const rev = q.revelationTypeAr || 'مَدَنِيَّة';
        const sName = q.surahArabic || 'سُورَةُ البَقَرَةِ';
        $('meta-surah-title').innerHTML = `${sName} <span class="surah-index">(${q.surah || surah})</span> <span class="revelation-tag">${rev}</span>`;
      }
      if ($('meta-ayah-num')) $('meta-ayah-num').textContent = q.ayah || ayah;
      if ($('meta-total-ayahs')) $('meta-total-ayahs').textContent = q.totalAyahs || 286;
      if ($('meta-tafsir')) $('meta-tafsir').textContent = `${q.tafsirNameAr || 'المُيَسَّر'} • ${q.tafsirNameEn || 'Al-Muyassar'}`;
      updateKhatmaProgress(q.surah || surah, q.ayah || ayah);

      // Synchronize audio recitation
      playRecitation(q);

      // Preload next 3 upcoming ayahs
      preloadNextAyah(state.currentSurah, state.currentAyah, 3);
    }
  } catch (e) {
    console.error('Quran verse load error', e);
    scheduleFallbackAdvance(10000);
  } finally {
    if (wrap) wrap.style.opacity = '1';
    requestAnimationFrame(fitAllContent);
  }
}

function tickClocks() {
  document.querySelectorAll('[data-tz]').forEach(el => {
    const tz = el.dataset.tz;
    if (tz) el.textContent = formatClockTime(tz);
  });
  // Next-prayer countdowns (1Hz, tabular fixed-width, no layout shift)
  document.querySelectorAll('[data-next-ts]').forEach(el => {
    const ts = Number(el.dataset.nextTs || 0);
    if (!ts) { el.textContent = ''; return; }
    const s = Math.floor((ts - Date.now()) / 1000);
    if (s <= 0) { el.textContent = 'الآن'; return; }
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    const t = (h > 0 ? h + ':' + String(m).padStart(2, '0') : String(m)) + ':' + String(ss).padStart(2, '0');
    el.textContent = `متبقي ${t}`;
  });
}

async function init() {
  // 1. Initial immediate render from pre-loaded reference data (zero layout shift)
  renderCities(defaultCities);

  // 2. Load Surahs canonical metadata (1-114)
  await loadSurahs();

  // 3. Determine starting surah & ayah
  const params = new URLSearchParams(location.search);
  const qSurah = parseInt(params.get('surah'), 10);
  const qAyah = parseInt(params.get('ayah'), 10);

  if (state.isQa) {
    state.currentSurah = 2;
    state.currentAyah = 282;
  } else if (qSurah && qAyah) {
    state.currentSurah = qSurah;
    state.currentAyah = qAyah;
  } else {
    const saved = getStoredCache('current_position');
    if (saved && saved.surah && saved.ayah) {
      state.currentSurah = saved.surah;
      state.currentAyah = saved.ayah;
    } else {
      state.currentSurah = 1;
      state.currentAyah = 1;
    }
  }

  // 4. Fetch dynamic data & start Quran verse
  // Clean recording mode (?clean=1): fullscreen Quran stage, side panel hidden
  if (params.get('clean') === '1') document.body.classList.add('clean');
  // Low-FX stream mode (?lowfx=1): kill decorative animations/transitions to
  // cut renderer CPU (clock tick + ayah changes still update, just unanimated)
  if (params.get('lowfx') === '1') document.body.classList.add('lowfx');
  // Slim city DOM (?cities=N): fewer rotating cards = smaller layout/paint cost
  const qCities = parseInt(params.get('cities'), 10);
  if (qCities > 0 && qCities <= 24) state.perPage = qCities;
  loadCapitalsPage();
  loadQuranVerse(state.currentSurah, state.currentAyah);

  // 5. Local clock ticks (no network request)
  setInterval(tickClocks, 1000);

  // 6. Smooth country rotation every 35 seconds (cycling all 195 countries)
  setInterval(() => {
    state.rotationLeft--;
    if (state.rotationLeft <= 0) {
      state.rotationLeft = state.rotationSeconds;
      state.page = (state.page + 1) % state.totalPages;
      loadCapitalsPage();
    }
  }, 1000);

  // 7. Dynamic auto-fit on window resize
  window.addEventListener('resize', () => requestAnimationFrame(fitAllContent), { passive: true });

  // 8. User click unpause handler (if browser required user gesture)
  window.addEventListener('click', () => {
    if (state.audio && state.audio.paused && !state.isQa) {
      state.audio.play().catch(() => {});
    }
  }, { passive: true });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
