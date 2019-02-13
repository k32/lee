-module(lee_lib).

-export([ parse_erl_term/1
        , format/2
        ]).

parse_erl_term(String) ->
    case erl_scan:string(String) of
        {ok, Tok0, _} ->
            Tok = Tok0 ++ [{dot, 1}],
            case erl_parse:parse_term(Tok) of
                {ok, Term} ->
                    {ok, Term};
                {error, {_, _, Err}} ->
                    {error, lists:concat(Err)}
            end;
        _ ->
            {error, "Not an erlang term"} %% TODO: Give user some clues
    end.

-spec format(string(), [term()]) -> string().
format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).
