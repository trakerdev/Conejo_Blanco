# 🐇 Conejo Blanco CLI & Terminal Agent

```text
(\_/)
(^_^)
/>Conejo_blanco;
by Traker
```

![Plataformas](https://img.shields.io/badge/Plataformas-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android-blueviolet.svg)
![Python](https://img.shields.io/badge/Python-3.8+-blue.svg?logo=python&logoColor=white)
![Motor](https://img.shields.io/badge/Motor-Ollama%20Local-black.svg)
![Modelos](https://img.shields.io/badge/Modelos-Gemma%202%20%7C%20Qwen2.5--Coder-orange.svg)

**Conejo Blanco** es un cliente y **agente autónomo de línea de comandos (CLI)** 100% local para interactuar con modelos de inteligencia artificial mediante **Ollama**. Inspirado en la experiencia visual de `gemini-cli`, incluye memoria persistente compartida entre modelos, renderizado de Markdown en tiempo real, ejecución controlada de comandos en terminal (`ReAct loop`), animación de onda Braille compacta en una línea (`#10b981`), auto-arranque del motor Ollama, lectura de archivos, tuberías (`|`) y exportación de sesiones.

---

## ✨ Novedades y Características Principales

* **🌊 Animación de Onda Braille en Una Línea:** Mientras el modelo procesa solicitudes, arranca Ollama o ejecuta comandos en terminal, se renderiza una onda sinusoidal compacta de 3 celdas Braille (`4x6` puntos en una sola línea) en color esmeralda (`#10b981`).
* **🧠 Memoria Persistente Compartida entre Modelos:**
  * **Perfil de Largo Plazo (`~/.conejo_blanco/memoria_usuario.json`):** Guarda automáticamente tus preferencias, herramientas y forma de trabajar (`<RECORDAR>...</RECORDAR>` o mediante `/recordar`). Cualquier modelo que elijas (`gemma2:2b`, `qwen2.5-coder:3b`, etc.) hereda tu contexto desde el inicio.
  * **Continuidad Episódica (`~/.conejo_blanco/historial_sesiones.jsonl`):** Conserva el registro de conversaciones recientes entre sesiones para dar continuidad inmediata sin importar si cambiaste de modelo (puedes iniciar limpio usando `--no-history`).
* **Selector Interactivo de Modelo al Instalar/Actualizar:** Al ejecutar el instalador puedes elegir entre **`gemma2:2b`** (ultraligero ~1.6 GB) o **`qwen2.5-coder:3b`** (especializado en programación y comandos de terminal ~1.9 GB), guardando tu elección automáticamente en `config.json`.
* **Actualización Inteligente:** Si ya tenías instalado Conejo Blanco, el instalador lo detecta automáticamente, omite la reinstalación de paquetes base y actualiza únicamente `cli.py`, el lanzador global y la configuración del modelo conservando tu memoria e historial.
* **Modo Agente Proactivo (`/agente` / `-a`):** Permite al modelo ejecutar comandos en tu terminal (`<EJECUTAR>...</EJECUTAR>`), leer la salida (`stdout`/`stderr`) e iterar sobre errores o siguientes pasos de forma autónoma con confirmación manual (`[s/N]`) o automática (`/auto` / `-y`).
* **Auto-Arranque de Ollama:** Al ejecutar `conejo_blanco`, verifica si `ollama serve` está activo; si no lo está, lo levanta en segundo plano automáticamente.

---

## 📂 Archivos del Repositorio

| Archivo | Sistema Operativo | Descripción |
| :--- | :--- | :--- |
| `instalar_conejo_blanco_linux.sh` | **Linux** (Debian/Ubuntu/elementary OS) | Instalador/actualizador en Bash con soporte `apt`, detección de `SUDO_USER` y lanzador global en `/usr/local/bin`. |
| `instalar_conejo_blanco_mac.sh` | **macOS** (Apple Silicon / Intel) | Instalador/actualizador mediante Homebrew (`brew`) con soporte Metal GPU y registro automático en `/opt/homebrew/bin` o `/usr/local/bin`. |
| `instalar_conejo_blanco_windows.ps1` | **Windows 10 / 11** | Instalador/actualizador en PowerShell mediante `winget` con registro automático en el `PATH` del usuario (`conejo_blanco.cmd`). |
| `instalar_conejo_blanco_android_termux.sh` | **Android** (Termux) | Instalador/actualizador nativo sin `sudo` mediante `pkg` y registro en `$PREFIX/bin`. |

---

## 🚀 Instalación y Actualización por Sistema Operativo

### 1. 🐧 Linux (Debian, Ubuntu, Linux Mint, elementary OS)

**Requisitos y recomendaciones:**
* Se recomienda ejecutarlo **sin `sudo`** (`./instalar_conejo_blanco_linux.sh`); el script solicitará contraseña únicamente para instalar dependencias del sistema y registrar `/usr/local/bin/conejo_blanco`, manteniendo `~/.conejo_blanco` bajo tu usuario.
* Si planeas usar el **Modo Agente (`-a`)** para que ejecute comandos por su cuenta, elige la opción **`2) qwen2.5-coder:3b`** durante la instalación.

```bash
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_linux.sh
./instalar_conejo_blanco_linux.sh
```

---

### 2. 🍎 macOS (Apple Silicon M1/M2/M3/M4 e Intel)

**Requisitos y recomendaciones:**
* Utiliza **Homebrew** (`brew`). Si no está presente, el script lo instala automáticamente.
* En Macs con chip **Apple Silicon**, Ollama utiliza la GPU **Metal** unificada de forma nativa, ejecutando `qwen2.5-coder:3b` y `gemma2:2b` a máxima velocidad.

```bash
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_mac.sh
./instalar_conejo_blanco_mac.sh
```

---

### 3. 🪟 Windows 10 / 11

**Requisitos y recomendaciones:**
* Ejecútalo en **Windows Terminal** (PowerShell) para visualizar correctamente los caracteres Braille Unicode (`U+2800`–`U+28FF`) y los colores ANSI.
* Utiliza `winget` para instalar Python 3.12 y Ollama si no están en el sistema.

```powershell
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\instalar_conejo_blanco_windows.ps1
```

---

### 4. 📱 Android (Termux)

**Requisitos y recomendaciones:**
* Instala **Termux** desde **F-Droid** o **GitHub** (evita la versión desactualizada de Google Play Store).
* En teléfonos con 6 GB u 8 GB de RAM, elige la opción **`1) gemma2:2b`** si buscas menor consumo de memoria, o **`2) qwen2.5-coder:3b`** si dispones de 8+ GB de RAM.
* Ejecuta `termux-setup-storage` previamente si deseas analizar archivos de tu carpeta de Descargas.

```bash
pkg install -y git
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_android_termux.sh
./instalar_conejo_blanco_android_termux.sh
```

---

## 💻 Guía de Uso y Comandos

Inicia el asistente desde cualquier ruta ejecutando:
```bash
conejo_blanco
```
O entra directamente en **Modo Agente** para que ejecute tareas en tu terminal:
```bash
conejo_blanco -a
```

### Comandos Internos (usa `Tab` para autocompletar)

| Comando | Descripción |
| :--- | :--- |
| `/agente` | Enciende o apaga el **Modo Agente** (cambia el prompt de `❯` a `⚡`). |
| `/auto` | Alterna entre pedir confirmación `[s/N]` antes de ejecutar cada comando o ejecutar automáticamente. |
| `/memoria` | Muestra la tabla de hechos y preferencias guardadas en `memoria_usuario.json`. |
| `/recordar <dato>` | Guarda manualmente una preferencia o regla permanente (ej. `/recordar Siempre usa Fish shell`). |
| `/olvidar` | Borra la memoria persistente de largo plazo para iniciar desde cero. |
| `/modelos` | Muestra una tabla con todos los modelos locales descargados en Ollama y su tamaño. |
| `/modelo <nombre>` | Cambia el modelo activo en caliente conservando memoria e historial (ej. `/modelo qwen2.5-coder:3b`). |
| `/archivo <ruta>` | Lee un archivo local y lo inyecta en la memoria de la conversación actual. |
| `/guardar [archivo.md]` | Exporta la conversación completa a un archivo Markdown con fecha y hora. |
| `/temp <0.0 - 2.0>` | Ajusta la temperatura del modelo para la sesión actual. |
| `/config` | Muestra los parámetros activos y la ruta de `config.json`. |
| `/limpiar` | Reinicia el historial de la conversación actual y limpia la pantalla. |
| `/salir` | Cierra la sesión (`exit` y `quit` también funcionan). |

---

### Ejemplos en Modo Directo (One-Shot) y Agente

* **Tarea autónoma paso a paso (con confirmación):**
  ```bash
  conejo_blanco -a "Verifica si Python y pip están instalados, revisa el espacio en disco y dame un resumen"
  ```

* **Analizar un archivo de código o configuración (`-f`):**
  ```bash
  conejo_blanco -f nginx.conf "Verifica si hay errores de sintaxis o mejoras de seguridad"
  ```

* **Procesar salida de comandos por tubería (`|`):**
  ```bash
  tail -n 40 /var/log/syslog | conejo_blanco "Resume los errores críticos"
  ```

* **Iniciar una sesión limpia sin cargar mensajes previos:**
  ```bash
  conejo_blanco --no-history
  ```

---

## ⚙️ Estructura de Archivos (`~/.conejo_blanco/`)

```text
~/.conejo_blanco/
├── cli.py                     # Cliente y agente CLI multiplataforma
├── config.json                # Modelo por defecto, temperatura y system prompt
├── memoria_usuario.json       # Memoria persistente compartida entre todos los modelos
├── historial_sesiones.jsonl   # Registro episódico de conversaciones recientes
├── historial_prompts          # Historial de entradas para flechas ↑ / ↓
├── ollama_serve.log           # Log del servidor local Ollama
└── venv/                      # Entorno virtual aislado de Python
```

---

## 🗑️ Desinstalación

* **Linux / macOS:**
  ```bash
  rm -rf ~/.conejo_blanco
  sudo rm -f /usr/local/bin/conejo_blanco /opt/homebrew/bin/conejo_blanco
  ```
* **Android (Termux):**
  ```bash
  rm -rf ~/.conejo_blanco $PREFIX/bin/conejo_blanco
  ```
* **Windows (PowerShell):**
  ```powershell
  Remove-Item -Recurse -Force "$env:USERPROFILE\.conejo_blanco"
  ```
