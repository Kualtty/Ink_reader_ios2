# -*- coding: utf-8 -*-
"""生成墨阅的 App 图标（1024×1024，不透明）。

AppIcon.appiconset 里原来只有 Contents.json、没有图片，
所以桌面/Sideloadly 上显示的是空白占位图标。这个脚本补上那张图。

用法：python tools/make_appicon.py
依赖：pillow（只在生成时需要，App 本身不依赖）
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(
    ROOT, "InkReader", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"
)

N = 1024          # 最终尺寸
S = 4             # 超采样倍数，缩回去边缘才干净
W = N * S


def u(x):
    """1024 坐标系 → 超采样坐标系"""
    return x * S


def lerp(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(3))


def bezier(p0, p1, p2, p3, t):
    mt = 1 - t
    x = (mt ** 3 * p0[0] + 3 * mt ** 2 * t * p1[0]
         + 3 * mt * t ** 2 * p2[0] + t ** 3 * p3[0])
    y = (mt ** 3 * p0[1] + 3 * mt ** 2 * t * p1[1]
         + 3 * mt * t ** 2 * p2[1] + t ** 3 * p3[1])
    return x, y


# ---------- 背景：墨蓝竖向渐变 ----------
grad = Image.new("RGB", (1, W))
for y in range(W):
    grad.putpixel((0, y), lerp((40, 54, 88), (11, 16, 30), y / (W - 1)))
img = grad.resize((W, W), Image.BILINEAR)
d = ImageDraw.Draw(img)

# ---------- 笔触：朱砂红，从右下往左上扫过去 ----------
# 画在书的后面，只露出两头，看着像一抹墨迹
stroke = Image.new("RGBA", (W, W), (0, 0, 0, 0))
sd = ImageDraw.Draw(stroke)
p0, p1, p2, p3 = (196, 812), (420, 690), (640, 856), (852, 668)
steps = 700
for i in range(steps + 1):
    t = i / steps
    x, y = bezier(p0, p1, p2, p3, t)
    x, y = u(x), u(y)          # 1024 坐标 → 超采样坐标，别漏
    # 两头细、中间粗，模拟毛笔的提按
    r = u((3 + 30 * math.sin(math.pi * t) ** 0.7))
    sd.ellipse([x - r, y - r * 0.62, x + r, y + r * 0.62], fill=(198, 62, 52, 255))
stroke = stroke.filter(ImageFilter.GaussianBlur(u(1.2)))
img.paste(stroke, (0, 0), stroke)

# ---------- 书：摊开的折页 ----------
cx, top, bot = 512, 300, 726
page_w, spine, curl = 318, 11, 36

page = (247, 240, 224)          # 纸色
page_shade = (226, 216, 196)    # 右侧页面稍暗一点
edge = (206, 194, 172)


def page_poly(sign):
    """sign=-1 左页，+1 右页"""
    sx = cx + sign * spine
    ox = cx + sign * page_w
    return [
        (u(sx), u(top)),
        (u(ox), u(top + curl)),
        (u(ox), u(bot - 6)),
        (u(sx), u(bot - 30)),
    ]


# 投影
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
shd = ImageDraw.Draw(shadow)
for sign in (-1, 1):
    poly = [(x, y + u(18)) for x, y in page_poly(sign)]
    shd.polygon(poly, fill=(0, 0, 0, 150))
shadow = shadow.filter(ImageFilter.GaussianBlur(u(14)))
img.paste(shadow, (0, 0), shadow)

for sign, fill in ((-1, page), (1, page_shade)):
    d.polygon(page_poly(sign), fill=fill)

# 书脊与外缘
d.line([(u(cx), u(top + 4)), (u(cx), u(bot - 30))], fill=edge, width=u(6))
for sign in (-1, 1):
    poly = page_poly(sign)
    d.line([poly[0], poly[3]], fill=edge, width=u(3))
    d.line([poly[1], poly[2]], fill=edge, width=u(3))

# 页面上的文字线
line = (214, 203, 182)
for sign in (-1, 1):
    inner = cx + sign * (spine + 26)
    outer = cx + sign * (page_w - 30)
    for k in range(5):
        y = top + 78 + k * 62
        # 跟着页面的斜度走
        skew = curl * (1 - abs(sign * (page_w - 30)) / page_w) * 0
        d.line(
            [(u(inner), u(y + skew)), (u(outer), u(y + curl * 0.55 + skew))],
            fill=line,
            width=u(9),
        )

# ---------- 收尾 ----------
img = img.resize((N, N), Image.LANCZOS)
img = img.convert("RGB")        # iOS 图标不允许透明通道
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, "PNG", optimize=True)
print("写好了：%s（%d×%d，%.0f KB）"
      % (os.path.relpath(OUT, ROOT), N, N, os.path.getsize(OUT) / 1024))
