-module(lee_transform_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").
-include_lib("lee/include/lee_types.hrl").

-define(typedef(TN, Type, TypeVars),
        #mnode{ metatypes = [typedef]
              , metaparams = #{ type           => Type
                              , type_variables => TypeVars
                              , typename       => atom_to_list(?MODULE) ++ ":" ++ atom_to_list(TN)
                              }
              }).

-lee_ignore([ignored/0]).
-type ignored() :: string().

-type foo_atom() :: foo.

-type simple(A) :: A.

-type simple() :: boolean().

-type strings() :: list(string()).

-type foobar() :: foo | bar | baz.

-type my_tuple() :: {float(), float(), xxx}.

-type list_of_bools() :: [boolean()].

-type non_empty_list_of_bools() :: [boolean(), ...].

-type my_int() :: non_neg_integer().

-type my_byte() :: 0..255.

-type remote_types() :: lee_types:list(lee_types:boolean()).

%% Recursive type is fine too:
-type stupid_list(A) :: {cons, A, stupid_list(A)} | nil.

-lee_verify({url/0, is_url/0}).
-type url() :: string().

halpme(A) ->
    A.

type_refl_test() ->
    Model0 = lee:type_refl([foo, bar], [ simple/0
                                       , simple/1
                                       , foo_atom/0
                                       , strings/0
                                       , foobar/0
                                       , my_tuple/0
                                       , list_of_bools/0
                                       , non_empty_list_of_bools/0
                                       , my_int/0
                                       , my_byte/0
                                       , remote_types/0
                                       , stupid_list/1
                                       ]),
    {ok, Model} = lee_model:compile([], [Model0]),
    ?assertMatch( #type{id = [foo, bar, {foo_atom, 0}]}
                , foo_atom()
                ),
    ?assertEqual( ?typedef(foo_atom, foo, [])
                , catch lee_model:get([foo, bar, {foo_atom, 0}], Model)
                ),
    ?assertEqual( ?typedef(simple, {var, 0}, [0])
                , catch lee_model:get([foo, bar, {simple, 1}], Model)
                ),
    ?assertEqual( ?typedef(simple, boolean(), [])
                , catch lee_model:get([foo, bar, {simple, 0}], Model)
                ),
    ?assertEqual( ?typedef(strings, list(string()), [])
                , catch lee_model:get([foo, bar, {strings, 0}], Model)
                ),
    ?assertEqual( ?typedef(foobar, union([foo, bar, baz]), [])
                , catch lee_model:get([foo, bar, {foobar, 0}], Model)
                ),
    ?assertEqual( ?typedef(my_tuple, tuple([float(), float(), xxx]), [])
                , catch lee_model:get([foo, bar, {my_tuple, 0}], Model)
                ),
    ?assertEqual( ?typedef(list_of_bools, list(boolean()), [])
                , catch lee_model:get([foo, bar, {list_of_bools, 0}], Model)
                ),
    ?assertEqual( ?typedef(non_empty_list_of_bools, nonempty_list(boolean()), [])
                , catch lee_model:get([foo, bar, {non_empty_list_of_bools, 0}], Model)
                ),
    ?assertEqual( ?typedef(my_int, non_neg_integer(), [])
                , catch lee_model:get([foo, bar, {my_int, 0}], Model)
                ),
    ?assertEqual( ?typedef(my_byte, range(0, 255), [])
                , catch lee_model:get([foo, bar, {my_byte, 0}], Model)
                ),
    ?assertEqual( ?typedef(remote_types, list(boolean()), [])
                , catch lee_model:get([foo, bar, {remote_types, 0}], Model)
                ),
    ?assertMatch( #type{id = [foo, bar, {stupid_list, 1}], parameters = [xxxx]}
                , stupid_list(xxxx)
                ),
    ?assertEqual( ?typedef( stupid_list
                          , union( tuple([cons, {var, 0}, stupid_list({var, 0})])
                                 , nil
                                 )
                          , [0]
                          )
                , catch lee_model:get([foo, bar, {stupid_list, 1}], Model)
                ),
    ok.
