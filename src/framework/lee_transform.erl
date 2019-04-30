%% @hidden
-module(lee_transform).

-export([parse_transform/2]).

%% TODO: Source code locations are... approximate
%% TODO: Error handling is inexistent
%% TODO: Reflect maps

-type local_tref() :: {Name :: atom(), Arity :: integer()}.

-type ast() :: term().

-type ast_var() :: atom().

-record(s,
        { module          :: atom()
        , local_types     :: #{local_tref() => {ast(), [ast()]}}
        , reflected_types :: #{local_tref() => {Namespace :: lee:key(), AST :: ast()}}
        , custom_verif    :: #{local_tref() => ast()}
        , line            :: integer() | undefined
        , namespace       :: lee:key() | undefined
        }).

%% Macro convention: uppercase macros are for matching, lower-case
%% for generation (they contain Line as a free variable)

-define(INT(Line, Val),
        {integer, Line, Val}).

-define(INT(Val), ?INT(_, Val)).

-define(int(Val),
        {integer, Line, Val}).

-define(ATOM(Line, Atom),
        {atom, Line, Atom}).

-define(ATOM(Atom), ?ATOM(_, Atom)).

-define(atom(Atom),
        {atom, Line, Atom}).

-define(LCALL(Line, Name, Args),
        {call, Line, ?ATOM(Name), Args}).

-define(tuple(Elems),
        {tuple, Line, Elems}).

-define(cons(A, B),
        {cons, Line, A, B}).

-define(nil,
        {nil, Line}).

-define(map(Elems),
        {map, Line, Elems}).

-define(ass(Key, Value),
        {map_field_assoc, Line, Key, Value}).

-define(lcall(Name, Args),
        {call, Line, ?atom(Name), Args}).

-define(RCALL(Line, Module, Function, Args),
        {call, Line
        , {remote, _, ?ATOM(Module), ?ATOM(Function)}
        , Args
        }).

-define(rcall(Module, Function, Args),
        {call, Line
        , {remote, Line, ?atom(Module), ?atom(Function)}
        , Args
        }).

-define(typedef(Name, Arity, AST),
        ?ass( ?tuple([?atom(Name), ?int(Arity)])
            , AST
            )).

-define(typeref(Namespace, Name, Arity, Attrs, Params),
        ?tuple([ ?atom(type)
               , mk_lee_key(Line, Namespace, Name, Arity)
               , Attrs
               , mk_literal_list(Line, Params)
               ])).

-define(typename(Module, Name, Arity),
        {string, Line, Module ++ ":" ++ Name}).

-define(LTYPE_REF(Name, Arity),
        {op, _, '/', ?ATOM(Name), {integer, _, Arity}}).

parse_transform(Forms0, _Options) ->
    Ignored = ignored(Forms0),
    CustomVerif = custom_verify(Forms0),
    Typedefs0 = find_local_typedefs(Forms0),
    Typedefs = maps:without(Ignored, Typedefs0),
    Module = hd([M || {attribute, _, module, M} <- Forms0]),
    State0 = #s{ local_types = Typedefs
               , custom_verif = CustomVerif
               , reflected_types = #{}
               , module = Module
               },
    io:format(user, "AST: ~p~n", [Forms0]),
    {Forms1, State} = forms(Forms0, State0),
    ReflectedTypes = maps:to_list(State#s.reflected_types),
    %% export_type and export definitions are the same.
    Exports = [make_export(I) || I <- ReflectedTypes],
    Forms2 = add_attributes(Forms1, [ {export, Exports}
                                    , {export_type, Exports}
                                    ]),
    %% Append type reflections to the module definition:
    Forms2 ++ [make_reflection_function(I) || I <- ReflectedTypes].

forms(?RCALL(Line, lee, type_refl, [Namespace0, Types0]), State0) ->
    %% Type reflection is triggered here
    Namespace = literal_list(fun(?ATOM(A)) -> A end, Namespace0),
    State1 = State0#s{ line      = Line
                     , namespace = Namespace
                     },
    Types1 = literal_list( fun(?LTYPE_REF(Name, Arity)) ->
                                   {Name, Arity}
                           end
                         , Types0
                         ),
    State2 = lists:foldl(fun refl_type/2, State1, Types1),
    #s{reflected_types = RTypes} = State2,
    %io:format(user, "State: ~p~n", [State2]),
    TypesAST = [?typedef(Name, Arity, AST)
                || {{Name, Arity}, {Namespace1, AST}} <- maps:to_list(RTypes)
                 , Namespace1 =:= Namespace
               ],
    AST = ?rcall(lee, namespace, [Namespace0, ?map(TypesAST)]),
    State = State2,
    {AST, State};
%% The remaining clauses just make up cheesy AST traversal:
forms(L, State0) when is_list(L) ->
    lists:mapfoldl(fun forms/2, State0, L);
forms(T, State0) when is_tuple(T) ->
    L = tuple_to_list(T),
    {AST, State} = forms(L, State0),
    {list_to_tuple(AST), State};
forms(AST, State) ->
    {AST, State}.

%% Reflect a local type
-spec refl_type(local_tref(), #s{}) -> #s{}.
refl_type(Type, State0) ->
    #s{ local_types = LocalTypes
      , line = Line
      , namespace = Namespace
      } = State0,
    {AST0, Params} = maps:get(Type, LocalTypes),
    {AST, State1} = do_refl_type(State0, AST0),
    #s{ reflected_types = M0
      , module = Module
      } = State1,
    Val = {Namespace, mk_type_alias(Module, Line, Type, AST, Params)},
    State1#s{reflected_types = M0 #{Type => Val}}.

%% Traverse AST of a type definition and produce a reflection
-spec do_refl_type(#s{}, ast()) -> {ast(), #s{}}.
do_refl_type(State, {var, Line, Var}) ->
    AST = ?tuple([?atom(var), ?atom(Var)]),
    {AST, State};
do_refl_type(State, Int = ?INT(_)) ->
    {Int, State};
do_refl_type(State, Atom = ?ATOM(_)) ->
    {Atom, State};
do_refl_type(State, {type, Line, map, Args0}) -> %% Maps are special
    Args = case Args0 of
               any -> [];
               _   -> Args0
           end,
    CallSpec = [?atom(lee_types), ?atom(map), Args],
    do_refl_type(State, {remote_type, Line, CallSpec});
do_refl_type(State0, {Qualifier, Line, Name, Args0})
  when Qualifier =:= type; Qualifier =:= user_type ->
    %% Another local type was refered... We need to reflect it too:
    State1 = maybe_refl_type({Name, length(Args0)}, State0),
    %% Type arguments are nested AST, traverse them
    {Args, State} = traverse_type_args(State1, Name, Args0),
    {?lcall(Name, Args), State};
do_refl_type(State0, {remote_type, Line, CallSpec}) ->
    [Module, Name, Args0] = CallSpec,
    {Args, State} = traverse_type_args(State0, Name, Args0),
    AST = {call, Line
          , {remote, Line, Module, Name}
          , Args
          },
    {AST, State}.

ignored(Forms) ->
    DeepDefs = [Defs || {attribute, _, lee_ignore, Defs} <- Forms],
    lists:usort(lists:append(DeepDefs)).

custom_verify(Forms) ->
    Defs = [Def || {attribute, _, lee_verify, Def} <- Forms],
    maps:from_list(Defs).

%% Collect all type definitions in the module
find_local_typedefs(Forms) ->
    ExtractTypeVarName = fun({var, _Line, Name}) when is_atom(Name) ->
                                 Name
                         end,
    maps:from_list([begin
                        Params = lists:map(ExtractTypeVarName, Params0),
                        {{Name, length(Params)}, {AST, Params}}
                    end
                    || { attribute
                       , _Line
                       , type
                       , {Name, AST, Params0}
                       } <- Forms
                   ]).

%% Produce a Lee mnode denoting a reflected typedef
-spec mk_type_alias(atom(), integer(), local_tref(), ast(), [ast_var()]) ->
                           ast().
mk_type_alias(Module, Line, {Name, Arity}, AST, Params) ->
    Variables = mk_literal_list( Line
                               , fun(I) -> ?ATOM(Line, I) end
                               , Params
                               ),
    ?tuple([ ?cons(?atom(typedef), ?nil)
           , ?map([ ?ass(?atom(type), AST)
                  , ?ass(?atom(type_variables), Variables)
                  , ?ass(?atom(typename), ?typename( atom_to_list(Module)
                                                   , atom_to_list(Name)
                                                   , Arity
                                                   ))
                  ])
           , ?map([])
           ]).

%% Produce a Lee key
mk_lee_key(Line, Namespace, Name, Arity) ->
    mk_literal_list( Line
                   , fun(A) when is_atom(A) ->
                             ?atom(A);
                        ({A, B}) ->
                             ?tuple([ ?atom(A)
                                    , ?int(B)
                                    ])
                     end
                   , Namespace ++ [{Name, Arity}]
                   ).

%% Check if the type has been already reflected, and reflect it
%% otherwise
-spec maybe_refl_type(local_tref(), #s{}) -> #s{}.
maybe_refl_type( TRef
               , State0 = #s{ reflected_types = RT
                            , local_types = LT
                            }
               ) ->
    case {maps:is_key(TRef, LT), maps:is_key(TRef, RT)} of
        {true, false} ->
            %% Dirty hack to avoid infinite loop:
            State1 = State0#s{ reflected_types =
                                   RT #{TRef => in_progress}
                             },
            refl_type(TRef, State1);
        _ ->
            State0
    end.

%% Make a function defenition that is a reflection of the type in the
%% term universe
make_reflection_function({{Name, Arity}, {Namespace, _}}) ->
    Vars = [{var, 0, list_to_atom("V" ++ integer_to_list(I))}
            || I <- lists:seq(0, Arity - 1)],
    Line = 0,
    Attrs = ?map([]), %% TODO: do something with attrs?
    {function, Line, Name, Arity
    , [{clause, Line, Vars, []
       , [?typeref( Namespace
                  , Name
                  , Arity
                  , Attrs
                  , Vars
                  )]
       }]
    }.

%% Insert attributes after `module'
add_attributes(Forms0, Attributes0) ->
    Pred = fun({attribute, _, module, _}) -> false;
              (_) -> true
           end,
    {Before, [Module|Rest]} = lists:splitwith(Pred, Forms0),
    Attributes = [{attribute, 0, K, V} || {K, V} <- Attributes0],
    Before ++ [Module|Attributes] ++ Rest.

%% Make an export declaration
make_export({FA = {_Name, _Arity}, _}) ->
    FA.

-spec traverse_type_args(#s{}, atom(), [ast()]) -> {ast(), #s{}}.
traverse_type_args(State0, Name, Args0) ->
    #s{line = Line} = State0,
    {Args1, State} = lists:mapfoldl( fun(I, S) -> do_refl_type(S, I) end
                                   , State0
                                   , Args0
                                   ),
    Args = case lists:member(Name, [tuple, union, map]) of
               true ->
                   [mk_literal_list(Line, Args1)];
               false ->
                   Args1
           end,
    {Args, State}.

literal_list(_, {nil, _}) ->
    [];
literal_list(Fun, {cons, _, Val, Tail}) ->
    [Fun(Val) | literal_list(Fun, Tail)].

mk_literal_list(Line, _, []) ->
    {nil, Line};
mk_literal_list(Line, Fun, [Val|Tail]) ->
    {cons, Line, Fun(Val), mk_literal_list(Line, Fun, Tail)}.

mk_literal_list(Line, List) ->
    mk_literal_list(Line, fun(A) -> A end, List).
