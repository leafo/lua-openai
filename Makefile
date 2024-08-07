.PHONY: build test local lint

build:
	moonc openai

test: build
	busted

local: build
	luarocks --lua-version=5.1 make --local lua-openai-dev-1.rockspec

lint:
	moonc -l openai

tags::
	moon-tags $$(git ls-files openai/ | grep -i '\.moon$$') > $@
