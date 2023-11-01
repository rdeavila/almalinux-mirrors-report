.PHONY: build pack run report lint

build:
	@podman run --rm -it -v .:/workspace -w /workspace crystallang/crystal:latest-alpine shards build --release --no-debug --progress --static

pack:
	@nfpm pkg --packager deb --target ./bin/
	@nfpm pkg --packager rpm --target ./bin/

run:
	@podman run --rm -it -p 7000:8000 -v ${PWD}:/docs squidfunk/mkdocs-material

report:
	@shards run -- $(filter-out $@,$(MAKECMDGOALS))

lint:
	@ameba --fix