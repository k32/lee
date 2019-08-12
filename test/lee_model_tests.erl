-module(lee_model_tests).

-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(moc(Attr, Children), {[t1], Attr, Children}).

-define(moc(Attr), {[t1], Attr}).

-define(moc, {[], #{}, #{}}).

-define(mnode, #mnode{metatypes = _}).

-define(metamodel,
        #{ metatype =>
               #{ t1 => {[metatype], #{}}
                , t2 => {[metatype], #{}}
                , bar => {[metatype], #{}}
                }
         }).

-define(metamodels, lee:base_metamodel(), ?metamodel).

-define(model(Attr), #{ foo => ?moc(Attr#{key => [foo]})
                      , bar =>
                            #{ bar => ?moc(Attr#{key => [bar, bar]}, #{})
                             }
                      , baz => ?moc( Attr#{key => [baz]}
                                   , #{quux => ?moc(Attr#{key => [baz, ?children, quux]}, #{})}
                                   )
                      }).

-define(NUMTESTS, 100).

-define(SIZE, 10).

-define(MODEL_DEPTH, 4).

-define(RUN_PROP(PROP, SIZE),
        {timeout, 120,
         ?_assertMatch( true
                      , proper:quickcheck( PROP()
                                         , [ {numtests, ?NUMTESTS}
                                           , {max_size, SIZE}
                                           , {to_file, user}
                                           ]
                                         )
                      )}).

-define(RUN_PROP(PROP), ?RUN_PROP(PROP, ?SIZE)).

merge_test() ->
    Model = ?model(#{}),
    ?assertMatch( {ok, _}
                , lee_model:compile([?metamodels], [Model])
                ),
    ?assertMatch( {error, _}
                , lee_model:compile([?metamodels, Model, Model], [])
                ),
    ?assertMatch( {error, _}
                , lee_model:compile([?metamodels], [Model, Model])
                ).

compile_test() ->
    %% Test that traversal of raw and cooked models yield the same
    %% results:
    ?RUN_PROP(compile_prop).

compile_prop() ->
    RecordTrace = fun(Key, Val, Acc, Scope) ->
                          { [{Key, Val, Scope} | Acc]
                          , Key
                          }
                  end,
    ?FORALL(Model0, model(atom(), #{}),
            begin
                {ok, Model1} = lee_model:compile([?metamodels], [Model0]),
                Tr0 = lists:sort(lee_model:fold(RecordTrace, [], foo, Model0)),
                Tr1 = lists:sort(lee_model:fold(RecordTrace, [], foo, Model1)),
                ?assertMatch(Tr0, Tr1)
            end).

traverse_test() ->
    CheckKey =
        fun(Key, MO, Acc) ->
                ?assertMatch( #mnode{ metatypes = [t1]
                                    , metaparams = #{key := Key}
                                    }
                            , MO
                            ),
                Acc + 1
        end,
    ?assertMatch( 4
                , lee_model:fold(CheckKey, 0, ?model(#{}))
                ).

cooked_traverse_test() ->
    {ok, Model} = lee_model:compile([?metamodels], [?model(#{})]),
    CheckKey =
        fun(Key, MO, Acc) ->
                ?assertMatch( #mnode{ metatypes = [t1]
                                    , metaparams = #{key := Key}
                                    }
                            , MO
                            ),
                Acc + 1
        end,
    ?assertMatch( 4
                , lee_model:fold(CheckKey, 0, Model)
                ).

get_test() ->
    {ok, Model} = lee_model:compile([?metamodels], [?model(#{})]),
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
    {ok, Model} = lee_model:compile([?metamodels], [Model0]),
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

scoped_traverse_test_() ->
    ?RUN_PROP(scoped_traverse_prop).

scoped_traverse_prop() ->
    CheckScope =
        fun(Key, #mnode{metaparams = MP}, Acc, Scope) ->
                #{ scope := ExpectedScope
                 , key   := ExpectedKey
                 } = MP,
                ?assertEqual(Scope, ExpectedScope),
                {_Base, Requered} = lee_model:split_key(Key),
                ?assertEqual(Key, ExpectedKey),
                {Acc + 1, Scope ++ Requered ++ [?children]}
        end,
    ?FORALL(Model, model([], #{}),
            begin
                lee_model:fold(CheckScope, 0, [], Model),
                true
            end).

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

full_split_key_test() ->
    ?assertMatch( [[foo, bar, 1]]
                , lee_model:full_split_key([foo, bar, 1])
                ),
    ?assertMatch( [[foo, ?children], [bar]]
                , lee_model:full_split_key([foo, ?children, bar])
                ),
    ?assertMatch( [[foo, ?lcl(1)], [bar]]
                , lee_model:full_split_key([foo, ?lcl(1), bar])
                ),
    ?assertMatch( [[foo, ?lcl(1)], [bar, ?children], [baz]]
                , lee_model:full_split_key([foo, ?lcl(1), bar, ?children, baz])
                ).

map_vals_test() ->
    M0 = #{ foo => {[], 0}
          , bar => #{ baz => {[], 1}
                    }
          },
    Fun = fun({MT, N}) ->
                  {[a|MT], N+1}
          end,
    ?assertEqual( #{ foo => {[a], 1}
                   , bar => #{ baz => {[a], 2}
                             }
                   }
                , lee_model:map_vals(Fun, M0)
                ).

%%%===================================================================
%%% Proper generators
%%%===================================================================

key() ->
    oneof([1, 2, 3, 4, 5, foo, bar, baz, quux, {foo, 1}]).

mnode(Depth, Key, Scope, MetaTypeGenerator, MetaParamGenerator) ->
    F = if Depth > 0 -> 1;
           true      -> 0
        end,
    ?LET({MetaTypes, MetaParams0}, {list(MetaTypeGenerator), MetaParamGenerator},
         begin
             MetaParams = MetaParams0 #{ scope => Scope
                                       , key   => Key
                                       },
             frequency([ {F, {MetaTypes, MetaParams,
                              model( Depth - 1
                                   , Key ++ [?children]
                                   , Key ++ [?children]
                                   , MetaTypeGenerator
                                   , MetaParamGenerator
                                   )}}
                       , {F, model( Depth - 0.5
                                  , Key
                                  , Scope
                                  , MetaTypeGenerator
                                  , MetaParamGenerator
                                  )}
                       , {3, {MetaTypes, MetaParams, #{}}}
                       ])
         end).

model(MetaTypeGenerator, MetaParamGenerator) ->
    model(?MODEL_DEPTH, [], [], MetaTypeGenerator, MetaParamGenerator).

model(Depth, Key0, Scope, MetaTypeGenerator, MetaParamGenerator) ->
    ?LET(Children, non_empty(list(
                     ?LET(Key, key(),
                          {Key, mnode( Depth
                                     , Key0 ++ [Key]
                                     , Scope
                                     , MetaTypeGenerator
                                     , MetaParamGenerator
                                     )})
                    )),
         begin
             maps:from_list(Children)
         end).
