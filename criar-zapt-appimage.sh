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
fmt_size() {
    if is_pos "$1"; then printf '≈ %s' "$(fmt_mb "$1")"; else printf 'tamanho desconhecido'; fi
}
size_range() {   # menor maior (bytes)
    if ! is_pos "$1" || ! is_pos "$2"; then printf 'tamanho desconhecido'; return; fi
    if [ "$1" = "$2" ]; then fmt_size "$1"; else printf 'de ≈ %s a %s' "$(fmt_mb "$1")" "$(fmt_mb "$2")"; fi
}
fmt_dur() {
    awk -v s="$1" 'BEGIN {
        s = int(s + 0.5); h = int(s / 3600); m = int((s % 3600) / 60); x = s % 60;
        if (h > 0) printf "%d:%02d:%02d", h, m, x; else printf "%d:%02d", m, x }'
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
    update-desktop-database "$BASE/applications" 2>/dev/null || true
    echo "Atalho criado. Procure por \"Zapt\" no menu de aplicativos."
    echo "Clique com o botão direito no ícone para ir direto a Música, Vídeo, Converter ou Atualizar."
}

remove_shortcut() {
    local BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
    rm -f "$BASE/applications/zapt.desktop" "$BASE/icons/hicolor/scalable/apps/zapt.svg"
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
    local rows=() row id c1 c2 args=() n=0 opt mark height
    mapfile -t rows
    [ "${#rows[@]}" -gt 0 ] || return 1
    if [ -z "$def" ]; then IFS='|' read -r def _ <<<"${rows[0]}"; fi
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

# ui_entry TÍTULO TEXTO [PADRÃO] -> imprime o texto digitado
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
    [ -n "$v" ] || return 1      # Enter em branco = cancelar
    printf '%s' "$v"
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
        { printf '%s\n\n' "$2"; [ -s "$RUNLOG" ] && cat "$RUNLOG"; } >"$f"
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

# ui_run TEXTO COMANDO...     RUN_KIND=pulse|dl|enc
# Nas janelas: roda em segundo plano com barra de progresso e botão Cancelar (retorna 130).
# No terminal: roda direto, mostrando a saída do comando.
ui_run() {
    local text="$1" pid rc pct args=()
    shift
    mkwork
    if [ "$UI" != gui ]; then
        printf '%s\n' "$text" >&2
        "$@"
        return $?
    fi
    RUNLOG="$WORKD/run.log"
    : >"$RUNLOG"
    "$@" >"$RUNLOG" 2>&1 &
    pid=$!
    if [ "${RUN_KIND:-pulse}" = enc ]; then args=(--percentage=0); else args=(--pulsate); fi
    (
        while kill -0 "$pid" 2>/dev/null; do
            case "${RUN_KIND:-pulse}" in
                enc) pct="$(enc_pct)"; echo "$pct"; echo "# $text ($pct%)" ;;
                dl) pct="$(grep -ao '[0-9][0-9.]*%' "$RUNLOG" 2>/dev/null | tail -n1)"; echo "# $text $pct" ;;
                *) echo "# $text" ;;
            esac
            sleep 0.5
        done
        echo 100
    ) | zenity --progress "${args[@]}" --auto-close --no-markup --title="Zapt" \
        --text="$text" --width=480 2>/dev/null
    rc=${PIPESTATUS[1]}
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

flow_more() {
    local c
    c="$(ui_menu "Zapt: mais opções" "Escolha uma opção:" "Voltar" <<'EOF'
nightly|Atualizar para a versão nightly (se o YouTube der erro 403)
estavel|Atualizar para a versão estável
resetar|Voltar para a versão que veio dentro do app
atalho|Criar atalho no menu de aplicativos
sematalho|Remover o atalho do menu de aplicativos
sobre|Sobre (versões instaladas)
EOF
)" || return 0
    case "$c" in
        nightly) flow_update nightly ;;
        estavel) flow_update stable ;;
        resetar) reset_update >/dev/null; YTDLP_VER=""; ui_info "Voltou para o yt-dlp que veio dentro do app." ;;
        atalho) ui_info "$(install_shortcut 2>&1)" ;;
        sematalho) ui_info "$(remove_shortcut 2>&1)" ;;
        sobre) ui_info "$(about_text)" ;;
    esac
}

# ---------------------------------------------------------------------------
# Download: escolha de formato e qualidade, com o tamanho estimado antes de confirmar
# ---------------------------------------------------------------------------
I_TYPE=""; I_TITLE=""; I_DUR=0
BA_ID=""; BA_EXT=""; BA_ABR=""; BA_CODEC=""; BA_BYTES=""
VROWS=()
SEL_LABEL=""; SEL_BYTES=""; YARGS=()
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
    if [ -n "$BA_ID" ]; then t="$t · áudio original do site: $BA_EXT${BA_ABR:+ ~$BA_ABR kbps}"; fi
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
        mp3) list="320:máxima 256:muito boa 192:recomendada 128:compacta 96:mínima" ;;
        m4a) list="256:máxima 192:recomendada 128:compacta 96:mínima" ;;
        *) list="160:máxima 128:recomendada 96:compacta 64:mínima" ;;
    esac
    for k in $list; do
        printf '%s|%s kbps — %s|%s\n' "${k%%:*}" "${k%%:*}" "${k#*:}" "$(fmt_size "$(audio_est "${k%%:*}")")"
    done
}

pick_audio() {
    local af aq def
    while true; do
        af="$(audio_format_rows | ui_choose "Música — formato" "$(info_text)" mp3 "Formato" "Detalhes e tamanho estimado")" || return 1
        case "$af" in
            orig | flac | wav) aq=""; break ;;
        esac
        case "$af" in opus) def=128 ;; *) def=192 ;; esac
        aq="$(audio_quality_rows "$af" | ui_choose "Música — qualidade ($af)" "$(info_text)" "$def" "Qualidade" "Tamanho estimado")" && break
    done
    case "$af" in
        orig)
            YARGS=(-f "${BA_ID}/ba/b" -x --audio-format best)
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
    local c row i def pick n h lab bytes vv va sel
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
        c="$(video_container_rows | ui_choose "Vídeo — formato" "$(info_text)" "" "Formato" "Detalhes e tamanho estimado")" || return 1
        load_vrows "$c"
        out=()
        def=""
        i=0
        for row in "${VROWS[@]}"; do
            i=$((i + 1))
            IFS='|' read -r h lab bytes _ <<<"$row"
            if [ -z "$def" ] && [ "${h:-0}" -le 1080 ]; then def="$i"; fi
            out+=("$i|$lab|$(fmt_size "$bytes")")
        done
        [ -n "$def" ] || def=1
        pick="$(printf '%s\n' "${out[@]}" | ui_choose "Vídeo — qualidade (${c^^})" "$(info_text)" "$def" "Qualidade" "Tamanho estimado")" && break
    done
    IFS='|' read -r h lab SEL_BYTES vv va <<<"${VROWS[$((pick - 1))]}"
    sel="$vv${va:+"+$va"}"
    SEL_LABEL="${c^^} · $lab"
    YARGS=(-f "$sel/bv*[height<=$h]+ba/b[height<=$h]" --merge-output-format "$c" --remux-video "$c" \
        --embed-metadata --no-playlist -o "%(title)s.%(ext)s" --trim-filenames 180 -P "$DEST")
    return 0
}

download_job() {
    local nl=()
    [ "$UI" = gui ] && nl=(--newline)
    "$YTDLP" "${FFARGS[@]}" "${nl[@]}" "${YARGS[@]}" --print-to-file "after_move:filepath" "$SAVED" "$DL_URL"
}

flow_download() {   # $1 = musica|video (vazio = pergunta)
    local mode="${1:-}" url rc text
    mkwork
    url="$(ui_entry "Zapt" "Cole o link do vídeo ou da música:")" || return 0
    url="${url//[[:space:]]/}"
    [ -n "$url" ] || return 0
    if [ -z "$mode" ]; then
        mode="$(printf '%s\n' 'musica|Música|somente o áudio' 'video|Vídeo|imagem e som' |
            ui_choose "Zapt" "O que você quer baixar?" musica "Tipo" "Detalhes")" || return 0
    fi

    RUN_KIND=pulse ui_run "Buscando informações do vídeo…" fetch_info_job "$url"
    rc=$?
    [ "$rc" -eq 130 ] && return 0
    if [ "$rc" -ne 0 ] || ! parse_info; then
        ui_fail "Zapt: não consegui ler o link" "Não consegui ler este link. Confira o endereço.
Se for do YouTube e o erro for 403 ou de acesso, use Mais opções > Atualizar para a versão nightly."
        return 0
    fi
    if [ "$I_TYPE" = playlist ]; then
        ui_info "Este link é de uma playlist. Cole o link de um vídeo ou de uma música específica."
        return 0
    fi

    DEST="$(dest_for "$mode")"
    while true; do
        if [ "$mode" = musica ]; then pick_audio || return 0; else pick_video || return 0; fi
        text="Baixar com estas opções?

Título: $I_TITLE
Formato: $SEL_LABEL
Tamanho estimado: $(fmt_size "$SEL_BYTES")
Salvar em: $DEST"
        ui_confirm "$text" "Baixar" "Voltar" && break
    done

    SAVED="$WORKD/saved.txt"
    : >"$SAVED"
    DL_URL="$url"
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
        if ui_confirm "Pronto!

$(basename "$LAST_FILE")
Tamanho final: $(fmt_mb "$(stat -c %s "$LAST_FILE")")
Pasta: $(dirname "$LAST_FILE")

Quer converter para compartilhar (Discord, WhatsApp...)?" "Converter…" "Fechar" n; then
            flow_convert "$LAST_FILE"
        fi
    else
        ui_info "Pronto! Salvo em: $DEST"
    fi
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
    [ "$P_KIND" = video ] && [ "$P_VCODEC" = h264 ] && { [ -z "$P_ACODEC" ] || [ "$P_ACODEC" = aac ]; } || return 1
    case "${P_EXT,,}" in mp4 | m4v) ;; *) return 1 ;; esac
    awk -v s="$P_SIZE" -v l="$1" 'BEGIN { exit !(s <= l * 1e6 * 0.98) }'
}
fits_already_audio() {
    is_pos "$1" || return 1
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

encode_video() {   # entrada saída   (usa PL_*)
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
        ff -y -i "$in" -map "0:$P_VIDX" "${vfa[@]}" -c:v libx264 -preset fast -profile:v high -pix_fmt yuv420p \
            -b:v "${PL_VK}k" -pass 1 -passlogfile "$WORKD/pass" -an -f null /dev/null || { rm -f "$tmp"; return 1; }
        echo "2/2" >"$WORKD/stage"
        ff -y -i "$in" -map "0:$P_VIDX" "${amap[@]}" "${vfa[@]}" -c:v libx264 -preset fast -profile:v high -pix_fmt yuv420p \
            -b:v "${PL_VK}k" -pass 2 -passlogfile "$WORKD/pass" "${aa[@]}" -movflags +faststart "$tmp" || { rm -f "$tmp"; return 1; }
    else
        echo "1/1" >"$WORKD/stage"
        ff -y -i "$in" -map "0:$P_VIDX" "${amap[@]}" "${vfa[@]}" -c:v libx264 -preset fast -profile:v high -pix_fmt yuv420p \
            -crf 22 -maxrate "${PL_VK}k" -bufsize "$((PL_VK * 2))k" "${aa[@]}" -movflags +faststart "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    mv -f "$tmp" "$out"
}

encode_audio() {   # entrada saída   (usa PA_K)
    local in="$1" out="$2" tmp extra=()
    tmp="${out%.*}.parcial.mp3"
    [ "$PA_K" -lt 80 ] && extra=(-ac 1 -ar 44100)
    echo "1/1" >"$WORKD/stage"
    if [ "$P_KIND" = audio ] && [ -n "$P_PICIDX" ]; then
        # mantém a capa do álbum; se não der, tenta de novo sem ela
        ff -y -i "$in" -map "0:a:0" -map "0:$P_PICIDX" -c:v copy -c:a libmp3lame -b:a "${PA_K}k" "${extra[@]}" \
            -map_metadata 0 -id3v2_version 3 "$tmp" 2>/dev/null ||
            ff -y -i "$in" -vn -map "0:a:0" -c:a libmp3lame -b:a "${PA_K}k" "${extra[@]}" \
                -map_metadata 0 -id3v2_version 3 "$tmp" || { rm -f "$tmp"; return 1; }
    else
        ff -y -i "$in" -vn -map "0:a:0" -c:a libmp3lame -b:a "${PA_K}k" "${extra[@]}" \
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
        CV_OUT="$(out_path "$CONV_IN" "$PR_SFX" mp3)"
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
        CV_OUT="$(out_path "$CONV_IN" "$PR_SFX" mp4)"
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
Arquivo: $(basename "$f")
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
    text="Pronto!

$(basename "$CV_OUT")
Tamanho final: $(fmt_mb "$CV_ACTUAL")
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
CONV_FILE=""

main_menu() {
    local c
    while true; do
        [ -n "$YTDLP_VER" ] || YTDLP_VER="$("$YTDLP" --version 2>/dev/null)"
        c="$(ui_menu "Zapt" "Zapt (yt-dlp $YTDLP_VER) — o que você quer fazer?" Sair <<'EOF'
musica|Baixar música
video|Baixar vídeo
converter|Converter um arquivo para compartilhar…
atualizar|Atualizar o yt-dlp
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
    case "$1" in
        "") main_menu ;;
        musica | video) flow_download "$1" ;;
        atualizar) flow_update "" ;;
        converter) flow_convert "$CONV_FILE" ;;
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
    --converter) CONV_FILE="${2:-}"; interactive converter ;;
esac

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

def ok_audio($c):
  if $c == "mp4" then (.ext == "m4a")
  elif $c == "webm" then (.ext == "webm")
  else true end;

(.duration // 0) as $dur
| (.formats // []) as $f
| ($f | map(select(.vcodec != "none" and ((.height // 0) > 0) and ok_video($cont)))) as $vids
| ($f | map(select(.vcodec == "none" and ((.acodec // "x") != "none") and ok_audio($cont)))
      | sort_by(.abr // .tbr // 0) | last) as $a
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

(.duration // 0) as $dur
| [ (.formats // [])[]
    | select(.vcodec == "none" and ((.acodec // "x") != "none")) ]
| sort_by(.abr // .tbr // 0)
| last
| select(. != null)
| (.filesize // .filesize_approx
   // (if ((.tbr // 0) > 0 and $dur > 0) then (.tbr * 125 * $dur) else null end)) as $sz
| [ .format_id,
    .ext,
    ((.abr // .tbr // 0) | floor),
    (.acodec // ""),
    (if $sz == null then "" else ($sz | floor) end) ]
| join("|")
BAUDIO_JQ_EOF

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
