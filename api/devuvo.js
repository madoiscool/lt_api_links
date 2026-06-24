import { readFile } from 'node:fs/promises';
import path from 'node:path';

export default async function handler(req, res) {
  try {
    const cwd = process.cwd();
    let script = await readFile(path.join(cwd, 'Devuvo.ps1'), 'utf8');

    // Inject the force-GBE app list (single source of truth: gbe.json) into the
    // $forceGbe array so the validator always matches the bot's /tokeer-gbe list
    // without editing the big script. Defensive: any failure here leaves the
    // script unchanged (never a 500) so validation can't be taken down by it.
    try {
      const raw = await readFile(path.join(cwd, 'gbe.json'), 'utf8');
      const parsed = JSON.parse(raw);
      const ids = (Array.isArray(parsed) ? parsed : (parsed.appids || []))
        .map((id) => String(id).replace(/[^0-9]/g, ''))
        .filter((id) => id.length > 0);
      const psArray = ids.map((id) => `    "${id}"`).join('\n');
      const replacement = `$forceGbe = @(\n${psArray}\n)`;
      // Replace the whole $forceGbe = @( ... ) block (appids never contain ')').
      // Anchor to start-of-line (m flag) so it hits the real assignment and NOT
      // the commented example line (#   $forceGbe = @("493340", "2688950")).
      script = script.replace(/^\$forceGbe\s*=\s*@\([^)]*\)/m, () => replacement);
    } catch (injectErr) {
      // leave the script unchanged if the list can't be read/parsed
    }

    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store, max-age=0, must-revalidate');
    res.status(200).send(script);
  } catch (error) {
    res.status(500).send('Failed to load Devuvo.ps1.');
  }
}
