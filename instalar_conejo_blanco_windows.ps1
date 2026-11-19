$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$AppDir = Join-Path $env:USERPROFILE ".conejo_blanco"
$VenvDir = Join-Path $AppDir "venv"
$PythonVenv = Join-Path $VenvDir "Scripts\python.exe"
$PipVenv = Join-Path $VenvDir "Scripts\pip.exe"
$CliPyPath = Join-Path $AppDir "cli.py"
$ConfigFile = Join-Path $AppDir "config.json"

Write-Host ""
Write-Host "(\_/)" -ForegroundColor Cyan
Write-Host "(^_^)" -ForegroundColor Cyan
Write-Host "/>Conejo_blanco;" -ForegroundColor Cyan
Write-Host "by Traker" -ForegroundColor Cyan
Write-Host ""

Write-Host "=== INSTALADOR / ACTUALIZADOR DE CONEJO BLANCO (WINDOWS 10 / 11) ===" -ForegroundColor Cyan
Write-Host ""

$ModoActualizacion = $false
if ((Test-Path $CliPyPath) -and (Test-Path $PythonVenv) -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
    $ModoActualizacion = $true
    Write-Host "ℹ Instalación previa detectada en $AppDir. Se actualizarán los scripts manteniendo tu entorno y memoria." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Selecciona el modelo de IA local predeterminado para Conejo Blanco:" -ForegroundColor Yellow
Write-Host "  1) gemma2:2b          (Ultraligero ~1.6 GB, muy rápido)" -ForegroundColor Cyan
Write-Host "  2) qwen2.5-coder:3b   (Especializado en código y agente terminal ~1.9 GB)" -ForegroundColor Cyan
$OpcionModelo = Read-Host "Elige una opción [1/2] (por defecto 1)"
if ($OpcionModelo -eq "2") {
    $ModeloElegido = "qwen2.5-coder:3b"
} else {
    $ModeloElegido = "gemma2:2b"
}
Write-Host "✔ Modelo seleccionado: $ModeloElegido" -ForegroundColor Green
Write-Host ""

if (-not $ModoActualizacion) {
    Write-Host "[Paso 1/6] Verificando instalación de Python 3 y Ollama..." -ForegroundColor Yellow
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Host "Instalando Python 3.12 mediante winget..."
        winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Write-Host "Instalando Ollama mediante winget..."
        winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    Write-Host "✔ Dependencias base listas." -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "[Paso 1/6] Omitiendo instalación de paquetes winget (ya instalados)." -ForegroundColor Yellow
    Write-Host ""
}

if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Path $AppDir | Out-Null }

Write-Host "[Paso 2/6] Verificando servicio activo de Ollama..." -ForegroundColor Yellow
if (-not (Get-Process -Name "ollama*" -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 4
}
Write-Host "✔ Motor Ollama activo." -ForegroundColor Green
Write-Host ""

Write-Host "[Paso 3/6] Verificando / descargando el modelo ($ModeloElegido)..." -ForegroundColor Yellow
ollama pull $ModeloElegido
Write-Host "✔ Modelo $ModeloElegido listo." -ForegroundColor Green
Write-Host ""

Write-Host "[Paso 4/6] Verificando entorno virtual de Python y dependencias..." -ForegroundColor Yellow
if (-not (Test-Path $PythonVenv)) { python -m venv $VenvDir }
& $PipVenv install --quiet --upgrade pip
& $PipVenv install --quiet requests rich prompt_toolkit
Write-Host "✔ Entorno virtual listo." -ForegroundColor Green
Write-Host ""

Write-Host "[Paso 5/6] Guardando modelo seleccionado en $ConfigFile..." -ForegroundColor Yellow
& $PythonVenv -c "import json, os, sys; cfg=sys.argv[1]; mod=sys.argv[2]; d={'default_model':mod,'temperature':0.3,'system_prompt':'Eres un asistente técnico y agente de terminal directo, preciso y útil que responde en español.'}; d.update(json.load(open(cfg,'r',encoding='utf-8-sig'))) if os.path.isfile(cfg) else None; d['default_model']=mod; json.dump(d,open(cfg,'w',encoding='utf-8'),indent=2,ensure_ascii=False)" "$ConfigFile" "$ModeloElegido"
Write-Host "✔ Configuración actualizada con $ModeloElegido." -ForegroundColor Green
Write-Host ""

Write-Host "[Paso 6/6] Actualizando el código fuente del cliente y agente CLI (cli.py) y lanzador global..." -ForegroundColor Yellow
$PythonCode = @'
#!/usr/bin/env python3
import sys
import os
import re
import math
import json
import time
import shutil
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

OLLAMA_BASE = "http://localhost:11434"
OLLAMA_CHAT_URL = f"{OLLAMA_BASE}/api/chat"
OLLAMA_TAGS_URL = f"{OLLAMA_BASE}/api/tags"

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

INSTRUCCIONES_AGENTE = """
ERES UN AGENTE EJECUTOR DE TERMINAL CON ACCESO TOTAL AL SISTEMA ({os_name} en {cwd}).
NUNCA digas "no tengo acceso", "no puedo descargar" ni le des instrucciones al usuario para que las haga él. TÚ TIENES ACCESO DIRECTO A LA TERMINAL MEDIANTE LA ETIQUETA <EJECUTAR>.

Para realizar cualquier acción (instalar paquetes, clonar repositorios, probar scripts, verificar archivos), responde ÚNICAMENTE con:
<EJECUTAR>comando_exacto</EJECUTAR>

EJEMPLOS OBLIGATORIOS DE COMPORTAMIENTO:
Usuario: instala gTTS desde github y haz una prueba
Asistente: <EJECUTAR>pip install git+https://github.com/pndurette/gTTS.git</EJECUTAR>

Usuario: revisa si se instaló bien
Asistente: <EJECUTAR>gtts-cli --version</EJECUTAR>

Usuario: crea un audio de prueba diciendo hola
Asistente: <EJECUTAR>gtts-cli "Hola Traker, prueba de voz exitosa" --lang es --output prueba.mp3</EJECUTAR>

REGLAS:
- Emite UN solo comando por turno dentro de <EJECUTAR>...</EJECUTAR>.
- No saludes ni expliques antes de emitir <EJECUTAR>.
- Solo responde en texto normal cuando la tarea esté 100% terminada y verificada.
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
    "/agente": "Activa/desactiva el modo agente ejecutor de comandos",
    "/auto": "Activa/desactiva la ejecución automática sin pedir confirmación",
    "/memoria": "Muestra los hechos y preferencias recordadas sobre ti",
    "/recordar": "Guarda un dato permanente en memoria (ej. /recordar Uso Fish shell)",
    "/olvidar": "Borra la memoria persistente de largo plazo",
    "/modelos": "Lista los modelos descargados en Ollama",
    "/modelo": "Cambia el modelo activo (ej. /modelo qwen2.5-coder:3b)",
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

def mostrar_banner(modelo_actual, temperatura, modo_agente, auto_ejecutar):
    estado_agente = "[bold green]ON[/bold green]" if modo_agente else "[dim]OFF[/dim]"
    estado_auto = "[bold red]AUTO[/bold red]" if auto_ejecutar else "[cyan]MANUAL[/cyan]"
    num_hechos = len(cargar_memoria_largo_plazo())

    banner_text = Text.from_markup(
        f"[bold bright_white]{ASCII_ART}[/bold bright_white]\n\n"
        f"[bold cyan]Modelo:[/bold cyan] {modelo_actual} | [bold cyan]Temp:[/bold cyan] {temperatura} | "
        f"[bold cyan]Agente:[/bold cyan] {estado_agente} ({estado_auto}) | [bold cyan]Memoria:[/bold cyan] {num_hechos} hechos\n"
        f"[dim]Comandos (Tab):[/dim] [bold yellow]/agente[/bold yellow] | [bold yellow]/auto[/bold yellow] | "
        f"[bold yellow]/memoria[/bold yellow] | [bold yellow]/recordar[/bold yellow] | [bold yellow]/modelos[/bold yellow] | "
        f"[bold yellow]/modelo[/bold yellow] | [bold yellow]/archivo[/bold yellow] | [bold yellow]/guardar[/bold yellow] | [bold yellow]/salir[/bold yellow]"
    )
    console.print(Panel(banner_text, border_style="cyan", expand=False))
    console.print()

def mostrar_config(modelo_actual, temperatura, system_prompt):
    tabla = Table(title=f"Configuración Activa ({CONFIG_FILE})", border_style="cyan")
    tabla.add_column("Parámetro", style="bold yellow")
    tabla.add_column("Valor Actual", style="white")
    tabla.add_row("Sistema detectado", detectar_so())
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
    console.print()

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
        return msg

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
    return resumen

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
            elif "<EJECUTAR>" in texto_actual:
                live.update(render_onda_animada(tick, "Preparando comando de terminal..."))
            else:
                live.update(Markdown(vista_limpia + " ▌"))
            tick += 1
            time.sleep(0.06)

        if estado_stream["not_found"]:
            live.update(Text(""))
            console.print(f"[bold red]Error:[/bold red] El modelo '[yellow]{modelo}[/yellow]' no está instalado.")
            console.print(f"Descárgalo ejecutando: [cyan]ollama pull {modelo}[/cyan]\n")
            return None

        if estado_stream["error"] is not None:
            live.update(Text(""))
            raise estado_stream["error"]

        respuesta_final = estado_stream["texto"]
        vista_final_limpia = re.sub(r"<RECORDAR>.*?</RECORDAR>", "", respuesta_final, flags=re.DOTALL | re.IGNORECASE).strip()
        if "<EJECUTAR>" in respuesta_final:
            live.update(Text(""))
        else:
            live.update(Markdown(vista_final_limpia))

    return estado_stream["texto"]

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

    while iteracion < max_iteraciones:
        iteracion += 1

        mensajes_envio = list(mensajes)
        if modo_agente:
            mensajes_envio.append({
                "role": "system",
                "content": "RECORDATORIO: No des instrucciones al usuario. Si falta ejecutar algo para cumplir la orden, responde ÚNICAMENTE con <EJECUTAR>comando</EJECUTAR>."
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
        mensajes.append({"role": "assistant", "content": respuesta_limpia})
        registrar_turno_sesion("assistant", respuesta_limpia, modelo_actual)

        if not modo_agente:
            console.print()
            return

        comando = extraer_comando_agente(respuesta_limpia)
        if not comando:
            console.print()
            return

        autorizado = auto_ejecutar
        if not auto_ejecutar:
            console.print(f"\n[bold yellow]⚠ El agente solicita ejecutar:[/bold yellow] [bold white]{comando}[/bold white]")
            resp_usuario = session.prompt([('class:prompt', '¿Autorizar ejecución? [s/N]: ')]).strip().lower()
            autorizado = resp_usuario in ['s', 'si', 'sí', 'y', 'yes']

        if autorizado:
            salida_comando = ejecutar_comando_sistema(comando)
            mensajes.append({
                "role": "user",
                "content": (
                    f"SALIDA DEL SISTEMA tras ejecutar `{comando}`:\n{salida_comando}\n\n"
                    "Si hubo un error, corrígelo ejecutando otro comando con <EJECUTAR>...</EJECUTAR>. "
                    "Si falta el siguiente paso (ej. probar o verificar), emite <EJECUTAR>...</EJECUTAR>. "
                    "Si ya terminó todo con éxito, informa el resultado final."
                )
            })
        else:
            console.print("[dim]✖ Ejecución rechazada por el usuario.[/dim]\n")
            mensajes.append({
                "role": "user",
                "content": f"Comando `{comando}` rechazado por el usuario. Propón otro comando con <EJECUTAR> o detente."
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
    args = parser.parse_args()

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
                    console.print(f"[red]✖ El modelo '{nuevo_modelo}' no está instalado.[/red]\n")
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

'@
Set-Content -Path $CliPyPath -Value $PythonCode -Encoding UTF8

$BinDir = Join-Path $AppDir "bin"
if (-not (Test-Path $BinDir)) { New-Item -ItemType Directory -Path $BinDir | Out-Null }

$CmdLauncher = Join-Path $BinDir "conejo_blanco.cmd"
$CmdContent = "@echo off`r`n`"$PythonVenv`" `"$CliPyPath`" %*"
Set-Content -Path $CmdLauncher -Value $CmdContent -Encoding ASCII

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    $NewPath = if ($UserPath) { "$UserPath;$BinDir" } else { $BinDir }
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    $env:Path += ";$BinDir"
}
Write-Host "✔ Scripts de ejecución actualizados correctamente." -ForegroundColor Green
Write-Host ""

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "Elige la pildora correcta, ejecuta el comando conejo_blanco para iniciar" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Cyan
