# Icon sheet 3 — lobby, pengaturan, peringkat — prompt untuk GPT

Untuk lobby (leaderboard, profil, cara main) dan panel pengaturan (musik/SFX). Gaya **harus sama** dengan `icon-sheet.png` dan `icon-sheet-2.png`.

Lampirkan `assets/ui/icon-sheet.png` ke ChatGPT sebagai **referensi gaya**, lalu copy **seluruh blok di bawah** sekali. Pilih **1024×1024** dan **background transparent**.

```text
Using the attached icon sheet ONLY as a style reference (same outline thickness, colours, gloss, lighting and size), create a NEW single 1024x1024 PNG image with a FULLY TRANSPARENT background: a third game UI icon sheet.

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
 1. Grey settings gear / cog.
 2. Purple double music note.
 3. Blue speaker with sound waves (volume).
 4. Cozy small house with a red roof (home / back to lobby).
Row 2:
 5. Golden crown with red gems (rank 1).
 6. Silver medal on a blue ribbon (rank 2).
 7. Bronze medal on a red ribbon (rank 3).
 8. Player profile bust silhouette in a round badge, teal.
Row 3:
 9. Open book with colourful pages (how to play / guide).
10. Three-step winners podium, gold/silver/bronze steps.
11. Big green rounded "play" triangle button.
12. Green rounded plus sign "+".
Row 4:
13. Red rounded minus sign "-".
14. Group of three friendly people busts (party / team), different shirt colours.
15. Calendar page with a red top binding.
16. Gift box with a golden ribbon bow.

Output only the finished icon sheet image.
```

## Setelah gambar jadi — taruh di mana

1. **Cek grid:** 4×4 rata, urutan sama dengan daftar, latar benar-benar transparan.
2. **Simpan di repo:** `assets/ui/icon-sheet-3.png` (folder ini). Gambar persegi di atas 1024 tidak masalah — Roblox mengecilkannya merata.
3. **Upload ke Roblox:** Studio → **View → Asset Manager → Import** → `icon-sheet-3.png` → klik kanan → **Copy Asset ID** (ID **Image**).
4. **Pasang ID-nya** di `src/shared/UiAssets.luau`, baris ketiga `iconSheets`:
   ```lua
   UiAssets.iconSheets = {
   	"rbxassetid://85647358432325", -- sheet 1
   	"rbxassetid://92991628549421", -- sheet 2
   	"rbxassetid://ID_SHEET_3_ANDA", -- sheet 3
   }
   ```
   Atau cukup kabari saya, nanti saya pasangkan.

Sampai sheet 3 terpasang, ikon-ikon ini memakai cadangan sementara (pengaturan, musik, speaker, rumah/lobby, mahkota & medali leaderboard, profil, buku, podium, play, plus/minus, grup, kalender, hadiah).
