# demo-app - Infrastructure & DevOps Practical Test

Satu VM Debian 12, Docker Compose untuk 4 environment, nginx sebagai reverse proxy,
dan satu script (ci.sh) untuk build, test, deploy, promote, approval, dan rollback.

## Arsitektur

```
 client (VPN) --:80--> ufw --> nginx --+-- /dev/     -> 127.0.0.1:8081 -> demo-development
                                       +-- /staging/ -> 127.0.0.1:8082 -> demo-staging
                                       +-- /beta/    -> 127.0.0.1:8083 -> demo-beta
                                       +-- /live/    -> 127.0.0.1:8084 -> demo-live

 git commit -> hook -> build + test -> dev -> cek -> staging -> [approval] -> beta -> [approval] -> live
```

- Image dibuild sekali (tag VERSION-commit), lalu image yang sama dipromosikan antar environment.
- Konfigurasi per environment ada di envs/<env>.env. Tiap environment punya compose project dan network sendiri.

## File
- app.py: aplikasi, endpoint /health, /version, /environment
- Dockerfile: image non-root dengan HEALTHCHECK
- docker-compose.yml + envs/*.env: deployment per environment
- nginx.conf: reverse proxy
- ci.sh: pipeline

## Port & keamanan
| Port | Akses |
|---|---|
| 22 SSH | dibuka di ufw |
| 80 nginx | dibuka di ufw |
| 8081-8084 container | hanya 127.0.0.1, tidak bisa diakses langsung dari luar |

- ufw default deny incoming, fail2ban untuk SSH
- Container non-root, read_only, limit memori
- Port Docker di-bind ke 127.0.0.1 karena port Docker di 0.0.0.0 bisa melewati ufw

## Cara menjalankan
1. Install: `apt install git curl nginx ufw fail2ban docker.io docker-compose`
2. Pasang nginx.conf ke /etc/nginx/sites-available, aktifkan, reload
3. Pasang hook: `printf '#!/bin/sh\n./ci.sh pipeline\n' > .git/hooks/post-commit`
4. Commit -> pipeline jalan otomatis (atau `./ci.sh pipeline`)

| Perintah | Fungsi |
|---|---|
| ./ci.sh status | versi & health semua env |
| ./ci.sh promote staging beta | promosi + approval |
| ./ci.sh promote beta live | promosi + approval |
| ./ci.sh rollback <env> | kembali ke versi sebelumnya |

## Rollback
Setelah deploy, ci.sh mengecek /health, /environment, dan /version lewat nginx.
Kalau gagal, environment otomatis kembali ke versi sebelumnya.
Rollback manual: ./ci.sh rollback <env>. Image lama tidak dihapus, jadi tidak perlu build ulang.

## Simulasi gagal
Image dibuild dengan PORT=9000 (seharusnya 8000). Hasilnya nginx 502, container unhealthy,
log menunjukkan port 9000. Diagnosa: curl -i, docker ps, docker logs, log error nginx.
Perbaikan: deploy ulang versi sehat terakhir.

## Log
- Pipeline: .state/pipeline.log
- Approval: .state/approvals.log
- Aplikasi (JSON): docker logs demo-<env>
- nginx: /var/log/nginx/demo-app.access.log dan demo-app.error.log

## Keterbatasan
- Belum HTTPS (lab tanpa domain)
- Ada downtime singkat saat container diganti
- Catatan versi disimpan di file lokal, belum memakai registry
