#!/bin/bash
set -e
echo "=== CNE Precios — $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
DIA_SEMANA=$(date -u '+%u')
HORA_UTC=$(date -u '+%H')
echo "Día: ${DIA_SEMANA} | Hora UTC: ${HORA_UTC}"

if [ "$RUN_MODE" = "cron" ]; then

    echo "Limpiando volumen..."
    python3 -c "
import os, shutil
from pathlib import Path
DATA = Path(os.environ.get('DATA_DIR', '/app/data'))
salidas = sorted(DATA.glob('salida_*'), key=lambda p: p.stat().st_mtime, reverse=True)
liberado = 0
for d in salidas[8:]:
    sz = sum(f.stat().st_size for f in d.rglob('*') if f.is_file())
    shutil.rmtree(d, ignore_errors=True)
    liberado += sz
    print(f'  Borrada: {d.name} ({sz//1024//1024:.0f} MB)')
csvs = sorted(DATA.glob('precios_cne_*.csv'), key=lambda p: p.stat().st_mtime, reverse=True)
for csv in csvs[6:]:
    sz = csv.stat().st_size
    csv.unlink()
    liberado += sz
    print(f'  Borrado CSV: {csv.name}')
stat = os.statvfs(DATA)
libre = (stat.f_bavail * stat.f_frsize) // 1024 // 1024
print(f'  Libre ahora: {libre} MB')
"

    echo "Ejecutando scraper..."
    python cne_precios_reanudable_v2.py
    echo "Scraper terminado."

    if { [ "$DIA_SEMANA" = "4" ] && [ "$HORA_UTC" = "00" ]; } || [ "${FORCE_WEEKLY}" = "1" ]; then
        echo "Generando reporte semanal..."
        python reporte_semanal.py
        echo "Reporte listo."
    fi
fi

echo "Iniciando web server..."
python file_server.py
