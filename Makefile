all: linelimit
	rebar3 do dialyzer,eunit

demo:
	rebar3 as demo escriptize

.PHONY: linelimit
linelimit:
	support/linelimit
