from pathlib import Path
import json, os, signal, subprocess, time

def run(*args, **kwargs):
    print('CAPTURE:', ' '.join(args), flush=True)
    kwargs.setdefault('timeout',360)
    return subprocess.run(args, check=True, text=True, **kwargs)

out = Path('build/StoreLatest'); out.mkdir(parents=True, exist_ok=True)
devices = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j'], text=True,timeout=180))['devices']
available = [d for runtime, group in devices.items() if 'iOS-27' in runtime for d in group if d['isAvailable']]
phones = [d for d in available if d['name'].startswith('iPhone') and 'Pro Max' not in d['name'] and 'Plus' not in d['name'] and 'Air' not in d['name']]
pads = [d for d in available if d['name'].startswith('iPad') and '13-inch' in d['name']]
if not phones: raise SystemExit('No current iPhone simulator available')
selected = [('iphone', phones[0])] + ([('ipad',pads[0])] if pads else [])
selected = [(kind, device) for kind, device in selected if kind == os.environ.get('CAPTURE_DEVICE',kind)]
manifest = {'source_commit': os.environ['SOURCE_COMMIT'], 'capture_commit': os.environ['GITHUB_SHA'], 'capture_run': os.environ['GITHUB_RUN_ID'], 'content':'Read-only replay of previously captured public account content; no credentials or private conversations.', 'tests_run':False, 'devices':[]}
for kind, device in selected:
    udid = device['udid']; target = out / kind; target.mkdir(exist_ok=True)
    run('xcrun','simctl','boot',udid) if device['state'] != 'Booted' else None
    run('xcrun','simctl','bootstatus',udid,'-b',timeout=180)
    run('xcrun','simctl','status_bar',udid,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
    run('xcrun','simctl','install',udid,'build/StoreApp/Build/Products/Release-iphonesimulator/Nonto.app')
    container = Path(subprocess.check_output(['xcrun','simctl','get_app_container',udid,'online.nonto.native','data'],text=True,timeout=90).strip()) / 'Documents'
    container.mkdir(exist_ok=True)
    for file in container.glob('capture-*.txt'): file.unlink()
    subprocess.run(['xcrun','simctl','terminate',udid,'online.nonto.native'],capture_output=True)
    run('xcrun','simctl','launch',udid,'online.nonto.native')
    deadline=time.monotonic()+180
    while not (container/'capture-ready.txt').exists():
        if (container/'capture-error.txt').exists(): raise RuntimeError((container/'capture-error.txt').read_text())
        if time.monotonic()>deadline: raise TimeoutError('App content not ready')
        time.sleep(1)
    def command(action):
        (container/'capture-command.txt').write_text(str(time.time_ns())+'|'+action)
    def screenshot(name):
        print('FRAME:',kind,name,flush=True)
        run('xcrun','simctl','io',udid,'screenshot',str(target/(name+'.png')))
    screenshot('01-feed')
    video = subprocess.Popen(['xcrun','simctl','io',udid,'recordVideo','--codec=h264','--force',str(target/'latest-raw.mp4')],stdout=(target/'recording.log').open('w'),stderr=subprocess.STDOUT)
    timeline=[]; start=time.monotonic()
    def step(action, seconds):
        timeline.append({'time':round(time.monotonic()-start,2),'action':action,'hold':seconds})
        if action!='hold': command(action)
        time.sleep(seconds)
    try:
        step('hold',4)
        step('scroll',4)
        screenshot('02-feed-scrolled')
        step('post',4)
        screenshot('03-post')
        step('gallery',4)
        screenshot('04-gallery')
        step('close-gallery',1)
        step('back',1)
        step('compose',5)
        screenshot('05-compose')
        step('close-compose',1)
        step('profile',5)
        screenshot('06-profile')
        step('scroll',3)
        screenshot('07-profile-scrolled')
        step('dark',2)
        screenshot('08-profile-dark')
    finally:
        video.send_signal(signal.SIGINT)
        video.wait(timeout=40)
    (target/'timeline.json').write_text(json.dumps(timeline,indent=2))
    manifest['devices'].append({'kind':kind,'name':device['name'],'udid':udid,'duration':round(time.monotonic()-start,2)})
    run('xcrun','simctl','shutdown',udid)
(out/'provenance.json').write_text(json.dumps(manifest,indent=2))
