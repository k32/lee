-module(lee_consult).

-export([ metamodel/0
        , read/2
        , read_to/3
        ]).

-include("lee.hrl").

-define(consult, consult).

-spec metamodel() -> lee:module().
metamodel() ->
    #{ metatype => #{ ?consult => {[metatype]
                                  , #{}
                                  }
                    }}.

-spec read_to(lee:model(), file:filename(), lee:data()) ->
                     {ok, lee:data()}
                   | {error, term()}.
read_to(Model, Filename, Data) ->
    case read(Model, Filename) of
        {ok, Patch} ->
            {ok, lee_storage:put(Data, Patch)};
        Error ->
            Error
    end.

-spec read(lee:model(), file:filename()) ->
                  {ok, [{lee:key(), term()}]}
                | {error, term()}.
read(Model, Filename) ->
    Keys = lee_model:get_metatype_index(?consult, Model),
    try
        Terms0 = case file:consult(Filename) of
                     {ok, T0} ->
                         T0;
                     {error, Reason} ->
                         throw(Reason)
                 end,
        case Terms0 of
             [Terms] when is_map(Terms) ->
                 ok;
             _ ->
                 Terms = try maps:from_list(Terms0)
                         catch
                             _:_ -> throw(badmap)
                         end
        end,
        {ok, lists:foldl( fun(Key, Acc) ->
                                  read_val(Model, Terms, Key, Acc)
                          end
                        , []
                        , Keys)}
    catch
        Error -> {error, Error}
    end.


read_val(Model, Terms, Key, Acc) ->
    #mnode{metaparams = Attrs} = lee_model:get(Key, Model),
    FileKey = maps:get(file_key, Attrs),
    case Terms of
        #{FileKey := Val} ->
            [{Key, Val} | Acc];
        #{} ->
            Acc
    end.
