#!/usr/bin/env python3
"""Builds the Escrow Pay pitch deck.

Screens come from test/deck/goldens, which are rendered from the real widget
tree — so the deck cannot drift from the app the way a mockup would.

    python3 scripts/build_deck.py     ->  deck/escrow-pay.pdf
"""

from __future__ import annotations

from pathlib import Path

from reportlab.lib.colors import Color, HexColor
from reportlab.lib.pagesizes import landscape
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "test/deck/goldens"
OUT = ROOT / "deck/escrow-pay.pdf"

# 16:9, the shape every projector expects.
PAGE = landscape((1280, 720))
W, H = PAGE

VOID = HexColor("#0A0A12")
SURFACE = HexColor("#13131F")
VIOLET = HexColor("#8B5CF6")
CYAN = HexColor("#22D3EE")
SUCCESS = HexColor("#34D399")
WARNING = HexColor("#FBBF24")
TEXT = HexColor("#F4F4F8")
MUTED = HexColor("#A1A1B5")
FAINT = HexColor("#6B6B80")

DISPLAY, MONO = "Grotesk", "Mono"
DISPLAY_B, MONO_B = "Grotesk-Bold", "Mono-Bold"


def register_fonts() -> None:
    """Uses the app's own faces, so the deck and the product match."""
    fonts = ROOT / "assets/fonts"
    for name, file in [
        (DISPLAY, "SpaceGrotesk-Regular.ttf"),
        (DISPLAY_B, "SpaceGrotesk-Bold.ttf"),
        ("Grotesk-Semi", "SpaceGrotesk-SemiBold.ttf"),
        (MONO, "JetBrainsMono-Regular.ttf"),
        (MONO_B, "JetBrainsMono-Bold.ttf"),
    ]:
        pdfmetrics.registerFont(TTFont(name, str(fonts / file)))


def backdrop(c: canvas.Canvas) -> None:
    """Near-black with a faint grid — the app's own ground."""
    c.setFillColor(VOID)
    c.rect(0, 0, W, H, fill=1, stroke=0)

    c.setStrokeColor(Color(1, 1, 1, alpha=0.028))
    c.setLineWidth(1)
    for x in range(0, int(W), 48):
        c.line(x, 0, x, H)
    for y in range(0, int(H), 48):
        c.line(0, y, W, y)


def accent_rule(c: canvas.Canvas, x: float, y: float, w: float = 90) -> None:
    c.setStrokeColor(VIOLET)
    c.setLineWidth(3)
    c.line(x, y, x + w, y)


def headline(c: canvas.Canvas, text: str, x: float, y: float,
             width: float, size: float = 44) -> None:
    """Draws a headline, shrinking it until it fits the space left beside
    the screenshots. A fixed size silently ran one title under an image."""
    while size > 24 and c.stringWidth(text, DISPLAY_B, size) > width:
        size -= 1
    c.setFont(DISPLAY_B, size)
    c.setFillColor(TEXT)
    c.drawString(x, y, text)


def eyebrow(c: canvas.Canvas, text: str, x: float, y: float) -> None:
    c.setFont(MONO, 12)
    c.setFillColor(CYAN)
    c.drawString(x, y, text.upper())


def wrap(c: canvas.Canvas, text: str, font: str, size: float, width: float):
    """Greedy wrap — enough for prose at these sizes."""
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if c.stringWidth(trial, font, size) <= width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def paragraph(c, text, x, y, width, size=17, leading=25, color=MUTED,
              font=DISPLAY) -> float:
    c.setFont(font, size)
    c.setFillColor(color)
    for line in wrap(c, text, font, size, width):
        c.drawString(x, y, line)
        y -= leading
    return y


def shot(c: canvas.Canvas, name: str, x: float, cy: float, height: float):
    """Draws a screenshot centred on cy, scaled to height."""
    path = SHOTS / name
    if not path.exists():
        return 0.0
    img = ImageReader(str(path))
    iw, ih = img.getSize()
    width = height * iw / ih

    # Opaque plate, then the image with no mask. mask="auto" honoured the
    # PNG's alpha and ghosted every screenshot into the near-black page.
    c.setFillColor(SURFACE)
    c.roundRect(x - 10, cy - height / 2 - 10, width + 20, height + 20, 18,
                fill=1, stroke=0)
    c.setStrokeColor(Color(1, 1, 1, alpha=0.14))
    c.setLineWidth(1)
    c.roundRect(x - 10, cy - height / 2 - 10, width + 20, height + 20, 18,
                fill=0, stroke=1)
    c.drawImage(img, x, cy - height / 2, width=width, height=height)
    return width


def footer(c: canvas.Canvas, page: int) -> None:
    c.setFont(MONO, 10)
    c.setFillColor(FAINT)
    c.drawString(64, 34, "ESCROW PAY")
    c.drawRightString(W - 64, 34, f"{page:02d}")


def mark(c: canvas.Canvas, x: float, y: float, size: float = 26) -> None:
    """The E monogram, same geometry as the launcher icon."""
    s = size / 424.0
    c.setFillColor(VIOLET)

    def bar(cx, cy, hw, hh):
        c.roundRect(
            x + (cx - hw - 320) * s * (424 / 384) * (384 / 424),
            y + (724 - cy - hh) * s,
            2 * hw * s, 2 * hh * s, 38 * s, fill=1, stroke=0,
        )

    bar(358, 512, 38, 212)
    bar(512, 338, 192, 38)
    bar(550, 512, 90, 38)
    bar(512, 686, 192, 38)


# --- slides -----------------------------------------------------------------

def cover(c: canvas.Canvas) -> None:
    backdrop(c)
    mark(c, 64, H - 110, 44)

    c.setFont(DISPLAY_B, 66)
    c.setFillColor(TEXT)
    c.drawString(64, H - 250, "Escrow Pay")

    c.setFont(DISPLAY, 28)
    c.setFillColor(MUTED)
    c.drawString(64, H - 300, "Trade with strangers safely.")

    accent_rule(c, 64, H - 340)

    paragraph(
        c,
        "Mobile-first onchain escrow for in-person resale. Funds sit in a "
        "program-controlled account until the buyer releases them. No "
        "middleman holds the money — not even us.",
        64, H - 390, 520, size=17, leading=26,
    )

    c.setFont(MONO, 13)
    c.setFillColor(FAINT)
    c.drawString(64, 120, "CLOCK IN  ·  Solana Mobile hackathon by RadiantsDAO")
    c.drawString(64, 96, "Flutter  ·  Anchor / Rust  ·  Solana devnet")

    shot(c, "01-home.png", 790, H / 2, 560)
    c.showPage()


def problem(c: canvas.Canvas) -> None:
    backdrop(c)
    eyebrow(c, "the problem", 64, H - 90)

    headline(c, "Someone always goes first.", 64, H - 150, 700)

    y = paragraph(
        c,
        "In a face-to-face resale one side has to move before the other. The "
        "seller hands over and hopes payment lands; the buyer pays and hopes "
        "the goods are real. Bank transfers reverse, cash is a risk to carry, "
        "and a stranger's screenshot proves nothing.",
        64, H - 215, 560, leading=27,
    )

    y -= 20
    for label, text in [
        ("Buyer's risk", "Pay first and the seller can simply walk."),
        ("Seller's risk", "Hand over first and the payment may never clear."),
        ("Neither can verify", "No shared record either side trusts."),
    ]:
        c.setFont("Grotesk-Semi", 16)
        c.setFillColor(WARNING)
        c.drawString(64, y, label)
        c.setFont(DISPLAY, 15)
        c.setFillColor(MUTED)
        # Below the label, not beside it: "Neither can verify" overran a
        # fixed column and collided with its own description.
        c.drawString(64, y - 22, text)
        y -= 56

    shot(c, "03-escrow-funded.png", 830, H / 2, 540)
    footer(c, 2)
    c.showPage()


def how(c: canvas.Canvas) -> None:
    backdrop(c)
    eyebrow(c, "how it works", 64, H - 90)

    headline(c, "Money and goods move together.", 64, H - 150, 600)

    steps = [
        ("1", "Seller lists", "Item and price become a QR code. Nothing "
                              "touches the chain yet."),
        ("2", "Buyer scans and funds", "One signature opens the escrow and "
                                       "deposits. Funds are held by the "
                                       "program."),
        ("3", "Buyer inspects", "A refund window runs. The buyer can still "
                                "pull out."),
        ("4", "Release at handover", "The buyer shows a release code; the "
                                     "seller scans it and is paid on the "
                                     "spot."),
    ]

    y = H - 230
    for num, title, body in steps:
        c.setFillColor(Color(0.545, 0.361, 0.965, alpha=0.18))
        c.circle(78, y + 6, 17, fill=1, stroke=0)
        c.setFont(MONO_B, 14)
        c.setFillColor(CYAN)
        c.drawCentredString(78, y + 1, num)

        c.setFont("Grotesk-Semi", 19)
        c.setFillColor(TEXT)
        c.drawString(110, y, title)
        paragraph(c, body, 110, y - 24, 440, size=14.5, leading=20)
        y -= 96

    shot(c, "02-listing-qr.png", 700, H / 2, 520)
    shot(c, "05-release-code.png", 1000, H / 2, 520)
    footer(c, 3)
    c.showPage()


def guarantees(c: canvas.Canvas) -> None:
    backdrop(c)
    eyebrow(c, "what the program guarantees", 64, H - 90)

    headline(c, "Rules, not promises.", 64, H - 150, 700)

    cards = [
        ("Neither party holds the funds", CYAN,
         "A program-derived account custodies the deposit. Not the seller, "
         "not the buyer, not us."),
        ("The payout address is fixed", VIOLET,
         "Set when the escrow opens. No instruction can redirect it, whoever "
         "submits one."),
        ("Inaction has a deadline", WARNING,
         "A buyer who never confirms cannot strand the money. After the "
         "window the seller can claim."),
        ("The release code is safe to show", SUCCESS,
         "It authorises a payment, never a destination — so a courier can "
         "scan it without being trusted."),
    ]

    x, y = 64, H - 230
    for i, (title, tint, body) in enumerate(cards):
        col = x + (i % 2) * 400
        row = y - (i // 2) * 170

        c.setFillColor(Color(1, 1, 1, alpha=0.04))
        c.roundRect(col, row - 110, 370, 140, 16, fill=1, stroke=0)
        c.setStrokeColor(Color(tint.red, tint.green, tint.blue, alpha=0.35))
        c.setLineWidth(1)
        c.roundRect(col, row - 110, 370, 140, 16, fill=0, stroke=1)

        c.setFillColor(tint)
        c.circle(col + 24, row + 6, 5, fill=1, stroke=0)
        c.setFont("Grotesk-Semi", 16)
        c.setFillColor(TEXT)
        c.drawString(col + 40, row, title)
        paragraph(c, body, col + 24, row - 30, 322, size=13.5, leading=19)

    shot(c, "04-escrow-released.png", 900, H / 2 - 10, 540)
    footer(c, 4)
    c.showPage()


def built(c: canvas.Canvas) -> None:
    backdrop(c)
    eyebrow(c, "what we built", 64, H - 90)

    headline(c, "Native mobile, onchain settlement.", 64, H - 150, 600)

    left = [
        ("Onchain", [
            "Anchor program, six instructions",
            "PDA per trade, 138-byte account",
            "Deployed and live on devnet",
        ]),
        ("Mobile", [
            "Flutter, Android, Mobile Wallet Adapter",
            "Camera QR scan and generation",
            "Deep links, share sheet, secure storage",
        ]),
        ("Verified", [
            "37 onchain tests incl. abuse paths",
            "105 app tests, analyzer clean",
            "Devnet smoke test on every deploy",
        ]),
    ]

    y = H - 230
    for title, items in left:
        c.setFont("Grotesk-Semi", 18)
        c.setFillColor(CYAN)
        c.drawString(64, y, title)
        y -= 28
        for item in items:
            c.setFont(MONO, 12)
            c.setFillColor(FAINT)
            c.drawString(64, y, "—")
            c.setFont(DISPLAY, 14.5)
            c.setFillColor(MUTED)
            c.drawString(88, y, item)
            y -= 23
        y -= 18

    shot(c, "06-listings.png", 700, H / 2, 520)
    shot(c, "07-trades.png", 1000, H / 2, 520)
    footer(c, 5)
    c.showPage()


def honest(c: canvas.Canvas) -> None:
    backdrop(c)
    eyebrow(c, "limits and what's next", 64, H - 90)

    headline(c, "What this does not solve.", 64, H - 150, 700)

    y = paragraph(
        c,
        "A chain cannot know whether goods changed hands in a car park. No "
        "escrow can. What it can decide is who a stalemate favours, and what "
        "each side is able to do. We say so plainly rather than claiming "
        "otherwise.",
        64, H - 210, 540, leading=26,
    )

    y -= 26
    c.setFont("Grotesk-Semi", 17)
    c.setFillColor(WARNING)
    c.drawString(64, y, "Open today")
    y -= 28
    for item in [
        "A buyer who takes the goods and refunds inside the window",
        "SOL only — USDC settlement is designed for, not built",
        "Android only, because Mobile Wallet Adapter is",
    ]:
        c.setFont(DISPLAY, 14.5)
        c.setFillColor(MUTED)
        c.drawString(78, y, f"·  {item}")
        y -= 24

    y -= 22
    c.setFont("Grotesk-Semi", 17)
    c.setFillColor(SUCCESS)
    c.drawString(64, y, "Next")
    y -= 28
    for item in [
        "An arbiter who can only pay buyer or seller — never a third address",
        "Photo and video evidence, hashed onchain",
        "Courier handover: the release code already supports any submitter",
        "USDC, and a longer window for faults found later",
    ]:
        c.setFont(DISPLAY, 14.5)
        c.setFillColor(MUTED)
        c.drawString(78, y, f"·  {item}")
        y -= 24

    shot(c, "03-escrow-funded.png", 880, H / 2, 500)
    footer(c, 6)
    c.showPage()


def closing(c: canvas.Canvas) -> None:
    backdrop(c)
    mark(c, W / 2 - 22, H - 190, 44)

    c.setFont(DISPLAY_B, 52)
    c.setFillColor(TEXT)
    c.drawCentredString(W / 2, H - 290, "Escrow Pay")

    c.setFont(DISPLAY, 22)
    c.setFillColor(MUTED)
    c.drawCentredString(W / 2, H - 332, "Trade with strangers safely.")

    accent_rule(c, W / 2 - 45, H - 366)

    c.setFont(MONO, 13)
    c.setFillColor(CYAN)
    c.drawCentredString(
        W / 2, H - 430, "5pY9AH8qYE6u17MYknPeoy9HufpguEAt9Lj1vnoXqzNC"
    )
    c.setFont(MONO, 11)
    c.setFillColor(FAINT)
    c.drawCentredString(W / 2, H - 452, "PROGRAM ID  ·  SOLANA DEVNET")

    c.setFont(DISPLAY, 15)
    c.setFillColor(MUTED)
    c.drawCentredString(
        W / 2, 150, "Kris  ·  Speak Technology Ltd  ·  Lagos, Nigeria"
    )
    c.showPage()


def main() -> None:
    register_fonts()
    OUT.parent.mkdir(parents=True, exist_ok=True)

    c = canvas.Canvas(str(OUT), pagesize=PAGE)
    c.setTitle("Escrow Pay")
    c.setAuthor("Kris, Speak Technology Ltd")
    c.setSubject("Onchain escrow for in-person resale — CLOCK IN hackathon")

    for slide in (cover, problem, how, guarantees, built, honest, closing):
        slide(c)

    c.save()
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
