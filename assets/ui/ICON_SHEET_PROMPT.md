# Icon sheet HUD — prompt untuk GPT (ChatGPT image)

Copy **seluruh blok di bawah** sekali, paste ke ChatGPT (mode gambar). Kalau ada pilihan ukuran dan latar, pilih **1024×1024** dan **background transparent**.

```text
Create a single 1024x1024 PNG image with a FULLY TRANSPARENT background: a game UI icon sheet.

LAYOUT (very important):
- Exactly 4 columns x 4 rows = 16 equal square cells, each 256x256 pixels.
- No grid lines, no borders, no frames, no text, no letters, no numbers, no labels, no watermark.
- Each icon is centered in its own cell with about 28 px of empty transparent padding on every side. Nothing may cross into a neighbouring cell.
- All 16 icons have the same visual size and weight.

STYLE (identical for every icon):
- Chunky cartoon mobile/Roblox simulator game UI icon, like premium casual-game HUD icons.
- Bold, rounded, slightly squishy shapes, slight 3/4 perspective.
- Thick dark-brown outline (#2E2016) of about 10 px around the whole silhouette, plus thinner inner outlines.
- Flat vibrant colours with a soft top-to-bottom gradient and a small white glossy highlight on the upper-left.
- Light comes from the top-left. No drop shadow outside the outline, no glow, no background circle or tile behind the icon.

ICONS, in reading order (left to right, top to bottom):
Row 1:
 1. Shiny gold coin with an embossed dollar sign.
 2. Neat stack of folded white bed sheets with a light-blue stripe.
 3. Rolled fluffy towel, light teal with a white stripe.
 4. Hotel housekeeping trolley cart (metal frame, wheels) loaded with folded linens.
Row 2:
 5. Two friendly cartoon guest busts side by side (simple round heads, one orange shirt, one blue shirt), no faces details beyond simple dots.
 6. Hourglass with a wooden frame and golden sand.
 7. Open cartoon hand / palm facing the viewer, white glove style.
 8. Golden trophy cup with a small star on it.
Row 3:
 9. Bright yellow-orange sun with rounded rays.
10. Pale yellow crescent moon with one small star next to it.
11. Blue-grey rain cloud with three blue raindrops.
12. Bold yellow lightning bolt.
Row 4:
13. Big bright green check mark.
14. Black trash bag tied at the top with a small yellow tie.
15. Silver wrench (spanner), slightly diagonal.
16. Golden five-pointed star.

Output only the finished icon sheet image.
```

## Setelah gambar jadi — taruh di mana

1. **Cek grid:** pastikan ikon ada di 4×4 kotak yang rata (ikon ke-1 kiri atas, ke-16 kanan bawah) dan latarnya benar-benar transparan. Kalau GPT memberi latar putih/kotak-kotak, minta ulang: *"same image, transparent background, no checkerboard"*.
2. **Simpan arsipnya di repo:** `assets/ui/icon-sheet.png` (folder ini).
3. **Upload ke Roblox:** di Studio buka **View → Asset Manager → Import** (ikon panah ke atas) → pilih `icon-sheet.png`. Setelah selesai, klik kanan gambarnya → **Copy Asset ID**.
   - Alternatif: Creator Hub → Creations → Development Items → **Images** → Upload. Pakai ID **Image**, bukan ID Decal.
4. **Pasang ID-nya** di `src/shared/UiAssets.luau`:
   ```lua
   UiAssets.iconSheet = "rbxassetid://ID_ANDA"
   ```
   Rojo akan menyinkronkan otomatis. Saat Play, semua ikon HUD (koin, seprai, handuk, troli, tamu, jam pasir, tangan, piala, cuaca, centang, sampah, bintang) langsung memakai gambar ini. Selama `iconSheet` masih kosong, HUD memakai emoji cadangan.
5. **Kalau ikon terpotong atau ikon tetangga ikut terlihat:** naikkan `UiAssets.cellInset` (misalnya `8`). Kalau urutannya beda dari daftar di atas, ubah koordinat `{ kolom, baris }` di `UiAssets.icons`.

Catatan: gambar yang baru di-upload kadang perlu beberapa menit lolos moderasi Roblox sebelum tampil.
