#!/usr/bin/env python3
"""Run a disposable, loopback-only synthetic workbench. Never uses an existing DB."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import socket
import subprocess
import tempfile
import time
from urllib.request import urlopen
from uuid import uuid4
from preview_fixture import fixture
from owned_process import stop_owned_group

ROOT = Path(__file__).resolve().parents[1]


def main():
    from check_standalone import main as check_standalone
    check_standalone()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin', type=Path, required=True, help='Installed stock PG16+ binaries')
    parser.add_argument('--dotnet', type=Path, required=True, help='Installed .NET SDK matching global.json')
    parser.add_argument('--port', type=int, default=0, help='Loopback HTTP port; 0 chooses an unused port')
    parser.add_argument('--no-build', action='store_true', help='Use already-built assets')
    parser.add_argument('--check', action='store_true', help='Run HTTP integration checks, then clean up')
    parser.add_argument('--browser-check',action='store_true',help='Run checked-in browser scenarios in the newly owned standard fixture')
    parser.add_argument('--browser',type=Path,help='Installed Chromium-compatible executable; used only with --browser-check')
    parser.add_argument('--example', choices=['standard','mixed-gas'], default='standard', help='Explicit synthetic dataset')
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error('Port must be between 0 and 65535')
    if args.browser_check and (not args.check or args.example!='standard' or args.browser is None or not args.browser.is_file()):
        parser.error('--browser-check requires --check, --example standard and an installed --browser executable')
    bins = {n: args.pg_bin.resolve()/n for n in ('initdb','pg_ctl','psql')}
    dotnet = args.dotnet.resolve()
    for binary in [dotnet,*bins.values()]:
        if not binary.is_file():
            parser.error(f'Missing installed binary: {binary}')
    env = {k:v for k,v in os.environ.items() if not k.startswith(('PG','OPENETRM_PREVIEW_','ASPNETCORE_','DOTNET_'))}
    env.update({'PGTZ':'UTC','DOTNET_CLI_TELEMETRY_OPTOUT':'1','DOTNET_NOLOGO':'1'})
    if not args.no_build:
        subprocess.run(['npm','ci','--prefix','web','--ignore-scripts'],cwd=ROOT,env=env,check=True,timeout=120)
        subprocess.run(['npm','run','build','--prefix','web'],cwd=ROOT,env=env,check=True,timeout=60)
        subprocess.run([str(dotnet),'restore','src/OpenEtrm.Api','--locked-mode'],cwd=ROOT,env=env,check=True,timeout=120)
        subprocess.run([str(dotnet),'build','src/OpenEtrm.Api','--no-restore'],cwd=ROOT,env=env,check=True,timeout=120)
    dll=ROOT/'src/OpenEtrm.Api/bin/Debug/net10.0/OpenEtrm.Api.dll'
    if not dll.is_file() or not (ROOT/'web/dist/index.html').is_file():
        parser.error('Build the API and web assets before using --no-build')
    # Use a short socket path on systems with a small Unix-socket path limit.
    temporary=Path(tempfile.mkdtemp(prefix='openetrm-preview-',dir='/tmp')).resolve()
    os.chmod(temporary,0o700)
    data=temporary/'data'
    run_id=str(uuid4())
    (temporary/'.openetrm-preview').write_text(run_id)
    started=False
    startup_attempted=False
    safe_to_remove=True
    child=None
    browser_process=None
    browser_cleanup_ok=True
    log=None
    def run(command,**kwargs):
        return subprocess.run([str(v) for v in command],env=env,text=True,capture_output=True,timeout=30,**kwargs)
    def stop_signal(signum,frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,stop_signal)
    try:
        initialized=run([bins['initdb'],'-D',data,'--auth-local=trust','--auth-host=reject','--encoding=UTF8','--locale=C','--no-instructions','--username=preview_owner'])
        if initialized.returncode:
            raise RuntimeError(initialized.stderr)
        startup_attempted=True
        safe_to_remove=False
        started_result=run([bins['pg_ctl'],'-D',data,'-w','-t','15','-l',temporary/'postgres.log','-o',shlex.join(['-k',str(temporary),'-h','','-p','55439','-c','track_commit_timestamp=on']),'start'])
        if started_result.returncode:
            raise RuntimeError(started_result.stderr)
        started=True
        psql=[bins['psql'],'-X','-h',temporary,'-p','55439','-U','preview_owner','-d','postgres','-qAt','-v','ON_ERROR_STOP=1']
        def query(sql):
            result=run(psql,input=sql)
            if result.returncode:
                raise RuntimeError(result.stderr)
            return result.stdout.strip()
        if Path(query('SHOW data_directory;')).resolve()!=data.resolve():
            raise RuntimeError('Refusing to operate on a database outside the owned disposable cluster')
        if args.example=='mixed-gas':
            export=temporary/'mixed-inputs.json'
            subprocess.run([str(dotnet),'run','--project','tests/OpenEtrm.MarketData.Checks','--',
                            '--export-mixed-resolution',str(export)],cwd=ROOT,env=env,check=True,timeout=60)
            from mixed_preview_fixture import fixture as mixed_fixture
            reference,market,security,manifest=mixed_fixture(export)
        else:
            reference,market,security,manifest=fixture(ROOT)
        for migration in sorted((ROOT/'db/migrations').glob('[0-9][0-9][0-9][0-9]_*.sql')):
            query(migration.read_text())
        query(reference)
        query(market)
        query(security)
        (temporary/'manifest.json').write_text(json.dumps(manifest))
        # Freeze assets for this owned instance; a later web build must not change
        # another running preview's presentation while it is being used.
        shutil.copytree(ROOT/'web/dist',temporary/'web')
        port=args.port
        if port==0:
            with socket.socket() as reservation:
                reservation.bind(('127.0.0.1',0))
                port=reservation.getsockname()[1]
        url=f'http://127.0.0.1:{port}'
        app_env={**env,'OPENETRM_PREVIEW_ROOT':str(temporary),'OPENETRM_PREVIEW_PORT':str(port),
                 'OPENETRM_PREVIEW_WEB':str(temporary/'web'),
                 'OPENETRM_PREVIEW_RUNTIME':f'Host={temporary};Port=55439;Database=postgres;Username=preview_runtime;SSL Mode=Disable',
                 'OPENETRM_PREVIEW_AUTHENTICATOR':f'Host={temporary};Port=55439;Database=postgres;Username=preview_authenticator;SSL Mode=Disable'}
        log=(temporary/'app.log').open('w')
        child=subprocess.Popen([str(dotnet),str(dll),'--local-preview'],cwd=ROOT,env=app_env,stdout=log,stderr=subprocess.STDOUT)
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            if child.poll() is not None:
                raise RuntimeError('Preview failed to start:\n'+(temporary/'app.log').read_text())
            try:
                with urlopen(url+'/api/health',timeout=.5) as response:
                    health=json.load(response)
                if health.get('runId')!=run_id:
                    raise RuntimeError('HTTP port belongs to a different process; refusing to reuse it')
                break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError('Preview did not become ready:\n'+(temporary/'app.log').read_text())
        print(f'PREVIEW_URL={url}',flush=True)
        print('Private synthetic database. Ctrl+C stops the app and removes its owned database.',flush=True)
        if args.check:
            if args.example=='mixed-gas':
                from check_mixed_preview import run_checks
                run_checks(url,json.loads(export.read_text()))
            else:
                from check_preview import run_checks
                workspace=run_checks(url)
                from check_schedule_storage import run_checks as check_schedule_storage
                check_schedule_storage(query,psql,env,manifest)
                from check_temporal_storage import run_checks as check_temporal_storage
                check_temporal_storage(query,psql,env,manifest,url)
                adapter_fixture=temporary/'adapter-fixture.json'
                adapter_fixture.write_text(json.dumps(workspace))
                subprocess.run([str(dotnet),'run','--project','tests/OpenEtrm.Api.Checks','--',str(adapter_fixture)],cwd=ROOT,env=env,check=True,timeout=60)
                if args.browser_check:
                    target=temporary/'browser-target.json'
                    target.write_text(json.dumps({'suite':'business_browser_v1','url':url,'runId':run_id}))
                    browser_process=subprocess.Popen(['node',str(ROOT/'tests/browser/run.mjs'),str(target),str(args.browser.resolve())],cwd=ROOT,env=env,start_new_session=True)
                    if browser_process.wait(timeout=180):
                        raise RuntimeError('Owned browser checks failed')
        else:
            child.wait()
    except KeyboardInterrupt:
        print('Stopping the owned preview.',flush=True)
    finally:
        # Stop the entire owned browser group, even if Node timed out or exited
        # before Chromium. Never remove a profile while a live child still uses it.
        if browser_process is not None:
            try:
                stop_owned_group(browser_process)
            except Exception:
                browser_cleanup_ok=False
                print('Browser cleanup unconfirmed; retaining its private directory.',flush=True)
        # Only the process started above and its exact database directory are touched.
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)
        if log is not None:
            log.close()
        if startup_attempted:
            status=run([bins['pg_ctl'],'-D',data,'status'])
            if status.returncode==0:
                stopped=run([bins['pg_ctl'],'-D',data,'-m','immediate','-w','-t','15','stop'])
                if stopped.returncode:
                    raise RuntimeError('Failed to stop owned preview; retained '+str(temporary))
                status=run([bins['pg_ctl'],'-D',data,'status'])
            if status.returncode!=3:
                raise RuntimeError('Cannot establish that owned preview stopped; retained '+str(temporary))
            # A failed startup can leave a late child; retain its directory.
            safe_to_remove=started and browser_cleanup_ok
        if safe_to_remove:
            shutil.rmtree(temporary)
            print('Removed owned disposable preview database.',flush=True)
        else:
            print(f'Startup/cleanup incomplete; retained private directory: {temporary}',flush=True)
        if not browser_cleanup_ok:
            raise RuntimeError('Owned browser cleanup could not be confirmed; private files retained')


if __name__=='__main__':
    main()
