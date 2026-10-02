#!/usr/bin/env python3
"""Run RevTrack's local, fictional fleet workspace. Never prints credentials."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / '.local'

def android_bridge(device):
    """Forward only this explicit Android target; keep the API on loopback."""
    candidates = [shutil.which('adb')]
    for variable in ('ANDROID_SDK_ROOT', 'ANDROID_HOME'):
        if os.environ.get(variable):
            candidates.append(str(Path(os.environ[variable]) / 'platform-tools/adb'))
    candidates.append(str(Path.home() / 'Library/Android/sdk/platform-tools/adb'))
    adb = next((path for path in candidates if path and Path(path).is_file()), None)
    if not adb:
        raise SystemExit('Android adb tidak ditemukan. Pasang platform-tools atau set ANDROID_SDK_ROOT.')
    subprocess.run([adb, '-s', device, 'reverse', 'tcp:8080', 'tcp:8080'], check=True)
    return adb

def free_port(port):
    with socket.socket() as probe:
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Port {port} sedang digunakan. Hentikan server RevTrack lama atau pilih sesi lain.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    targets = parser.add_mutually_exclusive_group()
    targets.add_argument('--mobile', metavar='DEVICE_ID', help='Run the native Android/iOS app on a Flutter device.')
    targets.add_argument('--web', action='store_true', help='Run the browser preview for supplementary QA.')
    parser.add_argument('--no-build', action='store_true', help='Web QA only: reuse an existing build (configuration must match).')
    parser.add_argument('--no-simulator', action='store_true', help='Leave fictional fleet data static.')
    args = parser.parse_args()
    if not args.mobile and not args.web:
        parser.print_help()
        print('\nMobile: flutter devices, lalu python3 scripts/dev.py --mobile <device-id>')
        return
    if args.no_build and not args.web:
        parser.error('--no-build hanya untuk --web; Flutter native memerlukan build sesuai perangkat.')
    free_port(8080)
    if args.web: free_port(7357)
    platform = None
    if args.mobile:
        devices = json.loads(subprocess.check_output(['flutter', 'devices', '--machine'], text=True))
        device = next((item for item in devices if item.get('id') == args.mobile), None)
        if not device:
            raise SystemExit('Device ID tidak ditemukan. Jalankan flutter devices dan gunakan ID persis.')
        platform = device.get('targetPlatform', '')
        if not platform.startswith(('android', 'ios')):
            raise SystemExit('--mobile hanya menerima perangkat Android/iOS; gunakan --web untuk browser QA.')
        if platform.startswith('ios') and not device.get('emulator', False):
            raise SystemExit('Launcher loopback ini untuk iOS simulator. iPhone fisik perlu API development HTTPS dan signing tersendiri.')
    LOCAL.mkdir(exist_ok=True)
    config_path = LOCAL / 'mobile.json'
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    config.setdefault('DEMO_API_TOKEN', secrets.token_hex(24))
    config['API_URL'] = 'http://127.0.0.1:8080'
    config.setdefault('MAPBOX_ACCESS_TOKEN', '')
    config.setdefault('MAPBOX_STYLE_URI', 'mapbox://styles/mapbox/standard')
    config_path.write_text(json.dumps(config, indent=2))
    config_path.chmod(0o600)
    token_path = LOCAL / 'device-token'
    if not token_path.exists(): token_path.write_text(secrets.token_hex(24))
    token_path.chmod(0o600)
    env = os.environ.copy()
    env.update(REVTRACK_DEMO_TOKEN=config['DEMO_API_TOKEN'], REVTRACK_DEVICE_TOKEN=token_path.read_text().strip(),
               REVTRACK_DATA_FILE=env.get('REVTRACK_DATA_FILE', str(LOCAL / 'fleet-state.json')), PORT='8080')
    env.setdefault('GOCACHE', str(LOCAL / 'go-cache'))
    binaries = LOCAL / 'bin'
    binaries.mkdir(exist_ok=True)
    for binary in ('server', 'simulator'):
        subprocess.run(['go', 'build', '-o', str(binaries / binary), f'./cmd/{binary}'], cwd=ROOT/'services/api', env=env, check=True)
    if args.web and not args.no_build:
        subprocess.run(['flutter', 'build', 'web', '--dart-define-from-file='+str(config_path)], cwd=ROOT/'apps/mobile', check=True)
    web = ROOT/'apps/mobile/build/web'
    if args.web and not (web/'index.html').exists(): raise SystemExit('Build web belum ada. Jalankan tanpa --no-build.')
    children, logs = [], []
    def spawn(command, name):
        log = (LOCAL/f'{name}.log').open('a')
        logs.append(log)
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True)
        children.append(process)
        return process
    def stop(_signal=None, _frame=None): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        server = spawn([str(binaries/'server')], 'api')
        ready = False
        for _ in range(50):
            if server.poll() is not None: raise SystemExit('API gagal dimulai. Lihat .local/api.log.')
            try:
                with urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=1) as response:
                    ready = response.status == 200
            except OSError: pass
            if ready: break
            time.sleep(.1)
        if not ready: raise SystemExit('API tidak siap dalam batas waktu.')
        if args.web:
            spawn([sys.executable, '-m', 'http.server', '7357', '--bind', '127.0.0.1', '--directory', str(web)], 'web')
        if not args.no_simulator: spawn([str(binaries/'simulator')], 'simulator')
        if args.web: print('RevTrack browser QA: http://127.0.0.1:7357', flush=True)
        print('Go API: http://127.0.0.1:8080/health · telemetri SIMULASI · data tersimpan di .local/', flush=True)
        print('Ctrl-C menghentikan server. Kredensial tidak dicetak dan tidak masuk Git.', flush=True)
        mobile = None
        if args.mobile:
            if platform.startswith('android'): android_bridge(args.mobile)
            mobile = subprocess.Popen(
                ['flutter', 'run', '-d', args.mobile, '--dart-define-from-file='+str(config_path)],
                cwd=ROOT/'apps/mobile', start_new_session=True,
            )
            children.append(mobile)
        while True:
            for process in children:
                if process.poll() is not None:
                    if process is mobile:
                        if process.returncode: raise SystemExit(process.returncode)
                        return
                    raise SystemExit('Salah satu proses berhenti. Periksa log di .local/.')
            time.sleep(1)
    except KeyboardInterrupt:
        print('\nMenghentikan workspace lokal…', flush=True)
    finally:
        for process in children:
            if process.poll() is None: os.killpg(process.pid, signal.SIGTERM)
        for process in children:
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait()
        for log in logs: log.close()

if __name__ == '__main__':
    main()
