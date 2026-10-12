#!/usr/bin/env python3
"""Exercise admin:reset on an isolated synthetic SQLite database and real PTY."""

import errno
import json
import os
from pathlib import Path
import pty
import secrets
import select
import signal
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
RESULTS = []

FIXTURE = '''
require "json"
data = JSON.parse(File.read(ENV.fetch("ACCIO_RESET_CHECK_FILE")))
raise "Expected isolated database" unless ActiveRecord::Base.connection_db_config.database == data.fetch("database")
case ENV.fetch("ACCIO_RESET_CHECK_STEP")
when "prepare"
  AuthSession.delete_all
  User.delete_all
  user = User.create!(email_address: "reset@example.test", password: data.fetch("old"))
  user.auth_sessions.create!(expires_at: 1.hour.from_now)
  user.auth_sessions.create!(expires_at: 1.hour.ago)
  data["original"] = user.attributes.as_json
  File.write(ENV.fetch("ACCIO_RESET_CHECK_FILE"), JSON.generate(data))
when "old"
  user = User.find(1)
  raise "Credentials changed on failure" unless user.authenticate(data.fetch("old")) && user.attributes.as_json == data.fetch("original")
  raise "Sessions changed on failure" unless AuthSession.count == 2
when "new"
  user = User.find(1)
  raise "New password rejected" unless user.authenticate(data.fetch("new"))
  raise "Old password accepted" if user.authenticate(data.fetch("old"))
  raise "Sessions not revoked" unless AuthSession.count.zero?
  expected = data.fetch("original").except("password_digest", "updated_at")
  raise "Other user data changed" unless user.attributes.as_json.except("password_digest", "updated_at") == expected
when "remove"
  AuthSession.delete_all
  User.delete_all
when "missing"
  raise "Unexpected records" unless User.count.zero? && AuthSession.count.zero?
end
'''


def run(*args, env):
    process = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, timeout=60)
    if process.returncode:
        raise AssertionError("Synthetic fixture command failed (credentials omitted)")


def terminal_reset(env, passwords=None, cancel=False, eof=False):
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ["bin/rails", "admin:reset"], cwd=ROOT, env=env,
        stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
    )
    os.close(slave)
    output = bytearray()

    def collect():
        if select.select([master], [], [], 0.1)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError as error:
                if error.errno != errno.EIO:
                    raise

    def prompt(text):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            collect()
            if text.encode() in output and not termios.tcgetattr(master)[3] & termios.ECHO:
                # New secrets must appear neither in argv nor in the child environment.
                for surface in ("cmdline", "environ"):
                    observed = Path(f"/proc/{process.pid}/{surface}").read_bytes()
                    for password in passwords or []:
                        if password:
                            assert password.encode() not in observed, "Credential exposed to process metadata"
                return
            assert process.poll() is None, "Command ended before hidden prompt"
        raise AssertionError("Hidden prompt timed out")

    try:
        if passwords is not None or cancel or eof:
            prompt("Nova senha")
            if cancel:
                process.send_signal(signal.SIGINT)
            elif eof:
                os.write(master, b"\x04")
            else:
                os.write(master, (passwords[0] + "\n").encode())
                prompt("Confirme a nova senha")
                os.write(master, (passwords[1] + "\n").encode())
        deadline = time.monotonic() + 30
        while process.poll() is None and time.monotonic() < deadline:
            collect()
        assert process.poll() is not None, "Command did not finish"
        collect()
        assert termios.tcgetattr(master)[3] & termios.ECHO, "Terminal echo not restored"
        text = output.decode(errors="replace")
        for password in passwords or []:
            if password.strip():
                assert password not in text, "Credential echoed by terminal"
        return process.returncode, text
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)


def main():
    with tempfile.TemporaryDirectory(prefix="admin-reset-", dir=ROOT / "tmp") as directory:
        directory = Path(directory)
        os.chmod(directory, 0o700)
        data = {
            "database": str(directory / "synthetic.sqlite3"),
            "old": secrets.token_hex(16),
            "new": secrets.token_hex(6),  # Exactly the current minimum: 12 characters.
        }
        private_file = directory / "fixture.json"
        private_file.write_text(json.dumps(data))
        private_file.chmod(0o600)
        runner = directory / "fixture.rb"
        runner.write_text(FIXTURE)
        env = dict(os.environ, RAILS_ENV="test", ACCIO_DATABASE_PATH=data["database"],
                   ACCIO_RESET_CHECK_FILE=str(private_file))
        # No inherited bootstrap credentials are used by this recovery test.
        env.pop("ACCIO_ADMIN_PASSWORD", None)
        env.pop("ACCIO_ADMIN_EMAIL", None)

        def fixture(step):
            run("bin/rails", "runner", str(runner), env=dict(env, ACCIO_RESET_CHECK_STEP=step))

        run("bin/rails", "db:prepare", env=env)
        fixture("prepare")
        log = ROOT / "log/test.log"
        log_start = log.stat().st_size if log.exists() else 0
        cases = [
            ("short password", ["short", "short"]),
            ("blank password", ["", ""]),
            ("whitespace password", [" " * 12, " " * 12]),
            ("different confirmation", [data["new"], secrets.token_hex(6)]),
            ("bcrypt byte limit", ["a" * 73, "a" * 73]),
        ]
        for name, passwords in cases:
            code, output = terminal_reset(env, passwords=passwords)
            assert code != 0 and "Senha inválida" in output, name
            fixture("old")
            RESULTS.append({"scenario": name, "result": "PASS"})
        for name, options in (("interrupted input", {"cancel": True}), ("end of input", {"eof": True})):
            code, output = terminal_reset(env, **options)
            assert code != 0 and ("cancelada" in output or "interrompida" in output), name
            fixture("old")
            RESULTS.append({"scenario": name, "result": "PASS"})

        noninteractive = subprocess.run(["bin/rails", "admin:reset"], cwd=ROOT, env=env,
                                        input=b"", capture_output=True, timeout=30)
        assert noninteractive.returncode != 0 and b"terminal interativo" in noninteractive.stderr
        fixture("old")
        RESULTS.append({"scenario": "non-interactive input rejected", "result": "PASS"})

        code, output = terminal_reset(env, passwords=[data["new"], data["new"]])
        assert code == 0 and "Todas as sessões anteriores foram revogadas" in output
        fixture("new")
        RESULTS.append({"scenario": "valid 12-character password and session revocation", "result": "PASS"})

        fixture("remove")
        code, output = terminal_reset(env)
        assert code != 0 and "Administrador não encontrado" in output and "Nova senha" not in output
        fixture("missing")
        RESULTS.append({"scenario": "missing administrator rejected before prompting", "result": "PASS"})

        logged = log.read_bytes()[log_start:] if log.exists() else b""
        for credential in (data["old"], data["new"]):
            assert credential.encode() not in logged, "Credential found in Rails log"
        RESULTS.append({"scenario": "no password echo, process argument/environment or Rails log exposure", "result": "PASS"})
    print(json.dumps({"database": "isolated temporary synthetic SQLite (removed)", "results": RESULTS}, indent=2))


if __name__ == "__main__":
    main()
