-module(lee_types_tests).

-include_lib("eunit/include/eunit.hrl").

-include_lib("lee/include/lee.hrl").

-include_lib("lee/include/lee_types.hrl").

-define(valid(Type, Term),
        ?assertMatch( {ok, _}
                    , lee:validate_term(Model, Type, Term)
                    )).

-define(invalid(Type, Term),
        ?assertMatch( {error, _, _}
                    , lee:validate_term(Model, Type, Term)
                    )).

model() ->
    {ok, Model} = lee_model:compile([], [lee:base_model()]),
    Model.

validate_concrete_atom_test() ->
    Model = model(),
    ?valid(true, true),
    ?valid(false, false),
    ?invalid(foo, 1),
    ?invalid(foo, []),
    ?invalid(foo, bar).

validate_bool_test() ->
    Model = model(),
    ?valid(boolean(), true),
    ?valid(boolean(), false),
    ?invalid(boolean(), 1),
    ?invalid(boolean(), {}),
    ?invalid(boolean(), foo).

integer_test() ->
    Model = model(),
    ?valid(integer(), -1),
    ?valid(integer(), 1000),
    ?valid(integer(), 0),
    ?invalid(integer(), 1.0),
    ?invalid(integer(), foo),
    ?valid(range(-1, 1), 1),
    ?valid(range(-1, 1), -1),
    ?invalid(range(-1, 1), -2),
    ?invalid(range(-1, 1), 2),
    ?valid(non_neg_integer(), 0),
    ?valid(non_neg_integer(), 1),
    ?invalid(non_neg_integer(), -1).

union_test() ->
    Model = model(),
    ?valid(number(), 1),
    ?valid(number(), 1.1),
    ?invalid(number(), []).

term_test() ->
    Model = model(),
    ?valid(term(), 1),
    ?valid(term(), 1.1),
    ?valid(term(), {1, 2, [], foo}),
    ?valid(term(), [foo, 1, [] | gg]).

atom_test() ->
    Model = model(),
    ?valid(atom(), foo),
    ?valid(atom(), bar),
    ?invalid(atom(), {}),
    ?invalid(atom(), 1).

list_test() ->
    Model = model(),
    ?valid(list(), []),
    ?valid(nonempty_list(integer()), [1, 2, 3]),
    ?invalid(nonempty_list(term()), []),
    UnionL = list(union(boolean(), integer())),
    ?valid(UnionL, [true, false, 1, 10, -1]),
    ?invalid(UnionL, [true, false, 1, bar]),
    ?invalid(list(), [foo, bar | baz]).

string_test() ->
    Model = model(),
    ?valid(string(), "this is a string"),
    ?valid(string(), "(✿ ┛O‿‿O)┛彡♥   ¯\_(ツ)_/¯"),
    ?invalid(string(), "foo" ++ [bar, {}] ++ "baz"),
    ?invalid(string(), [-1, 2]).

tuple_test() ->
    Model = model(),
    ?valid(tuple(), {}),
    ?valid(tuple(), {foo, 1, []}),
    ?invalid(tuple(), 1),
    ?invalid(tuple(), []),

    ?valid(tuple([]), {}),
    ?invalid(tuple([]), {1}),

    T = tuple([atom(), integer()]),
    ?valid(T, {foo, 1}),
    ?valid(T, {false, -1}),
    ?invalid(T, {false, -1, 5}),
    ?invalid(T, {false}),
    ?invalid(T, {false, "1"}).

binary_test() ->
    Model = model(),
    ?valid(binary(), <<>>),
    ?valid(binary(), <<"foo">>),
    ?invalid(binary(), "fooo"),
    ?invalid(binary(), 1).

map_test() ->
    Model = model(),
    T = map(atom(), string()),
    ?valid(T, #{}),
    ?valid(T, #{foo => "bar"}),
    ?invalid(T, #{ foo => "bar"
                 , "bar" => foo
                 , baz => "quux"
                 }),
    ?invalid(T, #{ foo => 1
                 , bar => "bar"
                 }).

exact_map_test() ->
    Model = model(),
    T = exact_map(#{ foo => boolean()
                   , bar => string()
                   }),
    ?valid(T, #{foo => true, bar => "bar"}),
    ?valid(T, #{foo => false, bar => []}),
    ?invalid(T, #{foo => foo, bar => "bar"}),
    ?invalid(T, #{foo => true}),
    ?invalid(T, #{foo => true, bar => 1}).

typedef_test() ->
    StupidList =
        fun(A) ->
                #type{id = [stupid_list], parameters = [A]}
        end,
    Model0 = #{stupid_list =>
                   {[typedef]
                   , #{ type => union( tuple([{var, '$a'}, StupidList({var, '$a'})])
                                     , nil
                                     )
                      , type_variables => ['$a']
                      , typename => "stupid_list"
                      }
                   , #{}
                   }
              },
    {ok, Model} = lee_model:compile([], [Model0, lee:base_model()]),
    T = StupidList(union(integer(), foo)),
    ?valid(T, nil),
    ?valid(T, {1, nil}),
    ?valid(T, {foo, {1, nil}}),
    ?valid(T, {42, {foo, {1, nil}}}),
    ?invalid(T, bar),
    ?invalid(T, 1.1),
    ?invalid(T, {1, foo}),
    ?invalid(T, {foo, {42, {1.1, nil}}}).

typedef_2_test() ->
    Model0 = #{foo => {[typedef]
                      , #{ type => {var, '1'}
                         , type_variables => ['1']
                         , typename => "foo"
                         }
                      , #{}
                      }},
    {ok, Model} = lee_model:compile([], [Model0, lee:base_model()]),
    T = fun(A) -> #type{id = [foo], parameters = [A]} end,
    ?valid(T(boolean()), true),
    ?valid(T(boolean()), false),
    ?invalid(T(boolean()), 1).
