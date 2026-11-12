#!/usr/bin/env python3
"""Compare two APKs with their signatures taken out.

    python3 scripts/repro_compare_apk.py RELEASE.apk REBUILT.apk

An APK signed with scheme v2/v3 is a zip file with an "APK Signing Block"
between the last file entry and the central directory. Signing with another
key, or another signing tool, changes three things only: that block, zero
padding a signer may put before it (apksigner pads the entries to a 4 KiB
boundary; Gradle's own signer need not), and the central directory's offset in
the end record. Templar Wallet's minSdk is 24, so there is no v1 JAR
signature inside the zip.

This script compares everything else byte for byte: every local file header
and its data, in order and at the same offsets, the central directory, and
the end record (offset aside); the padding must be zeros. Equal means the
two APKs hold the same files, in the same order, compressed and aligned the
same way. Re-sign with `apksigner sign --alignment-preserved` so a signer
does not move entries.

Exit 0 when they match, 1 when they differ (with the first differing zip
entries listed), 2 on a file that is not an APK of this kind.

Only the standard library; works on any Python 3.8+.
"""

import struct
import sys
import zipfile

EOCD_SIG = b"PK\x05\x06"
SIG_BLOCK_MAGIC = b"APK Sig Block 42"
# v1 (JAR) signature files; none expected, reported if present.
V1_SUFFIXES = (".SF", ".RSA", ".DSA", ".EC")


class NotAnApk(Exception):
    pass


def unsigned_view(data: bytes) -> bytes:
    """The parts of an APK that signing does not touch, concatenated:
    file entries, central directory, end record with its offset field zeroed.
    """
    eocd = data.rfind(EOCD_SIG, max(0, len(data) - 65557))
    if eocd < 0 or len(data) - eocd < 22:
        raise NotAnApk("no zip end-of-central-directory record")
    cd_size, cd_offset = struct.unpack_from("<II", data, eocd + 12)
    if cd_offset == 0xFFFFFFFF:
        raise NotAnApk("zip64 is not used by APKs")
    if cd_offset + cd_size != eocd:
        raise NotAnApk("central directory does not end at the end record")

    # Where the entries end: after the entry stored last in the file.
    entries_end = 0
    pos = cd_offset
    while pos < eocd:
        if data[pos:pos + 4] != b"PK\x01\x02":
            raise NotAnApk(f"bad central directory record at {pos}")
        flags, = struct.unpack_from("<H", data, pos + 8)
        csize, = struct.unpack_from("<I", data, pos + 20)
        n, m, k = struct.unpack_from("<HHH", data, pos + 28)
        local, = struct.unpack_from("<I", data, pos + 42)
        if data[local:local + 4] != b"PK\x03\x04":
            raise NotAnApk(f"bad local header at {local}")
        ln, le = struct.unpack_from("<HH", data, local + 26)
        stop = local + 30 + ln + le + csize
        if flags & 0x08:  # data descriptor, optionally with its signature
            stop += 16 if data[stop:stop + 4] == b"PK\x07\x08" else 12
        entries_end = max(entries_end, stop)
        pos += 46 + n + m + k

    gap_end = cd_offset
    if data[cd_offset - 16:cd_offset] == SIG_BLOCK_MAGIC:
        (size,) = struct.unpack_from("<Q", data, cd_offset - 24)
        gap_end = cd_offset - size - 8
        if gap_end < entries_end or struct.unpack_from("<Q", data, gap_end)[0] != size:
            raise NotAnApk("malformed APK Signing Block")
    if gap_end < entries_end:
        raise NotAnApk("entries overlap the central directory")
    if data[entries_end:gap_end].strip(b"\x00"):
        raise NotAnApk("non-zero bytes between the entries and the signing block")

    end_record = bytearray(data[eocd:])
    struct.pack_into("<I", end_record, 16, 0)
    return data[:entries_end] + data[cd_offset:eocd] + bytes(end_record)


def entry_differences(a_path: str, b_path: str, limit: int = 20):
    """Human-readable differences between the two zips' entries."""
    out = []
    with zipfile.ZipFile(a_path) as a, zipfile.ZipFile(b_path) as b:
        a_names = [i.filename for i in a.infolist()]
        b_names = [i.filename for i in b.infolist()]
        for name in sorted(set(a_names) - set(b_names)):
            out.append(f"only in the first:  {name}")
        for name in sorted(set(b_names) - set(a_names)):
            out.append(f"only in the second: {name}")
        common = [n for n in a_names if n in set(b_names)]
        if [n for n in a_names if n in common] != [n for n in b_names if n in common]:
            out.append("the entries are in a different order")
        for name in common:
            ia, ib = a.getinfo(name), b.getinfo(name)
            if ia.CRC != ib.CRC or ia.file_size != ib.file_size:
                out.append(f"content differs:    {name}")
            elif (ia.compress_type, ia.compress_size) != (ib.compress_type, ib.compress_size):
                out.append(f"compression differs: {name}")
            elif ia.header_offset != ib.header_offset:
                out.append(f"position differs:   {name} (alignment or an earlier entry)")
            if len(out) >= limit:
                out.append("…")
                break
        for name in a_names + b_names:
            if name.startswith("META-INF/") and name.upper().endswith(V1_SUFFIXES):
                out.append(f"v1 signature file present: {name}")
                break
    return out


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    a_path, b_path = argv[1], argv[2]
    try:
        with open(a_path, "rb") as f:
            a = unsigned_view(f.read())
        with open(b_path, "rb") as f:
            b = unsigned_view(f.read())
    except (OSError, NotAnApk) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    if a == b:
        print(f"MATCH  {a_path} == {b_path} (signatures aside)")
        return 0
    print(f"DIFFER {a_path} != {b_path}")
    for line in entry_differences(a_path, b_path) or ["same entries; the bytes differ elsewhere (zip headers)"]:
        print(f"  {line}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
