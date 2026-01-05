# StremHU PIA Helper (by madrian)

StremHU PIA (Private Internet Access) VPN helper szkript a StremHU Source-hoz.

Két részből áll:
- egy működő, kész Docker Compose fájlból:
  - PIA VPN konténer
  - StremHU Source konténer
  - Speedtest konténer (VPN sebességteszt + nyitott Port Check teszt)

A StremHU Source projekt itt érhető el: https://github.com/s4pp1/stremhu-source

Röviden: ez a `pia-helper.sh` két funkciót tud:
- `./pia-helper.sh setup`: interaktív `.env` beállítás (PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL), biztonsági mentés.
- `./pia-helper.sh <port>`: a forwarded portot jelenti az API felé (BASE_URL/TOKEN alapján). Nem kell futtatnod, a vpn-pia konténer automatikusan futtatja, amikor a forwarded port megváltozik. Ez biztosítja, hogy a StremHU Source torrent portja frissítve legyen.
- `./pia-helper.sh update`: a legfrissebb `pia-helper.sh` letöltése

## Telepítés / használat
1) Töltsd le a `docker-compose.yml` és `pia-helper.sh` fájlokat.
2) A script (`pia-helper.sh`) legyen végrehajtható: `chmod +x pia-helper.sh`.
3) Futtasd a szkriptet: `./pia-helper.sh setup`

- Megőrzi a meglévő `.env`-t backupba.
- Kérdez: PIA_USER, PIA_PASS, LOCAL_NETWORK, TOKEN, BASE_URL (meglévő értékeknél `Y/n`).
- Hálózati autodetekció: Docker subnet, lokális subnet; Tailscale opcionális. Fontos, mert csak így tudod elérni a csatlakozott VPN-hez a konténereket.

Ha ez az első indításod, a StremHU még nincs konfigurálva, ezért még nem tudjuk a port forwarding frissítéséhez a TOKEN/BASE_URL-t kitölteni. Semmi gond: addig nem leszel aktív feltöltő; erre a szkript figyelmeztet és kilép.

Itt az ideje első alkalommal elindítanod a konténereket a `docker compose up` paranccsal. Konfiguráld a StremHU-t a szokásos módon. Amint fut, állítsd le az egészet, majd futtasd ismét a `pia-helper.sh` szkriptet. Felismeri az eddig kitöltött adatokat, tehát mindenre nyomhatsz `Y`-t, hogy nem akarsz módosítani. A végén már ki tudja olvasni a TOKEN/BASE_URL értékeket a StremHU adatbázisából. Természetesen mindent konfigurálhatsz kézzel is.

Kézi `.env` minta:
```
# Private internet access VPN credentials:
PIA_USER=felhasznalo
PIA_PASS=jelszo

# Allowed subnets for inbound access when FIREWALL=1.
# Include:
#  - Docker network subnet the vpn container is attached to, usually 172.xxxxxx
#    Use this command to find out:
#     docker network inspect $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' vpn-pia)   --format '{{(index .IPAM.Config 0).Subnet}}'
#  - your host/LAN subnet for local access (example: 192.168.1.0/24)
#  - Tailscale subnet (100.64.0.0/10) if using Tailscale

LOCAL_NETWORK=172.18.0.0/16,10.88.1.0/24,100.64.0.0/10

TOKEN=api-token-ide
BASE_URL=https://sajat-api-url
```
Ennyi. Indítsd el újra a `docker compose up -d` parancsot, és a projekt használatra kész. A logokat a szokásos `docker compose logs -f` paranccsal tudod megnézni.


## Tippek
- 502 vagy más API hiba van induláskor, amíg a konténerek (pl. StremHU) teljesen elindulnak. Ez normális, nemsokára újra próbálja.

- A Speedtest + Port Check alapértelmezetten az :5000-es porton érhető el. A Speedtest az Ookla Speedtestet hasznája a teszteléshez.
  A Port Check fülön ellenőrizni tudod hogy nyitva -e van az adott port a PIA VPN-en.
