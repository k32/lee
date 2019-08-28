-module(lee_cli_tests).

-export([test_model_raw/0, test_model/0]).

-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("eunit/include/eunit.hrl").

test_cli_params() ->
    #{ something_unrelated => {[], #{}}
     , long =>
           {[value, cli_param]
           , #{ cli_operand => "long"
              , type => typerefl:string()
              , default => "default"
              , oneliner => "An example of a long CLI argument"
              }
           }
     , short => {[value, cli_param]
                , #{ cli_short => $s
                   , type => typerefl:integer()
                   , oneliner => "An example of a short CLI argument"
                   }
                }
     , flag1 => {[value, cli_param]
                , #{ cli_short => $f
                   , type => typerefl:boolean()
                   , oneliner => "Flag1"
                   }
                }
     , flag2 => {[value, cli_param]
                , #{ cli_short => $g
                   , type => typerefl:boolean()
                   , oneliner => "Some flag"
                   }
                }
     , flag3 => {[value, cli_param]
                , #{ cli_short => $h
                   , type => typerefl:boolean()
                   , oneliner => "Another flag"
                   }
                }
     , both =>
           {[value, cli_param]
           , #{ cli_operand => "both"
              , cli_short => $b
              , type => typerefl:tuple([foo, typerefl:integer()])
              , oneliner => "This can be set via short or long argument"
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
       , oneliner => "This is a test CLI action. It does stuff"
       , doc => "<para>This is a long and elaborate
                 documentation of a CLI action</para>
                 <para>
                 Blah blah blah
                 </para>"
       }
    , lists:foldl(fun maps:merge/2, #{}, Children)
    }.

test_positional_args1() ->
    #{ posn_1 =>
           {[value, cli_positional]
           , #{ cli_arg_position => 1
              , type => typerefl:string()
              }
           }
     , posn_2 =>
           {[value, cli_positional]
           , #{ cli_arg_position => 2
              , type => typerefl:string()
              }
           }
     }.

test_positional_args2() ->
    #{ posn_n =>
           {[value, cli_positional]
           , #{ cli_arg_position => rest
              , type => typerefl:list(typerefl:atom())
              }
           }
     }.

test_model_raw() ->
    #{ foo => test_cli_params()
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
     }.

test_model() ->
    MF = test_model_raw(),
    {ok, M} = lee_model:compile( [ lee:base_metamodel()
                                 , lee_cli:metamodel()
                                 ]
                               , [MF]
                               ),
    M.

-define(tok(String, Pattern),
        ?assertEqual( Pattern
                    , lee_cli:tokenize($@, string:tokens(String, " "))
                    )).

tokenize_test() ->
    ?tok("--foo", [{long, "foo", "true"}]),
    ?tok("-sj42", [{short, $s, "true"}, {short, $j, "42"}]),
    ?tok("@foo", [{command, "foo"}]),
    ?tok( "--foo bar --bar foo"
        , [ {long, "foo", "bar"}
          , {long, "bar", "foo"}
          ]),
    ?tok( "--foo --bar foo --baz"
        , [ {long, "foo", "true"}
          , {long, "bar", "foo"}
          , {long, "baz", "true"}
          ]),
    ?tok( "--foo1 -- bar"
        , [ {long, "foo1", "true"}
          , {positional, "bar"}
          ]),
    ?tok( "-- --foo"
        , [ {positional, "--foo"}
          ]),
    ?tok( "foo --bar 1 --baz --jobs 33 baz quux foo"
        , [ {positional, "foo"}
          , {long, "bar", "1"}
          , {long, "baz", "true"}
          , {long, "jobs", "33"}
          , {positional, "baz"}
          , {positional, "quux"}
          , {positional, "foo"}
          ]),
    ?tok("-s0 -c9", [{short, $s, "0"}, {short, $c, "9"}]),
    ?tok( "kill -9 -fml0 --foo bar -j 11 - @cmd foo -- @bar"
        , [ {positional, "kill"}
          , {short, $9, "true"}
          , {short, $f, "true"}
          , {short, $m, "true"}
          , {short, $l, "0"}
          , {long, "foo", "bar"}
          , {short, $j, "11"}
          , {positional, "-"}
          , {command, "cmd"}
          , {positional, "foo"}
          , {positional, "@bar"}
          ]).

read_cli(String) ->
    Args = string:tokens(String, " "),
    try lee_cli:read_to(test_model(), Args, lee_storage:new(lee_map_storage)) of
        Data ->
            {ok, Data}
    catch
        Err -> Err
    end.

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
    {ok, Data} = read_cli("@action_1 -fgs1 --long foo @action_2 foo bar"),
    %% List children
    ?assertMatch( [[action_1, ?lcl([1, "foo"])]]
                , lee_storage:list([action_1, ?children], Data)
                ),
    ?assertMatch( [[action_2, ?lcl(["foo"])]]
                , lee_storage:list([action_2, ?children], Data)
                ),
    ?assertMatch( {ok, true}
                , lee_storage:get([action_1, ?lcl([1, "foo"]), flag1], Data)
                ),
    ?assertMatch( {ok, "foo"}
                , lee_storage:get([action_1, ?lcl([1, "foo"]), long], Data)
                ),
    ?assertMatch( {ok, "foo"}
                , lee_storage:get([action_2, ?lcl(["foo"]), posn_1], Data)
                ),
    ?assertMatch( {ok, "bar"}
                , lee_storage:get([action_2, ?lcl(["foo"]), posn_2], Data)
                ).

rest1_test() ->
    {ok, Data} = read_cli("@action_3 foo quux 1"),
    ?assertMatch( {ok, [foo, quux, '1']}
                , lee_storage:get([action_3, ?lsngl, posn_n], Data)
                ).

rest2_test() ->
    {ok, Data} = read_cli("@action_4 1 2 foo bar"),
    ?assertMatch( {ok, "1"}
                , lee_storage:get([action_4, ?lcl(["1"]), posn_1], Data)
                ),
    ?assertMatch( {ok, "2"}
                , lee_storage:get([action_4, ?lcl(["1"]), posn_2], Data)
                ),
    ?assertMatch( {ok, [foo, bar]}
                , lee_storage:get([action_4, ?lcl(["1"]), posn_n], Data)
                ).

default_key_test() ->
    {ok, Data} = read_cli("@action_1 -s 42"),
    ?assertMatch( [[action_1, ?lcl([42, "default"])]]
                , lee_storage:list([action_1, ?children], Data)
                ).

no_key_test() ->
    ?assertMatch( {error, _}
                , read_cli("@action_1")
                ).

rest_empty_list_test() ->
    {ok, Data} = read_cli("@action_3"),
    ?assertMatch( {ok, []}
                , catch lee_storage:get([action_3, ?lsngl, posn_n], Data)
                ).
