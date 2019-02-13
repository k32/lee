-module(lee_model_tests).

-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(moc(Attr, Children), {[t1], Attr, Children}).

-define(moc(Attr), {[t1], Attr}).

-define(moc, {[], #{}, #{}}).

-define(mnode, #mnode{metatypes = _}).

-define(model(Attr), #{ foo => ?moc(Attr#{key => [foo]})
                      , bar =>
                            #{ bar => ?moc(Attr#{key => [bar, bar]}, #{})
                             }
                      , baz => ?moc( Attr#{key => [baz]}
                                   , #{quux => ?moc(Attr#{key => [baz, ?children, quux]}, #{})}
                                   )
                      }).

compile_test() ->
    Model = ?model(#{}),
    ?assertMatch(
       {ok, #model{ model = #{ [foo] := #mnode{ metatypes = [t1]
                                              , metaparams = #{key := [foo]}
                                              }
                             , [bar, bar] := ?mnode
                             , [baz, '$children', quux] := ?mnode
                            }
                  , metamodel = #{}
                  , meta_class_idx = #{}
                  }}
                , lee_model:compile([], [Model])
                ),
    ?assertMatch( {error, _}
                , lee_model:compile([Model, Model], [])
                ),
    ?assertMatch( {error, _}
                , lee_model:compile([], [Model, Model])
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

get_test() ->
    {ok, Model} = lee_model:compile([], [?model(#{})]),
    ?assertEqual( #mnode{ metatypes = [t1]
                        , metaparams = #{key => [foo]}
                        }
                , lee_model:get([foo], Model)
                ),
    ?assertEqual( #mnode{ metatypes = [t1]
                        , metaparams = #{key => [baz, ?children, quux]}
                        }
                , lee_model:get([baz, ?children, quux], Model)
                ).

mk_metatype_index_test() ->
    Expected = #{ t1 =>
                      ordsets:from_list([[foo], [bar, bar], [baz], [baz, ?children, quux]])
                , t2 =>
                      ordsets:from_list([[quux]])
                },
    Model0 = ?model(#{}) #{quux => {[t2], #{}}},
    {ok, Model} = lee_model:compile([], [Model0]),
    ?assertEqual( Expected
                , Model#model.meta_class_idx
                ).

match_test() ->
    ?assertMatch( true
                , lee_model:match([foo], [foo])
                ),
    ?assertMatch( true
                , lee_model:match([bar, bar], [bar, bar])
                ),
    ?assertMatch( false
                , lee_model:match([bar], [bar, bar])
                ),
    ?assertMatch( false
                , lee_model:match([bar, bar], [bar])
                ),
    ?assertMatch( false
                , lee_model:match([bar, bar], [bar, foo])
                ),
    ?assertMatch( true
                , lee_model:match([baz, ?children, quux], [baz, ?lcl(1), quux])
                ),
    ?assertMatch( false
                , lee_model:match([baz, ?children, quux], [baz, ?lcl(1), foo])
                ),
    ok.

optional_part_tests() ->
    ?assertMatch( {[], [foo]}
                , lee_model:optional_part([foo])
                ),
    ?assertMatch( {[], [bar, bar]}
                , lee_model:optional_part([bar, bar])
                ),
    ?assertMatch( {[baz, ?children], [quux]}
                , lee_model:optional_part([baz, ?children, quux])
                ).

scoped_traverse_test() ->
    Model = #{ foo => ?moc({}, #{ bar => ?moc
                                , baz => ?moc({}, #{quux => ?moc})
                                })
             , bar => ?moc({}, #{ foo => ?moc })
             },
    CheckScope =
        fun(Key, MO, Acc, Scope) ->
                [Self | Tail] = lists:reverse(Key),
                ?assertEqual(Scope, Tail),
                {MO, Acc + 1, [?children, Self|Scope]}
        end,
    ?assertEqual( {Model, 6}
                , lee_model:traverse(CheckScope, 0, [], Model)
                ).

split_key_test() ->
    ?assertMatch( {[], [foo, bar]}
                , lee_model:split_key([foo, bar])
                ),
    ?assertMatch( {[foo, bar, ?children], [quux]}
                , lee_model:split_key([foo, bar, ?children, quux])
                ),
    ?assertMatch( {[foo, ?children, bar, ?children], [quux]}
                , lee_model:split_key([foo, ?children, bar, ?children, quux])
                ).
