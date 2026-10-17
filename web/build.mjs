import { copyFileSync, mkdirSync } from 'node:fs';
mkdirSync('dist', { recursive: true });
for (const file of ['index.html', 'app.css']) copyFileSync(`src/${file}`, `dist/${file}`);
