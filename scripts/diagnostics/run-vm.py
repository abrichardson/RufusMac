"""Boot regression runner; captures the framebuffer after the GUI reports ready."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

firmware, monitor, *command = sys.argv[1:]
log = Path('/out/boot-test-' + firmware + '.log')
log.unlink(missing_ok=True)
process = subprocess.Popen(command)
deadline = time.monotonic() + 300
captured = False
try:
    while process.poll() is None:
        if time.monotonic() > deadline:
            raise TimeoutError('Virtual boot did not complete within 300 seconds')
        if not captured and log.exists() and 'MACUS_GUI_READY' in log.read_text(errors='replace'):
            time.sleep(1)  # Let X finish painting after the GUI-ready event.
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(3)
                client.connect(monitor)
                response = b''
                while b'(qemu)' not in response:
                    response += client.recv(4096)
                client.sendall(('screendump /out/boot-screen-' + firmware + '.ppm\n').encode())
                response = b''
                while b'(qemu)' not in response:
                    response += client.recv(4096)
            captured = True
        time.sleep(0.1)
    sys.exit(process.returncode)
except BaseException:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
    raise
