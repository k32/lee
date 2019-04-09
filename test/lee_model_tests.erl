-module(lee_model_tests).

-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("proper/include/proper.hrl").
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

cooked_traverse_test() ->
    {ok, Model} = lee_model:compile([], [?model(#{})]),
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
    ?assertEqual( {Model, 4}
                , lee_model:traverse(CheckKey, 0, Model)
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

scoped_traverse_test_() ->
    ?RUN_PROP(scoped_traverse_prop).

scoped_traverse_prop() ->
    CheckScope =
        fun(Key, MO = {_, MP, _}, Acc, Scope) ->
                #{ scope := ExpectedScope
                 , key   := ExpectedKey
                 } = MP,
                ?assertEqual(Scope, ExpectedScope),
                {_Base, Requered} = lee_model:split_key(Key),
                ?assertEqual(Key, ExpectedKey),
                {MO, Acc + 1, Scope ++ Requered ++ [?children]}
        end,
    ?FORALL(Model, model([], #{}),
            begin
                {Model1, _Acc} = lee_model:traverse(CheckScope, 0, [], Model),
                ?assertEqual(Model, Model1),
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

decompile_test_() ->
    ?RUN_PROP(decompile_compile_refl).

decompile_compile_refl() ->
    ?FORALL(Model0, model(atom(), map(atom(), term())),
            begin
                Model1 = lee_model:compile_module(Model0),
                Model = lee_model:decompile_module(Model1),
                ?assertEqual( Model0
                            , Model
                            ),
                true
            end).

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
