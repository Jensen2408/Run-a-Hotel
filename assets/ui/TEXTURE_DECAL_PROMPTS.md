# Run a Motel: texture & decal prompts (GPT image)

Generate one image per prompt. After generating, drop the PNGs in
`assets/textures/` (tiling) or `assets/decals/` (decals) and ask Claude to
upload them and wire them into the map.

## Shared style (paste in front of every prompt)

> Stylized cartoon game art for a cozy Roblox motel game, hand-painted look,
> soft flat colours, clean simple shapes, gentle colour variation, no harsh
> shadows or baked lighting, no text unless asked, no watermark, no border.
> Palette: warm cream, honey wood, teal (#1E8E8A), tile red (#D63A2C),
> soft greens, warm greys.

---

## A. Seamless tiling textures

Spec for all: **1024 x 1024, perfectly seamless / tileable on all four edges,
top-down orthographic view, even flat lighting, no perspective, no objects.**

1. **Asphalt road**: "Seamless top-down asphalt road surface, dark blue-grey,
   fine soft speckles, a few faint smooth patches, very subtle, cartoon style."
2. **Concrete sidewalk / parking lot**: "Seamless top-down light warm-grey
   concrete slabs, large square slabs with thin darker seams every 256 px,
   faint speckles, cartoon style."
3. **Grass ground**: "Seamless top-down cartoon lawn, mid green with lighter
   and darker green blade clusters and tiny clover patches, soft and not noisy."
4. **Lobby wood floor**: "Seamless top-down honey-coloured wooden floor planks,
   planks run horizontally, staggered joints, soft wood grain, a few knots,
   cartoon style."
5. **Room carpet**: "Seamless top-down soft motel carpet, warm beige-brown
   with a subtle small retro diamond pattern, low contrast, cartoon style."
6. **Kitchen floor tiles**: "Seamless top-down red and cream checkerboard
   floor tiles, 8 x 8 tiles across, thin grout lines, slightly glossy
   cartoon look."
7. **Pool water**: "Seamless top-down swimming pool water, bright turquoise
   with soft white caustic light ripples, cartoon style."
8. **Pool deck stone**: "Seamless top-down cream stone pavers, rounded square
   tiles with soft beige grout, cartoon style."
9. **Gravel / dirt path**: "Seamless top-down warm beige gravel path, small
   rounded pebbles in sand, soft and low contrast, cartoon style."

---

## B. Decals (transparent PNG)

Spec for all: **1024 x 1024 (or the ratio given), transparent background,
front view, flat, centred, crisp edges.** Keep text short and spelled
exactly as written.

1. **Welcome mat** (2:1): "Red rectangular door mat with a cream border and
   the word 'WELCOME' in chunky rounded cream letters, top-down view."
2. **Lobby travel poster** (2:3): "Retro travel poster, pine forest and snowy
   mountains at sunset over a lake, big rounded title 'VISIT PINE LAKE',
   framed look, cartoon style."
3. **Motel logo plaque** (1:1): "Round vintage motel emblem, teal circle with
   cream ring, red roof icon and pine tree, text 'RUN A MOTEL' around the top
   and 'EST. 1962' at the bottom."
4. **Kitchen menu board** (3:2): "Chalkboard menu with a wooden frame, title
   'MENU', three lines with small food icons: 'Pancakes $10', 'Burger $12',
   'Salad $8', hand-written chalk style, cartoon."
5. **Shop sale poster** (2:3): "Bright supply shop poster, 'FRESH SUPPLIES'
   title, icons of folded towels, bed sheets, eggs and flour, a red 'SALE'
   badge, cartoon style."
6. **Pool rules sign** (3:4): "White sign with a teal header 'POOL RULES',
   four simple icons with short lines: 'No running', 'No glass',
   'Swim safe', 'Have fun', cartoon style."
7. **No smoking sign** (1:1): "Round red and white no-smoking sign, cute
   rounded cigarette icon, cartoon style."
8. **Parking numbers** (1:1, make 6): "Painted white parking bay number '1'
   on transparent background, slightly worn paint, top-down" (repeat for 2-6).
9. **Manhole cover** (1:1): "Top-down round metal manhole cover, dark grey
   with a simple grid pattern and a small motel tree emblem, cartoon style."
10. **Room door hanger** (1:2): "Door hanger card, teal with cream text
    'DO NOT DISTURB' and a small sleeping moon icon, cartoon style."

---

## Where they go (Claude wires these after upload)

| Image | Applied to |
|---|---|
| Asphalt | Road (`Decor/Road.Asphalt`) |
| Concrete | Sidewalks, parking lot |
| Grass | Ground, lawns |
| Wood floor | Lobby floor, shop floor |
| Carpet | Room floors |
| Checker tiles | Kitchen floor |
| Pool water / deck | Pool water, deck, coping |
| Gravel | Courtyard path, campfire area |
| Decals | Porch mat, lobby walls, kitchen wall, shop wall, pool fence, parking bays, road, room doors |
