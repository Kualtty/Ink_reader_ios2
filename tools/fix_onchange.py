# -*- coding: utf-8 -*-
"""把 iOS 17 已废弃的 onChange(of:perform:) 单参数闭包改成两参数闭包。

背景：部署目标是 iPadOS 17.0，onChange(of:perform:) 在 17.0 起废弃，
      编译器会刷一堆 warning。新签名是 onChange(of:initial:_:)，
      闭包是 (旧值, 新值) -> Void。

注意：原来用 $0 的写法必须改，因为两参数闭包里 $0 是「旧值」，
      不改就会静默拿到错误的值。

用法：python tools/fix_onchange.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "InkReader")

changed = []

for dirpath, _dirs, files in os.walk(SRC):
    for name in files:
        if not name.endswith(".swift"):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        dirty = False
        for i, ln in enumerate(lines):
            if ".onChange(of:" not in ln:
                continue
            new = ln
            # 1) 原来直接用 $0 的，展开成名副其实的参数名（$0 在两参数闭包里是旧值）
            m = re.search(r"\{ (\w[\w.]*)\((\$0)\) \}", new)
            if m:
                new = new[:m.start()] + "{ _, value in %s(value) }" % m.group(1) + new[m.end():]
            # 2) { _ in  ->  { _, _ in
            new = new.replace("{ _ in", "{ _, _ in")
            # 3) { name in  ->  { _, name in
            new = re.sub(r"\{ (\w+) in", r"{ _, \1 in", new)
            # 幂等保护：别把已经改过的 { _, _ in 再改成 { _, _, _ in
            new = new.replace("{ _, _, _ in", "{ _, _ in")
            new = new.replace("{ _, _, in", "{ _, _ in")
            if new != ln:
                lines[i] = new
                dirty = True
                changed.append("%s:%d\n    - %s\n    + %s"
                               % (os.path.relpath(path, ROOT), i + 1, ln.strip(), new.strip()))
        if dirty:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write("\n".join(lines))

print("改动 %d 处：\n" % len(changed))
print("\n".join(changed))
