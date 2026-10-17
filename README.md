<p align="center">
  <img src="zapt.svg" width="96" alt="Zapt">
</p>

# Zapt

Baixador de vídeos e músicas com janelas simples, feito para quem não quer decorar comandos.
Você cola o link, escolhe o formato e a qualidade **vendo quanto o arquivo vai pesar**, e pode
converter o resultado para caber nos limites de envio do Discord, WhatsApp e outras redes.

Um único script gera o AppImage já com [yt-dlp](https://github.com/yt-dlp/yt-dlp), ffmpeg, Deno e jq dentro.
Feito para Ubuntu, Zorin OS e derivados (x86_64).

## O que ele faz

- **Baixar música ou vídeo** escolhendo formato (MP3, M4A, Opus, FLAC; MP4, MKV, WebM) e qualidade.
- **Tamanho estimado antes de baixar**, para você decidir com a informação na mão.
- **Vários links e playlists de uma vez**: cole quantos links quiser (um por linha) ou o link de uma playlist,
  marque quais itens baixar e veja o **tamanho total estimado** antes de confirmar. Os itens entram numa fila e
  são baixados um por vez, com barra de progresso geral; playlists vão para uma subpasta com o nome da lista.
- **Converter** qualquer vídeo ou música local para presets de compartilhamento
  (Discord 20 MB / 50 MB, WhatsApp 16 MB, redes sociais), com o tamanho previsto antes de confirmar.
- **Atualizar o yt-dlp pelo próprio app** (estável, nightly ou voltar ao original), sem apagar o AppImage.
- **Atalho no menu de aplicativos**, com ações rápidas (Música, Vídeo, Converter, Atualizar).
- Funciona em **janelas (zenity)** ou, sem ele, **no terminal**.

## Como usar

```bash
curl -L -o criar-zapt-appimage.sh https://raw.githubusercontent.com/dkdloi/zapt/main/criar-zapt-appimage.sh
chmod +x criar-zapt-appimage.sh
./criar-zapt-appimage.sh
```

O script confere e instala sozinho o que faltar (curl, xz-utils, unzip, zenity e a biblioteca FUSE),
pedindo a sua senha só se necessário. No fim aparece o arquivo `zapt-x86_64.AppImage` na pasta atual.

```bash
./zapt-x86_64.AppImage
```

Para ter o ícone no menu de aplicativos: **Mais opções > Criar atalho**.

### Opções do script

| Opção | Efeito |
| --- | --- |
| `--sem-deno` | Gera sem Deno (downloads do YouTube podem falhar) |
| `--sem-ffmpeg` | Gera sem ffmpeg (sem MP3 e sem conversão) |
| `--so-dependencias` | Só confere e instala as dependências |

### Atualizando o Zapt

Rode o script de novo. O AppImage anterior é guardado como `zapt-x86_64.AppImage.anterior`.
Para atualizar só o yt-dlp, use **Mais opções > Atualizar** dentro do app.

## Aviso

Use o Zapt apenas para baixar conteúdo que você tem o direito de baixar. Você é o responsável por
respeitar os termos dos serviços e as leis de direitos autorais do seu país.

## Licenças

O código deste repositório está sob a licença [MIT](LICENSE).
O script **baixa** ferramentas de terceiros, cada uma com a sua licença:
yt-dlp (Unlicense), ffmpeg (build GPL do projeto yt-dlp), jq (MIT), Deno (MIT) e appimagetool (MIT).
Este repositório não distribui nenhum desses binários.
