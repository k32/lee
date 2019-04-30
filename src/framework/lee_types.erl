%% @doc This module defines reflections of base Erlang types
-module(lee_types).

%% API exports
-export([ union/2  % Import~
        , union/1  % Import~
        , boolean/0  % Import~
        , validate_union/3
        , print_union/2

        , term/0  % Import~
        , any/0  % Import~
        , validate_term/3

        , integer/0  % Import~
        , non_neg_integer/0
        , range/2  % Import~
        , validate_integer/3
        , print_integer/2

        , float/0  % Import~
        , validate_float/3

        , atom/0  % Import~
        , atom_from_string/3
        , validate_atom/3

        , binary/0  % Import~
        , validate_binary/3

        , list/0  % Import~
        , list/1  % Import~
        , nonempty_list/1  % Import~
        , string/0  % Import~
        , validate_list/3
        , print_list/2

        , tuple/0  % Import~
        , validate_any_tuple/3

        , tuple/1  % Import~
        , validate_tuple/3
        , print_tuple/2

        , map/0  % Import~
        , map/2  % Import~
        , map/1  % Import~
        , validate_map/3

        , number/0  % Import~

        , print_type/2
        , is_typedef/1
        ]).

%%====================================================================
%% Types
%%====================================================================

-export_type([ boolean/0
             , term/0
             , any/0
             , integer/0
             , non_neg_integer/0
             , float/0
             , atom/0
             , binary/0
             , list/1
             , list/0
             , nonempty_list/1
             , string/0
             , tuple/0
             , map/0
             , map/2
             , number/0
             ]).

-export_type([ map_field_spec/0
             ]).

%%====================================================================
%% Macros
%%====================================================================

-include("lee_internal.hrl").

-define(te(Name, Arity, Attrs, Parameters),
        #type
        { id = [lee, base_types, {Name, Arity}]
        , refinement = Attrs
        , parameters = Parameters
        }).
-define(te(Attrs, Parameters),
        ?te(?FUNCTION_NAME, ?FUNCTION_ARITY, Attrs, Parameters)).
-define(te(Parameters),
        ?te(?FUNCTION_NAME, ?FUNCTION_ARITY, #{}, Parameters)).

%%====================================================================
%% Types (regular, not reflected)
%%====================================================================

%% This wrapper is needed, as there is no builtin `map/2' type:
-type map(K, V) :: #{K => V}.

-type map_field_spec() :: {optional, lee:type(), lee:type()}
                        | {optional_term, term(), lee:type()}
                        | {mandatory, term(), lee:type()}.

%%====================================================================
%% API functions
%%====================================================================

%% @doc Reflection of `A | B' type.
%%
%% Example:
%% ```union(boolean(), atom())'''
-spec union(lee:type(), lee:type()) -> lee:type().
union(A, B) ->
    ?te([A, B]).

%% @doc Reflection of `A | B | ...' type
%%
%% Example:
%% ```union([boolean(), atom(), tuple()])'''
-spec union([lee:type()]) -> lee:type().
union([A, B | T]) ->
    lists:foldl( fun union/2
               , union(A, B)
               , T
               ).

%% @private
-spec validate_union( lee:model()
                    , lee:type()
                    , term()
                    ) -> lee:validate_result().
validate_union(Model, Self = #type{parameters = [A, B]}, Term) ->
    case lee:validate_term(Model, A, Term) of
        {ok, _} ->
            {ok, []};
        {error, _, _} ->
            case lee:validate_term(Model, B, Term) of
                {ok, _} ->
                    {ok, []};
                {error, _, _} ->
                    Msg = format( "Expected: ~s~nGot: ~p"
                                , [ print_type(Model, Self)
                                  , Term
                                  ]
                                ),
                    {error, [Msg], []}
            end
    end.

%% @private
-spec print_union(lee:model(), lee:type()) ->
                         iolist().
print_union(Model, #type{parameters = [A, B]}) ->
    [print_type_(Model, A), " | ", print_type_(Model, B)].

%% @doc Reflection of `boolean()' type
-spec boolean() -> lee:type().
boolean() ->
    union(true, false).

%% @doc Reflection of `integer()' type
-spec integer() -> lee:type().
integer() ->
    range(neg_infinity, infinity).

%% @private
-spec validate_integer( lee:model()
                      , lee:type()
                      , term()
                      ) -> lee:validate_result().
validate_integer(Model, Self = #type{refinement = #{range := {A, B}}}, Term) ->
    try
        is_integer(Term) orelse throw(badint),
        A =:= neg_infinity orelse Term >= A orelse throw(badint),
        B =:= infinity     orelse Term =< B orelse throw(badint),
        {ok, []}
    catch
        badint ->
            Err = format("Expected: ~s~nGot: ~p", [print_type(Model, Self), Term]),
            {error, [Err], []}
    end.

%% @private
-spec print_integer(lee:model(), lee:type()) ->
                         iolist().
print_integer(_Model, #type{refinement = #{range := Range}}) ->
    case Range of
        {neg_infinity, infinity} ->
            "integer()";
        {0, infinity} ->
            "non_neg_integer()";
        {0, 255} ->
            "byte()";
        {0, 16#10ffff} ->
            "char()";
        {A, B} ->
            [integer_to_list(A), "..", integer_to_list(B)]
    end.

%% @doc Reflection of `non_neg_integer()' type
-spec non_neg_integer() -> lee:type().
non_neg_integer() ->
    range(0, infinity).

%% @doc Reflection of integer range `N..M' type
-spec range( integer() | neg_infinity
           , integer() | infinity
           ) -> lee:type().
range(A, B) ->
    ?te( integer
       , 0
       , #{range => {A, B}}
       , []
       ).

%% @doc Reflection of `string()' type
-spec string() -> lee:type().
string() ->
    list(range(0, 16#10ffff)).

%% @doc Reflection of `float()' type
-spec float() -> lee:type().
float() ->
    ?te([]).

%% @private
-spec validate_float( lee:model()
                    , lee:type()
                    , term()
                    ) -> lee:validate_result().
validate_float(_, _, Term) ->
    if is_float(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected float(), got ~p", [Term])], []}
    end.

%% @doc Reflection of `atom()' type
-spec atom() -> lee:type().
atom() ->
    ?te([]).

%% @private Validate that value is an atom
-spec validate_atom( lee:model()
                   , lee:type()
                   , term()
                   ) -> lee:validate_result().
validate_atom(_, _, Term) ->
    if is_atom(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected atom(), got ~p", [Term])], []}
    end.

%% @private
-spec atom_from_string( lee:model()
                      , lee:key()
                      , string()
                      ) -> lee:validate_result().
atom_from_string(_, _, Str) ->
    {ok, list_to_atom(Str)}.

%% @doc Reflection of `binary()' type
-spec binary() -> lee:type().
binary() ->
    ?te([]).

%% @private
-spec validate_binary( lee:model()
                     , lee:type()
                     , term()
                     ) -> lee:validate_result().
validate_binary(_, _, Term) ->
    if is_binary(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected binary(), got ~p", [Term])], []}
    end.

%% @doc Reflection of `tuple()' type
-spec tuple() -> lee:type().
tuple() ->
    ?te([]).

%% @private
-spec validate_any_tuple( lee:model()
                        , lee:type()
                        , term()
                        ) -> lee:validate_result().
validate_any_tuple(_, _, Term) ->
    if is_tuple(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected tuple(), got ~p", [Term])], []}
    end.

%% @doc Reflection of `{A, B, ...}'
%%
%% Example:
%% ```tuple([boolean(), atom()])'''
-spec tuple([lee:type()]) -> lee:type().
tuple(Params) ->
    ?te(Params).

%% @private
-spec validate_tuple( lee:model()
                    , lee:type()
                    , term()
                    ) -> lee:validate_result().
validate_tuple(Model, Self = #type{parameters = Params}, Term) ->
    try
        is_tuple(Term) orelse throw(badtuple),
        List = tuple_to_list(Term),
        length(Params) =:= length(List) orelse throw(badtuple),
        lists:zipwith( fun(Type, Val) ->
                               %% TODO: make better error message
                               case lee:validate_term(Model, Type, Val) of
                                   {ok, _} -> ok;
                                   _       -> throw(badtuple)
                               end
                       end
                     , Params
                     , List
                     ),
        {ok, []}
    catch
        badtuple ->
            {error, [format( "Expected: ~s~nGot ~p"
                           , [print_type(Model, Self), Term]
                           )], []}
    end.

%% @private
-spec print_tuple(lee:model(), lee:type()) ->
                             iolist().
print_tuple(Model, #type{parameters = Params}) ->
    PS = [print_type_(Model, I) || I <- Params],
    ["{", lists:join(",", PS), "}"].

%% @doc Reflection of `term()' type
-spec term() -> lee:type().
term() ->
    ?te([]).

%% @doc Reflection of `any()' type
-spec any() -> lee:type().
any() ->
    term().

%% @private
-spec validate_term( lee:model()
                   , lee:type()
                   , term()
                   ) -> lee:validate_result().
validate_term(_, _, _) ->
    {ok, []}.

%% @doc Reflection of `list()' type
-spec list() -> lee:type().
list() ->
    list(term()).

%% @doc Reflection of `[A]' type
-spec list(lee:type()) -> lee:type().
list(Type) ->
    ?te(#{non_empty => false}, [Type]).


%% @doc Reflection of `[A..]' type
-spec nonempty_list(lee:type()) -> lee:type().
nonempty_list(Type) ->
    ?te(list, 1, #{non_empty => true}, [Type]).

%% @private
-spec validate_list( lee:model()
                   , lee:type()
                   , term()
                   ) -> lee:validate_result().
validate_list( Model
             , Self = #type{ refinement = #{non_empty := NonEmpty}
                           , parameters = [Param]
                           }
             , Term
             ) ->
    try
        is_list(Term) orelse throw(badlist),
        not(NonEmpty) orelse length(Term) > 0 orelse throw(badlist),
        validate_list_(Model, Param, Term),
        {ok, []}
    catch
        {badelem, Elem} ->
            {error, [format( "Expected ~s, got ~p in ~s"
                           , [ print_type(Model, Param)
                             , Elem
                             , print_type(Model, Self)
                             ]
                           )], []};
        badlist ->
            {error, [format( "Expected ~s, got ~p"
                           , [ print_type(Model, Self)
                             , Term
                             ]
                           )], []}
    end.

%% @private
-spec print_list(lee:model(), lee:type()) ->
                             iolist().
print_list(Model, #type{ refinement = #{non_empty := NonEmpty}
                       , parameters = [Par]
                       }) ->
    case NonEmpty of
        true ->
            Prefix = "nonempty_";
        false ->
            Prefix = ""
    end,
    [Prefix, "list(", print_type_(Model, Par), ")"].

%% @doc Reflection of `map()' type
-spec map() -> lee:type().
map() ->
    map([{optional, term(), term()}]).

%% @doc Reflection of `#{K => V}' type
-spec map(lee:type(), lee:type()) -> lee:type().
map(K, V) ->
    map([{optional, K, V}]).

-spec map(Params, [field_spec()]) -> lee:type().
map(Params, FieldSpecs) ->
    %% Keys of exact fields are traeated as literal terms:
    ExactFields = [{Key, Type} || {T, Key, Type} <- FieldSpecs,
                                  T =:= optional_term orelse T =:= mandatory],
    MandatoryFields = [K || {mandatory, K, _} <- FieldSpecs],
    %% Other keys are treated as types, requiring an ugly and slow O(N*M) validation
    Optional = [{KeyType, ValType} || {optional, KeyType, ValType} <- FieldSpecs],
    ?te(#{}, Params).


    try
        is_map(Term) orelse throw(badmap),
        %% First validate exact fields, it's faster.

    catch
        {badval, Key, Val, ValType} ->
            {error, [format( "Expected ~s in key ~p of ~s~nGot: ~p"
                           , [ print_type(Model, ValType)
                             , Key
                             , print_type(Model, Self)
                             , Val
                             ]
                           )], []};`
        {badkey, Key} ->
            {error, [format( "Missing key(s) ~p in ~p, expected ~s"
                           , [ Key
                             , Term
                             , print_type(Model, Self)
                             ]
                           )], []};
        badmap ->
            {error, [format( "Expected ~s~nGot: ~p"
                           , [ print_type(Model, Self)
                             , Term
                             ]
                           )], []}
    end.



%% @private
-spec validate_map( lee:model()
                  , lee:type()
                  , term()
                  ) -> lee:validate_result().
validate_map( Model
            , Self = #type{parameters = [KeyT, ValueT]}
            , Term
            ) ->
    try

        [begin
             case lee:validate_term(Model, KeyT, K) of
                 {ok, _} -> ok;
                 _       -> throw(badmap)
             end,
             case lee:validate_term(Model, ValueT, V) of
                 {ok, _} -> ok;
                 _       -> throw({badval, K, V})
             end
         end
         || {K, V} <- maps:to_list(Term)],
        {ok, []}
    catch
        {badval, Key, Val} ->
            {error, [format( "Expected ~s, but key ~p got value ~p instead"
                           , [ print_type(Model, Self)
                             , Key
                             , Val
                             ]
                           )], []};
        badmap ->
            {error, [format( "Expected ~s, got ~p"
                           , [ print_type(Model, Self)
                             , Term
                             ]
                           )], []}
    end.

%% @private
-spec validate_exact_fields( lee:model()
                           , lee:type()
                           , map()
                           ) -> lee:validate_result().
validate_exact_fields( Model
                     , Self = #type{refinement = Attr}
                     , Term
                     ) ->
    #{ exact_map_spec := Spec
     , mandatory_map_fields := Mandatory0
     } = Attr,
    Mandatory = ordsets:from_list(Mandatory0),
    [case {Term, ordsets:is_element(K, Mandatory)} of
         {#{K := Val}, _} ->
             case lee:validate_term(Model, Type, Val) of
                 {ok, []} -> ok;
                 _        -> throw({badval, K, Val, Type})
             end;
         {_, true} ->
             throw({badkey, K});
         {_, false} ->
             ok
     end
     || {K, Type} <- Spec],
    ok.

%% @private
-spec print_exact_map(lee:model(), lee:type()) ->
                             iolist().
print_exact_map(Model, #type{refinement = #{exact_map_spec := Spec}}) ->
    %% TODO FIXME: Wrong!
    io_lib:format( "~w"
                 , [maps:map( fun(_, V) ->
                                      print_type_(Model, V)
                              end
                            , Spec
                            )]
                 ).

%% @doc Reflection of `number()' type
-spec number() -> lee:type().
number() ->
    union(integer(), float()).

%% @private
-spec print_type_(lee:model(), lee:type()) -> iolist().
print_type_(_, {var, Var}) ->
    io_lib:format("~s", [Var]);
print_type_(_, Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
print_type_(_, Integer) when is_integer(Integer) ->
    integer_to_list(Integer);
print_type_(Model, Type) ->
    #type{id = TypeId, parameters = TypeParams} = Type,
    #mnode{metaparams = Attrs} = lee_model:get(TypeId, Model),
    ?m_valid( type,
       case Attrs of
           #{print := Print} ->
               Print(Model, Type);
           #{typename := TypeName} ->
               StrParams = [print_type_(Model, I)
                            || I <- TypeParams
                           ],
               io_lib:format("~s(~s)", [ TypeName
                                       , lists:join($,, StrParams)
                                       ])
       end).

%% @doc Print type
-spec print_type(lee:model(), lee:type()) -> string().
print_type(Model, Type) ->
    TermType = print_type_(Model, Type),
    TypeDefL = collect_typedefs(Model, Type, #{}),
    TD = case maps:size(TypeDefL) of
             0 ->
                 [];
             _ ->
                 Typedefs = [print_typedef(Model, TypeId, Attrs)
                             || {TypeId, Attrs} <- maps:to_list(TypeDefL)],
                 [" when\n" | Typedefs]
         end,
    lists:flatten([TermType|TD]).

%% @private
-spec collect_typedefs( lee:model()
                      , lee:type()
                      , Acc
                      ) -> Acc when Acc :: #{lee:model_key() => map()}.
collect_typedefs(Model, #type{id = TypeId, parameters = Params}, Acc0) ->
    MNode = lee_model:get(TypeId, Model),
    Acc1 = case {map_sets:is_element(TypeId, Acc0), is_typedef(MNode)} of
               {false, true} ->
                   Attrs = MNode#mnode.metaparams,
                   TypeParams = ?m_attr(typedef, type_variables, Attrs),
                   BaseType = ?m_attr(typedef, type, Attrs),
                   Acc2 = Acc0 #{TypeId => Attrs},
                   Acc3 = collect_typedefs(Model, BaseType, Acc2),
                   lists:foldl( fun(I, Acc) ->
                                        collect_typedefs(Model, I, Acc)
                                end
                              , Acc3
                              , TypeParams);
               _ ->
                   Acc0
           end,
    lists:foldl( fun(I, Acc) ->
                         collect_typedefs(Model, I, Acc)
                 end
               , Acc1
               , Params);
collect_typedefs(_, T, Acc) ->
    Acc.

%% @private
-spec print_typedef(lee:model(), lee:key(), map()) -> iolist().
print_typedef(Model, _TypeId, Attrs) ->
    Name = ?m_attr(typedef, typename, Attrs),
    Vals = [atom_to_list(I) || I <- ?m_attr(typedef, type_variables, Attrs)],
    Type = print_type_(Model, ?m_attr(typedef, type, Attrs)),
    Vars = lists:join($,, Vals),
    io_lib:format("  ~s(~s) :: ~s.~n", [Name, Vars, Type]).

%% @private
-spec is_typedef(#mnode{}) -> boolean().
is_typedef(#mnode{metatypes = Meta}) ->
    lists:member(typedef, Meta).

%%====================================================================
%% Internal functions
%%====================================================================

%% @private
format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).

%% @private
validate_list_(_, _, []) ->
    ok;
validate_list_(Model, Param, [Term|Tail]) ->
    is_list(Tail) orelse throw(badlist),
    case lee:validate_term(Model, Param, Term) of
        {ok, _} ->
            validate_list_(Model, Param, Tail);
        _ ->
            throw({badelem, Term})
    end.
