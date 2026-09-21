#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""静态自检：文件清单是否齐全 + Swift 文件括号是否配平。

工程的目标平台是 iPad（iPadOS），但本机是 Windows、装不了 Xcode，
所以没法真正编译 —— 这个脚本只能挡住「忘了登记文件」「少写一个 }」这类低级错。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "InkReader")
sys.path.insert(0, os.path.join(ROOT, "tools"))

import builtins

_real_print = builtins.print

# PowerShell 重定向出来的是 UTF-16，直接写文件省得再来回转码
_LOG = open(os.path.join(ROOT, "tools", "_check.txt"), "w", encoding="utf-8")


def print(*args, **kwargs):  # noqa: A001 - 故意覆盖，同时写控制台和文件
    msg = " ".join(str(a) for a in args)
    _real_print(msg)
    _LOG.write(msg + "\n")

import importlib.util

spec = importlib.util.spec_from_file_location(
    "gen_xcodeproj", os.path.join(ROOT, "tools", "gen_xcodeproj.py")
)
# 直接读源码拿清单，避免执行生成器（它会写文件）
text = open(os.path.join(ROOT, "tools", "gen_xcodeproj.py"), encoding="utf-8").read()

names = [n for n in re.findall(r'"([A-Za-z0-9_+]+\.swift)"', text) if n != "sourcecode.swift"]
seen = []
for n in names:
    if n not in seen:
        seen.append(n)

missing = []
for n in seen:
    found = False
    for dirpath, _, files in os.walk(SRC):
        if n in files:
            found = True
            break
    if not found:
        missing.append(n)

print("清单里的 Swift 文件：%d 个" % len(seen))
if missing:
    print("  ✗ 磁盘上找不到：%s" % ", ".join(missing))
else:
    print("  ✓ 全部存在")

# 磁盘上有、但没登记进工程的
on_disk = []
for dirpath, _, files in os.walk(SRC):
    for f in files:
        if f.endswith(".swift"):
            on_disk.append(f)
orphan = sorted(set(on_disk) - set(seen))
if orphan:
    print("  ✗ 有文件没登记进 gen_xcodeproj.py：%s" % ", ".join(orphan))
else:
    print("  ✓ 磁盘上的文件都已登记")

# 括号配平（只看行内，忽略字符串里的括号）
bad = []
for n in seen:
    for dirpath, _, files in os.walk(SRC):
        if n in files:
            path = os.path.join(dirpath, n)
            src = open(path, encoding="utf-8").read()
            # 去掉注释与字符串字面量后再数
            src = re.sub(r"//[^\n]*", "", src)
            src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
            src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
            if src.count("{") != src.count("}"):
                bad.append("%s: { %d / } %d" % (n, src.count("{"), src.count("}")))
            break

if bad:
    print("  ✗ 括号不配平：")
    for b in bad:
        print("     -", b)
else:
    print("  ✓ 括号全部配平")

print("RESULT:", "OK" if not missing and not orphan and not bad else "FAILED")
_LOG.flush()
_LOG.close()
