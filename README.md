# 🐇 Conejo Blanco CLI & Terminal Agent

```text
(\_/)
(-_-)
/>Conejo_blanco;
by Traker
```

![Plataformas](https://img.shields.io/badge/Plataformas-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android-blueviolet.svg)
![Python](https://img.shields.io/badge/Python-3.8+-blue.svg?logo=python&logoColor=white)
![Motor](https://img.shields.io/badge/Motor-Ollama%20Local-black.svg)
![Modelo](https://img.shields.io/badge/Modelo%20Default-Gemma%202%20(2B)-orange.svg)

**Conejo Blanco** es un cliente y **agente autónomo de línea de comandos (CLI)** 100% local para interactuar con modelos de inteligencia artificial (como **Gemma 2**) mediante **Ollama**. Inspirado en la experiencia visual de `gemini-cli`, incluye renderizado de Markdown en tiempo real, ejecución controlada de comandos en terminal (`ReAct loop`), auto-arranque del motor Ollama, lectura de archivos, tuberías (`|`) y exportación de sesiones.

---

## ✨ Características Principales

* **100% Privado y Local:** Todo el procesamiento ocurre en tu dispositivo mediante Ollama sin conexión a la nube.
* **Auto-Arranque Inteligente de Ollama:** Al ejecutar `conejo_blanco`, el sistema verifica si el servicio `ollama serve` está activo; si está detenido (por ejemplo, tras reiniciar el equipo), lo inicia silenciosamente en segundo plano antes de abrir la interfaz.
* **Modo Agente Ejecutor (`/agente` / `-a`):** Permite al modelo proponer y ejecutar comandos en tu terminal (`<EJECUTAR>...</EJECUTAR>`), leer la salida (`stdout`/`stderr`) e iterar sobre los resultados hasta resolver el diagnóstico o tarea. Incluye confirmación manual (`[s/N]`) por seguridad o modo desatendido (`/auto` / `-y`).
* **Multiplataforma Nativo:** Instaladores dedicados para **Linux**, **macOS**, **Windows** y **Android (Termux)**.
* **Productividad CLI:** Renderizado de bloques de código con `rich`, historial persistente de prompts (`↑` / `↓`), autocompletado con `Tab` para comandos, rutas y modelos, soporte de tuberías (`stdin`) y exportación a Markdown (`/guardar`).

---

## 📂 Archivos del Repositorio

| Archivo | Sistema Operativo | Descripción |
| :--- | :--- | :--- |
| `instalar_conejo_blanco_linux.sh` | **Linux** (Debian/Ubuntu) | Instalador en Bash con soporte `apt`, entorno virtual y lanzador global en `/usr/local/bin`. |
| `instalar_conejo_blanco_mac.sh` | **macOS** (Apple Silicon / Intel) | Instalador en Bash mediante Homebrew (`brew`) con soporte Metal GPU y registro automático en `/opt/homebrew/bin` o `/usr/local/bin`. |
| `instalar_conejo_blanco_windows.ps1` | **Windows 10 / 11** | Instalador en PowerShell mediante `winget` con registro automático en el `PATH` del usuario (`conejo_blanco.cmd`). |
| `instalar_conejo_blanco_android_termux.sh` | **Android** (Termux) | Instalador nativo sin `sudo` mediante `pkg` y registro en `$PREFIX/bin`. |

---

## 🚀 Instalación y Recomendaciones por Sistema Operativo

### 1. 🐧 Linux (Debian, Ubuntu, Linux Mint, elementary OS)

**Requisitos y recomendaciones:**
* Requiere acceso `sudo` para instalar paquetes base (`curl`, `python3-venv`, `python3-pip`) y registrar `/usr/local/bin/conejo_blanco`.
* Recomendado contar con al menos 4 GB de RAM libre para `gemma2:2b` (~1.6 GB).

**Instalación:**
```bash
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_linux.sh
./instalar_conejo_blanco_linux.sh
```

---

### 2. 🍎 macOS (Apple Silicon M1/M2/M3/M4 e Intel)

**Requisitos y recomendaciones:**
* Utiliza **Homebrew** (`brew`). Si no lo tienes instalado, el script lo instalará automáticamente.
* En Macs con chip **Apple Silicon**, Ollama aprovecha de forma nativa la GPU **Metal** unificada, logrando velocidades de respuesta muy altas con `gemma2:2b` o incluso modelos de 7B/9B parámetros (`ollama pull gemma2:9b`).

**Instalación:**
```bash
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_mac.sh
./instalar_conejo_blanco_mac.sh
```

---

### 3. 🪟 Windows 10 / 11

**Requisitos y recomendaciones:**
* Se recomienda ejecutarlo desde **Windows Terminal** (PowerShell 7 o Windows PowerShell) para una visualización óptima de los colores ANSI, iconos y tablas Unicode.
* Utiliza `winget` (incluido por defecto en Windows 10/11) para instalar Python 3.12 y Ollama si no están presentes.
* Tras finalizar la instalación, si ya tenías otra ventana de terminal abierta, ábrela de nuevo para que reconozca la actualización de la variable de entorno `PATH`.

**Instalación:**
```powershell
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\instalar_conejo_blanco_windows.ps1
```

---

### 4. 📱 Android (Termux)

**Requisitos y recomendaciones:**
* **Importante:** Instala **Termux** desde **F-Droid** o **GitHub** (la versión de Google Play Store está desactualizada y no soporta los repositorios modernos de `pkg`).
* Recomendado disponer de un dispositivo con al menos **6 GB u 8 GB de RAM**. Si Android cierra Termux en segundo plano por ahorro de batería o límite de memoria, descarga un modelo ultracompacto como `qwen2.5:1.5b` (`ollama pull qwen2.5:1.5b`) y configúralo en `~/.conejo_blanco/config.json`.
* Para permitir que `conejo_blanco` lea archivos de tu carpeta de Descargas o Documentos de Android, ejecuta previamente `termux-setup-storage`.

**Instalación:**
```bash
pkg install -y git
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_android_termux.sh
./instalar_conejo_blanco_android_termux.sh
```

---

## 💻 Guía de Uso y Comandos

Una vez instalado en cualquiera de los 4 sistemas, inicia simplemente escribiendo:
```bash
conejo_blanco
```
*(El sistema levantará `ollama serve` automáticamente si no estaba corriendo).*

### Comandos Internos (dentro del chat — usa `Tab` para autocompletar)

| Comando | Descripción |
| :--- | :--- |
| `/agente` | Enciende o apaga el **Modo Agente** (cambia el indicador del prompt de `❯` a `⚡`). |
| `/auto` | Alterna entre pedir confirmación `[s/N]` antes de ejecutar cada comando o ejecutar automáticamente. |
| `/modelos` | Muestra una tabla con todos los modelos locales descargados en Ollama y su tamaño. |
| `/modelo <nombre>` | Cambia el modelo activo en caliente conservando el historial (ej. `/modelo qwen2.5-coder:3b`). |
| `/archivo <ruta>` | Lee un archivo local y lo inyecta en la memoria de la conversación actual. |
| `/guardar [archivo.md]` | Exporta la conversación completa a un archivo Markdown con fecha y hora. |
| `/temp <0.0 - 2.0>` | Ajusta la temperatura (creatividad) del modelo para la sesión actual. |
| `/config` | Muestra los parámetros activos y la ruta de `config.json`. |
| `/limpiar` | Reinicia el historial de la conversación actual y limpia la pantalla. |
| `/salir` | Cierra la sesión (`exit` y `quit` también funcionan). |

---

### Ejemplos en Modo Directo (One-Shot) y Agente

* **Iniciar directamente como Agente en terminal:**
  ```bash
  conejo_blanco -a
  ```

* **Diagnosticar el sistema de forma autónoma (con confirmación paso a paso):**
  ```bash
  conejo_blanco -a "Revisa el uso de disco, memoria RAM y qué procesos consumen más CPU"
  ```

* **Analizar un archivo de código o configuración (`-f`):**
  ```bash
  conejo_blanco -f nginx.conf "Verifica si hay errores de sintaxis o mejoras de seguridad"
  ```

* **Procesar salida de comandos por tubería (`|`):**
  * *Linux / macOS / Termux:*
    ```bash
    tail -n 40 /var/log/syslog | conejo_blanco "Resume los errores críticos"
    ```
  * *Windows PowerShell:*
    ```powershell
    Get-Content .\error.log -Tail 40 | conejo_blanco "Resume los errores críticos"
    ```

* **Elegir modelo y temperatura al vuelo (`-m` y `-t`):**
  ```bash
  conejo_blanco -m gemma2:2b -t 0.1 -f script.py "Optimiza este código"
  ```

---

## ⚙️ Configuración Personalizada (`~/.conejo_blanco/config.json`)

Puedes editar el archivo de configuración en tu directorio de usuario (`%USERPROFILE%\.conejo_blanco\config.json` en Windows o `~/.conejo_blanco/config.json` en Unix/Android):

```json
{
  "default_model": "gemma2:2b",
  "temperature": 0.3,
  "system_prompt": "Eres un asistente técnico y agente de terminal directo, preciso y útil que responde en español."
}
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
