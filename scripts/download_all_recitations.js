#!/usr/bin/env node
/**
 * Quran Live Stream - Offline Audio Downloader & Synchronizer
 * Downloads all 6,236 verse-by-verse recitation MP3 files (Mishary Alafasy 128kbps)
 * directly into web/assets/audio/ for 100% offline continuous playback.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const AUDIO_DIR = path.join(ROOT, 'web', 'assets', 'audio');
const SURAHS_FILE = path.join(ROOT, 'web', 'surahs.json');

if (!fs.existsSync(AUDIO_DIR)) {
  fs.mkdirSync(AUDIO_DIR, { recursive: true });
}

const surahs = JSON.parse(fs.readFileSync(SURAHS_FILE, 'utf8'));

function extractZip(zipPath, targetDir) {
  try {
    // Both modern Windows 10/11 and Linux include bsdtar / tar
    execSync(`tar -xf "${zipPath}" -C "${targetDir}"`, { stdio: 'ignore' });
    return true;
  } catch {
    try {
      if (process.platform === 'win32') {
        execSync(`powershell -Command "Expand-Archive -Path '${zipPath}' -DestinationPath '${targetDir}' -Force"`, { stdio: 'ignore' });
        return true;
      } else {
        execSync(`unzip -o "${zipPath}" -d "${targetDir}"`, { stdio: 'ignore' });
        return true;
      }
    } catch {
      return false;
    }
  }
}

async function downloadFile(url, destPath) {
  const res = await fetch(url, { headers: { 'User-Agent': 'QuranLiveStream/3.0' } });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const arrayBuf = await res.arrayBuffer();
  fs.writeFileSync(destPath, Buffer.from(arrayBuf));
}

function isSurahComplete(surahNum, ayahCount) {
  const s = String(surahNum).padStart(3, '0');
  for (let a = 1; a <= ayahCount; a++) {
    const fileName = `${s}${String(a).padStart(3, '0')}.mp3`;
    const p = path.join(AUDIO_DIR, fileName);
    if (!fs.existsSync(p) || fs.statSync(p).size < 1000) {
      return false;
    }
  }
  return true;
}

async function downloadSurah(surah) {
  const sPad = String(surah.number).padStart(3, '0');
  if (isSurahComplete(surah.number, surah.ayahs)) {
    console.log(`✓ Surah ${sPad} (${surah.nameAr}) already complete on disk (${surah.ayahs} ayahs).`);
    return true;
  }

  console.log(`⬇ Downloading Surah ${sPad} (${surah.nameAr}) [${surah.ayahs} ayahs]...`);
  const zipUrl = `https://everyayah.com/data/Alafasy_128kbps/zips/${sPad}.zip`;
  const zipFile = path.join(AUDIO_DIR, `${sPad}.zip`);

  try {
    await downloadFile(zipUrl, zipFile);
    const extracted = extractZip(zipFile, AUDIO_DIR);
    try { fs.unlinkSync(zipFile); } catch {}

    if (extracted && isSurahComplete(surah.number, surah.ayahs)) {
      console.log(`✓ Successfully extracted Surah ${sPad} (${surah.ayahs} ayahs).`);
      return true;
    }
  } catch (err) {
    try { if (fs.existsSync(zipFile)) fs.unlinkSync(zipFile); } catch {}
  }

  // Fallback to individual verse download if zip is unavailable or failed
  console.log(`ℹ Fetching missing ayahs individually for Surah ${sPad}...`);
  for (let a = 1; a <= surah.ayahs; a++) {
    const aPad = String(a).padStart(3, '0');
    const fileName = `${sPad}${aPad}.mp3`;
    const dest = path.join(AUDIO_DIR, fileName);
    if (fs.existsSync(dest) && fs.statSync(dest).size > 1000) continue;

    const ayahUrl = `https://everyayah.com/data/Alafasy_128kbps/${fileName}`;
    try {
      await downloadFile(ayahUrl, dest);
    } catch (e) {
      console.warn(`! Failed to download ${fileName}: ${e.message}`);
    }
  }

  return isSurahComplete(surah.number, surah.ayahs);
}

async function main() {
  const args = process.argv.slice(2);
  const singleSurahArg = args.find(a => a.startsWith('--surah='));
  const limitArg = args.find(a => a.startsWith('--limit='));

  let targetSurahs = surahs;
  if (singleSurahArg) {
    const num = parseInt(singleSurahArg.split('=')[1], 10);
    targetSurahs = surahs.filter(s => s.number === num);
  } else if (limitArg) {
    const limit = parseInt(limitArg.split('=')[1], 10);
    targetSurahs = surahs.slice(0, limit);
  }

  console.log(`=== Quran Audio Downloader (Alafasy 128kbps) ===`);
  console.log(`Target: ${AUDIO_DIR}`);
  console.log(`Total Surahs to process: ${targetSurahs.length}`);

  let completedCount = 0;
  for (let i = 0; i < targetSurahs.length; i++) {
    const s = targetSurahs[i];
    await downloadSurah(s);
    completedCount++;
    const percent = ((completedCount / targetSurahs.length) * 100).toFixed(1);
    console.log(`Progress: ${completedCount}/${targetSurahs.length} surahs (${percent}%)`);
  }

  const allFiles = fs.readdirSync(AUDIO_DIR).filter(f => f.endsWith('.mp3'));
  console.log(`\n=== Download Finished ===`);
  console.log(`Total MP3 audio files on disk: ${allFiles.length}/6236`);
}

if (require.main === module) {
  main().catch(err => {
    console.error('Fatal download error:', err);
    process.exit(1);
  });
}

module.exports = { downloadSurah, isSurahComplete, AUDIO_DIR };
