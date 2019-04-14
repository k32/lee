-module(lee_cli).

%% TODO: This module is experimental; it's too convoluted and it needs
%% a serious refactoring

-export([ metamodel/0
        , read/2
        , read_to/3
        ]).

-ifdef(TEST).
-export([tokenize/1, separate_args/1]).
-endif.

-include("lee.hrl").

%% CLI command scope:
-record(sc,
        { name             :: string() | undefined
        , short = #{}      :: #{char() => {lee:key(), lee:type()}}
        , long  = #{}      :: #{string() => {lee:key(), lee:type()}}
        , positional = []  :: [{integer() | rest, lee:key(), lee:type()}]
        , parent = []      :: lee:key()
        }).

-type token() :: {long, string(), string()}
               | {short, char(), string()}
               | {positional, string()}
               | separator
               .

-spec metamodel() -> lee:module().
metamodel() ->
    #{metatype => #{ cli_param =>
                         {[metatype]
                         , #{validate_mo => fun(_,_,_,_) -> ok end}
                         }
                   , cli_action =>
                         {[metatype]
                         , #{validate_mo => fun(_,_,_,_) -> ok end}
                         }
                   }}.

-spec read(lee:model(), [string()]) ->
                  {ok, lee:patch()}
                | {error, Error :: string()}.
read(Model, Args0) ->
    Scopes = mk_index(Model),
    Args = separate_args(Args0),
    case [tokenize(I) || I <- Args] of
        [] ->
            Global = [],
            Commands = [];
        [Global|Commands] ->
            ok
    end,
    try
        Globals = parse_args(maps:get(global, Scopes), Global),
        Acc0 = lee_lib:make_nested_patch(Model, [], Globals),
        Patch = lists:foldl( fun(Tokens, Acc) ->
                                     parse_command(Model, Scopes, Tokens) ++ Acc
                             end
                           , Acc0
                           , Commands),
        {ok, Patch}
    catch
        Error = {error, _} -> Error;
        Error -> {error, Error}
    end.

-spec read_to(lee:model(), [string()], lee:data()) ->
                     {ok, lee:data()}
                   | {error, string()}.
read_to(Model, Args, Data) ->
    case read(Model, Args) of
        {ok, Patch} ->
            {ok, lee_storage:patch(Data, Patch)};
        Err ->
            Err
    end.

-spec tokenize([string()]) -> [token()].
tokenize(L) ->
    Tokens = [I||I <- tokenize_(L), I /= []],
    group_tokens(Tokens).

%%====================================================================
%% Internal functions
%%====================================================================

-spec separate_args([string()]) -> [[string()]].
separate_args(Args) ->
    Pred = fun(Arg) -> lists:last(Arg) =/= $, end,
    case lists:splitwith(Pred, Args) of
        {[], []} ->
            [];
        {A1, []} ->
            [A1];
        {A1, [","|Rest]} ->
            [A1 | separate_args(Rest)];
        {A10, [L|Rest]} ->
            A1 = A10 ++ [lists:droplast(L)],
            [A1|separate_args(Rest)]
    end.

tokenize_([]) ->
    [];
tokenize_(["--"|Rest]) ->
    [separator | [{positional, I} || I <- Rest]];
tokenize_(["--" ++ Long|Rest]) ->
    [{long, Long, "true"} | tokenize_(Rest)];
tokenize_(["-" ++ [S1|Shorts] | Rest]) ->
    {Flags, Arg0} = lists:splitwith( fun(A) -> A < $0 orelse A > $9 end
                                   , Shorts
                                   ),
    Arg = case Arg0 of
              [] -> [];
              _  -> [{positional, Arg0}]
          end,
    [{short, [I], "true"} || I <- [S1|Flags]] ++ Arg ++ tokenize_(Rest);
tokenize_([A|Rest]) ->
    [{positional, A}|tokenize_(Rest)].

group_tokens([]) ->
    [];
group_tokens([separator|Rest]) ->
    Rest;
group_tokens([{short, S, _}, {positional, A} | Rest]) ->
    [{short, S, A} | group_tokens(Rest)];
group_tokens([{long, L, _}, {positional, A} | Rest]) ->
    [{long, L, A} | group_tokens(Rest)];
group_tokens([A|Rest]) ->
    [A|group_tokens(Rest)].

parse_command(Model, Scopes, [{positional, Cmd} | Rest]) ->
    case maps:get(Cmd, Scopes, undefined) of
        SC = #sc{parent = Parent} ->
            Patch = parse_args(SC, Rest),
            lee_lib:make_nested_patch(Model, Parent, Patch);
        undefined ->
            ErrorMsg = lee_lib:format("Unknown command ~s", [Cmd]),
            throw(ErrorMsg)
    end;
parse_command(_Model, _Scopes, [_Wrong|_]) ->
    ErrorMsg = lee_lib:format("Expected a command after ,", []),
    throw(ErrorMsg).

parse_args(_Scope, []) ->
    #{};
parse_args( #sc{ name = Name
               , long = Long
               , short = Short
               } = Scope
          , [{ArgType, Arg, Val}|Rest]
          ) when ArgType =:= long; ArgType =:= short ->
    {Dash, ArgMap} = case ArgType of
                         long  -> {"-", Long};
                         short -> {"", Short}
                     end,
    case maps:get(Arg, ArgMap, undefined) of
        undefined ->
            ErrorMsg = lee_lib:format( "Unexpected argument -~s~s in context ~s"
                                     , [Dash, Arg, Name]
                                     ),
            throw(ErrorMsg);
        {Key, Type} ->
            maps:merge( #{Key => lee_lib:string_to_term(Type, Val)}
                      , parse_args(Scope, Rest)
                      )
    end;
parse_args( #sc{ name = Name
               , positional = Pos0
               } = Scope0
          , [{positional, Val}|Rest]
          ) ->
    case Pos0 of
        [] ->
            ErrorMsg = lee_lib:format( "Unexpected positional argument ~p in context ~s"
                                     , [Val, Name]
                                     ),
            throw(ErrorMsg);
        [{rest, Key, Type}] ->
            error(not_implemented); %% TODO
        [{Position, Key, Type} | PRest] ->
            Scope = Scope0#sc{positional = PRest},
            maps:merge( #{Key => lee_lib:string_to_term(Type, Val)}
                      , parse_args(Scope, Rest)
                      )
    end.

mk_index(Model) ->
    Scopes0 = lee_model:fold( fun mk_index/4
                            , #{global => #sc{}}
                            , global
                            , Model
                            ),
    maps:map( fun(_, S0 = #sc{positional = P0}) ->
                      P1 = lists:sort(P0),
                      S0#sc{positional = P1}
              end
            , Scopes0
            ).

mk_index(Key, #mnode{metatypes = Meta, metaparams = Attrs}, Acc, Scope) ->
    case { lists:member(cli_param, Meta)
         , lists:member(cli_positional, Meta)
         , lists:member(cli_action, Meta)
         }
    of
        {false, false, false} -> %% Ignored
            {Acc, Scope};
        {true, false, false} -> %% CLI parameter
            SC = add_param(Key, Attrs, maps:get(Scope, Acc)),
            {Acc #{Scope => SC}, Scope};
        {false, true, false} -> %% Positional parameter
            SC = add_positional(Key, Attrs, maps:get(Scope, Acc)),
            {Acc #{Scope => SC}, Scope};
        {false, false, true} -> %% CLI action
            NewScope = maps:get(cli_operand, Attrs),
            SC = #sc{ name = NewScope
                    , parent = Key
                    },
            {Acc #{NewScope => SC}, NewScope}
    end.

add_param(Key0, Attrs, SC0) ->
    #sc{ long = Long0
       , short = Short0
       } = SC0,
    Type = maps:get(type, Attrs),
    %% Make key relative:
    Key = make_relative(Key0, SC0),
    Long = case Attrs of
               #{cli_operand := L} ->
                   Long0 #{L => {Key, Type}};
               _ ->
                   Long0
           end,
    Short = case Attrs of
                #{cli_short := S} ->
                    Short0 #{S => {Key, Type}};
                _ ->
                    Short0
            end,
    SC0#sc{ short = Short
          , long = Long
          }.

add_positional(Key0, Attrs, SC0 = #sc{positional = Pos0}) ->
    %% Make key relative:
    Key = make_relative(Key0, SC0),
    Pos = maps:get(cli_arg_position, Attrs),
    Type = maps:get(type, Attrs),
    SC0#sc{ positional = [{Pos, Key, Type} | Pos0] }.

make_relative(Key, #sc{parent = []}) ->
    Key;
make_relative(Key0, #sc{parent = Parent}) ->
    [?children | Key] = Key0 -- Parent,
    Key.
