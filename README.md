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
- **Recortar um trecho** (por exemplo, de 1:20 até 2:45) ao baixar ou ao converter: o tamanho estimado já
  considera só esse pedaço, o que ajuda a caber nos limites do Discord e do WhatsApp.
- **Tamanho final comparado com o estimado** depois de baixar ou converter, com um histórico em
  *Mais opções > Ver o histórico de estimativas* para acompanhar o quanto a estimativa erra.
- **Converter** qualquer vídeo ou música local para presets de compartilhamento
  (Discord 20 MB / 50 MB, WhatsApp 16 MB, redes sociais), com o tamanho previsto antes de confirmar.
- **Legendas**: ao baixar vídeo, escolha português, inglês ou outro idioma e se quer a legenda **embutida** no vídeo
  ou num **arquivo .srt** separado (não vale junto com o recorte).
- **Lembra das suas escolhas**: o último formato e qualidade já vêm marcados, ou você fixa um padrão
  (*Mais opções > Preferências*).
- **Aviso de versão nova do yt-dlp**: o Zapt confere de vez em quando (no máximo a cada 12 horas) e pergunta se
  quer atualizar, útil porque o YouTube muda sempre e versões velhas dão erro 403. Dá para desligar nas preferências.
- **Aceleração por hardware** (opcional) na conversão de vídeo, usando a placa de vídeo Intel/AMD via VAAPI, com
  teste embutido e volta automática para a CPU se falhar. Em *Mais opções > Preferências*.
- **Converter direto do gerenciador de arquivos**: botão direito num vídeo ou música > *Scripts > Converter para
  compartilhar (Zapt)* (Nautilus/Nemo) ou *Abrir com > Converter para compartilhar (Zapt)*. Também funciona
  arrastando arquivos para o ícone e com vários arquivos de uma vez.
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

Para ter o ícone no menu de aplicativos e o botão direito nos arquivos: **Mais opções > Criar atalho**.

Para a aceleração por hardware em vídeo Intel, pode ser preciso `sudo apt install intel-media-va-driver-non-free vainfo`.

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
