-module(lee_from_string_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("typerefl/include/types.hrl").

model() ->
    M0 = #{ atom =>
                {[value],
                 #{ type => atom()
                  }}
          , string =>
                {[value],
                 #{ type => string()
                  }}
          , integer =>
                {[value],
                 #{ type => integer()
                  }}
          , atoms =>
                {[value],
                 #{ type => list(atom())
                  }}
          , strings =>
                {[value],
                 #{ type => list(string())
                  }}
          , integers =>
                {[value],
                 #{ type => list(integer())
                  }}
          },
    {ok, Model} = lee_model:compile([lee:base_metamodel()], [M0]),
    Model.

from_string_test() ->
    Model = model(),
    ?assertMatch( {error, [] ++ _}
                , lee:from_string(Model, [integer], ",")),
    ?assertMatch( {error, [] ++ _}
                , lee:from_string(Model, [integer], "\"")),
    ?assertMatch( {ok, 42}
                , lee:from_string(Model, [integer], "42")),
    ?assertMatch( {ok, ''}
                , lee:from_string(Model, [atom], [])),
    ?assertMatch( {ok, '1'}
                , lee:from_string(Model, [atom], "1")),
    ?assertMatch( {ok, ""}
                , lee:from_string(Model, [string], [])),
    ?assertMatch( {ok, 'foo bar'}
                , lee:from_string(Model, [atom], "foo bar")),
    ?assertMatch( {ok, "foo bar"}
                , lee:from_string(Model, [string], "foo bar")).

from_strings_test() ->
    Model = model(),
    ?assertMatch( {ok, []}
                , lee:from_strings(Model, [atoms], [])),
    ?assertMatch( {ok, ['']}
                , lee:from_strings(Model, [atoms], [[]])),
    ?assertMatch( {ok, ['1']}
                , lee:from_strings(Model, [atoms], ["1"])),
    ?assertMatch( {ok, []}
                , lee:from_strings(Model, [strings], [])),
    ?assertMatch( {ok, [""]}
                , lee:from_strings(Model, [strings], [""])),
    ?assertMatch( {ok, ["foo bar"]}
                , lee:from_strings(Model, [strings], ["foo bar"])),
    ?assertMatch( {ok, ['foo bar']}
                , lee:from_strings(Model, [atoms], ["foo bar"])),
    ?assertMatch( {ok, [1, 2]}
                , lee:from_strings(Model, [integers], ["1", "2"])).
