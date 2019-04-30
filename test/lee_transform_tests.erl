-module(lee_transform_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").
-include_lib("lee/include/lee_types.hrl").

-lee_verify({url/0, is_url/0}).

-lee_ignore([ignored/0]).

-define(typedef(TN, Type, TypeVars),
        #mnode{ metatypes = [typedef]
              , metaparams = #{ type           => Type
                              , type_variables => TypeVars
                              , typename       => atom_to_list(?MODULE) ++ ":" ++ atom_to_list(TN)
                              }
              }).

-define(model(A),
        {ok, Model} = lee_model:compile( []
                                       , [lee:type_refl([?MODULE, ?FUNCTION_NAME], A)]
                                       )).

-define(getm(A),
        catch lee_model:get([?MODULE, ?FUNCTION_NAME, A], Model)).

%% -----------------------------------------------------------------------------

-type mybool() :: boolean().

boolean_refl_test() ->
    ?model([mybool/0]),
    ?assertEqual( ?typedef(mybool, boolean(), [])
                , ?getm({mybool, 0})
                ).

%% -----------------------------------------------------------------------------

-type myterm1() :: term().

-type myterm2() :: any().

term_refl_test() ->
    ?model([myterm1/0, myterm2/0]),
    ?assertEqual( ?typedef(myterm1, term(), [])
                , ?getm({myterm1, 0})
                ),
    ?assertEqual( ?typedef(myterm2, term(), [])
                , ?getm({myterm2, 0})
                ).

%% -----------------------------------------------------------------------------

-type my_int() :: non_neg_integer().

-type my_byte() :: 0..255.

integer_refl_test() ->
    ?model([my_int/0, my_byte/0]),
    ?assertEqual( ?typedef(my_int, non_neg_integer(), [])
                , ?getm({my_int, 0})
                ),
    ?assertEqual( ?typedef(my_byte, range(0, 255), [])
                , ?getm({my_byte, 0})
                ).

%% -----------------------------------------------------------------------------

-type list_of_bools() :: [boolean()].

-type non_empty_list_of_bools() :: [boolean(), ...].

-type mylist0() :: list().

-type strings() :: list(string()).

list_refl_test() ->
    ?model([list_of_bools/0, non_empty_list_of_bools/0, mylist0/0, strings/0]),
    ?assertEqual( ?typedef(list_of_bools, list(boolean()), [])
                , ?getm({list_of_bools, 0})
                ),
    ?assertEqual( ?typedef(non_empty_list_of_bools, nonempty_list(boolean()), [])
                , ?getm({non_empty_list_of_bools, 0})
                ),
    ?assertEqual( ?typedef(mylist0, list(term()), [])
                , ?getm({mylist0, 0})
                ),
    ?assertEqual( ?typedef(strings, list(string()), [])
                , ?getm({strings, 0})
                ).

%% -----------------------------------------------------------------------------

-type foo_atom() :: foo.

atom_refl_test() ->
    ?model([foo_atom/0]),
    ?assertEqual( #type{id = [?MODULE, ?FUNCTION_NAME, {foo_atom, 0}]}
                , foo_atom()
                ),
    ?assertEqual( ?typedef(foo_atom, foo, [])
                , ?getm({foo_atom, 0})
                ).

%% -----------------------------------------------------------------------------

-type foobarbaz() :: foo | bar | baz.

union_refl_test() ->
    ?model([foobarbaz/0]),
    ?assertEqual( ?typedef(foobarbaz, union([foo, bar, baz]), [])
                , ?getm({foobarbaz, 0})
                ).

%% -----------------------------------------------------------------------------

-type mytuple() :: {float(), float(), xxx}.

tuple_refl_test() ->
    ?model([mytuple/0]),
    ?assertEqual( ?typedef(mytuple, tuple([float(), float(), xxx]), [])
                , ?getm({mytuple, 0})
                ).

%% -----------------------------------------------------------------------------

-type simple(A) :: A.

%% Recursive type is fine too:
-type stupid_list(OwO) :: {cons, OwO, stupid_list(OwO)} | nil.

higher_kind_refl_test() ->
    ?model([simple/1, stupid_list/1]),
    ?assertEqual( ?typedef(simple, {var, 'A'}, ['A'])
                , ?getm({simple, 1})
                ),
    ?assertMatch( #type{ id = [?MODULE, ?FUNCTION_NAME, {stupid_list, 1}]
                       , parameters = [xxxx]
                       }
                , stupid_list(xxxx)
                ),
    ?assertEqual( ?typedef( stupid_list
                          , union( tuple([cons, {var, 'OwO'}, stupid_list({var, 'OwO'})])
                                 , nil
                                 )
                          , ['OwO']
                          )
                , ?getm({stupid_list, 1})
                ).

%% -----------------------------------------------------------------------------

-type mymap1() :: map().

map_0_refl_test() ->
    ?model([mymap1/0]),
    ?assertEqual( ?typedef(mymap1, map(), [])
                , ?getm({mymap1, 0})
                ).

-type mymap2(A, B) :: #{A => B}.

map_assoc_refl_test() ->
    ?model([mymap2/2]),
    ?assertEqual( ?typedef(mymap2, map({var, 'A'}, {var, 'B'}), ['A', 'B'])
                , ?getm({mymap1, 0})
                ).

-type mymap3() :: #{foo := integer()}.

-type mixmap(A, B) :: #{ foo := integer()
                       , bar := atom()
                       , K => V
                       }.

%% -----------------------------------------------------------------------------

-type remote_types() :: lee_types:list(lee_types:boolean()).

remote_type_refl_test() ->
    ?model([remote_types/0]),
    ?assertEqual( ?typedef(remote_types, list(boolean()), [])
                , ?getm({remote_types, 0})
                ).

%% -----------------------------------------------------------------------------

%% TODO: Test Lee attributes

-type ignored() :: string().

-type url() :: string().

%% -----------------------------------------------------------------------------

exports_test() ->
    Exports = ?MODULE:module_info(exports),
    ?assertMatch( []
                , [ {mybool, 0}
                  , {strings, 0}
                  , {myterm1, 0}
                  , {foobarbaz, 0}
                  , {simple, 1}
                  , {stupid_list, 1}
                  ] -- Exports
                ).
