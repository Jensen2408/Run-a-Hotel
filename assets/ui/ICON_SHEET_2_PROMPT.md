# Icon sheet 2 HUD — prompt untuk GPT (ChatGPT image)

Sheet kedua berisi ikon yang tidak ada di sheet pertama (panah, silang, peringatan, tidur, sapu, bel, dll.). Gayanya **harus sama** dengan `icon-sheet.png`.

Tips: lampirkan `assets/ui/icon-sheet.png` (sheet pertama) ke ChatGPT sebagai **gambar referensi gaya**, lalu copy **seluruh blok di bawah** sekali dan paste. Pilih **1024×1024** dan **background transparent** kalau ada opsinya.

```text
Using the attached icon sheet ONLY as a style reference (same outline thickness, colours, gloss, lighting and size), create a NEW single 1024x1024 PNG image with a FULLY TRANSPARENT background: a second game UI icon sheet.

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
 1. Big chunky yellow arrow pointing straight DOWN.
 2. Big chunky yellow arrow pointing straight RIGHT.
 3. Bold red X / cross mark.
 4. Orange warning triangle with a white exclamation mark.
Row 2:
 5. Sleep symbol: three blue "Z" shapes rising diagonally (as a pictogram, not text), on a small soft cloud.
 6. Housekeeping broom with yellow bristles and a wooden handle, slightly diagonal.
 7. Golden hotel reception desk bell (service bell) on a small base.
 8. Golden hotel room key with a round red key tag.
Row 3:
 9. Cozy single bed with a white pillow and a teal blanket, seen at 3/4.
10. Wooden motel room door with a small brass knob, slightly open.
11. Light-blue snowflake (air conditioning / cold air).
12. Electrical plug with a short cable (power), yellow-orange.
Row 4:
13. Green rounded "play / next" triangle button pointing right.
14. Grey "fast-forward / skip" double triangle pointing right.
15. Cluster of three golden sparkles (four-pointed stars).
16. Red retro alarm clock with two bells on top.

Output only the finished icon sheet image.
```

## Setelah gambar jadi — taruh di mana

1. **Cek grid:** 4×4 kotak rata, urutan sama dengan daftar (ikon 1 kiri atas, ikon 16 kanan bawah), latar benar-benar transparan.
2. **Simpan di repo:** `assets/ui/icon-sheet-2.png` (folder ini). Ukuran tidak harus tepat 1024 — Roblox mengecilkan ke 1024 secara merata, grid tetap pas selama gambarnya persegi.
3. **Upload ke Roblox:** Studio → **View → Asset Manager → Import** → pilih `icon-sheet-2.png` → klik kanan → **Copy Asset ID** (ID **Image**, bukan Decal).
4. **Pasang ID-nya** di `src/shared/UiAssets.luau`, baris kedua `iconSheets`:
   ```lua
   UiAssets.iconSheets = {
   	"rbxassetid://85647358432325", -- sheet 1
   	"rbxassetid://ID_SHEET_2_ANDA", -- sheet 2
   }
   ```
   Atau cukup bilang ke saya ID-nya / bahwa file sudah di folder ini, nanti saya cek dan pasangkan.

Sampai sheet 2 terpasang, ikon-ikon ini memakai cadangan sementara (panah tutorial, tanda silang, peringatan, tidur di checklist, sapu, bel, kunci, kasur, alarm, NEXT/SKIP).
