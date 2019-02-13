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

        , map/2  % Import~
        , validate_map/3

        , exact_map/1
        , validate_exact_map/3
        , print_exact_map/2

        , number/0  % Import~

        , print_type/2
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
             , map/2
             , number/0
             ]).

-type map(A, B) :: map(A, B). %% TODO Wtf?

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
%% API functions
%%====================================================================
-spec union(lee:type(), lee:type()) -> lee:type().
union(A, B) ->
    ?te([A, B]).

-spec union([lee:type()]) -> lee:type().
union([A, B|T]) ->
    lists:foldl( fun union/2
               , union(A, B)
               , T
               ).

-spec validate_union( lee:module()
                    , lee:type()
                    , term()
                    ) -> lee:validate_result().
validate_union(Model, #type{parameters = [A, B]}, Term) ->
    case lee:validate_term(Model, A, Term) of
        {ok, _} ->
            {ok, []};
        {error, _, _} ->
            case lee:validate_term(Model, B, Term) of
                {ok, _} ->
                    {ok, []};
                {error, _, _} ->
                    Msg = format( "Expected ~s | ~s, got ~p"
                                , [ print_type(Model, A)
                                  , print_type(Model, B)
                                  , Term
                                  ]
                                ),
                    {error, [Msg], []}
            end
    end.

-spec print_union(lee:module(), lee:type()) ->
                         iolist().
print_union(Model, #type{parameters = [A, B]}) ->
    [print_type_(Model, A), " | ", print_type_(Model, B)].

-spec boolean() -> lee:type().
boolean() ->
    union(true, false).

-spec integer() -> lee:type().
integer() ->
    range(neg_infinity, infinity).

-spec validate_integer( lee:module()
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
            Err = format("Expected ~s, got ~p", [print_type(Model, Self), Term]),
            {error, [Err], []}
    end.

-spec print_integer(lee:module(), lee:type()) ->
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

-spec non_neg_integer() -> lee:type().
non_neg_integer() ->
    range(0, infinity).

-spec range( integer() | neg_infinity
           , integer() | infinity
           ) -> lee:type().
range(A, B) ->
    ?te( integer
       , 0
       , #{range => {A, B}}
       , []
       ).

-spec string() -> lee:type().
string() ->
    list(range(0, 16#10ffff)).

-spec float() -> lee:type().
float() ->
    ?te([]).

-spec validate_float( lee:module()
                    , lee:type()
                    , term()
                    ) -> lee:validate_result().
validate_float(_, _, Term) ->
    if is_float(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected float(), got ~p", [Term])], []}
    end.

-spec atom() -> lee:type().
atom() ->
    ?te([]).

-spec validate_atom( lee:module()
                   , lee:type()
                   , term()
                   ) -> lee:validate_result().
validate_atom(_, _, Term) ->
    if is_atom(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected atom(), got ~p", [Term])], []}
    end.

-spec binary() -> lee:type().
binary() ->
    ?te([]).

-spec validate_binary( lee:module()
                     , lee:type()
                     , term()
                     ) -> lee:validate_result().
validate_binary(_, _, Term) ->
    if is_binary(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected binary(), got ~p", [Term])], []}
    end.

-spec tuple() -> lee:type().
tuple() ->
    ?te([]).

-spec validate_any_tuple( lee:module()
                        , lee:type()
                        , term()
                        ) -> lee:validate_result().
validate_any_tuple(_, _, Term) ->
    if is_tuple(Term) ->
            {ok, []};
       true ->
            {error, [format("Expected tuple(), got ~p", [Term])], []}
    end.

-spec tuple([lee:type()]) -> lee:type().
tuple(Params) ->
    ?te(Params).

-spec validate_tuple( lee:module()
                    , lee:type()
                    , term()
                    ) -> lee:validate_result().
validate_tuple(Model, Self = #type{parameters = Params}, Term) ->
    try
        is_tuple(Term)
            orelse throw(badtuple),
        List = tuple_to_list(Term),
        length(Params) =:= length(List)
            orelse throw(badtuple),
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
            {error, [format( "Expected ~s, got ~p"
                           , [print_type(Model, Self), Term]
                           )], []}
    end.

-spec print_tuple(lee:module(), lee:type()) ->
                             iolist().
print_tuple(Model, #type{parameters = Params}) ->
    PS = [print_type_(Model, I) || I <- Params],
    ["{", lists:join(",", PS), "}"].

-spec term() -> lee:type().
term() ->
    ?te([]).

-spec any() -> lee:type().
any() ->
    term().

-spec validate_term( lee:module()
                   , lee:type()
                   , term()
                   ) -> lee:validate_result().
validate_term(_, _, _) ->
    {ok, []}.

-spec list() -> lee:type().
list() ->
    list(term()).

-spec list(lee:type()) -> lee:type().
list(Type) ->
    ?te(#{non_empty => false}, [Type]).


-spec nonempty_list(lee:type()) -> lee:type().
nonempty_list(Type) ->
    ?te(list, 1, #{non_empty => true}, [Type]).

-spec validate_list( lee:module()
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

-spec print_list(lee:module(), lee:type()) ->
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

-spec map(lee:type(), lee:type()) -> lee:type().
map(K, V) ->
    ?te([K, V]).

-spec validate_map( lee:module()
                  , lee:type()
                  , term()
                  ) -> lee:validate_result().
validate_map( Model
            , Self = #type{parameters = [KeyT, ValueT]}
            , Term
            ) ->
    try
        is_map(Term) orelse throw(badmap),
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

%% "Literal" map
-spec exact_map(#{term() := lee:type()}) -> lee:type().
exact_map(Spec) ->
    ?te( #{ exact_map_spec => Spec
          , mandatory_map_fields => maps:keys(Spec)
          }
       , []
       ).

-spec validate_exact_map( lee:module()
                        , lee:type()
                        , term()
                        ) -> lee:validate_result().
validate_exact_map( Model
                  , Self = #type{refinement = Attr}
                  , Term
                  ) ->
    #{ exact_map_spec := Spec
     , mandatory_map_fields := Mandatory0
     } = Attr,
    try
        is_map(Term) orelse throw(badmap),
        Mandatory = ordsets:from_list(Mandatory0),
        maps:map( fun(K, Type) ->
                          case {Term, ordsets:is_element(K, Mandatory)} of
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
                  end
                , Spec
                ),
        {ok, []}
    catch
        {badval, Key, Val, ValType} ->
            {error, [format( "Expected ~s in key ~p of ~s, got ~p"
                           , [ print_type(Model, ValType)
                             , Key
                             , print_type(Model, Self)
                             , Val
                             ]
                           )], []};
        {badkey, Key} ->
            {error, [format( "Missing key(s) ~p in ~p, expected ~s"
                           , [ Key
                             , Term
                             , print_type(Model, Self)
                             ]
                           )], []};
        badmap ->
            {error, [format( "Expected ~s, got ~p"
                           , [ print_type(Model, Self)
                             , Term
                             ]
                           )], []}
    end.

-spec print_exact_map(lee:module(), lee:type()) ->
                             iolist().
print_exact_map(Model, #type{refinement = #{exact_map_spec := Spec}}) ->
    %% FIXME: Wrong!
    io_lib:format( "~w"
                 , [maps:map( fun(_, V) ->
                                      print_type(Model, V)
                              end
                            , Spec
                            )]
                 ).

-spec number() -> lee:type().
number() ->
    union(integer(), float()).

-spec print_type_(lee:module(), lee:type()) -> iolist().
print_type_(_, {var, Var}) ->
    io_lib:format("_~w", [Var]);
print_type_(_, Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
print_type_(_, Integer) when is_integer(Integer) ->
    integer_to_list(Integer);
print_type_(Model, Type) ->
    #type{id = TypeId, parameters = TypeParams} = Type,
    #mnode{ metatypes = Meta
          , metaparams = Attrs
          } = lee_model:get(TypeId, Model),
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
    end ++
    case lists:member(typedef, Meta) of
        true ->
            [" :: TODO "];
        false ->
            []
    end.

-spec print_type(lee:module(), lee:type()) -> string().
print_type(Model, Type) ->
    lists:flatten(print_type_(Model, Type)).

%%====================================================================
%% Internal functions
%%====================================================================

format(Fmt, Attrs) ->
    lists:flatten(io_lib:format(Fmt, Attrs)).

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
