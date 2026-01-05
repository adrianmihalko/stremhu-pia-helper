# StremHU PIA Helper (by madrian)

Röviden: ez a `pia-helper.sh` két funkciót tud:
- `./pia-helper.sh setup`: interaktív `.env` beállítás (PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL), kommentek megőrzése, biztonsági mentés.
- `./pia-helper.sh <port>`: a forwarded portot jelenti az API felé (BASE_URL/TOKEN alapján).

## Telepítés / használat
1) Másold a repo gyökerébe a scriptet (`pia-helper.sh`), legyen végrehajtható (`chmod +x pia-helper.sh`).
2) `.env` legyen elérhető futáskor. Dockerben mountold: `./.env:/.env:ro`.
3) Docker Compose-ban a VPN konténerhez add hozzá a scriptet: `./pia-helper.sh:/pia-helper.sh:ro`. Ha belül futtatod, indítsd a gyökérből (`/`), hogy megtalálja a `/.env`.

## Setup lépések
Futtasd: `./pia-helper.sh setup`
- Megőrzi a meglévő `.env`-t backupba.
- Kérdez: PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL (meglévő értékeknél `Y/n`).
- Hálózati autodetekció: Docker subnet, lokális subnet; Tailscale opcionális.
- Ha van adatbázis bind (`./data/database:/app/data/database`), próbálja kinyerni a TOKEN-t és BASE_URL-t (read-only).
- Végén `.env` újraírva, custom sorok érintetlenül maradnak.

## Port frissítés
Futtasd: `./pia-helper.sh <port>`
- TOKEN és BASE_URL a `.env`-ből (vagy mountolt `/.env`-ből) jön; ha hiányzik, hibával kilép.
- Curl hívás az API-ra, hibánál kilép 1-gyel, kiírja a státuszt/URL-t.

## Gyakori mount minta (docker-compose)
```yaml
    volumes:
      - ./config/vpn-pia:/pia
      - ./config/vpn-pia:/pia-shared
      - ./.env:/.env:ro
      - ./pia-helper.sh:/pia-helper.sh:ro
```
Indításkor a PIA konténerben a PF script hívja: `/pia-helper.sh <port>`.

## Tippek
- Ha 502 vagy más API hiba van induláskor, várj, amíg a konténerek (pl. StremHU) teljesen elindulnak; ez normális, a következő PF frissítésnél újra próbálja.
- Ha az adatbázis nem olvasható, manuálisan add meg TOKEN/BASE_URL értékeket setup közben.
