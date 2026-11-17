# Run a Motel (prototype)

Game Roblox co-op management survival untuk 1–4 pemain. Siang = Preparation, malam = tekanan tamu, target: bertahan 3 malam.

## Toolchain

Dikunci oleh [rokit.toml](rokit.toml): Rojo 7.7.1, Selene 0.32.0, StyLua 2.6.0, Luau 0.747.0 (test runner CLI), luau-lsp 1.70.1 (type-check). Tidak ada package Wally.

```powershell
rokit install
```

> Di mesin ini `rojo` di PATH bisa tertangkap shim Aftman lama dan error "no aftman.toml". Panggil lewat Rokit: `& "$env:USERPROFILE\.rokit\bin\rojo.exe" ...`, atau taruh `~\.rokit\bin` di depan `~\.aftman\bin` pada PATH.

## Build dan sync

```powershell
rojo build -o RunAMotel-Test.rbxlx   # place lokal mandiri, buka di Studio
rojo serve                           # lalu hubungkan plugin Rojo di place TESTER
```

Map placeholder dibuat oleh kode (`MapBuilder`) saat server start di `Workspace.Motel`, jadi hasil build bisa langsung dimainkan. Jangan sambungkan Rojo ke place live / jangan publish.

**Mode cepat untuk tester:** di Studio, set atribut `TimeScale` (number, mis. `0.25`) pada `Workspace` sebelum menekan Play. Semua durasi (fase, menginap, kesabaran, gerak NPC) ikut dikali. Diabaikan di server live.

## Pemeriksaan CLI

```powershell
luau tests/core.spec.luau     # 20 test logika inti (transaksi, race, tagihan, restart, simulasi 3 malam)
selene src
stylua --check src tests
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=<path>/globalTypes.d.luau src tests
```

`globalTypes.d.luau` diambil dari repo luau-lsp (`scripts/globalTypes.d.luau`).

## Struktur

| Path | Instance | Isi |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared.Config` | Semua angka balancing |
| `src/shared/Constants.luau` | `ReplicatedStorage.Shared.Constants` | Nama fase, item, action, remote |
| `src/server/MotelCore.luau` | `ServerScriptService.Server.MotelCore` | State otoritatif murni (tanpa API Roblox, tanpa yield) |
| `src/server/MapBuilder.luau` | | Blockout, waypoint, ProximityPrompt |
| `src/server/Visuals.luau` | | Mobil/tamu placeholder, papan kamar, lampu, hujan |
| `src/server/Main.server.luau` | | Remote, validasi, loop Heartbeat |
| `src/client/Hud.luau`, `Main.client.luau` | `StarterPlayerScripts.Client` | HUD, pemilih kamar, laporan |
| `tests/core.spec.luau` | (tidak di-sync) | Test CLI |

`Workspace.Motel` berisi `Map` (geometri, boleh diganti art final), `Waypoints` (part tak terlihat untuk rute NPC), `Interactables` (part dengan prompt; atribut `Action` dan `RoomId`), dan `Runtime` (NPC; dikosongkan saat restart).

## Cara main

- **Resepsionis:** prompt *Check In Guest* di Front Desk → pilih kamar READY. Sewa $25 masuk saat check-in.
- **Housekeeping:** setelah checkout, ambil sampah (tong di kamar) → buang di Dumpster; ambil seprai di Linen Shelf → *Change Sheets* di kasur. Handuk diantar ke pintu kamar yang meminta (tip $5).
- **Maintenance:** *Repair AC* (tahan) saat AC rusak; *Reset Breaker* di lobby saat listrik padam (check-in berhenti).
- **Supply Shop:** Refill $15 (+3 seprai, +3 handuk), Troli $45 (kapasitas bawa 1 → 2 untuk seluruh tim).
- Tombol **Ready** di Preparation melewati sisa waktu jika semua pemain siap.

## Checklist uji manual di Studio

Belum dijalankan (MCP Studio tidak tersedia saat implementasi). Pakai `TimeScale = 0.25` untuk mempercepat.

1. **M1 slice:** Play Solo → Output berisi `[Motel] Server ready`. Tekan Ready → mobil datang, tamu antre dengan label hitung mundur. Check-in ke Room 1 → kas +$25, papan Room 1 biru. Tunggu checkout → kantong sampah muncul, kasur coklat. Bersihkan → papan hijau READY. Tamu berikutnya bisa memakai Room 1.
2. **Transaksi sekali:** klik tombol kamar di picker berkali-kali dengan cepat → kas hanya naik sekali. Tekan *Deliver Towel* dua kali → tip sekali.
3. **Validasi jarak:** buka picker, berjalan jauh dari meja, lalu pilih kamar → "Go back to the front desk".
4. **M2:** biarkan tamu antre melewati kesabaran → "Too slow!", walkout tercatat di laporan. Habiskan seprai → "Out of sheets", beli refill. Cek laporan: rent/tips/purchases/bill/kas akhir.
5. **Tagihan:** jangan layani tamu di Night 1 → kurang $5, run berakhir skor 0, tombol Restart. Restart saat ada mobil/tamu di jalan → semua NPC hilang, kas $50, Preparation Night 1.
6. **M3:** Night 2 satu AC rusak (asap, papan merah, tidak bisa disewa sampai diperbaiki). Night 3 hujan + listrik padam saat antrean ≥2 (atau detik 80): lampu mati, check-in ditolak, housekeeping tetap jalan, Reset Breaker memulihkan.
7. **Selesai 3 malam:** layar "PROTOTYPE COMPLETE!" + Restart.
8. **Co-op:** Test → Clients and Servers, 2 pemain. Info Preparation menampilkan "(2 players)" dan ~5 tamu / tagihan $66 di Night 1. Dua pemain mengambil seprai terakhir bersamaan → hanya satu dapat. Satu pemain keluar sambil membawa seprai → stok kembali.
9. **4 pemain:** belum diverifikasi; perlu sesi Studio terpisah dengan 4 klien.
10. **Mobile:** Studio Device Emulator (ponsel) → HUD terskala, prompt bisa disentuh, tombol picker cukup besar.
