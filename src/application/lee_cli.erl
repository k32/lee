-module(lee_cli).

%% TODO: This module is experimental; it's too convoluted and it needs
%% some serious refactoring

-export([ metamodel/0
        , read/2
        , read_to/3
        , doc_gen/2
        ]).

-ifdef(TEST).
-export([tokenize/2]).
-endif.

-include("lee.hrl").

-define(sigil, $@).

%% CLI command scope:
-record(sc,
        { name = global    :: string() | global
        , short = #{}      :: #{char() => lee:key()}
        , long  = #{}      :: #{string() => lee:key()}
        , positional = []  :: [{integer() | rest, lee:key()}]
        , parent = []      :: lee:key()
        }).

-type doc_config() :: #{prog_name := string()}.

-type token() :: {long, string(), string()}
               | {short, char(), string()}
               | {positional, string()}
               | {command, string()}
               | separator
               .

-spec metamodel() -> lee:module().
metamodel() ->
    #{metatype =>
          #{ cli_param =>
                 {[metatype, documented]
                 , #{ validate_mo => fun(_,_,_,_) -> ok end
                    , doc_chapter_title => "CLI Arguments"
                    , doc_gen => fun ?MODULE:doc_gen/2
                    }
                 }
           , cli_action =>
                 {[metatype]
                 , #{validate_mo => fun(_,_,_,_) -> ok end}
                 }
           , cli_positional =>
                 {[metatype]
                 , #{validate_mo => fun(_,_,_,_) -> ok end}
                 }
           }
     }.

%% @doc Read CLI arguments to a patch
%% @throws {error, string()}
-spec read(lee:model(), [string()]) -> lee:patch().
read(Model, Args0) ->
    Scopes = mk_index(Model),
    Tokens = tokenize(?sigil, Args0),
    case split_commands(Tokens) of
        [[{command, _} | _] | _] = Commands ->
            Global = [];
        [Global | Commands] ->
            ok;
        [] ->
            Global = [],
            Commands = []
    end,
    try
        Globals = parse_args(Model, maps:get(global, Scopes), Global),
        Acc0 = lee_lib:make_nested_patch(Model, [], Globals),
        lists:foldl( fun(Tokns, Acc) ->
                             parse_command(Model, Scopes, Tokns) ++ Acc
                     end
                   , Acc0
                   , Commands)
    catch
        Error = {error, _} -> throw(Error);
        Error -> throw({error, Error})
    end.

-spec read_to(lee:model(), [string()], lee_storage:data()) ->
                     lee_storage:data().
read_to(Model, Args, Data) ->
    Patch = read(Model, Args),
    lee_storage:patch(Data, Patch).

-spec tokenize(char(), [string()]) -> [token()].
tokenize(Sigil, L) ->
    Tokens = [I || I <- tokenize_(Sigil, L), I /= []],
    group_tokens(Tokens).

-spec doc_gen(lee:model(), doc_config()) -> lee_doc:doc().
doc_gen(Model, Config) ->
    [{global, Global}|Scopes] = lists:sort(maps:to_list(mk_index(Model))),
    GlobalDoc = [{section, make_scope_docs(Global, Model)}],
    ActionDocs =
        [{section, [{id, "cli-command-" ++ Name}]
         , [{title, [[?sigil|Name]]} | make_cli_action_docs(I, Model)]}
         || {Name, I} <- Scopes],
    GlobalDoc ++ ActionDocs.

%%====================================================================
%% Internal functions
%%====================================================================

-spec split_commands([token()]) -> [[token()]].
split_commands(Tokens) ->
    Pred = fun({command, _}) -> false;
              (_)            -> true
           end,
    lee_lib:splitr(Pred, Tokens).

tokenize_(_, []) ->
    [];
tokenize_(_, ["--"|Rest]) ->
    [separator | [{positional, I} || I <- Rest]];
tokenize_(Sigil, [[Sigil|Command] | Rest]) ->
    [{command, Command} | tokenize_(Sigil, Rest)];
tokenize_(Sigil, ["--" ++ Long|Rest]) ->
    [{long, Long, "true"} | tokenize_(Sigil, Rest)];
tokenize_(Sigil, ["-" ++ [S1|Shorts] | Rest]) ->
    {Flags, Arg0} = lists:splitwith( fun(A) -> A < $0 orelse A > $9 end
                                   , Shorts
                                   ),
    Arg = case Arg0 of
              [] -> [];
              _  -> [{positional, Arg0}]
          end,
    [{short, [I], "true"} || I <- [S1|Flags]] ++ Arg ++ tokenize_(Sigil, Rest);
tokenize_(Sigil, [A|Rest]) ->
    [{positional, A}|tokenize_(Sigil, Rest)].

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

parse_command(Model, Scopes, [{command, Cmd} | Rest]) ->
    case maps:get(Cmd, Scopes, undefined) of
        SC = #sc{parent = Parent} ->
            Patch = parse_args(Model, SC, Rest),
            lee_lib:make_nested_patch(Model, Parent, Patch);
        undefined ->
            ErrorMsg = lee_lib:format("Unknown CLI command ~s", [Cmd]),
            throw(ErrorMsg)
    end.

parse_args( Model
          , #sc{ name = Name
               , long = Long
               , short = Short
               , parent = Parent
               } = Scope
          , [{ArgType, Arg, Val} | Rest]
          ) when ArgType =:= long; ArgType =:= short ->
    {Dash, ArgMap} = case ArgType of
                         long  -> {"-", Long};
                         short -> {"", Short}
                     end,
    case maps:get(Arg, ArgMap, undefined) of
        undefined ->
            ErrorMsg = lee_lib:format( "Unexpected CLI argument -~s~s in context ~s"
                                     , [Dash, Arg, Name]
                                     ),
            throw(ErrorMsg);
        Key ->
            RelKey = make_relative(Key, Parent),
            case lee:from_string(Model, Key, Val) of
                {ok, Term} ->
                    maps:merge( #{RelKey => Term}
                              , parse_args(Model, Scope, Rest)
                              );
                _ ->
                    ErrorMsg = lee_lib:format( "Unable to parse term: ~p~nKey: ~p"
                                             , [Val, Key]
                                             ),
                    throw(ErrorMsg)
            end
    end;
parse_args( Model
          , #sc{ name = Name
               , positional = Specs
               , parent = Parent
               } = Scope0
          , Positionals
          ) ->
    case zip_positionals(Model, Parent, Specs, Positionals) of
        {error, underflow} ->
            throw(lee_lib:format( "Not enough CLI arguments in command ~s"
                                , [Name]
                                ));
        {error, overflow, Val} ->
            throw(lee_lib:format( "Unexpected positional CLI argument ~p in command ~s"
                                , [Val, Name]
                                ));
        Zipped ->
            Zipped
    end.

zip_positionals(Model, Parent, [{rest, Key}], Vals0) ->
    Vals = [I || {_, I} <- Vals0],
    case lee:from_strings(Model, Key, Vals) of
        {ok, Terms} ->
            RelKey = make_relative(Key, Parent),
            #{RelKey => Terms};
        Err = {error, _} ->
            throw(Err)
    end;
zip_positionals(Model, Parent, [{_Position, Key}|T1], [{positional, Val}|T2]) ->
    case lee:from_string(Model, Key, Val) of
        {ok, Term} ->
            RelKey = make_relative(Key, Parent),
            (zip_positionals(Model, Parent, T1, T2)) #{RelKey => Term};
        Err = {error, _} ->
            throw(Err)
    end;
zip_positionals(_, _, [], [{positional, Val}|_]) ->
    {error, overflow, Val};
zip_positionals(_, _, [_|_], []) ->
    {error, underflow};
zip_positionals(_, _, [], []) ->
    #{}.

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

add_param(Key, Attrs, SC0) ->
    #sc{ long = Long0
       , short = Short0
       } = SC0,
    Long = case Attrs of
               #{cli_operand := L} ->
                   Long0 #{L => Key};
               _ ->
                   Long0
           end,
    Short = case Attrs of
                #{cli_short := S} ->
                    Short0 #{S => Key};
                _ ->
                    Short0
            end,
    SC0#sc{ short = Short
          , long = Long
          }.

add_positional(Key, Attrs, SC0 = #sc{positional = Pos0}) ->
    %% Make key relative:
    Pos = maps:get(cli_arg_position, Attrs),
    SC0#sc{ positional = [{Pos, Key} | Pos0] }.

make_relative(Key, []) ->
    Key;
make_relative(Key0, Parent) ->
    [?children | Key] = Key0 -- Parent,
    Key.

make_cli_action_docs(Scope = #sc{parent = Parent}, Model) ->
    #mnode{metaparams = ParentAttrs} = lee_model:get(Parent, Model),
    Oneliner = maps:get(oneliner, ParentAttrs, ""),
    Doc = lee_doc:docbook(maps:get(doc, ParentAttrs, "")),
    Preamble = [{para, [Oneliner]}|Doc],
    Preamble ++ make_scope_docs(Scope, Model).

make_scope_docs(#sc{ short = Short
                   , long = Long
                   , positional = Positional
                   }, Model) ->
    LongDoc = [document_param("--" ++ L, Key, Model)
               || {L, Key} <- maps:to_list(Long)],
    ShortDoc = [document_param("-" ++ S, Key, Model)
                || {S, Key} <- maps:to_list(Short)],
    PositionalDocs =
        [document_param(lee_lib:format("Position: ~p", [P]), Key, Model)
         || {P, Key} <- Positional],
    LongDoc ++ ShortDoc ++ PositionalDocs.

document_param(Name, Key, Model) ->
    MNode = lee_model:get(Key, Model),
    lee_doc:refer_value(Key, cli_param, Name, MNode).
