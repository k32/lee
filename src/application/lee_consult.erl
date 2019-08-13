-module(lee_consult).

-export([ metamodel/0
        , read/2
        , read/3
        , read_to/3
        , read_to/4
        , doc_chapter_title/2
        , doc_gen/2
        , meta_validate/4
        ]).

-export_type([filter/0, doc_config/0]).

-include("lee.hrl").

-define(consult, consult).

-type filter() :: [lee:metatype()] | all.

-type doc_config() :: #{ filter      := filter()
                       , config_name := string()
                       }.

-spec metamodel() -> lee:module().
metamodel() ->
    #{ metatype =>
           #{ ?consult => {[metatype, documented]
                          , #{ doc_chapter_title => fun ?MODULE:doc_chapter_title/2
                             , doc_gen => fun ?MODULE:doc_gen/2
                             , meta_validate => fun ?MODULE:meta_validate/4
                             }
                          }
            }}.

-spec meta_validate(lee:model(), _, lee:key(), #mnode{}) ->
                            lee_lib:check_result().
meta_validate(_, _, Key, #mnode{metaparams = Attrs}) ->
    case Attrs of
        #{file_key := _} -> {[], []};
        _                -> {["missing `file_key' attribute"], []}
    end.

%% @doc Parse file into a `lee_storage'
%% @throws {error, string()}
-spec read_to(lee:model(), file:filename(), lee_storage:data()) ->
                     lee_storage:data().
read_to(Model, Filename, Data) ->
    read_to(Model, Filename, all, Data).

%% @doc Parse file into a `lee_storage'
%% @throws {error, string()}
-spec read_to(lee:model(), file:filename(), filter(), lee_storage:data()) ->
                     lee_storage:data().
read_to(Model, Filename, Filter, Data) ->
    Patch = read(Model, Filename, Filter),
    lee_storage:patch(Data, Patch).

%% @doc Parse file into a patch
%% @throws {error, string()}
-spec read(lee:model(), file:filename()) -> lee:patch().
read(Model, Filename) ->
    read(Model, Filename, all).

%% @doc Parse file into a patch
%% @throws {error, string()}
-spec read(lee:model(), file:filename(), filter()) -> lee:patch().
read(Model, Filename, Filter) ->
    Predicate = predicate(Filter),
    Keys = lee_model:get_metatype_index(?consult, Model),
    Terms0 = case file:consult(Filename) of
                 {ok, T0} ->
                     T0;
                 {error, Reason0} ->
                     Reason = lee_lib:format( "Reading ~s failed: ~p"
                                            , [Filename, Reason0]
                                            ),
                     throw({error, Reason})
             end,
    case Terms0 of
         [Terms] when is_map(Terms) ->
             ok;
         _ ->
             Terms = try maps:from_list(Terms0)
                     catch
                         _:_ ->
                             throw({error, Filename ++ " should be a proplist or a map"})
                     end
    end,
    lists:foldl( fun(Key, Acc) ->
                         read_val(Model, Predicate, Terms, Key, Acc)
                 end
               , []
               , Keys).

read_val(Model, Predicate, Terms, Key, Acc) ->
    #mnode{metatypes = MT, metaparams = Attrs} = lee_model:get(Key, Model),
    Valid = Predicate(MT),
    FileKey = ?m_attr(?consult, file_key, Attrs),
    case Terms of
        #{FileKey := Val} when Valid ->
            [{set, Key, Val} | Acc];
        #{} ->
            Acc
    end.

-spec doc_gen(lee:model(), doc_config() | undefined) -> lee:doc().
doc_gen(Model, undefined) ->
    doc_gen(Model, default_doc_config());
doc_gen(Model, Config) ->
    #{filter := Filter} = Config,
    Predicate = predicate(Filter),
    Intro = "<para>
Configuration file is an Erlang term that can be in either proplist:
</para>
<programlisting language=\"erlang\">
<![CDATA[
{key1, Val1}.
{key2, Val2}.
...
]]>
</programlisting>
<para>
or map form:
</para>
<programlisting language=\"erlang\">
<![CDATA[
#{ key1 => Val1
 , key2 => Val2
 }.
]]>
</programlisting>
<para><emphasis>Valid keys:</emphasis></para>",
    Keys = lee_model:get_metatype_index(?consult, Model),
    Fun = fun(Key) ->
                  MNode = lee_model:get(Key, Model),
                  case Predicate(MNode#mnode.metatypes) of
                      true ->
                          {true, format_doc(Config, Key, MNode)};
                      false ->
                          false
                  end
          end,
    lee_doc:docbook(Intro) ++ lists:filtermap(Fun, Keys).

-spec doc_chapter_title(lee:model(), doc_config() | undefined) -> string().
doc_chapter_title(Model, undefined) ->
    doc_chapter_title(Model, default_doc_config());
doc_chapter_title(_Model, Config) ->
    #{config_name := ConfigName } = Config,
    "Configuration file: " ++ ConfigName.

default_doc_config() ->
    #{ filter => all
     , config_name => "configuration.eterm"
     }.

predicate(Filter) ->
  case Filter of
      all ->
          fun(_) -> true end;
      _ ->
          OrdSet = ordsets:from_list(Filter),
          fun(MetaTypes) ->
                  ordsets:intersection(OrdSet, MetaTypes) =/= []
          end
  end.

format_doc(_Config, Key, MNode = #mnode{metaparams = Attrs}) ->
    FileKey = ?m_attr(?consult, file_key, Attrs),
    lee_doc:refer_value(Key, ?consult, atom_to_list(FileKey), MNode).
