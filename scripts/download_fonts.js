const fs = require('fs');
const path = require('path');

const FONTS_DIR = path.resolve(__dirname, '..', 'web', 'assets', 'fonts');
if (!fs.existsSync(FONTS_DIR)) {
  fs.mkdirSync(FONTS_DIR, { recursive: true });
}

async function fetchBuffer(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`);
  const arrayBuffer = await res.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function main() {
  console.log('Downloading Google Fonts for offline broadcast...');

  // User-agent that gets woff2
  const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  const cssUrl = 'https://fonts.googleapis.com/css2?family=Amiri:wght@400;700&family=Cairo:wght@400;600;700;800&display=swap';
  const res = await fetch(cssUrl, { headers: { 'User-Agent': ua } });
  const css = await res.text();

  // Find all @font-face blocks
  const blocks = css.split('@font-face').slice(1).map(b => '@font-face' + b);

  let localCss = '/* Offline Local Fonts for Quran Live Stream */\n';
  let fontIndex = 1;

  for (const block of blocks) {
    const familyMatch = block.match(/font-family:\s*'([^']+)'/);
    const weightMatch = block.match(/font-weight:\s*(\d+)/);
    const styleMatch = block.match(/font-style:\s*([a-z]+)/);
    const urlMatch = block.match(/url\((https:\/\/[^)]+\.woff2)\)/);
    const unicodeMatch = block.match(/unicode-range:\s*([^;]+);/);

    if (!familyMatch || !urlMatch) continue;

    const family = familyMatch[1];
    const weight = weightMatch ? weightMatch[1] : '400';
    const style = styleMatch ? styleMatch[1] : 'normal';
    const remoteUrl = urlMatch[1];
    const unicodeRange = unicodeMatch ? unicodeMatch[1].trim() : null;

    const safeFamily = family.toLowerCase().replace(/[^a-z0-9]/g, '');
    const fileName = `${safeFamily}-${weight}-${style}-${fontIndex++}.woff2`;
    const filePath = path.join(FONTS_DIR, fileName);

    console.log(`Downloading ${fileName} (${family} ${weight})...`);
    const fontData = await fetchBuffer(remoteUrl);
    fs.writeFileSync(filePath, fontData);

    localCss += `@font-face {\n  font-family: '${family}';\n  font-style: ${style};\n  font-weight: ${weight};\n  font-display: block;\n  src: url('/assets/fonts/${fileName}') format('woff2');\n`;
    if (unicodeRange) {
      localCss += `  unicode-range: ${unicodeRange};\n`;
    }
    localCss += `}\n\n`;
  }

  const cssOutPath = path.join(FONTS_DIR, 'fonts.css');
  fs.writeFileSync(cssOutPath, localCss, 'utf8');
  console.log(`✓ All fonts saved to ${FONTS_DIR}`);
  console.log(`✓ fonts.css generated (${(fs.statSync(cssOutPath).size)} bytes)`);
}

main().catch(err => {
  console.error('Font download error:', err);
  process.exit(1);
});
