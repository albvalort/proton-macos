#!/usr/bin/env python3
"""Tiny xref helper over `otool -tV` output.

Usage:
  xref.py ASM func ADDR        -> start address of the function containing ADDR
  xref.py ASM callers ADDR     -> functions that call/jump to ADDR (direct only)
  xref.py ASM str TEXT         -> functions referencing a literal containing TEXT
  xref.py ASM tree ADDR DEPTH  -> caller tree up to DEPTH
  xref.py ASM ripref ADDR      -> instructions whose %rip-relative operand resolves to ADDR
Function starts are approximated by `pushq %rbp` prologues.
"""
import bisect
import os
import pickle
import re
import sys

LINE = re.compile(r'^([0-9a-f]{16})\t(\S+)\t?(.*)$')

def load(asm):
    cache = asm + '.idx'
    if os.path.exists(cache) and os.path.getmtime(cache) > os.path.getmtime(asm):
        with open(cache, 'rb') as f:
            return pickle.load(f)
    starts, calls, lits = [], {}, []
    with open(asm, errors='replace') as f:
        for line in f:
            m = LINE.match(line)
            if not m:
                continue
            addr = int(m.group(1), 16)
            op, rest = m.group(2), m.group(3)
            if op == 'pushq' and rest.startswith('%rbp'):
                starts.append(addr)
            elif op in ('callq', 'jmp') and rest.startswith('0x'):
                tgt = int(rest.split()[0], 16)
                calls.setdefault(tgt, []).append(addr)
            if 'literal pool for: "' in rest:
                lits.append((addr, rest.split('literal pool for: ', 1)[1]))
    data = (starts, calls, lits)
    with open(cache, 'wb') as f:
        pickle.dump(data, f)
    return data

def func_of(starts, a):
    i = bisect.bisect_right(starts, a) - 1
    return starts[i] if i >= 0 else None

def callers(starts, calls, a):
    return sorted({func_of(starts, c) for c in calls.get(a, [])} - {None})

def main():
    asm, cmd = sys.argv[1], sys.argv[2]
    starts, calls, lits = load(asm)
    if cmd == 'func':
        print(hex(func_of(starts, int(sys.argv[3], 16))))
    elif cmd == 'callers':
        a = int(sys.argv[3], 16)
        for c in calls.get(a, []):
            print(hex(c), 'in', hex(func_of(starts, c)))
    elif cmd == 'str':
        for a, s in lits:
            if sys.argv[3] in s:
                print(hex(a), 'in', hex(func_of(starts, a)), s[:120])
    elif cmd == 'ripref':
        want = int(sys.argv[3], 16)
        rip = re.compile(r'(-?0x[0-9a-f]+)\(%rip\)')
        prev = None
        with open(asm, errors='replace') as f:
            for line in f:
                m = LINE.match(line)
                if not m:
                    continue
                addr = int(m.group(1), 16)
                if prev:
                    paddr, pdisp, ptext = prev
                    if addr + pdisp == want:
                        print(hex(paddr), 'in', hex(func_of(starts, paddr)), ptext.strip()[:100])
                    prev = None
                r = rip.search(m.group(3))
                if r:
                    prev = (addr, int(r.group(1), 16), m.group(2) + ' ' + m.group(3))
    elif cmd == 'tree':
        def walk(a, d, seen):
            if d < 0 or a in seen:
                return
            seen.add(a)
            for c in callers(starts, calls, a):
                print('  ' * (int(sys.argv[4]) - d) + hex(c))
                walk(c, d - 1, seen)
        root = func_of(starts, int(sys.argv[3], 16))
        print(hex(root))
        walk(root, int(sys.argv[4]) - 1, set())

if __name__ == '__main__':
    main()
