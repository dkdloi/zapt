# Changelog

O número da versão é a data (`ano.mês.dia`). O arquivo `VERSION` guarda a versão mais recente;
o Zapt confere esse arquivo de vez em quando e avisa quando há uma nova.

## 2026.10.31

- **Correção**: o script de montagem voltou a gerar o AppImage com o `appimagetool` mais novo, que passou a
  exigir ícone em PNG (o erro era ".DirIcon is an SVG image").

## 2026.10.23

- **Cookies do navegador** para vídeos com restrição de idade, só para membros ou com verificação do YouTube
  (Firefox, Chrome, Chromium, Brave, Edge, Vivaldi, Opera). O Zapt oferece sozinho quando o erro pede login.
- **Pastas de destino** separadas para música e vídeo, ou perguntar a pasta a cada download.
- **Nome dos arquivos** configurável: Título, Artista - Título, Canal - Título, Data - Título.
- **Música**: opção de limpar o título ("(Official Video)", "[Lyrics]"...) e separar artista e título.
- **Conversão de áudio**: normalizar o volume e/ou cortar o silêncio do começo e do fim.
- **Converter uma pasta inteira** (com ou sem subpastas), escolhendo quais arquivos entram.
- **Aviso de versão nova do Zapt** (e número de versão no "Sobre" e no relatório de erro).

## 2026.10.22

- **Relatório de erro** com botão "Copiar relatório".
- **Tenta de novo sozinho** em erros passageiros (403, 429, rede).
- **Retoma a fila** de playlist interrompida ou com erro.
- Legendas só do autor (as automáticas são ignoradas para evitar o erro 429).
- Cache de downloads no script de montagem (`~/.cache/zapt`).

## Antes

- Playlists e fila de downloads, recorte de trecho, comparação do tamanho estimado com o real,
  legendas, preferências, aviso de versão do yt-dlp, aceleração por hardware (VAAPI),
  "Abrir com" no gerenciador de arquivos.
