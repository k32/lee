-module(lee_lib).

-include("lee.hrl").

-export([ string_to_term/1
        , string_to_term/2
        , format/2
        , make_nested_patch/3
        ]).

string_to_term(String) ->
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

string_to_term(Type, String) ->
    StringT = lee_types:string(),
    case Type of
        StringT ->
            String;
        _ ->
            case string_to_term(String) of
                {ok, Term} -> Term;
                Error -> throw(Error)
            end
    end.

-spec format(string(), [term()]) -> string().
format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).

-spec make_nested_patch(lee:model(), lee:key(), #{lee:key() => term()}) ->
                               lee:patch().
make_nested_patch(_Model, [], Children) ->
    [{set, K, V} || {K, V} <- maps:to_list(Children)];
make_nested_patch(Model, Parent, Children) ->
    #mnode{metaparams = #{?key_elements := KeyElems}} = lee_model:get(Parent, Model),
    MakeChildKey = fun(K, Acc) ->
                           case Children of
                               #{K := Val} -> [Val|Acc];
                               _           -> error({missing_key_element, K, Children})
                           end
                   end,
    ChildKey = lists:foldl(MakeChildKey, [], KeyElems),
    [{set, Parent ++ [?lcl(ChildKey)|K], V} || {K, V} <- maps:to_list(Children)].
