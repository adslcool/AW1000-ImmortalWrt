import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION_ENV = dict(os.environ, IMMORTALWRT_VERSION='25.12.2', IMMORTALWRT_REVISION='r38135-0c4cd0f9920a')

def run(*args, env=None, check=True, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, env=env, check=check, text=True, capture_output=True, timeout=15)

def fields(text):
    return dict(line.split('=', 1) for line in text.splitlines() if '=' in line)

class BuildTests(unittest.TestCase):
    def test_shell_syntax(self):
        for parent in ('scripts', 'files-template'):
            for path in (ROOT / parent).rglob('*'):
                if path.is_file():
                    first = path.read_bytes().splitlines()[:1]
                    if first and first[0].startswith(b'#!') and b'sh' in first[0]:
                        run('bash' if b'bash' in first[0] else 'sh', '-n', str(path))

    def test_version_merge_and_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / '.config'
            config.write_text((ROOT / 'config/aw1000.config').read_text() + '\n# CONFIG_VERSIONOPT is not set\nCONFIG_VERSION_NUMBER="25.12-SNAPSHOT"\n')
            for _ in range(2):
                run('bash', 'scripts/build-version.sh', tmp, env=VERSION_ENV)
            text = config.read_text()
            self.assertEqual(text.count('CONFIG_VERSIONOPT=y'), 1)
            self.assertNotIn('SNAPSHOT', text)
            self.assertNotIn('@@', text)
            run('bash', 'scripts/check-release.sh', tmp, 'config', env=VERSION_ENV)
            config.write_text(text.replace('CONFIG_VERSIONOPT=y', '# CONFIG_VERSIONOPT is not set'))
            self.assertNotEqual(run('bash', 'scripts/check-release.sh', tmp, 'config', env=VERSION_ENV, check=False).returncode, 0)

    def test_source_revision_stamp_overrides_detached_getver(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)
            scripts = source / 'scripts'
            scripts.mkdir()
            getver = scripts / 'getver.sh'
            getver.write_text('#!/bin/sh\n[ -s version ] && cat version || echo r0+38135-0c4cd0f992\n')
            getver.chmod(0o755)

            run('bash', 'scripts/stamp-source-revision.sh', tmp, env=VERSION_ENV)
            self.assertEqual((source / 'version').read_text(), 'r38135-0c4cd0f9920a\n')
            self.assertEqual(run(str(getver), cwd=source).stdout.strip(), VERSION_ENV['IMMORTALWRT_REVISION'])

            bad_env = dict(os.environ, IMMORTALWRT_REVISION='r0+38135-0c4cd0f992')
            result = run('bash', 'scripts/stamp-source-revision.sh', tmp, env=bad_env, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Invalid official release revision', result.stderr)

    def test_vendor_archive_materializes_and_checksum_is_enforced(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkout = Path(tmp)
            vendor = checkout / 'vendor'
            vendor.mkdir()
            shutil.copy2(ROOT / 'vendor/vendor-sources.tar.gz', vendor)
            shutil.copy2(ROOT / 'vendor/VENDOR_ARCHIVE.sha256', vendor)

            result = run('bash', 'scripts/materialize-vendor.sh', tmp)
            packages = Path(result.stdout.strip())
            self.assertTrue((packages / 'QModem/application/qmodem/Makefile').is_file())
            self.assertTrue((packages / 'luci-theme-argon/Makefile').is_file())
            self.assertTrue((packages / 'luci-app-aw1k-led/Makefile').is_file())
            self.assertTrue((packages / 'luci-app-openclash/Makefile').is_file())
            self.assertEqual(sum(path.is_file() for path in packages.rglob('*')), 1051)

            (vendor / 'VENDOR_ARCHIVE.sha256').write_text('0' * 64 + '  vendor-sources.tar.gz\n')
            result = run('bash', 'scripts/materialize-vendor.sh', tmp, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('FAILED', result.stderr)

    def test_bad_requested_versions_rejected_before_network(self):
        for version in ('25.12-SNAPSHOT', '26.0.0', '25.12.2;echo bad', 'master'):
            env = dict(os.environ, IMMORTALWRT_REQUESTED_VERSION=version)
            result = run('bash', 'scripts/resolve-immortalwrt-release.sh', env=env, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Use auto', result.stderr)

    def test_image_checks_require_real_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / '.config').write_text((ROOT / 'config/aw1000.config').read_text())
            run('bash', 'scripts/build-version.sh', tmp, env=VERSION_ENV)
            self.assertNotEqual(run('bash', 'scripts/check-release.sh', tmp, 'image', env=VERSION_ENV, check=False).returncode, 0)
            root = path / 'build_dir/target-test/root-qualcommax/etc'
            root.mkdir(parents=True)
            release = root / 'openwrt_release'
            release.write_text("DISTRIB_RELEASE='25.12.2'\nDISTRIB_REVISION='r38135-0c4cd0f9920a'\n")
            target = path / 'bin/targets/qualcommax/ipq807x'
            target.mkdir(parents=True)
            manifest = target / 'immortalwrt-arcadyan_aw1000.manifest'
            manifest.write_text('luci-app-openclash - 1.0\nqmodem - 1.0\n')
            for suffix in ('-sysupgrade.bin', '-factory.ubi', '-initramfs-uImage.itb'):
                (target / ('immortalwrt-arcadyan_aw1000' + suffix)).write_bytes(b'fixture')
            run('bash', 'scripts/check-release.sh', tmp, 'image', env=VERSION_ENV)
            release.write_text("DISTRIB_RELEASE='25.12.2'\nDISTRIB_REVISION='r0+38135-0c4cd0f992'\n")
            result = run('bash', 'scripts/check-release.sh', tmp, 'image', env=VERSION_ENV, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected 'r38135-0c4cd0f9920a', got 'r0+38135-0c4cd0f992'", result.stderr)
            release.write_text("DISTRIB_RELEASE='25.12.2'\nDISTRIB_REVISION='r38135-0c4cd0f9920a'\n")
            manifest.write_text(manifest.read_text() + 'xray-core - 1.0\n')
            self.assertNotEqual(run('bash', 'scripts/check-release.sh', tmp, 'image', env=VERSION_ENV, check=False).returncode, 0)

class LedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.leds = self.path / 'leds'
        for name in ('red:5g','green:5g','blue:5g','green:wifi'):
            led = self.leds / name
            led.mkdir(parents=True)
            (led / 'brightness').write_text('0')
            (led / 'max_brightness').write_text('255')
            (led / 'trigger').write_text('none [heartbeat] timer')
        self.status = self.path / 'failover.status'
        self.ledstatus = self.path / 'led.status'
        self.config = self.path / 'uci.json'
        self.config.write_text('{}')
        binpath = self.path / 'bin'; binpath.mkdir()
        uci = binpath / 'uci'
        uci.write_text('#!/usr/bin/env python3\nimport json,os,sys\nd=json.load(open(os.environ["TEST_UCI"]))\nk=sys.argv[-1]\nprint(d.get(k,""))\n')
        uci.chmod(0o755)
        logger = binpath / 'logger'; logger.write_text('#!/bin/sh\nexit 0\n'); logger.chmod(0o755)
        self.env = dict(os.environ, PATH=str(binpath)+os.pathsep+os.environ['PATH'],
            TEST_UCI=str(self.config), AW1000_LED_ROOT=str(self.leds),
            AW1000_FAILOVER_STATE=str(self.status), AW1000_LED_STATE=str(self.ledstatus),
            AW1000_NIGHT_FLAG=str(self.path / 'night'))
        self.count = 0

    def sample(self, *, healthy=1, route=1, state='wired', age=0, fails=0, recover=0):
        self.count += 1
        uptime = int(float(Path('/proc/uptime').read_text().split()[0])) - age
        self.status.write_text(f'sample_id=test-{self.count}\nupdated_uptime={uptime}\nstate={state}\ncellular_route_available={route}\ncellular_internet_healthy={healthy}\nwired_fail_count={fails}\nwired_recover_count={recover}\n')

    def apply(self):
        run('sh', str(ROOT / 'files-template/usr/sbin/aw1000-5g-role-led'), 'apply', env=self.env)
        return fields(self.ledstatus.read_text())

    def rgb(self):
        return tuple(int((self.leds / f'{c}:5g/brightness').read_text()) for c in ('red','green','blue'))

    def test_normal_states_and_other_leds_preserved(self):
        self.sample(); self.assertEqual(self.apply()['role'], 'standby'); self.assertEqual(self.rgb(), (0,0,255))
        self.sample(state='cellular'); self.assertEqual(self.apply()['role'], 'active'); self.assertEqual(self.rgb(), (0,255,0))
        self.sample(fails=1); self.assertEqual(self.apply()['role'], 'transition'); self.assertEqual(self.rgb(), (255,255,0))
        self.assertEqual((self.leds / 'green:wifi/trigger').read_text(), 'none [heartbeat] timer')

    def test_failures_count_fresh_samples_and_recovery_has_hysteresis(self):
        self.sample(); self.apply()
        self.sample(healthy=0)
        for _ in range(4):
            s = self.apply(); self.assertEqual(s['failure_count'], '1'); self.assertEqual(s['color'], 'blue')
        self.sample(healthy=0); self.assertEqual(self.apply()['color'], 'blue')
        self.sample(healthy=0); self.assertEqual(self.apply()['color'], 'red')
        self.assertEqual(self.rgb(), (255,0,0))
        self.assertEqual(self.apply()['color'], 'red')  # no periodic red/off blink
        self.sample(state='cellular'); self.assertEqual(self.apply()['color'], 'red')
        self.sample(state='cellular'); self.assertEqual(self.apply()['color'], 'green')

    def test_stale_missing_and_night_mode(self):
        self.sample(); self.apply()
        self.status.write_text('state=wired\n'); self.assertEqual(self.apply()['color'], 'off')
        self.sample(age=200); self.assertEqual(self.apply()['reason'], 'missing_or_stale_status')
        self.sample(); self.apply()
        Path(self.env['AW1000_NIGHT_FLAG']).touch()
        self.assertEqual(self.apply()['role'], 'night'); self.assertEqual(self.rgb(), (0,0,0))
        Path(self.env['AW1000_NIGHT_FLAG']).unlink()
        self.assertEqual(self.apply()['color'], 'blue')

    def test_night_schedule_equal_time_and_disabled(self):
        self.sample()
        values = {'ledstatus.settings.night_enabled':'1', 'ledstatus.settings.night_start':'00:00', 'ledstatus.settings.night_end':'00:00'}
        self.config.write_text(json.dumps(values)); self.assertEqual(self.apply()['color'], 'blue')
        values['aw1000-5g-role-led.main.enabled'] = '0'
        self.config.write_text(json.dumps(values)); self.assertEqual(self.apply()['role'], 'disabled')
        self.assertEqual(self.rgb(), (0,0,255))

    def test_status_is_read_only(self):
        self.sample(); self.apply()
        before = self.ledstatus.stat().st_mtime_ns
        run('sh', str(ROOT / 'files-template/usr/sbin/aw1000-5g-role-led'), 'status', env=self.env)
        self.assertEqual(self.ledstatus.stat().st_mtime_ns, before)

    def test_failover_publishes_only_complete_snapshot(self):
        source = (ROOT / 'files-template/usr/sbin/aw1000-failover').read_text().split('case "${1:-daemon}"')[0]
        script = self.path / 'writer.sh'
        script.write_text(source + '''
wired_iface() { echo wan; }
get_l3_device() { echo wan; }
cellular_route_devs() { echo wwan0; }
cellular_available() { return 0; }
health_cellular() { touch "$TEST_READY"; read -r go < "$TEST_GATE"; return 0; }
write_status wired 0 0
''')
        ready = self.path / 'ready'; gate = self.path / 'gate'; os.mkfifo(gate)
        self.status.write_text('old complete snapshot\n')
        env = dict(self.env, TEST_READY=str(ready), TEST_GATE=str(gate))
        proc = subprocess.Popen(['sh', str(script)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 3
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            self.assertEqual(self.status.read_text(), 'old complete snapshot\n')
            with gate.open('w') as handle: handle.write('go\n')
            out, err = proc.communicate(timeout=3)
            self.assertEqual(proc.returncode, 0, err)
            snapshot = fields(self.status.read_text())
            self.assertEqual(snapshot['cellular_internet_healthy'], '1')
            self.assertEqual(snapshot['cellular_route_available'], '1')
            self.assertTrue(snapshot['sample_id'])
        finally:
            if proc.poll() is None:
                proc.kill(); proc.communicate()

if __name__ == '__main__':
    unittest.main()
