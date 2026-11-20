#!/usr/bin/env bash
set -e
CONEJO_VERSION="1.9.0"

VERDE='\033[0;32m'
CIAN='\033[0;36m'
AMARILLO='\033[1;33m'
NEGRITA='\033[1m'
RESET='\033[0m'

APP_DIR="$HOME/.conejo_blanco"
CONFIG_FILE="$APP_DIR/config.json"

echo -e "${CIAN}${NEGRITA}"
cat << 'EOF'
(\_/)
(^_^)
/>Conejo_blanco;
by Traker
EOF
echo -e "${RESET}"

echo -e "${CIAN}${NEGRITA}=== INSTALADOR / ACTUALIZADOR DE CONEJO BLANCO v${CONEJO_VERSION} (macOS) ===${RESET}\n"

MODO_ACTUALIZACION=false
if [ -f "$APP_DIR/cli.py" ] && [ -x "$APP_DIR/venv/bin/python3" ] && command -v ollama &> /dev/null; then
    MODO_ACTUALIZACION=true
    echo -e "${VERDE}ℹ Instalación previa detectada en ${APP_DIR}. Se actualizarán los scripts manteniendo tu entorno y memoria.${RESET}\n"
fi

echo -e "${AMARILLO}Selecciona el modelo de IA local predeterminado para Conejo Blanco:${RESET}"
echo -e "  ${CIAN}1)${RESET} gemma2:2b          (Ultraligero ~1.6 GB, respuesta instantánea)"
echo -e "  ${CIAN}2)${RESET} qwen2.5-coder:3b   (Especializado en código y agente terminal ~1.9 GB)"
read -rp "Elige una opción [1/2] (por defecto 1): " OPCION_MODELO
case "$OPCION_MODELO" in
    2) MODELO_ELEGIDO="qwen2.5-coder:3b" ;;
    *) MODELO_ELEGIDO="gemma2:2b" ;;
esac
echo -e "${VERDE}✔ Modelo seleccionado: ${MODELO_ELEGIDO}${RESET}\n"

if [ "$MODO_ACTUALIZACION" = false ]; then
    echo -e "${AMARILLO}[Paso 1/6] Verificando Homebrew, Python 3 y Ollama...${RESET}"
    if ! command -v brew &> /dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ -x "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    command -v python3 &> /dev/null || brew install python
    command -v ollama &> /dev/null || brew install ollama
    echo -e "${VERDE}✔ Dependencias base listas en macOS.${RESET}\n"
else
    echo -e "${AMARILLO}[Paso 1/6] Omitiendo instalación de paquetes Homebrew (ya instalados).${RESET}\n"
fi

mkdir -p "$APP_DIR"

echo -e "${AMARILLO}[Paso 2/6] Verificando servicio activo de Ollama...${RESET}"
if ! pgrep -x "ollama" > /dev/null; then
    nohup ollama serve > "$APP_DIR/ollama_serve.log" 2>&1 &
    sleep 4
fi
echo -e "${VERDE}✔ Motor Ollama activo.${RESET}\n"

echo -e "${AMARILLO}[Paso 3/6] Verificando / descargando el modelo (${MODELO_ELEGIDO})...${RESET}"
ollama pull "$MODELO_ELEGIDO"
echo -e "${VERDE}✔ Modelo ${MODELO_ELEGIDO} listo.${RESET}\n"

echo -e "${AMARILLO}[Paso 4/6] Verificando entorno virtual de Python y dependencias...${RESET}"
if [ ! -x "$APP_DIR/venv/bin/python3" ]; then
    python3 -m venv "$APP_DIR/venv"
fi
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/venv/bin/pip" install --quiet requests rich prompt_toolkit
echo -e "${VERDE}✔ Entorno virtual listo.${RESET}\n"

echo -e "${AMARILLO}[Paso 5/6] Guardando modelo seleccionado en ${CONFIG_FILE}...${RESET}"
"$APP_DIR/venv/bin/python3" -c '
import json, os, sys
cfg_path = sys.argv[1]
modelo = sys.argv[2]
data = {
    "default_model": modelo,
    "temperature": 0.3,
    "system_prompt": "Eres un asistente técnico y agente de terminal directo, preciso y útil que responde en español."
}
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            existente = json.load(f)
        existente["default_model"] = modelo
        data = existente
    except Exception:
        pass
with open(cfg_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
' "$CONFIG_FILE" "$MODELO_ELEGIDO"
echo -e "${VERDE}✔ Configuración actualizada con ${MODELO_ELEGIDO}.${RESET}\n"

echo -e "${AMARILLO}[Paso 6/6] Actualizando el código fuente del cliente y agente CLI (cli.py) y comando global...${RESET}"
cat << 'EOF_PY' > "$APP_DIR/cli.py"
#!/usr/bin/env python3
import sys
import os
import re
import math
import json
import time
import shutil
import tempfile
import threading
import argparse
import subprocess
from datetime import datetime
import requests
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.live import Live
from rich.text import Text
from rich.table import Table
from prompt_toolkit import PromptSession
from prompt_toolkit.styles import Style
from prompt_toolkit.history import FileHistory
from prompt_toolkit.completion import Completer, Completion, PathCompleter

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

VERSION = "1.9.0"
GITHUB_RAW_BASE = "https://raw.githubusercontent.com/TrakerDev/conejo_blanco/main"

OLLAMA_BASE = "http://localhost:11434"
OLLAMA_CHAT_URL = f"{OLLAMA_BASE}/api/chat"
OLLAMA_TAGS_URL = f"{OLLAMA_BASE}/api/tags"
OLLAMA_PULL_URL = f"{OLLAMA_BASE}/api/pull"

APP_DIR = os.path.expanduser("~/.conejo_blanco")
HISTORY_FILE = os.path.join(APP_DIR, "historial_prompts")
CONFIG_FILE = os.path.join(APP_DIR, "config.json")
MEMORY_FILE = os.path.join(APP_DIR, "memoria_usuario.json")
SESSION_LOG_FILE = os.path.join(APP_DIR, "historial_sesiones.jsonl")
OLLAMA_LOG = os.path.join(APP_DIR, "ollama_serve.log")

DEFAULT_CONFIG = {
    "default_model": "gemma2:2b",
    "temperature": 0.3,
    "system_prompt": "Eres un asistente técnico y agente de terminal directo, preciso y útil que responde en español."
}

MODELOS_SUGERIDOS = {
    "gemma2:2b": "Google Gemma 2 (2B) - Ultraligero ~1.6 GB",
    "qwen2.5-coder:3b": "Qwen 2.5 Coder (3B) - Ideal para código y agente ~1.9 GB",
    "qwen2.5-coder:7b": "Qwen 2.5 Coder (7B) - Alta precisión técnica ~4.7 GB",
    "llama3.2:3b": "Meta Llama 3.2 (3B) - Propósito general rápido ~2.0 GB",
    "llama3.2:1b": "Meta Llama 3.2 (1B) - Mínimo consumo de RAM ~1.3 GB",
    "deepseek-coder-v2": "DeepSeek Coder V2 - Especializado en programación",
    "phi3.5": "Microsoft Phi-3.5 (3.8B) - Razonamiento compacto ~2.2 GB",
    "mistral": "Mistral (7B) - Modelo general robusto ~4.1 GB"
}

INSTRUCCIONES_AGENTE = """
ERES UN AGENTE EJECUTOR DE TERMINAL CON ACCESO TOTAL AL SISTEMA ({os_name} en {cwd}).
NUNCA digas "no tengo acceso", "no puedo descargar" ni le des instrucciones al usuario para que las haga él. TÚ TIENES ACCESO DIRECTO A LA TERMINAL MEDIANTE LA ETIQUETA <EJECUTAR>.

PROTOCOLO OBLIGATORIO EN CADA TAREA:
1. En el PRIMER paso de una solicitud del usuario, define un plan de acción breve y claro en lista numerada dentro de <PLAN>...</PLAN>, seguido inmediatamente del PRIMER comando a ejecutar dentro de <EJECUTAR>...</EJECUTAR>.
2. En los pasos siguientes tras recibir la salida del sistema, NO repitas <PLAN>; responde ÚNICAMENTE con <EJECUTAR>siguiente_comando</EJECUTAR> hasta completar la tarea.
3. Cuando todos los pasos del plan estén verificados y terminados, responde al usuario en español normal sin etiquetas.

EJEMPLOS OBLIGATORIOS DE COMPORTAMIENTO:
Usuario: instala gTTS desde github y haz una prueba de audio
Asistente: <PLAN>
1. Instalar la librería gTTS directamente desde su repositorio oficial de GitHub.
2. Verificar la instalación comprobando la versión de gtts-cli.
3. Generar un archivo de audio de prueba en español para validar el funcionamiento.
</PLAN>
<EJECUTAR>pip install git+https://github.com/pndurette/gTTS.git</EJECUTAR>

Usuario: [SALIDA DEL SISTEMA: Successfully installed gTTS-2.5.4]
Asistente: <EJECUTAR>gtts-cli --version</EJECUTAR>

REGLAS ESTRICTAS:
- Emite UN solo comando por turno dentro de <EJECUTAR>...</EJECUTAR>.
- NUNCA repitas un comando que ya ejecutaste en este turno. Si falló, cambia de estrategia o corrige los parámetros.
- No agregues explicaciones fuera de <PLAN> mientras ejecutas comandos.
"""

ASCII_ART = r"""(\_/)
(^_^)
/>Conejo_blanco;
by Traker"""

BRAILLE_MAP = [
    [0x01, 0x08],
    [0x02, 0x10],
    [0x04, 0x20],
    [0x40, 0x80],
]

console = Console()

COMANDOS_INTERNOS = {
    "/agente": "Activa/desactiva el modo agente ejecutor con plan de acción",
    "/auto": "Activa/desactiva la ejecución automática sin pedir confirmación",
    "/instalar": "Descarga e instala un modelo nuevo en Ollama (ej. /instalar qwen2.5-coder:3b)",
    "/modelos": "Lista los modelos descargados localmente en Ollama",
    "/modelo": "Cambia el modelo activo (ej. /modelo qwen2.5-coder:3b)",
    "/actualizar": "Verifica en GitHub si hay una versión nueva y actualiza este sistema",
    "/memoria": "Muestra los hechos y preferencias recordadas sobre ti",
    "/recordar": "Guarda un dato permanente en memoria (ej. /recordar Uso Fish shell)",
    "/olvidar": "Borra la memoria persistente de largo plazo",
    "/temp": "Ajusta la temperatura en caliente (ej. /temp 0.2)",
    "/config": "Muestra la configuración activa y ruta de config.json",
    "/archivo": "Carga un archivo al contexto de la sesión",
    "/guardar": "Exporta la conversación actual a Markdown (.md)",
    "/limpiar": "Reinicia la conversación y limpia la pantalla",
    "/salir": "Cierra la sesión de Conejo Blanco"
}

def detectar_so():
    if sys.platform == "win32":
        return "Windows (PowerShell/CMD)"
    elif sys.platform == "darwin":
        return "macOS (zsh/bash)"
    elif "com.termux" in os.environ.get("PREFIX", ""):
        return "Android / Termux (bash)"
    return "Linux / Unix (bash)"

def obtener_script_instalador_so():
    if sys.platform == "win32":
        return "instalar_conejo_blanco_windows.ps1"
    elif sys.platform == "darwin":
        return "instalar_conejo_blanco_mac.sh"
    elif "com.termux" in os.environ.get("PREFIX", ""):
        return "instalar_conejo_blanco_android_termux.sh"
    return "instalar_conejo_blanco_linux.sh"

def parsear_version(v_str):
    try:
        return tuple(int(x) for x in re.findall(r"\d+", v_str))
    except Exception:
        return (0, 0, 0)

def verificar_y_actualizar(forzar=False):
    script_nombre = obtener_script_instalador_so()
    url_script = f"{GITHUB_RAW_BASE}/{script_nombre}"

    console.print(f"[cyan]🔍 Buscando actualizaciones en GitHub para [bold]{detectar_so()}[/bold]...[/cyan]")
    console.print(f"[dim]Archivo objetivo: {script_nombre} (Versión local: v{VERSION})[/dim]")

    try:
        resp = requests.get(url_script, timeout=10)
        if resp.status_code == 404:
            console.print(f"[bold red]Error:[/bold red] No se encontró [cyan]{script_nombre}[/cyan] en el repositorio de GitHub.\n")
            return
        resp.raise_for_status()
        contenido_remoto = resp.text
    except Exception as e:
        console.print(f"[bold red]Error de conexión con GitHub:[/bold red] {e}\n")
        return

    match_ver = re.search(r'CONEJO_VERSION\s*=\s*["\']?([0-9]+\.[0-9]+\.[0-9]+)["\']?', contenido_remoto)
    if not match_ver:
        match_ver = re.search(r'VERSION\s*=\s*["\']([0-9]+\.[0-9]+\.[0-9]+)["\']', contenido_remoto)

    version_remota = match_ver.group(1) if match_ver else None

    if version_remota:
        console.print(f"[cyan]📦 Versión disponible en GitHub:[/cyan] [bold green]v{version_remota}[/bold green]")
        if not forzar and parsear_version(version_remota) <= parsear_version(VERSION):
            console.print(f"[green]✔ Ya tienes la última versión instalada (v{VERSION}).[/green]\n")
            return
    else:
        console.print("[yellow]⚠ No se detectó etiqueta de versión en el script remoto.[/yellow]")
        if not forzar:
            console.print("[dim]Usa [bold]/actualizar --forzar[/bold] si deseas reinstalar de todos modos.[/dim]\n")
            return

    console.print(f"\n[bold yellow]⚡ Descargando e iniciando actualización automática ({script_nombre})...[/bold yellow]\n")

    try:
        tmp_dir = tempfile.mkdtemp(prefix="conejo_update_")
        ruta_script = os.path.join(tmp_dir, script_nombre)
        with open(ruta_script, "w", encoding="utf-8", newline="\r\n" if sys.platform == "win32" else "\n") as f:
            f.write(contenido_remoto)

        if sys.platform == "win32":
            os.execvp("powershell.exe", [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", ruta_script
            ])
        elif "com.termux" in os.environ.get("PREFIX", ""):
            os.chmod(ruta_script, 0o755)
            os.execvp("/data/data/com.termux/files/usr/bin/bash", ["/data/data/com.termux/files/usr/bin/bash", ruta_script])
        else:
            os.chmod(ruta_script, 0o755)
            os.execvp("bash", ["bash", ruta_script])
    except Exception as e:
        console.print(f"[bold red]Error al ejecutar el actualizador:[/bold red] {e}\n")

def generar_frame_onda(tick):
    """Genera la onda sinusoidal Braille en una sola línea (3 celdas = 4x6 puntos)."""
    phase = (tick * 0.24) % (math.pi * 2)
    dots = [[False] * 6 for _ in range(4)]
    for x in range(6):
        y = (0.5 - math.sin(((x + 0.5) / 6.0) * 7.2257 - phase) * 0.42) * 3.0
        r = max(0, min(3, round(y)))
        dots[r][x] = True

    out = ""
    for c in range(3):
        mask = 0
        for dy in range(4):
            for dx in range(2):
                if dots[dy][c * 2 + dx]:
                    mask |= BRAILLE_MAP[dy][dx]
        out += chr(0x2800 + mask)
    return out

def render_onda_animada(tick, mensaje_estado):
    onda = generar_frame_onda(tick)
    t = Text()
    t.append(f"{onda} ", style="bold #10b981")
    t.append(mensaje_estado, style="bold cyan")
    return t

def instalar_modelo_ollama(nombre_modelo, session):
    """Descarga e instala un modelo en Ollama mostrando progreso en vivo con la onda Braille."""
    nombre_modelo = nombre_modelo.strip()
    if not nombre_modelo:
        console.print("[yellow]Especifica el modelo a instalar. Ejemplo: [bold]/instalar qwen2.5-coder:3b[/bold][/yellow]\n")
        return None

    console.print(f"[cyan]⬇️ Solicitando descarga de [bold white]{nombre_modelo}[/bold white] en Ollama...[/cyan]")

    estado_pull = {
        "status": "Conectando con registro de Ollama...",
        "porcentaje": "",
        "finalizado": False,
        "error": None
    }

    def _pull_worker():
        try:
            with requests.post(OLLAMA_PULL_URL, json={"name": nombre_modelo, "stream": True}, stream=True, timeout=600) as r:
                if r.status_code != 200:
                    estado_pull["error"] = f"HTTP {r.status_code}: {r.text}"
                    return
                for linea in r.iter_lines():
                    if linea:
                        datos = json.loads(linea.decode("utf-8"))
                        if "error" in datos:
                            estado_pull["error"] = datos["error"]
                            return
                        st = datos.get("status", "")
                        total = datos.get("total", 0)
                        completed = datos.get("completed", 0)
                        if total > 0:
                            pct = (completed / total) * 100
                            mb_done = completed / (1024 ** 2)
                            mb_tot = total / (1024 ** 2)
                            estado_pull["porcentaje"] = f" ({pct:.1f}% - {mb_done:.0f}/{mb_tot:.0f} MB)"
                        else:
                            estado_pull["porcentaje"] = ""
                        if st:
                            estado_pull["status"] = st
        except Exception as exc:
            estado_pull["error"] = str(exc)
        finally:
            estado_pull["finalizado"] = True

    hilo = threading.Thread(target=_pull_worker, daemon=True)
    hilo.start()

    tick = 0
    with Live(render_onda_animada(0, estado_pull["status"]), console=console, refresh_per_second=16) as live:
        while not estado_pull["finalizado"]:
            msg = f"{estado_pull['status']}{estado_pull['porcentaje']}"
            live.update(render_onda_animada(tick, msg))
            tick += 1
            time.sleep(0.06)
        live.update(Text(""))

    if estado_pull["error"]:
        console.print(f"[bold red]✖ Error al instalar '{nombre_modelo}':[/bold red] {estado_pull['error']}\n")
        return None

    console.print(f"[green]✔ Modelo [bold]{nombre_modelo}[/bold] instalado correctamente en Ollama.[/green]")
    resp = session.prompt([('class:prompt', f'¿Deseas activar {nombre_modelo} ahora mismo? [S/n]: ')]).strip().lower()
    if resp in ["", "s", "si", "sí", "y", "yes"]:
        return nombre_modelo
    console.print()
    return None

def cargar_memoria_largo_plazo():
    if not os.path.isfile(MEMORY_FILE):
        return []
    try:
        with open(MEMORY_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data.get("hechos", [])
    except Exception:
        return []

def guardar_hecho_memoria(nuevo_hecho):
    nuevo_hecho = nuevo_hecho.strip()
    if not nuevo_hecho:
        return False
    hechos = cargar_memoria_largo_plazo()
    if nuevo_hecho not in hechos:
        hechos.append(nuevo_hecho)
        hechos = hechos[-40:]
        os.makedirs(APP_DIR, exist_ok=True)
        with open(MEMORY_FILE, "w", encoding="utf-8") as f:
            json.dump({
                "ultima_actualizacion": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "hechos": hechos
            }, f, indent=2, ensure_ascii=False)
        return True
    return False

def registrar_turno_sesion(rol, contenido, modelo):
    if rol not in ("user", "assistant"):
        return
    os.makedirs(APP_DIR, exist_ok=True)
    entrada = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "modelo": modelo,
        "role": rol,
        "content": contenido[:2000]
    }
    try:
        with open(SESSION_LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entrada, ensure_ascii=False) + "\n")
    except Exception:
        pass

def cargar_contexto_reciente(limite_mensajes=6):
    if not os.path.isfile(SESSION_LOG_FILE):
        return []
    try:
        with open(SESSION_LOG_FILE, "r", encoding="utf-8") as f:
            lineas = f.readlines()[-limite_mensajes:]
        recientes = []
        for linea in lineas:
            item = json.loads(linea)
            recientes.append({"role": item["role"], "content": item["content"]})
        return recientes
    except Exception:
        return []

def mostrar_memoria():
    hechos = cargar_memoria_largo_plazo()
    if not hechos:
        console.print("[yellow]La memoria persistente está vacía. Usa [bold]/recordar <dato>[/bold] o conversa con el asistente.[/yellow]\n")
        return
    tabla = Table(title=f"🧠 Memoria Persistente del Usuario ({MEMORY_FILE})", border_style="cyan")
    tabla.add_column("#", justify="right", style="dim")
    tabla.add_column("Dato / Preferencia Aprendida", style="white")
    for idx, hecho in enumerate(hechos, 1):
        tabla.add_row(str(idx), hecho)
    console.print()
    console.print(tabla)
    console.print("[dim]Esta memoria se comparte automáticamente entre todos los modelos instalados.[/dim]\n")

def asegurar_ollama_activo():
    try:
        requests.get(OLLAMA_BASE, timeout=1.5)
        return
    except requests.exceptions.RequestException:
        pass

    ollama_bin = shutil.which("ollama")
    if not ollama_bin and sys.platform == "darwin":
        for ruta_brew in ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]:
            if os.path.isfile(ruta_brew):
                ollama_bin = ruta_brew
                break

    if not ollama_bin:
        console.print("[bold red]Error:[/bold red] El binario 'ollama' no está instalado o no está en el PATH.")
        sys.exit(1)

    os.makedirs(APP_DIR, exist_ok=True)
    with Live(render_onda_animada(0, "Despertando motor local de Ollama..."), console=console, refresh_per_second=16) as live:
        try:
            with open(OLLAMA_LOG, "a", encoding="utf-8") as log_file:
                if sys.platform == "win32":
                    creation_flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
                    subprocess.Popen(
                        [ollama_bin, "serve"],
                        stdout=log_file,
                        stderr=log_file,
                        creationflags=creation_flags
                    )
                else:
                    subprocess.Popen(
                        [ollama_bin, "serve"],
                        stdout=log_file,
                        stderr=log_file,
                        start_new_session=True
                    )
        except Exception as e:
            live.update(Text(""))
            console.print(f"[bold red]Error al intentar arrancar Ollama:[/bold red] {e}")
            sys.exit(1)

        for tick in range(150):
            time.sleep(0.1)
            live.update(render_onda_animada(tick, "Despertando motor local de Ollama..."))
            if tick % 5 == 0:
                try:
                    requests.get(OLLAMA_BASE, timeout=0.6)
                    live.update(Text(""))
                    return
                except requests.exceptions.RequestException:
                    continue

    console.print("[bold red]Error:[/bold red] Ollama tardó demasiado en responder.")
    console.print(f"Revisa el registro en [cyan]{OLLAMA_LOG}[/cyan] o ejecuta [cyan]ollama serve[/cyan] manualmente.")
    sys.exit(1)

def cargar_configuracion():
    os.makedirs(APP_DIR, exist_ok=True)
    if not os.path.isfile(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(DEFAULT_CONFIG, f, indent=2, ensure_ascii=False)
        except Exception:
            pass
        return DEFAULT_CONFIG.copy()
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8-sig") as f:
            datos = json.load(f)
        config = DEFAULT_CONFIG.copy()
        config.update(datos)
        return config
    except Exception:
        return DEFAULT_CONFIG.copy()

def construir_system_prompt(base_prompt, modo_agente):
    hechos = cargar_memoria_largo_plazo()
    bloque_memoria = ""
    if hechos:
        lista_hechos = "\n".join(f"- {h}" for h in hechos)
        bloque_memoria = (
            "\n\nMEMORIA PERSISTENTE SOBRE EL USUARIO Y SU FORMA DE TRABAJO:\n"
            f"{lista_hechos}\n"
            "Aplica siempre estas preferencias y contexto del usuario sin volver a preguntarlos."
        )

    instruccion_aprendizaje = (
        "\n\nSi el usuario menciona una preferencia permanente, herramienta, ruta o forma de trabajo "
        "(ej. 'siempre usa Fish', 'mi servidor está en /mnt/HDD', 'me dicen Traker'), "
        "incluye al final de tu respuesta la etiqueta <RECORDAR>resumen corto del dato</RECORDAR>."
    )

    prompt_final = f"{base_prompt}{bloque_memoria}{instruccion_aprendizaje}"

    if modo_agente:
        extra = INSTRUCCIONES_AGENTE.format(os_name=detectar_so(), cwd=os.getcwd())
        prompt_final = f"{prompt_final}\n\n{extra}"

    return prompt_final

class ConejoCompleter(Completer):
    def __init__(self):
        self.path_completer = PathCompleter(expanduser=True)

    def get_completions(self, document, complete_event):
        texto = document.text_before_cursor
        if texto.startswith("/") and " " not in texto:
            for cmd, desc in COMANDOS_INTERNOS.items():
                if cmd.startswith(texto.lower()):
                    yield Completion(cmd, start_position=-len(texto), display_meta=desc)
            return
        if texto.lower().startswith("/archivo ") or texto.lower().startswith("/guardar "):
            prefijo = texto.split(" ", 1)[1]
            sub_doc = document.__class__(prefijo, len(prefijo))
            for comp in self.path_completer.get_completions(sub_doc, complete_event):
                yield comp
            return
        if texto.lower().startswith("/modelo "):
            prefijo = texto.split(" ", 1)[1].lower()
            for m in obtener_modelos_locales():
                nombre = m.get("name", "")
                if nombre.lower().startswith(prefijo):
                    tamano_gb = m.get("size", 0) / (1024 ** 3)
                    yield Completion(nombre, start_position=-len(prefijo), display_meta=f"{tamano_gb:.2f} GB")
            return
        if texto.lower().startswith("/instalar "):
            prefijo = texto.split(" ", 1)[1].lower()
            for nombre, desc in MODELOS_SUGERIDOS.items():
                if nombre.lower().startswith(prefijo):
                    yield Completion(nombre, start_position=-len(prefijo), display_meta=desc)

def mostrar_banner(modelo_actual, temperatura, modo_agente, auto_ejecutar):
    estado_agente = "[bold green]ON[/bold green]" if modo_agente else "[dim]OFF[/dim]"
    estado_auto = "[bold red]AUTO[/bold red]" if auto_ejecutar else "[cyan]MANUAL[/cyan]"
    num_hechos = len(cargar_memoria_largo_plazo())

    banner_text = Text.from_markup(
        f"[bold bright_white]{ASCII_ART}[/bold bright_white]  [dim]v{VERSION}[/dim]\n\n"
        f"[bold cyan]Modelo:[/bold cyan] {modelo_actual} | [bold cyan]Temp:[/bold cyan] {temperatura} | "
        f"[bold cyan]Agente:[/bold cyan] {estado_agente} ({estado_auto}) | [bold cyan]Memoria:[/bold cyan] {num_hechos} hechos\n"
        f"[dim]Comandos (Tab):[/dim] [bold yellow]/agente[/bold yellow] | [bold yellow]/auto[/bold yellow] | "
        f"[bold yellow]/instalar[/bold yellow] | [bold yellow]/modelos[/bold yellow] | [bold yellow]/modelo[/bold yellow] | "
        f"[bold yellow]/actualizar[/bold yellow] | [bold yellow]/memoria[/bold yellow] | [bold yellow]/guardar[/bold yellow] | [bold yellow]/salir[/bold yellow]"
    )
    console.print(Panel(banner_text, border_style="cyan", expand=False))
    console.print()

def mostrar_config(modelo_actual, temperatura, system_prompt):
    tabla = Table(title=f"Configuración Activa ({CONFIG_FILE})", border_style="cyan")
    tabla.add_column("Parámetro", style="bold yellow")
    tabla.add_column("Valor Actual", style="white")
    tabla.add_row("Versión CLI", f"v{VERSION}")
    tabla.add_row("Sistema detectado", detectar_so())
    tabla.add_row("Instalador asignado", obtener_script_instalador_so())
    tabla.add_row("Modelo activo", modelo_actual)
    tabla.add_row("Temperatura", str(temperatura))
    tabla.add_row("Hechos en memoria", str(len(cargar_memoria_largo_plazo())))
    tabla.add_row("System Prompt Base", system_prompt)
    console.print()
    console.print(tabla)
    console.print("[dim]Edita ~/.conejo_blanco/config.json para cambiar tus valores permanentes.[/dim]\n")

def obtener_modelos_locales():
    try:
        r = requests.get(OLLAMA_TAGS_URL, timeout=3)
        r.raise_for_status()
        return r.json().get("models", [])
    except Exception:
        return []

def listar_modelos(modelo_actual):
    modelos = obtener_modelos_locales()
    if not modelos:
        console.print("[yellow]No se encontraron modelos descargados en Ollama.[/yellow]\n")
        return
    tabla = Table(title="Modelos Locales en Ollama", border_style="cyan")
    tabla.add_column("Estado", justify="center", style="green")
    tabla.add_column("Nombre del Modelo", style="bold white")
    tabla.add_column("Tamaño", justify="right", style="cyan")
    tabla.add_column("Parámetros", style="dim")
    for m in modelos:
        nombre = m.get("name", "desconocido")
        tamano_gb = m.get("size", 0) / (1024 ** 3)
        detalles = m.get("details", {})
        info_extra = f"{detalles.get('parameter_size', '?')} ({detalles.get('quantization_level', '?')})"
        activo = "● Activo" if nombre == modelo_actual or nombre == f"{modelo_actual}:latest" else ""
        tabla.add_row(activo, nombre, f"{tamano_gb:.2f} GB", info_extra)
    console.print()
    console.print(tabla)
    console.print("[dim]Usa [bold yellow]/instalar <modelo>[/bold yellow] para descargar uno nuevo o [bold yellow]/modelo <nombre>[/bold yellow] para cambiar.[/dim]\n")

def validar_modelo(nombre_modelo):
    nombres = [m.get("name", "") for m in obtener_modelos_locales()]
    return nombre_modelo in nombres or f"{nombre_modelo}:latest" in nombres

def leer_archivo(ruta):
    ruta_expandida = os.path.expanduser(ruta)
    if not os.path.isfile(ruta_expandida):
        console.print(f"[bold red]Error:[/bold red] No se encontró el archivo '{ruta}'.")
        sys.exit(1)
    with open(ruta_expandida, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def exportar_markdown(mensajes, modelo_actual, temperatura, nombre_archivo=None):
    conversacion = [m for m in mensajes if m.get("role") != "system"]
    if not conversacion:
        console.print("[yellow]No hay mensajes en la conversación actual para guardar.[/yellow]\n")
        return

    ahora = datetime.now()
    if not nombre_archivo:
        nombre_archivo = f"conejo_blanco_{ahora.strftime('%Y-%m-%d_%H-%M-%S')}.md"
    elif not nombre_archivo.endswith(".md"):
        nombre_archivo += ".md"

    ruta_salida = os.path.abspath(os.path.expanduser(nombre_archivo))
    try:
        os.makedirs(os.path.dirname(ruta_salida), exist_ok=True)
        with open(ruta_salida, "w", encoding="utf-8") as f:
            f.write("# 🐇 Sesión de Conejo Blanco CLI\n\n")
            f.write(f"- **Fecha y hora:** {ahora.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"- **Sistema:** {detectar_so()}\n")
            f.write(f"- **Modelo activo:** `{modelo_actual}` (Temperatura: `{temperatura}`)\n\n")
            f.write("---\n\n")
            for msg in conversacion:
                rol = msg.get("role")
                contenido = msg.get("content", "")
                if rol == "user":
                    f.write(f"### 👤 Usuario\n\n{contenido}\n\n")
                elif rol == "assistant":
                    f.write(f"### 🤖 Conejo Blanco (`{modelo_actual}`)\n\n{contenido}\n\n")
                f.write("---\n\n")
        console.print(f"[green]✔ Conversación exportada en:[/green] [bold cyan]{ruta_salida}[/bold cyan]\n")
    except Exception as e:
        console.print(f"[bold red]Error al guardar el archivo:[/bold red] {e}\n")

def ejecutar_comando_sistema(comando):
    """Ejecuta un comando en terminal y devuelve (codigo_salida, resumen_texto)."""
    console.print(Panel(f"[bold yellow]$ {comando}[/bold yellow]", title="⚡ Ejecutando en terminal", border_style="yellow", expand=False))

    resultado_box = {}
    error_box = {}
    terminado = threading.Event()

    def _worker():
        try:
            resultado_box["res"] = subprocess.run(
                comando,
                shell=True,
                capture_output=True,
                text=True,
                timeout=120,
                encoding="utf-8",
                errors="replace"
            )
        except Exception as exc:
            error_box["err"] = exc
        finally:
            terminado.set()

    hilo = threading.Thread(target=_worker, daemon=True)
    hilo.start()

    tick = 0
    with Live(render_onda_animada(0, "Ejecutando proceso en terminal..."), console=console, refresh_per_second=16) as live:
        while not terminado.is_set():
            live.update(render_onda_animada(tick, "Ejecutando proceso en terminal..."))
            tick += 1
            terminado.wait(0.06)
        live.update(Text(""))

    if "err" in error_box:
        err = error_box["err"]
        if isinstance(err, subprocess.TimeoutExpired):
            msg = "Error: El comando excedió el tiempo límite de 120 segundos."
        else:
            msg = f"Error al ejecutar el comando: {err}"
        console.print(f"[bold red]{msg}[/bold red]\n")
        return -1, msg

    resultado = resultado_box["res"]
    salida = ""
    if resultado.stdout:
        salida += f"STDOUT:\n{resultado.stdout}\n"
    if resultado.stderr:
        salida += f"STDERR:\n{resultado.stderr}\n"
    if not salida.strip():
        salida = "(El comando finalizó sin salida en pantalla)"

    if len(salida) > 6000:
        salida = salida[:6000] + "\n... [SALIDA TRUNCADA POR LONGITUD] ..."

    resumen = f"Código de salida: {resultado.returncode}\n{salida}"
    console.print(Panel(resumen.strip(), title="📋 Resultado del comando", border_style="dim", expand=False))
    console.print()
    return resultado.returncode, resumen

def consultar_modelo(mensajes, modelo, temperatura):
    payload = {
        "model": modelo,
        "messages": mensajes,
        "stream": True,
        "options": {"temperature": temperatura}
    }

    estado_stream = {
        "texto": "",
        "primer_token": False,
        "finalizado": False,
        "error": None,
        "not_found": False
    }

    def _leer_stream():
        try:
            with requests.post(OLLAMA_CHAT_URL, json=payload, stream=True) as r:
                if r.status_code == 404:
                    estado_stream["not_found"] = True
                    return
                r.raise_for_status()
                for linea in r.iter_lines():
                    if linea:
                        datos = json.loads(linea.decode('utf-8'))
                        fragmento = datos.get("message", {}).get("content", "")
                        if fragmento:
                            estado_stream["texto"] += fragmento
                            estado_stream["primer_token"] = True
        except Exception as exc:
            estado_stream["error"] = exc
        finally:
            estado_stream["finalizado"] = True

    hilo = threading.Thread(target=_leer_stream, daemon=True)
    hilo.start()

    tick = 0
    with Live(render_onda_animada(0, f"Procesando con {modelo}..."), console=console, refresh_per_second=16) as live:
        while not estado_stream["finalizado"]:
            texto_actual = estado_stream["texto"]
            vista_limpia = re.sub(r"<RECORDAR>.*?(?:</RECORDAR>|$)", "", texto_actual, flags=re.DOTALL | re.IGNORECASE).strip()
            if not estado_stream["primer_token"]:
                live.update(render_onda_animada(tick, f"Procesando con {modelo}..."))
            elif "<PLAN>" in texto_actual and "</PLAN>" not in texto_actual:
                live.update(render_onda_animada(tick, "Elaborando plan de acción..."))
            elif "<EJECUTAR>" in texto_actual:
                live.update(render_onda_animada(tick, "Preparando comando de terminal..."))
            else:
                vista_sin_tags = re.sub(r"<PLAN>.*?</PLAN>", "", vista_limpia, flags=re.DOTALL | re.IGNORECASE).strip()
                live.update(Markdown(vista_sin_tags + " ▌"))
            tick += 1
            time.sleep(0.06)

        if estado_stream["not_found"]:
            live.update(Text(""))
            console.print(f"[bold red]Error:[/bold red] El modelo '[yellow]{modelo}[/yellow]' no está instalado.")
            console.print(f"Instálalo con: [cyan]/instalar {modelo}[/cyan]\n")
            return None

        if estado_stream["error"] is not None:
            live.update(Text(""))
            raise estado_stream["error"]

        respuesta_final = estado_stream["texto"]
        vista_final_limpia = re.sub(r"<RECORDAR>.*?</RECORDAR>", "", respuesta_final, flags=re.DOTALL | re.IGNORECASE).strip()
        if "<EJECUTAR>" in respuesta_final or "<PLAN>" in respuesta_final:
            live.update(Text(""))
        else:
            live.update(Markdown(vista_final_limpia))

    return estado_stream["texto"]

def normalizar_comando(cmd):
    return re.sub(r"\s+", " ", cmd.strip())

def extraer_plan_accion(respuesta):
    match = re.search(r"<PLAN>(.*?)(?:</PLAN>|<EJECUTAR>|$)", respuesta, re.DOTALL | re.IGNORECASE)
    if match:
        plan = match.group(1).strip()
        if plan:
            return plan
    return None

def extraer_comando_agente(respuesta):
    match = re.search(r"<EJECUTAR>(.*?)(?:</EJECUTAR>|$)", respuesta, re.DOTALL | re.IGNORECASE)
    if match:
        cmd = match.group(1).strip()
        cmd = re.sub(r"^```(?:bash|sh|zsh|powershell)?\s*|\s*```$", "", cmd, flags=re.IGNORECASE).strip()
        if cmd:
            return cmd

    match_md = re.search(r"```(?:bash|sh|zsh|powershell)?\s*\n(.*?)\n```", respuesta, re.DOTALL | re.IGNORECASE)
    if match_md:
        return match_md.group(1).strip()

    return None

def procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session, base_prompt):
    max_iteraciones = 8
    iteracion = 0
    temp_efectiva = min(temperatura_actual, 0.15) if modo_agente else temperatura_actual

    historial_comandos = {}
    ultimo_error_firma = None
    fallos_consecutivos = 0
    plan_mostrado = False

    while iteracion < max_iteraciones:
        iteracion += 1

        mensajes_envio = list(mensajes)
        if modo_agente:
            prohibidos = ""
            if historial_comandos:
                lista_prev = ", ".join(f"`{c}`" for c in historial_comandos.keys())
                prohibidos = f" Comandos YA ejecutados en este turno (PROHIBIDO repetirlos): {lista_prev}."
            if iteracion == 1:
                instruccion_turno = (
                    "RECORDATORIO DE PLAN Y ACCIÓN: Primero escribe el listado numerado de pasos dentro de <PLAN>...</PLAN> "
                    "y en seguida el primer comando dentro de <EJECUTAR>comando</EJECUTAR>."
                )
            else:
                instruccion_turno = (
                    "RECORDATORIO: Continúa ejecutando el siguiente paso pendiente del plan con <EJECUTAR>comando</EJECUTAR>. "
                    f"No repitas <PLAN>.{prohibidos}"
                )
            mensajes_envio.append({"role": "system", "content": instruccion_turno})

        respuesta = consultar_modelo(mensajes_envio, modelo_actual, temp_efectiva)
        if respuesta is None:
            mensajes.pop()
            return

        for match_rec in re.finditer(r"<RECORDAR>(.*?)</RECORDAR>", respuesta, re.DOTALL | re.IGNORECASE):
            dato = match_rec.group(1).strip()
            if guardar_hecho_memoria(dato):
                console.print(f"[dim cyan]🧠 Memoria actualizada: {dato}[/dim cyan]")
                mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)

        respuesta_limpia = re.sub(r"<RECORDAR>.*?</RECORDAR>", "", respuesta, flags=re.DOTALL | re.IGNORECASE).strip()

        # Mostrar el Plan de Acción en pantalla antes de iniciar los comandos
        if modo_agente and not plan_mostrado:
            plan_texto = extraer_plan_accion(respuesta_limpia)
            if plan_texto:
                console.print(Panel(
                    Markdown(plan_texto),
                    title="📋 Plan de Acción del Agente",
                    border_style="cyan",
                    expand=False
                ))
                console.print()
                plan_mostrado = True

        mensajes.append({"role": "assistant", "content": respuesta_limpia})
        registrar_turno_sesion("assistant", respuesta_limpia, modelo_actual)

        if not modo_agente:
            console.print()
            return

        comando = extraer_comando_agente(respuesta_limpia)
        if not comando:
            # Si mostró el plan pero olvidó emitir <EJECUTAR> en el primer paso, forzar la ejecución del paso 1
            if plan_mostrado and iteracion == 1:
                mensajes.append({
                    "role": "user",
                    "content": "Excelente plan. Ahora ejecuta el Paso 1 respondiendo ÚNICAMENTE con <EJECUTAR>comando</EJECUTAR>."
                })
                continue
            console.print()
            return

        cmd_norm = normalizar_comando(comando)
        veces_ejecutado = historial_comandos.get(cmd_norm, 0)

        if veces_ejecutado >= 1:
            console.print(f"[bold yellow]🛡️ Protección anti-bucle:[/bold yellow] El agente intentó repetir `[white]{comando}[/white]`.")
            if veces_ejecutado >= 2:
                console.print("[bold red]🛑 Bucle detectado:[/bold red] Deteniendo ejecución autónoma para evitar ciclos infinitos.\n")
                mensajes.append({
                    "role": "user",
                    "content": (
                        f"SISTEMA: Ejecución detenida porque intentaste repetir `{comando}` múltiples veces. "
                        "Explica al usuario qué lograste hasta ahora y qué problema impidió continuar."
                    )
                })
                resp_cierre = consultar_modelo(mensajes, modelo_actual, temp_efectiva)
                if resp_cierre:
                    mensajes.append({"role": "assistant", "content": resp_cierre})
                console.print()
                return

            historial_comandos[cmd_norm] = veces_ejecutado + 1
            mensajes.append({
                "role": "user",
                "content": (
                    f"ADVERTENCIA ANTI-BUCLE: El comando `{comando}` YA fue ejecutado anteriormente y ya tienes su resultado arriba. "
                    "ESTÁ PROHIBIDO volver a ejecutarlo. Usa un comando DIFERENTE para avanzar o entrega la respuesta final en texto."
                )
            })
            continue

        autorizado = auto_ejecutar
        if not auto_ejecutar:
            console.print(f"[bold yellow]⚠ El agente solicita ejecutar:[/bold yellow] [bold white]{comando}[/bold white]")
            resp_usuario = session.prompt([('class:prompt', '¿Autorizar ejecución? [s/N]: ')]).strip().lower()
            autorizado = resp_usuario in ['s', 'si', 'sí', 'y', 'yes']

        if autorizado:
            historial_comandos[cmd_norm] = 1
            codigo_salida, salida_comando = ejecutar_comando_sistema(comando)

            if codigo_salida != 0:
                fallos_consecutivos += 1
                firma_actual = f"{codigo_salida}:{salida_comando[:200]}"
                if firma_actual == ultimo_error_firma or fallos_consecutivos >= 3:
                    console.print("[bold red]🛑 Protección anti-bucle:[/bold red] Múltiples fallos consecutivos sin progreso. Deteniendo ciclo.\n")
                    mensajes.append({
                        "role": "user",
                        "content": (
                            f"SALIDA DEL SISTEMA tras ejecutar `{comando}`:\n{salida_comando}\n\n"
                            "SISTEMA: Se detuvo la ejecución automática tras 3 errores consecutivos. "
                            "Resume claramente el error ocurrido y sugiere la solución al usuario sin emitir más etiquetas <EJECUTAR>."
                        )
                    })
                    resp_final = consultar_modelo(mensajes, modelo_actual, temp_efectiva)
                    if resp_final:
                        mensajes.append({"role": "assistant", "content": resp_final})
                    console.print()
                    return
                ultimo_error_firma = firma_actual
            else:
                fallos_consecutivos = 0
                ultimo_error_firma = None

            mensajes.append({
                "role": "user",
                "content": (
                    f"SALIDA DEL SISTEMA tras ejecutar `{comando}`:\n{salida_comando}\n\n"
                    "Analiza este resultado respecto al plan. Si hubo un error, corrígelo con un comando NUEVO. "
                    "Si falta el siguiente paso del plan, emite <EJECUTAR>nuevo_comando</EJECUTAR>. "
                    "Si todos los pasos del plan ya terminaron con éxito, entrega el resumen final en texto normal."
                )
            })
        else:
            console.print("[dim]✖ Ejecución rechazada por el usuario.[/dim]\n")
            historial_comandos[cmd_norm] = 2
            mensajes.append({
                "role": "user",
                "content": f"Comando `{comando}` rechazado por el usuario. No vuelvas a pedirlo; busca una alternativa o detente."
            })

    console.print("[yellow]⚠ Se alcanzó el límite máximo de 8 pasos autónomos por turno.[/yellow]\n")

def main():
    config = cargar_configuracion()

    parser = argparse.ArgumentParser(prog="conejo_blanco", description="Agente y Cliente CLI local para Ollama con memoria persistente.")
    parser.add_argument("prompt", nargs="*", help="Instrucción directa.")
    parser.add_argument("-m", "--model", default=config["default_model"], help="Modelo local.")
    parser.add_argument("-t", "--temperature", type=float, default=float(config["temperature"]), help="Temperatura.")
    parser.add_argument("-a", "--agent", action="store_true", help="Inicia con el modo agente activado.")
    parser.add_argument("-y", "--yes", action="store_true", help="Autoriza automáticamente los comandos del agente.")
    parser.add_argument("-l", "--list-models", action="store_true", help="Lista modelos locales.")
    parser.add_argument("-f", "--file", action="append", help="Archivos de contexto.")
    parser.add_argument("--no-history", action="store_true", help="Inicia sin cargar el contexto reciente de sesiones previas.")
    parser.add_argument("--update", action="store_true", help="Verifica en GitHub si hay una nueva versión y actualiza.")
    parser.add_argument("-v", "--version", action="store_true", help="Muestra la versión instalada.")
    args = parser.parse_args()

    if args.version:
        console.print(f"Conejo Blanco CLI v{VERSION} ({detectar_so()})")
        return

    if args.update:
        verificar_y_actualizar(forzar=False)
        return

    asegurar_ollama_activo()

    modelo_actual = args.model
    temperatura_actual = args.temperature
    base_prompt = config["system_prompt"]
    modo_agente = args.agent
    auto_ejecutar = args.yes

    if args.list_models:
        listar_modelos(modelo_actual)
        return

    mensajes = [
        {"role": "system", "content": construir_system_prompt(base_prompt, modo_agente)}
    ]

    if not args.no_history:
        recientes = cargar_contexto_reciente(limite_mensajes=6)
        if recientes:
            mensajes.extend(recientes)

    contexto_extra = []
    if not sys.stdin.isatty():
        datos_pipe = sys.stdin.read().strip()
        if datos_pipe:
            contexto_extra.append(f"--- ENTRADA POR TUBERÍA (STDIN) ---\n{datos_pipe}")
    if args.file:
        for ruta in args.file:
            contexto_extra.append(f"--- ARCHIVO: {ruta} ---\n{leer_archivo(ruta)}")

    prompt_inicial = " ".join(args.prompt).strip()

    estilo_prompt = Style.from_dict({
        'prompt': 'ansicyan bold',
        'completion-menu.completion': 'bg:#1e1e1e #ffffff',
        'completion-menu.completion.current': 'bg:#00afaf #000000 bold',
        'completion-menu.meta.completion': 'bg:#1e1e1e #888888',
        'completion-menu.meta.completion.current': 'bg:#00afaf #111111',
    })
    session = PromptSession(
        style=estilo_prompt,
        history=FileHistory(HISTORY_FILE),
        completer=ConejoCompleter(),
        complete_while_typing=False
    )

    if prompt_inicial or contexto_extra:
        bloque_contexto = "\n\n".join(contexto_extra)
        mensaje_usuario = f"{bloque_contexto}\n\n{prompt_inicial}".strip()
        mensajes.append({"role": "user", "content": mensaje_usuario})
        registrar_turno_sesion("user", mensaje_usuario, modelo_actual)
        console.print()
        procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session, base_prompt)
        return

    mostrar_banner(modelo_actual, temperatura_actual, modo_agente, auto_ejecutar)

    while True:
        try:
            prefijo_agente = "⚡" if modo_agente else "❯"
            entrada = session.prompt([('class:prompt', f'[{modelo_actual}] {prefijo_agente} ')]).strip()

            if not entrada:
                continue
            if entrada.lower() in ['/salir', 'exit', 'quit']:
                console.print("[dim]Desconectando de la Matrix...[/dim]")
                break
            if entrada.lower() == '/actualizar' or entrada.lower().startswith('/actualizar '):
                forzar_act = "--forzar" in entrada.lower() or "-f" in entrada.lower()
                verificar_y_actualizar(forzar=forzar_act)
                continue
            if entrada.lower() == '/instalar' or entrada.lower().startswith('/instalar '):
                modelo_a_instalar = entrada[9:].strip() if len(entrada) > 9 else ""
                instalado = instalar_modelo_ollama(modelo_a_instalar, session)
                if instalado:
                    modelo_actual = instalado
                    mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)
                    console.print(f"[green]✔ Modelo activo cambiado a [bold]{modelo_actual}[/bold].[/green]\n")
                continue
            if entrada.lower() == '/agente':
                modo_agente = not modo_agente
                mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)
                estado = "[bold green]ACTIVADO[/bold green]" if modo_agente else "[yellow]DESACTIVADO[/yellow]"
                console.print(f"Modo Agente ejecutor: {estado}\n")
                continue
            if entrada.lower() == '/auto':
                auto_ejecutar = not auto_ejecutar
                if auto_ejecutar and not modo_agente:
                    modo_agente = True
                    mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)
                estado = "[bold red]AUTOMÁTICO (sin confirmación)[/bold red]" if auto_ejecutar else "[cyan]MANUAL (pide confirmación)[/cyan]"
                console.print(f"Ejecución de comandos: {estado}\n")
                continue
            if entrada.lower() == '/memoria':
                mostrar_memoria()
                continue
            if entrada.lower().startswith('/recordar '):
                dato = entrada[10:].strip()
                if guardar_hecho_memoria(dato):
                    mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)
                    console.print(f"[green]🧠 Guardado en memoria permanente:[/green] [white]{dato}[/white]\n")
                else:
                    console.print("[yellow]Ese dato ya estaba en memoria o está vacío.[/yellow]\n")
                continue
            if entrada.lower() == '/olvidar':
                if os.path.isfile(MEMORY_FILE):
                    os.remove(MEMORY_FILE)
                mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)
                console.print("[yellow]🧹 Memoria persistente de largo plazo borrada.[/yellow]\n")
                continue
            if entrada.lower() == '/limpiar':
                mensajes = [{"role": "system", "content": construir_system_prompt(base_prompt, modo_agente)}]
                console.clear()
                mostrar_banner(modelo_actual, temperatura_actual, modo_agente, auto_ejecutar)
                continue
            if entrada.lower() == '/config':
                mostrar_config(modelo_actual, temperatura_actual, base_prompt)
                continue
            if entrada.lower().startswith('/temp '):
                try:
                    nueva_temp = float(entrada[6:].strip())
                    if 0.0 <= nueva_temp <= 2.0:
                        temperatura_actual = nueva_temp
                        console.print(f"[green]✔ Temperatura ajustada a [bold]{temperatura_actual}[/bold].[/green]\n")
                    else:
                        console.print("[yellow]Debe estar entre 0.0 y 2.0.[/yellow]\n")
                except ValueError:
                    console.print("[yellow]Valor inválido. Ej: /temp 0.2[/yellow]\n")
                continue
            if entrada.lower() in ['/modelos', '/models']:
                listar_modelos(modelo_actual)
                continue
            if entrada.lower() == '/guardar' or entrada.lower().startswith('/guardar '):
                archivo_destino = entrada[8:].strip() if len(entrada) > 8 else None
                exportar_markdown(mensajes, modelo_actual, temperatura_actual, archivo_destino)
                continue
            if entrada.lower().startswith('/modelo '):
                nuevo_modelo = entrada[8:].strip()
                if validar_modelo(nuevo_modelo):
                    modelo_actual = nuevo_modelo
                    mensajes[0]["content"] = construir_system_prompt(base_prompt, modo_agente)
                    console.print(f"[green]✔ Modelo cambiado a [bold]{modelo_actual}[/bold] (memoria y contexto conservados).[/green]\n")
                else:
                    console.print(f"[red]✖ El modelo '{nuevo_modelo}' no está instalado.[/red]")
                    console.print(f"[dim]Descárgalo ahora con: [bold yellow]/instalar {nuevo_modelo}[/bold yellow][/dim]\n")
                continue
            if entrada.lower().startswith('/archivo '):
                ruta = os.path.expanduser(entrada[9:].strip())
                if os.path.isfile(ruta):
                    contenido = leer_archivo(ruta)
                    mensajes.append({"role": "user", "content": f"Contenido del archivo '{ruta}':\n\n{contenido}"})
                    mensajes.append({"role": "assistant", "content": f"He leído `{ruta}`."})
                    console.print(f"[green]✔ Archivo '{ruta}' cargado.[/green]\n")
                else:
                    console.print(f"[red]✖ Archivo no encontrado.[/red]\n")
                continue

            mensajes.append({"role": "user", "content": entrada})
            registrar_turno_sesion("user", entrada, modelo_actual)
            console.print()
            procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session, base_prompt)

        except KeyboardInterrupt:
            console.print("\n[dim]Usa /salir para cerrar.[/dim]")
        except Exception as e:
            console.print(f"\n[bold red]Error:[/bold red] {e}\n")

if __name__ == "__main__":
    main()

EOF_PY
chmod +x "$APP_DIR/cli.py"

BIN_DIR="/usr/local/bin"
[ -d "/opt/homebrew/bin" ] && BIN_DIR="/opt/homebrew/bin"

LAUNCHER_SCRIPT='#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! pgrep -x "ollama" > /dev/null 2>&1; then
    nohup ollama serve > "$HOME/.conejo_blanco/ollama_serve.log" 2>&1 &
    sleep 2
fi
exec "$HOME/.conejo_blanco/venv/bin/python3" "$HOME/.conejo_blanco/cli.py" "$@"'

if [ -w "$BIN_DIR" ]; then
    printf "%s
" "$LAUNCHER_SCRIPT" > "$BIN_DIR/conejo_blanco"
    chmod +x "$BIN_DIR/conejo_blanco"
else
    sudo bash -c "printf '%s
' '$LAUNCHER_SCRIPT' > "$BIN_DIR/conejo_blanco""
    sudo chmod +x "$BIN_DIR/conejo_blanco"
fi
echo -e "${VERDE}✔ Scripts de ejecución actualizados en ${BIN_DIR}/conejo_blanco.${RESET}\n"

echo -e "${CIAN}${NEGRITA}========================================================================${RESET}"
echo -e "${VERDE}${NEGRITA}Elige la pildora correcta, ejecuta el comando conejo_blanco para iniciar${RESET}"
echo -e "${CIAN}${NEGRITA}========================================================================${RESET}"
