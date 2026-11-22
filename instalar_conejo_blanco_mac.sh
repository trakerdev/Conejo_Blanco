#!/usr/bin/env bash
set -e
CONEJO_VERSION="2.1.0"

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
rm -f "$APP_DIR/historial_sesiones.jsonl"

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
import signal
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

VERSION = "2.1.0"
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
TERMINAL_LOG_FILE = os.path.join(APP_DIR, "historial_terminal.jsonl")
TASK_MEMORY_FILE = os.path.join(APP_DIR, "memoria_tareas.json")
OLLAMA_LOG = os.path.join(APP_DIR, "ollama_serve.log")

TIMEOUT_MAXIMO_SEGUNDOS = 300  # 5 minutos máximo (countdown 05:00 -> 00:00)

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

REGLAS_PELIGRO = [
    (r"\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive\s+--force)\b",
     "Eliminación recursiva forzada de archivos o directorios sin posibilidad de recuperación."),
    (r"\brm\s+.*(/|\*|~|\$HOME|%USERPROFILE%)\b",
     "Borrado con comodines o sobre rutas críticas del sistema/usuario."),
    (r"\b(rmdir|del\s+/[sq]|rd\s+/[sq]|Remove-Item\s+.*-Recurse)\b",
     "Eliminación masiva de carpetas y subdirectorios."),
    (r"\b(mkfs|fdisk|parted|gdisk|diskpart|format\s+[a-zA-Z]:)\b",
     "Formateo o modificación de tabla de particiones de disco (pérdida total de datos)."),
    (r"\bdd\s+.*of=/dev/",
     "Escritura directa a nivel de bloque sobre un dispositivo físico o partición."),
    (r"\bchmod\s+(-R\s+)?(777|000)\b|\bchown\s+-R\s+root\b",
     "Alteración crítica de permisos o propiedad de archivos que puede comprometer la seguridad o el arranque."),
    (r"\b(shutdown|reboot|halt|poweroff|init\s+[06]|Stop-Computer|Restart-Computer)\b",
     "Apagado o reinicio inmediato del sistema operativo, interrumpiendo procesos activos."),
    (r"\b(kill\s+-9\s+-1|killall|pkill\s+-9|taskkill\s+/f)\b",
     "Terminación forzada de procesos del sistema sin guardado previo."),
    (r"\b(DROP\s+DATABASE|DROP\s+TABLE|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\s*;)\b",
     "Destrucción irreversible de bases de datos, tablas o registros completos."),
    (r"\b(iptables\s+-F|ufw\s+disable|systemctl\s+(stop|disable)\s+(ssh|sshd|networking|NetworkManager))\b",
     "Desactivación del firewall o corte de conectividad de red/SSH del equipo."),
    (r"(curl|wget)\s+.*\|\s*(sudo\s+)?(ba)?sh\b",
     "Descarga y ejecución remota directa de scripts sin revisión previa de su contenido."),
    (r">\s*/etc/(passwd|shadow|sudoers|fstab|hosts)",
     "Sobrescritura directa de archivos críticos de configuración o autenticación del sistema.")
]

INSTRUCCIONES_AGENTE = """Eres un agente híbrido en {os_name} (dir: {cwd}) con acceso a terminal mediante <EJECUTAR>comando</EJECUTAR>.

REGLAS:
1. Si el usuario solo conversa o pregunta teoría, responde directo en español sin usar <PLAN> ni <EJECUTAR>.
2. Si pide una acción en el sistema (instalar, crear, revisar, ejecutar):
   - En el primer paso, escribe un plan breve (máx. 3-4 pasos) en <PLAN>...</PLAN>, una línea explicando qué harás, y el primer comando en <EJECUTAR>comando</EJECUTAR>.
   - En los pasos siguientes, responde SOLO con <EJECUTAR>siguiente_comando</EJECUTAR> sin repetir el plan.
   - Al terminar y verificar, resume el resultado en español normal sin etiquetas.
3. Usa UN solo comando por turno, compatible con {os_name}. Nunca repitas comandos ya ejecutados ni inventes salidas.
4. Pide confirmación antes de acciones destructivas (borrar carpetas, formatear, alterar permisos críticos)."""

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
    "/auto": "Activa/desactiva la ejecución automática (mantiene protección ante comandos peligrosos)",
    "/tareas": "Muestra la memoria de tareas (archivos creados, dependencias instaladas y pasos realizados)",
    "/historial": "Muestra el historial de comandos ejecutados en terminal con duración y estado",
    "/procesos": "Muestra procesos ejecutándose en segundo plano y permite consultar su salida",
    "/instalar": "Descarga e instala un modelo nuevo en Ollama (ej. /instalar qwen2.5-coder:3b)",
    "/modelos": "Lista los modelos descargados localmente en Ollama",
    "/modelo": "Cambia el modelo activo e inicia un chat limpio (ej. /modelo qwen2.5-coder:3b)",
    "/actualizar": "Verifica en GitHub si hay una versión nueva y actualiza este sistema",
    "/memoria": "Muestra los hechos y preferencias recordadas sobre ti",
    "/recordar": "Guarda un dato permanente en memoria (ej. /recordar Uso Fish shell)",
    "/olvidar": "Borra la memoria persistente de largo plazo",
    "/temp": "Ajusta la temperatura en caliente (ej. /temp 0.2)",
    "/config": "Muestra la configuración activa y ruta de config.json",
    "/archivo": "Carga un archivo al contexto de la sesión",
    "/guardar": "Exporta la conversación actual a Markdown (.md)",
    "/limpiar": "Reinicia la conversación y memoria de tareas desde cero",
    "/salir": "Limpia la sesión actual y cierra Conejo Blanco"
}

# Registro global de procesos asíncronos enviados a segundo plano
PROCESOS_BG = {}

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

def formatear_tiempo(segundos):
    segundos = max(0, int(segundos))
    mins = segundos // 60
    segs = segundos % 60
    return f"{mins:02d}:{segs:02d}"

# ==========================================================
# 1. MEMORIA DE TAREAS (Archivos, Dependencias y Pasos)
# ==========================================================
def cargar_memoria_tareas():
    vacia = {"archivos_creados": [], "dependencias_instaladas": [], "pasos_realizados": []}
    if not os.path.isfile(TASK_MEMORY_FILE):
        return vacia
    try:
        with open(TASK_MEMORY_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        for k in vacia:
            if k not in data or not isinstance(data[k], list):
                data[k] = []
        return data
    except Exception:
        return vacia

def guardar_memoria_tareas(data):
    os.makedirs(APP_DIR, exist_ok=True)
    try:
        with open(TASK_MEMORY_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except Exception:
        pass

def limpiar_memoria_tareas():
    try:
        if os.path.isfile(TASK_MEMORY_FILE):
            os.remove(TASK_MEMORY_FILE)
    except Exception:
        pass

def analizar_y_registrar_tarea(comando, codigo_salida, salida):
    """Extrae automáticamente archivos creados/modificados, dependencias instaladas y pasos ejecutados."""
    if codigo_salida != 0:
        return
    mem = cargar_memoria_tareas()
    ts = datetime.now().strftime("%H:%M:%S")
    cmd_limpio = comando.strip()

    # Registrar paso completado
    paso_entry = f"[{ts}] {cmd_limpio}"
    if paso_entry not in mem["pasos_realizados"]:
        mem["pasos_realizados"].append(paso_entry)
        mem["pasos_realizados"] = mem["pasos_realizados"][-30:]

    # Detectar dependencias instaladas (pip, apt, npm, brew, pkg, winget, cargo, go)
    patrones_dep = [
        r"(?:pip3?|python3?\s+-m\s+pip)\s+install\s+([^\n;&|]+)",
        r"(?:apt|apt-get)\s+install\s+(?:-y\s+)?([^\n;&|]+)",
        r"npm\s+(?:install|i)\s+(?:-g\s+)?([^\n;&|]+)",
        r"brew\s+install\s+([^\n;&|]+)",
        r"pkg\s+install\s+(?:-y\s+)?([^\n;&|]+)",
        r"winget\s+install\s+([^\n;&|]+)",
    ]
    for pat in patrones_dep:
        for m in re.finditer(pat, cmd_limpio, re.IGNORECASE):
            paquetes = re.sub(r"\s+--?[a-zA-Z0-9_-]+", "", m.group(1)).strip()
            if paquetes and paquetes not in mem["dependencias_instaladas"]:
                mem["dependencias_instaladas"].append(paquetes)

    # Detectar archivos creados o modificados (cat >, tee, touch, mkdir, redirección >, -o / --output)
    patrones_arch = [
        r"(?:cat\s+<<[^\n]+>\s*|tee\s+(?:-a\s+)?|touch\s+|mkdir\s+(?:-p\s+)?|>\s*)([a-zA-Z0-9_./~-]+\.[a-zA-Z0-9]+|[a-zA-Z0-9_./~-]+)",
        r"(?:-o|--output|--out)\s+([a-zA-Z0-9_./~-]+)",
        r"git\s+clone\s+\S+(?:\s+([a-zA-Z0-9_./~-]+))?"
    ]
    for pat in patrones_arch:
        for m in re.finditer(pat, cmd_limpio):
            ruta = m.group(1)
            if ruta and not ruta.startswith("-") and ruta not in ("/dev/null",):
                if ruta not in mem["archivos_creados"]:
                    mem["archivos_creados"].append(ruta)

    guardar_memoria_tareas(mem)

def mostrar_memoria_tareas():
    mem = cargar_memoria_tareas()
    if not any(mem.values()):
        console.print("[yellow]No hay tareas, archivos ni dependencias registradas en la sesión actual.[/yellow]\n")
        return

    tabla = Table(title="🗂️ Memoria de Tareas de la Sesión Actual", border_style="cyan")
    tabla.add_column("Categoría", style="bold yellow", width=24)
    tabla.add_column("Elementos Registrados", style="white")

    archivos = "\n".join(f"• {a}" for a in mem["archivos_creados"]) or "[dim]Ninguno[/dim]"
    deps = "\n".join(f"• {d}" for d in mem["dependencias_instaladas"]) or "[dim]Ninguna[/dim]"
    pasos = "\n".join(f"{i}. {p}" for i, p in enumerate(mem["pasos_realizados"][-10:], 1)) or "[dim]Ninguno[/dim]"

    tabla.add_row("Archivos creados/mod.", archivos)
    tabla.add_row("Dependencias instaladas", deps)
    tabla.add_row("Pasos realizados", pasos)

    console.print()
    console.print(tabla)
    console.print()

# ==========================================================
# 4. HISTORIAL DE TERMINAL (Comandos, Salidas, Errores, Duración)
# ==========================================================
def registrar_historial_terminal(comando, codigo_salida, salida, duracion_seg, estado="completado"):
    os.makedirs(APP_DIR, exist_ok=True)
    registro = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "cwd": os.getcwd(),
        "comando": comando,
        "codigo_salida": codigo_salida,
        "duracion_segundos": round(duracion_seg, 2),
        "estado": estado,
        "salida": salida[:3000]
    }
    try:
        with open(TERMINAL_LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(registro, ensure_ascii=False) + "\n")
    except Exception:
        pass

def mostrar_historial_terminal(limite=15):
    if not os.path.isfile(TERMINAL_LOG_FILE):
        console.print("[yellow]Aún no se han ejecutado comandos en la terminal.[/yellow]\n")
        return
    try:
        with open(TERMINAL_LOG_FILE, "r", encoding="utf-8") as f:
            lineas = f.readlines()[-limite:]
    except Exception as e:
        console.print(f"[bold red]Error al leer el historial:[/bold red] {e}\n")
        return

    if not lineas:
        console.print("[yellow]El historial de terminal está vacío.[/yellow]\n")
        return

    tabla = Table(title=f"📜 Historial de Terminal (Últimos {len(lineas)} comandos)", border_style="cyan")
    tabla.add_column("Hora", style="dim", width=10)
    tabla.add_column("Comando", style="bold white")
    tabla.add_column("Estado / Código", justify="center", width=16)
    tabla.add_column("Duración", justify="right", style="cyan", width=10)
    tabla.add_column("Resumen de Salida / Error", style="dim")

    for linea in lineas:
        try:
            item = json.loads(linea)
            hora = item.get("timestamp", "")[-8:]
            cmd = item.get("comando", "")
            code = item.get("codigo_salida", -1)
            est = item.get("estado", "")
            dur = f"{item.get('duracion_segundos', 0):.2f}s"
            resumen = item.get("salida", "").replace("\n", " ").strip()[:65]
            if est == "timeout":
                badge = "[bold red]TIMEOUT (5m)[/bold red]"
            elif est == "segundo_plano":
                badge = "[bold yellow]BG (Activo)[/bold yellow]"
            elif code == 0:
                badge = "[bold green]OK (0)[/bold green]"
            else:
                badge = f"[bold red]ERR ({code})[/bold red]"
            tabla.add_row(hora, cmd[:40], badge, dur, resumen)
        except Exception:
            continue

    console.print()
    console.print(tabla)
    console.print(f"[dim]Registro completo guardado en: {TERMINAL_LOG_FILE}[/dim]\n")

# ==========================================================
# 5. EVALUACIÓN DE RIESGO / OPERACIONES PELIGROSAS
# ==========================================================
def evaluar_peligrosidad_comando(comando):
    """Analiza si un comando representa un riesgo destructivo o crítico y devuelve la razón."""
    for patron, motivo in REGLAS_PELIGRO:
        if re.search(patron, comando, re.IGNORECASE):
            return True, motivo
    return False, None

# ==========================================================
# ANIMACIÓN ONDA BRAILLE + COUNTDOWN 5 MINUTOS + ASYNC BG
# ==========================================================
def generar_frame_onda(tick):
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

def render_onda_animada(tick, mensaje_estado, extra_info=""):
    onda = generar_frame_onda(tick)
    t = Text()
    t.append(f"{onda} ", style="bold #10b981")
    t.append(mensaje_estado, style="bold cyan")
    if extra_info:
        t.append(f"  {extra_info}", style="bold yellow")
    return t

def terminar_arbol_procesos(proc):
    """Finaliza de forma segura un proceso y sus subprocesos si excede el timeout."""
    try:
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            time.sleep(0.3)
            if proc.poll() is None:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass

def monitorear_proceso_bg(proc_id, proc, comando, inicio_ts):
    """Hilo en segundo plano que sigue trabajando si el usuario desacopla un comando largo."""
    try:
        stdout_data, stderr_data = proc.communicate(timeout=TIMEOUT_MAXIMO_SEGUNDOS)
        duracion = time.time() - inicio_ts
        salida = ""
        if stdout_data:
            salida += f"STDOUT:\n{stdout_data}\n"
        if stderr_data:
            salida += f"STDERR:\n{stderr_data}\n"
        if not salida.strip():
            salida = "(Finalizó sin salida en pantalla)"
        PROCESOS_BG[proc_id]["estado"] = "finalizado"
        PROCESOS_BG[proc_id]["codigo"] = proc.returncode
        PROCESOS_BG[proc_id]["salida"] = salida
        PROCESOS_BG[proc_id]["duracion"] = round(duracion, 2)
        registrar_historial_terminal(comando, proc.returncode, salida, duracion, estado="bg_completado")
        analizar_y_registrar_tarea(comando, proc.returncode, salida)
    except subprocess.TimeoutExpired:
        terminar_arbol_procesos(proc)
        duracion = time.time() - inicio_ts
        PROCESOS_BG[proc_id]["estado"] = "timeout"
        PROCESOS_BG[proc_id]["codigo"] = -1
        PROCESOS_BG[proc_id]["salida"] = "Proceso terminado por exceder el límite de 5 minutos (05:00)."
        PROCESOS_BG[proc_id]["duracion"] = round(duracion, 2)
        registrar_historial_terminal(comando, -1, "Timeout de 5 minutos alcanzado en segundo plano.", duracion, estado="timeout")

def mostrar_procesos_bg():
    if not PROCESOS_BG:
        console.print("[yellow]No hay procesos en segundo plano registrados en esta sesión.[/yellow]\n")
        return

    tabla = Table(title="⚙️ Procesos Asíncronos en Segundo Plano", border_style="cyan")
    tabla.add_column("ID", justify="center", style="bold yellow")
    tabla.add_column("PID", justify="center", style="dim")
    tabla.add_column("Comando", style="white")
    tabla.add_column("Estado", justify="center")
    tabla.add_column("Tiempo / Salida", style="dim")

    for pid_key, info in PROCESOS_BG.items():
        est = info["estado"]
        if est == "ejecutando":
            transcurrido = int(time.time() - info["inicio"])
            restante = max(0, TIMEOUT_MAXIMO_SEGUNDOS - transcurrido)
            badge = "[bold green]● Trabajando[/bold green]"
            detalle = f"Restante: {formatear_tiempo(restante)}"
        elif est == "finalizado":
            code = info.get("codigo", 0)
            badge = f"[cyan]✔ Terminado ({code})[/cyan]"
            detalle = info.get("salida", "").replace("\n", " ")[:55]
        else:
            badge = "[bold red]⏱ Timeout[/bold red]"
            detalle = "Excedió 05:00"

        tabla.add_row(str(pid_key), str(info["pid"]), info["comando"][:38], badge, detalle)

    console.print()
    console.print(tabla)
    console.print()

def ejecutar_comando_sistema(comando):
    """
    Ejecuta un comando con:
    - Countdown de 5 minutos máximo (05:00 -> 00:00)
    - Ejecución asíncrona no bloqueante (si tarda >12s o presionas Ctrl+C, pasa a segundo plano y sigue trabajando)
    - Registro en historial de terminal y memoria de tareas
    """
    console.print(Panel(f"[bold yellow]$ {comando}[/bold yellow]", title="⚡ Ejecutando en terminal", border_style="yellow", expand=False))

    inicio_ts = time.time()
    try:
        if sys.platform == "win32":
            proc = subprocess.Popen(
                comando,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace"
            )
        else:
            proc = subprocess.Popen(
                comando,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                preexec_fn=os.setsid
            )
    except Exception as exc:
        duracion = time.time() - inicio_ts
        msg = f"Error al iniciar el comando: {exc}"
        console.print(f"[bold red]{msg}[/bold red]\n")
        registrar_historial_terminal(comando, -1, msg, duracion, estado="error")
        return -1, msg

    tick = 0
    desacoplado = False

    with Live(render_onda_animada(0, "Ejecutando proceso...", "[⏳ 05:00]"), console=console, refresh_per_second=16) as live:
        while proc.poll() is None:
            transcurrido = time.time() - inicio_ts
            restante = TIMEOUT_MAXIMO_SEGUNDOS - transcurrido

            # 3. Control de tiempo: Timeout máximo de 5 minutos (300 segundos)
            if restante <= 0:
                terminar_arbol_procesos(proc)
                live.update(Text(""))
                duracion = time.time() - inicio_ts
                msg = f"Error: Tiempo límite de 5 minutos (05:00) agotado. Proceso PID {proc.pid} detenido."
                console.print(f"[bold red]⏱ {msg}[/bold red]\n")
                registrar_historial_terminal(comando, -1, msg, duracion, estado="timeout")
                return -1, msg

            countdown_str = f"[⏳ {formatear_tiempo(restante)}]"
            if transcurrido >= 10:
                estado_txt = "Proceso largo en curso (Ctrl+C para enviar a 2do plano)..."
            else:
                estado_txt = "Ejecutando proceso en terminal..."

            live.update(render_onda_animada(tick, estado_txt, countdown_str))
            tick += 1

            try:
                time.sleep(0.06)
            except KeyboardInterrupt:
                # 2. Ejecución asíncrona: pasar a segundo plano sin bloquear la conversación
                desacoplado = True
                live.update(Text(""))
                break

        if not desacoplado:
            live.update(Text(""))

    if desacoplado:
        proc_id = len(PROCESOS_BG) + 1
        PROCESOS_BG[proc_id] = {
            "pid": proc.pid,
            "comando": comando,
            "inicio": inicio_ts,
            "estado": "ejecutando",
            "codigo": None,
            "salida": "",
            "duracion": 0
        }
        hilo_bg = threading.Thread(
            target=monitorear_proceso_bg,
            args=(proc_id, proc, comando, inicio_ts),
            daemon=True
        )
        hilo_bg.start()

        duracion_parcial = time.time() - inicio_ts
        registrar_historial_terminal(comando, 0, f"Movido a segundo plano (ID #{proc_id}, PID {proc.pid})", duracion_parcial, estado="segundo_plano")
        msg_bg = (
            f"Proceso largo enviado a segundo plano (Tarea #{proc_id} | PID {proc.pid}). "
            "Sigue trabajando de forma asíncrona (límite 5 min). Usa /procesos para ver su avance."
        )
        console.print(Panel(f"[bold cyan]🔄 {msg_bg}[/bold cyan]", border_style="cyan", expand=False))
        console.print()
        return 0, msg_bg

    stdout_data, stderr_data = proc.communicate()
    duracion = time.time() - inicio_ts

    salida = ""
    if stdout_data:
        salida += f"STDOUT:\n{stdout_data}\n"
    if stderr_data:
        salida += f"STDERR:\n{stderr_data}\n"
    if not salida.strip():
        salida = "(El comando finalizó sin salida en pantalla)"

    if len(salida) > 6000:
        salida = salida[:6000] + "\n... [SALIDA TRUNCADA POR LONGITUD] ..."

    resumen = f"Código de salida: {proc.returncode} | Duración: {duracion:.2f}s\n{salida}"
    console.print(Panel(resumen.strip(), title=f"📋 Resultado del comando ({duracion:.2f}s)", border_style="dim", expand=False))
    console.print()

    registrar_historial_terminal(comando, proc.returncode, salida, duracion, estado="completado" if proc.returncode == 0 else "error")
    analizar_y_registrar_tarea(comando, proc.returncode, salida)

    return proc.returncode, resumen

# ==========================================================
# GESTIÓN DE ACTUALIZACIONES, OLLAMA Y MEMORIA PERSISTENTE
# ==========================================================
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

def instalar_modelo_ollama(nombre_modelo, session):
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

def limpiar_sesion_temporal():
    try:
        if os.path.isfile(SESSION_LOG_FILE):
            os.remove(SESSION_LOG_FILE)
    except Exception:
        pass

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
        lista_hechos = "\n".join(f"- {h}" for h in hechos[-15:])
        bloque_memoria = f"\n\nPreferencias del usuario:\n{lista_hechos}"

    tareas = cargar_memoria_tareas()
    bloque_tareas = ""
    if any(tareas.values()):
        partes = []
        if tareas["archivos_creados"]:
            partes.append("Archivos: " + ", ".join(tareas["archivos_creados"][-10:]))
        if tareas["dependencias_instaladas"]:
            partes.append("Paquetes: " + ", ".join(tareas["dependencias_instaladas"][-10:]))
        if tareas["pasos_realizados"]:
            partes.append("Pasos previos: " + " | ".join(tareas["pasos_realizados"][-4:]))
        bloque_tareas = "\n\nContexto de sesión:\n" + "\n".join(partes)

    if not modo_agente:
        return f"{base_prompt}{bloque_memoria}"

    extra = INSTRUCCIONES_AGENTE.format(os_name=detectar_so(), cwd=os.getcwd())
    return f"{base_prompt}{bloque_memoria}{bloque_tareas}\n\n{extra}"

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
    activos_bg = sum(1 for p in PROCESOS_BG.values() if p["estado"] == "ejecutando")
    bg_str = f" | [bold yellow]BG:[/bold yellow] {activos_bg}" if activos_bg > 0 else ""

    banner_text = Text.from_markup(
        f"[bold bright_white]{ASCII_ART}[/bold bright_white]  [dim]v{VERSION}[/dim]\n\n"
        f"[bold cyan]Modelo:[/bold cyan] {modelo_actual} | [bold cyan]Temp:[/bold cyan] {temperatura} | "
        f"[bold cyan]Agente:[/bold cyan] {estado_agente} ({estado_auto}) | [bold cyan]Memoria:[/bold cyan] {num_hechos}{bg_str}\n"
        f"[dim]Comandos (Tab):[/dim] [bold yellow]/agente[/bold yellow] | [bold yellow]/auto[/bold yellow] | "
        f"[bold yellow]/tareas[/bold yellow] | [bold yellow]/historial[/bold yellow] | [bold yellow]/procesos[/bold yellow] | "
        f"[bold yellow]/instalar[/bold yellow] | [bold yellow]/limpiar[/bold yellow] | [bold yellow]/salir[/bold yellow]"
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
    tabla.add_row("Timeout máximo", f"{TIMEOUT_MAXIMO_SEGUNDOS}s (05:00)")
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

def consultar_modelo(mensajes, modelo, temperatura):
    payload = {
        "model": modelo,
        "messages": mensajes,
        "stream": True,
        "keep_alive": "10m",
        "options": {
            "temperature": temperatura,
            "num_ctx": 2048
        }
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
        if modo_agente and historial_comandos:
            lista_prev = ", ".join(f"`{c}`" for c in historial_comandos.keys())
            mensajes_envio.append({
                "role": "system",
                "content": f"No repitas comandos ya ejecutados: {lista_prev}."
            })

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

        if modo_agente and not plan_mostrado:
            plan_texto = extraer_plan_accion(respuesta_limpia)
            if plan_texto:
                console.print(Panel(
                    Markdown(plan_texto),
                    title="📋 Plan de Acción del Agente",
                    border_style="cyan",
                    expand=False
                ))
                # Mostrar explicación breve si el modelo escribió texto fuera de las etiquetas
                texto_explicativo = re.sub(r"<PLAN>.*?</PLAN>", "", respuesta_limpia, flags=re.DOTALL | re.IGNORECASE)
                texto_explicativo = re.sub(r"<EJECUTAR>.*?(?:</EJECUTAR>|$)", "", texto_explicativo, flags=re.DOTALL | re.IGNORECASE).strip()
                if texto_explicativo:
                    console.print(Markdown(texto_explicativo))
                console.print()
                plan_mostrado = True

        mensajes.append({"role": "assistant", "content": respuesta_limpia})

        if not modo_agente:
            console.print()
            return

        comando = extraer_comando_agente(respuesta_limpia)
        if not comando:
            if plan_mostrado and iteracion == 1:
                mensajes.append({
                    "role": "user",
                    "content": "Ahora ejecuta el Paso 1 respondiendo ÚNICAMENTE con <EJECUTAR>comando</EJECUTAR>."
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

        # 5. Modo de confirmación: pedir autorización SIEMPRE si es operación peligrosa, incluso en modo /auto
        es_peligroso, motivo_peligro = evaluar_peligrosidad_comando(comando)
        autorizado = auto_ejecutar

        if es_peligroso:
            console.print(Panel(
                f"[bold red]⚠️ OPERACIÓN POTENCIALMENTE PELIGROSA DETECTADA[/bold red]\n\n"
                f"[bold white]Comando:[/bold white] [yellow]{comando}[/yellow]\n"
                f"[bold white]Motivo de riesgo:[/bold white] {motivo_peligro}\n"
                f"[dim]La confirmación obligatoria está activa incluso en modo automático (/auto).[/dim]",
                title="🚨 Alerta de Seguridad",
                border_style="red",
                expand=False
            ))
            resp_usuario = session.prompt([('class:prompt', '¿Confirmas que deseas ejecutar esta operación riesgosa? [s/N]: ')]).strip().lower()
            autorizado = resp_usuario in ['s', 'si', 'sí', 'y', 'yes']
        elif not auto_ejecutar:
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
            registrar_historial_terminal(comando, -2, "Rechazado por el usuario (alerta de seguridad/confirmación).", 0.0, estado="rechazado")
            mensajes.append({
                "role": "user",
                "content": f"Comando `{comando}` rechazado por el usuario por precaución. No vuelvas a pedirlo; busca una alternativa segura o detente."
            })

    console.print("[yellow]⚠ Se alcanzó el límite máximo de 8 pasos autónomos por turno.[/yellow]\n")

def iniciar_mensajes_limpios(base_prompt, modo_agente):
    """Crea una sesión de conversación completamente nueva sin tareas ni comandos pendientes."""
    limpiar_sesion_temporal()
    limpiar_memoria_tareas()
    return [{"role": "system", "content": construir_system_prompt(base_prompt, modo_agente)}]

def main():
    config = cargar_configuracion()

    parser = argparse.ArgumentParser(prog="conejo_blanco", description="Agente y Cliente CLI local para Ollama con memoria persistente.")
    parser.add_argument("prompt", nargs="*", help="Instrucción directa.")
    parser.add_argument("-m", "--model", default=config["default_model"], help="Modelo local.")
    parser.add_argument("-t", "--temperature", type=float, default=float(config["temperature"]), help="Temperatura.")
    parser.add_argument("-a", "--agent", action="store_true", help="Inicia con el modo agente activado.")
    parser.add_argument("-y", "--yes", action="store_true", help="Autoriza automáticamente comandos seguros del agente.")
    parser.add_argument("-l", "--list-models", action="store_true", help="Lista modelos locales.")
    parser.add_argument("-f", "--file", action="append", help="Archivos de contexto.")
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

    mensajes = iniciar_mensajes_limpios(base_prompt, modo_agente)

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
        console.print()
        procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session, base_prompt)
        limpiar_sesion_temporal()
        return

    mostrar_banner(modelo_actual, temperatura_actual, modo_agente, auto_ejecutar)

    try:
        while True:
            try:
                prefijo_agente = "⚡" if modo_agente else "❯"
                entrada = session.prompt([('class:prompt', f'[{modelo_actual}] {prefijo_agente} ')]).strip()

                if not entrada:
                    continue
                if entrada.lower() in ['/salir', 'exit', 'quit']:
                    mensajes.clear()
                    limpiar_sesion_temporal()
                    limpiar_memoria_tareas()
                    console.print("[dim]Sesión limpiada. Desconectando de la Matrix...[/dim]")
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
                        mensajes = iniciar_mensajes_limpios(base_prompt, modo_agente)
                        console.print(f"[green]✔ Modelo activo cambiado a [bold]{modelo_actual}[/bold] (nuevo chat limpio).[/green]\n")
                    continue
                if entrada.lower() == '/tareas':
                    mostrar_memoria_tareas()
                    continue
                if entrada.lower() == '/historial':
                    mostrar_historial_terminal()
                    continue
                if entrada.lower() == '/procesos':
                    mostrar_procesos_bg()
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
                    estado = "[bold red]AUTOMÁTICO (comandos peligrosos siguen pidiendo permiso)[/bold red]" if auto_ejecutar else "[cyan]MANUAL (pide confirmación)[/cyan]"
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
                    mensajes = iniciar_mensajes_limpios(base_prompt, modo_agente)
                    console.clear()
                    mostrar_banner(modelo_actual, temperatura_actual, modo_agente, auto_ejecutar)
                    console.print("[dim]✔ Conversación y memoria de tareas reiniciadas desde cero.[/dim]\n")
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
                        mensajes = iniciar_mensajes_limpios(base_prompt, modo_agente)
                        console.print(f"[green]✔ Modelo cambiado a [bold]{modelo_actual}[/bold] (nuevo chat limpio iniciado).[/green]\n")
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
                console.print()
                procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session, base_prompt)

            except KeyboardInterrupt:
                console.print("\n[dim]Usa /salir para cerrar o /limpiar para reiniciar el chat.[/dim]")
            except EOFError:
                mensajes.clear()
                limpiar_sesion_temporal()
                limpiar_memoria_tareas()
                break
            except Exception as e:
                console.print(f"\n[bold red]Error:[/bold red] {e}\n")
    finally:
        limpiar_sesion_temporal()

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
