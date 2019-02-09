-module(lee_model_tests).

-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/lee_internal.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(moc(Attr, Children), {[t1], Attr, Children}).

-define(moc(Attr), {[t1], Attr}).

-define(moc, {[], #{}, #{}}).

-define(model(Attr), #{ foo => ?moc(Attr#{key => [foo]})
                      , bar =>
                            #{ bar => ?moc(Attr#{key => [bar, bar]}, #{})
                             }
                      , baz => ?moc( Attr#{key => [baz]}
                                   , #{quux => ?moc(Attr#{key => [baz, ?children, quux]}, #{})}
                                   )
                      }).

merge_test() ->
    ?assertMatch( {ok, #{}}
                , lee_model:merge(#{}, #{})
                ),
    ?assertMatch( {ok, #{foo := ?moc, bar := ?moc}}
                , lee_model:merge(#{foo => ?moc}, #{bar => ?moc})
                ),
    ?assertMatch( {ok, #{foo := #{ bar := ?moc
                                 , baz := ?moc
                                 }}}
                , lee_model:merge( #{foo => #{bar => ?moc}}
                                 , #{foo => #{baz => ?moc}}
                                 )
                ),
    ?assertMatch( {error, {clashing_keys, [[foo]]}}
                , lee_model:merge( #{foo => ?moc}
                                 , #{foo => ?moc, bar => ?moc}
                                 )
                ).

traverse_test() ->
    CheckKey =
        fun(Key, MO, Acc) ->
                case MO of
                    {[t1], #{key := Key}} ->
                        ok;
                    {[t1], #{key := Key}, _} ->
                        ok
                end,
                {MO, Acc + 1}
        end,
    ?assertEqual( {?model(#{}), 4}
                , lee_model:traverse(CheckKey, 0, ?model(#{}))
                ).

desugar_test() ->
    ?assertEqual( ?model(#{}) #{foo =>
                                    ?moc(#{key => [foo]}, #{})}
                , lee_model:desugar(?model(#{}))
                ).

get_test() ->
    ?assertEqual( ?moc(#{key => [foo]})
                , lee_model:get([foo], ?model(#{}))
                ),
    ?assertEqual( ?moc(#{key => [baz, ?children, quux]}, #{})
                , lee_model:get([baz, ?children, quux], ?model(#{}))
                ).

mk_metatype_index_test() ->
    Expected = #{ t1 =>
                      map_sets:from_list([[foo], [bar, bar], [baz], [baz, ?children, quux]])
                , t2 =>
                      map_sets:from_list([[quux]])
                },
    Model = lee_model:desugar(?model(#{}) #{quux => {[t2], #{}}}),
    ?assertEqual( Expected
                , lee_model:mk_metatype_index(Model)
                ).

match_test() ->
    {ok, Model} = lee_model:create([], [?model(#{})]),
    ?assertMatch( true
                , lee_model:match(Model, [foo], [foo])
                ),
    ?assertMatch( true
                , lee_model:match(Model, [bar, bar], [bar, bar])
                ),
    ?assertMatch( false
                , lee_model:match(Model, [bar], [bar, bar])
                ),
    ?assertMatch( false
                , lee_model:match(Model, [bar, bar], [bar])
                ),
    ?assertMatch( false
                , lee_model:match(Model, [bar, bar], [bar, foo])
                ),
    ?assertMatch( true
                , lee_model:match(Model, [baz, ?children, quux], [baz, 1, quux])
                ),
    ?assertMatch( false
                , lee_model:match(Model, [baz, ?children, quux], [baz, 1, foo])
                ),
    ok.

optional_part_tests() ->
    {ok, Model} = lee_model:create([], [?model(#{})]),
    ?assertMatch( {[], [foo]}
                , lee_model:optional_part([foo])
                ),
    ?assertMatch( {[], [bar, bar]}
                , lee_model:optional_part(Model, [bar, bar])
                ),
    ?assertMatch( {[baz, ?children], [quux]}
                , lee_model:optional_part(Model, [baz, ?children, quux])
                ).
