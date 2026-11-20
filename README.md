# 🐇 Conejo Blanco CLI & Terminal Agent (v2.0.0)

```text
(\_/)
(^_^)
/>Conejo_blanco;
by Traker
```

![Versión](https://img.shields.io/badge/Versión-v2.0.0-brightgreen.svg)
![Plataformas](https://img.shields.io/badge/Plataformas-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android-blueviolet.svg)
![Python](https://img.shields.io/badge/Python-3.8+-blue.svg?logo=python&logoColor=white)
![Motor](https://img.shields.io/badge/Motor-Ollama%20Local-black.svg)
![Modelos](https://img.shields.io/badge/Modelos-Gemma%202%20%7C%20Qwen2.5--Coder-orange.svg)

**Conejo Blanco** es un cliente y **agente autónomo de línea de comandos (CLI)** 100% local para interactuar con modelos de inteligencia artificial mediante **Ollama**. Inspirado en la experiencia visual de `gemini-cli`, incluye memoria de tareas de sesión, ejecución asíncrona no bloqueante, temporizador countdown de 5 minutos, historial de auditoría de terminal, guardián de seguridad para comandos peligrosos y auto-actualización por sistema operativo.

---

## ✨ Novedades Principales (v2.0.0)

* **🗂️ Memoria de Tareas de Sesión (`/tareas`):** Registra automáticamente en `~/.conejo_blanco/memoria_tareas.json` los **archivos creados/modificados**, las **dependencias instaladas** (`pip`, `apt`, `npm`, `brew`, `pkg`, `winget`) y los **pasos realizados**, inyectándolos en el contexto del agente para que nunca pierda el hilo de lo que ya construyó.
* **🔄 Ejecución Asíncrona No Bloqueante (`/procesos`):** Si un comando tarda más de 10 segundos (compilaciones, descargas pesadas, servidores), puedes enviarlo a segundo plano con `Ctrl+C` para seguir conversando mientras la onda Braille sigue trabajando en paralelo.
* **⏳ Control de Tiempo con Countdown de 5 Minutos:** Todos los comandos cuentan con un temporizador visible (`[⏳ 05:00]` → `[⏳ 00:00]`) que detiene el árbol de procesos automáticamente si alcanza los 5 minutos, evitando cuelgues infinitos.
* **📜 Historial de Auditoría de Terminal (`/historial`):** Guarda en `~/.conejo_blanco/historial_terminal.jsonl` cada comando ejecutado, su salida, errores, código de retorno y duración exacta en segundos.
* **🚨 Guardián de Seguridad en Modo Automático (`/auto`):** Incluso con `/auto` o `-y` activados, intercepta operaciones destructivas o críticas (`rm -rf`, formateo de discos, `chmod 777`, `DROP DATABASE`, `shutdown`, `curl | sh`, etc.), muestra un panel de alerta explicando **por qué es peligroso** y exige confirmación explícita `[s/N]`.
* **🧹 Sesiones Limpias al Iniciar, Limpiar o Cerrar:** Cada inicio, `/limpiar`, `/salir` o cambio de modelo (`/modelo`) reinicia el chat y la memoria de tareas desde cero sin comandos colgados.

---

## 📂 Archivos del Repositorio

| Archivo | Sistema Operativo | Descripción |
| :--- | :--- | :--- |
| `instalar_conejo_blanco_linux.sh` | **Linux** (Debian/Ubuntu/elementary OS) | Instalador/actualizador en Bash con soporte `apt`, detección de `SUDO_USER` y lanzador global en `/usr/local/bin`. |
| `instalar_conejo_blanco_mac.sh` | **macOS** (Apple Silicon / Intel) | Instalador/actualizador mediante Homebrew (`brew`) con soporte Metal GPU y registro automático en `/opt/homebrew/bin` o `/usr/local/bin`. |
| `instalar_conejo_blanco_windows.ps1` | **Windows 10 / 11** | Instalador/actualizador en PowerShell mediante `winget` con registro automático en el `PATH` del usuario (`conejo_blanco.cmd`). |
| `instalar_conejo_blanco_android_termux.sh` | **Android** (Termux) | Instalador/actualizador nativo sin `sudo` mediante `pkg` y registro en `$PREFIX/bin`. |

---

## 🚀 Instalación por Sistema Operativo

### 1. 🐧 Linux (Debian, Ubuntu, Linux Mint, elementary OS)
```bash
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_linux.sh
./instalar_conejo_blanco_linux.sh
```

### 2. 🍎 macOS (Apple Silicon M1/M2/M3/M4 e Intel)
```bash
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_mac.sh
./instalar_conejo_blanco_mac.sh
```

### 3. 🪟 Windows 10 / 11 (PowerShell / Windows Terminal)
```powershell
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\instalar_conejo_blanco_windows.ps1
```

### 4. 📱 Android (Termux desde F-Droid / GitHub)
```bash
pkg install -y git
git clone https://github.com/TrakerDev/conejo_blanco.git
cd conejo_blanco
chmod +x instalar_conejo_blanco_android_termux.sh
./instalar_conejo_blanco_android_termux.sh
```

---

## 💻 Comandos Disponibles

| Comando | Descripción |
| :--- | :--- |
| `/agente` | Enciende o apaga el **Modo Agente** (muestra un **Plan de Acción** numerado antes de ejecutar comandos). |
| `/auto` | Alterna ejecución automática para comandos seguros (los comandos peligrosos **siempre** piden autorización). |
| `/tareas` | Muestra los archivos creados, dependencias instaladas y pasos realizados en la sesión. |
| `/historial` | Muestra el registro de comandos ejecutados con su estado, duración y resumen de salida. |
| `/procesos` | Lista los procesos enviados a segundo plano con su tiempo restante y resultado. |
| `/instalar <modelo>` | Descarga e instala un modelo nuevo mediante Ollama con progreso en vivo (usa `Tab` para sugerencias). |
| `/modelos` | Lista los modelos locales descargados en Ollama. |
| `/modelo <nombre>` | Cambia el modelo activo e inicia un nuevo chat limpio conservando tu memoria persistente. |
| `/actualizar` | Verifica en GitHub si hay una nueva versión, descarga el instalador de tu SO y actualiza (`--forzar` reinstala). |
| `/memoria` | Muestra los hechos y preferencias guardadas en `memoria_usuario.json`. |
| `/recordar <dato>` | Guarda manualmente una preferencia o regla permanente. |
| `/olvidar` | Borra la memoria persistente de largo plazo. |
| `/archivo <ruta>` | Carga un archivo local al contexto de la sesión. |
| `/guardar [archivo.md]` | Exporta la conversación completa a Markdown. |
| `/temp <0.0 - 2.0>` | Ajusta la temperatura del modelo en la sesión actual. |
| `/config` | Muestra los parámetros activos, versión y ruta de `config.json`. |
| `/limpiar` | Reinicia la conversación y memoria de tareas desde cero. |
| `/salir` | Limpia la sesión actual y cierra el programa. |

---

## 🗑️ Desinstalación

* **Linux / macOS:** `rm -rf ~/.conejo_blanco && sudo rm -f /usr/local/bin/conejo_blanco /opt/homebrew/bin/conejo_blanco`
* **Android (Termux):** `rm -rf ~/.conejo_blanco $PREFIX/bin/conejo_blanco`
* **Windows (PowerShell):** `Remove-Item -Recurse -Force "$env:USERPROFILE\.conejo_blanco"`
