#!/usr/bin/env bash
set -e

VERDE='\033[0;32m'
CIAN='\033[0;36m'
AMARILLO='\033[1;33m'
NEGRITA='\033[1m'
RESET='\033[0m'

echo -e "${CIAN}${NEGRITA}"
cat << 'EOF'
(\_/)
(-_-)
/>Conejo_blanco;
by Traker
EOF
echo -e "${RESET}"

echo -e "${CIAN}${NEGRITA}=== INICIANDO INSTALACIÓN DE CONEJO BLANCO (LINUX DEBIAN/UBUNTU) ===${RESET}\n"

echo -e "${AMARILLO}[Paso 1/7] Actualizando repositorios e instalando dependencias base (curl, python3, venv, pip)...${RESET}"
sudo apt-get update -qq
sudo apt-get install -y -qq curl python3 python3-venv python3-pip
echo -e "${VERDE}✔ Dependencias del sistema listas.${RESET}\n"

echo -e "${AMARILLO}[Paso 2/7] Verificando e instalando Ollama para ejecutar modelos locales...${RESET}"
if ! command -v ollama &> /dev/null; then
    echo "Descargando e instalando Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama ya se encuentra instalado en el sistema."
fi

APP_DIR="$HOME/.conejo_blanco"
mkdir -p "$APP_DIR"

if ! pgrep -x "ollama" > /dev/null; then
    echo "Iniciando el servicio de Ollama en segundo plano..."
    nohup ollama serve > "$APP_DIR/ollama_serve.log" 2>&1 &
    sleep 3
fi
echo -e "${VERDE}✔ Motor Ollama activo.${RESET}\n"

MODELO_DEFAULT="gemma2:2b"
echo -e "${AMARILLO}[Paso 3/7] Descargando el modelo ligero de Google (${MODELO_DEFAULT})...${RESET}"
echo "Esto puede tardar unos minutos dependiendo de tu velocidad de internet (~1.6 GB)."
ollama pull $MODELO_DEFAULT
echo -e "${VERDE}✔ Modelo ${MODELO_DEFAULT} descargado y listo.${RESET}\n"

echo -e "${AMARILLO}[Paso 4/7] Creando directorio en ${APP_DIR} y entorno virtual de Python...${RESET}"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/venv/bin/pip" install --quiet requests rich prompt_toolkit
echo -e "${VERDE}✔ Entorno virtual y librerías de interfaz instaladas.${RESET}\n"

CONFIG_FILE="$APP_DIR/config.json"
echo -e "${AMARILLO}[Paso 5/7] Verificando archivo de configuración en ${CONFIG_FILE}...${RESET}"
if [ ! -f "$CONFIG_FILE" ]; then
    cat << 'EOF' > "$CONFIG_FILE"
{
  "default_model": "gemma2:2b",
  "temperature": 0.3,
  "system_prompt": "Eres un asistente técnico y agente de terminal directo, preciso y útil que responde en español."
}
EOF
    echo -e "${VERDE}✔ Archivo config.json inicial creado.${RESET}\n"
else
    echo -e "${VERDE}✔ Se conservó tu archivo config.json existente.${RESET}\n"
fi

echo -e "${AMARILLO}[Paso 6/7] Escribiendo el código fuente del cliente y agente CLI en Python...${RESET}"
cat << 'EOF_PY' > "$APP_DIR/cli.py"
#!/usr/bin/env python3
import sys
import os
import re
import json
import time
import shutil
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
OLLAMA_LOG = os.path.join(APP_DIR, "ollama_serve.log")

DEFAULT_CONFIG = {
    "default_model": "gemma2:2b",
    "temperature": 0.3,
    "system_prompt": "Eres un asistente técnico y agente de terminal directo, preciso y útil que responde en español."
}

INSTRUCCIONES_AGENTE = """
MODO AGENTE DE TERMINAL ACTIVADO.
Sistema operativo actual: {os_name} | Directorio actual: {cwd}

Tienes capacidad para ejecutar comandos en la terminal del usuario y leer su salida para diagnosticar, explorar archivos o realizar tareas.
Cuando necesites ejecutar un comando en el sistema, responde ÚNICAMENTE con el comando envuelto exactamente en estas etiquetas, sin texto adicional antes ni después:
<EJECUTAR>comando aquí</EJECUTAR>

Reglas estrictas:
1. Ejecuta un solo comando por turno.
2. Tras emitir <EJECUTAR>...</EJECUTAR>, detente y espera a recibir la salida del sistema.
3. Una vez que recibas el resultado del comando, analízalo. Si necesitas más información, emite otro <EJECUTAR>...</EJECUTAR>. Cuando tengas la respuesta completa para el usuario, respóndele en español normal sin usar etiquetas.
"""

ASCII_ART = r"""(\_/)
(-_-)
/>Conejo_blanco;
by Traker"""

console = Console()

COMANDOS_INTERNOS = {
    "/agente": "Activa/desactiva el modo agente ejecutor de comandos",
    "/auto": "Activa/desactiva la ejecución automática sin pedir confirmación",
    "/modelos": "Lista los modelos descargados en Ollama",
    "/modelo": "Cambia el modelo activo (ej. /modelo gemma2:2b)",
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

def asegurar_ollama_activo():
    """Valida si Ollama responde; si no, lo inicia en segundo plano y espera a que esté listo."""
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
    with console.status("[cyan]🐇 Iniciando motor local de Ollama en segundo plano...[/cyan]", spinner="dots"):
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
            console.print(f"[bold red]Error al intentar arrancar Ollama:[/bold red] {e}")
            sys.exit(1)

        for _ in range(30):
            time.sleep(0.5)
            try:
                requests.get(OLLAMA_BASE, timeout=1)
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
    if not modo_agente:
        return base_prompt
    extra = INSTRUCCIONES_AGENTE.format(os_name=detectar_so(), cwd=os.getcwd())
    return f"{base_prompt}\n\n{extra}"

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

    banner_text = Text.from_markup(
        f"[bold bright_white]{ASCII_ART}[/bold bright_white]\n\n"
        f"[bold cyan]Modelo:[/bold cyan] {modelo_actual} | [bold cyan]Temp:[/bold cyan] {temperatura} | "
        f"[bold cyan]Agente:[/bold cyan] {estado_agente} ({estado_auto})\n"
        f"[dim]Comandos (Tab):[/dim] [bold yellow]/agente[/bold yellow] | [bold yellow]/auto[/bold yellow] | "
        f"[bold yellow]/modelos[/bold yellow] | [bold yellow]/modelo[/bold yellow] | [bold yellow]/archivo[/bold yellow] | "
        f"[bold yellow]/guardar[/bold yellow] | [bold yellow]/limpiar[/bold yellow] | [bold yellow]/salir[/bold yellow]"
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
    tabla.add_row("System Prompt", system_prompt)
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
    try:
        resultado = subprocess.run(
            comando,
            shell=True,
            capture_output=True,
            text=True,
            timeout=60,
            encoding="utf-8",
            errors="replace"
        )
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
    except subprocess.TimeoutExpired:
        msg = "Error: El comando excedió el tiempo límite de 60 segundos."
        console.print(f"[bold red]{msg}[/bold red]\n")
        return msg
    except Exception as e:
        msg = f"Error al ejecutar el comando: {e}"
        console.print(f"[bold red]{msg}[/bold red]\n")
        return msg

def consultar_modelo(mensajes, modelo, temperatura):
    respuesta_completa = ""
    payload = {
        "model": modelo,
        "messages": mensajes,
        "stream": True,
        "options": {"temperature": temperatura}
    }

    with Live(Markdown("▌"), console=console, refresh_per_second=12) as live:
        with requests.post(OLLAMA_CHAT_URL, json=payload, stream=True) as r:
            if r.status_code == 404:
                live.update(Text(""))
                console.print(f"[bold red]Error:[/bold red] El modelo '{modelo}' no está instalado.\n")
                return None
            r.raise_for_status()
            for linea in r.iter_lines():
                if linea:
                    datos = json.loads(linea.decode('utf-8'))
                    fragmento = datos.get("message", {}).get("content", "")
                    respuesta_completa += fragmento
                    if "<EJECUTAR>" in respuesta_completa:
                        live.update(Text("🐇 Analizando acción de terminal...", style="dim cyan"))
                    else:
                        live.update(Markdown(respuesta_completa + " ▌"))
        
        if "<EJECUTAR>" in respuesta_completa:
            live.update(Text(""))
        else:
            live.update(Markdown(respuesta_completa))
    
    return respuesta_completa

def procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session):
    max_iteraciones = 8
    iteracion = 0

    while iteracion < max_iteraciones:
        iteracion += 1
        respuesta = consultar_modelo(mensajes, modelo_actual, temperatura_actual)
        if respuesta is None:
            mensajes.pop()
            return

        mensajes.append({"role": "assistant", "content": respuesta})

        match = re.search(r"<EJECUTAR>(.*?)</EJECUTAR>", respuesta, re.DOTALL | re.IGNORECASE)
        if not match or not modo_agente:
            console.print()
            return

        comando = match.group(1).strip()
        if not comando:
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
                "content": f"Resultado de ejecutar `{comando}`:\n\n{salida_comando}\n\nAnaliza este resultado y continúa con la tarea o responde al usuario."
            })
        else:
            console.print("[dim]✖ Ejecución rechazada por el usuario.[/dim]\n")
            mensajes.append({
                "role": "user",
                "content": f"El usuario rechazó ejecutar el comando `{comando}`. Busca una alternativa o explica qué necesitas sin ejecutarlo."
            })

    console.print("[yellow]⚠ Se alcanzó el límite máximo de 8 pasos autónomos por turno.[/yellow]\n")

def main():
    config = cargar_configuracion()

    parser = argparse.ArgumentParser(prog="conejo_blanco", description="Agente y Cliente CLI local para Ollama.")
    parser.add_argument("prompt", nargs="*", help="Instrucción directa.")
    parser.add_argument("-m", "--model", default=config["default_model"], help="Modelo local.")
    parser.add_argument("-t", "--temperature", type=float, default=float(config["temperature"]), help="Temperatura.")
    parser.add_argument("-a", "--agent", action="store_true", help="Inicia con el modo agente activado.")
    parser.add_argument("-y", "--yes", action="store_true", help="Autoriza automáticamente los comandos del agente.")
    parser.add_argument("-l", "--list-models", action="store_true", help="Lista modelos locales.")
    parser.add_argument("-f", "--file", action="append", help="Archivos de contexto.")
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
        procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session)
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
                    console.print(f"[green]✔ Modelo cambiado a [bold]{modelo_actual}[/bold].[/green]\n")
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
            console.print()
            procesar_turno_agente(mensajes, modelo_actual, temperatura_actual, modo_agente, auto_ejecutar, session)

        except KeyboardInterrupt:
            console.print("\n[dim]Usa /salir para cerrar.[/dim]")
        except Exception as e:
            console.print(f"\n[bold red]Error:[/bold red] {e}\n")

if __name__ == "__main__":
    main()

EOF_PY
chmod +x "$APP_DIR/cli.py"
echo -e "${VERDE}✔ Código Python generado correctamente.${RESET}\n"

echo -e "${AMARILLO}[Paso 7/7] Configurando el comando global 'conejo_blanco' en /usr/local/bin...${RESET}"
sudo bash -c "cat << 'EOF_BIN' > /usr/local/bin/conejo_blanco
#!/usr/bin/env bash
if ! pgrep -x "ollama" > /dev/null 2>&1; then
    nohup ollama serve > "\$HOME/.conejo_blanco/ollama_serve.log" 2>&1 &
    sleep 2
fi
exec "\$HOME/.conejo_blanco/venv/bin/python3" "\$HOME/.conejo_blanco/cli.py" "\$@"
EOF_BIN"
sudo chmod +x /usr/local/bin/conejo_blanco
echo -e "${VERDE}✔ Comando global registrado.${RESET}\n"

echo -e "${CIAN}${NEGRITA}========================================================================${RESET}"
echo -e "${VERDE}${NEGRITA}Elige la pildora correcta, ejecuta el comando conejo_blanco para iniciar${RESET}"
echo -e "${CIAN}${NEGRITA}========================================================================${RESET}"
