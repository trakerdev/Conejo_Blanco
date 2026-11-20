# 🐇 Conejo Blanco CLI & Terminal Agent (v1.9.0)

```text
(\_/)
(^_^)
/>Conejo_blanco;
by Traker
```

![Versión](https://img.shields.io/badge/Versión-v1.9.0-brightgreen.svg)
![Plataformas](https://img.shields.io/badge/Plataformas-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android-blueviolet.svg)
![Python](https://img.shields.io/badge/Python-3.8+-blue.svg?logo=python&logoColor=white)
![Motor](https://img.shields.io/badge/Motor-Ollama%20Local-black.svg)
![Modelos](https://img.shields.io/badge/Modelos-Gemma%202%20%7C%20Qwen2.5--Coder-orange.svg)

**Conejo Blanco** es un cliente y **agente autónomo de línea de comandos (CLI)** 100% local para interactuar con modelos de inteligencia artificial mediante **Ollama**. Inspirado en la experiencia visual de `gemini-cli`, incluye planificación explícita antes de actuar (`<PLAN>`), protección anti-bucle, descarga directa de modelos desde el chat (`/instalar`), actualización automática por sistema operativo desde GitHub (`/actualizar`), memoria persistente compartida entre modelos y onda Braille animada en una línea (`#10b981`).

---

## ✨ Novedades y Características Principales

* **📋 Plan de Acción Estructurado en Modo Agente (`/agente` / `-a`):** Antes de ejecutar el primer comando de una tarea, el agente despliega un panel con la lista numerada de pasos (`📋 Plan de Acción del Agente`) y procede a ejecutarlos secuencialmente.
* **🛡️ Protección Anti-Bucle:** Detecta si el modelo intenta repetir un comando ya ejecutado o si encadena 3 fallos consecutivos sin progreso, bloqueando el ciclo automáticamente.
* **⬇️ Instalación Directa de Modelos (`/instalar <modelo>`):** Descarga cualquier modelo disponible en Ollama (con barra de progreso en MB y porcentaje en vivo y autocompletado con `Tab` para modelos recomendados como `qwen2.5-coder:3b`, `gemma2:2b`, `llama3.2:3b`, `deepseek-coder-v2`) y te permite activarlo al instante.
* **🔄 Auto-Actualización Inteligente (`/actualizar` o `--update`):** Consulta el repositorio `TrakerDev/conejo_blanco` en GitHub, compara la versión remota contra la instalada localmente, descarga **únicamente** el instalador correspondiente a tu sistema operativo (`linux`, `mac`, `windows` o `android_termux`) y lo ejecuta conservando tu entorno y memoria.
* **🌊 Animación de Onda Braille en Una Línea:** Onda sinusoidal compacta de 3 celdas Braille (`4x6` puntos) en color esmeralda (`#10b981`) durante descargas, inferencia y ejecución de comandos.
* **🧠 Memoria Persistente Compartida entre Modelos:** Guarda preferencias y datos clave en `~/.conejo_blanco/memoria_usuario.json` (`<RECORDAR>...</RECORDAR>` o `/recordar`) y conserva continuidad reciente entre sesiones (`--no-history` para iniciar limpio).

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
| `/auto` | Alterna entre pedir confirmación `[s/N]` antes de ejecutar cada comando o ejecutar automáticamente. |
| `/instalar <modelo>` | Descarga e instala un modelo nuevo mediante Ollama con progreso en vivo (usa `Tab` para ver sugerencias). |
| `/modelos` | Lista los modelos locales descargados en Ollama. |
| `/modelo <nombre>` | Cambia el modelo activo en caliente conservando memoria e historial. |
| `/actualizar` | Verifica en GitHub si hay una nueva versión, descarga el instalador de tu SO y actualiza (`--forzar` reinstala). |
| `/memoria` | Muestra los hechos y preferencias guardadas en `memoria_usuario.json`. |
| `/recordar <dato>` | Guarda manualmente una preferencia o regla permanente. |
| `/olvidar` | Borra la memoria persistente de largo plazo. |
| `/archivo <ruta>` | Carga un archivo local al contexto de la sesión. |
| `/guardar [archivo.md]` | Exporta la conversación completa a Markdown. |
| `/temp <0.0 - 2.0>` | Ajusta la temperatura del modelo en la sesión actual. |
| `/config` | Muestra los parámetros activos, versión y ruta de `config.json`. |
| `/limpiar` | Reinicia la conversación actual y limpia la pantalla. |
| `/salir` | Cierra la sesión. |

---

## 🗑️ Desinstalación

* **Linux / macOS:** `rm -rf ~/.conejo_blanco && sudo rm -f /usr/local/bin/conejo_blanco /opt/homebrew/bin/conejo_blanco`
* **Android (Termux):** `rm -rf ~/.conejo_blanco $PREFIX/bin/conejo_blanco`
* **Windows (PowerShell):** `Remove-Item -Recurse -Force "$env:USERPROFILE\.conejo_blanco"`
