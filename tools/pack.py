#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把工程打包成一个干净文件夹 dist/InkReader-iPad/

去掉 .git、脚本临时文件（tools/_*.txt）、__pycache__、打包产物，
拷出来的目录自带 README / LICENSE / .github / .gitignore，
可以直接 git init → commit → push，也可以整个丢给别人用 Xcode 打开。
"""
import os
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist", "InkReader-iPad")

SKIP_DIRS = {".git", "dist", "__pycache__", "build", "DerivedData", "xcuserdata"}
SKIP_FILES = {".DS_Store"}
SKIP_SUFFIX = (".pyc", ".ipa", ".xcuserstate")

lines = []


def log(text=""):
    lines.append(text)
    print(text)


def humsize(n):
    return "%.1f KB" % (n / 1024) if n < 1024 * 1024 else "%.2f MB" % (n / 1024 / 1024)


def make_zip():
    """把 dist/InkReader-iPad 压成 dist/InkReader-iPad.zip，方便直接拖到 GitHub 网页上传。"""
    zpath = os.path.join(os.path.dirname(DIST), "InkReader-iPad.zip")
    if os.path.exists(zpath):
        os.remove(zpath)  # 单个文件覆盖，不要整目录删
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, _, filenames in os.walk(DIST):
            for name in sorted(filenames):
                fp = os.path.join(dirpath, name)
                z.write(fp, os.path.relpath(fp, DIST))
    return zpath


def main():
    # 不做 rmtree：整目录删除太危险，直接覆盖写进去就够了
    os.makedirs(DIST, exist_ok=True)

    count = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        rel = os.path.relpath(dirpath, ROOT)
        for name in sorted(filenames):
            if name in SKIP_FILES or name.endswith(SKIP_SUFFIX):
                continue
            # 脚本自己吐的临时文本（PowerShell 控制台是 GBK，靠这些文件回读结果）
            if name.startswith("_") and name.endswith(".txt"):
                continue
            src = os.path.join(dirpath, name)
            dst = os.path.join(DIST, name) if rel == "." else os.path.join(DIST, rel, name)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            count += 1

    total = 0
    biggest = ("", 0)
    for dirpath, _, filenames in os.walk(DIST):
        for name in filenames:
            size = os.path.getsize(os.path.join(dirpath, name))
            total += size
            if size > biggest[1]:
                biggest = (os.path.relpath(os.path.join(dirpath, name), DIST), size)

    log("打包完成: %s" % DIST)
    log("文件数: %d" % count)
    log("总大小: %.2f MB" % (total / 1024 / 1024))
    log("最大文件: %s (%.2f MB)" % (biggest[0], biggest[1] / 1024 / 1024))

    if "--zip" in sys.argv:
        zpath = make_zip()
        log("压缩包: %s (%s)" % (zpath, humsize(os.path.getsize(zpath))))
        log("")
        log("上传到 GitHub：把 InkReader-iPad.zip 解压后整个目录拖到网页上传，或")
        log("  cd %s" % DIST)
        log('  git init && git add . && git commit -m "墨阅 InkReader for iPad"')
        log("  git remote add origin <你的仓库地址> && git push -u origin main")

    log("RESULT: OK" if biggest[1] < 5 * 1024 * 1024 else "RESULT: 有文件超过 5 MB")

    with open(os.path.join(ROOT, "tools", "_pack.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
