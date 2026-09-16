# Cloud Run Proxy

Lightweight Go HTTP/WebSocket reverse proxy for Cloud Run with path routing.

Default service name:

```text
pm-panel
```

## Files

```text
Dockerfile
main.go
deploy.sh
.dockerignore
README.md
```

## Easy Menu

Upload all files to Google Cloud Shell, then run:

```bash
chmod +x deploy.sh
./deploy.sh
```

Menu options:

```text
1) Install or redeploy
2) Change host/path config only
3) Change runtime settings only
4) Test OVPN, SSH, VLESS
5) Show logs
6) Delete Cloud Run service
7) Delete image repository
8) Exit
```

Low-cost deploy defaults:

```text
Memory: 512Mi
CPU: 1
Concurrency: 80
Min instances: 0
Max instances: 2
Timeout: 3600s
```

Region choices:

```text
southamerica-east1  Brazil, Sao Paulo
europe-southwest1   Spain, Madrid
us-central1         United States, Iowa
asia-southeast1     Singapore, best for Philippines
asia-southeast2     Jakarta, near Philippines
me-central1         Doha, Middle East
```

Default routes:

```text
/vp-us -> cffdg.mindfreak.online:700
/vp-ge -> fgfja.mindfreak.online:700
/vp-uk -> dbaai.mindfreak.online:700
/vp-sg -> dcafc.mindfreak.online:700
```

Path behavior:

```text
/vp-sg       forwards as /ovpn
/vp-sg/ssh   forwards as /ssh
/vp-sg/vless forwards as /vless
```

## One-Time Paste

If you do not want to use the menu, paste this in Cloud Shell:

```bash
chmod +x deploy.sh
./deploy.sh
```
