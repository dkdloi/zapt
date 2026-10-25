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
  ou num **arquivo .srt** separado (não vale junto com o recorte). O Zapt baixa **só legendas feitas pelo autor**:
  as automáticas e traduzidas pelo YouTube são ignoradas (e o resumo avisa), porque esses pedidos costumam
  ser bloqueados com o erro 429. Se mesmo assim a legenda falhar, o vídeo é baixado sem ela.
- **Lembra das suas escolhas**: o último formato e qualidade já vêm marcados, ou você fixa um padrão
  (*Mais opções > Preferências*).
- **Aviso de versão nova do yt-dlp**: o Zapt confere de vez em quando (no máximo a cada 12 horas) e pergunta se
  quer atualizar, útil porque o YouTube muda sempre e versões velhas dão erro 403. Dá para desligar nas preferências.
- **Aceleração por hardware** (opcional) na conversão de vídeo, usando a placa de vídeo Intel/AMD via VAAPI, com
  teste embutido e volta automática para a CPU se falhar. Em *Mais opções > Preferências*.
- **Converter direto do gerenciador de arquivos**: botão direito num vídeo ou música > *Scripts > Converter para
  compartilhar (Zapt)* (Nautilus/Nemo) ou *Abrir com > Converter para compartilhar (Zapt)*. Também funciona
  arrastando arquivos para o ícone e com vários arquivos de uma vez.
- **Tenta de novo sozinho** quando o erro é passageiro (403, 429, queda de rede): até 3 rodadas, com pausa entre elas.
  Erros definitivos (vídeo privado, indisponível, com idade restrita) não ficam repetindo.
- **Retoma a fila**: se você cancelar uma playlist, se der erro em algum item ou o computador desligar, o Zapt
  guarda o que faltou e pergunta, ao abrir, se quer continuar de onde parou.
- **Relatório de erro**: quando algo falha, o botão *Copiar relatório* junta versões, sistema, link e a saída do erro
  (seu nome de usuário é trocado por `~`), pronto para colar numa conversa de suporte.
- **Cookies do navegador** para vídeos com restrição de idade, só para membros ou com verificação do YouTube.
  Quando o erro pede login, o Zapt oferece sozinho. O YouTube pode limitar contas usadas com ferramentas como o
  yt-dlp, então prefira uma conta secundária no navegador.
- **Pastas e nomes**: pasta separada para música e vídeo (ou perguntar a cada download) e nome do arquivo como
  *Título*, *Artista - Título*, *Canal - Título* ou *Data - Título* (*Mais opções > Preferências*).
- **Música com etiquetas limpas** (opcional): tira "(Official Video)" e parecidos do título e separa artista e título.
- **Ajustes de áudio** na conversão de música: normalizar o volume e cortar o silêncio do começo e do fim.
- **Converter uma pasta inteira**: escolha a pasta (com ou sem subpastas), marque os arquivos e o destino.
  Também aparece com o botão direito numa pasta (*Scripts > Converter para compartilhar*).
- **Aviso de versão nova do Zapt**: confere o arquivo `VERSION` deste repositório de vez em quando.
  O histórico está no [CHANGELOG](CHANGELOG.md).
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
| `--sem-cache` | Baixa tudo de novo, sem usar nem guardar o cache |
| `--limpar-cache` | Apaga os downloads guardados em `~/.cache/zapt` e sai |

### Atualizando o Zapt

Rode o script de novo: os downloads ficam em `~/.cache/zapt` (cerca de 215 MB) e só o que tiver versão nova é
baixado, então o rebuild leva segundos. O AppImage anterior é guardado como `zapt-x86_64.AppImage.anterior`.
Para atualizar só o yt-dlp, use **Mais opções > Atualizar** dentro do app.

## Aviso

Use o Zapt apenas para baixar conteúdo que você tem o direito de baixar. Você é o responsável por
respeitar os termos dos serviços e as leis de direitos autorais do seu país.

## Licenças

O código deste repositório está sob a licença [MIT](LICENSE).
O script **baixa** ferramentas de terceiros, cada uma com a sua licença:
yt-dlp (Unlicense), ffmpeg (build GPL do projeto yt-dlp), jq (MIT), Deno (MIT) e appimagetool (MIT).
Este repositório não distribui nenhum desses binários.
