API = src/github/api.json
AMEBA = lib/ameba/bin/ameba

.PHONY: format lint spec build clean

default: format lint spec build

format:
	crystal tool format

lint: $(AMEBA)
	lib/ameba/bin/ameba --all

spec: $(API)
	crystal spec

build: $(API)
	shards build --release

clean:
	rm -rf bin lib src/github/api.json

$(API):
	curl -sL -o $@ https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.json

$(AMEBA):
	shards install
