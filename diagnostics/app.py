#!/usr/bin/env python3
"""Offline, automatically launched graphical diagnostics appliance."""
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, messagebox
import inventory
import storage


class DiagnosticsApp:
    def __init__(self, root):
        self.root = root
        self.report = None
        self.destinations = []
        self.events = queue.Queue()
        self.busy = False
        self.test_mode = 'macus.selftest=1' in (inventory.read('/proc/cmdline') or '')
        root.title('Macus Diagnostics')
        root.geometry(f'{min(1100, root.winfo_screenwidth() - 20)}x{min(760, root.winfo_screenheight() - 60)}+0+0')
        root.minsize(720, 520)
        root.protocol('WM_DELETE_WINDOW', self.close)
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('.', font=('DejaVu Sans', 11))
        style.configure('TButton', padding=(12, 9))
        style.configure('Title.TLabel', font=('DejaVu Sans', 24, 'bold'), foreground='#145d72')
        self.status = tk.StringVar(value='Starting hardware scan…')
        self.asset = tk.StringVar()
        self.destination = tk.StringVar()
        outer = ttk.Frame(root, padding=22)
        outer.pack(fill='both', expand=True)
        ttk.Label(outer, text='Macus Diagnostics', style='Title.TLabel').pack(anchor='w')
        ttk.Label(outer, text='Scan. Check. Save.  •  Runs offline from your USB.').pack(anchor='w', pady=(4, 14))
        row = ttk.Frame(outer)
        row.pack(fill='x')
        ttk.Label(row, text='Asset ID (optional)').pack(side='left')
        ttk.Entry(row, textvariable=self.asset, width=26).pack(side='left', padx=12)
        self.rescan = ttk.Button(row, text='Scan again', command=self.scan)
        self.rescan.pack(side='right')
        tabs = ttk.Notebook(outer)
        summary = ttk.Frame(tabs, padding=12)
        tabs.add(summary, text='Hardware')
        self.summary = tk.Text(summary, wrap='word', font=('DejaVu Sans', 12), relief='flat', padx=10, pady=10)
        scroll = ttk.Scrollbar(summary, command=self.summary.yview)
        self.summary.configure(yscrollcommand=scroll.set, state='disabled')
        scroll.pack(side='right', fill='y')
        self.summary.pack(fill='both', expand=True)
        checks_tab = ttk.Frame(tabs)
        tabs.add(checks_tab, text='Checks & notes')
        checks_canvas = tk.Canvas(checks_tab, highlightthickness=0)
        checks_scroll = ttk.Scrollbar(checks_tab, command=checks_canvas.yview)
        checks_canvas.configure(yscrollcommand=checks_scroll.set)
        checks_scroll.pack(side='right', fill='y')
        checks_canvas.pack(fill='both', expand=True)
        checks = ttk.Frame(checks_canvas, padding=12)
        checks_canvas.create_window((0, 0), window=checks, anchor='nw')
        checks.bind('<Configure>', lambda _: checks_canvas.configure(scrollregion=checks_canvas.bbox('all')))
        self.checks = {}
        hints = dict(inventory.CHECKS)
        hints['display'] = 'Use Screen colors in Extra tests; inspect pixels and backlight.'
        hints['keyboard'] = 'Use Keyboard check in Extra tests. Record the result here.'
        hints['audio'] = 'Use Speaker check in Extra tests. Microphone needs a separate check.'
        hints['camera'] = 'Preview is not included in this image; leave not tested unless checked separately.'
        hints['network'] = 'Adapters are inventoried. Leave not tested unless connectivity was checked separately.'
        for i, (name, hint) in enumerate(hints.items()):
            value = tk.StringVar(value='not tested')
            self.checks[name] = value
            ttk.Label(checks, text=name.capitalize(), width=13).grid(row=i, column=0, sticky='w', pady=2)
            ttk.Combobox(checks, textvariable=value, values=['not tested', 'pass', 'fail', 'not applicable'], state='readonly', width=15).grid(row=i, column=1, padx=8)
            ttk.Label(checks, text=hint, wraplength=400, font=('DejaVu Sans', 9)).grid(row=i, column=2, sticky='w')
        self.cosmetics = tk.StringVar(value='not graded')
        ttk.Label(checks, text='Cosmetics').grid(row=9, column=0, sticky='w', pady=6)
        ttk.Combobox(checks, textvariable=self.cosmetics, values=['not graded', 'excellent', 'good', 'fair', 'poor'], state='readonly', width=15).grid(row=9, column=1, padx=8)
        ttk.Label(checks, text='Notes / missing parts').grid(row=10, column=0, columnspan=2, sticky='w')
        self.notes = tk.Text(checks, height=3, wrap='word', font=('DejaVu Sans', 10))
        self.notes.grid(row=11, column=0, columnspan=3, sticky='ew')
        tests = ttk.Frame(tabs, padding=18)
        tabs.add(tests, text='Extra tests')
        ttk.Label(tests, text='Optional tests — connect power first', font=('DejaVu Sans', 15, 'bold')).pack(anchor='w', pady=10)
        ttk.Label(tests, text='These limited checks do not certify the whole machine.\nRAM testing covers 256 MiB, not all installed memory.').pack(anchor='w', pady=12)
        self.cpu = ttk.Button(tests, text='Test CPU · 60 seconds', command=lambda: self.test('cpu'))
        self.cpu.pack(anchor='w', pady=6)
        self.memory = ttk.Button(tests, text='Test memory · one 256 MiB pass', command=lambda: self.test('memory'))
        self.memory.pack(anchor='w', pady=6)
        manual = ttk.Frame(tests)
        manual.pack(anchor='w', pady=10)
        ttk.Button(manual, text='Screen colors', command=self.screen_test).pack(side='left', padx=(0, 8))
        ttk.Button(manual, text='Keyboard check', command=self.keyboard_test).pack(side='left', padx=8)
        ttk.Button(manual, text='Speaker check', command=self.speaker_test).pack(side='left', padx=8)
        self.test_status = tk.StringVar(value='No extra tests run.')
        ttk.Label(tests, textvariable=self.test_status, wraplength=750).pack(anchor='w', pady=20)
        status_label = ttk.Label(outer, textvariable=self.status, wraplength=950)
        footer = ttk.Frame(outer)
        self.usbs = ttk.Combobox(footer, textvariable=self.destination, state='readonly', width=34)
        self.usbs.pack(side='left')
        self.retry = ttk.Button(footer, text='Find USB', command=self.find_usb)
        self.retry.pack(side='left', padx=8)
        actions = ttk.Frame(outer)
        self.save_button = ttk.Button(actions, text='Save report', command=lambda: self.save(False))
        self.save_button.pack(side='right', padx=8)
        self.shutdown_button = ttk.Button(actions, text='Save & Shut Down', command=lambda: self.save(True))
        self.shutdown_button.pack(side='right')
        # Reserve the controls first; the notebook takes the remaining space.
        actions.pack(side='bottom', fill='x', pady=(8, 0))
        footer.pack(side='bottom', fill='x')
        status_label.pack(side='bottom', anchor='w', pady=(0, 8))
        tabs.pack(fill='both', expand=True, pady=14)
        self.root.after(100, self.poll)
        self.root.after(250, self.scan)

    def work(self, action, kind):
        if self.busy:
            return
        self.busy = True
        self.buttons()
        def job():
            try:
                self.events.put((kind, action()))
            except Exception as error:
                self.events.put(('error', str(error)))
        threading.Thread(target=job, daemon=True).start()

    def buttons(self):
        for button in [self.rescan, self.retry]:
            button.configure(state='disabled' if self.busy else 'normal')
        for button in [self.cpu, self.memory]:
            button.configure(state='disabled' if self.busy or self.report is None else 'normal')
        ready = not self.busy and self.report is not None and self.destination.get() in [str(p) for p in self.destinations]
        for button in [self.save_button, self.shutdown_button]:
            button.configure(state='normal' if ready else 'disabled')

    def screen_test(self):
        popup = tk.Toplevel(self.root)
        popup.attributes('-fullscreen', True)
        colors = ['white', 'black', 'red', 'green', 'blue', '#808080']
        index = [0]
        label = tk.Label(popup, text='Click or Space: next color   •   Esc: return', font=('DejaVu Sans', 14))
        label.pack(side='bottom', pady=24)
        def advance(event=None):
            color = colors[index[0] % len(colors)]
            popup.configure(bg=color)
            label.configure(bg=color, fg='white' if color in ['black', 'blue'] else 'black')
            index[0] += 1
        popup.bind('<Button-1>', advance)
        popup.bind('<space>', advance)
        popup.bind('<Escape>', lambda _: popup.destroy())
        advance()
        popup.focus_force()

    def keyboard_test(self):
        popup = tk.Toplevel(self.root)
        popup.title('Keyboard check')
        popup.geometry('720x400')
        label = ttk.Label(popup, text='Type every key. Check modifiers too. Close when done.', padding=16)
        label.pack(fill='x')
        box = tk.Text(popup, font=('DejaVu Sans', 15), wrap='word')
        box.pack(fill='both', expand=True, padx=16)
        box.bind('<KeyPress>', lambda event: label.configure(text='Last key: ' + event.keysym + '   |   keycode: ' + str(event.keycode)))
        ttk.Button(popup, text='Done — record result in Checks', command=popup.destroy).pack(pady=12)
        box.focus_set()

    def speaker_test(self):
        if self.busy:
            return
        self.status.set('Playing left/right speaker audio. Listen, then record the result in Checks.')
        self.work(lambda: inventory.run(['speaker-test', '-c', '2', '-t', 'wav', '-l', '1'], timeout=20), 'speaker')

    def scan(self):
        self.status.set('Scanning hardware and finding your report USB…')
        self.work(lambda: (inventory.collect(), storage.find_storage()), 'scan')

    def find_usb(self):
        self.status.set('Looking for a USB prepared by Macus…')
        self.work(storage.find_storage, 'storage')

    def set_storage(self, paths):
        self.destinations = paths
        self.usbs.configure(values=[str(p) for p in paths])
        self.destination.set(str(paths[0]) if len(paths) == 1 else '')
        self.usbs.bind('<<ComboboxSelected>>', lambda _: self.buttons())
        if not paths:
            self.status.set('Scan ready. No writable report USB found. Insert a USB prepared with Macus, then click Find USB. Results remain in memory.')
        elif len(paths) > 1:
            self.status.set('Several report USBs found. Choose one below before saving.')
        else:
            self.status.set('Ready. Add an asset ID or checks, then Save & Shut Down.')

    def render(self):
        report = self.report
        system = report['system']
        def value(item):
            return str(item) if item is not None and item != '' else 'Unknown'
        def size(item):
            try:
                return f'{int(item) / (1024 ** 3):.1f} GiB'
            except (TypeError, ValueError):
                return 'Unknown'
        lines = [
            'Device: ' + value(system.get('manufacturer')) + ' ' + value(system.get('model')),
            'Serial: ' + value(system.get('serial')),
            'Processor: ' + value(system.get('cpu')),
            'Usable memory: ' + size(system.get('usable_memory_bytes')),
        ]
        lines.append(inventory.hardware_details(report))
        if report['batteries']:
            lines += ['Battery: ' + value(b.get('health_percent')) + '% of design capacity · cycles: ' + value(b.get('cycle_count')) for b in report['batteries']]
        else:
            lines += ['Battery: none reported']
        firmware = report['firmware']
        secure = firmware.get('secure_boot')
        lines += ['Boot: ' + ('UEFI' if firmware.get('uefi') else 'BIOS') + ' · Secure Boot: ' + ('unknown' if secure is None else ('on' if secure else 'off'))]
        lines += ['Extra tests: CPU ' + report['tests']['cpu']['status'] + ' · memory ' + report['tests']['memory']['status']]
        text = '\n\n'.join(lines)
        text += '\n\nUnknown and not tested do not mean pass. BIOS passwords, organization enrollment and Windows eligibility need separate checks.'
        self.summary.configure(state='normal')
        self.summary.delete('1.0', 'end')
        self.summary.insert('1.0', text)
        self.summary.configure(state='disabled')

    def test(self, kind):
        self.status.set('Running ' + kind + ' test. Please keep power connected…')
        def perform():
            if kind == 'cpu':
                result = inventory.run(['stress-ng', '--cpu', str(min(os.cpu_count() or 1, 4)), '--verify', '--timeout', '60s', '--metrics-brief'], timeout=85)
                result['scope'] = '60 seconds, at most 4 workers'
            else:
                available = re.search(r'^MemAvailable:\s+(\d+)', inventory.read('/proc/meminfo') or '', re.M)
                if not available or int(available[1]) < 768 * 1024:
                    return kind, {'status': 'not tested', 'reason': 'Less than 768 MiB available or unknown'}
                result = inventory.run(['memtester', '256M', '1'], timeout=600)
                result['scope'] = '256 MiB, one pass'
            code = result.get('exit_code')
            result['status'] = 'passed' if code == 0 else ('failed' if code is not None else result['status'])
            return kind, result
        self.work(perform, 'test')

    def save(self, shutdown):
        if self.report is None or self.busy:
            return
        destination = Path(self.destination.get())
        if destination not in self.destinations:
            return
        self.report['asset_id'] = self.asset.get().strip()[:80]
        self.report['manual_checks'] = {k: v.get() for k, v in self.checks.items()}
        self.report['cosmetics'] = self.cosmetics.get()
        self.report['notes'] = self.notes.get('1.0', 'end').strip()[:4000]
        report = json.loads(json.dumps(self.report))
        self.status.set('Saving report to USB…')
        def perform():
            # Revalidate USB ancestry and the marker after a possible unplug/swap.
            if not inventory.usb_output(destination) or not storage.marked(destination.parent):
                raise OSError('The selected USB is no longer available. Reconnect it and choose Find USB.')
            return inventory.save(report, destination), shutdown
        self.work(perform, 'saved')

    def poll(self):
        try:
            kind, result = self.events.get_nowait()
            self.busy = False
            if kind == 'scan':
                self.report, paths = result
                self.render()
                self.set_storage(paths)
                if self.test_mode:
                    self.asset.set('VM-BOOT-TEST')
                    if len(paths) == 1:
                        self.serial('MACUS_GUI_READY')
                        self.root.after(3000, lambda: self.save(True))
                    else:
                        self.serial('MACUS_SELFTEST_FAILED: report USB not found')
            elif kind == 'storage':
                self.set_storage(result)
            elif kind == 'speaker':
                self.status.set('Speaker playback finished. Record what you heard in Checks.' if result.get('exit_code') == 0 else 'Speaker playback unavailable. Leave audio not tested or record a confirmed failure.')
            elif kind == 'test':
                test, data = result
                self.report['tests'][test] = data
                self.test_status.set(test.capitalize() + ': ' + data['status'] + '. ' + data.get('reason', ''))
                self.status.set('Test finished. Save to keep the result.')
                self.render()
            elif kind == 'saved':
                path, shutdown = result
                self.status.set('Saved to ' + str(path))
                if self.test_mode:
                    self.serial('MACUS_SELFTEST_PASSED: ' + str(path))
                if shutdown:
                    self.status.set('Report saved. Shutting down — remove the USB after power is off.')
                    result = inventory.run(['systemctl', 'poweroff'], timeout=10)
                    if result.get('exit_code') != 0:
                        self.status.set('Report saved. Automatic shutdown failed; use the power button to shut down.')
            elif kind == 'error':
                self.status.set('Could not finish: ' + result)
                if self.test_mode:
                    self.serial('MACUS_SELFTEST_FAILED: ' + result)
                else:
                    messagebox.showerror('Macus Diagnostics', result)
            self.buttons()
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def serial(self, message):
        try:
            with open('/dev/ttyS0', 'w') as stream:
                stream.write(message + '\n')
        except OSError:
            print(message, flush=True)

    def close(self):
        if self.busy:
            return
        if messagebox.askyesno('Shut down without saving?', 'Any unsaved results will be lost. Shut down?'):
            inventory.run(['systemctl', 'poweroff'])


if __name__ == '__main__':
    DiagnosticsApp(tk.Tk()).root.mainloop()
