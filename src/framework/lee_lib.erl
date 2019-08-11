%% @private
-module(lee_lib).

-include("lee.hrl").

-export([ term_to_string/1
        , format/2
        , make_nested_patch/3
        , splitl/2
        , splitr/2
        , inject_error_location/2
        , run_cmd/2
        ]).

-spec format(string(), [term()]) -> string().
format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).

-spec make_nested_patch(lee:model(), lee:key(), #{lee:key() => term()}) ->
                               lee:patch().
make_nested_patch(_Model, [], Children) ->
    [{set, K, V} || {K, V} <- maps:to_list(Children)];
make_nested_patch(Model, Parent, Children) ->
    #mnode{metaparams = #{?key_elements := KeyElems}} = lee_model:get(Parent, Model),
    MakeChildKey =
        fun(K) ->
                case Children of
                    #{K := Val} ->
                        Val;
                    _ ->
                        InstKey = Parent ++ [?children | K],
                        MNode = lee_model:get(InstKey, Model),
                        case MNode#mnode.metaparams of
                            #{default := Default} ->
                                Default;
                            _ ->
                                throw({missing_key_element, K, Children})
                        end
                end
        end,
    ChildKey = lists:map(MakeChildKey, KeyElems),
    [{set, Parent ++ [?lcl(ChildKey)|K], V} || {K, V} <- maps:to_list(Children)].

-spec splitl(fun((A) -> boolean()), [A]) -> [[A]].
splitl(_, []) ->
    [];
splitl(Pred, L) ->
    case lists:splitwith(Pred, L) of
        {[], [B | C]} ->
            [[B] | splitl(Pred, C)];
        {A, []} ->
            [A];
        {A, [B | C]} ->
            [A ++ [B] | splitl(Pred, C)]
    end.

-spec splitr(fun((A) -> boolean()), [A]) -> [[A]].
splitr(_, []) ->
    [];
splitr(Pred, L) ->
    case lists:splitwith(Pred, L) of
        {[], [B|C]} ->
            splitr(Pred, B, C);
        {A, []} ->
            [A];
        {A, [B|C]} ->
            [A|splitr(Pred, B, C)]
    end.

splitr(_, H, []) ->
    [[H]];
splitr(Pred, H, L) ->
    case lists:splitwith(Pred, L) of
        {A, []} ->
            [[H|A]];
        {A, [B|C]} ->
            [[H|A] | splitr(Pred, B, C)]
    end.

-spec term_to_string(term()) -> string().
term_to_string(Term) ->
    case io_lib:printable_unicode_list(Term) of
        true -> Term;
        false -> format("~p", [Term])
    end.

-spec inject_error_location(term(), lee:validate_result()) ->
                                   lee:validate_result().
inject_error_location(Location, Result) ->
    Fun = fun(Msg) ->
                  format("Key: ~p~n~s", [Location, term_to_string(Msg)])
          end,
    case Result of
        {ok, Warn} ->
            {ok, [Fun(I) || I <- Warn]};
        {error, Err, Warn} ->
            {error, [Fun(I) || I <- Err], [Fun(I) || I <- Warn]}
    end.

-spec run_cmd(string(), [string()]) -> {integer(), binary()} | {error, term()}.
run_cmd(Cmd, Args) ->
    case os:find_executable(Cmd) of
        false ->
            {error, enoent};
        Executable ->
            Port = erlang:open_port( {spawn_executable, Executable}
                                   , [ exit_status
                                     , stderr_to_stdout
                                     , {args, Args}
                                     ]),
            collect_port_output(Port, [])
    end.

collect_port_output(Port, Acc) ->
    receive
        {Port, {exit_status, Status}} ->
            {Status, iolist_to_binary(Acc)};
        {Port, {data, Data}} ->
            [Acc|Data]
    end.
