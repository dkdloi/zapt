#!/usr/bin/env bash
# Zapt: gera o AppImage (baixador e conversor de vídeo/música) para Ubuntu/Zorin x86_64, com ffmpeg, Deno e jq embutidos.
# O app tem menu para baixar MÚSICA ou VÍDEO escolhendo formato e qualidade (com o
# tamanho estimado antes de baixar), converter arquivos para Discord/WhatsApp/redes
# sociais e atualizar o yt-dlp.
#
# Uso:
#   ./criar-zapt-appimage.sh                # completo (~215 MB)
#   ./criar-zapt-appimage.sh --sem-deno     # sem Deno (YouTube pode falhar)
#   ./criar-zapt-appimage.sh --sem-ffmpeg   # sem ffmpeg (sem MP3, sem conversão)
#
#   ./criar-zapt-appimage.sh --so-dependencias   # só confere/instala as dependências
#
# As dependências (curl, xz-utils, unzip, zenity e a biblioteca FUSE) são conferidas e
# instaladas automaticamente com apt; só pede a sua senha se algo estiver faltando.
# O arquivo zapt-x86_64.AppImage é criado na pasta onde você rodar o script.
# Se já existir um, ele é guardado como zapt-x86_64.AppImage.anterior.
set -euo pipefail

WITH_FFMPEG=1
WITH_DENO=1
ONLY_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --sem-ffmpeg) WITH_FFMPEG=0 ;;
        --sem-deno)   WITH_DENO=0 ;;
        --so-dependencias) ONLY_DEPS=1 ;;
        -h|--help)    sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Opção desconhecida: $arg" >&2; exit 1 ;;
    esac
done

if [ "$(uname -m)" != "x86_64" ]; then
    echo "Este script gera AppImage apenas para x86_64." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Dependências: confere o que falta e instala sozinho (Ubuntu, Zorin, Mint, Debian)
# ---------------------------------------------------------------------------
echo "==> Conferindo dependências..."
MISSING=()
need_cmd() { command -v "$1" >/dev/null 2>&1 || MISSING+=("$2"); }
need_cmd curl curl
need_cmd tar tar
[ "$WITH_FFMPEG" = 1 ] && need_cmd xz xz-utils
[ "$WITH_DENO" = 1 ] && need_cmd unzip unzip
need_cmd zenity zenity          # janelas do app (sem ele, o app usa o terminal)
# FUSE 2: necessário para abrir qualquer AppImage (o nome do pacote muda conforme a versão)
if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    if apt-cache show libfuse2t64 >/dev/null 2>&1; then MISSING+=(libfuse2t64); else MISSING+=(libfuse2); fi
fi

if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "    Faltam: ${MISSING[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        SUDO=""
        if [ "$(id -u)" -ne 0 ]; then
            if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else echo "    Sem permissão de administrador (sudo não encontrado)." >&2; fi
        fi
        echo "    Instalando (pode pedir a sua senha)..."
        $SUDO apt-get install -y "${MISSING[@]}" ||
            { $SUDO apt-get update && $SUDO apt-get install -y "${MISSING[@]}"; } ||
            echo "    Não consegui instalar tudo automaticamente." >&2
    else
        echo "    Este sistema não usa apt. Instale manualmente: ${MISSING[*]}" >&2
    fi
else
    echo "    Tudo certo, nada a instalar."
fi

# o que é indispensável para gerar o AppImage
for cmd in curl tar; do
    command -v "$cmd" >/dev/null || { echo "Falta o comando essencial: $cmd" >&2; exit 1; }
done
[ "$WITH_FFMPEG" = 1 ] && { command -v xz >/dev/null || { echo "Falta o comando essencial: xz (pacote xz-utils)" >&2; exit 1; }; }
[ "$WITH_DENO" = 1 ] && { command -v unzip >/dev/null || { echo "Falta o comando essencial: unzip" >&2; exit 1; }; }
command -v zenity >/dev/null || echo "    Aviso: sem o zenity o app abrirá o menu no terminal, não em janelas."
[ "$ONLY_DEPS" = 1 ] && { echo "Dependências conferidas."; exit 0; }

OUT_DIR="$PWD"
FINAL="$OUT_DIR/zapt-x86_64.AppImage"
TMP_IMG="$OUT_DIR/.zapt-novo.AppImage"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$TMP_IMG"' EXIT
APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/ytdlp-app"

echo "==> Baixando yt-dlp..."
curl -fL --progress-bar -o "$APPDIR/usr/bin/yt-dlp" \
    https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux

echo "==> Baixando jq (lê as informações dos vídeos)..."
curl -fL --progress-bar -o "$APPDIR/usr/bin/jq" \
    https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64

if [ "$WITH_FFMPEG" = 1 ]; then
    echo "==> Baixando ffmpeg (build estático do projeto yt-dlp)..."
    curl -fL --progress-bar -o "$WORK/ffmpeg.tar.xz" \
        https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-linux64-gpl.tar.xz
    tar -xJf "$WORK/ffmpeg.tar.xz" -C "$APPDIR/usr/bin" --strip-components=2 \
        ffmpeg-master-latest-linux64-gpl/bin/ffmpeg \
        ffmpeg-master-latest-linux64-gpl/bin/ffprobe
fi

if [ "$WITH_DENO" = 1 ]; then
    echo "==> Baixando Deno (necessário para o yt-dlp baixar do YouTube)..."
    curl -fL --progress-bar -o "$WORK/deno.zip" \
        https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip
    unzip -q -o "$WORK/deno.zip" deno -d "$APPDIR/usr/bin"
fi

echo "==> Baixando appimagetool..."
curl -fL --progress-bar -o "$WORK/appimagetool" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x "$WORK/appimagetool"

echo "==> Montando o AppDir..."
cat > "$APPDIR/AppRun" <<'APPRUN_EOF'
#!/bin/bash
# AppRun do Zapt (AppImage com yt-dlp, ffmpeg, Deno e jq)
HERE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
export PATH="$HERE/usr/bin:$PATH"
export LC_NUMERIC=C

APP_SHARE="$HERE/usr/share/ytdlp-app"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/yt-dlp-appimage"
USER_BIN="$DATA_DIR/yt-dlp"            # cópia do yt-dlp que o app atualiza
BASE_ID_FILE="$DATA_DIR/base-id"       # de qual AppImage a cópia veio
BUNDLED_BIN="$HERE/usr/bin/yt-dlp"     # yt-dlp que veio dentro do AppImage
BUNDLED_ID="$(stat -c '%s-%Y' "$BUNDLED_BIN" 2>/dev/null)"

# Limites de envio, em MB (conferidos em out/2026; as redes mudam isso de vez em quando).
# Para qualquer outro limite, use "Outro limite de tamanho" no conversor.
LIM_DISCORD=20          # Discord, conta grátis
LIM_DISCORD_BASIC=50    # Discord, Nitro Basic
LIM_WHATSAPP=16         # WhatsApp, vídeo/áudio enviado como mídia (como documento vai até 2 GB)

# Usa o ffmpeg embutido, se existir
FFARGS=()
if [ -x "$HERE/usr/bin/ffmpeg" ]; then
    FFARGS=(--ffmpeg-location "$HERE/usr/bin")
fi

# Se o AppImage foi recriado (traz outro yt-dlp), descarta a cópia atualizada antiga
if [ -x "$USER_BIN" ] && [ "$(cat "$BASE_ID_FILE" 2>/dev/null)" != "$BUNDLED_ID" ]; then
    rm -f "$USER_BIN" "$BASE_ID_FILE"
fi

YTDLP_VER=""
use_best_bin() {
    if [ -x "$USER_BIN" ]; then YTDLP="$USER_BIN"; else YTDLP="$BUNDLED_BIN"; fi
}
use_best_bin

# O AppImage é somente leitura: para atualizar, copiamos o yt-dlp para a pasta
# do usuário e deixamos o próprio yt-dlp se atualizar ali. O arquivo .AppImage
# nunca é alterado nem precisa ser apagado.
ensure_user_bin() {
    mkdir -p "$DATA_DIR"
    if [ ! -x "$USER_BIN" ]; then
        cp "$BUNDLED_BIN" "$USER_BIN" && echo "$BUNDLED_ID" > "$BASE_ID_FILE"
    fi
    YTDLP="$USER_BIN"
}

update_args() {   # $1 = ""|nightly|stable
    case "$1" in
        nightly) echo "-U --update-to nightly" ;;
        stable)  echo "-U --update-to stable" ;;
        *)       echo "-U" ;;
    esac
}

reset_update() {
    rm -f "$USER_BIN" "$BASE_ID_FILE"
    use_best_bin
    echo "Voltou para o yt-dlp que veio dentro do app."
}

about_text() {
    local origem="embutida no app"
    [ "$YTDLP" = "$USER_BIN" ] && origem="atualizada pelo app"
    echo "Zapt: $("$YTDLP" --version 2>/dev/null) ($origem)"
    echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n1 | cut -d' ' -f1-3)"
    echo "deno: $(deno --version 2>/dev/null | head -n1)"
    echo "AppImage: ${APPIMAGE:-(não está rodando como AppImage)}"
}

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
WORKD=""
mkwork() {
    [ -n "$WORKD" ] && return 0
    WORKD="$(mktemp -d)"
    trap 'rm -rf "$WORKD"' EXIT
}

kill_tree() {
    local p
    for p in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$p"; done
    kill "$1" 2>/dev/null
}

is_pos() { awk -v x="$1" 'BEGIN { exit !(x + 0 > 0) }'; }

# 12345678 -> "12,3 MB"   (MB = 1.000.000 bytes, como no gerenciador de arquivos do Ubuntu)
fmt_mb() {
    awk -v b="$1" 'BEGIN {
        if (b >= 1e9) s = sprintf("%.2f GB", b / 1e9);
        else if (b >= 1e6) s = sprintf("%.1f MB", b / 1e6);
        else s = sprintf("%.0f KB", b / 1e3);
        gsub(/\./, ",", s); print s }'
}
# Ao baixar vários itens, SIZE_MULT multiplica os tamanhos estimados de um item
# (assim as telas já mostram o TOTAL). Fora disso fica em 1.
SIZE_MULT=1
scale_b() { awk -v b="$1" -v m="${SIZE_MULT:-1}" 'BEGIN { printf "%.0f", b * m }'; }
fmt_size() {
    if is_pos "$1"; then printf '≈ %s' "$(fmt_mb "$(scale_b "$1")")"; else printf 'tamanho desconhecido'; fi
}
size_range() {   # menor maior (bytes)
    if ! is_pos "$1" || ! is_pos "$2"; then printf 'tamanho desconhecido'; return; fi
    if [ "$1" = "$2" ]; then fmt_size "$1"; else printf 'de ≈ %s a %s' "$(fmt_mb "$(scale_b "$1")")" "$(fmt_mb "$(scale_b "$2")")"; fi
}
fmt_dur() {
    awk -v s="$1" 'BEGIN {
        s = int(s + 0.5); h = int(s / 3600); m = int((s % 3600) / 60); x = s % 60;
        if (h > 0) printf "%d:%02d:%02d", h, m, x; else printf "%d:%02d", m, x }'
}
# parse_time "1:20" -> segundos. Aceita 90, 1:20, 1:02:03, 1:20.5 (vírgula também). rc 1 se inválido.
parse_time() {
    awk -v s="$1" 'BEGIN {
        gsub(/[ \t]/, "", s); gsub(/,/, ".", s)
        n = split(s, p, ":")
        if (s == "" || n > 3) exit 1
        t = 0
        for (i = 1; i <= n; i++) {
            if (i < n) { if (p[i] !~ /^[0-9]+$/) exit 1 }
            else if (p[i] !~ /^[0-9]+(\.[0-9]+)?$/) exit 1
            if (i > 1 && p[i] + 0 >= 60) exit 1
            t = t * 60 + p[i]
        }
        printf "%.3f", t }'
}
num_g() { awk -v s="$1" 'BEGIN { printf "%g", s }'; }            # 80.000 -> 80
tag_time() {     # segundos -> 1m20s (para nomes de arquivo)
    awk -v s="$1" 'BEGIN {
        s = int(s + 0.5); h = int(s / 3600); m = int((s % 3600) / 60); x = s % 60
        if (h > 0) printf "%dh%02dm%02ds", h, m, x; else if (m > 0) printf "%dm%02ds", m, x; else printf "%ds", x }'
}

# size_diff ESTIMADO REAL [palavra]  ->  " (estimado ≈ 4,8 MB; diferença +8%)"   (vazio se não há estimativa)
size_diff() {
    is_pos "$1" && is_pos "$2" || return 0
    awk -v e="$1" -v r="$2" -v w="${3:-estimado}" -v em="$(fmt_mb "$1")" 'BEGIN {
        d = (r - e) / e * 100
        s = sprintf("%+.0f%%", d); if (s == "+0%" || s == "-0%") s = "0%"
        printf " (%s ≈ %s; diferença %s)", w, em, s }'
}

# record_size TIPO DESCRIÇÃO ESTIMADO REAL: anota no histórico (para ver o quanto a estimativa erra)
record_size() {
    local f="$DATA_DIR/estimativas.log"
    is_pos "$3" && is_pos "$4" || return 0
    mkdir -p "$DATA_DIR" 2>/dev/null || return 0
    printf '%s|%s|%s|%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "${2//|//}" "${3%.*}" "${4%.*}" \
        "$(awk -v e="$3" -v r="$4" 'BEGIN { printf "%+.1f", (r - e) / e * 100 }')" >>"$f" 2>/dev/null || return 0
    if [ "$(wc -l <"$f")" -gt 500 ]; then tail -n 400 "$f" >"$f.tmp" && mv -f "$f.tmp" "$f"; fi
    return 0
}

minmax() {       # lê linhas "a|b|bytes|..." e imprime "menor|maior"
    awk -F'|' 'NF { if ($3 != "") { if (min == "" || $3 + 0 < min + 0) min = $3; if ($3 + 0 > max + 0) max = $3 } }
               END { printf "%s|%s", min, max }'
}

# Pasta de destino: ~/Música para música, ~/Vídeos para vídeo
dest_for() {
    local d=""
    if [ "$1" = "musica" ]; then
        d="$(xdg-user-dir MUSIC 2>/dev/null || true)"
    else
        d="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
    fi
    if [ -z "$d" ] || [ ! -d "$d" ]; then d="$HOME"; fi
    echo "$d"
}

# ---------------------------------------------------------------------------
# Preferências (arquivo simples "chave=valor" na pasta de dados do app)
#   last_*  = última escolha feita (sempre guardada)     fixed_* = padrão fixo definido pelo usuário
#   memory  = last (lembrar a última) | fixed (usar o padrão fixo) | off (sempre perguntar do zero)
# ---------------------------------------------------------------------------
PREFS_FILE="$DATA_DIR/prefs"
PICK_AFMT=""; PICK_AQ=""; PICK_VCONT=""; PICK_VH=""

pref_get() {   # chave [valor se não existir]
    local v
    v="$(grep -a "^$1=" "$PREFS_FILE" 2>/dev/null | tail -n1)"
    v="${v#*=}"
    printf '%s' "${v:-${2:-}}"
}
pref_set() {   # chave valor
    mkdir -p "$DATA_DIR" 2>/dev/null || return 0
    { grep -av "^$1=" "$PREFS_FILE" 2>/dev/null; printf '%s=%s\n' "$1" "${2//$'\n'/ }"; } >"$PREFS_FILE.tmp" 2>/dev/null &&
        mv -f "$PREFS_FILE.tmp" "$PREFS_FILE"
    return 0
}
pref_del_prefix() {   # apaga todas as chaves que começam com o prefixo
    [ -f "$PREFS_FILE" ] || return 0
    grep -av "^$1" "$PREFS_FILE" >"$PREFS_FILE.tmp" 2>/dev/null
    mv -f "$PREFS_FILE.tmp" "$PREFS_FILE"
    return 0
}
pref_default() {   # nome (ex.: audio_fmt) -> valor que deve vir marcado (vazio = sem preferência)
    case "$(pref_get memory last)" in
        last) pref_get "last_$1" ;;
        fixed) pref_get "fixed_$1" ;;
    esac
}
pref_remember() { pref_set "last_$1" "$2"; }   # nome valor

remember_picks() {   # $1 = musica|video: guarda o que foi escolhido
    if [ "$1" = musica ]; then
        [ -n "$PICK_AFMT" ] && pref_remember audio_fmt "$PICK_AFMT"
        [ -n "$PICK_AQ" ] && pref_remember audio_q "$PICK_AQ"
    else
        [ -n "$PICK_VCONT" ] && pref_remember video_cont "$PICK_VCONT"
        [ -n "$PICK_VH" ] && pref_remember video_h "$PICK_VH"
        if [ -n "$PICK_SUBS" ]; then
            pref_remember subs "$PICK_SUBS"
            [ -n "$PICK_SMODE" ] && pref_remember subs_mode "$PICK_SMODE"
        fi
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Atalho no menu de aplicativos
# ---------------------------------------------------------------------------
install_shortcut() {
    local APPIMG="${APPIMAGE:-}"
    local BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
    if [ -z "$APPIMG" ]; then
        echo "Abra o app a partir do arquivo .AppImage para criar o atalho."
        return 1
    fi
    mkdir -p "$BASE/applications" "$BASE/icons/hicolor/scalable/apps"
    rm -f "$BASE/applications/yt-dlp.desktop" "$BASE/icons/hicolor/scalable/apps/yt-dlp.svg"   # atalho da versão antiga
    cp "$HERE/zapt.svg" "$BASE/icons/hicolor/scalable/apps/zapt.svg"
    cat > "$BASE/applications/zapt.desktop" <<DESKTOP_INNER_EOF
[Desktop Entry]
Type=Application
Name=Zapt
Comment=Baixa músicas (MP3) e vídeos (MP4)
Exec="$APPIMG" %U
Icon=zapt
Terminal=false
Categories=AudioVideo;Network;
Actions=Musica;Video;Converter;Atualizar;

[Desktop Action Musica]
Name=Baixar música
Exec="$APPIMG" --gui-musica

[Desktop Action Video]
Name=Baixar vídeo
Exec="$APPIMG" --gui-video

[Desktop Action Converter]
Name=Converter arquivo para compartilhar
Exec="$APPIMG" --gui-converter

[Desktop Action Atualizar]
Name=Atualizar o yt-dlp
Exec="$APPIMG" --gui-atualizar
DESKTOP_INNER_EOF
    # "Abrir com" nos vídeos e músicas: Converter para compartilhar
    cat > "$BASE/applications/zapt-converter.desktop" <<DESKTOP_INNER_EOF
[Desktop Entry]
Type=Application
Name=Converter para compartilhar (Zapt)
Comment=Converte vídeos e músicas para Discord, WhatsApp e redes sociais
Exec="$APPIMG" --converter %F
Icon=zapt
Terminal=false
Categories=AudioVideo;
MimeType=video/mp4;video/x-matroska;video/webm;video/quicktime;video/x-msvideo;video/mpeg;video/ogg;video/3gpp;video/x-flv;video/x-ms-wmv;audio/mpeg;audio/mp4;audio/x-m4a;audio/ogg;audio/flac;audio/x-flac;audio/x-wav;audio/wav;audio/webm;audio/aac;audio/opus;audio/x-opus+ogg;
DESKTOP_INNER_EOF
    # Botão direito no arquivo > Scripts > Converter para compartilhar (Nautilus e Nemo)
    local sd
    for sd in "$BASE/nautilus/scripts" "$BASE/nemo/scripts"; do
        case "$sd" in
            */nemo/scripts) [ -d "$BASE/nemo" ] || continue ;;
        esac
        mkdir -p "$sd"
        cat > "$sd/Converter para compartilhar (Zapt)" <<SCRIPT_INNER_EOF
#!/bin/sh
exec "$APPIMG" --converter "\$@"
SCRIPT_INNER_EOF
        chmod +x "$sd/Converter para compartilhar (Zapt)"
    done
    update-desktop-database "$BASE/applications" 2>/dev/null || true
    echo "Atalho criado. Procure por \"Zapt\" no menu de aplicativos."
    echo "Clique com o botão direito no ícone para ir direto a Música, Vídeo, Converter ou Atualizar."
    echo "Nos vídeos e músicas: botão direito > Abrir com > Converter para compartilhar (Zapt),"
    echo "ou botão direito > Scripts > Converter para compartilhar (Zapt)."
}

remove_shortcut() {
    local BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
    rm -f "$BASE/applications/zapt.desktop" "$BASE/applications/zapt-converter.desktop" "$BASE/icons/hicolor/scalable/apps/zapt.svg"
    rm -f "$BASE/nautilus/scripts/Converter para compartilhar (Zapt)" "$BASE/nemo/scripts/Converter para compartilhar (Zapt)"
    rm -f "$BASE/applications/yt-dlp.desktop" "$BASE/icons/hicolor/scalable/apps/yt-dlp.svg"
    update-desktop-database "$BASE/applications" 2>/dev/null || true
    echo "Atalho removido."
}

# ---------------------------------------------------------------------------
# Camada de interface: o mesmo fluxo roda em janelas (zenity) ou no terminal.
# UI=gui|tty. As listas chegam por stdin, uma linha por item: "id|coluna1|coluna2".
# ---------------------------------------------------------------------------
UI=""
RUNLOG=""

have_gui() {
    command -v zenity >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }
}
have_tty() { [ -t 0 ] && [ -t 1 ]; }
pause() { IFS= read -r -p "Pressione Enter para continuar. " _ </dev/tty || true; }

# ui_menu TÍTULO TEXTO [RÓTULO_CANCELAR]   (linhas "id|rótulo")  -> imprime o id
ui_menu() {
    local title="$1" text="$2" cancel="${3:-Sair}" rows=() row id lbl args=() n opt
    mapfile -t rows
    if [ "$UI" = gui ]; then
        for row in "${rows[@]}"; do
            IFS='|' read -r id lbl <<<"$row"
            args+=("$id" "$lbl")
        done
        zenity --list --title="$title" --text="$text" --width=500 \
            --height=$((190 + 38 * ${#rows[@]})) \
            --column=id --column="Ação" --hide-column=1 --print-column=1 \
            --ok-label="Escolher" --cancel-label="$cancel" "${args[@]}" 2>/dev/null
        return $?
    fi
    while true; do
        printf '\n%s\n' "$text" >&2
        n=0
        for row in "${rows[@]}"; do
            n=$((n + 1))
            IFS='|' read -r id lbl <<<"$row"
            printf '  %d) %s\n' "$n" "$lbl" >&2
        done
        printf '  0) %s\n' "$cancel" >&2
        IFS= read -r -p "Escolha: " opt </dev/tty || return 1
        [ "$opt" = 0 ] && return 1
        case "$opt" in '' | *[!0-9]*) continue ;; esac
        [ "$opt" -ge 1 ] && [ "$opt" -le "${#rows[@]}" ] || continue
        IFS='|' read -r id lbl <<<"${rows[$((opt - 1))]}"
        printf '%s' "$id"
        return 0
    done
}

# ui_choose TÍTULO TEXTO PADRÃO CABEÇALHO1 CABEÇALHO2   (linhas "id|col1|col2") -> imprime o id
ui_choose() {
    local title="$1" text="$2" def="$3" h1="$4" h2="$5"
    local rows=() row id c1 c2 args=() n=0 opt mark height found=0
    mapfile -t rows
    [ "${#rows[@]}" -gt 0 ] || return 1
    for row in "${rows[@]}"; do
        IFS='|' read -r id _ <<<"$row"
        [ "$id" = "$def" ] && found=1
    done
    if [ "$found" = 0 ]; then IFS='|' read -r def _ <<<"${rows[0]}"; fi
    if [ "$UI" = gui ]; then
        for row in "${rows[@]}"; do
            IFS='|' read -r id c1 c2 <<<"$row"
            mark=FALSE
            [ "$id" = "$def" ] && mark=TRUE
            args+=("$mark" "$id" "$c1" "$c2")
        done
        height=$((250 + 34 * ${#rows[@]}))
        [ "$height" -gt 640 ] && height=640
        zenity --list --radiolist --title="$title" --text="$text" --width=760 --height="$height" \
            --column="" --column=id --column="$h1" --column="$h2" --hide-column=2 --print-column=2 \
            --ok-label="Continuar" --cancel-label="Voltar" "${args[@]}" 2>/dev/null
        return $?
    fi
    while true; do
        printf '\n%s\n\n' "$text" >&2
        n=0
        for row in "${rows[@]}"; do
            n=$((n + 1))
            IFS='|' read -r id c1 c2 <<<"$row"
            mark=" "
            [ "$id" = "$def" ] && mark="*"
            printf ' %s%2d) %s\n        %s\n' "$mark" "$n" "$c1" "$c2" >&2
        done
        printf '\n  0) Voltar     (Enter = opção marcada com *)\n' >&2
        IFS= read -r -p "Escolha: " opt </dev/tty || return 1
        [ "$opt" = 0 ] && return 1
        if [ -z "$opt" ]; then printf '%s' "$def"; return 0; fi
        case "$opt" in *[!0-9]*) continue ;; esac
        [ "$opt" -ge 1 ] && [ "$opt" -le "${#rows[@]}" ] || continue
        IFS='|' read -r id _ <<<"${rows[$((opt - 1))]}"
        printf '%s' "$id"
        return 0
    done
}

# ui_entry TÍTULO TEXTO [PADRÃO] [vazio] -> imprime o texto digitado ("vazio" = aceita Enter em branco no terminal)
ui_entry() {
    local v
    if [ "$UI" = gui ]; then
        zenity --entry --title="$1" --text="$2" --entry-text="${3:-}" --width=540 \
            --ok-label="Continuar" --cancel-label="Cancelar" 2>/dev/null
        return $?
    fi
    printf '\n%s\n' "$2" >&2
    IFS= read -r -p "> " v </dev/tty || return 1
    [ -z "$v" ] && v="${3:-}"
    [ -n "$v" ] || [ "${4:-}" = vazio ] || return 1      # Enter em branco = cancelar (salvo se pedido "vazio")
    printf '%s' "$v"
}

# ui_links TEXTO -> imprime o que foi colado (um ou vários links)
ui_links() {
    local line out=""
    if [ "$UI" = gui ]; then
        mkwork
        printf '%s\n' "# $1" "# Uma linha por link. Linhas que começam com # são ignoradas." "" >"$WORKD/links.txt"
        zenity --text-info --editable --title="Zapt: cole os links" --filename="$WORKD/links.txt" \
            --width=680 --height=380 --ok-label="Continuar" --cancel-label="Cancelar" 2>/dev/null
        return $?
    fi
    printf '\n%s\n(Um link por linha. Linha em branco para continuar; em branco logo de início = cancelar.)\n' "$1" >&2
    while IFS= read -r -p "> " line </dev/tty; do
        [ -n "$line" ] || break
        out+="$line"$'\n'
    done
    [ -n "$out" ] || return 1
    printf '%s' "$out"
}

# Do texto colado, tira os links (separados por espaço ou linha), sem repetir e sem comentários
links_from_text() {
    awk '/^[[:space:]]*#/ { next } { for (i = 1; i <= NF; i++) if (!seen[$i]++) print $i }'
}

# sel_expr N EXPRESSÃO -> índices (1..N), um por linha.  "1,3,5-8", "menos 2,4", "todos" ou vazio.
sel_expr() {
    awk -v n="$1" -v e="$2" 'BEGIN {
        e = tolower(e); gsub(/[ \t]/, "", e)
        if (e == "" || e == "todos") { for (i = 1; i <= n; i++) print i; exit }
        excl = 0
        if (sub(/^menos/, "", e)) excl = 1
        m = split(e, p, ",")
        for (k = 1; k <= m; k++) {
            if (p[k] ~ /^[0-9]+$/) { a = p[k] + 0; b = a }
            else if (p[k] ~ /^[0-9]+-[0-9]+$/) { split(p[k], r, "-"); a = r[1] + 0; b = r[2] + 0 }
            else exit 2
            if (a > b || a < 1 || b > n) exit 2
            for (i = a; i <= b; i++) s[i] = 1
        }
        for (i = 1; i <= n; i++) if ((excl && !(i in s)) || (!excl && (i in s))) print i
    }'
}

# ui_checklist TÍTULO TEXTO CABEÇALHO1 CABEÇALHO2   (linhas "id|col1|col2", todas marcadas)
# -> imprime os ids marcados, um por linha
ui_checklist() {
    local title="$1" text="$2" h1="$3" h2="$4"
    local rows=() row id c1 c2 args=() n=0 ans sel i
    mapfile -t rows
    [ "${#rows[@]}" -gt 0 ] || return 1
    if [ "$UI" = gui ]; then
        for row in "${rows[@]}"; do
            IFS='|' read -r id c1 c2 <<<"$row"
            args+=(TRUE "$id" "$c1" "$c2")
        done
        zenity --list --checklist --title="$title" --text="$text" --width=840 --height=620 \
            --column="" --column=id --column="$h1" --column="$h2" --hide-column=2 --print-column=2 \
            --separator=$'\n' --ok-label="Continuar" --cancel-label="Voltar" "${args[@]}" 2>/dev/null
        return $?
    fi
    while true; do
        printf '\n%s\n\n' "$text" >&2
        n=0
        for row in "${rows[@]}"; do
            n=$((n + 1))
            IFS='|' read -r id c1 c2 <<<"$row"
            printf ' %3d) %s  [%s]\n' "$n" "$c1" "$c2" >&2
        done
        printf '\nDigite os números a baixar (ex.: 1,3,5-8), "menos 2,4" para tirar alguns,\n"todos" ou Enter para todos.   0 = voltar\n' >&2
        IFS= read -r -p "Escolha: " ans </dev/tty || return 1
        [ "$ans" = 0 ] && return 1
        sel="$(sel_expr "$n" "$ans")" || { printf 'Não entendi. Tente de novo.\n' >&2; continue; }
        [ -n "$sel" ] || { printf 'Nada selecionado.\n' >&2; continue; }
        while read -r i; do
            IFS='|' read -r id _ <<<"${rows[$((i - 1))]}"
            printf '%s\n' "$id"
        done <<<"$sel"
        return 0
    done
}

# ui_confirm TEXTO [ROTULO_OK] [ROTULO_CANCELAR] [s|n = padrão no terminal] -> 0 se OK
ui_confirm() {
    local a def="${4:-s}" hint="[S/n]"
    if [ "$UI" = gui ]; then
        zenity --question --no-markup --title="Zapt" --text="$1" \
            --ok-label="${2:-OK}" --cancel-label="${3:-Cancelar}" --width=500 2>/dev/null
        return $?
    fi
    [ "$def" = n ] && hint="[s/N]"
    printf '\n%s\n\n' "$1" >&2
    IFS= read -r -p "${2:-OK}? $hint " a </dev/tty || return 1
    case "${a,,}" in
        s | sim | y | yes) return 0 ;;
        n | nao | não) return 1 ;;
        *) [ "$def" = s ] ;;
    esac
}

# ui_text TÍTULO ARQUIVO   (mostra um texto longo)
ui_text() {
    if [ "$UI" = gui ]; then
        zenity --text-info --title="$1" --filename="$2" --width=780 --height=480 2>/dev/null
    else
        printf '\n'; cat "$2" >&2; printf '\n'
        pause
    fi
}

ui_info() {
    if [ "$UI" = gui ]; then
        zenity --info --no-markup --title="Zapt" --text="$1" --width=500 2>/dev/null
    else
        printf '\n%s\n\n' "$1" >&2
        pause
    fi
}

# ui_fail TÍTULO DICA   (mostra a dica e, nas janelas, a saída do último comando)
ui_fail() {
    local f
    if [ "$UI" = gui ]; then
        mkwork
        f="$WORKD/erro.txt"
        { printf '%s\n\n' "$2"; [ -s "$RUNLOG" ] && grep -av '^\[download\] *[0-9.]*% of' "$RUNLOG"; } >"$f"
        zenity --text-info --title="$1" --filename="$f" --width=720 --height=420 2>/dev/null
    else
        printf '\n%s\n\n' "$2" >&2
        pause
    fi
}

# ui_pick_file -> imprime o caminho escolhido
ui_pick_file() {
    local dir f
    dir="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
    [ -d "$dir" ] || dir="$HOME"
    if [ "$UI" = gui ]; then
        zenity --file-selection --title="Escolha o vídeo ou a música" --filename="$dir/" \
            --file-filter="Vídeo e áudio | *.mp4 *.mkv *.webm *.mov *.avi *.m4v *.flv *.ts *.3gp *.mp3 *.m4a *.opus *.ogg *.flac *.wav *.aac *.wma" \
            --file-filter="Todos os arquivos | *" 2>/dev/null
        return $?
    fi
    printf '\nArraste o arquivo para cá (ou digite o caminho) e pressione Enter.\n' >&2
    printf 'Enter em branco = voltar.\n' >&2
    IFS= read -r -p "> " f </dev/tty || return 1
    f="${f#\'}"; f="${f%\'}"; f="${f#\"}"; f="${f%\"}"
    f="${f//\\ / }"
    case "$f" in "~/"*) f="$HOME/${f:2}" ;; esac
    [ -n "$f" ] || return 1
    printf '%s' "$f"
}

# Mostra a porcentagem de uma conversão lendo o arquivo de progresso do ffmpeg
enc_pct() {
    local st cur tot t
    st="$(cat "$WORKD/stage" 2>/dev/null)"
    cur="${st%/*}"
    tot="${st#*/}"
    t="$(grep -a '^out_time_us=' "$WORKD/prog" 2>/dev/null | tail -n1 | cut -d= -f2)"
    case "$t" in '' | *[!0-9]*) t=0 ;; esac
    awk -v c="${cur:-1}" -v n="${tot:-1}" -v t="$t" -v d="$P_DUR" \
        'BEGIN { p = ((c - 1) + (d > 0 ? t / 1e6 / d : 0)) / n * 100; if (p > 99) p = 99; if (p < 0) p = 0; printf "%d", p }'
}

# Progresso geral de uma fila de downloads (lê "k/n" em $WORKD/stage e o % do item atual no log)
q_pct() {
    local st cur tot ip
    st="$(cat "$WORKD/stage" 2>/dev/null)"
    cur="${st%/*}"
    tot="${st#*/}"
    ip="$(tail -c 20000 "$RUNLOG" 2>/dev/null | tac | sed '/^\[\[ITEM /q' | grep -ao '[0-9][0-9]*\(\.[0-9]*\)\?%' | head -n1)"
    ip="${ip%\%}"; ip="${ip%%.*}"
    case "$ip" in '' | *[!0-9]*) ip=0 ;; esac
    awk -v c="${cur:-1}" -v n="${tot:-1}" -v t="$ip" \
        'BEGIN { p = ((c - 1) + t / 100) / n * 100; if (p > 99) p = 99; if (p < 0) p = 0; printf "%d", p }'
}

# ui_run TEXTO COMANDO...     RUN_KIND=pulse|dl|dlq|enc
# O comando pode mudar o texto mostrado escrevendo em $WORKD/runtext.
# Nas janelas: roda em segundo plano com barra de progresso e botão Cancelar (retorna 130).
# No terminal: roda direto, mostrando a saída do comando.
ui_run() {
    local text="$1" pid rc pct args=()
    shift
    mkwork
    rm -f "$WORKD/runtext"
    if [ "$UI" != gui ]; then
        printf '%s\n' "$text" >&2
        "$@"
        return $?
    fi
    RUNLOG="$WORKD/run.log"
    : >"$RUNLOG"
    "$@" >"$RUNLOG" 2>&1 &
    pid=$!
    case "${RUN_KIND:-pulse}" in enc | dlq) args=(--percentage=0) ;; *) args=(--pulsate) ;; esac
    (
        local cur
        while kill -0 "$pid" 2>/dev/null; do
            cur="$text"
            [ -s "$WORKD/runtext" ] && cur="$(cat "$WORKD/runtext")"
            case "${RUN_KIND:-pulse}" in
                enc) pct="$(enc_pct)"; echo "$pct"; echo "# $cur ($pct%)" ;;
                dlq) pct="$(q_pct)"; echo "$pct"; echo "# $cur" ;;
                dl) pct="$(grep -ao '[0-9][0-9.]*%' "$RUNLOG" 2>/dev/null | tail -n1)"; echo "# $cur $pct" ;;
                *) echo "# $cur" ;;
            esac
            sleep 0.5
        done
        echo 100
    ) | zenity --progress "${args[@]}" --auto-close --no-markup --title="Zapt" \
        --text="$text" --width=480 2>/dev/null
    rc=${PIPESTATUS[1]}
    rm -f "$WORKD/runtext"
    if [ "$rc" -ne 0 ]; then
        kill_tree "$pid"
        wait "$pid" 2>/dev/null
        return 130
    fi
    wait "$pid"
    return $?
}

# ---------------------------------------------------------------------------
# Atualização do yt-dlp
# ---------------------------------------------------------------------------
update_job() {
    # shellcheck disable=SC2046
    "$USER_BIN" $(update_args "$1")
}

flow_update() {   # $1 = ""|nightly|stable
    local before after rc
    mkwork
    ensure_user_bin
    before="$("$USER_BIN" --version 2>/dev/null)"
    RUN_KIND=pulse ui_run "Atualizando o yt-dlp…" update_job "$1"
    rc=$?
    [ "$rc" -eq 130 ] && return 0
    after="$("$USER_BIN" --version 2>/dev/null)"
    YTDLP_VER=""
    if [ "$rc" -ne 0 ]; then
        ui_fail "Zapt: erro ao atualizar" "Não foi possível atualizar o yt-dlp. Confira a internet e tente de novo."
        return 0
    fi
    if [ "$before" = "$after" ]; then
        ui_info "O yt-dlp já está na versão mais recente deste canal ($after)."
    else
        ui_info "Atualizado: $before → $after"
    fi
}

# ---------------------------------------------------------------------------
# Aviso de versão nova do yt-dlp
# ---------------------------------------------------------------------------
UPD_CACHE="$DATA_DIR/update_check"   # linhas: "<epoch> <canal> <versão ou ->"
GH_BASE="${ZAPT_GH_BASE:-https://github.com}"

http_location() {   # url -> valor do cabeçalho Location (sem seguir o redirecionamento)
    local u="$1" out=""
    if command -v curl >/dev/null 2>&1; then
        out="$(curl -sSI --max-time 4 "$u" 2>/dev/null)"
    elif command -v wget >/dev/null 2>&1; then
        out="$(wget -q -S --spider --max-redirect=0 --timeout=4 "$u" 2>&1)"
    elif command -v deno >/dev/null 2>&1; then
        out="$(timeout 6 deno eval --allow-net \
            "const r=await fetch('$u',{method:'HEAD',redirect:'manual'});console.log('location: '+(r.headers.get('location')||''))" 2>/dev/null)"
    fi
    printf '%s\n' "$out" | tr -d '\r' | awk 'tolower($1) == "location:" { print $2; exit }'
}

ytdlp_channel() {   # nightly se a versão tem 4 partes (2026.10.21.232810), senão stable
    if [ "$(printf '%s' "$1" | awk -F. '{ print NF }')" -ge 4 ]; then echo nightly; else echo stable; fi
}

latest_remote() {   # canal -> versão mais recente publicada (vazio se não deu)
    local repo="yt-dlp/yt-dlp" loc
    [ "$1" = nightly ] && repo="yt-dlp/yt-dlp-nightly-builds"
    loc="$(http_location "$GH_BASE/$repo/releases/latest")"
    case "$loc" in */tag/*) loc="${loc##*/tag/}" ;; *) return 0 ;; esac
    printf '%s' "$loc" | grep -E '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}([.0-9]*)?$' || true
}

version_newer() {   # $1 mais nova que $2?
    [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] &&
        [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# Descobre a versão mais nova (usa o cache: 12 h se deu certo, 1 h se falhou). Imprime a versão ou nada.
latest_known() {   # $1 = canal   $2 = "cache" para só olhar o cache
    local now t ch v ttl
    now="$(date +%s)"
    if [ -s "$UPD_CACHE" ]; then
        read -r t ch v <"$UPD_CACHE"
        if [ "$ch" = "$1" ] && [ -n "$t" ]; then
            ttl=43200; [ "$v" = "-" ] && ttl=3600
            if [ "$((now - t))" -lt "$ttl" ] || [ "${2:-}" = cache ]; then
                [ "$v" = "-" ] || printf '%s' "$v"
                return 0
            fi
        fi
    fi
    [ "${2:-}" = cache ] && return 0
    v="$(latest_remote "$1")"
    mkdir -p "$DATA_DIR"
    printf '%s %s %s\n' "$now" "$1" "${v:--}" >"$UPD_CACHE"
    printf '%s' "$v"
}

update_available() {   # só cache, sem rede: imprime a versão nova, se houver
    local cur ch lat
    [ "$(pref_get update_check on)" = on ] || return 1
    cur="${YTDLP_VER:-$("$YTDLP" --version 2>/dev/null)}"
    ch="$(ytdlp_channel "$cur")"
    lat="$(latest_known "$ch" cache)"
    version_newer "$lat" "$cur" && { printf '%s' "$lat"; return 0; }
    return 1
}

# Pergunta uma vez por versão nova se quer atualizar
UPD_ASKED=0
update_notice() {
    local cur ch lat
    [ "$UPD_ASKED" = 0 ] || return 0
    UPD_ASKED=1
    [ "$(pref_get update_check on)" = on ] || return 0
    cur="$("$YTDLP" --version 2>/dev/null)"
    [ -n "$cur" ] || return 0
    ch="$(ytdlp_channel "$cur")"
    lat="$(latest_known "$ch")"
    version_newer "$lat" "$cur" || return 0
    [ "$(pref_get update_seen)" = "$lat" ] && return 0
    pref_set update_seen "$lat"
    if ui_confirm "Há uma versão nova do yt-dlp.

Você usa: $cur
Nova: $lat

O YouTube muda sempre e versões antigas podem dar erro 403. Atualizar agora?" "Atualizar" "Agora não"; then
        flow_update ""
    fi
}

onoff() {   # chave padrão(on|off) -> "ligado"/"desligado"
    if [ "$(pref_get "$1" "$2")" = on ]; then printf 'ligado'; else printf 'desligado'; fi
}
toggle_pref() {   # chave padrão(on|off)
    if [ "$(pref_get "$1" "$2")" = on ]; then pref_set "$1" off; else pref_set "$1" on; fi
}
mem_label() {
    case "$(pref_get memory last)" in
        fixed) printf 'manter o meu padrão' ;;
        off) printf 'sempre perguntar do zero' ;;
        *) printf 'lembrar a última escolha' ;;
    esac
}

# texto com o que está guardado (para as telas de preferências)
prefs_summary() {
    local l f
    for l in last fixed; do
        f="$([ "$l" = last ] && echo 'Última escolha' || echo 'Padrão fixo')"
        printf '%s — Música: %s%s · Vídeo: %s%s\n' "$f" \
            "$(pref_get "${l}_audio_fmt" '—' | tr a-z A-Z)" "$(pref_get "${l}_audio_q" | sed 's/^./ &/;s/$/ kbps/;s/^ kbps$//')" \
            "$(pref_get "${l}_video_cont" '—' | tr a-z A-Z)" "$(pref_get "${l}_video_h" | sed 's/^./ até &/;s/$/p/;s/^p$//')"
    done
}

fix_defaults() {
    local k n=0
    for k in audio_fmt audio_q video_cont video_h subs subs_mode; do
        if [ -n "$(pref_get "last_$k")" ]; then
            pref_set "fixed_$k" "$(pref_get "last_$k")"
            n=$((n + 1))
        fi
    done
    if [ "$n" -eq 0 ]; then
        ui_info "Ainda não há escolhas guardadas. Baixe algo uma vez e depois volte aqui."
        return 0
    fi
    pref_set memory fixed
    ui_info "Pronto: as suas últimas escolhas viraram o padrão fixo.

$(prefs_summary | tail -n1)

Para voltar a lembrar sempre a última escolha, mude em \"Escolhas de formato e qualidade\"."
}

flow_prefs() {
    local c m
    while true; do
        c="$(ui_menu "Zapt: preferências" "$(prefs_summary)

O que você quer ajustar?" Voltar <<EOF
memoria|Escolhas de formato e qualidade: $(mem_label)
fixar|Usar as minhas últimas escolhas como padrão fixo
esquecer|Esquecer as escolhas guardadas
aviso|Aviso de versão nova do yt-dlp: $(onoff update_check on)
hw|Aceleração por hardware na conversão: $(onoff hw off)
EOF
)" || return 0
        case "$c" in
            memoria)
                m="$(printf '%s\n' \
                    'last|Lembrar a última escolha|o app já vem com o último formato e qualidade marcados' \
                    'fixed|Manter o meu padrão|usa sempre o padrão fixo que você definiu (veja "Usar as minhas últimas escolhas como padrão fixo")' \
                    'off|Sempre perguntar do zero|não marca nada de antemão' |
                    ui_choose "Zapt: preferências" "Como o Zapt deve escolher o formato e a qualidade de antemão?" "$(pref_get memory last)" "Modo" "Como funciona")" &&
                    pref_set memory "$m"
                ;;
            fixar) fix_defaults ;;
            esquecer)
                if ui_confirm "Esquecer o formato e a qualidade guardados (a última escolha e o padrão fixo)?" "Esquecer" "Cancelar" n; then
                    pref_del_prefix last_
                    pref_del_prefix fixed_
                    ui_info "Pronto, esqueci as escolhas guardadas."
                fi
                ;;
            aviso) toggle_pref update_check on ;;
            hw) flow_hw_pref ;;
        esac
    done
}

# Mostra o quanto as estimativas de tamanho erraram nos últimos downloads e conversões
flow_history() {
    local f="$DATA_DIR/estimativas.log" t
    if [ ! -s "$f" ]; then
        ui_info "Ainda não há registros. Depois de baixar ou converter, o Zapt anota aqui o tamanho estimado e o tamanho final."
        return 0
    fi
    mkwork
    t="$WORKD/historico.txt"
    {
        echo "Quanto o tamanho final diferiu do estimado (+ = ficou maior, - = ficou menor)."
        echo "Média por tipo, em todos os registros:"
        awk -F'|' '{ s[$2] += $6; a[$2] += ($6 < 0 ? -$6 : $6); n[$2]++ }
            END { for (k in n) printf "  %-16s %3d registros · diferença média %+.1f%% · erro médio %.1f%%\n", k, n[k], s[k] / n[k], a[k] / n[k] }' "$f" | sort
        echo
        echo "Últimos registros (mais recente primeiro):"
        tail -n 30 "$f" | tac | awk -F'|' '
            function fm(b,   s) {
                if (b >= 1e9) s = sprintf("%.2f GB", b / 1e9); else if (b >= 1e6) s = sprintf("%.1f MB", b / 1e6); else s = sprintf("%.0f KB", b / 1e3)
                gsub(/\./, ",", s); return s }
            { printf "  %s  %-14s estimado %s → final %s (%+.1f%%)\n      %s\n", $1, $2, fm($4), fm($5), $6, $3 }'
    } >"$t"
    ui_text "Zapt: histórico de estimativas" "$t"
}

flow_more() {
    local c
    c="$(ui_menu "Zapt: mais opções" "Escolha uma opção:" "Voltar" <<'EOF'
nightly|Atualizar para a versão nightly (se o YouTube der erro 403)
estavel|Atualizar para a versão estável
resetar|Voltar para a versão que veio dentro do app
prefs|Preferências…
historico|Ver o histórico de estimativas de tamanho
atalho|Criar atalho no menu de aplicativos
sematalho|Remover o atalho do menu de aplicativos
sobre|Sobre (versões instaladas)
EOF
)" || return 0
    case "$c" in
        nightly) flow_update nightly ;;
        estavel) flow_update stable ;;
        resetar) reset_update >/dev/null; YTDLP_VER=""; ui_info "Voltou para o yt-dlp que veio dentro do app." ;;
        prefs) flow_prefs ;;
        historico) flow_history ;;
        atalho) ui_info "$(install_shortcut 2>&1)" ;;
        sematalho) ui_info "$(remove_shortcut 2>&1)" ;;
        sobre) ui_info "$(about_text)" ;;
    esac
}

# ---------------------------------------------------------------------------
# Recorte de um trecho (início e fim), no download e na conversão
# ---------------------------------------------------------------------------
CLIP_ON=0; CLIP_S=0; CLIP_E=0; CLIP_DUR=0; CLIP_TAG=""; CLIP_IN=()

clip_text() {
    if is_pos "$CLIP_E"; then
        printf 'Trecho: %s a %s (%s)' "$(fmt_dur "$CLIP_S")" "$(fmt_dur "$CLIP_E")" "$(fmt_dur "$CLIP_DUR")"
    else
        printf 'Trecho: de %s até o final' "$(fmt_dur "$CLIP_S")"
    fi
}

# ask_clip DURAÇÃO_TOTAL (0 = desconhecida): pergunta início e fim. Preenche CLIP_*. rc 1 = voltar.
ask_clip() {
    local total="$1" a b s e hint="" def_end=""
    if is_pos "$total"; then
        hint="
Duração total: $(fmt_dur "$total")"
        def_end="$(fmt_dur "$total")"
    fi
    while true; do
        a="$(ui_entry "Recortar: início" "Onde o trecho começa? (exemplos: 1:20, 90, 1:02:03)$hint" "0:00")" || return 1
        s="$(parse_time "${a:-0:00}")" || { ui_info "Não entendi \"$a\". Escreva minutos e segundos, como 1:20."; continue; }
        b="$(ui_entry "Recortar: fim" "Onde o trecho termina? (exemplo: 2:45)
Deixe em branco para ir até o final.$hint" "$def_end" vazio)" || return 1
        e=""
        if [ -n "${b//[[:space:]]/}" ]; then
            e="$(parse_time "$b")" || { ui_info "Não entendi \"$b\". Escreva minutos e segundos, como 2:45."; continue; }
            if ! is_pos "$e"; then ui_info "O fim precisa ser depois do início."; continue; fi
        fi
        if is_pos "$total"; then
            if ! awk -v s="$s" -v t="$total" 'BEGIN { exit !(s < t) }'; then
                ui_info "O início ($(fmt_dur "$s")) passa do final do arquivo ($(fmt_dur "$total"))."
                continue
            fi
            if [ -z "$e" ] || awk -v e="$e" -v t="$total" 'BEGIN { exit !(e > t) }'; then e="$total"; fi
        fi
        if [ -n "$e" ] && ! awk -v s="$s" -v e="$e" 'BEGIN { exit !(e - s >= 1) }'; then
            ui_info "O fim precisa ser depois do início, e o trecho precisa ter pelo menos 1 segundo."
            continue
        fi
        break
    done
    CLIP_S="$s"
    CLIP_E="${e:-0}"
    if [ -n "$e" ]; then CLIP_DUR="$(awk -v s="$s" -v e="$e" 'BEGIN { printf "%.3f", e - s }')"; else CLIP_DUR=0; fi
    # trecho que cobre o arquivo todo = sem recorte
    if is_pos "$total" && ! is_pos "$s" && awk -v e="$CLIP_E" -v t="$total" 'BEGIN { exit !(e >= t - 0.5) }'; then
        CLIP_ON=0
        return 0
    fi
    CLIP_ON=1
    CLIP_TAG="$(tag_time "$s")-$([ -n "$e" ] && tag_time "$e" || echo fim)"
    return 0
}

# choose_clip TEXTO DURAÇÃO: "inteiro ou só um trecho?". CLIP_ON=0|1. rc 1 = voltar.
choose_clip() {
    local text="$1" total="$2" c d="sem recorte"
    CLIP_ON=0
    is_pos "$total" && d="duração $(fmt_dur "$total")"
    while true; do
        c="$(printf '%s\n' "inteiro|Inteiro|$d" \
            'trecho|Só um trecho|você escolhe o início e o fim (exemplo: de 1:20 até 2:45)' |
            ui_choose "Zapt" "$text" inteiro "O que usar" "Detalhes")" || return 1
        [ "$c" = inteiro ] && return 0
        ask_clip "$total" && return 0
    done
}

# junta o recorte aos argumentos do yt-dlp (usa o ffmpeg para cortar; as pontas são recodificadas)
apply_clip_args() {
    [ "$CLIP_ON" = 1 ] || return 0
    local i end=inf
    is_pos "$CLIP_E" && end="$(num_g "$CLIP_E")"
    YARGS+=(--download-sections "*$(num_g "$CLIP_S")-$end" --force-keyframes-at-cuts)
    for ((i = 0; i < ${#YARGS[@]}; i++)); do
        if [ "${YARGS[$i]}" = "-o" ]; then
            YARGS[$((i + 1))]="%(title)s (trecho $CLIP_TAG).%(ext)s"
            break
        fi
    done
}

# opções de recorte para o ffmpeg (antes do -i)
clip_in_args() {
    CLIP_IN=()
    [ "$CLIP_ON" = 1 ] || return 0
    CLIP_IN=(-ss "$(num_g "$CLIP_S")")
    is_pos "$CLIP_E" && CLIP_IN+=(-to "$(num_g "$CLIP_E")")
    return 0
}

# ---------------------------------------------------------------------------
# Download: escolha de formato e qualidade, com o tamanho estimado antes de confirmar
# ---------------------------------------------------------------------------
I_TYPE=""; I_TITLE=""; I_DUR=0
BA_ID=""; BA_EXT=""; BA_ABR=""; BA_CODEC=""; BA_BYTES=""
VROWS=()
SEL_LABEL=""; SEL_BYTES=""; YARGS=(); YFALLBACK=""   # YFALLBACK: outro seletor (-f) para tentar se o 1º falhar
DEST=""; DL_URL=""; SAVED=""; LAST_FILE=""

fetch_info_job() {
    "$YTDLP" "${FFARGS[@]}" --no-playlist --no-warnings -J "$1" >"$WORKD/info.json"
}

load_baudio() {
    IFS='|' read -r BA_ID BA_EXT BA_ABR BA_CODEC BA_BYTES \
        <<<"$(jq -r -f "$APP_SHARE/baudio.jq" "$WORKD/info.json" 2>/dev/null)"
    [ "${BA_ABR:-0}" = 0 ] && BA_ABR=""
    return 0
}

parse_info() {
    local f="$WORKD/info.json"
    { [ -s "$f" ] && jq -e . "$f" >/dev/null 2>&1; } || return 1
    I_TYPE="$(jq -r '._type // "video"' "$f")"
    I_TITLE="$(jq -r '.title // "sem título"' "$f")"
    I_DUR="$(jq -r '(.duration // 0) | tostring' "$f")"
    load_baudio
    return 0
}

info_text() {
    local t="$I_TITLE
Duração: $(fmt_dur "$I_DUR")"
    if [ "${BATCH_N:-1}" -gt 1 ]; then
        t="$BATCH_N itens: os tamanhos abaixo são o TOTAL estimado (calculado pelo 1º item e pela duração dos demais).
Item de exemplo: $t"
    fi
    if [ -n "$BA_ID" ]; then t="$t · áudio original do site: $BA_EXT${BA_ABR:+ ~$BA_ABR kbps}"; fi
    if [ "$CLIP_ON" = 1 ]; then t="$t
$(clip_text) · os tamanhos abaixo já são só desse trecho"; fi
    printf '%s' "$t"
}

audio_est() { awk -v k="$1" -v d="$I_DUR" 'BEGIN { printf "%d", k * 125 * d * 1.01 }'; }   # bytes a k kbps
lossless_est() { awk -v f="$1" -v d="$I_DUR" 'BEGIN { printf "%d", d * 176400 * f }'; }  # 44,1 kHz, 16 bits, estéreo

audio_format_rows() {
    if [ -n "$BA_ID" ]; then
        printf 'orig|Original|sem reconverter (%s%s) · %s\n' "$BA_EXT" "${BA_ABR:+, ~$BA_ABR kbps}" "$(fmt_size "$BA_BYTES")"
    fi
    printf 'mp3|MP3|toca em qualquer aparelho · %s\n' "$(size_range "$(audio_est 96)" "$(audio_est 320)")"
    printf 'm4a|M4A (AAC)|ótimo em celulares e Apple · %s\n' "$(size_range "$(audio_est 96)" "$(audio_est 256)")"
    printf 'opus|OPUS|melhor qualidade por tamanho · %s\n' "$(size_range "$(audio_est 64)" "$(audio_est 160)")"
    printf 'flac|FLAC|sem perdas, arquivo grande · %s\n' "$(fmt_size "$(lossless_est 0.6)")"
    printf 'wav|WAV|sem compressão, arquivo enorme · %s\n' "$(fmt_size "$(lossless_est 1)")"
}

audio_quality_rows() {   # $1 = mp3|m4a|opus
    local list k
    case "$1" in
        mp3) list="320:máxima 256:muito_boa 192:recomendada 128:compacta 96:mínima" ;;
        m4a) list="256:máxima 192:recomendada 128:compacta 96:mínima" ;;
        *) list="160:máxima 128:recomendada 96:compacta 64:mínima" ;;
    esac
    for k in $list; do
        printf '%s|%s kbps — %s|%s\n' "${k%%:*}" "${k%%:*}" "$(tr _ ' ' <<<"${k#*:}")" "$(fmt_size "$(audio_est "${k%%:*}")")"
    done
}

pick_audio() {
    local af aq def fdef qdef
    YFALLBACK=""
    PICK_AFMT=""; PICK_AQ=""
    fdef="$(pref_default audio_fmt)"
    qdef="$(pref_default audio_q)"
    while true; do
        af="$(audio_format_rows | ui_choose "Música — formato" "$(info_text)" "${fdef:-mp3}" "Formato" "Detalhes e tamanho estimado")" || return 1
        case "$af" in
            orig | flac | wav) aq=""; break ;;
        esac
        case "$af" in opus) def=128 ;; *) def=192 ;; esac
        [ -n "$qdef" ] && def="$qdef"
        aq="$(audio_quality_rows "$af" | ui_choose "Música — qualidade ($af)" "$(info_text)" "$def" "Qualidade" "Tamanho estimado")" && break
    done
    PICK_AFMT="$af"; PICK_AQ="$aq"
    case "$af" in
        orig)
            YARGS=(-f "${BA_ID}/ba/b" -x --audio-format best)
            YFALLBACK="ba/b"
            SEL_LABEL="Original ($BA_EXT${BA_ABR:+, ~$BA_ABR kbps}), sem reconverter"
            SEL_BYTES="$BA_BYTES" ;;
        flac)
            YARGS=(-f "ba/b" -x --audio-format flac --embed-thumbnail --convert-thumbnails jpg)
            SEL_LABEL="FLAC (sem perdas)"
            SEL_BYTES="$(lossless_est 0.6)" ;;
        wav)
            YARGS=(-f "ba/b" -x --audio-format wav)
            SEL_LABEL="WAV (sem compressão)"
            SEL_BYTES="$(lossless_est 1)" ;;
        *)
            YARGS=(-f "ba/b" -x --audio-format "$af" --audio-quality "${aq}K" --embed-thumbnail --convert-thumbnails jpg)
            SEL_LABEL="${af^^} · ${aq} kbps"
            SEL_BYTES="$(audio_est "$aq")" ;;
    esac
    YARGS+=(--embed-metadata --no-playlist -o "%(title)s.%(ext)s" --trim-filenames 180 -P "$DEST")
    return 0
}

load_vrows() { mapfile -t VROWS < <(jq -r --arg cont "$1" -f "$APP_SHARE/rows.jq" "$WORKD/info.json" 2>/dev/null); }

video_container_rows() {
    local c mn mx top desc
    for c in mp4 mkv webm; do
        load_vrows "$c"
        [ "${#VROWS[@]}" -gt 0 ] || continue
        IFS='|' read -r mn mx <<<"$(printf '%s\n' "${VROWS[@]}" | minmax)"
        top="${VROWS[0]%%|*}"
        case "$c" in
            mp4) desc="funciona em tudo (celular, TV, WhatsApp)" ;;
            mkv) desc="qualidade máxima, qualquer codec" ;;
            *) desc="formato aberto (VP9), bom para computador" ;;
        esac
        printf '%s|%s|%s · até %sp · %s\n' "$c" "${c^^}" "$desc" "$top" "$(size_range "$mn" "$mx")"
    done
}

pick_video() {
    local c row i def pick n h lab bytes vv va sel asel cdef hmax
    YFALLBACK=""
    PICK_VCONT=""; PICK_VH=""
    cdef="$(pref_default video_cont)"
    hmax="$(pref_default video_h)"
    case "$hmax" in '' | *[!0-9]*) hmax=1080 ;; esac
    local -a out=()
    n="$(video_container_rows | wc -l)"
    if [ "$n" -eq 0 ]; then
        # site sem detalhes de qualidade: baixa o melhor disponível
        SEL_LABEL="melhor qualidade disponível (MP4)"
        SEL_BYTES=""
        YARGS=(-f "bv*+ba/b" --merge-output-format mp4 --embed-metadata --no-playlist \
            -o "%(title)s.%(ext)s" --trim-filenames 180 -P "$DEST")
        return 0
    fi
    while true; do
        c="$(video_container_rows | ui_choose "Vídeo — formato" "$(info_text)" "$cdef" "Formato" "Detalhes e tamanho estimado")" || return 1
        load_vrows "$c"
        out=()
        def=""
        i=0
        for row in "${VROWS[@]}"; do
            i=$((i + 1))
            IFS='|' read -r h lab bytes _ <<<"$row"
            if [ -z "$def" ] && [ "${h:-0}" -le "$hmax" ]; then def="$i"; fi
            out+=("$i|$lab|$(fmt_size "$bytes")")
        done
        [ -n "$def" ] || def=1
        pick="$(printf '%s\n' "${out[@]}" | ui_choose "Vídeo — qualidade (${c^^})" "$(info_text)" "$def" "Qualidade" "Tamanho estimado")" && break
    done
    IFS='|' read -r h lab SEL_BYTES vv va <<<"${VROWS[$((pick - 1))]}"
    PICK_VCONT="$c"; PICK_VH="$h"
    sel="$vv${va:+"+$va"}"
    SEL_LABEL="${c^^} · $lab"
    YARGS=(-f "$sel/bv*[height<=$h]+ba/b[height<=$h]" --merge-output-format "$c" --remux-video "$c" \
        --embed-metadata --no-playlist -o "%(title)s.%(ext)s" --trim-filenames 180 -P "$DEST")
    # Plano B se der erro (ex.: 403 numa faixa de áudio): mantém o MESMO vídeo e deixa o yt-dlp
    # escolher o áudio sozinho (ele prefere a faixa original); sem áudio separado, tudo automático.
    case "$c" in mp4) asel="ba[ext=m4a]/ba" ;; webm) asel="ba[ext=webm]/ba" ;; *) asel="ba" ;; esac
    if [ -n "$va" ]; then
        YFALLBACK="$vv+$asel/bv*[height<=$h]+ba/b[height<=$h]"
    else
        YFALLBACK="bv*[height<=$h]+ba/b[height<=$h]"
    fi
    if [ "${BATCH_N:-1}" -gt 1 ]; then
        YFALLBACK=""
        # vários itens: os códigos de formato do 1º vídeo não valem para os outros,
        # então pede a mesma altura (e o mesmo tipo de codec) em cada um
        case "$c" in
            mp4) YARGS[1]="bv*[height<=$h][vcodec^=avc]+ba[ext=m4a]/bv*[height<=$h][ext=mp4]+ba/bv*[height<=$h]+ba/b[height<=$h]" ;;
            webm) YARGS[1]="bv*[height<=$h][ext=webm]+ba[ext=webm]/bv*[height<=$h]+ba/b[height<=$h]" ;;
            *) YARGS[1]="bv*[height<=$h]+ba/b[height<=$h]" ;;
        esac
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Legendas (só em vídeo, sem recorte): baixar e embutir ou salvar em .srt
# ---------------------------------------------------------------------------
PICK_SUBS=""; PICK_SMODE=""

subs_avail() {   # $1 = prefixo do idioma (pt, en) -> m (do autor) | a (automática) | n (não achei)
    [ "${BATCH_N:-1}" -eq 1 ] && [ -s "$WORKD/info.json" ] || { printf '?'; return 0; }
    jq -r --arg p "$1" '
        (((.subtitles // {}) | keys) | map(select(startswith($p))) | length) as $m
        | (((.automatic_captions // {}) | keys) | map(select(startswith($p))) | length) as $a
        | if $m > 0 then "m" elif $a > 0 then "a" else "n" end' "$WORKD/info.json" 2>/dev/null || printf '?'
}
subs_note() {   # prefixo -> texto curto
    case "$(subs_avail "$1")" in
        m) printf 'legenda feita pelo autor' ;;
        a) printf 'só legenda automática (pode ter erros)' ;;
        n) printf 'não encontrei neste vídeo' ;;
        *) printf 'se o vídeo tiver' ;;
    esac
}

subs_expr() {   # pt | en | pten | other:es,fr  ->  "pt.*,en.*"
    local c="${1#other:}" out="" x
    case "$1" in
        pt) echo 'pt.*' ; return ;;
        en) echo 'en.*' ; return ;;
        pten) echo 'pt.*,en.*' ; return ;;
    esac
    c="$(printf '%s' "$c" | tr -cd 'A-Za-z,-')"
    local IFS=,
    for x in $c; do [ -n "$x" ] && out="${out:+$out,}$x.*"; done
    printf '%s' "$out"
}
subs_name() {
    case "$1" in
        pt) echo 'português' ;;
        en) echo 'inglês' ;;
        pten) echo 'português e inglês' ;;
        other:*) echo "${1#other:}" ;;
    esac
}

pick_subs() {   # depois de pick_video: acrescenta as opções de legenda em YARGS. rc 1 = voltar
    local c d m mdef codes ex expr cont
    PICK_SUBS=""; PICK_SMODE=""
    [ "$CLIP_ON" = 1 ] && return 0           # com recorte as legendas não acompanham o trecho
    [ -n "$PICK_VCONT" ] || return 0         # sem detalhes de qualidade, não mexe
    d="$(pref_default subs)"; mdef="$(pref_default subs_mode)"
    case "$d" in other:*) ex="${d#other:}"; d=other ;; esac
    c="$(printf '%s\n' \
        "none|Sem legendas|só o vídeo" \
        "pt|Português|$(subs_note pt)" \
        "en|Inglês|$(subs_note en)" \
        "pten|Português e inglês|baixa as duas" \
        "other|Outro idioma…|você digita o código (es, fr, ja…)" |
        ui_choose "Vídeo — legendas" "$(info_text)

Quer baixar legendas junto com o vídeo?" "${d:-none}" "Legendas" "Situação neste vídeo")" || return 1
    if [ "$c" = other ]; then
        ex="$(ui_entry "Legendas" "Código(s) do idioma, separados por vírgula (exemplos: es  ou  es,fr  ou  ja):" "${ex:-es}")" || return 1
        ex="$(printf '%s' "$ex" | tr -cd 'A-Za-z,-')"
        [ -n "$ex" ] || return 0
        c="other:$ex"
    fi
    PICK_SUBS="$c"
    [ "$c" = none ] && return 0
    m="$(printf '%s\n' \
        "embed|Embutida no vídeo|aparece no player; dá para ligar e desligar" \
        "file|Arquivo .srt separado|fica ao lado do vídeo, com o mesmo nome" |
        ui_choose "Vídeo — legendas" "Como guardar as legendas?" "${mdef:-embed}" "Modo" "Resultado")" || return 1
    PICK_SMODE="$m"
    expr="$(subs_expr "$c")"
    YARGS+=(--write-subs --write-auto-subs --sub-langs "$expr")
    cont="${PICK_VCONT:-mp4}"
    if [ "$m" = embed ]; then
        YARGS+=(--embed-subs)
        [ "$cont" = webm ] && YARGS+=(--sub-format "vtt/best") || YARGS+=(--convert-subs srt)
        SEL_LABEL="$SEL_LABEL · legendas: $(subs_name "$c") (embutidas)"
    else
        YARGS+=(--convert-subs srt)
        SEL_LABEL="$SEL_LABEL · legendas: $(subs_name "$c") (arquivo .srt)"
    fi
    return 0
}

# ydl_try URL [argumentos extras]: baixa com YARGS; se falhar e houver plano B (YFALLBACK),
# tenta mais uma vez com ele (o que já foi baixado é reaproveitado pelo yt-dlp).
ydl_try() {
    local url="$1" nl=() rc fb=()
    shift
    [ "$UI" = gui ] && nl=(--newline)
    "$YTDLP" "${FFARGS[@]}" "${nl[@]}" "${YARGS[@]}" "$@" \
        --print-to-file "after_move:filepath" "$SAVED" "$url" </dev/null
    rc=$?
    if [ "$rc" -ne 0 ] && [ -n "$YFALLBACK" ]; then
        printf '\nA primeira tentativa falhou; tentando de outro jeito...\n'
        [ "${RUN_KIND:-}" = dl ] && printf '%s' "Tentando de outro jeito…" >"$WORKD/runtext"
        fb=("${YARGS[@]}")
        fb[1]="$YFALLBACK"
        "$YTDLP" "${FFARGS[@]}" "${nl[@]}" "${fb[@]}" "$@" \
            --print-to-file "after_move:filepath" "$SAVED" "$url" </dev/null
        rc=$?
    fi
    return $rc
}

download_job() { ydl_try "$DL_URL"; }

# ---------------------------------------------------------------------------
# Vários links, playlists e fila de downloads
# ---------------------------------------------------------------------------
ITEM_URL=(); ITEM_TITLE=(); ITEM_DUR=(); ITEM_GROUP=(); ITEM_SRC=()
QSEL=(); BATCH_N=1; NLINKS=0

# Lê cada link (sem baixar nada) e guarda o JSON em $WORKD/x<N>.json
expand_job() {
    local u i=0 msg
    : >"$WORKD/xfail.txt"
    while IFS= read -r u; do
        i=$((i + 1))
        msg="Lendo o link $i de $NLINKS…"
        [ "$NLINKS" -eq 1 ] && msg="Buscando informações do link…"
        printf '%s' "$msg" >"$WORKD/runtext"
        if ! "$YTDLP" "${FFARGS[@]}" --flat-playlist --no-playlist --no-warnings -J "$u" \
            >"$WORKD/x$i.json" </dev/null; then
            printf '%s\n' "$u" >>"$WORKD/xfail.txt"
            rm -f "$WORKD/x$i.json"
        fi
    done <"$WORKD/links.list"
}

# Monta a lista de itens (ITEM_*) a partir dos JSON lidos. Playlist vira vários itens.
build_items() {
    local i=0 u url title dur grp
    ITEM_URL=(); ITEM_TITLE=(); ITEM_DUR=(); ITEM_GROUP=(); ITEM_SRC=()
    while IFS= read -r u; do
        i=$((i + 1))
        [ -s "$WORKD/x$i.json" ] || continue
        jq -e . "$WORKD/x$i.json" >/dev/null 2>&1 || continue
        while IFS=$'\t' read -r url title dur grp; do
            case "$url" in http://* | https://*) ;; *) continue ;; esac
            [ "$grp" = "-" ] && grp=""
            ITEM_URL+=("$url")
            ITEM_TITLE+=("$title")
            ITEM_DUR+=("${dur:-0}")
            ITEM_GROUP+=("$grp")
            ITEM_SRC+=("$i")
        done < <(jq -r --arg u "$u" -f "$APP_SHARE/items.jq" "$WORKD/x$i.json" 2>/dev/null)
    done <"$WORKD/links.list"
}

# Deixa escolher quais itens baixar (todos vêm marcados). Preenche QSEL com os índices.
select_items() {
    local i n="${#ITEM_URL[@]}" rows="" dur lab g sel
    for ((i = 0; i < n; i++)); do
        dur="—"
        is_pos "${ITEM_DUR[$i]}" && dur="$(fmt_dur "${ITEM_DUR[$i]}")"
        lab="${ITEM_TITLE[$i]//|//}"
        g="${ITEM_GROUP[$i]}"
        rows+="$i|$lab|$dur${g:+ · $g}"$'\n'
    done
    while true; do
        sel="$(printf '%s' "$rows" | ui_checklist "Zapt" \
            "Encontrei $n itens. Todos já vêm marcados; desmarque os que você não quer baixar." \
            "Título" "Duração")" || return 1
        mapfile -t QSEL <<<"$sel"
        [ -n "${QSEL[0]:-}" ] && return 0
        ui_info "Marque pelo menos um item."
    done
}

fail_read() {
    ui_fail "Zapt: não consegui ler o link" "Não consegui ler este link. Confira o endereço.
Se for do YouTube e o erro for 403 ou de acesso, use Mais opções > Atualizar para a versão nightly."
}

# Baixa os itens de QSEL, um de cada vez, com as opções já escolhidas em YARGS
queue_job() {
    local i k=0 n="${#QSEL[@]}" grp=()
    : >"$WORKD/qfail.txt"
    for i in "${QSEL[@]}"; do
        k=$((k + 1))
        echo "$k/$n" >"$WORKD/stage"
        printf 'Baixando %s de %s: %s' "$k" "$n" "${ITEM_TITLE[$i]}" >"$WORKD/runtext"
        printf '\n[[ITEM %s/%s]] %s\n' "$k" "$n" "${ITEM_TITLE[$i]}"
        grp=()
        [ -n "${ITEM_GROUP[$i]}" ] && grp=(-P "$DEST/${ITEM_GROUP[$i]}")
        ydl_try "${ITEM_URL[$i]}" "${grp[@]}" || printf '%s\n' "${ITEM_TITLE[$i]}" >>"$WORKD/qfail.txt"
    done
    return 0
}

batch_download() {   # depois do queue_job: mostra o resumo
    local rc nfail=0 nsaved=0 total=0 f n="${#QSEL[@]}" text est
    RUN_KIND=dlq ui_run "Baixando…" queue_job
    rc=$?
    [ -s "$WORKD/qfail.txt" ] && nfail="$(wc -l <"$WORKD/qfail.txt")"
    if [ -s "$SAVED" ]; then
        nsaved="$(grep -c . "$SAVED")"
        while IFS= read -r f; do
            [ -f "$f" ] && total=$((total + $(stat -c %s "$f")))
        done <"$SAVED"
    fi
    if [ "$rc" -eq 130 ]; then
        ui_info "Cancelado. Os $nsaved itens que já tinham sido baixados continuam em: $DEST"
        return 0
    fi
    if [ "$nfail" -eq 0 ]; then
        text="Pronto! $n itens baixados."
    else
        text="Pronto! $((n - nfail)) de $n itens baixados."
    fi
    est="$(scale_b "${SEL_BYTES:-0}")"
    text+="
Tamanho total: $(fmt_mb "$total")"
    if [ "$nfail" -eq 0 ] && [ "$nsaved" -eq "$n" ]; then
        text+="$(size_diff "$est" "$total")"
        record_size baixar-lote "$SEL_LABEL ($n itens)" "$est" "$total"
    fi
    text+="
Pasta: $DEST"
    if [ "$nfail" -gt 0 ]; then
        text+="

Não consegui baixar $nfail:
$(head -n 10 "$WORKD/qfail.txt" | sed 's/^/ • /')"
        [ "$nfail" -gt 10 ] && text+="
  …e mais $((nfail - 10))."
        text+="

DICA: erros 403 do YouTube costumam ser passageiros; tente de novo.
Se persistir, use Mais opções > Atualizar para a versão nightly."
    fi
    ui_info "$text"
}

download_main() {   # $1 = musica|video (vazio = pergunta)
    local mode="${1:-}" txt rc text n i first tries nfail note mult real est clip_line
    mkwork
    SIZE_MULT=1; BATCH_N=1

    txt="$(ui_links "Cole o link do vídeo ou da música. Dá para colar vários links (um por linha) e também links de playlist.")" || return 0
    printf '%s\n' "$txt" | links_from_text >"$WORKD/links.list"
    NLINKS="$(wc -l <"$WORKD/links.list")"
    [ "$NLINKS" -gt 0 ] || return 0
    if [ -z "$mode" ]; then
        mode="$(printf '%s\n' 'musica|Música|somente o áudio' 'video|Vídeo|imagem e som' |
            ui_choose "Zapt" "O que você quer baixar?" musica "Tipo" "Detalhes")" || return 0
    fi

    RUN_KIND=pulse ui_run "Lendo o link…" expand_job
    rc=$?
    [ "$rc" -eq 130 ] && return 0
    build_items
    nfail="$(wc -l <"$WORKD/xfail.txt")"
    if [ "${#ITEM_URL[@]}" -eq 0 ]; then
        fail_read
        return 0
    fi
    if [ "$nfail" -gt 0 ]; then
        ui_info "Não consegui ler $nfail dos links; sigo com os outros:
$(sed 's/^/ • /' "$WORKD/xfail.txt")"
    fi

    # quais itens baixar
    if [ "${#ITEM_URL[@]}" -eq 1 ]; then QSEL=(0); else select_items || return 0; fi
    n="${#QSEL[@]}"

    if [ "$n" -eq 1 ]; then
        i="${QSEL[0]}"
        if [ -z "${ITEM_GROUP[$i]}" ]; then
            cp "$WORKD/x${ITEM_SRC[$i]}.json" "$WORKD/info.json"   # link solto: o JSON já é o completo
        else
            RUN_KIND=pulse ui_run "Buscando informações do vídeo…" fetch_info_job "${ITEM_URL[$i]}"
            rc=$?
            [ "$rc" -eq 130 ] && return 0
            [ "$rc" -eq 0 ] || { fail_read; return 0; }
        fi
        parse_info || { fail_read; return 0; }
        if [ "$I_TYPE" = playlist ]; then
            ui_info "Este link leva a outra lista de vídeos. Abra a lista no navegador e cole o link de cada playlist."
            return 0
        fi
    else
        # vários itens: usa o primeiro que responder como exemplo para as opções e tamanhos
        BATCH_N="$n"
        first=-1
        tries=0
        for i in "${QSEL[@]}"; do
            tries=$((tries + 1))
            [ "$tries" -gt 3 ] && break
            RUN_KIND=pulse ui_run "Lendo as opções de qualidade…" fetch_info_job "${ITEM_URL[$i]}"
            rc=$?
            [ "$rc" -eq 130 ] && return 0
            if [ "$rc" -eq 0 ] && parse_info && [ "$I_TYPE" != playlist ]; then first="$i"; break; fi
        done
        if [ "$first" -lt 0 ]; then fail_read; return 0; fi
        # total estimado = tamanho do 1º item × (soma das durações ÷ duração do 1º)
        mult="$(for i in "${QSEL[@]}"; do echo "${ITEM_DUR[$i]}"; done |
            awk -v d="$I_DUR" '{ s += ($1 + 0 > 0 && d + 0 > 0) ? $1 / d : 1 } END { printf "%.4f", s }')"
        SIZE_MULT="$mult"
    fi

    # recorte (só quando é um item; em lote não faz sentido o mesmo trecho para todos)
    CLIP_ON=0
    if [ "$n" -eq 1 ]; then
        choose_clip "$(info_text)" "$I_DUR" || return 0
        if [ "$CLIP_ON" = 1 ] && is_pos "$I_DUR" && is_pos "$CLIP_DUR"; then
            SIZE_MULT="$(awk -v c="$CLIP_DUR" -v d="$I_DUR" 'BEGIN { printf "%.4f", c / d }')"
        fi
    fi

    DEST="$(dest_for "$mode")"
    note=""
    for i in "${QSEL[@]}"; do
        [ -n "${ITEM_GROUP[$i]}" ] && { note=" (playlists em subpastas com o nome da lista)"; break; }
    done
    while true; do
        if [ "$mode" = musica ]; then
            pick_audio || return 0
        else
            pick_video || return 0
            pick_subs || continue
        fi
        apply_clip_args
        if [ "$n" -gt 1 ]; then
            text="Baixar $n itens com estas opções?

Formato: $SEL_LABEL
Tamanho total estimado: $(fmt_size "$SEL_BYTES")
Salvar em: $DEST$note"
        else
            clip_line=""
            [ "$CLIP_ON" = 1 ] && clip_line="$(clip_text)
"
            text="Baixar com estas opções?

Título: $I_TITLE
${clip_line}Formato: $SEL_LABEL
Tamanho estimado: $(fmt_size "$SEL_BYTES")
Salvar em: $DEST"
            [ "$CLIP_ON" = 1 ] && text="$text

O recorte baixa só esse pedaço, mas pode levar um pouco mais de tempo."
        fi
        ui_confirm "$text" "Baixar" "Voltar" && break
    done
    remember_picks "$mode"

    SAVED="$WORKD/saved.txt"
    : >"$SAVED"
    if [ "$n" -gt 1 ]; then
        batch_download
        return 0
    fi

    DL_URL="${ITEM_URL[${QSEL[0]}]}"
    RUN_KIND=dl ui_run "Baixando…" download_job
    rc=$?
    [ "$rc" -eq 130 ] && return 0
    if [ "$rc" -ne 0 ]; then
        ui_fail "Zapt: erro ao baixar" "DICA: erros 403 do YouTube costumam ser passageiros. Tente de novo.
Se persistir, volte ao menu e use: Mais opções > Atualizar para a versão nightly."
        return 0
    fi
    LAST_FILE="$(tail -n1 "$SAVED")"
    if [ -f "$LAST_FILE" ]; then
        real="$(stat -c %s "$LAST_FILE")"
        est="$(scale_b "${SEL_BYTES:-0}")"
        record_size baixar "$SEL_LABEL" "$est" "$real"
        if ui_confirm "Pronto!

$(basename "$LAST_FILE")
Tamanho final: $(fmt_mb "$real")$(size_diff "$est" "$real")
Pasta: $(dirname "$LAST_FILE")

Quer converter para compartilhar (Discord, WhatsApp...)?" "Converter…" "Fechar" n; then
            flow_convert "$LAST_FILE"
        fi
    else
        ui_info "Pronto! Salvo em: $DEST"
    fi
}

flow_download() {   # $1 = musica|video (vazio = pergunta)
    local rc
    download_main "$@"
    rc=$?
    SIZE_MULT=1; BATCH_N=1; CLIP_ON=0
    return $rc
}

# ---------------------------------------------------------------------------
# Conversão para compartilhar (Discord, WhatsApp, redes sociais...)
# ---------------------------------------------------------------------------
P_DUR=0; P_SIZE=0; P_KIND=""; P_W=0; P_H=0; P_SHORT=0; P_VCODEC=""; P_ACODEC=""
P_VBR=0; P_FPS=0; P_VIDX=""; P_PICIDX=""; P_EXT=""
PL_SHORT=0; PL_VK=0; PL_AK=0; PL_EST=0; PL_MODE=""; PL_FPS30=0; PL_LOW=0
PA_K=0; PA_EST=0; PA_LOW=0
PR_NAME=""; PR_SFX=""; PR_LIM=0; PR_K=0; CUSTOM_LIM=""
CONV_IN=""; CV_KIND=""; CV_OUT=""; CV_DESC=""; CV_EST=0; CV_LOW=0; CV_ACTUAL=""

probe_file() {   # $1 = arquivo -> P_*
    local f="$1" j
    mkwork
    j="$WORKD/probe.json"
    ffprobe -v error -print_format json -show_format -show_streams "$f" >"$j" 2>/dev/null || return 1
    P_SIZE="$(stat -c %s "$f")"
    local P_VBR_RAW P_ABR P_FMTBR
    eval "$(jq -r '
        def num: if . == null then 0 else (tonumber? // 0) end;
        ([.streams[] | select(.codec_type == "video" and ((.disposition.attached_pic // 0) == 0))][0]) as $v
        | ([.streams[] | select(.codec_type == "video" and ((.disposition.attached_pic // 0) == 1))][0]) as $p
        | ([.streams[] | select(.codec_type == "audio")][0]) as $a
        | [ "P_DUR=\((.format.duration | num) | @sh)",
            "P_KIND=\((if $v then "video" else "audio" end) | @sh)",
            "P_VIDX=\(($v.index // "") | @sh)",
            "P_PICIDX=\(($p.index // "") | @sh)",
            "P_W=\(($v.width // 0) | @sh)",
            "P_H=\(($v.height // 0) | @sh)",
            "P_VCODEC=\(($v.codec_name // "") | @sh)",
            "P_ACODEC=\(($a.codec_name // "") | @sh)",
            "P_VBR_RAW=\((($v.bit_rate | num) / 1000) | @sh)",
            "P_ABR=\((($a.bit_rate | num) / 1000) | @sh)",
            "P_FMTBR=\(((.format.bit_rate | num) / 1000) | @sh)",
            "P_FPS=\((($v.avg_frame_rate // "0/1") | split("/") | ((.[0] | num) / ((.[1] | num) | if . == 0 then 1 else . end))) | @sh)"
          ] | join("\n")' "$j")"
    P_SHORT=$((P_W < P_H ? P_W : P_H))
    P_VBR="$(awk -v r="$P_VBR_RAW" -v f="$P_FMTBR" -v a="$P_ABR" -v s="$P_SIZE" -v d="$P_DUR" 'BEGIN {
        if (r > 0) v = r; else if (f > 0) v = f - a; else if (d > 0) v = s * 8 / d / 1000 - a; else v = 0;
        if (v < 0) v = 0; printf "%d", v }')"
    return 0
}

# plan_video LIMITE_MB(0 = sem limite) [MARGEM]  ->  PL_*
plan_video() {
    local out
    out="$(awk -v D="$P_DUR" -v L="$1" -v M="${2:-0.92}" -v SS="$P_SHORT" -v SVK="$P_VBR" \
        -v HA="$([ -n "$P_ACODEC" ] && echo 1 || echo 0)" -v FPS="$P_FPS" 'BEGIN {
        n = split("1080 720 480 360 240", T, " ")
        split("2800 1300 650 350 180", TH, " ")      # kbps mínimos para cada resolução
        split("6000 3500 1600 900 500", CAP, " ")    # teto de kbps no modo "sem limite"
        low = 0
        if (L > 0) {
            total = L * 1e6 * M * 8 / D / 1000
            ak = HA ? ((total < 500) ? 64 : ((total < 1200) ? 96 : 128)) : 0
            vk = total - ak
            sel = n
            for (i = 1; i <= n; i++) if (T[i] <= SS + 1 && vk >= TH[i]) { sel = i; break }
            if (vk < TH[n]) low = 1
            mode = "twopass"
        } else {
            sel = n
            for (i = 1; i <= n; i++) if (T[i] <= SS + 1) { sel = i; break }
            ak = HA ? 128 : 0
            vk = CAP[sel]
            mode = "crf"
        }
        if (SVK > 0 && vk > SVK * 1.3) vk = SVK * 1.3     # não faz sentido passar da taxa do original
        if (vk < 50) vk = 50
        outs = T[sel]
        if (SS > 0 && SS < outs) outs = SS                  # nunca aumenta a resolução
        fps30 = (L > 0 && FPS > 30.5) ? 1 : 0
        est = (vk + ak) * 1000 / 8 * D * 1.01
        printf "%d %d %d %d %s %d %d", outs, vk, ak, est, mode, fps30, low }')"
    read -r PL_SHORT PL_VK PL_AK PL_EST PL_MODE PL_FPS30 PL_LOW <<<"$out"
}

# plan_audio KBPS_FIXO LIMITE_MB(0 = usa KBPS_FIXO) -> PA_*
plan_audio() {
    local out
    out="$(awk -v D="$P_DUR" -v K="$1" -v L="$2" 'BEGIN {
        low = 0
        if (L > 0) { k = int(L * 1e6 * 0.95 * 8 / D / 1000); if (k > 192) k = 192; if (k < 64) low = 1; if (k < 32) k = 32 }
        else k = K
        printf "%d %d %d", k, k * 125 * D * 1.01, low }')"
    read -r PA_K PA_EST PA_LOW <<<"$out"
}

fits_already() {   # vídeo: já é MP4/H.264/AAC e já cabe no limite ($1 em MB)?
    is_pos "$1" || return 1
    [ "$CLIP_ON" = 1 ] && return 1     # com recorte sempre é preciso converter
    [ "$P_KIND" = video ] && [ "$P_VCODEC" = h264 ] && { [ -z "$P_ACODEC" ] || [ "$P_ACODEC" = aac ]; } || return 1
    case "${P_EXT,,}" in mp4 | m4v) ;; *) return 1 ;; esac
    awk -v s="$P_SIZE" -v l="$1" 'BEGIN { exit !(s <= l * 1e6 * 0.98) }'
}
fits_already_audio() {
    is_pos "$1" || return 1
    [ "$CLIP_ON" = 1 ] && return 1
    [ "$P_KIND" = audio ] && [ "$P_ACODEC" = mp3 ] || return 1
    awk -v s="$P_SIZE" -v l="$1" 'BEGIN { exit !(s <= l * 1e6 * 0.98) }'
}

preset_info() {   # id -> PR_*
    PR_K=0
    case "$1" in
        discord) PR_NAME="Discord — conta grátis"; PR_SFX="discord"; PR_LIM=$LIM_DISCORD ;;
        discord50) PR_NAME="Discord — Nitro Basic"; PR_SFX="discord"; PR_LIM=$LIM_DISCORD_BASIC ;;
        whatsapp) PR_NAME="WhatsApp"; PR_SFX="whatsapp"; PR_LIM=$LIM_WHATSAPP ;;
        social) PR_NAME="Redes sociais — alta qualidade"; PR_SFX="social"; PR_LIM=0 ;;
        mp3_192) PR_NAME="MP3 192 kbps"; PR_SFX="mp3-192"; PR_LIM=0; PR_K=192 ;;
        mp3_128) PR_NAME="MP3 128 kbps"; PR_SFX="mp3-128"; PR_LIM=0; PR_K=128 ;;
        audio) PR_NAME="Só o áudio, em MP3"; PR_SFX="audio"; PR_LIM=0; PR_K=128 ;;
        custom) PR_NAME="Limite personalizado"; PR_SFX="compacto"; PR_LIM="$CUSTOM_LIM" ;;
    esac
}

preset_label() {   # nome com o limite entre parênteses
    if is_pos "$PR_LIM" && [ "$1" != custom ]; then printf '%s (até %s MB)' "$PR_NAME" "$PR_LIM"; else printf '%s' "$PR_NAME"; fi
}

conv_video_desc() {   # $1 = limite em MB (0 = sem limite)
    local est
    if fits_already "$1"; then
        printf 'já cabe: o original tem %s, não precisa converter' "$(fmt_mb "$P_SIZE")"
        return
    fi
    plan_video "$1"
    if [ "$PL_MODE" = twopass ]; then est="≈ $(fmt_mb "$PL_EST")"; else est="até $(fmt_mb "$PL_EST")"; fi
    printf 'MP4 · %sp · %s' "$PL_SHORT" "$est"
    if [ "$PL_LOW" = 1 ]; then printf ' · vídeo longo: qualidade baixa'; fi
}

conv_audio_desc() {   # $1 = kbps fixo, $2 = limite em MB
    if fits_already_audio "$2"; then
        printf 'já cabe: o original tem %s, não precisa converter' "$(fmt_mb "$P_SIZE")"
        return
    fi
    plan_audio "$1" "$2"
    printf 'MP3 · %s kbps · ≈ %s' "$PA_K" "$(fmt_mb "$PA_EST")"
    if [ "$PA_LOW" = 1 ]; then printf ' · áudio longo: qualidade baixa'; fi
}

conv_video_rows() {
    local id
    for id in discord discord50 whatsapp social; do
        preset_info "$id"
        printf '%s|%s|%s\n' "$id" "$(preset_label "$id")" "$(conv_video_desc "$PR_LIM")"
    done
    printf 'custom|Outro limite de tamanho…|você escolhe o tamanho máximo em MB\n'
    if [ -n "$P_ACODEC" ]; then
        plan_audio 128 0
        printf 'audio|Só o áudio, em MP3|MP3 · 128 kbps · ≈ %s\n' "$(fmt_mb "$PA_EST")"
    fi
}

conv_audio_rows() {
    local id
    for id in mp3_192 mp3_128; do
        preset_info "$id"
        printf '%s|%s|%s\n' "$id" "$PR_NAME" "$(conv_audio_desc "$PR_K" 0)"
    done
    for id in discord discord50 whatsapp; do
        preset_info "$id"
        printf '%s|%s|%s\n' "$id" "$(preset_label "$id")" "$(conv_audio_desc 0 "$PR_LIM")"
    done
    printf 'custom|Outro limite de tamanho…|você escolhe o tamanho máximo em MB\n'
}

out_path() {   # arquivo sufixo extensão -> caminho livre ao lado do original
    local dir base cand n=0
    dir="$(dirname "$1")"
    base="$(basename "${1%.*}")"
    cand="$dir/$base ($2).$3"
    while [ -e "$cand" ]; do
        n=$((n + 1))
        cand="$dir/$base ($2 $n).$3"
    done
    printf '%s' "$cand"
}

ff() {   # ffmpeg com progresso: em arquivo (janelas) ou na tela (terminal)
    if [ "$UI" = gui ]; then
        : >"$WORKD/prog"
        ffmpeg -hide_banner -nostdin -loglevel error -nostats -progress "$WORKD/prog" "$@"
    else
        ffmpeg -hide_banner -nostdin -loglevel error -stats "$@"
    fi
}

encode_video_cpu() {   # entrada saída   (usa PL_*)
    local in="$1" out="$2" tmp vf="" vfa=() aa amap=()
    tmp="${out%.*}.parcial.mp4"
    if [ "$PL_SHORT" -lt "$P_SHORT" ]; then
        vf="scale='if(gt(iw,ih),-2,$PL_SHORT)':'if(gt(iw,ih),$PL_SHORT,-2)'"
    fi
    if [ "$PL_FPS30" = 1 ]; then vf="${vf:+$vf,}fps=30"; fi
    [ -n "$vf" ] && vfa=(-vf "$vf")
    if [ "$PL_AK" -gt 0 ]; then
        aa=(-c:a aac -b:a "${PL_AK}k" -ac 2)
        amap=(-map "0:a:0?")
    else
        aa=(-an)
    fi
    if [ "$PL_MODE" = twopass ]; then
        echo "1/2" >"$WORKD/stage"
        ff -y "${CLIP_IN[@]}" -i "$in" -map "0:$P_VIDX" "${vfa[@]}" -c:v libx264 -preset fast -profile:v high -pix_fmt yuv420p \
            -b:v "${PL_VK}k" -pass 1 -passlogfile "$WORKD/pass" -an -f null /dev/null || { rm -f "$tmp"; return 1; }
        echo "2/2" >"$WORKD/stage"
        ff -y "${CLIP_IN[@]}" -i "$in" -map "0:$P_VIDX" "${amap[@]}" "${vfa[@]}" -c:v libx264 -preset fast -profile:v high -pix_fmt yuv420p \
            -b:v "${PL_VK}k" -pass 2 -passlogfile "$WORKD/pass" "${aa[@]}" -movflags +faststart "$tmp" || { rm -f "$tmp"; return 1; }
    else
        echo "1/1" >"$WORKD/stage"
        ff -y "${CLIP_IN[@]}" -i "$in" -map "0:$P_VIDX" "${amap[@]}" "${vfa[@]}" -c:v libx264 -preset fast -profile:v high -pix_fmt yuv420p \
            -crf 22 -maxrate "${PL_VK}k" -bufsize "$((PL_VK * 2))k" "${aa[@]}" -movflags +faststart "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    mv -f "$tmp" "$out"
}

# ---- aceleração por hardware (VAAPI, GPU Intel/AMD) ----
HW_DEV=""; HW_FELL=0
hw_device() {   # imprime o dispositivo de render, se existir
    local d
    for d in "${ZAPT_DRI:-/dev/dri}"/renderD*; do [ -e "$d" ] && { printf '%s' "$d"; return 0; }; done
    return 1
}
hw_test() {   # codifica 0,3 s de teste na GPU; 0 = funciona
    local d
    d="$(hw_device)" || return 1
    ffmpeg -hide_banner -nostdin -loglevel error -y -vaapi_device "$d" \
        -f lavfi -i testsrc=duration=0.3:size=320x240:rate=25 \
        -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null - >/dev/null 2>&1
}
hw_active() { [ "$(pref_get hw off)" = on ] && [ "$HW_FELL" = 0 ] && HW_DEV="$(hw_device)"; }

encode_video_hw() {   # entrada saída   (usa PL_*; uma passada só)
    local in="$1" out="$2" tmp vf="" aa amap=()
    tmp="${out%.*}.parcial.mp4"
    if [ "$PL_SHORT" -lt "$P_SHORT" ]; then
        vf="scale='if(gt(iw,ih),-2,$PL_SHORT)':'if(gt(iw,ih),$PL_SHORT,-2)'"
    fi
    if [ "$PL_FPS30" = 1 ]; then vf="${vf:+$vf,}fps=30"; fi
    vf="${vf:+$vf,}format=nv12,hwupload"
    if [ "$PL_AK" -gt 0 ]; then
        aa=(-c:a aac -b:a "${PL_AK}k" -ac 2)
        amap=(-map "0:a:0?")
    else
        aa=(-an)
    fi
    echo "1/1" >"$WORKD/stage"
    ff -y -vaapi_device "$HW_DEV" "${CLIP_IN[@]}" -i "$in" -map "0:$P_VIDX" "${amap[@]}" -vf "$vf" \
        -c:v h264_vaapi -b:v "${PL_VK}k" -maxrate "${PL_VK}k" -bufsize "$((PL_VK * 2))k" \
        "${aa[@]}" -movflags +faststart "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$out"
}

encode_video() {   # entrada saída: tenta a GPU (se ligada) e cai para a CPU se falhar
    if hw_active; then
        encode_video_hw "$1" "$2" && return 0
        HW_FELL=1
        echo "[zapt] a aceleração por hardware falhou; refazendo pela CPU" >&2
    fi
    encode_video_cpu "$1" "$2"
}

flow_hw_pref() {
    local d msg
    if ! d="$(hw_device)"; then
        ui_info "Não encontrei a placa de vídeo para aceleração (/dev/dri/renderD*).

Em Ubuntu/Zorin com vídeo Intel, instale o driver com:
  sudo apt install intel-media-va-driver-non-free vainfo
e abra o Zapt de novo. Sem isso a conversão segue normal, só mais lenta."
        return 0
    fi
    if [ "$(pref_get hw off)" = on ]; then
        pref_set hw off
        ui_info "Aceleração por hardware desligada. A conversão volta a usar só a CPU."
        return 0
    fi
    mkwork
    if RUN_KIND=pulse ui_run "Testando a placa de vídeo…" hw_test; then
        pref_set hw on
        HW_FELL=0
        msg="Pronto: a aceleração por hardware está ligada ($d).

A conversão de vídeo deve ficar bem mais rápida. O tamanho final pode variar um pouco mais do que na CPU; se passar do limite, o Zapt refaz com margem maior."
    else
        msg="O teste de codificação na placa de vídeo falhou, então deixei desligado.

Em Intel, costuma resolver: sudo apt install intel-media-va-driver-non-free vainfo
Confira com: vainfo"
    fi
    ui_info "$msg"
}

encode_audio() {   # entrada saída   (usa PA_K)
    local in="$1" out="$2" tmp extra=()
    tmp="${out%.*}.parcial.mp3"
    [ "$PA_K" -lt 80 ] && extra=(-ac 1 -ar 44100)
    echo "1/1" >"$WORKD/stage"
    if [ "$P_KIND" = audio ] && [ -n "$P_PICIDX" ]; then
        # mantém a capa do álbum; se não der, tenta de novo sem ela
        ff -y "${CLIP_IN[@]}" -i "$in" -map "0:a:0" -map "0:$P_PICIDX" -c:v copy -c:a libmp3lame -b:a "${PA_K}k" "${extra[@]}" \
            -map_metadata 0 -id3v2_version 3 "$tmp" 2>/dev/null ||
            ff -y "${CLIP_IN[@]}" -i "$in" -vn -map "0:a:0" -c:a libmp3lame -b:a "${PA_K}k" "${extra[@]}" \
                -map_metadata 0 -id3v2_version 3 "$tmp" || { rm -f "$tmp"; return 1; }
    else
        ff -y "${CLIP_IN[@]}" -i "$in" -vn -map "0:a:0" -c:a libmp3lame -b:a "${PA_K}k" "${extra[@]}" \
            -map_metadata 0 -id3v2_version 3 "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    mv -f "$tmp" "$out"
}

conv_job() {
    if [ "$CV_KIND" = video ]; then encode_video "$CONV_IN" "$CV_OUT"; else encode_audio "$CONV_IN" "$CV_OUT"; fi
}

# Calcula o plano do preset escolhido. Retorna 1 se não há o que converter.
conv_prepare() {
    local id="$1"
    preset_info "$id"
    if [ "$id" = audio ] || [ "$P_KIND" = audio ]; then
        CV_KIND=audio
        if fits_already_audio "$PR_LIM"; then
            ui_info "Este arquivo já tem $(fmt_mb "$P_SIZE") e é MP3: já cabe no limite de $PR_LIM MB. Pode enviar como está."
            return 1
        fi
        plan_audio "$PR_K" "$PR_LIM"
        CV_OUT="$(out_path "$CONV_IN" "$PR_SFX${CLIP_TAG:+ $CLIP_TAG}" mp3)"
        CV_EST="$PA_EST"
        CV_LOW="$PA_LOW"
        CV_DESC="MP3 · ${PA_K} kbps$([ "$PA_K" -lt 80 ] && printf ' · mono')"
    else
        CV_KIND=video
        if fits_already "$PR_LIM"; then
            ui_info "Este vídeo já tem $(fmt_mb "$P_SIZE") e já está em MP4/H.264: cabe no limite de $PR_LIM MB. Pode enviar como está."
            return 1
        fi
        plan_video "$PR_LIM"
        CV_OUT="$(out_path "$CONV_IN" "$PR_SFX${CLIP_TAG:+ $CLIP_TAG}" mp4)"
        CV_EST="$PL_EST"
        CV_LOW="$PL_LOW"
        CV_DESC="MP4 (H.264) · ${PL_SHORT}p · áudio AAC ${PL_AK} kbps"
        [ "$PL_AK" -eq 0 ] && CV_DESC="MP4 (H.264) · ${PL_SHORT}p · sem áudio"
    fi
    return 0
}

# Converte; se o vídeo passar do limite, tenta uma vez de novo com mais margem.
conv_run() {
    local margin=0.92 attempt=1 rc actual
    CV_ACTUAL=""
    while true; do
        [ "$CV_KIND" = video ] && plan_video "$PR_LIM" "$margin"
        RUN_KIND=enc ui_run "Convertendo…" conv_job
        rc=$?
        if [ "$rc" -ne 0 ]; then
            rm -f "${CV_OUT%.*}".parcial.*
            return "$rc"
        fi
        actual="$(stat -c %s "$CV_OUT")"
        if [ "$CV_KIND" = video ] && is_pos "$PR_LIM" && [ "$attempt" -lt 2 ] &&
            awk -v a="$actual" -v l="$PR_LIM" 'BEGIN { exit !(a > l * 1e6) }'; then
            margin="$(awk -v m="$margin" -v a="$actual" -v l="$PR_LIM" 'BEGIN { printf "%.4f", m * (l * 1e6 / a) * 0.97 }')"
            rm -f "$CV_OUT"
            attempt=2
            continue
        fi
        CV_ACTUAL="$actual"
        return 0
    done
}

conv_summary() {
    if [ "$P_KIND" = video ]; then
        printf '%sx%s · %s · %s' "$P_W" "$P_H" "$(fmt_dur "$P_DUR")" "$(fmt_mb "$P_SIZE")"
    else
        printf 'Áudio · %s · %s' "$(fmt_dur "$P_DUR")" "$(fmt_mb "$P_SIZE")"
    fi
}

flow_convert() {   # $1 = arquivo (vazio = abre o seletor de arquivos)
    local f="${1:-}" head preset ans text est_txt lim_txt res
    mkwork
    if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
        ui_info "Para converter é preciso o ffmpeg. Gere o AppImage sem a opção --sem-ffmpeg."
        return 0
    fi
    if [ -z "$f" ]; then
        f="$(ui_pick_file)" || return 0
        [ -n "$f" ] || return 0
    fi
    if [ ! -f "$f" ]; then
        ui_info "Arquivo não encontrado:
$f"
        return 0
    fi
    if ! probe_file "$f" || ! is_pos "$P_DUR"; then
        ui_info "Não consegui ler este arquivo como vídeo ou áudio."
        return 0
    fi
    CONV_IN="$f"
    P_EXT="${f##*.}"
    head="Arquivo: $(basename "$f")
$(conv_summary)"

    # inteiro ou só um trecho? (P_DUR passa a ser a duração do trecho: os tamanhos já saem certos)
    CLIP_ON=0; CLIP_TAG=""; CLIP_IN=()
    choose_clip "$head" "$P_DUR" || return 0
    if [ "$CLIP_ON" = 1 ]; then
        clip_in_args
        if is_pos "$CLIP_DUR"; then P_DUR="$CLIP_DUR"; fi
        head="$head
$(clip_text)"
    else
        CLIP_TAG=""
    fi

    while true; do
        if [ "$P_KIND" = video ]; then
            preset="$(conv_video_rows | ui_choose "Converter para compartilhar" "$head" "" "Para onde vai" "O que será feito e tamanho estimado")" || return 0
        else
            preset="$(conv_audio_rows | ui_choose "Converter para compartilhar" "$head" "" "Para onde vai" "O que será feito e tamanho estimado")" || return 0
        fi
        CUSTOM_LIM=""
        if [ "$preset" = custom ]; then
            ans="$(ui_entry "Tamanho máximo" "Tamanho máximo do arquivo, em MB (exemplo: 25):" "25")" || continue
            ans="${ans//,/.}"
            if ! is_pos "$ans"; then
                ui_info "Digite um número maior que zero."
                continue
            fi
            CUSTOM_LIM="$ans"
        fi
        conv_prepare "$preset" || continue

        if is_pos "$PR_LIM"; then
            lim_txt=" (limite de $PR_LIM MB)"
        else
            lim_txt=""
        fi
        if [ "$CV_KIND" = video ] && [ "$PL_MODE" = crf ]; then est_txt="até ≈ $(fmt_mb "$CV_EST")"; else est_txt="≈ $(fmt_mb "$CV_EST")"; fi
        text="Converter agora?

Para: $(preset_label "$preset")
Arquivo: $(basename "$f")$([ "$CLIP_ON" = 1 ] && printf '\n%s' "$(clip_text)")
Resultado: $CV_DESC
Tamanho estimado: $est_txt$lim_txt
Será salvo como:
$(basename "$CV_OUT")"
        [ "$CV_LOW" = 1 ] && text="$text

Atenção: o arquivo é longo para esse limite, então a qualidade ficará baixa."
        ui_confirm "$text" "Converter" "Voltar" || continue
        break
    done

    conv_run
    res=$?
    if [ "$res" -eq 130 ]; then return 0; fi
    if [ "$res" -ne 0 ]; then
        ui_fail "Zapt: erro ao converter" "A conversão falhou. Confira se o arquivo não está corrompido."
        return 0
    fi
    local diff_word=estimado kind=converter
    if [ "$CV_KIND" = video ] && [ "$PL_MODE" = crf ]; then diff_word="teto estimado"; kind=converter-teto; fi
    record_size "$kind" "$CV_DESC" "$CV_EST" "$CV_ACTUAL"
    text="Pronto!

$(basename "$CV_OUT")
Tamanho final: $(fmt_mb "$CV_ACTUAL")$(size_diff "$CV_EST" "$CV_ACTUAL" "$diff_word")
Pasta: $(dirname "$CV_OUT")"
    if is_pos "$PR_LIM" && awk -v a="$CV_ACTUAL" -v l="$PR_LIM" 'BEGIN { exit !(a > l * 1e6) }'; then
        text="$text

Atenção: ficou acima do limite de $PR_LIM MB. Converta de novo com \"Outro limite\" um pouco menor."
    fi
    if [ "$PR_SFX" = whatsapp ]; then
        text="$text

Dica: no WhatsApp, enviar como Documento permite até 2 GB, sem recompressão."
    fi
    if ui_confirm "$text" "Abrir pasta" "Fechar" n; then
        xdg-open "$(dirname "$CV_OUT")" >/dev/null 2>&1 &
    fi
}

# ---------------------------------------------------------------------------
# Menu principal e escolha do modo de interface
# ---------------------------------------------------------------------------
CONV_FILES=()

main_menu() {
    local c u
    update_notice
    while true; do
        [ -n "$YTDLP_VER" ] || YTDLP_VER="$("$YTDLP" --version 2>/dev/null)"
        c="$(ui_menu "Zapt" "Zapt (yt-dlp $YTDLP_VER) — o que você quer fazer?" Sair <<EOF
musica|Baixar música
video|Baixar vídeo
converter|Converter um arquivo para compartilhar…
atualizar|Atualizar o yt-dlp$(u="$(update_available)" && printf ' (há uma versão nova: %s)' "$u")
mais|Mais opções…
EOF
)" || return 0
        case "$c" in
            musica | video) flow_download "$c" ;;
            converter) flow_convert "" ;;
            atualizar) flow_update "" ;;
            mais) flow_more ;;
        esac
    done
}

run_flow() {
    local f
    case "$1" in
        "") main_menu ;;
        musica | video) update_notice; flow_download "$1" ;;
        atualizar) flow_update "" ;;
        converter)
            if [ "${#CONV_FILES[@]}" -eq 0 ]; then
                flow_convert ""
            else
                for f in "${CONV_FILES[@]}"; do flow_convert "$f"; done
            fi
            ;;
    esac
}

# $1 = fluxo (vazio = menu principal)
interactive() {
    local flow="${1:-}"
    if have_tty; then
        UI=tty
    elif have_gui; then
        UI=gui
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        # Sem zenity e sem terminal: reabre o próprio AppImage dentro de um terminal
        if [ "$flow" = converter ] && [ "${#CONV_FILES[@]}" -gt 0 ]; then
            exec x-terminal-emulator -e "${APPIMAGE:-$0}" --converter "${CONV_FILES[@]}"
        fi
        exec x-terminal-emulator -e "${APPIMAGE:-$0}" --fluxo "$flow"
    else
        echo "Instale o zenity (sudo apt install zenity) ou rode a partir de um terminal." >&2
        exit 1
    fi
    run_flow "$flow"
    exit 0
}

# ---------------------------------------------------------------------------
# Linha de comando (tudo isto também está nos menus)
# ---------------------------------------------------------------------------

# Para testes: carrega só as funções
[ -n "${YTDLP_APP_LIB:-}" ] && return 0

[ "${1:-}" = "--instalar-atalho" ] && { install_shortcut; exit $?; }
[ "${1:-}" = "--remover-atalho" ] && { remove_shortcut; exit 0; }
[ "${1:-}" = "--reset-update" ] && { reset_update; exit 0; }

# --nightly = atualizar para a versão nightly
if [ "$#" -eq 1 ] && [ "$1" = "--nightly" ]; then
    set -- -U --update-to nightly
fi

# Qualquer comando de atualização do yt-dlp (-U, --update, --update-to ...)
WANT_UPDATE=0
for a in "$@"; do
    case "$a" in -U | --update | --update-to | --update-to=*) WANT_UPDATE=1 ;; esac
done
if [ "$WANT_UPDATE" = 1 ]; then
    ensure_user_bin
    exec "$USER_BIN" "${FFARGS[@]}" "$@"
fi

# Janelas específicas (usadas pelos atalhos do menu de aplicativos)
case "${1:-}" in
    --gui-musica) interactive musica ;;
    --gui-video) interactive video ;;
    --gui-atualizar) interactive atualizar ;;
    --gui-converter) interactive converter ;;
    --fluxo) interactive "${2:-}" ;;
    --converter) shift; CONV_FILES=("$@"); interactive converter ;;
esac

# Só caminhos de arquivos existentes (Abrir com, arrastar para o ícone): vai para o conversor
if [ "$#" -ge 1 ]; then
    ALL_FILES=1
    for a in "$@"; do
        case "$a" in -*) ALL_FILES=0; break ;; esac
        [ -f "$a" ] || { ALL_FILES=0; break; }
    done
    if [ "$ALL_FILES" = 1 ]; then CONV_FILES=("$@"); interactive converter; fi
fi

# Atalhos:  --musica [opções] URL   |   --video [opções] URL   (salvam na pasta atual, em MP3 / MP4)
if [ "$#" -ge 1 ] && { [ "$1" = "--musica" ] || [ "$1" = "--video" ]; }; then
    MODE="${1#--}"
    shift
    if [ "$#" -eq 0 ]; then
        echo "Uso: yt-dlp --$MODE URL" >&2
        exit 1
    fi
    if [ "$MODE" = musica ]; then
        MODE_ARGS=(--no-playlist -x --audio-format mp3 --audio-quality 0
            --embed-thumbnail --convert-thumbnails jpg --embed-metadata -o "%(title)s.%(ext)s")
    else
        MODE_ARGS=(--no-playlist -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"
            --merge-output-format mp4 -o "%(title)s.%(ext)s")
    fi
    exec "$YTDLP" "${FFARGS[@]}" "${MODE_ARGS[@]}" "$@"
fi

# Sem argumentos: abre o menu principal (janelas ou terminal)
if [ "$#" -eq 0 ]; then
    interactive ""
fi

# Qualquer outra coisa: repassa direto ao yt-dlp
exec "$YTDLP" "${FFARGS[@]}" "$@"
APPRUN_EOF

cat > "$APPDIR/usr/share/ytdlp-app/rows.jq" <<'ROWS_JQ_EOF'
# Opções de qualidade de vídeo para um contêiner.
# Uso: jq -r --arg cont mp4|mkv|webm -f rows.jq info.json
# Saída, uma linha por qualidade (a mais alta primeiro):
#   altura|rótulo|bytes|id_video|id_audio
# "bytes" vem vazio quando o site não informa tamanho nem taxa de bits.
# "id_audio" vem vazio quando o formato de vídeo já traz o som junto.

def fsize($dur):
  (.filesize // .filesize_approx //
   (if ((.tbr // 0) > 0 and $dur > 0) then (.tbr * 125 * $dur) else null end));

# taxa de bits só do vídeo (tira a parte do áudio nos formatos combinados)
def vbr_eff:
  (.vbr // ((.tbr // 0) - (if (.acodec // "x") != "none" then (.abr // 96) else 0 end)));

# na mesma resolução, prefere VP9 (eficiente e tocável), depois AV1, depois H.264
def codec_rank:
  ((.vcodec // "") | if test("^vp0?9") then 3 elif test("^av01") then 2 else 1 end);

# MP4 só com vídeo compatível (H.264); AV1 e VP9 ficam para MKV/WEBM
def ok_video($c):
  if $c == "mp4" then
    (.ext == "mp4" and (((.vcodec // "") | test("^(av01|vp0?9)")) | not))
  elif $c == "webm" then (.ext == "webm")
  else true end;

# áudio: faixa ORIGINAL primeiro (como o yt-dlp; dublagens têm language_preference menor),
# sem versões "DRC", depois maior taxa de bits; em empate, a primeira da lista
def arank: [ (.language_preference // -1), (((.format_id // "") | test("drc")) | not), (.abr // .tbr // 0) ];

def ok_audio($c):
  if $c == "mp4" then (.ext == "m4a")
  elif $c == "webm" then (.ext == "webm")
  else true end;

(.duration // 0) as $dur
| (.formats // []) as $f
| ($f | map(select(.vcodec != "none" and ((.height // 0) > 0) and ok_video($cont)))) as $vids
| ($f | map(select(.vcodec == "none" and ((.acodec // "x") != "none") and ok_audio($cont)))
      | to_entries | sort_by([(.value | arank), -.key]) | last | .value) as $a
| $vids
| group_by([.height, ((.fps // 30) >= 50)])
| map(sort_by([codec_rank, vbr_eff]) | last)
| map(
    . as $v
    | (if ((.acodec // "x") == "none") then $a else null end) as $aud
    | select(((.acodec // "x") != "none") or ($aud != null))
    | ($v | fsize($dur)) as $vsz
    | (if $aud then ($aud | fsize($dur)) else 0 end) as $asz
    | { h: $v.height,
        hi: (($v.fps // 30) >= 50),
        v: $v.format_id,
        a: ($aud.format_id // ""),
        size: (if ($vsz != null and $asz != null) then (($vsz + $asz) | floor) else null end) }
  )
| sort_by(-.h, (if .hi then 0 else 1 end))
| .[]
| [ .h, ("\(.h)p" + (if .hi then "60" else "" end)), (.size // ""), .v, .a ]
| join("|")
ROWS_JQ_EOF

cat > "$APPDIR/usr/share/ytdlp-app/baudio.jq" <<'BAUDIO_JQ_EOF'
# Melhor áudio original disponível (sem reconverter).
# Uso: jq -r -f baudio.jq info.json
# Saída (uma linha, ou nada se o site não tem áudio separado):
#   id|extensão|kbps|codec|bytes

# Mesma ideia do yt-dlp: primeiro a faixa de áudio ORIGINAL (language_preference maior;
# dublagens vêm abaixo), depois a que não é versão "DRC" (volume comprimido), depois a de
# maior taxa de bits. Em empate, a primeira da lista.
def arank: [ (.language_preference // -1), (((.format_id // "") | test("drc")) | not), (.abr // .tbr // 0) ];

(.duration // 0) as $dur
| [ (.formats // [])[]
    | select(.vcodec == "none" and ((.acodec // "x") != "none")) ]
| to_entries
| sort_by([(.value | arank), -.key])
| last
| select(. != null)
| .value
| (.filesize // .filesize_approx
   // (if ((.tbr // 0) > 0 and $dur > 0) then (.tbr * 125 * $dur) else null end)) as $sz
| [ .format_id,
    .ext,
    ((.abr // .tbr // 0) | floor),
    (.acodec // ""),
    (if $sz == null then "" else ($sz | floor) end) ]
| join("|")
BAUDIO_JQ_EOF

cat > "$APPDIR/usr/share/ytdlp-app/items.jq" <<'ITEMS_JQ_EOF'
# Entrada: JSON de um link (vídeo ou playlist, lido com --flat-playlist). Variável: $u = link original.
# Saída: uma linha por item, separada por tab:  url  título  duração(s)  pasta
# "pasta" é o nome da playlist (próprio para nome de pasta) ou "-" quando o item é um link solto.
def clean: gsub("[\\x01-\\x1f]"; " ");
if (._type // "video") == "playlist" then
    ((.title // "playlist") | tostring | clean | gsub("[/\\\\:*?\"<>|]"; "_") | gsub("^[. ]+"; "") | .[0:80]) as $g
    | (if $g == "" then "playlist" else $g end) as $g
    | (.entries // [])[]
    | select(. != null)
    | [ (.url // .webpage_url // "-"),
        ((.title // "sem título") | tostring | clean),
        ((.duration // 0) | tonumber? // 0 | tostring),
        $g ]
    | @tsv
else
    [ $u,
      ((.title // "sem título") | tostring | clean),
      ((.duration // 0) | tonumber? // 0 | tostring),
      "-" ]
    | @tsv
end
ITEMS_JQ_EOF

cat > "$APPDIR/zapt.desktop" <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=Zapt
Comment=Baixa músicas e vídeos e converte para compartilhar
Comment[en]=Download music (MP3) and videos (MP4)
Exec=zapt %U
Icon=zapt
Terminal=false
Categories=AudioVideo;Network;
Actions=Musica;Video;Converter;Atualizar;

[Desktop Action Musica]
Name=Baixar música
Exec=zapt --gui-musica

[Desktop Action Video]
Name=Baixar vídeo
Exec=zapt --gui-video

[Desktop Action Converter]
Name=Converter arquivo para compartilhar
Exec=zapt --gui-converter

[Desktop Action Atualizar]
Name=Atualizar o yt-dlp
Exec=zapt --gui-atualizar
DESKTOP_EOF

cat > "$APPDIR/zapt.svg" <<'SVG_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#16367f"/>
      <stop offset="1" stop-color="#0a1b45"/>
    </linearGradient>
    <linearGradient id="bolt" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffe45c"/>
      <stop offset="1" stop-color="#ffb800"/>
    </linearGradient>
  </defs>
  <rect width="256" height="256" rx="56" fill="url(#bg)"/>
  <!-- raio que termina em ponta de seta para baixo -->
  <path d="M158 30 L84 134 L120 134 L104 196 L178 110 L141 110 Z" fill="url(#bolt)" stroke="#fff3b0" stroke-width="3" stroke-linejoin="round"/>
  <!-- base do download -->
  <path d="M66 222 H190" stroke="#4cc9f0" stroke-width="14" stroke-linecap="round"/>
</svg>
SVG_EOF


chmod +x "$APPDIR/AppRun" "$APPDIR/usr/bin/"*
ln -sf zapt.svg "$APPDIR/.DirIcon"

echo "==> Gerando o AppImage..."
# --appimage-extract-and-run: funciona mesmo sem libfuse2 instalado
ARCH=x86_64 "$WORK/appimagetool" --appimage-extract-and-run \
    "$APPDIR" "$TMP_IMG" >/dev/null
chmod +x "$TMP_IMG"

# Guarda o AppImage anterior (se houver) em vez de exigir que você o apague
if [ -e "$FINAL" ]; then
    mv -f "$FINAL" "$FINAL.anterior"
    echo "O AppImage anterior foi guardado como: $FINAL.anterior"
fi
mv "$TMP_IMG" "$FINAL"

echo
echo "Pronto: $FINAL"
echo
echo "Abra o Zapt (duplo clique ou ./zapt-x86_64.AppImage) para ver o menu."
echo "Para ter o ícone no menu de aplicativos: Mais opções > Criar atalho."
echo "Depois de testar a nova versão, você pode apagar o arquivo .anterior."
