#!/usr/bin/env python3
"""The Unsafe Mode image's command index, and the check of its extras list.

Plan unsafe-mode.md §4.1 (agentry-notes), D3 and D8; agentry-dockerimages#15.

The index maps each command a Kali package puts in usr/bin, usr/sbin, bin or
sbin to the package that ships it, from Kali's Contents-<arch> for main,
contrib and non-free. A command several packages ship takes, in order:

  1. the package whose name equals the command;
  2. the one package Kali marks Priority required, important or standard.

What is left ambiguous after that is left out of the index and written to
ambiguous.tsv, never guessed. The CLI (agentry-cli, Unsafe Mode M2) reads the
index by a declared command's bare name and installs the package it names, so
both columns are held to a grammar (plan invariant 3): a command that is not a
plain command name, and a package that is not a Debian package name, are left
out and counted, whatever the Contents say.

Every file read is first held to the SHA-256 that Kali's InRelease lists for
it. apt-get update has already verified InRelease's signature against Kali's
archive key, so a mirror that serves anything else fails the build.

The extras list (extras.tsv, maintained by hand) is checked here too, since
the Contents are at hand: each row is one of the two closed recipe kinds,
each value is held to a grammar, and a link's path must be a file its package
ships on this architecture.

The base's own programs (agentry-dockerimages#23). Contents does not list
alternatives links, so a program the built base already carries through one
(awk, which, pager...) would have no row, and the CLI would call it
unavailable while the run could start it. --base-scan runs in the final stage,
after its installs: it walks the image's PATH, resolves each entry inside the
image, and gives a program with no row one naming the package that owns the
file it resolves to (dpkg's own file lists). A program on the PATH that no
package owns fails the build, unless base-unowned.txt names it with a reason.

Usage:
  make-index.py --arch amd64 --dir /work --extras extras.tsv --out /out
      /work holds InRelease and <comp>/Contents-<arch>.gz and
      <comp>/binary-<arch>/Packages.gz for main, contrib and non-free.
  make-index.py --base-scan / --data /etc/agentry/unsafe --unowned base-unowned.txt
  make-index.py --check-extras extras.tsv    the grammar alone, no Contents
  make-index.py --self-test
"""

import argparse
import gzip
import hashlib
import io
import os
import re
import sys
import tempfile

COMPONENTS = ("main", "contrib", "non-free")
HIGH_PRIORITY = {"required", "important", "standard"}
# Where a command lives: a direct child of one of the four bin directories.
BIN_PATH = re.compile(r"^(?:usr/)?s?bin/([^/]+)$")
# A command name the index may hold. The CLI holds a declared command to the
# same shape before it looks one up.
COMMAND = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
PACKAGE = re.compile(r"^[a-z0-9][a-z0-9.+-]+$")
PIP_SPEC = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*==[A-Za-z0-9][A-Za-z0-9.+!_-]*$")
PKG_PATH = re.compile(r"^(?:[A-Za-z0-9._+-]+/)*[A-Za-z0-9._+-]+$")


# The PATH the base scan walks: the image's own ENV PATH, in order.
BASE_PATH = ("usr/local/sbin", "usr/local/bin", "usr/sbin", "usr/bin", "sbin", "bin")


class Refused(Exception):
    """The inputs are not what the build may trust or use."""


def release_hashes(release_text):
    """The SHA256 section of an InRelease: {path: (sha256, size)}."""
    out, inside = {}, False
    for line in release_text.splitlines():
        if line.startswith("SHA256:"):
            inside = True
            continue
        if inside:
            if not line.startswith(" "):
                break
            fields = line.split()
            if len(fields) != 3 or not fields[1].isdigit():
                raise Refused(f"InRelease: an SHA256 line that is not <hash> <size> <path>: {line.strip()!r}")
            digest, size, path = fields
            out[path] = (digest, int(size))
    return out


def verified(path, rel, hashes):
    """The lines of gzipped path, refused unless its bytes are what InRelease lists for rel.

    The compressed file is read whole, to hash it; its lines are then
    decompressed as a stream: main's Contents is about 8 million of them, and a
    builder VM (Apple's container builder on the Mac) has little memory."""
    if rel not in hashes:
        raise Refused(f"{rel} is not listed in InRelease")
    with open(path, "rb") as fh:
        data = fh.read()
    want, size = hashes[rel]
    got = hashlib.sha256(data).hexdigest()
    if got != want or len(data) != size:
        raise Refused(f"{rel}: sha256 {got}, size {len(data)}; InRelease says {want}, {size}")
    return io.TextIOWrapper(gzip.GzipFile(fileobj=io.BytesIO(data)), encoding="utf-8", errors="replace")


def parse_contents(lines, keep_files_of=()):
    """{command: set of packages} for the bin directories, {package: set of paths}
    for the packages in keep_files_of (the ones the extras list links from), and
    how many package names were refused for not being package names."""
    commands, files, refused = {}, {}, 0
    keep = set(keep_files_of)
    for line in lines:
        # "path<whitespace>section/pkg[,section/pkg...]"; the path may hold spaces.
        parts = line.rsplit(None, 1)
        if len(parts) != 2:
            continue
        path, where = parts
        pkgs = set()
        for loc in where.split(","):
            pkg = loc.rsplit("/", 1)[-1]
            if PACKAGE.match(pkg):
                pkgs.add(pkg)
            elif loc:
                refused += 1
        for p in pkgs & keep:
            files.setdefault(p, set()).add(path)
        m = BIN_PATH.match(path)
        if m and pkgs and COMMAND.match(m.group(1)):
            commands.setdefault(m.group(1), set()).update(pkgs)
    return commands, files, refused


def parse_priorities(lines):
    """{package: priority} from a Packages file."""
    out, pkg = {}, None
    for line in lines:
        if line.startswith("Package: "):
            pkg = line[len("Package: "):].strip()
        elif line.startswith("Priority: ") and pkg:
            out[pkg] = line[len("Priority: "):].strip()
        elif not line.strip():
            pkg = None
    return out


def resolve(commands, priorities):
    """The index {command: package}, and what stays ambiguous {command: packages}."""
    index, ambiguous = {}, {}
    for cmd, pkgs in commands.items():
        if len(pkgs) == 1:
            index[cmd] = next(iter(pkgs))
        elif cmd in pkgs:
            index[cmd] = cmd
        else:
            high = sorted(p for p in pkgs if priorities.get(p) in HIGH_PRIORITY)
            if len(high) == 1:
                index[cmd] = high[0]
            else:
                ambiguous[cmd] = sorted(pkgs)
    return index, ambiguous


def link_packages(text):
    """The packages the extras list's link rows name."""
    rows = (line.split("\t") for line in text.splitlines())
    return {row[2] for row in rows if len(row) == 4 and row[0] == "link"}


def check_extras(text, files=None, name="extras.tsv"):
    """Refuse an extras list that is not the closed recipe set, or a link Kali does not ship.

    files is {package: paths} from Contents; None checks the grammar alone, as
    scripts/check.sh does without a registry or a mirror."""
    seen = set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        row = raw.split("\t")
        where = f"{name}:{n}"
        if row[0] == "pip" and len(row) == 3:
            _, cmd, spec = row
            if not PIP_SPEC.match(spec):
                raise Refused(f"{where}: pip wants <pypi-name>==<exact version>, got {spec!r}")
        elif row[0] == "link" and len(row) == 4:
            _, cmd, pkg, path = row
            if not PACKAGE.match(pkg) or not PKG_PATH.match(path) or ".." in path.split("/"):
                raise Refused(f"{where}: link wants a package name and a relative path, got {pkg!r} {path!r}")
            if files is not None and path not in files.get(pkg, ()):
                raise Refused(f"{where}: {pkg} does not ship {path} on this architecture")
        else:
            raise Refused(f"{where}: want 'pip<TAB>command<TAB>name==version' or 'link<TAB>command<TAB>package<TAB>path'")
        if not COMMAND.match(cmd):
            raise Refused(f"{where}: {cmd!r} is not a command name")
        if cmd in seen:
            raise Refused(f"{where}: {cmd} is listed twice")
        seen.add(cmd)


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def build(arch, workdir, extras, outdir):
    release = read_text(os.path.join(workdir, "InRelease"))
    hashes = release_hashes(release)
    extras_text = read_text(extras)
    linked = link_packages(extras_text)
    commands, files, priorities, refused = {}, {}, {}, 0
    for comp in COMPONENTS:
        rel = f"{comp}/Contents-{arch}.gz"
        cmds, fls, bad = parse_contents(verified(os.path.join(workdir, rel), rel, hashes), linked)
        refused += bad
        for k, v in cmds.items():
            commands.setdefault(k, set()).update(v)
        for k, v in fls.items():
            files.setdefault(k, set()).update(v)
        rel = f"{comp}/binary-{arch}/Packages.gz"
        priorities.update(parse_priorities(verified(os.path.join(workdir, rel), rel, hashes)))
    check_extras(extras_text, files)
    index, ambiguous = resolve(commands, priorities)
    date = next((line[len("Date: "):] for line in release.splitlines() if line.startswith("Date: ")), "unknown")
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "commands.tsv"), "w", encoding="utf-8") as fh:
        fh.write(f"# command\tpackage: Kali kali-rolling {arch}, main contrib non-free, InRelease of {date}\n")
        for cmd in sorted(index):
            fh.write(f"{cmd}\t{index[cmd]}\n")
    with open(os.path.join(outdir, "ambiguous.tsv"), "w", encoding="utf-8") as fh:
        fh.write("# command\tpackages: shipped by several, none named for it, not one of standard priority; left out of the index\n")
        for cmd in sorted(ambiguous):
            fh.write(f"{cmd}\t{','.join(ambiguous[cmd])}\n")
    print(f"index: {len(index)} commands, {len(ambiguous)} ambiguous and left out, {refused} package names refused ({arch}, InRelease of {date})")


def resolve_in(root, path, hops=40):
    """path (absolute inside the image) with every symlink followed inside root,
    as an absolute path inside the image; None when it dangles or loops."""
    parts = [p for p in path.split("/") if p]
    done = []
    while parts:
        part = parts.pop(0)
        if part == ".":
            continue
        if part == "..":
            if done:
                done.pop()
            continue
        here = os.path.join(root, *done, part)
        if os.path.islink(here):
            hops -= 1
            if hops < 0:
                return None
            target = os.readlink(here)
            if target.startswith("/"):
                done = []
            parts = [p for p in target.split("/") if p] + parts
            continue
        if not os.path.lexists(here):
            return None
        done.append(part)
    return "/" + "/".join(done)


def owners(root):
    """{resolved path: package} for every regular file dpkg's lists record."""
    out = {}
    info = os.path.join(root, "var/lib/dpkg/info")
    for name in sorted(os.listdir(info)):
        if not name.endswith(".list"):
            continue
        pkg = name[: -len(".list")].split(":", 1)[0]
        for line in read_text(os.path.join(info, name)).splitlines():
            line = line.strip()
            if not line.startswith("/"):
                continue
            head, tail = line.rsplit("/", 1)
            parent = resolve_in(root, head or "/")
            if parent is None or not tail:
                continue
            real = os.path.join(parent, tail)
            full = os.path.join(root, real.lstrip("/"))
            if os.path.isfile(full) and not os.path.islink(full):
                out.setdefault(real, pkg)
    return out


def read_rows(path):
    """The first column of a tab-separated data file's non-comment rows."""
    if not os.path.exists(path):
        return set()
    return {line.split("\t", 1)[0] for line in read_text(path).splitlines() if line.strip() and not line.startswith("#")}


def read_unowned(path):
    """base-unowned.txt: <command><TAB><why>, each command held to the grammar."""
    out = {}
    for n, line in enumerate(read_text(path).splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        row = line.split("\t")
        if len(row) != 2 or not COMMAND.match(row[0]) or not row[1].strip():
            raise Refused(f"{path}, row {n}: want <command><TAB><why>, got {line!r}")
        out[row[0]] = row[1]
    return out


def base_programs(root):
    """{command: the path it resolves to} for every executable on the image's
    PATH, the first directory winning, as a shell would find it."""
    found = {}
    for d in BASE_PATH:
        real_dir = resolve_in(root, "/" + d)
        full_dir = os.path.join(root, (real_dir or "").lstrip("/"))
        if real_dir is None or not os.path.isdir(full_dir):
            continue
        for name in sorted(os.listdir(full_dir)):
            if name in found or not COMMAND.match(name):
                continue
            real = resolve_in(root, f"{real_dir}/{name}")
            full = os.path.join(root, (real or "").lstrip("/"))
            if real and os.path.isfile(full) and os.access(full, os.X_OK):
                found[name] = real
    return found


def base_scan(root, datadir, unowned_path):
    """Index the base's own programs that have no row (agentry-dockerimages#23)."""
    index_path = os.path.join(datadir, "commands.tsv")
    known = read_rows(index_path) | read_rows(os.path.join(datadir, "ambiguous.tsv"))
    unowned = read_unowned(unowned_path)
    owned = owners(root)
    added, missing = {}, []
    for cmd, real in base_programs(root).items():
        if cmd in known or cmd in unowned:
            continue
        pkg = owned.get(real)
        if pkg and PACKAGE.match(pkg):
            added[cmd] = pkg
        else:
            missing.append(f"{cmd} ({real})")
    if missing:
        raise Refused("programs on the base's PATH that no package owns and base-unowned.txt does not name: " + ", ".join(missing))
    if added:
        with open(index_path, "a", encoding="utf-8") as fh:
            fh.write("# command\tpackage: the base's own programs Contents does not list (alternatives links), each to the package owning its target\n")
            for cmd in sorted(added):
                fh.write(f"{cmd}\t{added[cmd]}\n")
    print(f"base scan: {len(added)} of the base's own programs indexed ({', '.join(f'{c}={p}' for c, p in sorted(added.items())) or 'none'}), {len(unowned)} named in base-unowned.txt")
    return added


def base_scan_test():
    """The base scan on a made-up image root."""
    failures = []
    with tempfile.TemporaryDirectory() as root:
        def put(path, body="#!/bin/sh\n", mode=0o755):
            full = os.path.join(root, path.lstrip("/"))
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(body)
            os.chmod(full, mode)
        def link(path, target):
            full = os.path.join(root, path.lstrip("/"))
            os.makedirs(os.path.dirname(full), exist_ok=True)
            os.symlink(target, full)
        # merged /usr: /bin and /sbin are links to usr/bin and usr/sbin
        os.makedirs(os.path.join(root, "usr/bin"))
        os.makedirs(os.path.join(root, "usr/sbin"))
        link("/bin", "usr/bin")
        link("/sbin", "usr/sbin")
        put("/usr/bin/mawk")
        link("/etc/alternatives/awk", "/usr/bin/mawk")
        link("/usr/bin/awk", "/etc/alternatives/awk")          # an alternatives link
        put("/usr/bin/which.debianutils")
        link("/etc/alternatives/which", "/usr/bin/which.debianutils")
        link("/usr/bin/which", "/etc/alternatives/which")
        put("/usr/bin/tar")                                     # listed by dpkg as /bin/tar
        link("/usr/sbin/rmt", "/etc/alternatives/rmt")
        link("/etc/alternatives/rmt", "/usr/sbin/rmt-tar")
        put("/usr/sbin/rmt-tar")
        put("/usr/bin/python3")                                 # already in the index
        put("/usr/sbin/policy-rc.d")                            # no package owns it
        put("/usr/bin/README", mode=0o644)                      # not executable
        link("/usr/bin/dangling", "/nowhere")
        put("/usr/bin/[")                                       # not a command name
        info = os.path.join(root, "var/lib/dpkg/info")
        os.makedirs(info)
        lists = {"mawk:amd64": ["/usr/bin/mawk"], "debianutils": ["/usr/bin/which.debianutils"],
                 "tar": ["/bin/tar", "/usr/sbin/rmt-tar"], "python3-minimal": ["/usr/bin/python3"]}
        for pkg, paths in lists.items():
            with open(os.path.join(info, pkg + ".list"), "w", encoding="utf-8") as fh:
                fh.write("/.\n/usr\n" + "\n".join(paths) + "\n")
        data = os.path.join(root, "data")
        os.makedirs(data)
        with open(os.path.join(data, "commands.tsv"), "w", encoding="utf-8") as fh:
            # what Contents gives: the real files, never the alternatives links; tar
            # is left out so its ownership through dpkg's /bin/tar is exercised
            fh.write("# header\npython3\tpython3-minimal\nmawk\tmawk\nwhich.debianutils\tdebianutils\nrmt-tar\ttar\n")
        with open(os.path.join(data, "ambiguous.tsv"), "w", encoding="utf-8") as fh:
            fh.write("# header\n")
        unowned = os.path.join(root, "unowned.txt")
        with open(unowned, "w", encoding="utf-8") as fh:
            fh.write("# comment\n")
        try:
            base_scan(root, data, unowned)
            failures.append("a PATH program no package owns was accepted")
        except Refused as e:
            if "policy-rc.d" not in str(e):
                failures.append(f"the refusal does not name policy-rc.d: {e}")
        with open(unowned, "w", encoding="utf-8") as fh:
            fh.write("policy-rc.d\tthe container image's service hook\n")
        added = base_scan(root, data, unowned)
        want = {"awk": "mawk", "which": "debianutils", "tar": "tar", "rmt": "tar"}
        if added != want:
            failures.append(f"base scan added {added}, want {want}")
        rows = read_text(os.path.join(data, "commands.tsv"))
        if "awk\tmawk\n" not in rows or rows.count("python3\t") != 1:
            failures.append(f"commands.tsv after the scan:\n{rows}")
        if base_scan(root, data, unowned):
            failures.append("a second scan added rows the first already wrote")
        with open(unowned, "w", encoding="utf-8") as fh:
            fh.write("$(x)\twhy\n")
        try:
            read_unowned(unowned)
            failures.append("base-unowned.txt with a command that is no command name was accepted")
        except Refused:
            pass
    return failures


def self_test():
    """Each rule, on made-up Contents, Packages and extras."""
    contents = "\n".join([
        "usr/bin/file\tutils/file",
        "usr/bin/strings\tdevel/binutils",
        "usr/bin/strings\tdevel/binutils",           # listed twice by one package
        "usr/bin/7z\tutils/7zip,utils/p7zip-full",    # neither named 7z, one standard
        "usr/bin/nc\tnet/netcat-openbsd,net/nc",      # one is named for it
        "usr/bin/tie\tutils/aaa,utils/bbb",           # two, neither standard: ambiguous
        "usr/bin/both\tutils/ccc,utils/ddd",          # two, both standard: ambiguous
        "sbin/ip\tnet/iproute2",
        "usr/bin/sub/dir\tutils/subdirs",                   # not a direct child: no command
        "usr/bin/$(x)\tutils/evil",                   # not a command name
        "usr/share/ghidra/support/analyzeHeadless\tmisc/ghidra",
        "usr/share/doc/a file with spaces\tdoc/spaced",
        "usr/bin/foo\tutils/$(curl${IFS}x|sh);`id`",  # a package that is no package name
        "usr/bin/bar\tutils/Bad_Name,utils/good-one",  # one refused, one kept
    ])
    packages = "\n".join([
        "Package: 7zip", "Priority: standard", "",
        "Package: p7zip-full", "Priority: optional", "",
        "Package: aaa", "Priority: optional", "",
        "Package: bbb", "Priority: extra", "",
        "Package: ccc", "Priority: standard", "",
        "Package: ddd", "Priority: important", "",
    ])
    commands, files, refused = parse_contents(contents.splitlines(), {"ghidra", "spaced"})
    index, ambiguous = resolve(commands, parse_priorities(packages.splitlines()))
    want_index = {"file": "file", "strings": "binutils", "7z": "7zip", "nc": "nc", "ip": "iproute2", "bar": "good-one"}
    if refused != 2 or "foo" in commands:
        failures_early = [f"a package that is no package name was kept ({refused} refused, foo={commands.get('foo')})"]
    else:
        failures_early = []
    want_ambiguous = {"tie": ["aaa", "bbb"], "both": ["ccc", "ddd"]}
    failures = list(failures_early)
    if index != want_index:
        failures.append(f"index {index} != {want_index}")
    if ambiguous != want_ambiguous:
        failures.append(f"ambiguous {ambiguous} != {want_ambiguous}")
    if "a file with spaces" not in {p.rsplit("/", 1)[-1] for p in files.get("spaced", ())}:
        failures.append("a path with spaces was not read whole")

    good = "# comment\npip\tdecompyle3\tdecompyle3==3.9.3\nlink\tanalyzeHeadless\tghidra\tusr/share/ghidra/support/analyzeHeadless\n"
    try:
        check_extras(good, files)
    except Refused as e:
        failures.append(f"a good extras list was refused: {e}")
    bad = {
        "unpinned pip": "pip\tdecompyle3\tdecompyle3>=3\n",
        "pip with a URL": "pip\tx\thttps://example.com/x.whl\n",
        "an unknown kind": "curl\tx\thttps://example.com/x\n",
        "a shell in the command": "pip\t$(x)\tx==1\n",
        "a path the package does not ship": "link\tanalyzeHeadless\tghidra\tusr/bin/nope\n",
        "a path climbing out": "link\tx\tghidra\t../../etc/passwd\n",
        "a command listed twice": "pip\tx\tx==1\npip\tx\tx==2\n",
        "spaces for tabs": "pip decompyle3 decompyle3==3.9.3\n",
    }
    for name, text in bad.items():
        try:
            check_extras(text, files)
            failures.append(f"extras with {name} was accepted")
        except Refused:
            pass

    with tempfile.TemporaryDirectory() as d:
        blob = gzip.compress(b"usr/bin/file utils/file\n")
        hashes = {"main/Contents-amd64.gz": (hashlib.sha256(blob).hexdigest(), len(blob))}
        path = os.path.join(d, "c.gz")
        with open(path, "wb") as fh:
            fh.write(blob)
        if list(verified(path, "main/Contents-amd64.gz", hashes)) != ["usr/bin/file utils/file\n"]:
            failures.append("a verified file was not read back")
        with open(path, "wb") as fh:
            fh.write(blob + b"x")
        try:
            verified(path, "main/Contents-amd64.gz", hashes)
            failures.append("a file that is not what InRelease lists was accepted")
        except Refused:
            pass
        try:
            verified(path, "contrib/Contents-amd64.gz", hashes)
            failures.append("a file InRelease does not list was accepted")
        except Refused:
            pass
    if files.get("file"):
        failures.append("the file list of a package the extras do not link from was kept")
    if link_packages("link\tx\tghidra\tusr/x\npip\ty\ty==1\n") != {"ghidra"}:
        failures.append("link_packages did not name the linked package alone")
    try:
        release_hashes("SHA256:\n abc main/Contents-amd64.gz\n")
        failures.append("an InRelease line without its size was accepted")
    except Refused:
        pass
    listed = release_hashes("Origin: Kali\nSHA256:\n abc 12 main/Contents-amd64.gz\nSHA512:\n def 12 main/Contents-amd64.gz\n")
    if listed != {"main/Contents-amd64.gz": ("abc", 12)}:
        failures.append(f"release_hashes read {listed}")

    failures += base_scan_test()

    for f in failures:
        print(f"FAIL make-index self-test: {f}")
    if not failures:
        print("ok   make-index self-test")
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--check-extras", metavar="FILE")
    ap.add_argument("--arch")
    ap.add_argument("--dir")
    ap.add_argument("--extras")
    ap.add_argument("--out")
    ap.add_argument("--base-scan", metavar="ROOT")
    ap.add_argument("--data", metavar="DIR")
    ap.add_argument("--unowned", metavar="FILE")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if args.check_extras:
        try:
            check_extras(read_text(args.check_extras), name=args.check_extras)
        except Refused as e:
            print(f"REFUSED: {e}", file=sys.stderr)
            return 1
        print(f"ok   {args.check_extras}: the closed recipe set")
        return 0
    if args.base_scan:
        if not (args.data and args.unowned):
            ap.error("--base-scan needs --data and --unowned")
        try:
            base_scan(args.base_scan, args.data, args.unowned)
        except Refused as e:
            print(f"REFUSED: {e}", file=sys.stderr)
            return 1
        return 0
    if not (args.arch and args.dir and args.extras and args.out):
        ap.error("--arch, --dir, --extras and --out are required")
    try:
        build(args.arch, args.dir, args.extras, args.out)
    except Refused as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
