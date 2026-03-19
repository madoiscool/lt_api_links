export default async function handler(req, res) {
  const response = await fetch('http://steam.run', {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1.19041.4522'
    }
  });

  if (!response.ok) {
    res.status(response.status).send('Failed to fetch script.');
    return;
  }

  const text = await response.text();
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.status(200).send(text);
}
