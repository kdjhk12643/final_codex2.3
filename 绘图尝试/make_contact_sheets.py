from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent / "rendered_pages"
FONT_PATH = Path(r"C:\Windows\Fonts\NotoSansSC-VF.ttf")
FONT = ImageFont.truetype(str(FONT_PATH), 28) if FONT_PATH.exists() else ImageFont.load_default()


def main() -> None:
    pages = sorted(ROOT.glob("page-*.png"), key=lambda p: int(p.stem.split("-")[1]))
    thumb_w = 360
    thumb_h = 510
    cols = 4
    rows = 4
    batch_size = cols * rows
    for batch, start in enumerate(range(0, len(pages), batch_size), 1):
        subset = pages[start : start + batch_size]
        canvas = Image.new("RGB", (cols * thumb_w, rows * (thumb_h + 40)), "white")
        draw = ImageDraw.Draw(canvas)
        for i, path in enumerate(subset):
            img = Image.open(path).convert("RGB")
            img.thumbnail((thumb_w, thumb_h), Image.LANCZOS)
            x = (i % cols) * thumb_w + (thumb_w - img.width) // 2
            y = (i // cols) * (thumb_h + 40) + 35
            canvas.paste(img, (x, y))
            draw.text(
                ((i % cols) * thumb_w + 12, (i // cols) * (thumb_h + 40) + 4),
                path.stem,
                font=FONT,
                fill=(31, 41, 55),
            )
        out = ROOT / f"contact_sheet_{batch:02d}.png"
        canvas.save(out)
        print(out)


if __name__ == "__main__":
    main()
