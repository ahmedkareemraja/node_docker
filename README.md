# node-app

## Docker

### Build the image

```
docker build -t node-app:latest .
```

- `-t node-app:latest` names (tags) the image so you can reference it later instead of using its image ID.
- `.` tells Docker to use the current directory as the build context (where the `Dockerfile` and source files are read from).

### Run the container

```
docker run -p 3000:3000 --env-file .env node-app:latest
```

- `-p 3000:3000` maps `<host_port>:<container_port>`. The container listens on the port defined by `PORT` in `.env` (currently `3000`), so the second number must match that value.
- `--env-file .env` passes the environment variables from your local `.env` file into the container at runtime. The `.env` file is excluded from the image itself (see `.dockerignore`), so this is required every time you run the container.
- `node-app:latest` is the image name/tag built in the previous step (an image ID also works).
