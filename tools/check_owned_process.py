"""Exercise real owned child/grandchild teardown without a database or browser."""
import subprocess
import sys
from owned_process import live_group_members, stop_owned_group


def check(label, code, exits_first=False):
    process = subprocess.Popen([sys.executable, '-u', '-c', code],
                               stdout=subprocess.PIPE, text=True, start_new_session=True)
    try:
        assert process.stdout.readline().strip() == 'ready'
        if exits_first:
            process.wait(timeout=5)
            assert live_group_members(process.pid), 'Grandchild must outlive its parent for this check'
        stop_owned_group(process, grace_seconds=.3)
        assert not live_group_members(process.pid)
        print('PASS '+label)
    finally:
        stop_owned_group(process, grace_seconds=.3)
        process.stdout.close()


if __name__ == '__main__':
    check('normal group termination', 'import time;print("ready");time.sleep(60)')
    check('SIGTERM-resistant descendants are awaited after SIGKILL',
          'import signal,subprocess,sys,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);'
          'subprocess.Popen([sys.executable,"-c","import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(60)"]);'
          'print("ready");time.sleep(60)')
    check('orphaned descendants stop even after the launcher exits',
          'import subprocess,sys;subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"]);print("ready")', True)
    print('3 owned-process cleanup checks passed.')
