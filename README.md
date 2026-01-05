# StremHU PIA Helper (by madrian)

StremHU PIA (Private Internet Access) VPN helper szkript StremHU Source-hoz.

A StremHU Source projekt itt érhető el:

https://github.com/s4pp1/stremhu-source

Röviden: ez a `pia-helper.sh` két funkciót tud:
- `./pia-helper.sh setup`: interaktív `.env` beállítás (PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL), biztonsági mentés.
- `./pia-helper.sh <port>`: a forwarded portot jelenti az API felé (BASE_URL/TOKEN alapján). Nem kell futtatnod, a vpn-pia konténer automatikusan futtatja, amikor a forwarded port megváltozik. Ez biztosítja, hogy a StremHU Source torrent portja frissítve legyen.

## Telepítés / használat
1) Töltsd le a docker-compose.yml és pia-helper.sh fájlokat.
2) A script (`pia-helper.sh`), legyen végrehajtható (`chmod +x pia-helper.sh`).

## Setup lépések
Futtasd: `./pia-helper.sh setup`
- Megőrzi a meglévő `.env`-t backupba.
- Kérdez: PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL (meglévő értékeknél `Y/n`).
- Hálózati autodetekció: Docker subnet, lokális subnet; Tailscale opcionális. Fontos, mert csak így tudod elérni a csatlakozott VPN-hez a konténereket.
- Ha van adatbázis (`./data/database:/app/data/database`), próbálja kinyerni a TOKEN-t és BASE_URL-t (read-only).


## Tippek
- 502 vagy más API hiba van induláskor, amíg a konténerek (pl. StremHU) teljesen elindulnak; ez normális, nemsokára újra próbálja.
