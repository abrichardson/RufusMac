import sys, subprocess, time, socket, os
from pathlib import Path
firmware, monitor, *command = sys.argv[1:]
log = Path('/out/quickscan-' + firmware + '.log')
log.unlink(missing_ok=True)
start = time.monotonic()
process = subprocess.Popen(command)
captured = False
expect_failure = os.environ.get('EXPECT_SAVE_FAILURE') == '1'
try:
    while process.poll() is None:
        text = log.read_text(errors='replace') if log.exists() else ''
        if 'QUICKSCAN_ERROR' in text:
            if not expect_failure:
                raise RuntimeError(text)
            time.sleep(5)
            assert process.poll() is None, 'Save failure incorrectly powered off'
            assert 'QUICKSCAN_SAVED' not in text
            print(f'{firmware}: save failure displayed and PC stayed on', flush=True)
            break
        if time.monotonic() - start > 240:
            raise TimeoutError('Quick Scan VM exceeded 240 seconds')
        if 'QUICKSCAN_SAVED' in text and not captured:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(3)
                client.connect(monitor)
                def prompt():
                    data = b''
                    while b'(qemu)' not in data:
                        part = client.recv(4096)
                        if not part:
                            raise OSError('Monitor closed')
                        data += part
                prompt()
                client.sendall(('screendump /out/quickscan-' + firmware + '.ppm\n').encode())
                prompt()
            captured = True
        time.sleep(0.1)
    if expect_failure:
        assert 'QUICKSCAN_ERROR' in log.read_text(errors='replace')
        sys.exit(0)
    assert process.returncode == 0 and 'QUICKSCAN_SAVED' in log.read_text(errors='replace')
    print(f'{firmware}: complete in {time.monotonic()-start:.1f}s of emulated VM wall time', flush=True)
finally:
    if process.poll() is None:
        process.terminate()
        try: process.wait(timeout=10)
        except subprocess.TimeoutExpired: process.kill()
