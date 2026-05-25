from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1] / "rendered_pages"
FONT_PATH = Path(r"C:\Windows\Fonts\NotoSansSC-VF.ttf")
FONT = ImageFont.truetype(str(FONT_PATH), 26) if FONT_PATH.exists() else ImageFont.load_default()


def page_number(path: Path) -> int:
    return int(path.stem.split("-")[1])


def main() -> None:
    pages = sorted(ROOT.glob("page-*.png"), key=page_number)
    cols, rows = 4, 4
    thumb_w, thumb_h = 360, 510
    for batch, start in enumerate(range(0, len(pages), cols * rows), 1):
        subset = pages[start : start + cols * rows]
        canvas = Image.new("RGB", (cols * thumb_w, rows * (thumb_h + 38)), "white")
        draw = ImageDraw.Draw(canvas)
        for i, path in enumerate(subset):
            img = Image.open(path).convert("RGB")
            img.thumbnail((thumb_w, thumb_h), Image.LANCZOS)
            x = (i % cols) * thumb_w + (thumb_w - img.width) // 2
            y = (i // cols) * (thumb_h + 38) + 34
            canvas.paste(img, (x, y))
            draw.text(((i % cols) * thumb_w + 10, (i // cols) * (thumb_h + 38) + 4), path.stem, font=FONT, fill=(31, 41, 55))
        out = ROOT / f"contact_sheet_{batch:02d}.png"
        canvas.save(out)
        print(out)


if __name__ == "__main__":
    main()
