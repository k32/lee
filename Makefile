all: linelimit #test/docbook.xsd test/xlink.xsd test/namespace.xsd
	rebar3 do dialyzer,eunit,ct,edoc

demo:
	rebar3 as demo escriptize

# Fetch DocBook XSD schema for testing
# test/docbook.xsd:
# 	curl -o $@ https://docbook.org/xml/5.0/xsd/docbook.xsd

# test/xlink.xsd:
# 	curl -o $@ https://www.w3.org/1999/xlink.xsd

# test/namespace.xsd:
# 	curl -o $@ https://www.w3.org/1998/namespace.xsd

.PHONY: linelimit
linelimit:
	support/linelimit
