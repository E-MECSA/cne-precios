#!/bin/bash
# start.sh v3 — limpia el volumen PRIMERO, luego corre scraper
set -e
echo "=== CNE Precios — $(date '+%Y-%m-%d %H:%M:%S %Z') ==="

DIA_SEMANA=$(date -u '+%u')
HORA_UTC=$(date -u '+%H')
echo "Día: ${DIA_SEMANA} | Hora UTC: ${HORA_UTC}"

if [ "$RUN_MODE" = "cron" ]; then

    # ── LIMPIEZA ANTES DE CORRER ─────────────────────────────────────────
    echo "🧹 Limpiando volumen..."
    python3 - << 'PYEOF'
import os, shutil
from pathlib import Path
from datetime import datetime, timedelta

DATA = Path(os.environ.get('DATA_DIR', '/app/data'))
KEEP = 8       # conservar últimas N carpetas salida_*
KEEP_CSVS = 6  # conservar últimos N CSV en raíz

stat = os.statvfs(DATA)
libre_mb = (stat.f_bavail * stat.f_frsize) / 1024 / 1024
print(f"  Espacio libre antes: {libre_mb:.0f} MB")

# Borrar carpetas salida_* más antiguas (conservar las KEEP más recientes)
salidas = sorted(DATA.glob('salida_*'), key=lambda p: p.stat().st_mtime, reverse=True)
liberado = 0
for d in salidas[KEEP:]:
    sz = sum(f.stat().st_size for f in d.rglob('*') if f.is_file())
    shutil.rmtree(d, ignore_errors=True)
    liberado += sz
    print(f"  Borrada: {d.name} ({sz//1024//1024:.0f} MB)")

# Borrar CSVs de raíz (conservar los KEEP_CSVS más recientes)
csvs = sorted(DATA.glob('precios_cne_*.csv'), key=lambda p: p.stat().st_mtime, reverse=True)
for csv in csvs[KEEP_CSVS:]:
    sz = csv.stat().st_size
    csv.unlink()
    liberado += sz
    print(f"  Borrado CSV: {csv.name}")

stat2 = os.statvfs(DATA)
libre_mb2 = (stat2.f_bavail * stat2.f_frsize) / 1024 / 1024
print(f"  Espacio libre después: {libre_mb2:.0f} MB (liberados {liberado//1024//1024:.0f} MB)")
PYEOF

    # ── SCRAPER ──────────────────────────────────────────────────────────
    echo "▶ Ejecutando scraper..."
    python cne_precios_reanudable_v2.py
    echo "✅ Scraper terminado."

    # ── REPORTE SEMANAL (jueves 00:00 UTC = 18:00 México, o FORCE_WEEKLY) ─
    if { [ "$DIA_SEMANA" = "4" ] && [ "$HORA_UTC" = "00" ]; } || [ "${FORCE_WEEKLY}" = "1" ]; then
        echo "📊 Generando reporte semanal..."
        python reporte_semanal.py
        echo "✅ Reporte listo."
        [ "${FORCE_WEEKLY}" = "1" ] && echo "ℹ️  Recuerda quitar FORCE_WEEKLY de las variables."
    fi
fi

echo "🌐 Iniciando web server..."
python file_server.py
