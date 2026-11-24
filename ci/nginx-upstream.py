import ipaddress
import pathlib
import re
import subprocess
import sys

action, *args = sys.argv[1:]
path = pathlib.Path("/etc/nginx/conf.d/app.conf")
original = path.read_text()

matches = list(
    re.finditer(
        r"upstream\s+(?:demo3|java_app)\s*\{([^}]*)\}",
        original,
        re.S,
    )
)

if len(matches) != 1:
    raise SystemExit(
    "Expected exactly one application upstream (demo3 or java_app) in app.conf"
)

block = matches[0]

if action == "check":
    subprocess.run(["nginx", "-t"], check=True)
    sys.exit(0)

if action == "sync":
    if not args:
        raise SystemExit("Empty backend list")

    body = "\n    least_conn;\n"

    for item in args:
        ip, state = item.split("=")
        ip = str(ipaddress.IPv4Address(ip))

        if state not in ("up", "down"):
            raise SystemExit("Invalid backend state")

        suffix = " down" if state == "down" else ""
        body += (
            f"    server {ip}:8080 "
            f"max_fails=3 fail_timeout=15s{suffix};\n"
        )

    body += "    keepalive 16;\n"

elif action in ("up", "down"):
    ip = str(ipaddress.IPv4Address(args[0]))

    pattern = re.compile(
        r"(^\s*server\s+" + re.escape(ip)
        + r":8080\b)([^;\n]*);",
        re.M,
    )

    if len(pattern.findall(block[1])) != 1:
        raise SystemExit("Expected exactly one matching backend")

    def replace(match):
        options = re.sub(r"\s+down\b", "", match[2]).rstrip()
        suffix = " down" if action == "down" else ""
        return match[1] + options + suffix + ";"

    body = pattern.sub(replace, block[1])

else:
    raise SystemExit("Unknown action")

updated = (
    original[:block.start(1)]
    + body
    + original[block.end(1):]
)

try:
    path.write_text(updated)
    subprocess.run(["nginx", "-t"], check=True)
    subprocess.run(["systemctl", "reload", "nginx"], check=True)
except Exception:
    path.write_text(original)
    subprocess.run(["systemctl", "reload", "nginx"], check=False)
    raise