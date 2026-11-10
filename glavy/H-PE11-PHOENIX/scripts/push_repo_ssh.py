#!/usr/bin/env python3
# PHOENIX-11 // GitHub push через deploy-key по SSH-over-443 (в песочнице нет ssh-клиента)
import os, sys, time, select

REPO = "/home/z/my-project/repo/H-PE11-PHOENIX"
KEY_PATH = "/tmp/phx_deploy_key"
PUB_PATH = KEY_PATH + ".pub"
REMOTE = "ssh://git@ssh.github.com:443/rtynbirf/H-PE11-PHOENIX.git"

def gen_key():
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    k = Ed25519PrivateKey.generate()
    priv = k.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.OpenSSH,
        serialization.NoEncryption(),
    )
    pub = k.public_key().public_bytes(
        serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH
    )
    with open(KEY_PATH, "wb") as f:
        f.write(priv)
    os.chmod(KEY_PATH, 0o600)
    with open(PUB_PATH, "wb") as f:
        f.write(pub + b" phoenix11-deploy\n")
    return pub.decode()

class ParamikoChannelWrapper:
    def __init__(self, chan, sshclient):
        self.chan = chan
        self.client = sshclient
        self._stderr = chan.makefile_stderr("rb", bufsize=0)

    def read(self, n=-1):
        if n is None or n < 0:
            n = 65536
        return self.chan.recv(n)

    def write(self, data):
        self.chan.sendall(data)

    def can_read(self):
        r, _, _ = select.select([self.chan], [], [], 0)
        return bool(r)

    @property
    def stderr(self):
        return self._stderr

    def close(self, timeout=None):
        try:
            self.chan.shutdown_write()
            t0 = time.time()
            while not self.chan.exit_status_ready() and time.time() - t0 < 60:
                time.sleep(0.1)
        except Exception:
            pass
        try:
            self.chan.close()
        except Exception:
            pass
        try:
            self.client.close()
        except Exception:
            pass

class ParamikoSSHVendor:
    def __init__(self, **connect_kwargs):
        self.connect_kwargs = connect_kwargs

    def run_command(self, host, command, username=None, port=None,
                    password=None, key_filename=None, ssh_command=None,
                    protocol_version=None):
        import paramiko
        c = paramiko.SSHClient()
        # AUDIT-2026-1030 / FINDING-C3: TOFU вместо AutoAddPolicy — первое
        # подключение доверяем и сохраняем host-key, дальше только строгое сравнение.
        kh = os.path.join(os.path.expanduser('~'), '.ssh', 'known_hosts')
        first_use = not (os.path.exists(kh) and os.path.getsize(kh) > 0)
        if first_use:
            print('[TOFU] first use: saving host-key to', kh, flush=True)
            c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            os.makedirs(os.path.dirname(kh), exist_ok=True)
        else:
            c.load_host_keys(kh)
            c.set_missing_host_key_policy(paramiko.RejectPolicy())
        kw = dict(self.connect_kwargs)
        if key_filename:
            kw["key_filename"] = key_filename
        c.connect(host, port=int(port or 22), username=username or "git",
                  allow_agent=False, look_for_keys=False, timeout=30, **kw)
        if first_use:
            try:
                c.get_host_keys().save(kh)
                os.chmod(kh, 0o600)
            except Exception as e:
                print('[TOFU] known_hosts save failed:', e, flush=True)
        t = c.get_transport()
        chan = t.open_session(timeout=30)
        # GIT_PROTOCOL не шлём: GitHub и по v0 отдаёт полный протокол пуша
        cmd = command.decode() if isinstance(command, bytes) else command
        chan.exec_command(cmd)
        return ParamikoChannelWrapper(chan, c)

def main():
    if os.path.exists(KEY_PATH) and os.path.exists(PUB_PATH):
        pub = open(PUB_PATH).read().strip()
        print("[i] использую существующий ключ:", PUB_PATH)
    else:
        pub = gen_key()
        print("[x] ed25519 deploy-key сгенерирован:", PUB_PATH)
    print("PUB:", pub)

    from dulwich.repo import Repo
    from dulwich.client import SSHGitClient

    r = Repo(REPO)
    cli = SSHGitClient("ssh.github.com", port=443, username="git",
                       vendor=ParamikoSSHVendor(key_filename=KEY_PATH))

    def update_refs(refs):
        local = r.refs[b"refs/heads/main"]
        return {b"refs/heads/main": local}

    def generate_pack_data(have, want, *, ofs_delta=False, progress=None):
        return r.generate_pack_data(set(have), set(want), progress=progress, ofs_delta=ofs_delta)

    path = b"/rtynbirf/H-PE11-PHOENIX.git"
    result = cli.send_pack(
        path,
        update_refs,
        generate_pack_data=generate_pack_data,
        progress=lambda data: sys.stdout.buffer.write(b"  remote: " + data),
    )
    print()
    print("[x] push result:", result.refs)
    return 0

if __name__ == "__main__":
    sys.exit(main())
