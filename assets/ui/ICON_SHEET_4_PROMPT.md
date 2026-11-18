# Icon sheet 4 — dapur, makanan, role — prompt untuk GPT

Untuk dapur / room service (menu, bahan, kompor) dan soft role (chef). Gaya **harus sama** dengan `icon-sheet.png`, `icon-sheet-2.png` dan `icon-sheet-3.png`.

Lampirkan `assets/ui/icon-sheet.png` ke ChatGPT sebagai **referensi gaya**, lalu copy **seluruh blok di bawah** sekali. Pilih **1024×1024** dan **background transparent**.

```text
Using the attached icon sheet ONLY as a style reference (same outline thickness, colours, gloss, lighting and size), create a NEW single 1024x1024 PNG image with a FULLY TRANSPARENT background: a fourth game UI icon sheet.

LAYOUT (very important):
- Exactly 4 columns x 4 rows = 16 equal square cells, each 256x256 pixels.
- No grid lines, no borders, no frames, no text, no letters, no numbers, no labels, no watermark.
- Each icon is centered in its own cell with about 28 px of empty transparent padding on every side. Nothing may cross into a neighbouring cell.
- All 16 icons have the same visual size and weight.

STYLE (identical for every icon, matching the reference):
- Chunky cartoon mobile/Roblox simulator game UI icon, premium casual-game HUD style.
- Bold, rounded, slightly squishy shapes, slight 3/4 perspective where it makes sense.
- Thick dark-brown outline (#2E2016) of about 10 px around the whole silhouette, plus thinner inner outlines.
- Flat vibrant colours with a soft top-to-bottom gradient and a small white glossy highlight on the upper-left.
- Light comes from the top-left. No drop shadow outside the outline, no glow, no background circle or tile behind the icon.

ICONS, in reading order (left to right, top to bottom):
Row 1:
 1. Stack of three fluffy pancakes with a butter pat and dripping maple syrup.
 2. Juicy cheeseburger: sesame bun, patty, cheese, lettuce, tomato.
 3. Fresh green salad in a white bowl with tomato slices.
 4. One white egg (slightly cream-coloured).
Row 2:
 5. Small burlap flour sack with a wheat symbol on it (no text).
 6. Golden round burger bun with sesame seeds (top and bottom halves).
 7. Raw pink-red meat patty on a small piece of white paper.
 8. Bunch of leafy green vegetables (lettuce leaves and a carrot).
Row 3:
 9. Front of a red kitchen stove / cooker with two burners and orange flames.
10. White retro fridge with a rounded top and a chrome handle.
11. Silver room-service tray with a domed cloche lid.
12. White chef hat (toque) with a puffy top.
Row 4:
13. Burnt black food lump on a frying pan with grey smoke puffs.
14. Paper order ticket / receipt with a torn bottom edge and a few grey lines (no letters).
15. Steaming cooking pot with a lid and orange handles.
16. Two theatre masks / role badge: a small gold star badge with a ribbon (represents "roles").
```

## Setelah gambar jadi

1. Simpan sebagai `assets/ui/icon-sheet-4.png` (1024×1024, transparan).
2. Upload ke Roblox (Studio → Asset Manager → Images, atau Creator Hub → Decals), salin **asset id gambar** (bukan decal id).
3. Isi baris sheet 4 di `src/shared/UiAssets.luau`:
   ```lua
   "rbxassetid://XXXXXXXX", -- sheet 4
   ```
Sampai sheet ini di-upload, ikon dapur tampil sebagai emoji (fallback) di HUD, dan ikon dunia dari server (label di atas objek) tidak tampil.
