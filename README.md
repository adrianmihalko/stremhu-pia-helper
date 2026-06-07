# StremHU PIA Helper (by madrian)

StremHU PIA (Private Internet Access) VPN helper szkript a StremHU Source-hoz.

Két részből áll:
- egy működő, kész Docker Compose fájlból:
  - PIA VPN konténer
  - StremHU Source konténer
  - Speedtest konténer (VPN sebességteszt + nyitott Port Check teszt)
- és egy  `pia-helper.sh` szkriptből
  - interaktív `.env` beállítás (PIA bejelentkezési adatok, port forwardinghoz TOKEN/BASE_URL)
  - automatikus torrent port frissítés a port változásakor a StremHU-ban

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

### Telepítés röviden

    madrian@ubuntu:~/temp/test-stremhu$ git clone https://github.com/adrianmihalko/stremhu-pia-helper.git
    Cloning into 'stremhu-pia-helper'...
    remote: Enumerating objects: 46, done.
    remote: Counting objects: 100% (46/46), done.
    remote: Compressing objects: 100% (32/32), done.
    remote: Total 46 (delta 20), reused 40 (delta 14), pack-reused 0 (from 0)
    Receiving objects: 100% (46/46), 14.47 KiB | 673.00 KiB/s, done.
    Resolving deltas: 100% (20/20), done.
    
    madrian@ubuntu:~/temp/test-stremhu$ cd stremhu-pia-helper/
    madrian@ubuntu:~/temp/test-stremhu/stremhu-pia-helper$ ls
    docker-compose.yml  pia-helper.sh  README.md
    
    madrian@ubuntu:~/temp/test-stremhu/stremhu-pia-helper$ ./pia-helper.sh setup
    StremHU PIA Helper by madrian v0.2
    
    == PIA Credentials ==
    Enter PIA username: p01...
    Enter PIA password: k.....
    
    == Networks ==
    - Docker subnet not detected automatically; update .env manually if needed.
    - Detected local subnet: 10.88.1.0/24
    Local network subnets (if you dont see your local subnet, please add it here):
    LOCAL_NETWORK=10.88.1.0/24
    Include Tailscale subnet 100.64.0.0/10? [Y/n]: y
    
    == Database & API ==
    - Compose file not found in /home/madrian/temp/test-stremhu/stremhu-pia-helper or /home/madrian/temp/test-stremhu/stremhu-pia-helper; cannot auto-detect database path.
    Enter BASE_URL (leave blank to skip for now):
    - BASE_URL not provided; you can rerun setup after StremHU is configured to populate it.
    Enter TOKEN (leave blank to skip for now):
    - TOKEN not provided; rerun setup after StremHU admin user exists to fill it.
    .env updated.

Basic setup kész, itt most kilépünk és elindítjuk a konténereket. Amint kész, még egyszer futtatjuk a ./pia-helper.sh setup parancsot, hogy megtalálja a TOKEN-t és adjuk meg BASE_URL-ként a StremHU Source elérés útját

    madrian@ubuntu:~/temp/test-stremhu/stremhu-pia-helper$ docker compose up
    [+] up 4/4
     ✔ Network stremhu-pia-helper_default Created                                                                                              0.0s
     ✔ Container vpn-pia                  Created                                                                                              0.0s
     ✔ Container stremhu-source           Created                                                                                              0.0s
     ✔ Container speedtest-app            Created                                                                                              0.0s
    Attaching to speedtest-app, stremhu-source, vpn-pia
    vpn-pia  | *** DEBUG env var is set. This shows everything Bash does unsanitized, and may include sensitive information. Use with caution! ***
    ...

Amint konfiguráltuk a StremHU Sourcet, állítsuk le a konténereket és futtassuk ./pia-helper.sh setup ismét a fent említett okok miatt. 

    madrian@ubuntu:~/temp/test-stremhu/stremhu-pia-helper$ ./pia-helper.sh setup
    StremHU PIA Helper by madrian v0.2
    Backed up existing .env to .env.bak-20260607092847
    
    == PIA Credentials ==
    PIA_USER already set to 'p01..'. Keep existing? [Y/n]:
    PIA_PASS already set to 'k....'. Keep existing? [Y/n]:
    
    == Networks ==
    LOCAL_NETWORK already set to '10.88.1.0/24,100.64.0.0/10'. Keep existing? [Y/n]:
    
    == Database & API ==
    - Local database path from compose: /home/madrian/temp/test-stremhu/stremhu-pia-helper/data/system
    - BASE_URL not found in database; will prompt.
    - Extracted TOKEN from database: c268
    Enter BASE_URL (leave blank to skip for now): http://10.88.1.23:3000
    
    Use extracted TOKEN (c268...)? [Y/n]: .env updated.
    madrian@ubuntu:~/temp/test-stremhu/stremhu-pia-helper$

Ennyi, a BASE_URL-t töltsük ki (a StremHU Source elérési útja), indíthatjuk a konténereket.

