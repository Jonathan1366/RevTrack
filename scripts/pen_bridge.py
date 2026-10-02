"""Use the installed Pen VS Code MCP bridge without changing Codex settings.

Usage: python3 scripts/pen_bridge.py get_app_state '{}'
       python3 scripts/pen_bridge.py execute @/private/tmp/pen-request.json
"""

import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time


def main():
    binary = Path.home() / '.pencil/mcp/visual_studio_code/out/mcp-server-darwin-arm64'
    interactive = sys.argv[1] == '--interactive'
    if interactive and sys.stdin.isatty():
        import termios
        attributes = termios.tcgetattr(sys.stdin)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(sys.stdin, termios.TCSANOW, attributes)
    params = sys.argv[2] if len(sys.argv) > 2 else '{}'
    if params.startswith('@'):
        params = Path(params[1:]).read_text()
    process = subprocess.Popen(
        [str(binary), '--app', 'visual_studio_code', '--agent', 'codex'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    buffer = b''

    def send(data):
        process.stdin.write((json.dumps(data) + '\n').encode())
        process.stdin.flush()

    def receive(message_id):
        nonlocal buffer
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                try:
                    data = json.loads(line)
                except ValueError:
                    continue
                if data.get('id') == message_id:
                    return data
            if select.select([process.stdout], [], [], 1)[0]:
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                buffer += chunk
        raise TimeoutError('Pen MCP did not respond')

    try:
        send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
            'protocolVersion': '2024-11-05', 'capabilities': {},
            'clientInfo': {'name': 'revtrack-design', 'version': '1.0'},
        }})
        receive(1)
        send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        if interactive:
            print('Pen VS Code bridge ready', flush=True)
        requests = sys.stdin if interactive else [json.dumps({'tool': sys.argv[1], 'arguments': json.loads(params)})]
        for message_id, request in enumerate(requests, start=2):
            if request.startswith('@'):
                request = Path(request.strip()[1:]).read_text()
            request = json.loads(request)
            send({'jsonrpc': '2.0', 'id': message_id, 'method': 'tools/call', 'params': {
                'name': request['tool'], 'arguments': request.get('arguments', {}),
            }})
            result = receive(message_id)
            # Images belong in a file, never in terminal output.
            for index, content in enumerate(result.get('result', {}).get('content', [])):
                if content.get('type') == 'image':
                    import base64
                    image_path = Path(f'/private/tmp/revtrack-pen-preview-{index}.png')
                    image_path.write_bytes(base64.b64decode(content.pop('data')))
                    content['localPath'] = str(image_path)
            print(json.dumps(result, ensure_ascii=False), flush=True)
    finally:
        process.terminate()
        process.wait(timeout=5)


if __name__ == '__main__':
    main()
