all: linelimit
	rebar3 do dialyzer,eunit,escriptize

.PHONY: linelimit
linelimit:
	support/linelimit
