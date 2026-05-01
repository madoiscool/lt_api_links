import { readFile } from 'node:fs/promises';
import path from 'node:path';

export default async function handler(req, res) {
  try {
    const scriptPath = path.join(process.cwd(), 'Devuvo.ps1');
    const script = await readFile(scriptPath, 'utf8');

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=60');
    res.status(200).send(script);
  } catch (error) {
    res.status(500).send('Failed to load Devuvo.ps1.');
  }
}
