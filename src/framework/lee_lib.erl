%% @private
-module(lee_lib).

-include("lee.hrl").

-export([ term_to_string/1
        , format/2
        , make_nested_patch/3
        , splitl/2
        , splitr/2
        , inject_error_location/2
        , compose_checks/1
        , perform_checks/3
        , run_cmd/2
        , validate_optional_meta_attr/3
        , validate_optional_meta_attr/4
        , validate_meta_attr/3
        ]).

-export_type([check_result/0]).

-type check_result() :: {[string()], [string()]}.

-spec format(string(), [term()]) -> string().
format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).

-spec make_nested_patch(lee:model(), lee:key(), #{lee:key() => term()}) ->
                               lee:patch().
make_nested_patch(_Model, [], Children) ->
    [{set, K, V} || {K, V} <- maps:to_list(Children)];
make_nested_patch(Model, Parent, Children) ->
    #mnode{metaparams = MAttrs} = lee_model:get(Parent, Model),
    KeyElems = ?m_attr(map, ?key_elements, MAttrs, []),
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

-spec inject_error_location(lee:key(), check_result()) ->
                                   check_result().
inject_error_location(Location, {Err, Warn}) ->
    Fun = fun(Msg) ->
                  format( "Key: ~p~n~s"
                        , [Location, term_to_string(Msg)]
                        )
          end,
    {[Fun(I) || I <- Err], [Fun(I) || I <- Warn]}.

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

-spec compose_checks([check_result()]) -> check_result().
compose_checks(L) ->
    {Err, Warn} = lists:unzip(L),
    {lists:append(Err), lists:append(Warn)}.

-spec perform_checks(lee:key(), M, [fun((M) -> check_result())]) ->
                            check_result().
perform_checks(Key, Attrs, CheckFuns) ->
    CheckResults = [F(Attrs) || F <- CheckFuns],
    inject_error_location(Key, compose_checks(CheckResults)).

-spec validate_optional_meta_attr( atom()
                                 , typerefl:type()
                                 , lee:properties() | #mnode{}
                                 , boolean()
                                 ) -> lee:validate_result().
validate_optional_meta_attr(Attr, Type, #mnode{metaparams = MP}, WarnIfAbsent) ->
    validate_optional_meta_attr(Attr, Type, MP, WarnIfAbsent);
validate_optional_meta_attr(Attr, Type, Params, WarnIfAbsent) ->
    case Params of
        #{Attr := _} ->
            validate_meta_attr(Attr, Type, Params);
        _ when WarnIfAbsent ->
            Warn = format("Missing attribute ~p", [Attr]),
            {[], [Warn]};
        _ ->
            {[], []}
    end.

-spec validate_optional_meta_attr( atom()
                                 , typerefl:type()
                                 , lee:properties() | #mnode{}
                                 ) -> lee:validate_result().
validate_optional_meta_attr(Attr, Type, #mnode{metaparams = MP}) ->
    validate_optional_meta_attr(Attr, Type, MP, false).

-spec validate_meta_attr( atom()
                        , typerefl:type()
                        , lee:properties() | #mnode{}
                        ) -> lee:validate_result().
validate_meta_attr(Attr, Type, #mnode{metaparams = MP}) ->
    validate_meta_attr(Attr, Type, MP);
validate_meta_attr(Attr, Type, Params) ->
    case Params of
        #{Attr := Val} ->
            case typerefl:typecheck(Type, Val) of
                ok ->
                    {[], []};
                {error, Err} ->
                    {[Err], []}
            end;
        _ ->
            Err = format("Expeted mandatory meta-parameter ~p", [Attr]),
            {[Err], []}
    end.
