-module(lee_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("typerefl/include/types.hrl").

-define(moc, {[], #{}, #{}}).

namespace_test() ->
    ?assertMatch( #{foo := #{bar := #{baz := #{}}}}
                , lee:namespace([foo, bar], #{baz => #{}})
                ).

run_validate(Model, Config0) ->
    Config = [{set, K, V} || {K, V} <- maps:to_list(Config0)],
    Data = lee_storage:patch( lee_storage:new(lee_map_storage, [])
                            , Config
                            ),
    catch lee:validate(Model, Data).

-define(valid(Config),
        ?assertMatch( {ok, _}
                    , run_validate(Model, Config)
                    )).

-define(invalid(Config),
        ?assertMatch( {error, _, _}
                    , run_validate(Model, Config)
                    )).

validate_test() ->
    Model0 = #{ foo => {[value]
                       , #{type => typerefl:boolean()}
                       }
              , bar => {[value]
                       , #{type => typerefl:integer(), default => 42}
                       }
              },
    Model1 = Model0 #{ baz => {[map]
                              , #{}
                              , Model0
                              }
                     },
    {ok, Model} = compile(Model1),
    ?valid(#{[foo] => true}),
    ?valid(#{[foo] => true, [bar] => 1}),
    ?valid(#{[foo] => false, [bar] => -12}),
    ?invalid(#{}),
    ?invalid(#{[bar] => 1}),
    ?invalid(#{[foo] => 1}),
    ?invalid(#{[foo] => true, [bar] => 1.0}),
    ?valid(#{ [baz, ?lcl(1), foo] => true
            , [baz, ?lcl(1), bar] => 1
            , [foo] => true
            }),
    ?valid(#{ [baz, ?lcl(1), foo] => false
            , [foo] => true
            }),
    ?invalid(#{ [baz, ?lcl(1), foo] => foo
              , [foo] => true
              }),
    ?invalid(#{ [baz, ?lcl(1), bar] => 1
              , [foo] => true
              }),
    ok.

meta_validate_value_test() ->
    Compile = fun(Attrs) ->
                      compile(#{foo => {[value], Attrs}})
              end,
    %% Missing `type':
    ?assertMatch( {error, {validation_error, _}}
                , Compile(#{})
                ),
    %% Wrong type of `default':
    ?assertMatch( {error, {validation_error, _}}
                , Compile(#{type => integer(), default => foo})
                ),
    %% Wrong type of `oneliner':
    ?assertMatch( {error, {validation_error, _}}
                , Compile(#{type => integer(), oneliner => foo})
                ),
    %% Error in `doc':
    ?assertMatch( {error, {validation_error, _}}
                , Compile(#{type => integer(), doc => "<para>foo"})
                ).

meta_validate_map_test() ->
    Model1 = #{foo => {[map], #{key_elements => foo}}},
    ?assertMatch({error, {validation_error, _}}, compile(Model1)),
    Model2 = #{foo => {[map], #{key_elements => []}}},
    ?assertMatch({ok, _}, compile(Model2)),
    Model3 = #{foo => {[map], #{key_elements => [[foo]]}}},
    ?assertMatch({error, {validation_error, _}}, compile(Model3)),
    Model4 = #{foo => {[map],
                       #{key_elements => [bar]},
                       #{bar => {[value], #{}}}
                      }},
    ?assertMatch({error, {validation_error, _}}, compile(Model4)),
    Model5 = #{foo => {[map],
                       #{key_elements => [[bar]]},
                       #{bar => {[value], #{}}}
                      }},
    ?assertMatch({ok, _}, compile(Model5)).

get_test() ->
    Model0 = #{ foo => {[value]
                       , #{type => typerefl:boolean()}
                       }
              , bar => {[value]
                       , #{type => typerefl:integer(), default => 42}
                       }
              },
    Model1 = Model0 #{ baz => {[map], #{}, Model0}},
    Model2 = Model1 #{ baz => {[map], #{}, Model1}},
    {ok, Model} = compile(Model2),
    Patch = [ {set, [foo],                              true }
            , {set, [baz, ?lcl(0), foo],                true }
            , {set, [baz, ?lcl(0), bar],                0    }
            , {set, [baz, ?lcl(1), foo],                false}
            , {set, [baz, ?lcl(0), baz, ?lcl(42), foo], false}
            ],
    Config = lee_storage:patch( lee_storage:new(lee_map_storage)
                              , Patch
                              ),
    ?assertMatch(true, lee:get(Model, Config, [foo])),
    ?assertMatch(42, lee:get(Model, Config, [bar])),

    ?assertMatch(0, lee:get(Model, Config, [baz, ?lcl(0), bar])),
    ?assertMatch(true, lee:get(Model, Config, [baz, ?lcl(0), foo])),

    ?assertMatch(false, lee:get(Model, Config, [baz, ?lcl(1), foo])),
    ?assertMatch(42, lee:get(Model, Config, [baz, ?lcl(1), bar])),

    ?assertMatch(false, lee:get(Model, Config, [baz, ?lcl(0), baz, ?lcl(42), foo])),
    ?assertMatch(42, lee:get(Model, Config, [baz, ?lcl(0), baz, ?lcl(42), bar])),
    ok.

overlay_test() ->
    Model0 = #{ foo => {[value]
                       , #{type => typerefl:boolean()}
                       }
              , bar => {[value]
                       , #{type => typerefl:integer(), default => 42}
                       }
              },
    Model1 = Model0 #{ baz => {[map], #{}, Model0}},
    Model2 = Model1 #{ baz => {[map], #{}, Model1}},
    {ok, Model} = compile(Model2),
    Patch1 = [ {set, [foo],                              true }
             , {set, [baz, ?lcl(0), foo],                true }
             , {set, [baz, ?lcl(0), bar],                0    }
             , {set, [baz, ?lcl(1), foo],                false}
             , {set, [baz, ?lcl(0), baz, ?lcl(42), foo], false}
             ],
    Config1 = lee_storage:patch( lee_storage:new(lee_map_storage)
                               , Patch1
                               ),
    Patch2 = [ {set, [bar],                              32   }
             , {set, [baz, ?lcl(2), foo],                false}
             , {set, [baz, ?lcl(2), bar],                21   }
             ],
    Config2 = lee_storage:patch( lee_storage:new(lee_map_storage)
                               , Patch2
                               ),
    Config = [Config2, Config1],

    ?assertMatch(true, lee:get(Model, Config, [foo])),
    ?assertMatch(32, lee:get(Model, Config, [bar])),

    ?assertMatch(0, lee:get(Model, Config, [baz, ?lcl(0), bar])),
    ?assertMatch(true, lee:get(Model, Config, [baz, ?lcl(0), foo])),

    ?assertMatch(false, lee:get(Model, Config, [baz, ?lcl(1), foo])),
    ?assertMatch(42, lee:get(Model, Config, [baz, ?lcl(1), bar])),

    ?assertMatch(21, lee:get(Model, Config, [baz, ?lcl(2), bar])),

    ?assertMatch( [[baz, ?lcl(0)], [baz, ?lcl(1)], [baz, ?lcl(2)]]
                , lee:list(Model, Config, [baz, ?children])
                ),
    ok.

compile(Model) ->
    lee_model:compile( [lee:base_metamodel()]
                     , [Model]
                     ).
