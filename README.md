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

**Lihat map di Edit mode (sebelum Play):** jalankan di Command Bar Studio (atau lewat MCP):

```lua
local folder = game.ServerScriptService.Server:Clone() -- salinan supaya versi modul terbaru dipakai
require(folder.MapBuilder).build(require(game.ReplicatedStorage.Shared.Config))
folder:Destroy()
```

Ini membangun `Workspace.Motel` (gameplay + scenery `MapDecor`) di place. Saat Play, server memakai map itu bila atribut `MapVersion` cocok dengan `MapBuilder.VERSION`; kalau tidak ada atau versinya beda, server membangun ulang. Naikkan `MapBuilder.VERSION` setiap kali layout berubah. Simpan place secara manual bila ingin map tetap ada.

**Mode cepat untuk tester:** di Studio, set atribut `TimeScale` (number, mis. `0.25`) pada `Workspace` sebelum menekan Play. Semua durasi (fase, menginap, kesabaran, gerak NPC) ikut dikali. Diabaikan di server live.

## Lobby + Game (satu place, dua mode)

Satu place menjalankan dua mode ([src/shared/Mode.luau](src/shared/Mode.luau)):

| Mode | Server | Isi |
|---|---|---|
| **Lobby** | Server publik (pemain masuk dari halaman game) | Aula lobby, pad room 1–4, papan TOP NIGHTS, papan profil, papan How to play, musik + pengaturan volume |
| **Game** | Reserved server yang dibuat lobby | Motel (permainan 3 malam) |

Setiap script memanggil `Mode.get()` lalu berhenti bila modenya bukan miliknya (`Server/Main` dan `Client/Main` + `Ambience` untuk Game, `Lobby/LobbyMain` dan `Client/LobbyClient` untuk Lobby). Server menulis hasilnya ke atribut `Workspace.Mode`.

**Di Studio** tidak ada reserved server, jadi pilih mode dengan atribut `Mode` (string) di `Workspace` sebelum Play: `Game` untuk menguji motel, kosong atau `Lobby` untuk menguji lobby. Map yang tersimpan di place untuk mode lain (`Workspace.Motel` / `Workspace.Lobby`) dihapus otomatis saat server mulai.

Alur: pemain berdiri di pad N masuk room N (kapasitas N). Pemain pertama memulai hitung mundur `Config.lobby.padCountdown` (20 dtk); room berangkat saat penuh atau waktu habis, lewat `TeleportService:ReserveServer(game.PlaceId)` dengan `TeleportData { partySize }`. Server Game menunggu seluruh party (maks `Config.lobby.partyWait`) sebelum fase pertama. Setelah run selesai, rekor disimpan (`Persistence.recordRun`), rekor baru memunculkan banner NEW RECORD, dan tombol **LOBBY** di laporan mengirim pemain ke server publik place ini (lobby).

Teleport tidak bisa di Studio: peluncuran room hanya disimulasikan dengan notifikasi, lalu pemain didorong keluar pad. Leaderboard dan profil memakai DataStore: aktifkan **Game Settings → Security → Enable Studio Access to API Services**.

## Pemeriksaan CLI

```powershell
luau tests/core.spec.luau     # 21 test logika inti (transaksi, race, tagihan, restart, simulasi 3 malam)
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
| `src/server/Visuals.luau` | | Mobil, tamu, papan kamar, lampu, hujan |
| `src/server/NpcRigs.luau` | | Tamu dan penjaga toko R15 default (pakaian, muka, rambut dari marketplace UGC) |
| `src/server/Main.server.luau` | | Remote, validasi, loop Heartbeat |
| `src/client/Hud.luau`, `Main.client.luau` | `StarterPlayerScripts.Client` | HUD, pemilih kamar, laporan |
| `src/server/Persistence.luau` | | DataStore rekor malam + profil (juga dipakai lobby) |
| `src/lobby/server/*` | `ServerScriptService.Lobby` | `LobbyBuilder` (aula, pad, papan), `LobbyMain` (room, teleport, leaderboard) |
| `src/lobby/client/LobbyClient.client.luau` | `StarterPlayerScripts.Client.LobbyClient` | Panel room, profil, toast; memakai `UiKit`, `Icons`, `Sfx`, `Settings` |
| `src/shared/Mode.luau` | `ReplicatedStorage.Shared.Mode` | Pilih mode Lobby/Game per server |
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
