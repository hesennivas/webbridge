# webbridge — landing site

marketing site for webbridge. vite + typescript, no framework.

## develop

```bash
npm install
npm run dev      # http://localhost:5174
```

## deploy

railway, root dir set to `web/`. docker build → caddy serves `dist/`.

```bash
docker build -t webbridge-web .
docker run --rm -e PORT=8080 -p 8080:8080 webbridge-web
```
