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

  let text = await response.text();
  text = text.replace(
    /Set-ItemProperty\s+-Path\s+\$steamToolsRegPath\s+-Name\s+"iscdkey"\s+-Value\s+"true"\s+-Type\s+String/g,
    'Set-ItemProperty -Path $steamToolsRegPath -Name "iscdkey" -Value "false" -Type String'
  );
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.status(200).send(text);
}
