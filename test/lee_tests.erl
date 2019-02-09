-module(lee_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/lee_internal.hrl").
-include_lib("lee/include/lee_types.hrl").

-define(moc, {[], #{}, #{}}).

namespace_test() ->
    ?assertMatch( #{foo := #{bar := #{baz := #{}}}}
                , lee:namespace([foo, bar], #{baz => #{}})
                ).

-define(valid(Config),
        ?assertMatch( {ok, _}
                    , catch lee:validate( Model
                                        , #data{ backend = lee_map_storage
                                               , data    = Config
                                               }
                                        )
                    )).

-define(invalid(Config),
        ?assertMatch( {error, _, _}
                    , catch lee:validate( Model
                                        , #data{ backend = lee_map_storage
                                               , data    = Config
                                               }
                                        )
                    )).

validate_test() ->
    Model0 = #{ foo => {[value]
                       , #{mandatory => true, type => lee_types:boolean()}
                       }
              , bar => {[value]
                       , #{type => lee_types:integer()}
                       }
              },
    Model1 = Model0 #{ baz => {[map]
                              , #{key => bar}
                              , Model0
                              }
                     },
    {ok, Model} = lee_model:create( [lee:base_metamodel()]
                                  , [lee:base_model(), Model1]
                                  ),
    ?valid(#{[foo] => true}),
    ?valid(#{[foo] => true, [bar] => 1}),
    ?valid(#{[foo] => false, [bar] => -12}),
    ?invalid(#{}),
    ?invalid(#{[bar] => 1}),
    ?invalid(#{[foo] => 1}),
    ?invalid(#{[foo] => true, [bar] => 1.0}),
    ?valid(#{ [baz, 1, foo] => true
            , [baz, 1, bar] => 1
            , [foo] => true
            }),
    ?valid(#{ [baz, 1, foo] => false
            , [foo] => true
            }),
    ?invalid(#{ [baz, 1, foo] => foo
              , [foo] => true
              }),
    ?invalid(#{ [baz, 1, bar] => 1
              , [foo] => true
              }),
    ok.

get_test() ->
    Model0 = #{ foo => {[value]
                       , #{mandatory => true, type => lee_types:boolean()}
                       }
              , bar => {[value]
                       , #{type => lee_types:integer(), default => 42}
                       }
              },
    Model1 = Model0 #{ baz => {[map], #{key => bar}, Model0}},
    Model2 = Model1 #{ baz => {[map], #{key => bar}, Model1}},
    {ok, Model} = lee_model:create( [lee:base_metamodel()]
                                  , [lee:base_model(), Model2]
                                  ),
    Config = #data{ backend = lee_map_storage
                  , data = #{ [foo] => true
                            , [baz, 0, foo] => true
                            , [baz, 0, bar] => 0
                            , [baz, 0, baz, 42, foo] => false
                            }
                  },
    ?assertMatch({ok, true}, lee:get(Model, Config, [foo])),
    ?assertMatch({ok, 42}, lee:get(Model, Config, [bar])),

    ?assertMatch({ok, 0}, lee:get(Model, Config, [baz, 0, bar])),
    ?assertMatch({ok, true}, lee:get(Model, Config, [baz, 0, foo])),
    ?assertMatch({ok, false}, lee:get(Model, Config, [baz, 0, baz, 42, foo])),
    ?assertMatch({ok, 42}, lee:get(Model, Config, [baz, 0, baz, 42, bar])),
    ok.

from_string_test() ->
    M = lee:base_model(),
    ?assertMatch({ok, true},  lee:from_string(M, lee_types:boolean(), "true")),
    ?assertMatch({ok, false}, lee:from_string(M, lee_types:boolean(), "false")),
    ?assertMatch({ok, 1}, lee:from_string(M, lee_types:boolean(), "1")),
    ?assertMatch({ok, 1.1}, lee:from_string(M, lee_types:boolean(), "1.1")),
    ?assertMatch({ok, {foo, "bar", []}}, lee:from_string(M, lee_types:boolean(), "{foo, \"bar\", []}")),
    ?assertMatch({error, _}, lee:from_string(M, lee_types:boolean(), "")),
    ?assertMatch({error, _}, lee:from_string(M, lee_types:boolean(), ",")),
    ok.
