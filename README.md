# StremHU PIA Helper (by madrian)

A **StremHU PIA Helper** egy PIA (Private Internet Access) VPN kiegészítő egy **már működő és bekonfigurált** [StremHU Source](https://github.com/s4pp1/stremhu-source) telepítéshez.

Nem hoz létre új stacket: a meglévő `docker-compose.yml` mellé egy **override** fájlt generál, ami

- hozzáad egy `vpn-pia` (WireGuard + PIA) konténert, amin keresztül a StremHU forgalma megy,
- hozzáad egy `speedtest-app` konténert (VPN sebességteszt + nyitott port ellenőrzés),
- a StremHU Source konténert `network_mode: service:vpn-pia` módba teszi, és a portjait átveszi a VPN konténer.

Emellett a helper automatikusan frissíti a StremHU torrent portját, amikor a PIA forwarded port megváltozik.

## Hogyan működik

1. A `vpn-pia` konténer felépíti a PIA WireGuard alagutat, és port forwardingot kér.
2. Amikor a forwarded port megváltozik, a PIA konténer lefuttatja a `pia-helper.sh <port>` parancsot.
3. A helper egy `PUT` kérést küld a StremHU API-nak (`/api/<TOKEN>/relay/settings`), beállítva az új portot.

A `TOKEN` a StremHU adatbázisából (`users.api_key`, admin szerepkör) kerül kiolvasásra, a `BASE_URL` pedig a `settings` tábla `network` bejegyzéséből (séma + host) és a compose-ban publikált portból (alapértelmezés: `7070`).

## Követelmények

- Docker és Docker Compose **>= 2.24** (az override `!reset` tag miatt; régebbi compose-nál figyelmeztet és kézzel kell a portokat átmozgatni).
- `sqlite3` és `curl` a gépen (az adatbázis olvasásához, illetve a PORT_SCRIPT-hez).
- Egy már beüzemelt StremHU Source (legalább egyszer fusson, legyen admin felhasználó).

## Telepítés

1. Töltsd le a `pia-helper.sh` fájlt (a repo-ból), és tedd végrehajthatóvá:

   ```bash
   chmod +x pia-helper.sh
   ```

2. Győződj meg róla, hogy a StremHU Source **már be van üzemelve és konfigurálva** (van admin felhasználó és hálózat), és **állítsd le a stacket**, mert a konténer hálózati módja és a publikált portok meg fognak változni:

   ```bash
   docker compose down
   ```

   > A setup először megkérdezi, hogy a StremHU már be van-e állítva, és ha nem, kilép a szükséges lépésekkel. Ezután ellenőrzi, hogy fut-e a stack: ha igen, emlékeztet a leállításra, és **addig nem folytatja**, amíg a konténerek futnak (kilép, hogy ne készüljön inkonzisztens adatbázis-másolat).

3. A StremHU `docker-compose.yml` mellett futtasd:

   ```bash
   ./pia-helper.sh setup
   ```

   A setup interaktívan bekérdezi:
   - `PIA_USER`, `PIA_PASS` (jelszó bekérésnél nem látszik),
   - `LOCAL_NETWORK`: automatikusan detektálja a Docker subnetet, a helyi LAN subnetet, és opcionálisan a Tailscale subnetet (`100.64.0.0/10`). **Fontos**, hogy a csatlakozott VPN-hez elérhető legyenek a konténerek.
   - `LOC` (PIA ország, alap: `hungary`), `TZ` (alap: `Europe/Budapest`).

   Emellett megkeresi a StremHU szolgáltatást és annak publikált webes portját (alap: `7070`), valamint kiolvassa az adatbázisból a `TOKEN`-t és a `BASE_URL`-t.

   Eredményül létrejön/módosul:
   - `.env` (mindig biztonsági mentéssel: `.env.bak-<időbélyeg>`),
   - `docker-compose.override.yml` (vagy `compose.pia.yml`, ha már van idegen override fájlod),
   - `pia-compose/pia` és `pia-compose/pia-shared` mappák.

4. Indítsd el a stacket:

   ```bash
   docker compose up -d
   ```

   Ha a generált fájl neve `compose.pia.yml`:

   ```bash
   docker compose -f docker-compose.yml -f compose.pia.yml up -d
   ```

## Adattárolás: named volume vagy bind mount

A helper mindkét esetet támogatja az adatbázis kiolvasásához:

- **Bind mount** (pl. `./data:/app/data`): a `.../system/database` mappa tartalmát előbb egy ideiglenes könyvtárba másolja.
- **Named volume** (az alapértelmezett, pl. `data:/app/data`): a valódi volume nevét a compose `volumes:` `name:` mezőjéből oldja fel (pl. `data` → `stremhu-source-data`); a tartalmat `docker cp`-vel a konténerből, vagy ha az nincs, egy ideiglenes `alpine` konténerrel másolja ki.

Az adatbázis útvonala a konténeren belül `.../system/database/app.db`. Mivel a StremHU SQLite WAL módban fut, a helper a `app.db` mellett az `app.db-wal` (és `-shm`) fájlt is átmásolja, majd `sqlite3 ".backup"` segítségével konzisztens pillanatképet készít — enélkül a friss `TOKEN`/`BASE_URL` nem látszana. A forrás adatbázist nem módosítja.

## Automatikus port frissítés

Nem kell kézzel futtatnod: a `vpn-pia` konténer automatikusan meghívja a `pia-helper.sh <port>` parancsot, amikor a forwarded port megváltozik, így a StremHU torrent portja naprakész marad.

Kézzel is futtatható:

```bash
./pia-helper.sh 51234
```

## Frissítés

```bash
./pia-helper.sh update
```

## `.env` minta

```
PIA_USER=felhasznalo
PIA_PASS=jelszo

LOCAL_NETWORK=172.18.0.0/16,10.88.1.0/24,100.64.0.0/10

TOKEN=api-token-ide
BASE_URL=https://10-88-1-25.local-ip.medicmobile.org:7070
LOC=hungary
TZ=Europe/Budapest
SELFSIGNED=false
```

- `SELFSIGNED=true` esetén a helper a `curl -k` kapcsolót használja (önmagában aláírt tanúsítvány).
- Ha a `BASE_URL` nem oldható fel az adatbázisból, a setup bekéri; később újrafuttatható.

## Tippek / hibakeresés

- Induláskor `502` vagy API hiba: amíg a konténerek (pl. StremHU) teljesen elindulnak, ez normális, a helper újrapróbálkozik.
- A Speedtest + Port Check a `http://<host>:3004` címen érhető el. A Port Check fülön ellenőrizhető, hogy a PIA VPN-en nyitva van-e az adott port.
- Ha a `!reset` miatt régebbi compose hibát jelez, frissítsd a Docker Compose-t, vagy kézzel távolítsd el a `stremhu-source` `ports:` sorait, és tedd át őket a `vpn-pia` szolgáltatás alá.
- A `compose.pia.example.yml` egy olvasható példa a generált override tartalmára.
