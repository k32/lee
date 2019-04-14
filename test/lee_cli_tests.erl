-module(lee_cli_tests).

-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("eunit/include/eunit.hrl").

test_cli_params() ->
    #{ something_unrelated => {[something], #{}}
     , long =>
           {[value, cli_param]
           , #{ cli_operand => "long"
              , type => lee_types:string()
              }
           }
     , short => {[value, cli_param]
                , #{ cli_short => "s"
                   , type => lee_types:integer()
                   }
                }
     , flag1 => {[value, cli_param]
                , #{ cli_short => "f"
                   , type => lee_types:boolean()
                   }
                }
     , flag2 => {[value, cli_param]
                , #{ cli_short => "g"
                   , type => lee_types:boolean()
                   }
                }
     , flag3 => {[value, cli_param]
                , #{ cli_short => "h"
                   , type => lee_types:boolean()
                   }
                }
     , both =>
           {[value, cli_param]
           , #{ cli_operand => "both"
              , cli_short => "b"
              , type => lee_types:tuple([foo, lee_types:integer()])
              }
           }
     }.

-define(match_positional(POS),
        #sc{ positional = POS
           }).

test_cli_action(Name, KeyElems, Children) ->
    {[map, cli_action]
    , #{ cli_operand => Name
       , ?key_elements => KeyElems
       }
    , lists:foldl(fun maps:merge/2, #{}, Children)
    }.

test_positional_args1() ->
    #{ posn_1 =>
           {[value, cli_positional]
           , #{ cli_arg_position => 1
              , type => lee_types:string()
              }
           }
     , posn_2 =>
           {[value, cli_positional]
           , #{ cli_arg_position => 2
              , type => lee_types:string()
              }
           }
     }.

test_positional_args2() ->
    #{ posn_n =>
           {[value, cli_positional]
           , #{ cli_arg_position => rest
              , type => lee_types:list(lee_types:atom())
              }
           }
     }.

test_model() ->
    MF = #{ foo => test_cli_params()
          , action_1 =>
                test_cli_action("action_1", [[short], [long]]
                               , [test_cli_params()])
          , action_2 =>
                test_cli_action("action_2", [[posn_1]]
                               , [test_positional_args1()])
          , action_3 =>
                test_cli_action("action_3", []
                               , [test_positional_args2()])
          , action_4 =>
                test_cli_action("action_4", [[posn_1]]
                               , [ test_positional_args1()
                                 , test_positional_args2()
                                 ])
          },
    {ok, M} = lee_model:compile([], [lee:base_model(), MF]),
    M.

-define(tok(String, Pattern),
        ?assertEqual( Pattern
                    , lee_cli:tokenize(string:split(String, " ", all))
                    )).

split_commands_test() ->
    ?assertMatch( [["--long", "foo"]]
                , lee_cli:separate_args(["--long", "foo"])
                ),
    ?assertMatch( [["-f", "1"]]
                , lee_cli:separate_args(["-f", "1"])
                ),
    ?assertMatch( [["-f", "1"]]
                , lee_cli:separate_args(["-f", "1,"])
                ),
    ?assertMatch( [["-f", "1"]]
                , lee_cli:separate_args(["-f", "1", ","])
                ),
    ?assertMatch( [["-f", "1"], ["-f", "1"]]
                , lee_cli:separate_args(["-f", "1,", "-f", "1"])
                ),
    ?assertMatch( [["-f", "1"], ["-f", "1"]]
                , lee_cli:separate_args(["-f", "1", ",", "-f", "1"])
                ).

tokenize_test() ->
    ?tok("--foo", [{long, "foo", "true"}]),
    %?tok("-sj42", [{short, $s, "true"}, {short, $j, "42"}]),
    ?tok( "--foo bar --bar foo"
        , [ {long, "foo", "bar"}
          , {long, "bar", "foo"}
          ]
        ),
    ?tok( "--foo --bar foo --baz"
        , [ {long, "foo", "true"}
          , {long, "bar", "foo"}
          , {long, "baz", "true"}
          ]
        ),
    ?tok( "--foo1 -- bar"
        , [ {long, "foo1", "true"}
          , {positional, "bar"}
          ]
        ),
    ?tok( "-- --foo"
        , [ {positional, "--foo"}
          ]
        ),
    ?tok( "foo --bar 1 --baz --jobs 33 baz quux foo"
        , [ {positional, "foo"}
          , {long, "bar", "1"}
          , {long, "baz", "true"}
          , {long, "jobs", "33"}
          , {positional, "baz"}
          , {positional, "quux"}
          , {positional, "foo"}
          ]
        ),
    ?tok("-s0 -c9", [{short, "s", "0"}, {short, "c", "9"}]),
    ?tok( "kill -9 -fml0 --foo bar -j 11 -"
        , [ {positional, "kill"}
          , {short, "9", "true"}
          , {short, "f", "true"}
          , {short, "m", "true"}
          , {short, "l", "0"}
          , {long, "foo", "bar"}
          , {short, "j", "11"}
          , {positional, "-"}
          ]
        ).

read_cli(String) ->
    Args = string:split(String, " ", all),
    lee_cli:read_to(test_model(), Args, lee_storage:new(lee_map_storage)).

simple_long_test() ->
    {ok, Data1} = read_cli("--long foo"),
    ?assertMatch( {ok, "foo"}
                , lee_storage:get([foo, long], Data1)
                ).

simple_short_test() ->
    {ok, Data1} = read_cli("-s 1"),
    ?assertMatch( {ok, 1}
                , lee_storage:get([foo, short], Data1)
                ).

simple_both_test() ->
    {ok, Data1} = read_cli("-b {foo,1}"),
    ?assertMatch( {ok, {foo, 1}}
                , lee_storage:get([foo, both], Data1)
                ),
    {ok, Data2} = read_cli("--both {foo,2}"),
    ?assertMatch( {ok, {foo, 2}}
                , lee_storage:get([foo, both], Data2)
                ).

global_flags_test() ->
    {ok, Data1} = read_cli("-fgs1"),
    ?assertMatch( {ok, true}
                , lee_storage:get([foo, flag1], Data1)
                ),
    ?assertMatch( {ok, true}
                , lee_storage:get([foo, flag2], Data1)
                ),
    ?assertMatch( undefined
                , lee_storage:get([foo, flag3], Data1)
                ),
    ?assertMatch( {ok, 1}
                , lee_storage:get([foo, short], Data1)
                ).

children_test() ->
    {ok, Data} = read_cli(", action_1 -s1 --long foo, action_2 foo bar"),
    ?assertMatch( [[action_1, ?lcl(1)]]
                , lee_storage:list([action_1, ?children], Data)
                ),
    ?assertMatch( [[action_2, ?lcl(_)]]
                , lee_storage:list([action_2, ?children], Data)
                ).
