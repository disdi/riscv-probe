# Start with Docker

`docker-compose.yml` builds the `Dockerfile` in this repository. That image installs the MkDocs versions pinned in `requirements.txt` and serves `mkdocs.yml`.

```sh
docker-compose up
```

Go to [http://localhost:8000/](http://localhost:8000/)
