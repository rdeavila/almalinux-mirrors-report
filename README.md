# AlmaLinux Mirror Report

## Run locally

```
docker run --rm -it -p 7000:8000 -v ${PWD}:/docs squidfunk/mkdocs-material
```

## Build

```
docker run --rm -v ${PWD}:/docs squidfunk/mkdocs-material build
```
