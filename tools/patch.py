import os
import sys

TARGETS = [
    "assets/bin/Data/Managed/Metadata/global-metadata.dat",
    "lib/arm64-v8a/libil2cpp.so",
    "lib/armeabi-v7a/libil2cpp.so",
]


def load_pairs(path):
    pairs = []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            old, new = line.split("=", 1)
            old = old.strip()
            new = new.strip()
            if not old or not new:
                continue
            if len(old) != len(new):
                print("  SKIP length mismatch: %s -> %s" % (old, new))
                continue
            pairs.append((old.encode(), new.encode()))
    return pairs


def main():
    root = sys.argv[1]
    pairs_file = sys.argv[2]
    changed_file = sys.argv[3]

    pairs = load_pairs(pairs_file)
    if not pairs:
        print("No valid patches.")
        return 0

    total = 0
    for rel in TARGETS:
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            continue

        with open(full, "rb") as f:
            data = f.read()

        hits = 0
        for old, new in pairs:
            n = data.count(old)
            if n:
                data = data.replace(old, new)
                hits += n
                print("  %s %d hit(s) in %s" % (old.decode(), n, rel))

        if hits:
            with open(full, "wb") as f:
                f.write(data)
            total += hits
            with open(changed_file, "a", encoding="utf-8") as cf:
                cf.write(rel + "\n")
            print("  wrote %s" % rel)

    print("TOTAL HITS: %d" % total)
    if total == 0:
        print("WARNING: nothing matched - the names live in another file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
